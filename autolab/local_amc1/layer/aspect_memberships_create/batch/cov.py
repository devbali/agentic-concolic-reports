import json, sys, collections
from concolic.checks.run import load_runs
from concolic.coverage import CoverageChecker
from concolic.assumptions import validate_declared, AssumptionSet
from concolic.assumptions.registry import lookup
batch = sys.argv[1]; decl = sys.argv[2] if len(sys.argv) > 2 else None
runs = load_runs(batch)
aset = AssumptionSet()
if decl:
    doc = json.load(open(decl))
    rs = validate_declared(doc); assert not rs, rs
    from concolic.assumptions import Assumption
    for r in doc:
        aset.add(lookup(r["type"]).from_dict(r))
res = CoverageChecker(runs, assumptions=aset, max_cliques=200, max_missing_per_clique=50).check_coverage()
print("runs", res.total_runs, "complete", res.complete, "tree_complete", res.tree_complete,
      "missing", len(res.missing), "truncated", res.truncated, "solver_lost", res.solver_lost)
print("tree_missing", list(res.tree_missing)[:10])
out = []
for m in res.missing:
    d = m.__dict__ if hasattr(m, "__dict__") else dict(m)
    out.append({k: (v if isinstance(v,(str,int,float,bool,type(None),list,dict)) else repr(v)) for k, v in d.items()})
json.dump(out, open(sys.argv[3] if len(sys.argv) > 3 else "/tmp/amc_missing.json", "w"), indent=1, default=repr)
