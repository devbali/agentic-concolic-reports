#!/usr/bin/env python3
"""Full stream-ordinal structure of ONE mobile dump vs ONE dual dump.

Print every records/rows/to_a related PC expr + taken for:
- dump_anon_mobile_0001.json (mobile-only)
- dump_anon_mobile_presenter_0001.json (dual)
Also the SYM_RESULT vars minted (from symbolic_results? symbolic_vars?) to see
which ordinals each run shape produces.
"""
import json
import os
import re

HERE = '/home/dev/project/reports/diaspora/results3/people_show'

def show(fname):
    p = os.path.join(HERE, fname)
    if not os.path.exists(p):
        print(f"!! {fname} missing")
        return
    raw = json.load(open(p))
    print(f"\n########## {fname} ##########")
    print(f"label={raw.get('label')} script={raw.get('script')}")
    rel = []
    for ev in raw.get("events", []):
        expr = str(ev.get("expr", ""))
        if re.search(r"records|to_a|rows", expr):
            rel.append((expr[:100], ev.get("taken")))
    print(f"record-family PCs ({len(rel)}):")
    for e, t in rel:
        print(f"   taken={t}  {e}")
    # also count how many SYM_RESULT_*_rows N ordinals appear in ALL events
    ords = set()
    for ev in raw.get("events", []):
        expr = str(ev.get("expr", ""))
        for m in re.finditer(r"records_(\d+)_rows|to_a_(\d+)_rows|records_(\d+)[^_]", expr):
            ords.add(m.group(0))
    print(f"row ordinals seen: {sorted(ords)}")

show("dump_anon_mobile_0001.json")
show("dump_anon_mobile_presenter_0001.json")