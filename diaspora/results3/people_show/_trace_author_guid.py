#!/usr/bin/env python3
"""Trace assoc_author_guid PCs in ONE dual dump: exact exprs + taken."""
import glob
import json
import os

HERE = '/home/dev/project/reports/diaspora/results3/people_show'
p = os.path.join(HERE, 'dump_anon_mobile_presenter_0001.json')
raw = json.load(open(p))

print("=== events with 'guid' or 'empty' ===")
for ev in raw.get("events", []):
    expr = str(ev.get("expr", ""))
    if "guid" in expr or "empty" in expr:
        print(f"  taken={ev.get('taken')} type={ev.get('type')} expr={expr[:130]!r}")

print("\n=== symbolic_vars with guid ===")
for sv in raw.get("symbolic_vars", []):
    if "guid" in sv.get("name", ""):
        print(f"  {sv.get('name')} = {sv.get('value')!r} sort={sv.get('sort')}")

print("\n=== all assoc_ vars ===")
for sv in raw.get("symbolic_vars", []):
    if sv.get("name", "").startswith("assoc_author"):
        print(f"  {sv.get('name')} = {sv.get('value')!r}")