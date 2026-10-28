#!/usr/bin/env python3
"""Debug witness check on 16-family item 0 with exact pc.expr matching."""
import glob
import json
import os
import re
import sys

HERE = '/home/dev/project/reports/diaspora/results3/people_show'
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run  # noqa: E402

_LEN_RE = re.compile(r"len\(([^()]+)\)")


def fix_len_names(dump: dict) -> dict:
    return json.loads(_LEN_RE.sub(r"SYM_LEN_\1", json.dumps(dump)))


data = json.load(open(os.path.join(HERE, 'coverage_summary_live.json')))
missing = data['missing']
ROW_RE = re.compile(r"Relation_records_(\d+)_rows")
fam16 = [it for it in missing
         if set(int(m.group(1)) for m in ROW_RE.finditer(it['node_constraint'])) == {4, 5}]
it = fam16[0]
nc = it['node_constraint']
conjs = [c.strip() for c in nc.split(" AND ")]
print(f"item has {len(conjs)} conjuncts")

# Build run_exprs keyed by RAW pc.expr text (post len-rename)
run_exprs = []
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
        run = Run.from_dict(fix_len_names(raw))
    except Exception:
        continue
    outs = {}
    for pc in run.path_conditions:
        outs.setdefault(pc.expr, set()).add(bool(pc.taken))
    run_exprs.append(outs)
print(f"runs: {len(run_exprs)}")

# global T/F per RAW expr
import collections
cov = collections.defaultdict(lambda: [0, 0])
for ro in run_exprs:
    for e, ts in ro.items():
        if True in ts:
            cov[e][0] += 1
        if False in ts:
            cov[e][1] += 1

print("\nPer-conjunct coverage (raw expr form):")
for conj in conjs:
    if conj.startswith("Not(") and conj.endswith(")"):
        inner = conj[4:-1]
        t, f = cov.get(inner, [0, 0])
        print(f"  needs NOT({inner[:90]}) -> raw T={t} F={f} {'OK' if f else 'BLOCK'}")
    else:
        t, f = cov.get(conj, [0, 0])
        print(f"  needs {conj[:90]} -> raw T={t} F={f} {'OK' if t else 'BLOCK'}")