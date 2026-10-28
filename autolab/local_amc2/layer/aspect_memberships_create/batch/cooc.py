import json,glob,collections,re
def t(e):
    n=e.get('note')
    try: return json.loads(n)['text']
    except Exception: return n or ''
sig=collections.Counter()
for f in sorted(glob.glob('in/packet/dumps/dump_*.json')):
    d=json.load(open(f))
    s=[(e['target'].split('#')[-1].split('.')[-1], re.sub(r'\$\$\(\w+\)','?',t(e))) for e in d['events'] if e.get('type')=='symbolic_call']
    keys=[]
    for tg,x in s:
        if x.startswith(('INSERT','UPDATE "contacts"')) or 'IS NULL' in x or 'IS NOT NULL' in x or 'aspect_memberships' in x:
            keys.append(tg+': '+x[:90])
    sig[tuple(keys)]+=1
for k,v in sig.most_common():
    print(v); [print('    ',x) for x in k]
