#!/usr/bin/env python3
"""Compare two diffarm arms: RUNS DIFFERING / VIEWS DIFFERING."""
import json, sys
old, new = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
ov = set(open(sys.argv[1][:-5] + ".views").read().splitlines())
nv = set(open(sys.argv[2][:-5] + ".views").read().splitlines())
keys = set(old["per_run"]) | set(new["per_run"])
runs_diff = [k for k in sorted(keys) if old["per_run"].get(k) != new["per_run"].get(k)]
print(f"{old['corpus'].split('/')[-1]:22s} pop={old['population']:7d} "
      f"sampled={old['sampled']:6d} runs={old['runs']:6d} views={old['views_emitted']:7d} "
      f"distinct={old['distinct_views']:5d}  RUNS DIFFERING={len(runs_diff):6d}  "
      f"VIEWS DIFFERING={len(ov ^ nv):6d}  exc old/new={old['transform_exceptions']}/{new['transform_exceptions']}")
if runs_diff[:3]:
    print("   e.g.", runs_diff[:3])
    for k in runs_diff[:2]:
        print("     old", old["per_run"].get(k), "new", new["per_run"].get(k))
for f in sorted(set(old["flags"]) | set(new["flags"])):
    if old["flags"].get(f) != new["flags"].get(f):
        print(f"   FLAG DIFF {f}: old={old['flags'].get(f)} new={new['flags'].get(f)}")
