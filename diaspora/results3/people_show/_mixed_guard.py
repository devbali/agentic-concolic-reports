#!/usr/bin/env python3
"""List, for each missing item (new snapshot), the guard var and its sign."""
import json

cs = json.load(open("coverage_summary.json"))
miss = cs["missing"]

def guard_spec(nc):
    """returns dict var->{'pos'|'neg'}"""
    out = {}
    i = 0
    while True:
        j = nc.find("== True", i)
        if j < 0:
            break
        k = nc.rfind(" AND ", 0, j)
        seg = nc[k + 5:j].strip()
        neg = "Not((" in seg
        var = seg.split("Not((")[-1].split(" == ")[0].strip("() ").strip()
        if var.endswith("_not_found") or var.endswith("_closed_account"):
            out[var] = "neg" if neg else "pos"
        i = j + 6
    return out

for idx, m in enumerate(miss):
    g = guard_spec(m["node_constraint"])
    print(f"[{idx:2d}] {len(m['node_constraint']):5d}  {sorted((v + '=' + s) for v, s in g.items())}")
