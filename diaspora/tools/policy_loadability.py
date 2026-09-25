#!/usr/bin/env python3
"""POLICY LOADABILITY — how many statements of a shipped policy the project's
own SQL loader can actually load.

    policy_loadability.py <policy.sql> [<policy.sql> ...] [--app-config PATH]
                          [--timeout-ms N] [--json OUT]

THE LOADER is the one every SQL consumer in this project goes through:
`src/queries_from_runs/subsume/check_subsumed.sh` (Calcite parse + H2/Calcite
schema + blockaid's solver-type probe), driven by the app config. A statement
it cannot take lands in that harness's `errors` map and — per
`subsume.py`'s own docstring — "participates in no pair and always survives",
i.e. it is silently kept in the policy while meaning nothing to any consumer.
That silence is the defect this tool measures.

WRITTEN   statements in the file (comment lines excluded)
LOADABLE  statements the loader accepted (no `errors` entry)

A bare unresolved bind (`_SYM_RESULT_<...>`) is the usual cause: it is not a
column of any FROM table and is not a declared constant, so the loader rejects
the statement. Declaring it in the app config's `subsume.const_decls` (where
`_MY_UID` is declared) makes it an uninterpreted constant of the right type,
which loads AND is the honest reading — an unconstrained unknown value.

The pairwise solver is not what is being measured, so `--timeout-ms` defaults
to 1: parsing and the solver-type probe both run BEFORE the pairwise pass, so
the error map is complete while no pair costs anything.
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKER = "/home/dev/project/src/queries_from_runs/subsume/check_subsumed.sh"


def statements(path):
    """The SQL statements of a policy file, comment lines removed."""
    body = "".join(
        l for l in open(path, encoding="utf-8", errors="replace")
        if not l.lstrip().startswith("--")
    )
    return [s.strip() for s in body.split(";") if s.strip()]


def load_probe(sqls, app_config, timeout_ms, batch=20):
    env = dict(os.environ)
    env["QFR_APP_CONFIG"] = app_config
    env["SUBSUME_TIMEOUT_MS"] = str(timeout_ms)
    env.pop("JAVA_TOOL_OPTIONS", None)
    # BATCHED: the harness's pairwise cost is quadratic in the list size and
    # only its PER-QUERY parse + solver-type probe is measured here, so the
    # file is probed in chunks and the chunk offset added back to the indices.
    errors = {}
    for off in range(0, len(sqls), batch):
        chunk = sqls[off:off + batch]
        p = subprocess.run(
            [CHECKER], input=json.dumps({"queries": chunk}),
            capture_output=True, text=True, env=env, timeout=3600,
        )
        if p.returncode != 0:
            raise RuntimeError(f"checker exited {p.returncode}: {p.stderr[-800:]}")
        res = json.loads(p.stdout.strip().splitlines()[-1])
        for k, v in (res.get("errors") or {}).items():
            errors[str(off + int(k))] = v
    return {"errors": errors}


def main():
    args = sys.argv[1:]
    files, skip = [], False
    for i, a in enumerate(args):
        if skip:
            skip = False
            continue
        if a.startswith("--"):
            skip = a in ("--app-config", "--timeout-ms", "--json", "--batch")
            continue
        files.append(a)

    def opt(n, d=None):
        return args[args.index(n) + 1] if n in args else d

    app_config = opt("--app-config",
                     "/home/dev/project/reports/diaspora/queries_config/app.json")
    timeout_ms = int(opt("--timeout-ms", "1"))
    out_json = opt("--json")
    batch = int(opt("--batch", "20"))

    report = {}
    total_w = total_l = 0
    for f in files:
        sqls = statements(f)
        res = load_probe(sqls, app_config, timeout_ms, batch)
        errs = res.get("errors") or {}
        # a solver TIMEOUT at 1ms is not a load failure; only real rejections are
        errs = {k: v for k, v in errs.items()
                if "timeout" not in str(v).lower()}
        n_w, n_bad = len(sqls), len(errs)
        n_l = n_w - n_bad
        total_w += n_w
        total_l += n_l
        name = os.path.basename(f)
        report[name] = {
            "written": n_w, "loadable": n_l, "unloadable": n_bad,
            "errors": {int(k): v for k, v in errs.items()},
            "unloadable_sql": {int(k): sqls[int(k)][:400] for k in errs},
        }
        pct = 100.0 * n_l / n_w if n_w else 100.0
        print(f"{name:26s} written={n_w:4d}  loadable={n_l:4d}  "
              f"unloadable={n_bad:4d}  {pct:6.2f}%")
        seen = set()
        for k, v in sorted(errs.items(), key=lambda kv: int(kv[0])):
            shape = re.sub(r"\s+", " ", str(v))[:110]
            if shape in seen:
                continue
            seen.add(shape)
            print(f"      e.g. #{k}: {shape}")
    if len(files) > 1:
        pct = 100.0 * total_l / total_w if total_w else 100.0
        print(f"{'TOTAL':26s} written={total_w:4d}  loadable={total_l:4d}  "
              f"unloadable={total_w - total_l:4d}  {pct:6.2f}%")
    if out_json:
        with open(out_json, "w") as fh:
            json.dump(report, fh, indent=1)
    sys.exit(0 if total_l == total_w else 1)


if __name__ == "__main__":
    main()
