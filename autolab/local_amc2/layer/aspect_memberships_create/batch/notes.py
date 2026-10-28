import json,glob,re,collections
by=collections.defaultdict(collections.Counter); kinds=collections.Counter(); nonote=collections.Counter()
for f in sorted(glob.glob('in/packet/dumps/dump_*.json')):
    d=json.load(open(f))
    for e in d['events']:
        if e.get('type')!='symbolic_call': continue
        t=e['target']; n=e.get('note')
        if n is None: nonote[t]+=1; continue
        try:
            j=json.loads(n); txt=j.get('text') if isinstance(j,dict) else n
        except Exception: txt=n
        txt=re.sub(r'\$\$?\([^)]*\)','$()',txt)
        by[t][txt]+=1
for t in sorted(by):
    print('##',t, 'no-note:',nonote.get(t,0))
    for s,c in by[t].most_common(): print('  %5d  %s'%(c,s))
print('nonote',nonote)
