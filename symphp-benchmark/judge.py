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
    sfx = appdb.JUDGE_INSTANCE["suffix"]
    w = HERE / "build" / "judge-work" / (f"{app}-{sfx}" if sfx else app)
    w.mkdir(parents=True, exist_ok=True)
    return w


def runner(app: str) -> str:
    sfx = appdb.JUDGE_INSTANCE["suffix"]
    return f"judge-{app}-{sfx}-php" if sfx else f"judge-{app}-php"


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
    elif APPS[app].get("judge_cgi") == "xdebug":
        # The image's own php-cgi (7.4.33, with pdo_mysql), Xdebug off: logins and other
        # untraced runs of an app the trace build cannot run.
        env["XDEBUG_MODE"] = "off"
        cmd = ["/usr/local/bin/php-cgi", *ini]
    else:
        env["SYMPHP_TRACE"] = str(trace)
        cmd = ["/hostlib/ld-linux-x86-64.so.2", "--library-path", "/hostlib", str(CGI_REAL), "-n", *ini]
    full = ["docker", "exec", "-i", "-w", str(src), runner(app), "env", "-i",
            *[f"{k}={v}" for k, v in env.items()], *cmd]
    try:
        p = subprocess.run(full, input=body, capture_output=True, timeout=120)
    except subprocess.TimeoutExpired as e:
        # A request that runs past 120 s on the real 7.4 app (e.g. WordPress waiting on its own
        # cron URL) is recorded with what it printed so far; its statement history still counts.
        p = subprocess.CompletedProcess(full, -9, e.stdout or b"", (e.stderr or b"") + b"\n[judge: timed out after 120 s]")
    text = trace.read_text(errors="replace") if trace.exists() else ""
    return p, text


def _run_fault_cgi(app: str, req: dict):
    """The fault replay. An app with `judge_cgi: "xdebug"` (one whose extensions the trace build
    lacks: php-cgi-trace has no PDO) is replayed under the ace-judge-php74 php-cgi instead, and its
    `lines` come from the same coverage-only Xdebug prepend as the coverage pass."""
    if APPS[app].get("judge_cgi") != "xdebug":
        return _run_cgi(app, req)
    cov = work_of(app) / "fault_cov.json"
    if cov.exists():
        cov.unlink()
    p, _ = _run_cgi(app, req, xdebug=True, cov_out=str(cov))
    text = ""
    if cov.exists():
        text = "\n".join(f"{f}:{n}" for f, ns in json.loads(cov.read_text()).items() for n in ns)
    return p, text


def is_authenticated(app: str, req: dict) -> bool:
    login = APPS[app].get("login")
    return bool(login) and all((req.get("COOKIE") or {}).get(k) == v for k, v in login["cookie"].items())


def login_recipe(app: str, script: str) -> dict:
    """The login recipe for `script`: the first whose path prefix matches (apps.json `login.recipes`)."""
    for r in APPS[app]["login"]["recipes"]:
        if script.startswith(r["prefix"]):
            return r
    raise SystemExit(f"{app}: no login recipe covers {script}")


def set_cookies(stdout: bytes) -> dict:
    """name -> value from a CGI response's Set-Cookie headers (the last one per name wins)."""
    head = stdout.partition(b"\r\n\r\n")[0].decode(errors="replace")
    out = {}
    for line in head.split("\r\n"):
        if line.lower().startswith("set-cookie:"):
            name, _, rest = line.split(":", 1)[1].strip().partition("=")
            value = rest.split(";", 1)[0]
            if value != "deleted":
                out[name] = urllib.parse.unquote(value)
    return out


def login_if_authenticated(app: str, req: dict) -> dict:
    """The authenticated arm (M2): a request carrying the login cookie is replayed on a session the
    app's own login request just created (fixed session id, so the cookie names it).

    For an app whose login SETS its own auth cookies (`login.cookies_from_login`, phpMyAdmin's
    encrypted pmaUser/pmaAuth and a regenerated session id), the judge uses the cookies of ITS OWN
    login: the ones ACE's harness recorded were made for ACE's session and mean nothing here.
    Returns the cookies to substitute (empty otherwise)."""
    if not is_authenticated(app, req):
        return {}
    recipe = login_recipe(app, req["script"])
    jar = dict(recipe["request"].get("COOKIE") or {})
    login = recipe["request"]
    if recipe.get("pre"):
        # Two-step login (phpMyAdmin): a GET that issues the form token, then the POST with it.
        p, _ = _run_cgi(app, {**recipe["pre"], "COOKIE": jar})
        jar.update(set_cookies(p.stdout))
        m = re.search(recipe["token"]["regex"].encode(), p.stdout)
        if m:
            login = {**login, "POST": {**login.get("POST", {}), recipe["token"]["into"]: m.group(1).decode()}}
    p, _ = _run_cgi(app, {**login, "COOKIE": jar})
    jar.update(set_cookies(p.stdout))
    pin_session_files(app)
    return jar if APPS[app]["login"].get("cookies_from_login") else {}


