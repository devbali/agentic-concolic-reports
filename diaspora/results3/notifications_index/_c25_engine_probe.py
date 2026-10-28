#!/usr/bin/env python3
"""C25 — the ENGINE's OWN §16f walk, replayed offline over the four witness
leaves at every width, with the shipped `minimal_subconjunction`.

Reads the bitsets `_c25_mincond.py` built over the C24R2 corpus, rebuilds
`takes`/`evals`/`universe` at RUN granularity (the engine uses PROFILES; a
profile exists iff some run has it, so the A > 0 / B = 0 partition — the only
thing the inference reads — is identical, and only the A COUNTS differ), and
runs the emission-side walk of coverage.py step 6 verbatim:

    acc = (); for (e, o) in combo:
        hit = minimal_subconjunction(acc, e, takes, evals, universe, W, budget)
        if hit: drop e, contribute NO literal
        else:   keep, acc += ((e, o),)

for W = 1..12 and budget in {20 000 (the default), 10**9}.  A difference
between the two budgets at the same W IS a budget exhaustion — the shipped
search reports one silently (`_SubconjBudget` -> None -> member stays).

No src/ edit: the engine function is IMPORTED.
"""
import json, os, pickle, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.coverage import minimal_subconjunction   # noqa: E402

BITS = os.environ.get("BITS", os.path.join(HERE, "_c25_mincond_bits.pkl"))
CKPT = os.environ.get("CKPT", os.path.join(HERE, "_cov_c24_C24R2.ckpt.jsonl"))
OUT = os.environ.get("OUT", os.path.join(HERE, "_c25_engine_probe.json"))
BUDGETS = [int(x) for x in os.environ.get("BUDGETS", "20000,1000000000").split(",")]

st = pickle.load(open(BITS, "rb"))
EXPRS = st["exprs"]; N = st["n"]; TB = st["T"]; FB = st["F"]
EIDX = {e: i for i, e in enumerate(EXPRS)}
takes = {}
for e, j in EIDX.items():
    takes[(e, True)] = TB[j]
    takes[(e, False)] = FB[j]
evals = {e: TB[EIDX[e]] | FB[EIDX[e]] for e in EXPRS}
UNIV = (1 << N) - 1
print(f"bitsets: {len(EXPRS)} exprs over {N} runs", flush=True)

f = open(CKPT); f.readline()
leaves = []
for line in f:
    r = json.loads(line); v = r.get("v") or {}
    for combo in (v.get("combos") or []):
        leaves.append((r["k"], [(e, bool(o)) for e, o in combo]))
f.close()
print(f"witness leaves: {len(leaves)}", flush=True)

out = []
for li, (k, combo) in enumerate(leaves):
    print(f"\n=== LEAF {li}  key {k}  width {len(combo)} ===", flush=True)
    rec = {"leaf": li, "key": k, "width": len(combo), "by_width": {}}
    for W in range(1, len(combo) + 1):
        for bud in BUDGETS:
            acc = (); kept = []; drops = []
            for e, o in combo:
                hit = minimal_subconjunction(acc, e, takes, evals, UNIV,
                                             width=W, budget=bud)
                if hit is not None:
                    cond, a = hit
                    drops.append({"member": e, "outcome": o,
                                  "C": [[x, y] for x, y in cond],
                                  "size": len(cond), "A_runs": a})
                    continue
                kept.append((e, o)); acc = acc + ((e, o),)
            rec["by_width"].setdefault(str(W), {})[str(bud)] = {
                "kept": len(kept), "dropped": len(drops), "drops": drops}
        d0 = rec["by_width"][str(W)][str(BUDGETS[0])]
        d1 = rec["by_width"][str(W)][str(BUDGETS[-1])]
        flag = "  *** BUDGET-EXHAUSTED (default differs from unbounded)" \
            if d0["dropped"] != d1["dropped"] else ""
        print(f"  W={W:2d}  kept={d0['kept']:2d} dropped={d0['dropped']:2d}"
              f"   (unbounded budget: dropped={d1['dropped']}){flag}", flush=True)
        for d in d1["drops"]:
            print(f"      drop |C|={d['size']} A={d['A_runs']}  {d['member']}", flush=True)
            for x, y in d["C"]:
                print(f"          {'T' if y else 'F'}  {x}", flush=True)
    out.append(rec)

json.dump(out, open(OUT, "w"), indent=1)
print("\nC25-ENGINE-PROBE-DONE", flush=True)
