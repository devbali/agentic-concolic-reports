#!/usr/bin/env python3
"""Per-item table for the 64 missing combos (Bali 2026-09-04 04:49 directive).

Joins /tmp/per_item_sat.json (per-item Z3 verdict + model) with
/tmp/replay_missing.json (concrete-run result) into one row per missing item.
Writes /tmp/missing_items_table.tsv.

Columns:
  idx        - item index (matches coverage_summary.json missing[] order)
  verdict    - per-item Z3 SAT/UNSAT/UNKNOWN
  elapsed_ms - per-item Z3 solver time
  witnessed  - did the replay concrete-run dump contain ALL the combo's
               path conditions (WITNESSED / NOT / NOT_ATTEMPTED)
  pcs        - # path conditions in the replay dump (0 if not attempted)
  err        - replay dump error class (e.g. ActionView::MissingTemplate)
  guards     - which guard flags the model forces true (closed_account=CA / not_found=NF)
"""
import json

sat = json.load(open("/tmp/per_item_sat.json"))
rep = json.load(open("/tmp/replay_missing.json"))

replay_by_idx = {r["dump"]: r for r in rep["results"]}

rows = []
for r in sat["rows"]:
    idx = r["idx"]
    nc = r.get("node_constraint", "")
    # replay result by position (replay script uses same idx order)
    rr = rep["results"][idx]
    model = r.get("model") or {}
    guards = []
    if any(k == "SYM_PERSON_via_user_closed_account" and v is True for k, v in model.items()):
        guards.append("person_CA")
    if any("closed_account" in k and v is True and not k.startswith("SYM_PERSON_") for k, v in model.items()):
        guards.append("res_CA")
    if any("not_found" in k and v is True for k, v in model.items()):
        guards.append("NF")
    rows.append({
        "idx": idx,
        "verdict": r["verdict"],
        "elapsed_ms": r["elapsed_ms"],
        "witnessed": "WITNESSED" if rr.get("covered") else "NOT",
        "pcs": rr.get("pcs", 0),
        "error": rr.get("error") or "",
        "guards": "+".join(guards),
    })

with open("/tmp/missing_items_table.tsv", "w") as fh:
    fh.write("\t".join(["idx", "verdict", "elapsed_ms", "witnessed", "pcs", "error", "guards"]) + "\n")
    for r in rows:
        fh.write("\t".join(str(r[k]) for k in ["idx", "verdict", "elapsed_ms", "witnessed", "pcs", "error", "guards"]) + "\n")

print(f"{'idx':>3} {'verdict':>6} {'ms':>7} {'witnessed':>10} {'pcs':>4}  guards")
for r in rows:
    print(f"{r['idx']:3d} {r['verdict']:>6} {r['elapsed_ms']:7.1f} {r['witnessed']:>10} {r['pcs']:4d}  {r['guards']}")

from collections import Counter
c = Counter((r["verdict"], r["witnessed"]) for r in rows)
print("\nsummary (verdict, witnessed):", dict(c))
