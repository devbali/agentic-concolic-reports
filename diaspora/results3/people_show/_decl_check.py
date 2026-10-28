#!/usr/bin/env python3
"""Compare z3 declarations between old corpus era and current drain corpus.

Q: does the drain corpus declare SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1_rows?
   what len(...)-family names DOES it declare?
"""
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


dumps = sorted(os.path.join(HERE, f) for f in os.listdir(HERE)
               if f.startswith("dump_") and f.endswith(".json"))
print(f"dumps: {len(dumps)}")

runs = []
for p in dumps:
    try:
        raw = json.load(open(p))
        runs.append(Run.from_dict(fix_len_names(raw)))
    except Exception as e:
        print(f"skip {os.path.basename(p)}: {e}")

# union of declarations
decls = []
seen = set()
len_decls = []
for run in runs:
    for d in run.z3_declarations():
        name = d.split("=", 1)[0].strip()
        if name in seen:
            continue
        seen.add(name)
        decls.append(d)
        if "SYM_LEN_" in name or "records" in name or "rows" in name:
            len_decls.append(d)

print(f"total decls: {len(decls)}")
print(f"records/rows/len decls ({len(len_decls)}):")
for d in sorted(len_decls)[:40]:
    print("  ", d)

# specifically check the 4 names the 6b constraints use
wanted = [
    "SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1_rows",
    "SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_a_1_rows",
    "SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2_rows",
    "SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_3_rows",
    "SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_4_rows",
    "SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_5_rows",
]
for w in wanted:
    print(f"  declared? {w}: {w in seen}")