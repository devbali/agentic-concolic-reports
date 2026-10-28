#!/usr/bin/env python3
"""Corpus census (FIXED: applies fix_len_names like the checker does).

For every dump, apply the checker's exact rename
len(X) -> SYM_LEN_X over a json round-trip, then count:
- bare records_N conjuncts (SYM_LEN_..._records_N ==/!= val) — from events
- rows_N (SYM_LEN_..._records_N_rows)
- to_a_N (SYM_LEN_..._to_a_N_rows)
and report which ordinal pairs co-mint in single dumps.
"""
import glob
import json
import re
import os
from collections import Counter

HERE = '/home/dev/project/reports/diaspora/results3/people_show'
_LEN_RE = re.compile(r"len\(([^()]+)\)")

BARE_RE = re.compile(r"SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_(\d+)\s*(==|!=)\s*(\d+)")
ROWS_RE = re.compile(r"SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_(\d+)_rows\s*(>|==|!=)\s*(\d+)")
TOA_RE  = re.compile(r"SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_a_(\d+)_rows\s*(>|==|!=)\s*(\d+)")

dumps = sorted(glob.glob(os.path.join(HERE, 'dump_*.json')))
print(f"dumps: {len(dumps)}")

co_bare_rows = Counter()
has_bare = has_rows = has_toa = dual_found = 0
same_n_exact = Counter()

for p in dumps:
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    txt = json.dumps(raw)
    fixed = _LEN_RE.sub(r"SYM_LEN_\1", txt)

    bares = set((int(m.group(1)), m.group(2), m.group(3)) for m in BARE_RE.finditer(fixed))
    rows = set((int(m.group(1)), m.group(2), m.group(3)) for m in ROWS_RE.finditer(fixed))
    toas = set((int(m.group(1)), m.group(2), m.group(3)) for m in TOA_RE.finditer(fixed))
    if bares:
        has_bare += 1
    if rows:
        has_rows += 1
    if toas:
        has_toa += 1
    if bares and (rows or toas):
        dual_found += 1
        zero_bare = {n for n, op, v in bares if op == "==" and v == "0"}
        pos_rows = {n for n, op, v in rows if op == ">" and int(v) > 0}
        pos_toa = {n for n, op, v in toas if op in (">", "!=") and v != "0"}
        for n in zero_bare:
            for m in pos_rows:
                co_bare_rows[(n, m)] += 1
                if n == m:
                    same_n_exact[(n, m)] += 1
            for m in pos_toa:
                co_bare_rows[(n, m)] += 1
                if n == m:
                    same_n_exact[(n, m)] += 1

print(f"dumps with bare records_N: {has_bare}")
print(f"dumps with rows_N:         {has_rows}")
print(f"dumps with to_a_N:         {has_toa}")
print(f"dumps with BOTH bare AND rows/to_a: {dual_found}")
print(f"\nco-mint pairs (records_N==0 with rows_M>0 / to_a_M>0):")
for (n, m), c in sorted(co_bare_rows.items()):
    print(f"  records_{n}==0 ∧ rows_{m}>0: {c} dumps")
print(f"\nSAME-N pairs (missing items' demand: records_N==0 ∧ rows_N>0):")
for (n, m), c in sorted(same_n_exact.items()):
    print(f"  records_{n}==0 ∧ rows_{n}>0: {c} dumps")