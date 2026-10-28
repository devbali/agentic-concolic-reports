#!/usr/bin/env python3
"""P44 — verify the CONTROL cubes against their witness dump by the SAME code
path `_p15_explain.py` uses (independent of the index bitmasks that built them).
Ground truth must be 525/525 walked; anything less is a defect in the control
itself and must be fixed before the hit rate means anything."""
import json, os, re, sys
from collections import Counter
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for, renamer
from coverage_assumptions import ALIASES
_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s

def literals(nc):
    out, depth, cur, i, n = [], 0, [], 0, len(nc or "")
    while i < n:
        c = nc[i]
        if c == "(": depth += 1
        elif c == ")": depth -= 1
        if depth == 0 and nc.startswith(" AND ", i):
            out.append("".join(cur)); cur = []; i += 5; continue
        cur.append(c); i += 1
    if cur: out.append("".join(cur))
    res = []
    for t in out:
        t = t.strip()
        if not t: continue
        pol = True
        while t.startswith("Not(") and t.endswith(")"):
            t = t[4:-1].strip(); pol = not pol
        res.append((t, pol))
    return res

G = json.load(open(sys.argv[1]))
by = {}
for c in G: by.setdefault(c["ctrl_dump"], []).append(c)
V = Counter(); bad = []
for nm, cs in by.items():
    d = json.load(open(os.path.join(HERE, nm)))
    ev = d.get("events") or ()
    amap = alias_map_for([(e.get("result_name"), e.get("note"))
                          for e in ev if e.get("type") == "symbolic_call"], ALIASES)
    rn = renamer(amap)
    taken = {}
    for e in ev:
        if e.get("type") == "path_condition":
            taken.setdefault(fixlen(rn(str(e.get("expr", "")))), set()).add(bool(e.get("taken")))
    for c in cs:
        okl = all(pol in taken.get(x, ()) for x, pol in literals(c["node_constraint"]))
        okg = all(pol in taken.get(x, ()) for x, pol in (c["gates"] or {}).items())
        V["cube realised" if okl else "CUBE NOT REALISED"] += 1
        V["gates walked" if okg else "GATES NOT WALKED"] += 1
        if not (okl and okg): bad.append((c["id"], nm))
print(dict(V))
print("first bad:", bad[:5])
print("P44-CTRL-VERIFY-DONE")
