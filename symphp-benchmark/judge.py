#!/usr/bin/env python3
"""The concrete judge both tools are scored by.

usage: judge.py setup <app>
       judge.py replay <app> <requests.json> --out <replay.json> [--reset request|batch|none]
                                                                 [--coverage xdebug]
       judge.py exec-lines <app>

Replays a request against the UNINSTRUMENTED application, under a stock PHP
7.4 php-cgi (`~/symphp-eval/hotcrp/bin/php-cgi-trace`, the same build the
SymPHP replays use, minus `ENABLE_SYMPHP`) and a real MySQL. A request is
`{"script", "GET", "POST", "COOKIE"}`.

A request FAULTS a sink when, during it:

* MySQL reports a statement error (`performance_schema`'s statement history,
  `MYSQL_ERRNO <> 0`, filtered to `CURRENT_SCHEMA = <the app's database>`) --
  the fault Witcher and SymPHP escalate to a segfault; or
* `/bin/sh` (dash) reports a syntax error on the request's stderr.

TWO DATABASE MODES.

* An app with a `db` block in apps.json (the real apps) gets its OWN judge server,
  `judge-<app>-db` (appdb.py), a clone loaded from a snapshot of the installed
  database -- never the installed one. It listens on the port the app's own
  config names, inside its own network namespace, and php-cgi runs in a
  long-lived runner container (`judge-<app>-php`) that joins that namespace, so
  the unmodified config reaches the clone. The app source is mounted READ-ONLY
  there. php-cgi-trace is a host binary; it runs under the host's own loader
  and libraries, mounted read-only.
* An app without one (Witcher-Test, the oracle fixtures) keeps the original
  setup: host php-cgi against `ace-judge-mysql` on 127.0.0.1:3307, its errors
  now filtered to the app's `schema`.

One replay at a time per DB server (a lock file): the statement history is
server-wide. `--reset request` (the default for a `db` app) restores the
snapshot and the session directory before EACH request, so a finding is judged
on the state it was found in, not on what earlier replays left behind.

COVERAGE. `lines` is the php-cgi-trace trace of the same replay (the existing
field; Witcher-Test's scores read it). `--coverage xdebug` adds `xdebug_lines`
from a SECOND pass: one reset, then every request in order under the
ace-judge-php74 image's php-cgi with Xdebug 3. Xdebug 3 has no ini-only way to
collect line coverage (`xdebug.mode=coverage` only enables the collector;
something must call `xdebug_start_code_coverage()`), so that pass uses a
coverage-only `auto_prepend_file` that lives OUTSIDE the docroot
(`judge_cov_prepend.php`): it starts the collector and, at shutdown, writes the
executed lines to a file. It changes no app behaviour, and it is never used on
the fault replays.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse

import appdb

HERE = pathlib.Path(__file__).resolve().parent
APPS = json.loads((HERE / "apps.json").read_text())
CGI = pathlib.Path.home() / "symphp-eval/hotcrp/bin/php-cgi-trace"
CGI_REAL = CGI.resolve()
MYSQL = ["docker", "exec", "-i", "ace-judge-mysql", "mysql", "-uroot", "-N", "-B"]
SHELL_FAULT = re.compile(rb"sh: \d+: Syntax error[^\n]*")
PHP74 = "ace-judge-php74"
HOSTLIB = "/lib/x86_64-linux-gnu"


def mysql(sql: str) -> str:
    return subprocess.run(MYSQL, input=sql, capture_output=True, text=True, check=True).stdout


def src_of(app: str) -> pathlib.Path:
    return (HERE / APPS[app]["src"]).resolve()


def work_of(app: str) -> pathlib.Path:
    w = HERE / "build" / "judge-work" / app
    w.mkdir(parents=True, exist_ok=True)
    return w


def runner(app: str) -> str:
    return f"judge-{app}-php"


def ensure_runner(app: str) -> str:
    """The long-lived php-cgi container in the judge DB's network namespace."""
    db = appdb.ensure(app, "judge")
    name = runner(app)
    p = subprocess.run(["docker", "inspect", "-f", "{{.State.Running}}", name], capture_output=True, text=True)
    if p.returncode == 0 and p.stdout.strip() == "true":
        return name
    if p.returncode == 0:
        subprocess.run(["docker", "rm", "-f", name], capture_output=True)
    src, work = src_of(app), work_of(app)
    subprocess.run(["docker", "run", "-d", "--name", name, *appdb.LOG_OPTS, "--network", f"container:{db}",
                    "-u", f"{os.getuid()}:{os.getgid()}",
                    "-v", f"{HOSTLIB}:/hostlib:ro", "-v", f"{CGI_REAL}:{CGI_REAL}:ro",
                    "-v", f"{src}:{src}:ro", "-v", f"{work}:{work}", "-v", f"{HERE}:{HERE}:ro",
                    "-e", "XDEBUG_MODE=off", PHP74, "sleep", "infinity"], check=True, capture_output=True)
    return name


