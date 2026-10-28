import json,sys
sys.path.insert(0,'/home/dev/project/src_new')
from dumps_to_policy.syntax.policy_json import from_json
from domains.ruby_rails_sql import checks
pol=from_json(json.load(open('in/policy.json')))
real=json.load(open('in/real_mode.json'))
app=json.load(open('in/app_config.json'))
for fn in ('shape_check','statement_differential'):
    f=getattr(checks,fn,None)
    if not f: print('no',fn); continue
    try: items=f(pol,real,app)
    except TypeError: items=f(pol,real)
    print('=====',fn,len(items))
    for it in items:
        d=it if isinstance(it,dict) else getattr(it,'__dict__',{}) or {k:getattr(it,k) for k in ('identity','evidence','consequence') if hasattr(it,k)}
        print('--',d.get('identity')); print('   ',str(d.get('evidence')))
