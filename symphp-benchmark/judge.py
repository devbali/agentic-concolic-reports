#!/usr/bin/env python3
"""The concrete judge both tools are scored by.

usage: judge.py setup <app>
       judge.py replay <app> <requests.json> --out <replay.json>
       judge.py exec-lines <app>

Replays a request against the UNINSTRUMENTED application, under a stock PHP
7.4 php-cgi (`~/symphp-eval/hotcrp/bin/php-cgi-trace`, the same build the
SymPHP replays use, minus `ENABLE_SYMPHP`) and a real MySQL 8 (the
`ace-judge-mysql` container on 127.0.0.1:3307, so the host's own MySQL is
never touched). A request is `{"script", "GET", "POST", "COOKIE"}`.

A request FAULTS a sink when, during it:

* MySQL reports a statement error (`performance_schema`'s statement history,
  `MYSQL_ERRNO <> 0`) -- the fault Witcher and SymPHP escalate to a segfault; or
* `/bin/sh` (dash) reports a syntax error on the request's stderr.

Neither tool's own verdict enters this: a request either faults here or it
does not. Line coverage is the same replay's trace, against the executable
lines `exec-lines` computes with PHP-Parser (the paper's denominator method).
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time
import urllib.parse

HERE = pathlib.Path(__file__).resolve().parent
APPS = json.loads((HERE / "apps.json").read_text())
CGI = pathlib.Path.home() / "symphp-eval/hotcrp/bin/php-cgi-trace"
MYSQL = ["docker", "exec", "-i", "ace-judge-mysql", "mysql", "-uroot", "-N", "-B"]
SHELL_FAULT = re.compile(rb"sh: \d+: Syntax error[^\n]*")


def mysql(sql: str) -> str:
    return subprocess.run(MYSQL, input=sql, capture_output=True, text=True, check=True).stdout


def setup(app: str) -> None:
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


def statement_errors() -> list[dict]:
    rows = mysql("SELECT MYSQL_ERRNO, REPLACE(REPLACE(SQL_TEXT, '\\n', ' '), '\\t', ' ') "
                 "FROM performance_schema.events_statements_history_long "
                 "WHERE MYSQL_ERRNO <> 0 AND SQL_TEXT IS NOT NULL;")
    return [{"errno": int(r.split("\t", 1)[0]), "sql": r.split("\t", 1)[1]} for r in rows.splitlines() if r]


def replay_one(app: str, req: dict) -> dict:
    src = (HERE / APPS[app]["src"]).resolve()
    script = req["script"]
    query = urllib.parse.urlencode(req.get("GET") or {})
    body = urllib.parse.urlencode(req.get("POST") or {}).encode()
    cookie = "; ".join(f"{k}={urllib.parse.quote(v)}" for k, v in (req.get("COOKIE") or {}).items())
    with tempfile.TemporaryDirectory() as tmp:
        trace = os.path.join(tmp, "trace.txt")
        env = {"PATH": "/usr/bin:/bin", "DOCUMENT_ROOT": str(src), "SCRIPT_FILENAME": str(src / script),
               "SCRIPT_NAME": "/" + script, "REQUEST_URI": f"/{script}?{query}",
               "REQUEST_METHOD": "POST" if req.get("POST") else "GET", "QUERY_STRING": query,
               "CONTENT_TYPE": "application/x-www-form-urlencoded", "CONTENT_LENGTH": str(len(body)),
               "HTTP_COOKIE": cookie, "SERVER_NAME": "localhost", "SERVER_PORT": "80",
               "SERVER_PROTOCOL": "HTTP/1.1", "GATEWAY_INTERFACE": "CGI/1.1", "REDIRECT_STATUS": "200",
               "REMOTE_ADDR": "127.0.0.1", "HTTP_HOST": "localhost", "SYMPHP_TRACE": trace}
        mysql("TRUNCATE performance_schema.events_statements_history_long;")
        p = subprocess.run([str(CGI), "-n", "-d", "mysqli.default_port=3307", "-d", "display_errors=0"],
                           input=body, env=env, cwd=src, capture_output=True, timeout=120)
        lines = sorted(set(pathlib.Path(trace).read_text(errors="replace").split())) if os.path.exists(trace) else []
    faults = [{"kind": "sql", **e} for e in statement_errors()]
    faults += [{"kind": "shell", "message": m.decode(errors="replace")} for m in SHELL_FAULT.findall(p.stderr)]
    rel = lambda l: l.replace(str(src) + "/", "")                      # noqa: E731
    return {"request": req, "exit": p.returncode, "body_bytes": len(p.stdout),
            "faults": faults, "lines": [rel(l) for l in lines]}


def exec_lines(app: str) -> dict[str, list[int]]:
    """Executable lines per file (exec_lines.php, PHP-Parser)."""
    src = (HERE / APPS[app]["src"]).resolve()
    root = HERE.parents[1]
    p = subprocess.run(["docker", "run", "--rm", "-u", f"{os.getuid()}:{os.getgid()}", "-v", f"{root}:{root}",
                        "php:8.2-cli", "php", str(HERE / "exec_lines.php"), str(src)],
                       capture_output=True, text=True, check=True)
    return json.loads(p.stdout)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=("setup", "replay", "exec-lines"))
    ap.add_argument("app")
    ap.add_argument("requests", nargs="?")
    ap.add_argument("--out")
    a = ap.parse_args()
    if a.cmd == "setup":
        setup(a.app)
    elif a.cmd == "exec-lines":
        print(json.dumps(exec_lines(a.app)))
    else:
        reqs = json.loads(pathlib.Path(a.requests).read_text())
        results = [replay_one(a.app, r) for r in reqs]
        pathlib.Path(a.out).write_text(json.dumps(results, indent=1) + "\n")
        print(f"{len(results)} requests replayed, {sum(1 for r in results if r['faults'])} faulted", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
