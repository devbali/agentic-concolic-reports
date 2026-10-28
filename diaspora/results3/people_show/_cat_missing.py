#!/usr/bin/env python3
"""Categorize the missing items from coverage_summary.json (current run)."""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(HERE, "coverage_summary.json")) as f:
    data = json.load(f)

missing = data.get("missing", [])
print("TOTAL MISSING:", len(missing))

# Categorize by which len-vars appear in the node constraint
records_pat = re.compile(r"SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_\d+(?:_rows)?")
toa_pat = re.compile(r"SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_a_\d+(?:_rows)?")

cat = {}
for i, m in enumerate(missing):
    node = m.get("node_constraint", "")
    recs = sorted(set(records_pat.findall(node)))
    toas = sorted(set(toa_pat.findall(node)))
    key = (tuple(recs), tuple(toas))
    cat.setdefault(key, []).append(i)

for (recs, toas), items in sorted(cat.items(), key=lambda kv: -len(kv[1])):
    print(f"\n[{len(items)} items] REC={recs} TOA={toas}")
    sample = missing[items[0]]["node_constraint"][:280]
    print("  sample:", sample)

# Also count purely guard×via_user-ish items (no len vars at all)
nolen = [i for i, m in enumerate(missing)
         if not records_pat.search(m.get("node_constraint", ""))
         and not toa_pat.search(m.get("node_constraint", ""))]
print("\n\nItems with NO len-vars:", len(nolen))
for i in nolen[:12]:
    print(f"  [{i}]", missing[i]["node_constraint"][:200])