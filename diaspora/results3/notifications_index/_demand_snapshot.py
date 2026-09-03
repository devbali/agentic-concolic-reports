#!/usr/bin/env python3
"""Checker-style demand replay: for each BLOCKING missing combo, find a corpus
snapshot that records the combo's exprs, MERGE the combo's concrete_values
into that snapshot's FULL seed dict (so the run reaches the same context), and
emit the merged seeds per variant for a SEEDS_ONLY replay. This reliably
observes combos that a partial-seed replay misses (the run needs the full
context to reach the exact ordinal decisions)."""
import glob, json, os, re, sys
HERE=os.path.dirname(os.path.abspath(__file__))
VARIANTS=("html_plain","html_typed","json_plain","json_typed","mobile_plain","mobile_typed","xml_plain")

def unfix(n): return f"len({n[8:]})" if n.startswith("SYM_LEN_") else n
def to_seed(v):
    if isinstance(v,bool) or v is None: return v
    if isinstance(v,(int,float)): return int(v)
    s=str(v)
    if s in("True","False"): return s=="True"
    try: return int(s)
    except: return s.strip('"').strip("'")

summary=json.load(open(os.path.join(HERE,"coverage_summary.json")))
missing=[m for m in summary.get("missing",[]) if not m.get("untracked")]
# index corpus: path -> (variant, seeds, set(exprs))
idx=[]
for p in sorted(glob.glob(os.path.join(HERE,"dump_*.json"))):
    d=json.load(open(p))
    v=next((x for x in VARIANTS if os.path.basename(p).startswith("dump_"+x)),None)
    exprs={e["expr"] for e in d.get("events",[]) if e.get("type")=="path_condition"}
    idx.append((v, d.get("concolic_seeds") or {}, exprs))
per={v:[] for v in VARIANTS}; seen={v:set() for v in VARIANTS}; unmatched=0
for m in missing:
    combo={unfix(k):to_seed(v) for k,v in (m.get("concrete_values") or {}).items()}
    if not combo: continue
    # the combo's exprs (the constraint's atoms)
    atoms=[a.strip().replace("NOT ","").strip() for a in m["node_constraint"].split(" AND ")]
    atoms=[a for a in atoms if a.startswith("(")]
    # find a snapshot recording the MOST of these atoms (richest context), per variant
    best={}
    for v,seeds,exprs in idx:
        if v is None: continue
        score=sum(1 for a in atoms if a in exprs)
        if score==0: continue
        if v not in best or score>best[v][0] or (score==best[v][0] and len(seeds)>len(best[v][2])):
            best[v]=(score,seeds,seeds)
    for v,(score,seeds,_) in best.items():
        merged=dict(seeds); merged.update(combo)
        key=json.dumps(merged,sort_keys=True)
        if key in seen[v]: continue
        seen[v].add(key); per[v].append(merged)
    if not best: unmatched+=1
for v,lst in per.items():
    out=os.path.join(HERE,f"_dsnap_{v}.json")
    if lst: json.dump(lst,open(out,"w"))
    elif os.path.exists(out): os.remove(out)
    print(f"{v}: {len(lst)} full-context seeds")
print(f"missing combos: {len(missing)}; unmatched: {unmatched}")
