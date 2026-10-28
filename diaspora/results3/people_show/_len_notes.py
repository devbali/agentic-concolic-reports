#!/usr/bin/env python3
"""Check the SELECT notes attached to the len vars in mobile vs non-mobile dumps."""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
files = sorted(f for f in os.listdir(HERE) if f.startswith("dump_") and f.endswith(".json"))

LEN_RE = re.compile(r"len\(([^)]+)\)")

# For each len var name, collect its note (SELECT) across dumps
notes = {}
for f in files:
    try:
        d = json.load(open(os.path.join(HERE, f)))
    except Exception:
        continue
    for v in d.get("symbolic_vars", []):
        name = v.get("name", "")
        m = LEN_RE.match(name)
        if not m:
            continue
        var = m.group(1)
        note = v.get("note", "") or ""
        # normalize: collapse numbers in FROM "..." / IN (...) into <N>
        note_n = re.sub(r'"\w+"\.\w+@@\d+', '"X".Y@@N', note)
        notes.setdefault(var, set()).add(note_n[:120])

for var in sorted(notes):
    print(f"=== {var}")
    for n in sorted(notes[var])[:4]:
        print("   ", n)