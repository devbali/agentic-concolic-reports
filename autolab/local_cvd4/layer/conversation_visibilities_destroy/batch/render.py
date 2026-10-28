import json,sys
p=json.load(open(sys.argv[1]))
def r(x):
    if isinstance(x,dict) and '$' in x:
        t=x['$'];f=x.get('f',{})
        if t=='tuple': return [r(v) for v in x['v']]
        if t=='Ref': return f['id']
        if t=='Lit': return repr(f['value'])
        if t=='Field': return f"{r(f['base'])}.{f['name']}"
        if t=='Predicate': return f"{r(f['lhs'])} {f['op']} {r(f['rhs'])}"
        if t=='Conjunction': return ' AND '.join(r(f['preds'])) or 'TRUE'
        if t=='Condition': return ' OR '.join('('+b+')' for b in r(f['branches']))
        return {t:{k:r(v) for k,v in f.items()}}
    return x
for i,a in enumerate(p['policy']['f']['atoms']['v']):
    f=a['f'];print(f"ATOM {i} reliable={f['reliable']} IF {r(f['condition'])}")
    for e in f['events']['v']:
        ef=e['f'];n=json.loads(ef['note']) if ef['note'] else None
        print(f"   {e['$']:6} {ef['target']} -> {r(ef['result'])} args={r(ef['args'])} inter={ef['interaction']}\n        {n}")
print([k for k in p['policy']['f'] if k!='atoms'])
