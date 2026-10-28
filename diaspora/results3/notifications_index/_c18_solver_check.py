#!/usr/bin/env python3
"""C18 — verify the two new declarations WITH THE ENGINE'S OWN SOLVER before
spending a pass (the RENDER_IDENTITY / §79 precedent).

  1. every declared constraint PARSES against the merged declarations
     (an unparseable one makes EVERY query unsat, which looks like
     completeness -- M-SNAP's stated failure mode);
  2. the 24 re-mint witness leaves and the 28 A = 0 witness leaves become
     UNSAT with the tier on and are SAT with it off;
  3. a leaf the corpus HAS covered stays SAT, and no OBSERVED cube is made
     unsat.

  usage: [SAMPLE=4000] python3 -u _c18_solver_check.py
"""
import json, os, random, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from coverage_report import (canonicalize_ordinals, apply_len_bounds,   # noqa: E402
                             fix_len_names, share_run_objects)
from concolic_engine.run import Run                                     # noqa: E402
from concolic_engine.solver import check_satisfiability                 # noqa: E402
import coverage_assumptions as CA                                       # noqa: E402

N = int(os.environ.get("SAMPLE", "4000"))
files = [l.strip() for l in open(os.path.join(HERE, "_snapshot_c16_R2.txt")) if l.strip()]
random.seed(1813); files = random.sample(files, min(N, len(files)))
runs = []
for p in files:
    try:
        raw = json.load(open(p))
        canonicalize_ordinals(raw)
        runs.append(share_run_objects(apply_len_bounds(Run.from_dict(fix_len_names(raw)))))
    except Exception:
        pass
print(f"runs loaded: {len(runs)}", flush=True)

decls, seen = [], set()
for r in runs:
    for d in r.z3_declarations():
        n = d.split("=", 1)[0].strip()
        if n not in seen:
            seen.add(n); decls.append(d)
print(f"merged declarations: {len(decls)}", flush=True)

aset = CA.build(runs)
cons = aset.symbolic_constraints()
new = [c for c in cons if "SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_ary" in c
       and " == SYM_LEN_" in c] + [c for c in cons if c.startswith("Or(SYM_NOTE_TYPE_PROFILE")]
print(f"symbolic constraints total {len(cons)}; C18 tiers {len(new)}")
bad = []
for c in cons:
    if not check_satisfiability([c], decls, 5000).satisfiable:
        bad.append(c)
print(f"constraints that do NOT parse / are self-unsat: {len(bad)}")
for c in bad[:10]:
    print("   BAD", c)
print(f"all constraints TOGETHER satisfiable: "
      f"{check_satisfiability(list(cons), decls, 20000).satisfiable}")

res = json.load(open(os.path.join(HERE, "_c16_residue.json")))["leaves"]
def cls(x):
    if x["A0_at_gate_conjunction"]:
        return "A0"
    if x["rule_T_members"] > 0:
        return "remintRT"
    return "open"
tally = Counter()
for x in res:
    cube = [(f"Not({k['expr']})" if not k["outcome"] else k["expr"]) for k in x["keys"]]
    off = check_satisfiability(cube, decls, 20000).satisfiable
    on = check_satisfiability(cube + list(cons), decls, 20000).satisfiable
    tally[(cls(x), "SAT" if off else "unsat", "SAT" if on else "unsat")] += 1
print("\nwitness leaves: class, WITHOUT the declarations, WITH them")
for k, n in sorted(tally.items()):
    print(f"   {n:4d}  {k[0]:9s}  off={k[1]:5s}  on={k[2]}")

# no OBSERVED profile may be made unsat: sample real runs' own cubes
obs = 0; killed = 0
for r in random.sample(runs, min(300, len(runs))):
    lits = {}
    for pc in r.path_conditions:
        lits[pc.expr] = bool(pc.taken)
    cube = [e if t else f"Not({e})" for e, t in list(lits.items())[:40]]
    if not cube:
        continue
    obs += 1
    if not check_satisfiability(cube + list(cons), decls, 20000).satisfiable:
        killed += 1
print(f"\nobserved run cubes checked {obs}; made UNSAT by the declarations: {killed}")
print("C18-SOLVER-CHECK-DONE")
