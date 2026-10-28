#!/usr/bin/env python3
"""P29 — verify the RENDER_TEXT_SOURCE declaration against the ENGINE'S OWN
solver before any pass (the check §79.1 ran for RENDER_IDENTITY):
the two AGREEING assignments must stay SAT, the two DISAGREEING ones must go
UNSAT, and the declaration must not make anything else unevaluable.
"""
import glob, json, logging, os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
logging.getLogger("concolic_engine.solver").setLevel(logging.ERROR)
from concolic_engine.run import Run
from concolic_engine.coverage import CoverageChecker
from concolic_engine.solver import check_satisfiability
import coverage_report as CR
import coverage_assumptions as CA

lst = os.environ.get("DUMP_LIST", HERE + "/_snapshot_pruned_P26F2.txt")
paths = [l.strip() for l in open(lst) if l.strip()]
random.seed(29)
paths = random.sample(paths, int(os.environ.get("N", "400")))
runs = []
for p in paths:
    raw = json.load(open(p))
    CR.canonicalize_ordinals(raw)
    runs.append(CR.share_run_objects(Run.from_dict(CR.fix_len_names(raw))))
print("runs", len(runs))
aset = CA.build(runs)
ck = CoverageChecker(runs, assumptions=aset)
decls = ck._merged_declarations()
extra = aset.symbolic_constraints()
print("symbolic constraints declared:", len(extra))
for e in extra:
    print("   ", e)

R = "(SYM_RESULT_Anonymous_process_3 == '')"
R2 = "(SYM_RESULT_Anonymous_process_2 == '')"
for V in CA._RTS_ACT:
    A = f"({V}_text_empty == True)"
    print("\n===", V)
    for r in (True, False):
        for a in (True, False):
            cl = [R if r else f"Not({R})", A if a else f"Not({A})"]
            with_c = check_satisfiability(list(extra) + cl, decls, 20000)
            no_c = check_satisfiability(cl, decls, 20000)
            print("   render=%-5s act_text_empty=%-5s  WITH declaration %-6s  "
                  "WITHOUT %-6s  %s"
                  % (r, a, "SAT" if with_c.satisfiable else "UNSAT",
                     "SAT" if no_c.satisfiable else "UNSAT",
                     "expected" if (with_c.satisfiable == (r == a)) else "*** UNEXPECTED ***"))
# render identity still holds
print("\nRENDER_IDENTITY interaction (process_2 vs process_3):")
for a in (True, False):
    for b in (True, False):
        cl = [R2 if a else f"Not({R2})", R if b else f"Not({R})"]
        s = check_satisfiability(list(extra) + cl, decls, 20000)
        print("   p2=%-5s p3=%-5s -> %s" % (a, b, "SAT" if s.satisfiable else "UNSAT"))
# nothing became unevaluable: every corpus decision must still be a tautology-SAT
bad = []
exprs = sorted({pc.expr for r in runs for pc in r.path_conditions})
for e in exprs:
    pr = check_satisfiability(list(extra) + [f"Or({e}, Not({e}))"], decls, 20000)
    if not pr.satisfiable:
        bad.append(e)
print("\ncorpus decisions in this sample: %d   made UNEVALUABLE by the declaration: %d"
      % (len(exprs), len(bad)))
for b in bad[:10]:
    print("   ", b)
print("P29-SOLVER-CHECK-DONE")
