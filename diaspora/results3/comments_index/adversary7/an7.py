#!/usr/bin/env python3
"""Segment an adversary7 concrete_run.json into per-request statement sequences.
A new request starts at the first `users` SELECT or the first `posts` finder
after at least one statement of the previous request."""
import json,re,sys,os
def norm(s): return re.sub(r"\s+"," ",s).strip()
START=re.compile(r'^SELECT ("users"\.\*|"posts"\.\*|posts\.\*) FROM')
for p in sys.argv[1:]:
    d=json.load(open(p))
    print("#"*100); print("##",os.path.basename(p))
    for sc in d:
        sts=sc.get("statements") or []
        segs=[];cur=[]
        for st in sts:
            s=norm(st["sql"])
            if START.match(s) and cur and not START.match(norm(cur[-1][0])):
                segs.append(cur); cur=[]
            elif START.match(s) and cur and START.match(norm(cur[-1][0])) and s.startswith('SELECT "users"'):
                segs.append(cur); cur=[]
            cur.append((s,st.get("under")))
        if cur: segs.append(cur)
        print(f"-- scenario {sc.get('name')}  statements={len(sts)}  segments={len(segs)}  error={sc.get('error')}")
        for i,seg in enumerate(segs,1):
            print(f"   [seg {i:02d}]")
            for s,u in seg:
                print(f"      {s[:190]}")
        tc={}
        for c in sc.get("target_calls") or []:
            tc[c.get("target")]=tc.get(c.get("target"),0)+1
        print("   depth-0 target_calls:", tc)
