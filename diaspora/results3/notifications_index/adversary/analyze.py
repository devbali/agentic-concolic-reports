import json,collections,sys
for f in sys.argv[1:]:
    d=json.load(open(f))
    print("="*90); print("FILE",f)
    for sc in d:
        if sc['name'].startswith('_'): continue
        print("scenario",sc['name'],"| error:",sc['error'])
        st=collections.Counter()
        for s in sc['statements']: st[(s['under'], s['sql'])]+=1
        for (u,sql),n in st.most_common():
            print(f"  {n:4d} [{u}] {sql[:190]}")
        stack=[];chains=collections.Counter()
        for c in sc['target_calls']:
            stack=stack[:c['depth']]; stack.append(c['target'])
            chains[" -> ".join(stack)]+=1
        print("  --- call chains ---")
        for k,v in chains.most_common(40): print(f"  {v:4d} {k}")
