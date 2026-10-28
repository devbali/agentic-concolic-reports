#!/usr/bin/env python3
"""Print the NOTE MULTISET of a probe dump set (wildcarded), one line per
distinct shape with its count. Used as the X7 ground-truth differential."""
import glob, json, os, re, sys
from collections import Counter

def wc(s):
    s = re.sub(r"\$\$\([^)]*\)", "?", s)
    s = re.sub(r"'[^']*'", "'?'", s)
    return re.sub(r"\b\d+\b", "?", s)

d = sys.argv[1]
c = Counter()
n_dumps = 0
for f in sorted(glob.glob(os.path.join(d, "dump_*.json"))):
    n_dumps += 1
    j = json.load(open(f))
    for ev in j.get("events") or []:
        if ev.get("type") == "symbolic_call" and ev.get("result_name"):
            note = str(ev.get("note") or "")
            if note.lstrip().upper().startswith(("SELECT","INSERT","UPDATE","DELETE","WITH","REPLACE")):
                c[wc(note)] += 1
print(f"# dumps={n_dumps} distinct_note_shapes={len(c)} total_noted_events={sum(c.values())}")
for k, v in sorted(c.items()):
    print(f"{v}\t{k}")