def pin_session_token(app: str, text: str) -> str:
    """apps.json `login.pin_token` {key, value}: the session's form/CSRF token (or the key it is
    derived from), as PHP serialized it (`key|s:N:"..."` in a session file, `s:K:"key";s:N:"..."`
    in a serialized array), set to a fixed value. Both ACE's harness and the judge pin it right
    after their own login, so a POST that carries the token is valid on both sides (each login
    draws its own random token otherwise). Session STATE, never app code. `text` is latin-1
    decoded bytes: the old value is skipped by its declared LENGTH, so a binary key works."""
    pin = (APPS[app].get("login") or {}).get("pin_token")
    if not pin:
        return text
    rx = re.compile(r'(?:^|(?<=[;}|"]))' + re.escape(pin["key"]) + r'(\||";)s:(\d+):"')
    out, pos = [], 0
    for m in rx.finditer(text):
        if m.start() < pos:
            continue
        end = m.end() + int(m.group(2)) + 1                 # value bytes + closing quote
        out += [text[pos:m.start()], f'{pin["key"]}{m.group(1)}s:{len(pin["value"])}:"{pin["value"]}"']
        pos = end
    return "".join(out) + text[pos:]


def pin_session_db(app: str, role: str) -> None:
    """`pin_token.db_sql`: an app whose sessions live in its DATABASE (OpenCart 3: oc_session, JSON)
    pins the token with that statement, on the role's clone, right after the login."""
    pin = (APPS[app].get("login") or {}).get("pin_token") or {}
    if pin.get("db_sql"):
        appdb.sql(appdb.container(app, role), pin["db_sql"].replace("{value}", pin["value"]), APPS[app]["db"]["database"])


def pin_session_files(app: str) -> None:
    pin_session_db(app, "judge")
    if not (APPS[app].get("login") or {}).get("pin_token"):
        return
    for f in (work_of(app) / "sessions").glob("sess_*"):
        f.write_bytes(pin_session_token(app, f.read_bytes().decode("latin-1")).encode("latin-1"))


def with_cookies(req: dict, cookies: dict) -> dict:
    return {**req, "COOKIE": {**(req.get("COOKIE") or {}), **cookies}} if cookies else req


XSS_MARKER = "acexss"


def xss_faults(req: dict, stdout: bytes) -> list[dict]:
    """M4, decision (f): a reflected-XSS fault is STRUCTURAL. The request must carry a benign
    unique marker (`acexss<hex>`); the response must be HTML and not an attachment; and an HTML5
    parse (html5lib) must show the marker as an element or attribute NAME -- page structure the
    request created -- not merely as text."""
    markers = {m for g in ("GET", "POST", "COOKIE") for v in (req.get(g) or {}).values()
               for m in re.findall(XSS_MARKER + r"[0-9a-f]+", str(v))}
    if not markers:
        return []
    head, _, body = stdout.partition(b"\r\n\r\n")
    h = head.decode(errors="replace").lower()
    ctype = re.search(r"^content-type:\s*([^;\r\n]+)", h, re.M)
    if (ctype and "html" not in ctype.group(1)) or re.search(r"^content-disposition:\s*attachment", h, re.M):
        return []
    import html5lib
    doc = html5lib.parse(body, treebuilder="etree", namespaceHTMLElements=False)
    out = []
    for el in doc.iter():
        tag = el.tag if isinstance(el.tag, str) else ""
        names = [tag] + list(el.attrib)
        for n in names:
            for m in markers:
                if n.lower().startswith(m):
                    out.append({"kind": "xss", "marker": m, "as": "element" if n == tag else "attribute"})
    return out


#: `--reset marked` state: the login area and its cookies, valid until the next restore.
MARKED = {"area": None, "cookies": {}, "fresh": False}
LOGOUT = re.compile(r"(?i)logout|log_out|signout")


def _marked_prepare(app: str, req: dict) -> dict:
    """`--reset marked` (apps with a large snapshot, e.g. OpenEMR's 10 MB): restore the snapshot
    and the sessions only before a request marked `"reset": true` (score.py marks every ORACLE
    WITNESS, so each finding is still judged on the snapshot state); other requests (one per
    explored trace) run in order on the state their predecessors left. An authenticated request
    logs in once per area, again after every restore and after any logout-looking script."""
    if req.get("reset"):
        appdb.restore(app, "judge")
        reset_sessions(app)
        MARKED.update(area=None, cookies={})
    if not is_authenticated(app, req):
        return {}
    area = login_recipe(app, req["script"])["prefix"]
    if MARKED["area"] != area:
        reset_sessions(app)
        MARKED.update(area=area, cookies=login_if_authenticated(app, req))
    return MARKED["cookies"]


