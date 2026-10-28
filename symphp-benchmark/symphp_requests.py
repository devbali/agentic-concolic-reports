#!/usr/bin/env python3
"""SymPHP's S2E test cases -> judge requests.

usage: symphp_requests.py <out.json> <run-dir> [<run-dir> ...]

For each run (`~/symphp-eval/witcher-test/runs/<name>/`, made by that tree's
run.sh), every S2E state with a test case becomes one request: the run's seed
request (`request.json`) with each solved `_SYM_<key>` value substituted. The
seed request itself is included too -- SymPHP's first state executes it
concretely -- so a tool is credited with everything its input already reached.

A symbolic name carries the KEY but not the superglobal (`_SYM_nv1`), so it is
mapped back to whichever of GET/POST the seed held it in; SymPHP marks only
those two (php-src/Zend/zend_hash.c, `TRACK_VARS_GET`/`TRACK_VARS_POST`).
Parsing reuses the SymPHP replay's own `parse_testcases`.
"""

from __future__ import annotations

import importlib.util
import json
import pathlib
import sys

_spec = importlib.util.spec_from_file_location(
    "symphp_replay", pathlib.Path.home() / "symphp-eval/hotcrp/replay/replay.py")
replay = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(replay)


def requests_for(run: pathlib.Path) -> tuple[list[dict], dict]:
    seed = json.loads((run / "request.json").read_text())
    states = replay.parse_testcases(str(run / "s2e-last"))
    out = [seed]
    for sid in sorted(states):
        req = json.loads(json.dumps(seed))
        for key, data in states[sid]["vars"].items():
            value = data.decode("latin-1")
            for g in ("GET", "POST"):
                if key in req.get(g, {}):
                    req[g][key] = value
                    break
        out.append(req)
    meta = json.loads((run / "run.json").read_text()) if (run / "run.json").exists() else {}
    debug = run / "s2e-last" / "debug.txt"
    text = debug.read_text(errors="replace") if debug.exists() else ""
    meta |= {"states_with_testcase": len(states), "php_forks": text.count("PHPFORK"),
             "completed": text.count("php-cgi finished")}
    return out, meta


def main() -> int:
    out, runs = pathlib.Path(sys.argv[1]), [pathlib.Path(p) for p in sys.argv[2:]]
    reqs, metas = [], []
    for run in runs:
        r, m = requests_for(run)
        reqs += r
        metas.append({"run": run.name, **m, "requests": len(r)})
    unique = {json.dumps(r, sort_keys=True): r for r in reqs}
    out.write_text(json.dumps(list(unique.values()), indent=1) + "\n")
    out.with_suffix(".runs.json").write_text(json.dumps(metas, indent=1) + "\n")
    print(f"{len(runs)} runs, {len(reqs)} requests, {len(unique)} distinct", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
