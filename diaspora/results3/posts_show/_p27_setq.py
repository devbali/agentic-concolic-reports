#!/usr/bin/env python3
"""P27 phase 4 — run the CHECKER's own §16d one-query-per-set test (fixed base
+ this set's pins + one blocking clause per observed leaf) on the sets the
census and the exact recount DISAGREE about, and on a control sample of the
sets they agree about. UNSAT = the checker calls the set COVERED."""
import json, os, sys, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
import z3
from concolic_engine.solver import _Z3_NAMESPACE
from concolic_engine.coverage import _outcome_constraint, _block_constraint

fh = open(os.path.join(HERE, "_p27_state.jsonl"))
H = json.loads(fh.readline())
ENV = dict(_Z3_NAMESPACE)
for d in H["decls"]:
    try: exec(d, {"__builtins__": {}}, ENV)
    except Exception: pass
def st(cs, to=20000):
    s = z3.Solver(); s.set("timeout", to)
    for c in cs:
        try: s.add(eval(c, {"__builtins__": {}}, ENV))
        except Exception as e: return "parsefail"
    r = s.check()
    return "sat" if r == z3.sat else ("unsat" if r == z3.unsat else "unknown")
sets = {}
for line in fh:
    r = json.loads(line); sets[r["ci"]] = r
rec = {d["ci"]: d for d in json.load(open(os.path.join(HERE, "_p27_recount.json")))}
disputed = sorted(ci for ci in sets
                  if sets[ci]["sat"] - sets[ci]["covered"] > 0
                  and rec[ci]["sat_x"] - rec[ci]["cov_x"] == 0)
agree_rem = sorted(ci for ci in sets if rec[ci]["sat_x"] - rec[ci]["cov_x"] > 0)
random.seed(20260913)
print(f"disputed sets (census remaining>0, exact remaining=0): {len(disputed)}")
out = {"disputed": [], "control": []}
for lab, pool, n in (("disputed", disputed, len(disputed)),
                     ("control", random.sample(agree_rem, 25), 25)):
    ok = {}
    for ci in pool[:n]:
        s = sets[ci]
        fixed = list(H["fixed_base"]) + [_outcome_constraint(e, H["pinned"][e])
                                         for e in s["group"] if e in H["pinned"]]
        blocks = []
        seen = set()
        for g in s["groups"]:
            for o in g["obs"]:
                k = tuple(sorted(o.items()))
                if k in seen: continue
                seen.add(k)
                blocks.append(_block_constraint(k))
        v = st(fixed + blocks)
        ok[v] = ok.get(v, 0) + 1
        out[lab].append([ci, s["width"], s["sat"] - s["covered"],
                         rec[ci]["sat_x"] - rec[ci]["cov_x"], v])
    print(f"  {lab}: {len(pool[:n])} sets -> " +
          ", ".join(f"{k}={v}" for k, v in sorted(ok.items())))
json.dump(out, open(os.path.join(HERE, "_p27_setq.json"), "w"), indent=1)
print("\n  first 12 disputed:")
print(f"   {'set':>5} {'w':>3} {'rem(prod)':>9} {'rem(exact)':>10}  checker-16d-query")
for r in out["disputed"][:12]:
    print(f"   {r[0]:>5} {r[1]:>3} {r[2]:>9} {r[3]:>10}  {r[4]}")
print("P27-SETQ-DONE")