def replay_one(app: str, req: dict, reset: str = "none") -> dict:
    src = src_of(app)
    rel = lambda l: l.replace(str(src) + "/", "")                      # noqa: E731
    spec = APPS[app].get("db")
    marked = bool(req.get("reset"))
    req = {k: v for k, v in req.items() if k != "reset"}
    if spec:
        db = appdb.container(app, "judge")
        with appdb.lock(db):
            cookies = {}
            if reset == "request":
                appdb.restore(app, "judge")
                reset_sessions(app)
                cookies = login_if_authenticated(app, req)
            elif reset == "marked":
                cookies = _marked_prepare(app, {**req, "reset": marked})
            appdb.clear_history(db)
            p, text = _run_fault_cgi(app, with_cookies(req, cookies))
            if reset == "marked" and LOGOUT.search(req["script"] + json.dumps(req.get("GET") or {})):
                MARKED["area"] = None
            faults = [{"kind": "sql", **e} for e in
                      appdb.statement_errors(db, spec["database"] if spec.get("schema_filter", True) else None,
                                             spec.get("fault_exclude_errnos", ()))]
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
    faults += xss_faults(req, p.stdout)
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
        area, cookies = None, {}
        for i, req in enumerate(reqs):
            if is_authenticated(app, req) and login_recipe(app, req["script"])["prefix"] != area:
                # A different area's login replaces the session's role (same session id).
                reset_sessions(app)
                cookies = login_if_authenticated(app, req)
                area = login_recipe(app, req["script"])["prefix"]
            req = with_cookies(req, cookies) if is_authenticated(app, req) else req
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
                        "php:8.2-cli", "php", "-d", "memory_limit=2G", str(HERE / "exec_lines.php"), str(src),
                        ",".join(APPS[app].get("php_exts") or ["php"])],
                       capture_output=True, text=True, check=True)
    return json.loads(p.stdout)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=("setup", "replay", "exec-lines"))
    ap.add_argument("app")
    ap.add_argument("requests", nargs="?")
    ap.add_argument("--out")
    ap.add_argument("--reset", choices=("request", "batch", "marked", "none"))
    ap.add_argument("--coverage", choices=("trace", "xdebug"), default="trace")
    ap.add_argument("--instance", default="", help="judge clone judge-<app>-<N>-db / runner judge-<app>-<N>-php")
    a = ap.parse_args()
    appdb.JUDGE_INSTANCE["suffix"] = a.instance
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
            if reset == "marked":
                appdb.restore(a.app, "judge")
                reset_sessions(a.app)
            if reset == "batch":
                appdb.restore(a.app, "judge")
                reset_sessions(a.app)
                if reqs and is_authenticated(a.app, reqs[0]):
                    _run_cgi(a.app, login_recipe(a.app, reqs[0]["script"])["request"])
        if a.out.endswith(".jsonl"):
            # STREAMING (large apps): one compact JSON line per request, written as it is judged,
            # so neither memory nor a crash loses the slice. Covered lines are stored per file
            # (`lines_by_file`); for a judge_cgi xdebug app they ARE the Xdebug coverage. A rerun
            # RESUMES: complete lines already in the file are kept and their requests skipped.
            outp = pathlib.Path(a.out)
            done = 0
            if outp.exists():
                raw = outp.read_bytes()
                keep = raw[:raw.rfind(b"\n") + 1] if b"\n" in raw else b""
                outp.write_bytes(keep)                   # drop a partial last line
                done = keep.count(b"\n")
            if done and reset == "marked" and done < len(reqs):
                # The state the skipped requests left is gone: start the rest on a fresh snapshot.
                reqs[done] = {**reqs[done], "reset": True}
            faulted = 0
            with outp.open("a") as fh:
                for r in reqs[done:]:
                    res = replay_one(a.app, r, reset)
                    by_file: dict[str, list[int]] = {}
                    for l in res.pop("lines"):
                        f, _, n = l.rpartition(":")
                        if n.isdigit():
                            by_file.setdefault(f, []).append(int(n))
                    res["lines_by_file"] = by_file
                    faulted += bool(res["faults"])
                    fh.write(json.dumps(res, separators=(",", ":")) + "\n")
                    fh.flush()
            print(f"{len(reqs) - done} requests replayed ({done} resumed), {faulted} faulted", file=sys.stderr)
            return 0
        results = [replay_one(a.app, r, reset) for r in reqs]
        if a.coverage == "xdebug" and APPS[a.app].get("judge_cgi") == "xdebug":
            # The fault replays already ran under Xdebug: their lines ARE the Xdebug coverage.
            for r in results:
                r["xdebug_lines"] = r["lines"]
        elif a.coverage == "xdebug":
            reqs = [{k: v for k, v in r.items() if k != "reset"} for r in reqs]
            for r, lines in zip(results, xdebug_pass(a.app, reqs)):
                r["xdebug_lines"] = lines
        out = json.dumps(results, indent=1) + "\n"
        if a.out.endswith(".gz"):
            # Per-request covered lines make large-app replays GBs of JSON (disk): gzip it.
            import gzip
            pathlib.Path(a.out).write_bytes(gzip.compress(out.encode(), 6))
        else:
            pathlib.Path(a.out).write_text(out)
        print(f"{len(results)} requests replayed, {sum(1 for r in results if r['faults'])} faulted", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
