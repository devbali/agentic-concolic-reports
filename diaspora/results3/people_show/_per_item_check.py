#!/usr/bin/env python3
"""Per-item Z3 satisfiability proof for the 64 people_show missing combos.

Bali directive 2026-09-04 04:49: go ITEM-AT-A-TIME, one bounded Z3 check per
missing item (node_constraint), timeout -> UNKNOWN (never claim a verdict we
did not prove). Reuses the EXACT solver context of the checker that produced
the missing list (same merged declarations, same bounds + assumption symbolic
constraints) so the verdicts are faithful to the app's own demand universe.

IMPORTANT (fix 2026-09-04): the stored node_constraint is DISPLAY format
("A AND B AND C"), not eval-able Python. The parseable form is
And(A, B, C) — rebuilt here by splitting on the join separator " AND ".
A fresh z3 model is extracted per item (concrete values for the seed
replay step).

Verdicts per item:
    SAT     -> the combo is z3-satisfiable under bounds+assumptions; the
               model carries concrete values for a seed replay run.
    UNSAT   -> z3 proved the combo unsatisfiable (genuine proof).
    UNKNOWN -> solver did not return within the per-item budget, OR the
               rebuilt query failed to parse. Reported honestly as unknown,
               NEVER as complete/unsat.

Writes /tmp/per_item_sat.json: index | verdict | elapsed_ms | model-if-SAT.

Usage: python3 _per_item_check.py
"""
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.coverage import CoverageChecker     # noqa: E402
from concolic_engine.run import Run                      # noqa: E402
from concolic_engine.solver import check_satisfiability  # noqa: E402
import coverage_assumptions  # noqa: E402

PER_ITEM_TIMEOUT_MS = 60_000  # 60s per item; elapsed ~timeout => UNKNOWN
SEP = " AND "  # display join separator in node_constraint


def fix_len_names(dump: dict) -> dict:
    _LEN_RE = re.compile(r"len\(([^()]+)\)")
    return json.loads(_LEN_RE.sub(r"SYM_LEN_\1", json.dumps(dump)))


def rebuild_and_query(node_constraint: str):
    """Split display 'A AND B AND C' -> 'And(A, B, C)'. Returns None if the
    split looks wrong (a clause containing the separator would be ambiguous)."""
    clauses = [c.strip() for c in node_constraint.split(SEP)]
    if len(clauses) < 1:
        return None
    if any(SEP in c for c in clauses):  # defensive: ambiguous split
        return None
    if len(clauses) == 1:
        return clauses[0]
    return f"And({', '.join(clauses)})"


def main() -> int:
    dumps = sorted(os.path.join(HERE, f) for f in os.listdir(HERE)
                   if f.startswith("dump_") and f.endswith(".json"))
    runs = []
    for p in dumps:
        try:
            runs.append(Run.from_dict(fix_len_names(json.load(open(p)))))
        except Exception as e:  # noqa: BLE001
            print(f"skip {os.path.basename(p)}: {type(e).__name__}: {e}", flush=True)
    print(f"loaded {len(runs)} runs", flush=True)

    assumptions = coverage_assumptions.build()
    cc = CoverageChecker(runs, assumptions=assumptions)
    decls = cc._merged_declarations()
    bounds = cc._merged_bounds()
    extra = assumptions.symbolic_constraints()
    fixed_base = list(extra) + bounds

    summary = json.load(open(os.path.join(HERE, "coverage_summary.json")))
    items = summary["missing"]
    print(f"per-item checking {len(items)} missing combos (timeout {PER_ITEM_TIMEOUT_MS/1000:.0f}s, "
          f"{len(decls)} decls, {len(fixed_base)} fixed constraints)", flush=True)

    rows = []
    t0 = time.time()
    for i, m in enumerate(items):
        nc = m["node_constraint"]
        query = rebuild_and_query(nc)
        start = time.time()
        if query is None:
            rows.append({
                "idx": i, "verdict": "UNKNOWN", "elapsed_ms": 0.0,
                "node_constraint": nc[:220], "model": None,
                "stored_concrete_values": m.get("concrete_values"),
                "note": "ambiguous AND split",
            })
            print(f"  [{i:2d}] UNKNOWN    (ambiguous split)  {nc[:90]}", flush=True)
            continue
        res = check_satisfiability(fixed_base + [query], decls, PER_ITEM_TIMEOUT_MS)
        elapsed = time.time() - start
        if res.satisfiable:
            verdict = "SAT"
        elif elapsed >= PER_ITEM_TIMEOUT_MS / 1000 * 0.9:
            verdict = "UNKNOWN"
        else:
            # Distinguish genuine UNSAT from parse failure: parse failures
            # come back with solver_elapsed_ms == 0.0 from solver.py.
            if res.solver_elapsed_ms == 0.0 and elapsed < PER_ITEM_TIMEOUT_MS / 1000 * 0.9:
                verdict = "UNKNOWN"  # likely parse failure, not a proof
            else:
                verdict = "UNSAT"
        rows.append({
            "idx": i,
            "verdict": verdict,
            "elapsed_ms": round(res.solver_elapsed_ms, 1),
            "node_constraint": nc[:220],
            "model": (res.model if res.satisfiable else None),
            "stored_concrete_values": m.get("concrete_values"),
        })
        print(f"  [{i:2d}] {verdict:7s} {res.solver_elapsed_ms:8.0f}ms  {nc[:90]}", flush=True)

    wall = time.time() - t0
    counts = {}
    for r in rows:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
    print(f"\nper-item verdicts: {counts}  wall={wall:.1f}s", flush=True)

    out = "/tmp/per_item_sat.json"
    with open(out, "w") as fh:
        json.dump({"verdicts": counts, "wall_seconds": round(wall, 1), "rows": rows},
                  fh, indent=2, sort_keys=False)
    print(f"wrote {out}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())