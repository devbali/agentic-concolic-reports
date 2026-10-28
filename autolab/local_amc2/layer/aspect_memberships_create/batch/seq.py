import json,glob,sys
def txt(e):
    n=e.get('note')
    if n is None: return None
    try: return json.loads(n)
    except Exception: return n
pat=sys.argv[1]; k=int(sys.argv[2]) if len(sys.argv)>2 else 0
hits=[]
for f in sorted(glob.glob('in/packet/dumps/dump_*.json')):
    d=json.load(open(f))
    s=[e for e in d['events'] if e.get('type')=='symbolic_call']
    if any(pat in json.dumps(txt(e)) for e in s): hits.append((f,s,d))
print(len(hits))
f,s,d=hits[k]; print(f)
for e in s:
    print(' ',e['target'],'|',e.get('result_name'),'|',json.dumps(txt(e))[:360])
