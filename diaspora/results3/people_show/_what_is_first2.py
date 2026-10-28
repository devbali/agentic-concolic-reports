#!/usr/bin/env python3
"""What are first_2 / find_by_2? Dump the SQL note (if any) and co-occurrence
of the _2 finder slots vs _1 slots, to confirm the sequential-guard argument
applies (same @person lookup minted twice, not a different query)."""
import json, glob, re
from collections import Counter

# Find a dump that references first_2_not_found
cands = glob.glob("dump_anon_mobile_presenter_*.json")[:0]  # none yet
# scan a few dumps
slots = Counter()
sample_notes = {}
n = 0
for f in glob.glob("dump_*.json"):
    if "replay" in f or n > 30:
        break
    try:
        d = json.load(open(f))
    except Exception:
        continue
    n += 1
    for e in d.get("events", []):
        if e.get("type") == "call":
            pass
    for e in d.get("events", []):
        if e.get("type") != "symbolic_call":
            continue
        note = (e.get("note") or e.get("sql") or e.get("details") or "")
        for m in re.finditer(r"FinderMethods_first_(\d+)|find_by_(\d+)", json.dumps(e)):
            pass
print("scanned", n, "dumps (quick probe)")

# Direct: grep dump files for first_2 var usage with notes
first2 = {}
first1 = {}
for f in glob.glob("dump_anon_mobile_presenter_0001.json"):
    d = json.load(open(f))
    def walk(o):
        if isinstance(o, dict):
            if o.get("type") == "symbolic_call" or o.get("type") == "call":
                s = json.dumps(o)
                if "first_2" in s or "find_by_2" in s:
                    print(f"[{f}] {o.get('type')}: {s[:400]}")
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    walk(d)
