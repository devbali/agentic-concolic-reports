#!/usr/bin/env python3
"""Ground-truth differential reader: cardinality vars + their !=0 branch."""
import json, glob, re, sys, os

LEN = re.compile(r"len\([A-Za-z0-9_]+\)")

def arm(d):
    fs = sorted(glob.glob(os.path.join(d, "dump_*.json")))
    if not fs:
        return None
    out = []
    for f in fs:
        j = json.load(open(f))
        sv = j.get("symbolic_vars") or {}
        lens = {}
        for k, v in (sv.items() if isinstance(sv, dict) else []):
            if LEN.fullmatch(str(k)):
                lens[k] = v.get("value") if isinstance(v, dict) else v
        pcs = []
        for e in j.get("events", []):
            if e.get("type") == "path_condition" and LEN.search(e.get("expr", "")):
                pcs.append((e["expr"], e.get("taken")))
        out.append((os.path.basename(f), lens, pcs))
    return out

for name in ("pre", "post"):
    d = os.path.join(os.path.dirname(os.path.abspath(__file__)), name)
    r = arm(d)
    print("=" * 72)
    print("ARM %s   (%s)" % (name.upper(), d))
    if r is None:
        print("  NO DUMPS")
        continue
    for fn, lens, pcs in r:
        print("  dump: %s" % fn)
        print("  -- cardinality variables (len(...)) and their seeded value:")
        for k in sorted(lens):
            print("       %-60s = %r" % (k, lens[k]))
        print("  -- path conditions over a cardinality variable:")
        for expr, taken in pcs:
            print("       taken=%-5s  %s" % (taken, expr))
