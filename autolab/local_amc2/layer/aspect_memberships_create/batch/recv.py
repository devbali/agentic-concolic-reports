import json,glob,collections
def t(e):
    try: return json.loads(e.get('note'))['text']
    except Exception: return e.get('note') or ''
arm=collections.Counter(); ex=None
for f in sorted(glob.glob('in/packet/dumps/dump_*.json')):
    d=json.load(open(f)); ev=d['events']
    if not any(e['type']=='symbolic_call' and 'UPDATE "contacts"' in t(e) for e in ev): continue
    rc=[(json.dumps(e['expr']),e['taken']) for e in ev if e['type']=='path_condition' and 'receiving' in json.dumps(e['expr'])]
    k=tuple(rc); arm[k]+=1
    if not rc and ex is None: ex=f
for k,v in arm.items(): print(v,k)
print('example with no receiving PC:',ex)
# what is the receiving value of the find_by row in the 64?
vals=collections.Counter()
for f in sorted(glob.glob('in/packet/dumps/dump_*.json')):
    d=json.load(open(f)); ev=d['events']
    if not any(e['type']=='symbolic_call' and 'UPDATE "contacts"' in t(e) for e in ev): continue
    for v in d['symbolic_vars']:
        if v['name'].endswith('find_by_1_receiving'): vals[repr(v.get('value'))]+=1
print('find_by_1_receiving values in the 64:',vals)
