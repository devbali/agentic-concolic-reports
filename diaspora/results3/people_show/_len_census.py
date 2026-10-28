#!/usr/bin/env python3
"""Check which len-vars appear in mobile vs non-mobile dumps, and their values."""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
files = sorted(f for f in os.listdir(HERE) if f.startswith("dump_") and f.endswith(".json"))

LEN_RE = re.compile(r"len\(([^)]+)\)")
mobile_records = 0
mobile_rows = 0
nonmobile_records = 0
nonmobile_rows = 0

mobile_files = [f for f in files if "mobile" in f]
nonmobile_files = [f for f in files if "mobile" not in f]
print(f"mobile files: {len(mobile_files)}, non-mobile files: {len(nonmobile_files)}")

for f in mobile_files[:80]:
    try:
        d = json.load(open(os.path.join(HERE, f)))
    except Exception:
        continue
    sv = [v.get("name", "") for v in d.get("symbolic_vars", [])]
    lens = [n for n in sv if n.startswith("len(")]
    if any("records_1_rows" in n for n in lens):
        mobile_rows += 1
    if any(re.search(r"records_\d+\)$", n) and "_rows" not in n for n in lens):
        mobile_records += 1

for f in nonmobile_files[:80]:
    try:
        d = json.load(open(os.path.join(HERE, f)))
    except Exception:
        continue
    sv = [v.get("name", "") for v in d.get("symbolic_vars", [])]
    lens = [n for n in sv if n.startswith("len(")]
    if any("_rows" in n for n in lens):
        nonmobile_rows += 1
    if any(re.search(r"records_\d+\)$", n) and "_rows" not in n for n in lens):
        nonmobile_records += 1

print(f"mobile:  dumps with records_N len: {mobile_records}, with _rows len: {mobile_rows}")
print(f"non-mobile: dumps with records_N len: {nonmobile_records}, with _rows len: {nonmobile_rows}")

# Show actual len var names in one mobile and one non-mobile dump
for f in (mobile_files[0] if mobile_files else None, nonmobile_files[0] if nonmobile_files else None):
    if not f:
        continue
    d = json.load(open(os.path.join(HERE, f)))
    sv = [v.get("name", "") for v in d.get("symbolic_vars", [])]
    lens = sorted(n for n in sv if n.startswith("len("))
    print(f"\n{f}: {len(lens)} len vars:")
    for n in lens:
        print("   ", n)