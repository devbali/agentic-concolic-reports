#!/usr/bin/env python3
"""Full-corpus per-variant statement-shape scan (round 5, write-aware).
usage: _corpus_scan.py <batch> <out.json>   -> {variant: {n, maxmult:{shape:max}, present:{shape:ndumps}}}"""
import json, glob, os, re, sys, collections
def shape(sql):
    s=re.sub(r"[`\"]","",str(sql)); s=re.sub(r"\$\$\([^)]*\)|\?|\b\d+\b","@",s); s=re.sub(r"'[^']*'","@",s)
    s=re.sub(r"\b(true|false)\b","@",s,flags=re.I); s=re.sub(r"\(\s*@\s*(,\s*@\s*)+\)","(@,@+)",s)
    return re.sub(r"\s+"," ",s).strip().lower()
batch, out = sys.argv[1], sys.argv[2]
scan = collections.defaultdict(lambda: {"n":0,"maxmult":{},"present":{}})
for p in glob.glob(os.path.join(batch,"dump_*.json")):
    try: d=json.load(open(p))
    except Exception: continue
    v = "_".join((d.get("label") or "?").split("_")[:2])
    c = collections.Counter()
    for e in d.get("events") or []:
        n = e.get("note") or ""
        if e.get("type")=="symbolic_call" and re.match(r"\s*(select|update|insert|delete)", n, re.I): c[shape(n)] += 1
    S = scan[v]; S["n"] += 1
    for sh,m in c.items():
        S["maxmult"][sh] = max(S["maxmult"].get(sh,0), m); S["present"][sh] = S["present"].get(sh,0)+1
json.dump(scan, open(out,"w"))
for v,S in sorted(scan.items()): print(v, S["n"], len(S["maxmult"]))
