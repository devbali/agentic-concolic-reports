#!/usr/bin/env python3
"""Show the actual PC expr texts involving via_user / handle / rows len vars."""
import json
import os

HERE = "/home/dev/project/reports/diaspora/results3/people_show"
files = sorted(f for f in os.listdir(HERE) if f.startswith("dump_") and f.endswith(".json"))

seen = set()
shown = 0
for f in files:
    if "mobile" not in f:
        continue
    try:
        d = json.load(open(os.path.join(HERE, f)))
    except Exception:
        continue
    for pc in d.get("events", []):
        if pc.get("type") != "path_condition":
            continue
        e = pc.get("expr", "")
        if not e or e in seen:
            continue
        if ("via_user" in e) or ("records_1_rows" in e) or ("to_a_1_rows" in e) or ("first_1" in e and "handle" in e):
            seen.add(e)
            shown += 1
            if shown <= 24:
                print(f"[{d.get('label','?')}] {e[:160]}")
print("total distinct matching exprs:", shown)