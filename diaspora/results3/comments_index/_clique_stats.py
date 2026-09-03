import sys,glob,json,collections
sys.path.insert(0,'/home/dev/project/src'); sys.path.insert(0,'/home/dev/project/reports/diaspora/results3/comments_index')
from concolic_engine.run import Run
from concolic_engine import coverage as cov
import coverage_report as cr, coverage_assumptions as ca
runs=[]
for p in glob.glob('/home/dev/project/reports/diaspora/results3/comments_index/dump_*.json'):
    runs.append(cr.share_run_objects(cr.apply_len_bounds(Run.from_dict(cr.fix_len_names(json.load(open(p)))))))
aset=ca.build(runs)
exprs=[]; seen=set()
pol=collections.defaultdict(set)
for r in runs:
    for pc in r.path_conditions:
        if pc.expr not in seen: seen.add(pc.expr); exprs.append(pc.expr)
        pol[pc.expr].add(bool(pc.taken))
print('runs',len(runs),'exprs',len(exprs),'assumptions',len(aset))
single=[e for e in exprs if len(pol[e])<2]; print('single-polarity exprs',len(single)); [print('  ',e) for e in single]
active=[e for e in exprs if not aset.is_untracked(None,e)]
adj={e:set() for e in active}
for i,a in enumerate(active):
    for b in active[i+1:]:
        if not aset.are_independent(None,None,a,b): adj[a].add(b); adj[b].add(a)
cl=cov._maximal_cliques(active,adj,cap=100000)
sizes=collections.Counter(len(c) for c in cl) if cl else None
print('cliques',None if cl is None else len(cl),'sizes',dict(sorted(sizes.items())) if sizes else None)
if cl:
    big=max(cl,key=len); print('biggest clique:'); [print('  ',e) for e in big]
    deg=sorted(((len(adj[e]),e) for e in active),reverse=True)[:12]; print('top degrees:'); [print('  ',d,e) for d,e in deg]
