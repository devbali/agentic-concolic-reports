# coverage over a batch dir, with declarations built through the SAME wire check.py uses
import json, sys
from concolic.checks.run import load_runs
from concolic.coverage import CoverageChecker
from concolic.assumptions.declared import declared_assumption_set
batch = sys.argv[1]; decl = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != "-" else None
runs = load_runs(batch)
aset = None
if decl:
    aset, refusals = declared_assumption_set(json.load(open(decl)))
    assert not refusals, refusals
    print("built", len(aset.assumptions))
res = CoverageChecker(runs, assumptions=aset, max_cliques=200, max_missing_per_clique=50).check_coverage()
print("runs", res.total_runs, "complete", res.complete, "tree_complete", res.tree_complete,
      "missing", len(res.missing), "truncated", res.truncated, "solver_lost", res.solver_lost)
print("tree_missing", list(res.tree_missing)[:10])
out = []
for m in res.missing:
    d = m.__dict__ if hasattr(m, "__dict__") else dict(m)
    out.append({k: (v if isinstance(v,(str,int,float,bool,type(None),list,dict)) else repr(v)) for k, v in d.items()})
json.dump(out, open(sys.argv[3] if len(sys.argv) > 3 else "/tmp/amc2_missing.json", "w"), indent=1, default=repr)
