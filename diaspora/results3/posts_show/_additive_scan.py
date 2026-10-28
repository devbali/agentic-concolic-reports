#!/usr/bin/env python3
"""Does posts_show have ANY additive dependence for the gate to catch?

Coordinator, 2026-09-11. The flip-both test FAILs a pair when the combination
produces a target-call SHAPE absent from base u flip-A u flip-B. That is a
CORPUS FACT and needs no replay: group the runs by the pair's (A,B) outcome
cell, union the access-trace shapes per cell, and ask whether any cell holds a
shape the other three never produce.

If such pairs exist they are the RIGHT negative controls -- they must FAIL the
gate. If none exist, the endpoint has no additive dependence for this test to
see, and PASS is the honest verdict for non-foreclosing pairs.

Shapes are interned to bit positions so a run's trace is one int and a cell
union is an OR -- otherwise this is 1 733 pairs x N runs of set arithmetic.
"""
import json, os, sys, time
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from end_to_end_completion_checker.assumption import assumption_checker as AC  # noqa: E402

LIMIT = int(os.environ.get("SCAN_RUNS", "8000"))
pairs = [tuple(x[:2]) for x in json.load(open(os.path.join(HERE, "_tier2_after_wf.json")))["kept"]]
want = sorted({e for p in pairs for e in p})
widx = {e: i for i, e in enumerate(want)}
print(f"{len(pairs)} candidate pairs over {len(want)} expressions", flush=True)

files = [l.strip() for l in open(os.environ["DUMP_LIST"]) if l.strip()][:LIMIT]
files = [f if os.path.isabs(f) else os.path.join(HERE, f) for f in files]
print(f"scanning {len(files)} dumps", flush=True)

shape_id = {}
runs = []            # (outcome bitmask, evaluated bitmask, trace bitmask)
t0 = time.time()
for n, p in enumerate(files):
    try:
        d = json.load(open(p))
    except Exception:
        continue
    out = ev = 0
    for e in d.get("events") or ():
        if e.get("type") == "path_condition":
            i = widx.get(str(e.get("expr", "")))
            if i is not None:
                ev |= 1 << i
                if e.get("taken"):
                    out |= 1 << i
    tr = 0
    for s in AC.access_trace(d):
        j = shape_id.get(s)
        if j is None:
            j = shape_id[s] = len(shape_id)
        tr |= 1 << j
    runs.append((out, ev, tr))
    del d
    if n % 2000 == 0:
        print(f"  [{n}/{len(files)}] shapes={len(shape_id)} {time.time()-t0:.0f}s", flush=True)
print(f"loaded {len(runs)} runs, {len(shape_id)} distinct trace shapes, "
      f"{time.time()-t0:.0f}s", flush=True)

hits = []
for pi, (a, b) in enumerate(pairs):
    ia, ib = widx[a], widx[b]
    ma, mb = 1 << ia, 1 << ib
    cell = [0, 0, 0, 0]      # index: A*2+B
    seen = [0, 0, 0, 0]
    for out, ev, tr in runs:
        if not (ev & ma) or not (ev & mb):
            continue          # not co-evaluated in this run
        k = (2 if out & ma else 0) | (1 if out & mb else 0)
        cell[k] |= tr
        seen[k] += 1
    if sum(1 for c in seen if c) < 2:
        continue              # only one cell observed: nothing to compare
    for k in range(4):
        if not seen[k]:
            continue
        others = 0
        for j in range(4):
            if j != k:
                others |= cell[j]
        novel = cell[k] & ~others
        if novel:
            hits.append((pi, a, b, k, seen, novel.bit_count()))
    if pi % 300 == 0:
        print(f"  pair {pi}/{len(pairs)} hits={len(hits)} {time.time()-t0:.0f}s", flush=True)

inv = {v: k for k, v in shape_id.items()}
print(f"\n=== ADDITIVE-DEPENDENCE WITNESSES IN THE CORPUS ===")
print(f"pairs with a cell-only shape: {len({h[0] for h in hits})} of {len(pairs)}")
for pi, a, b, k, seen, nbits in hits[:15]:
    names = []
    ia = 0
    print(f"  pair#{pi} cell=({k>>1},{k&1}) seen={seen} novel_shapes={nbits}")
    print(f"     A: {a[:96]}")
    print(f"     B: {b[:96]}")
json.dump({"n_pairs": len(pairs), "n_runs": len(runs), "n_shapes": len(shape_id),
           "hits": [[h[0], h[1], h[2], h[3], h[4], h[5]] for h in hits[:500]],
           "n_hit_pairs": len({h[0] for h in hits})},
          open(os.path.join(HERE, "_additive_scan.json"), "w"), indent=1)
print(f"\nwrote _additive_scan.json ({time.time()-t0:.0f}s)")
