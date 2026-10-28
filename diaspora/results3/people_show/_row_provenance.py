#!/usr/bin/env python3
"""Identify what the five rows ordinals + to_a correspond to (app source).

For each ordinal family, grab the symbolic_vars entries (name/value/note)
from dumps that carry that ordinal, to see the SQL note / source call site.
"""
import glob
import json
import os
import re

HERE = '/home/dev/project/reports/diaspora/results3/people_show'
_LEN_RE = re.compile(r"len\(([^()]+)\)")

TARGETS = {
    "rows_1": "SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1_rows",
    "rows_2": "SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2_rows",
    "rows_3": "SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_3_rows",
    "rows_4": "SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_4_rows",
    "rows_5": "SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_5_rows",
    "to_a_1": "SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_a_1_rows",
}

seen = {k: set() for k in TARGETS}
notes = {k: set() for k in TARGETS}

for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    fixed = _LEN_RE.sub(r"SYM_LEN_\1", json.dumps(raw))
    for k, name in TARGETS.items():
        if name in fixed:
            # find the symbolic_var entry and its note
            for sv in raw.get("symbolic_vars", []):
                if sv.get("name") == name or sv.get("name", "").replace("SYM_LEN_", "len(") == name:
                    note = sv.get("note", "")
                    val = sv.get("value")
                    if note:
                        notes[k].add(str(note)[:120])
                    if val is not None:
                        seen[k].add(str(val)[:60])

print("=== rows/to_a ordinal provenance (symbolic_vars notes + values) ===")
for k in TARGETS:
    print(f"\n--- {k} ({TARGETS[k]}) ---")
    for n in sorted(notes[k])[:4]:
        print(f"   note: {n}")
    for v in sorted(seen[k])[:4]:
        print(f"   values: {v}")