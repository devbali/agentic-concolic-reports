#!/usr/bin/env python3
"""coverage_report.py <dumps-dir> [--assumptions <declared.json>]

Prints the endpoint's coverage status over a directory of dump_*.json: whether it
is complete, and for each unwalked-but-satisfiable frontier edge, the concrete
SEED dict that reaches it (feed one straight back to box_runner_blind.py via
EXTRA_SEEDS_JSON). `unknown`/`unevaluable` edges are decisions with no Z3 meaning
-- a branch no input can drive -- and are candidates for a declared assumption.

Imports only the engine's coverage checker; no oracle, no judge. Blind.
"""
import glob
import json
import sys

from dump_ir.run import Run
from dump_ir.provenance import validate_provenance
from concolic import coverage
from concolic.assumptions import AssumptionSet, declared_assumption_set


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    d = sys.argv[1]
    declared = None
    if "--assumptions" in sys.argv:
        declared = sys.argv[sys.argv.index("--assumptions") + 1]

    runs, bad = [], 0
    for p in sorted(glob.glob(f"{d}/dump_*.json")):
        raw = json.load(open(p))
        if raw.get("error"):
            continue
        try:
            r = Run.from_dict(raw)
            validate_provenance(r, where=p)
            runs.append(r)
        except Exception as e:  # noqa: BLE001
            bad += 1
            print(f"  provenance-fail {p.split('/')[-1]}: {type(e).__name__}", file=sys.stderr)

    # Load BOTH declared kinds (UntrackedPathAssumption AND IndependenceAssumption)
    # through the engine's canonical loader, so this local check applies independence
    # exactly as the gate does -- an independence declaration that closes coverage shows
    # up as "complete": true here too, not just at the gate.
    aset = AssumptionSet()
    refusals = []
    if declared:
        aset, refusals = declared_assumption_set(json.load(open(declared)))

    res = coverage.check(runs, aset, timeout_ms=8000)
    # Observed branch decisions grouped by their source file, so a declarer can name
    # mutually-independent groups (e.g. shared framework/bootstrap files vs the endpoint
    # script). Each entry is a decision `expr` string -- paste these into an
    # IndependenceAssumption's "a"/"b" as {"expr": <string>}.
    by_file = {}
    for r in runs:
        for pc in r.path_conditions:
            s = getattr(pc, "source", None)
            f = ((getattr(s, "file", "") or "").rsplit("/", 1)[-1]) or "?"
            by_file.setdefault(f, set()).add(pc.expr)
    out = {
        "runs": len(runs), "provenance_fail": bad,
        "complete": res.complete,
        "missing": [{"edge": str(m.edge), "seeds": m.seeds} for m in res.missing],
        "unknown": [str(e) for e in res.unknown],
        "unevaluable": list(res.unevaluable),
        "closed": len(res.closed),
        "assumption_refusals": [str(r) for r in refusals],
        "decisions_by_file": {f: sorted(e) for f, e in sorted(by_file.items())},
    }
    print(json.dumps(out, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
