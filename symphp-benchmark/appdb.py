"""Per-app clone database servers, for ACE (`ace-<app>-db`) and the judge (`judge-<app>-db`).

Neither tool ever talks to an app's INSTALLED database (`<app>-mysql57`): that one is only
read, once, with `mysqldump`, to make the snapshot every clone is loaded from
(`apps.json` -> `db.snapshot`).

THE ADDRESS TRICK. An app's own config names its installed server, e.g. WebChess's
`$CFG_SERVER = "127.0.0.1:3341"`. A clone listens on that SAME port, but inside its own
network namespace, and every PHP process that runs the app (ACE's harness, the judge's
php-cgi) joins that namespace (`docker run --network container:<clone>`). So the app's
unmodified config reaches the clone, and nothing on the host is touched.

Every container started here is log-capped (`--log-opt max-size=20m --log-opt max-file=2`).
"""

from __future__ import annotations

import fcntl
import json
import os
import pathlib
import subprocess
import time
import contextlib

HERE = pathlib.Path(__file__).resolve().parent
APPS = json.loads((HERE / "apps.json").read_text())
LOG_OPTS = ["--log-opt", "max-size=20m", "--log-opt", "max-file=2"]


def spec(app: str) -> dict | None:
    return APPS[app].get("db")


def container(app: str, role: str) -> str:
    """`ace-<app>-db` or `judge-<app>-db`."""
    assert role in ("ace", "judge")
    return f"{role}-{app}-db"


def sql(name: str, text: str, db: str | None = None, check: bool = True) -> str:
    cmd = ["docker", "exec", "-i", name, "mysql", "-uroot", "-N", "-B"] + ([db] if db else [])
    p = subprocess.run(cmd, input=text, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise RuntimeError(f"{name}: {p.stderr.strip()[:500]}")
    return p.stdout


def _running(name: str) -> bool | None:
    p = subprocess.run(["docker", "inspect", "-f", "{{.State.Running}}", name], capture_output=True, text=True)
    return None if p.returncode != 0 else p.stdout.strip() == "true"


def ensure(app: str, role: str) -> str:
    """Start (or reuse) the clone server for `app`, loaded from its snapshot on first start."""
    s = spec(app)
    name = container(app, role)
    state = _running(name)
    if state is None:
        args = [f"--port={s['port']}", "--performance-schema-consumer-events-statements-history-long=ON"]
        if s.get("sql_mode") is not None:
            args.append(f"--sql-mode={s['sql_mode']}")
        args += s.get("mysqld_args", [])
        subprocess.run(["docker", "run", "-d", "--name", name, *LOG_OPTS,
                        "-e", "MYSQL_ALLOW_EMPTY_PASSWORD=yes", s.get("image", "mysql:5.7"), *args],
                       check=True, capture_output=True)
        fresh = True
    elif state is False:
        subprocess.run(["docker", "start", name], check=True, capture_output=True)
        fresh = False
    else:
        fresh = False
    # The image's entrypoint first runs a TEMPORARY server (no networking) to
    # initialise the datadir, then restarts; wait for the real one, on our port.
    for _ in range(180):
        logs = subprocess.run(["docker", "logs", name], capture_output=True, text=True)
        ready = f"port: {s['port']}" in (logs.stdout + logs.stderr)
        if ready and subprocess.run(["docker", "exec", name, "mysql", "-uroot", "-e", "select 1"],
                                    capture_output=True).returncode == 0:
            break
        time.sleep(1)
    else:
        raise SystemExit(f"{name} is not answering")
    # performance_schema consumers are runtime state; re-enable on every start.
    sql(name, "UPDATE performance_schema.setup_consumers SET ENABLED='YES' "
              "WHERE NAME IN ('events_statements_history', 'events_statements_history_long');")
    if fresh or not sql(name, f"SHOW DATABASES LIKE '{s['database']}';").strip():
        restore(app, role)
    return name


def restore(app: str, role: str) -> None:
    """Drop and reload the app's database from its snapshot (the reset)."""
    s = spec(app)
    name = container(app, role)
    dump = (HERE / s["snapshot"]).read_text()
    sql(name, f"DROP DATABASE IF EXISTS `{s['database']}`;\n" + dump)
    if s.get("init_sql"):
        # Server-level state a `--databases` dump does not carry (e.g. the app's DB user).
        sql(name, "\n".join(s["init_sql"]))


def statement_errors(name: str, schema: str | None) -> list[dict]:
    """Statement errors since the last `clear_history`, filtered to `schema` (CURRENT_SCHEMA)."""
    where = "MYSQL_ERRNO <> 0 AND SQL_TEXT IS NOT NULL"
    if schema:
        where += f" AND CURRENT_SCHEMA = '{schema}'"
    rows = sql(name, "SELECT MYSQL_ERRNO, REPLACE(REPLACE(SQL_TEXT, '\\n', ' '), '\\t', ' ') "
                     f"FROM performance_schema.events_statements_history_long WHERE {where};")
    return [{"errno": int(r.split("\t", 1)[0]), "sql": r.split("\t", 1)[1]} for r in rows.splitlines() if r]


def clear_history(name: str) -> None:
    sql(name, "TRUNCATE performance_schema.events_statements_history_long;")


@contextlib.contextmanager
def lock(name: str):
    """One replay at a time per DB server: the statement history is server-wide."""
    path = HERE / "build" / "locks"
    path.mkdir(parents=True, exist_ok=True)
    with open(path / f"{name}.lock", "w") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(fh, fcntl.LOCK_UN)


def snapshot(app: str) -> pathlib.Path:
    """Make the snapshot from the INSTALLED server, read-only (`mysqldump --single-transaction`)."""
    s = spec(app)
    out = HERE / s["snapshot"]
    out.parent.mkdir(parents=True, exist_ok=True)
    p = subprocess.run(["docker", "exec", s["installed"], "mysqldump", "-uroot", "--single-transaction",
                        "--skip-lock-tables", "--databases", s["database"]], capture_output=True, text=True, check=True)
    out.write_text(p.stdout)
    return out


if __name__ == "__main__":
    import sys
    cmd, app, *rest = sys.argv[1:]
    if cmd == "snapshot":
        print(snapshot(app))
    elif cmd == "ensure":
        print(ensure(app, rest[0]))
    elif cmd == "restore":
        restore(app, rest[0])
