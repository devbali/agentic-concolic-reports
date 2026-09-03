#!/usr/bin/env python3
"""Corpus PC census over the boundary decisions (round 6).
usage: _pc_census.py <batch>  -> prints combos of (via_cookie, remembered, locked, stale, prev_login_first, ip compares, error) with dump counts
and the trackable SET-list shapes per combo."""
import json, glob, os, re, sys, collections
batch=sys.argv[1]
KEYS={'via_cookie':'SYM_PARAM_via_cookie == True','remembered':'_remembered == True','locked':'_locked == True',
      'stale':'_last_seen_stale == True','prev_first':'_prev_login_first == True','ip_same':"_current_sign_in_ip == StringVal('0.0.0.0')",
      'last_eq_cur':'_last_sign_in_ip == ','cid_arr':'SYM_PARAM_cid_is_array == True','cid_empty':'SYM_PARAM_cid_array_empty == True'}
combos=collections.Counter(); shapes=collections.defaultdict(collections.Counter); errs=collections.Counter()
n=0
for p in glob.glob(os.path.join(batch,'dump_*.json')):
    try: d=json.load(open(p))
    except Exception: continue
    n+=1
    st={k:None for k in KEYS}
    tr=[]
    for e in d.get('events') or []:
        if e.get('type')=='path_condition':
            x=e.get('expr','')
            for k,pat in KEYS.items():
                if pat in x and st[k] is None: st[k]=e.get('taken')
        elif e.get('type')=='symbolic_call':
            nt=e.get('note') or ''
            m=re.search(r'UPDATE "users" SET (.*?) WHERE',nt)
            if m: tr.append(re.sub(r' = \?','',m.group(1)).replace('"',''))
    err=(d.get('error') or {}).get('type')
    key=tuple((k,st[k]) for k in ('via_cookie','remembered','locked','stale','prev_first','ip_same','last_eq_cur'))+(('err',err),)
    combos[key]+=1
    for t in tr: shapes[key][t]+=1
print('dumps',n)
for k,c in sorted(combos.items(),key=lambda x:-x[1]):
    print(c, dict(k))
    for t,m in shapes[k].most_common(): print('      ',m,t)
