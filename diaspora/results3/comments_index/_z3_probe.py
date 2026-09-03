import sys,glob,json,time,collections,os
sys.path.insert(0,'/home/dev/project/src'); sys.path.insert(0,'/home/dev/project/reports/diaspora/results3/comments_index')
from concolic_engine.run import Run
from concolic_engine import coverage as cov, solver
import coverage_report as cr, coverage_assumptions as ca
LOG=open('/home/dev/project/reports/diaspora/results3/comments_index/_z3_probe.log','w')
orig=solver.check_satisfiability
stats=collections.Counter(); tot=[0.0,0]
def wrapped(constraints, decls, timeout_ms=5000):
    t=time.time(); r=orig(constraints, decls, timeout_ms); dt=time.time()-t
    tot[0]+=dt; tot[1]+=1
    strs=sum(1 for c in constraints if "StringVal" in c or "Length(" in c or "== ''" in c)
    LOG.write(f"{dt:.2f}s n_constraints={len(constraints)} string_constraints={strs} sat={r.satisfiable} first={constraints[-1][:90] if constraints else ''}\n"); LOG.flush()
    return r
cov.check_satisfiability=wrapped
runs=[cr.share_run_objects(cr.apply_len_bounds(Run.from_dict(cr.fix_len_names(json.load(open(p)))))) for p in glob.glob('/home/dev/project/reports/diaspora/results3/comments_index/dump_*.json')]
LOG.write(f"loaded {len(runs)}\n"); LOG.flush()
res=cov.CoverageChecker(runs, assumptions=ca.build(runs), max_missing_per_clique=4).check_coverage()
LOG.write(f"DONE complete={res.complete} missing={len(res.missing)} truncated={res.truncated} solver_lost={res.solver_lost} queries={tot[1]} z3_time={tot[0]:.0f}s\n"); LOG.flush()
json.dump([{"node_constraint":m.node_constraint,"concrete_values":m.concrete_values} for m in res.missing], open('/home/dev/project/reports/diaspora/results3/comments_index/_probe_missing.json','w'))
