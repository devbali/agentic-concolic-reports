#!/usr/bin/env python3
import json, sys

path = "coverage_summary.json"
with open(path) as f:
    data = json.load(f)

missing = data.get("missing", data.get("missing_items", []))
print("TOTAL MISSING:", len(missing))
print("="*80)
for i, item in enumerate(missing):
    print(f"--- missing[{i}] ---")
    print(json.dumps(item, indent=2)[:2000])
