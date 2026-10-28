#!/usr/bin/env python3
"""PRECISE bare-records census: Relation_records_N NOT followed by _row/_rows.

Confound fix: `SYM_RESULT_ActiveRecord__Relation_records_1_row_public` contains
`records_1` followed by `_row` (attribute), and `records_1_rows` followed by
`_rows` (length var). True BARE records case is `records_N` followed by
anything OTHER than `_row`/`_rows` — e.g. the block/contact NullRelation
length expr `(len(SYM_RESULT_ActiveRecord__Relation_records_1) != 0)`, where
records_1 is immediately followed by `)`, ` `, `==`, etc.
"""
import glob
import json
import os
import re
from collections import Counter

HERE = '/home/dev/project/reports/diaspora/results3/people_show'

ROW_RE = re.compile(r"SYM_RESULT_ActiveRecord__Relation_records_(\d+)_rows")
# bare: records_N where the char after N is NOT '_'
BARE_RE = re.compile(r"SYM_RESULT_ActiveRecord__Relation_records_(\d+)(?![_0-9])")

n_dumps = 0
bare_ord_counts = Counter()
bare_with_stream = Counter()
bare_only = 0      # bare records, no stream rows
bare_and_stream = 0
stream_only = 0
both_impossible = 0

for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    n_dumps += 1
    txt = json.dumps(raw)
    row_ords = set(int(m.group(1)) for m in ROW_RE.finditer(txt))
    bare_ords = set(int(m.group(1)) for m in BARE_RE.finditer(txt))
    for b in bare_ords:
        bare_ord_counts[b] += 1
    if bare_ords and row_ords:
        bare_and_stream += 1
        for b in sorted(bare_ords):
            for r in sorted(row_ords):
                bare_with_stream[(b, r)] += 1
    elif bare_ords:
        bare_only += 1
    elif row_ords:
        stream_only += 1
    if 1 in row_ords and 4 in row_ords:
        both_impossible += 1
    if 2 in row_ords and 4 in row_ords:
        both_impossible += 1
    if 1 in row_ords and 5 in row_ords:
        both_impossible += 1

print(f"dumps: {n_dumps}")
print(f"bare-records ordinal counts: {dict(sorted(bare_ord_counts.items()))}")
print(f"bare-only runs: {bare_only}")
print(f"stream-only runs: {stream_only}")
print(f"bare AND stream runs: {bare_and_stream}")
print(f"runs with rows_1&rows_4 / rows_2&rows_4 / rows_1&rows_5 together: {both_impossible}")
print(f"\nbare records_N co-minting with stream rows_M (PRECISE):")
for (b, r), c in sorted(bare_with_stream.items()):
    print(f"  bare_{b} & rows_{r}: {c}")