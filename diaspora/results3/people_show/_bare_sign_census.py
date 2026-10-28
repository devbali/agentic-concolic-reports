#!/usr/bin/env python3
"""Sign census of bare records_N conjuncts in dual dumps."""
import glob
import json
import re
import os
from collections import Counter

HERE = '/home/dev/project/reports/diaspora/results3/people_show'
_LEN_RE = re.compile(r"len\(([^()]+)\)")
BARE_RE = re.compile(r"Not\(\(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_(\d+)\s*(==|!=)\s*(\d+)\)\)|(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_(\d+)\s*(==|!=)\s*(\d+))")

sign_counter = Counter()
detail = Counter()

for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    fixed = _LEN_RE.sub(r"SYM_LEN_\1", json.dumps(raw))
    for m in BARE_RE.finditer(fixed):
        if m.group(1):  # Not((...)) form
            n, op, v = m.group(1), m.group(2), m.group(3)
            sign = f"Not(records_{n}{op}{v})"
        else:
            n, op, v = m.group(5), m.group(6), m.group(7)
            sign = f"records_{n}{op}{v}"
        sign_counter[sign] += 1

print("=== bare records_N conjunct signs across ALL dumps ===")
for sign, c in sign_counter.most_common(20):
    print(f"  [{c:5d}] {sign}")