def setup(app: str) -> None:
    if APPS[app].get("db"):
        ensure_runner(app)
        appdb.restore(app, "judge")
        print(appdb.sql(appdb.container(app, "judge"),
                        f"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='{APPS[app]['db']['database']}';").strip(),
              "tables")
        return
    for _ in range(60):
        if subprocess.run([*MYSQL, "-e", "select 1"], capture_output=True).returncode == 0:
            break
        time.sleep(1)
    else:
        raise SystemExit("ace-judge-mysql is not answering")
    mysql("UPDATE performance_schema.setup_consumers SET ENABLED='YES' "
          "WHERE NAME IN ('events_statements_history', 'events_statements_history_long');")
    mysql("\n".join(APPS[app]["db_setup"]))
    print(mysql("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN "
                "('mysql','sys','performance_schema','information_schema');").strip(), "tables")


def statement_errors(schema: str | None) -> list[dict]:
    where = "MYSQL_ERRNO <> 0 AND SQL_TEXT IS NOT NULL"
    if schema:
        where += f" AND CURRENT_SCHEMA = '{schema}'"
    rows = mysql("SELECT MYSQL_ERRNO, REPLACE(REPLACE(SQL_TEXT, '\\n', ' '), '\\t', ' ') "
                 f"FROM performance_schema.events_statements_history_long WHERE {where};")
    return [{"errno": int(r.split("\t", 1)[0]), "sql": r.split("\t", 1)[1]} for r in rows.splitlines() if r]


def cgi_env(app: str, req: dict, src: pathlib.Path) -> tuple[dict, bytes]:
    """The CGI environment of one request. ACE's harness builds `$_SERVER` from this same function."""
    script = req["script"]
    query = urllib.parse.urlencode(req.get("GET") or {})
    body = urllib.parse.urlencode(req.get("POST") or {}).encode()
    cookie = "; ".join(f"{k}={urllib.parse.quote(v)}" for k, v in (req.get("COOKIE") or {}).items())
    env = {"PATH": "/usr/bin:/bin", "DOCUMENT_ROOT": str(src), "SCRIPT_FILENAME": str(src / script),
           "SCRIPT_NAME": "/" + script, "PHP_SELF": "/" + script, "REQUEST_URI": f"/{script}?{query}",
           "REQUEST_METHOD": "POST" if req.get("POST") else "GET", "QUERY_STRING": query,
           "CONTENT_TYPE": "application/x-www-form-urlencoded", "CONTENT_LENGTH": str(len(body)),
           "HTTP_COOKIE": cookie, "SERVER_NAME": "localhost", "SERVER_PORT": "80",
           "SERVER_PROTOCOL": "HTTP/1.1", "GATEWAY_INTERFACE": "CGI/1.1", "REDIRECT_STATUS": "200",
           "REMOTE_ADDR": "127.0.0.1", "HTTP_HOST": "localhost"}
    return env, body


def ini_args(app: str) -> list[str]:
    out = []
    for k, v in (APPS[app].get("ini") or {}).items():
        out += ["-d", f"{k}={v}"]
    return out


def reset_sessions(app: str) -> pathlib.Path:
    """The judge's session directory, restored from the app's session seed (if any)."""
    d = work_of(app) / "sessions"
    if d.exists():
        shutil.rmtree(d)
    d.mkdir()
    seed = APPS[app].get("session_seed_dir")
    if seed:
        for f in (HERE / seed).iterdir():
            shutil.copy(f, d / f.name)
    return d


def _run_cgi(app: str, req: dict, *, xdebug: bool = False, cov_out: str | None = None):
    """Run php-cgi in the app's runner container; returns (CompletedProcess, trace_text)."""
    src, work = src_of(app), work_of(app)
    env, body = cgi_env(app, req, src)
    sessions = work / "sessions"
    sessions.mkdir(exist_ok=True)
    ini = [*ini_args(app), "-d", f"session.save_path={sessions}"]
    trace = work / "trace.txt"
    if trace.exists():
        trace.unlink()
    if xdebug:
        env["XDEBUG_MODE"] = "coverage"
        env["ACE_COV_OUT"] = cov_out
        cmd = ["/usr/local/bin/php-cgi", "-d", "xdebug.mode=coverage",
               "-d", f"auto_prepend_file={HERE / 'judge_cov_prepend.php'}", *ini]
    else:
        env["SYMPHP_TRACE"] = str(trace)
        cmd = ["/hostlib/ld-linux-x86-64.so.2", "--library-path", "/hostlib", str(CGI_REAL), "-n", *ini]
    full = ["docker", "exec", "-i", "-w", str(src), runner(app), "env", "-i",
            *[f"{k}={v}" for k, v in env.items()], *cmd]
    p = subprocess.run(full, input=body, capture_output=True, timeout=120)
    text = trace.read_text(errors="replace") if trace.exists() else ""
    return p, text


