#!/usr/bin/env python3
"""Classify the 64 missing items by stream-ordinal demand.

- FIVE-ORDINAL items (demand rows at ordinals 1,2,3 AND 4,5+ etc.):
  unwitnessable — no run mints >3 stream ordinals. → proof path.
- DUAL-only items (demand rows only at dual-shape ordinals 3,4,5 /
  4,5): potentially reachable with more dual runs. → campaign path.
- Other shapes.

For each item extract the set of records_N_rows ordinals demanded (positive
side — i.e. the ordinal simply appears in the conjunction, regardless of
Not() wrapper) and the set of bare records_N ordinals.
"""
import json
import re
from collections import Counter

data = json.load(open('/home/dev/project/reports/diaspora/results3/people_show/coverage_summary.json'))
missing = data['missing']

ROW_RE = re.compile(r"Relation_records_(\d+)_rows")
BARE_RE = re.compile(r"Relation_records_(\d+)(?![_0-9])")

classes = Counter()
examples = {}
items_by_class = {}

for it in missing:
    nc = it['node_constraint']
    row_ords = set(int(m.group(1)) for m in ROW_RE.finditer(nc))
    bare_ords = set(int(m.group(1)) for m in BARE_RE.finditer(nc))
    n = len(row_ords)
    if n >= 5:
        cls = "FIVE+_ORDINALS (unwitnessable)"
    elif n == 4:
        cls = "FOUR_ORDINALS"
    elif n == 3 and row_ords == {3, 4, 5}:
        cls = "DUAL_3_4_5 (reachable?)"
    elif n == 3:
        cls = "THREE_OTHER"
    elif n == 2 and row_ords == {4, 5}:
        cls = "DUAL_4_5 (reachable?)"
    elif n == 2:
        cls = "TWO_OTHER"
    elif n == 1:
        cls = "ONE_ORDINAL"
    else:
        cls = "NO_STREAM_ORDINAL"
    classes[cls] += 1
    items_by_class.setdefault(cls, []).append((row_ords, bare_ords))
    if cls not in examples:
        examples[cls] = (sorted(row_ords), sorted(bare_ords))

print("=== 64 missing items by stream-ordinal demand ===")
for cls, c in classes.most_common():
    print(f"  [{c:3d}] {cls}   e.g. rows={examples[cls][0]} bare={examples[cls][1]}")
    for row_ords, bare_ords in items_by_class[cls][:3]:
        print(f"         rows={sorted(row_ords)} bare={sorted(bare_ords)}")