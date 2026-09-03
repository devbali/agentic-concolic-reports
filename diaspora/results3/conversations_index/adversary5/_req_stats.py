#!/usr/bin/env python3
"""Per-request statement multiplicity vs the corpus ceiling (adversary round 4).
usage: _req_stats.py <corpus_scan.json> <run.json> [<run.json>...]
Variant is guessed from the scenario name (json/mobile/js/xml/html x cid)."""
import json, re, sys, collections
def shape(sql):
    s=re.sub(r"[`\"]","",str(sql)); s=re.sub(r"\$\$\([^)]*\)|\?|\b\d+\b","@",s); s=re.sub(r"'[^']*'","@",s)
    s=re.sub(r"\b(true|false)\b","@",s); s=re.sub(r"\(\s*@\s*(,\s*@\s*)+\)","(@,@+)",s)
    return re.sub(r"\s+"," ",s).strip().lower()
SKIP=re.compile(r"^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)",re.I)
scan=json.load(open(sys.argv[1]))
allmax=collections.Counter()
for sc,S in scan.items():
    for sh,m in S["maxmult"].items(): allmax[sh]=max(allmax[sh],m)
def variant(name):
    n=name.lower()
    fmt="mobile" if "mobile" in n else "json" if "json" in n else "js" if re.search(r"\bjs\b|_js_",n) else "xml" if "xml" in n else "html"
    cid="withcid" if ("cid" in n and "nocid" not in n) else "plain"
    return f"{fmt}_{cid}"
for rf in sys.argv[2:]:
    for sc in json.load(open(rf)):
        name=sc["name"]; v=variant(name); S=scan.get(v,{"maxmult":{},"n":0})
        ms=collections.Counter(); tx=0
        for st in sc.get("statements",[]):
            if SKIP.match(st["sql"]): tx+=1; continue
            ms[shape(st["sql"])]+=1
        flags=[]
        print(f"== {name} [{v}] statements={sum(ms.values())} (+{tx} tx) error={sc.get('error')}")
        for sh,c in sorted(ms.items(),key=lambda x:-x[1]):
            cm=S["maxmult"].get(sh); am=allmax.get(sh)
            tag="" if cm is not None and c<=cm else ("ABSENT-CORPUS" if am is None else ("ABSENT-VARIANT" if cm is None else f"OVER x{c}>{cm}"))
            if tag: flags.append(tag)
            print(f"   {c:2d} corpus[{v}]max={cm if cm is not None else '-'} all={am if am is not None else '-'} {tag:14s} {sh[:130]}")
        # corpus shapes the request lacks (present in >=90% of that variant's dumps) -- informational
        missing=[sh for sh,p in S.get("present",{}).items() if S["n"] and p/S["n"]>0.9 and sh not in ms]
        for sh in missing: print(f"   -- corpus-usual shape not issued: {sh[:110]}")
