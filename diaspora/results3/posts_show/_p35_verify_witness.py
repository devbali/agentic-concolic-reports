import json, os, sys
sys.path.insert(0,"/home/dev/project/reports/diaspora/results3/posts_show")
sys.path.insert(0,"/home/dev/project/src")
from end_to_end_completion_checker.assumption import assumption_checker as AC
import importlib
B="/home/dev/project/reports/diaspora/results3/posts_show/"
cfg=json.load(open(B+"assumption_manifest.json"))
mn,fn=cfg["canonicalize"].split(":"); m=importlib.import_module(mn)
AC._CANON_FN=getattr(m,fn); AC._ALIASES=list(getattr(m,"ALIASES",[]) or [])
paths=[l.strip() for l in open("/tmp/claude-1000/newdumps.txt")]
dumps={}
for p in paths:
    bn=os.path.basename(p)
    d=AC._load_dump_uncached(os.path.join(B,bn))
    dumps[bn]=AC._outcomes_of_dump(d)
print(f"loaded {len(dumps)} kept dumps", flush=True)
classes=json.load(open(B+"_p35_witness_sample.json"))
ok=bad=nomatch=0
for i,c in enumerate(classes):
    C=[(e,bool(o)) for e,o in c["conditioning"]]; d_=c["member"]
    hit=None
    for bn,outs in dumps.items():
        if all(outs.get(AC.canon(e),frozenset())==frozenset([o]) for e,o in C) \
           and outs.get(AC.canon(d_),frozenset()):
            hit=bn; break
    if hit: ok+=1
    else:
        anyC=any(all(outs.get(AC.canon(e),frozenset())==frozenset([o]) for e,o in C)
                 for outs in dumps.values())
        if anyC: bad+=1
        else: nomatch+=1
    if i<3:
        print(f"\n  class {i}: member={d_[:66]}", flush=True)
        print(f"     witness dump: {hit}", flush=True)
        if hit:
            outs=dumps[hit]
            for e,o in C:
                g=outs.get(AC.canon(e),frozenset())
                print(f"       C: want={o!s:5s} got={sorted(g)!s:14s} {'OK' if g==frozenset([o]) else 'NO'}  {e[:52]}", flush=True)
            print(f"       d evaluated: {sorted(outs.get(AC.canon(d_),frozenset()))}", flush=True)
print(f"\n=== VERIFIED {ok}/{len(classes)} classes have a REAL witness among the kept dumps ===", flush=True)
print(f"    realises C but d UNEVALUATED (would be a false FAIL): {bad}", flush=True)
print(f"    no kept dump realises C at all                      : {nomatch}", flush=True)
