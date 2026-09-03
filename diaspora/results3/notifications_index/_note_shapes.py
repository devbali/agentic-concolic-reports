#!/usr/bin/env python3
import glob, json, os, re, sys
from collections import Counter
HERE = os.path.dirname(os.path.abspath(__file__))
args=sys.argv[1:]
sample = int(args[args.index('--sample')+1]) if '--sample' in args else 0
files = sorted(glob.glob(os.path.join(HERE,'dump_*.json')))
if sample and len(files)>sample:
    step=len(files)/float(sample); files=[files[int(i*step)] for i in range(sample)]
BIND=re.compile(r'\$\$\([^)]*\)')
shapes=Counter(); dumps=Counter()
n=0
for p in files:
    try: d=json.load(open(p))
    except Exception: continue
    n+=1; here=set()
    for ev in d.get('events') or []:
        if ev.get('type')!='symbolic_call': continue
        nt=re.sub(r'\s+',' ',str(ev.get('note') or '')).strip()
        if not nt or nt=='None': continue
        s=BIND.sub('?',nt)
        shapes[s]+=1; here.add(s)
    for s in here: dumps[s]+=1
print(f"== {n} dumps, {len(shapes)} distinct note shapes ==")
for s,c in shapes.most_common(200):
    print(f"{c:9d} ev /{dumps[s]:7d} dumps  {s[:190]}")
