#!/usr/bin/env python3
"""usage: _summ.py <run.json> [names...] -> per scenario: error, statements in order (shape + frame)"""
import json,re,sys
def shape(sql):
    s=re.sub(r"[`\"]","",str(sql)); s=re.sub(r"\$\$\([^)]*\)|\?|\b\d+\b","@",s); s=re.sub(r"'[^']*'","@",s)
    return re.sub(r"\s+"," ",s).strip().lower()
d=json.load(open(sys.argv[1])); want=sys.argv[2:]
for sc in d:
    if want and not any(w in sc['name'] for w in want): continue
    d0=[t['target'] for t in sc.get('target_calls',[]) if t.get('depth')==0]
    print(f"== {sc['name']} error={sc.get('error')} depth0={len(d0)} stmts={len(sc['statements'])}")
    for st in sc['statements']:
        s=shape(st['sql'])
        if s.startswith(('begin','commit','rollback')): continue
        print(f"   [{st.get('under','?')[:38]:38}] {s[:150]}")
