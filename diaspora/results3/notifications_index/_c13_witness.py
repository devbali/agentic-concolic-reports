#!/usr/bin/env python3
"""C13 — the 777 distinct witness cubes of the C12 coverage pass, from the
CHECKPOINT (not the 153 MB summary, whose `missing[]` is a flattened, capped
projection of the same thing).

`_cov_c12.ckpt.jsonl` holds ONE record per demand set (1 665), and for a set
with a gap `combos[i]` is the leaf assignment — EVERY (expr, outcome) pair the
leaf pins, gates included, because the leaf is the foreclosure-ordered cube —
and `models[i]` is Z3's counterexample for it. So the enabling gates are read
off the checker's own structure and NOTHING is re-solved here (RUNBOOK Phase 2).

The pass ran at max_missing_per_clique=4 (coverage_report.py's own default; the
launch line did not set MAX_MISSING_PER_CLIQUE and the engine's new default of 1
is therefore NOT what ran): 171 of the 298 flagged sets stopped AT the cap, so
the witness list is a LOWER bound on the remaining leaves.

writes _c13_gaps.json
"""
import json, os, re, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
CKPT = os.environ.get("C13_CKPT", os.path.join(HERE, "_cov_c12.ckpt.jsonl"))
OUT  = os.environ.get("C13_GAPS", os.path.join(HERE, "_c13_gaps.json"))

f = open(CKPT); hdr = json.loads(f.readline())
sets_total = sets_gap = combos_total = capped = 0
seen, gaps = set(), []
for line in f:
    r = json.loads(line); v = r["v"]; sets_total += 1
    cs = v.get("combos") or []
    if not cs:
        continue
    sets_gap += 1
    capped += 1 if v.get("truncated") else 0
    for i, c in enumerate(cs):
        combos_total += 1
        cube = [(e, bool(t)) for e, t in c]
        key = tuple(cube)
        if key in seen:
            continue
        seen.add(key)
        gaps.append({
            "id": f"g{len(gaps):05d}",
            "set": r["k"],
            "set_capped": bool(v.get("truncated")),
            "width": len(cube),
            "cube": cube,
            "model": v["models"][i],
        })
print(f"demand sets in checkpoint : {sets_total}")
print(f"sets WITH A GAP           : {sets_gap}   ({capped} stopped AT the cap of 4)")
print(f"witness leaves            : {combos_total}   distinct: {len(gaps)}")
w = Counter(g["width"] for g in gaps)
print("width histogram           :", dict(sorted(w.items())))
ex = Counter(e for g in gaps for e, _ in g["cube"])
print(f"distinct expressions      : {len(ex)}")
json.dump(gaps, open(OUT, "w"))
print(f"C13-WITNESS-DONE {OUT} ({os.path.getsize(OUT)/1e6:.1f} MB)")
