import json,glob,collections,re
by=collections.defaultdict(collections.Counter)
for f in sorted(glob.glob('in/packet/dumps/*.json')):
  d=json.load(open(f)); seen=set()
  for e in d['events']:
    if e.get('type')!='symbolic_call': continue
    n=e.get('note')
    if n is None: t='<NO NOTE>'
    else:
      try: t=json.loads(n).get('text')
      except Exception: t='RAW:'+n
    t=re.sub(r'\$\$\(p\d+\)','$$(p)',t or '<none>')
    k=(e['target'],t)
    if k not in seen: seen.add(k); by[e['target']][t]+=1
json.dump({k:dict(v) for k,v in by.items()},open('batch/notes_by_target.json','w'),indent=1)
for k,v in by.items():
  print('##',k)
  for t,c in v.most_common(): print('  %4d  %s'%(c,t))
