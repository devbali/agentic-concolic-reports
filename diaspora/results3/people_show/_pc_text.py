#!/usr/bin/env python3
"""Print raw pc.expr text for guard-family PCs as seen by the checker's Run."""
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


# first dump with first_2_not_found
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    txt = json.dumps(raw)
    if "first_2_not_found" not in txt:
        continue
    run = Run.from_dict(fix_len_names(raw))
    for pc in run.path_conditions:
        if "first_2_not_found" in pc.expr or "first_1_not_found" in pc.expr:
            print(f"pc.expr={pc.expr!r} taken={pc.taken}")
    break

# Now the exact node_constraint form for the same expr in missing items
data = json.load(open(os.path.join(HERE, 'coverage_summary_live.json')))
for it in data['missing'][:2]:
    for conj in it['node_constraint'].split(" AND "):
        if "first_2_not_found" in conj or "first_1_not_found" in conj:
            print(f"item conj: {conj!r}")