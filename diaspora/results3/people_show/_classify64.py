#!/usr/bin/env python3
"""Classify the 64 missing items: cross-format (bare records + rows),
guard-foreclosed (nf1/ca1 x stream), or within-format deep conjunctions."""
import json
import os
import re

HERE = "/home/dev/project/reports/diaspora/results3/people_show"
with open(os.path.join(HERE, "coverage_summary.json")) as f:
    d = json.load(f)
missing = d.get("missing", [])

bare_rec = re.compile(r"Not\(\(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_[12] != 0\)\)")
rows_rec = re.compile(r"\(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_(?:records_\d+_rows|to_a_\d+_rows) [>!]=? 0\)")
guard_t = re.compile(r"\((?:SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found|SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account|SYM_PERSON_via_user_closed_account) == True\)")
stream_row = re.compile(r"SYM_RESULT_ActiveRecord__Relation_to_a_1_row_")

cats = {"cross_format": 0, "guard_x_stream": 0, "within_format_deep": 0}
samples = {}
for i, m in enumerate(missing):
    nc = m.get("node_constraint", "")
    has_bare = bool(bare_rec.search(nc))
    has_rows = bool(rows_rec.search(nc))
    has_guard = bool(guard_t.search(nc))
    has_row_attr = bool(stream_row.search(nc))
    if has_bare and has_rows:
        c = "cross_format"
    elif has_guard and (has_rows or has_row_attr):
        c = "guard_x_stream"
    else:
        c = "within_format_deep"
    cats[c] += 1
    samples.setdefault(c, (i, nc))

print("categories:", cats)
for c, (i, nc) in samples.items():
    print(f"\n--- {c} sample (item {i}) ---")
    print(nc[:400])