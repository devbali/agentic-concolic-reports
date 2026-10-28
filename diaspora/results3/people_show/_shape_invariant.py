#!/usr/bin/env python3
"""EMPIRICAL PROOF of the ordinal-shape invariant across the whole corpus.

1. Max distinct records_N_rows ordinals per run (expect: 3).
2. Co-occurrence matrix: which row ordinals appear together in a run.
3. The killer: do ANY dumps contain records_1_rows AND records_4_rows
   together (demanding both shapes in one run)? Expect 0.
   Same for records_2_rows AND records_4_rows, records_1_rows AND
   records_5_rows, etc.
4. Also: bare records_N (no _rows) co-occurrence with stream ordinals.
"""
import glob
import json
import os
import re
from collections import Counter

HERE = '/home/dev/project/reports/diaspora/results3/people_show'

ROW_RE = re.compile(r"SYM_RESULT_ActiveRecord__Relation_records_(\d+)_rows")
BARE_RE = re.compile(r"SYM_RESULT_ActiveRecord__Relation_records_(\d+)[^_]")

max_ord = 0
ord_counts = Counter()
co_occur = Counter()
bare_with_stream = Counter()
dual_shape = 0      # bare records AND stream in same run
mobile_shape = 0    # stream, no bare
both_shapes = 0     # impossible check: records_1_rows AND records_4_rows together

n_dumps = 0
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    n_dumps += 1
    txt = json.dumps(raw)
    row_ords = set(int(m.group(1)) for m in ROW_RE.finditer(txt))
    bare_ords = set(int(m.group(1)) for m in BARE_RE.finditer(txt) if not txt[m.start():m.end()+10].startswith("SYM_RESULT_ActiveRecord__Relation_records_" + m.group(1) + "_rows"))
    # simpler: bare = records_N NOT followed by _rows
    bare_ords = set()
    for m in BARE_RE.finditer(txt):
        after = txt[m.end():m.end()+6]
        if not after.startswith("_rows"):
            bare_ords.add(int(m.group(1)))
    if len(row_ords) > max_ord:
        max_ord = len(row_ords)
        max_example = os.path.basename(p)
    ord_counts[len(row_ords)] += 1
    for o1 in row_ords:
        for o2 in row_ords:
            if o1 < o2:
                co_occur[(o1, o2)] += 1
    if bare_ords and row_ords:
        dual_shape += 1
        for b in sorted(bare_ords):
            for r in sorted(row_ords):
                bare_with_stream[(b, r)] += 1
    elif row_ords and not bare_ords:
        mobile_shape += 1
    if 1 in row_ords and 4 in row_ords:
        both_shapes += 1
    if 2 in row_ords and 4 in row_ords:
        both_shapes += 1
    if 1 in row_ords and 5 in row_ords:
        both_shapes += 1

print(f"dumps: {n_dumps}")
print(f"max distinct stream-row ordinals in one run: {max_ord} (in {max_example})")
print(f"distribution of #stream-row-ordinals per run: {dict(sorted(ord_counts.items()))}")
print(f"\nmobile-shape runs (stream, no bare records): {mobile_shape}")
print(f"dual-shape runs (bare records AND stream):    {dual_shape}")
print(f"runs containing BOTH records_1_rows and records_4_rows (impossible-shape): {both_shapes}")

print(f"\nco-occurrence of stream-row ordinals (pair: #runs):")
for (a, b), c in sorted(co_occur.items()):
    print(f"  rows_{a} & rows_{b}: {c}")
print(f"\nbare records_N co-minting with stream rows_M:")
for (b, r), c in sorted(bare_with_stream.items()):
    print(f"  bare_{b} & rows_{r}: {c}")