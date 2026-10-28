import json, os, re, sys
from collections import defaultdict
HERE="/home/dev/project/reports/diaspora/results3/posts_show"
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for, renamer
from coverage_assumptions import ALIASES
_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s
DET=json.load(open(f"{HERE}/_p44_missdiag.json"))
man={m["gap"]:m for m in json.load(open(f"{HERE}/_p15_manifest_CTRL1.json"))}
ctrl={c["id"]:c for c in json.load(open(f"{HERE}/_p44_ctrl_gaps_C1.json"))}
ex=json.load(open(f"{HERE}/_p44_explain_CTRL1.json"))["per_gap"]
def maps(p):
    d=json.load(open(os.path.join(HERE,p)))
    ev=d.get("events") or ()
    amap=alias_map_for([(e.get("result_name"),e.get("note")) for e in ev if e.get("type")=="symbolic_call"],ALIASES)
    return d, renamer(amap), amap
for det in DET[:3]:
    g=det["gap"]; m=man[g]; c=ctrl[g]
    sd=json.load(open(os.path.join(HERE,m["seed_file"])))[m["seed_index"]]
    L=det["len"]
    print("="*70); print("gap",g,"want",det["want"],"L",L)
    print(" base   ",m["base"]); print(" witness",c["ctrl_dump"]); print(" driven ",ex[g]["dump"])
    for tag,p in (("BASE",m["base"]),("WITNESS",c["ctrl_dump"]),("DRIVEN",ex[g]["dump"])):
        d,rn,amap=maps(p)
        lens={}
        for sv in (d.get("symbolic_vars") or ()):
            n=str(sv.get("name"))
            if n.startswith("len("): lens[n]=(sv.get("value"), fixlen(rn(n)))
        hits={k:v for k,v in lens.items() if v[1]==L}
        print(f"  {tag}: {len(lens)} len vars; canonicalising to L: {hits}")
    print("  SEED len keys written:")
    for k,v in sorted(sd.items()):
        if k.startswith("len("): print("     ",k,"=",v)
