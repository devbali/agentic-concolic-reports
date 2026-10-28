#!/usr/bin/env python3
"""What guid-family expr texts are in the RUN corpus (pc.expr after fix_len_names)?"""
import glob
import json
import os
import re
import sys
import collections

HERE = '/home/dev/project/reports/diaspora/results3/people_show'
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run  # noqa: E402

_LEN_RE = re.compile(r"len\(([^()]+)\)")


def fix_len_names(dump: dict) -> dict:
    return json.loads(_LEN_RE.sub(r"SYM_LEN_\1", json.dumps(dump)))


forms = collections.Counter()
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
        run = Run.from_dict(fix_len_names(raw))
    except Exception:
        continue
    for pc in run.path_conditions:
        if "author_guid" in pc.expr or "first_2_guid" in pc.expr:
            forms[(pc.expr, bool(pc.taken))] += 1

print("guid-family PC forms across corpus:")
for (expr, taken), c in sorted(forms.items(), key=lambda kv: -kv[1])[:20]:
    print(f"  {c:6d}  taken={taken}  {expr[:120]}")