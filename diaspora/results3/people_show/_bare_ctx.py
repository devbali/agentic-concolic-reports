#!/usr/bin/env python3
"""Find which run records bare Relation_records_1 len and show its context."""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
files = sorted(f for f in os.listdir(HERE) if f.startswith("dump_") and f.endswith(".json"))

LEN_RE = re.compile(r"len\(([^)]+)\)")

count = 0
for f in files:
    d = json.load(open(os.path.join(HERE, f)))
    names = set()
    for v in d.get("symbolic_vars", []):
        m = LEN_RE.match(v.get("name", ""))
        if m:
            names.add(m.group(1))
    if any(n == "SYM_RESULT_ActiveRecord__Relation_records_1" or n == "SYM_RESULT_ActiveRecord__Relation_records_2" for n in names):
        count += 1
        if count <= 2:
            print(f"===== {f}")
            print("  scenario:", d.get("scenario"), "| format:", d.get("format"))
            # show all len vars with notes
            for v in d.get("symbolic_vars", []):
                m = LEN_RE.match(v.get("name", ""))
                if m:
                    print(f"   LEN {m.group(1)}")
                    print(f"       note={v.get('note', '')[:110]!r}")
                    print(f"       value={v.get('value')} concrete_len={v.get('concrete_length')}")
            # find exprs mentioning records_1/records_2
            for pc in d.get("path_conditions", [])[:200]:
                e = pc.get("expr", "")
                if "records_1" in e or "records_2" in e:
                    print(f"   PC: {e[:200]}")
        if count >= 2:
            break

print("runs recording bare records_1/records_2:", count)