def replay_one(app: str, req: dict, reset: str = "none") -> dict:
    src = src_of(app)
    rel = lambda l: l.replace(str(src) + "/", "")                      # noqa: E731
    spec = APPS[app].get("db")
    if spec:
        db = appdb.container(app, "judge")
        with appdb.lock(db):
            if reset == "request":
                appdb.restore(app, "judge")
                reset_sessions(app)
            appdb.clear_history(db)
            p, text = _run_cgi(app, req)
            faults = [{"kind": "sql", **e} for e in appdb.statement_errors(db, spec["database"])]
        lines = sorted(set(text.split()))
    else:
        with appdb.lock("ace-judge-mysql"), tempfile.TemporaryDirectory() as tmp:
            script = req["script"]
            env, body = cgi_env(app, req, src)
            trace = os.path.join(tmp, "trace.txt")
            env["SYMPHP_TRACE"] = trace
            mysql("TRUNCATE performance_schema.events_statements_history_long;")
            p = subprocess.run([str(CGI), "-n", "-d", "mysqli.default_port=3307", "-d", "display_errors=0"],
                               input=body, env=env, cwd=src, capture_output=True, timeout=120)
            lines = sorted(set(pathlib.Path(trace).read_text(errors="replace").split())) if os.path.exists(trace) else []
            faults = [{"kind": "sql", **e} for e in statement_errors(APPS[app].get("schema"))]
    faults += [{"kind": "shell", "message": m.decode(errors="replace")} for m in SHELL_FAULT.findall(p.stderr)]
    head, sep, _ = p.stdout.partition(b"\r\n\r\n")
    return {"request": req, "exit": p.returncode, "body_bytes": len(p.stdout),
            "headers": head.decode(errors="replace")[:2000] if sep else "",
            "faults": faults, "lines": [rel(l) for l in lines]}


def xdebug_pass(app: str, reqs: list[dict]) -> list[list[str]]:
    """Coverage pass: ONE reset, then every request in order (decision (a): per batch)."""
    if not APPS[app].get("db"):
        raise SystemExit("--coverage xdebug needs a db app (a runner container)")
    src, work = src_of(app), work_of(app)
    db = appdb.container(app, "judge")
    out = []
    with appdb.lock(db):
        appdb.restore(app, "judge")
        reset_sessions(app)
        for i, req in enumerate(reqs):
            cov = work / "xdebug_cov.json"
            if cov.exists():
                cov.unlink()
            _run_cgi(app, req, xdebug=True, cov_out=str(cov))
            lines = set()
            if cov.exists():
                for f, ns in json.loads(cov.read_text()).items():
                    if f.startswith(str(src) + "/"):
                        lines |= {f"{f[len(str(src)) + 1:]}:{n}" for n in ns}
            out.append(sorted(lines))
    return out


def exec_lines(app: str) -> dict[str, list[int]]:
    """Executable lines per file (exec_lines.php, PHP-Parser)."""
    src = src_of(app)
    root = HERE.parents[1]
    p = subprocess.run(["docker", "run", "--rm", *appdb.LOG_OPTS, "-u", f"{os.getuid()}:{os.getgid()}",
                        "-v", f"{root}:{root}", "-v", f"{src}:{src}:ro",
                        "php:8.2-cli", "php", str(HERE / "exec_lines.php"), str(src)],
                       capture_output=True, text=True, check=True)
    return json.loads(p.stdout)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=("setup", "replay", "exec-lines"))
    ap.add_argument("app")
    ap.add_argument("requests", nargs="?")
    ap.add_argument("--out")
    ap.add_argument("--reset", choices=("request", "batch", "none"))
    ap.add_argument("--coverage", choices=("trace", "xdebug"), default="trace")
    a = ap.parse_args()
    if a.cmd == "setup":
        setup(a.app)
    elif a.cmd == "exec-lines":
        print(json.dumps(exec_lines(a.app)))
    else:
        reqs = json.loads(pathlib.Path(a.requests).read_text())
        has_db = bool(APPS[a.app].get("db"))
        reset = a.reset or ("request" if has_db else "none")
        if has_db:
            ensure_runner(a.app)
            if reset == "batch":
                appdb.restore(a.app, "judge")
                reset_sessions(a.app)
        results = [replay_one(a.app, r, reset) for r in reqs]
        if a.coverage == "xdebug":
            for r, lines in zip(results, xdebug_pass(a.app, reqs)):
                r["xdebug_lines"] = lines
        pathlib.Path(a.out).write_text(json.dumps(results, indent=1) + "\n")
        print(f"{len(results)} requests replayed, {sum(1 for r in results if r['faults'])} faulted", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
