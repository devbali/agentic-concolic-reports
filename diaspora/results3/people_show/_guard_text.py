#!/usr/bin/env python3
"""Inspect the raw expr text of guard-family PCs + the exact node_constraint
form of missing-item guard conjuncts, to fix the witness matcher."""
import glob
import json
import os
import re

HERE = '/home/dev/project/reports/diaspora/results3/people_show'

# 1. What does a first_1_not_found event look like in a dump?
cnt = 0
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json')))[:2000]:
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    for ev in raw.get("events", []):
        expr = str(ev.get("expr", ""))
        if "first_1_not_found" in expr:
            print(f"DUMP EVENT: taken={ev.get('taken')} expr={expr!r}")
            cnt += 1
            if cnt >= 3:
                break
    if cnt >= 3:
        break
print(f"(sampled {cnt} first_1_not_found events)")

# 2. The missing item's guard conjuncts verbatim
data = json.load(open(os.path.join(HERE, 'coverage_summary_live.json')))
for it in data['missing'][:1]:
    for conj in it['node_constraint'].split(" AND "):
        if "not_found" in conj or "closed_account" in conj:
            print(f"MISSING CONJ: {conj!r}")

# 3. The decl name used for that var
sys_ = "/home/dev/project/src"
import sys
sys.path.insert(0, sys_)
from concolic_engine.run import Run  # noqa: E402
_LEN_RE = re.compile(r"len\(([^()]+)\)")
fixed = json.loads(_LEN_RE.sub(r"SYM_LEN_\1", json.dumps(json.load(open(glob.glob(os.path.join(HERE, 'dump_*.json'))[0])))))
run = Run.from_dict(fixed)
for d in run.z3_declarations():
    if "first_1_not_found" in d:
        print(f"DECL: {d}")