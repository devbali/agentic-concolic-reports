#!/usr/bin/env python3
"""C27 — HAND VERIFICATION of one refuting replay from _c27_fals_F1.json.

Re-runs the probe with keep=True and reads the resulting dump DIRECTLY (no
verdict helper): does it record each literal of C with C's outcome, and does
it record the member at all? Prints the raw recorded outcomes either way.
"""
import json, os, sys
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from end_to_end_completion_checker.assumption import assumption_checker as A
import importlib

HERE = os.path.dirname(os.path.abspath(__file__))
cfg = json.load(open(os.path.join(HERE, "assumption_manifest.json")))
mod_name, fn_name = cfg["canonicalize"].split(":")
mod = importlib.import_module(mod_name)
A._CANON_FN = getattr(mod, fn_name); A._ALIASES = list(getattr(mod, "ALIASES", []) or [])

fals = json.load(open(os.path.join(HERE, "_c27_fals_F1.json")))
CLS = int(sys.argv[1]) if len(sys.argv) > 1 else 0
c = fals[CLS]
base = next(b for b in c["per_base"] if b["verdict"] == "FAIL")
p = os.path.join(HERE, base["base"])
print(f"class {CLS}  member {c['expr']}")
print(f"base   {base['base']}  ({base['flips']} flip(s))")
sd = A.load_dump(p)
scen = (sd.get("concolic_scenario") or {}).get("name")
seeds = dict(A.seeds_as_written(sd))
gates = [(g, side == "taken") for g, side in c["conditioning"]]
for g, o in gates:
    if o in A.outcomes_of(sd, g):
        print(f"  base already matches: {'taken' if o else 'not_taken'}  {g[:70]}")
        continue
    dim = A.expr_dimension(g)
    seeds = A.flipped_seeds(sd, seeds, g, dim)
    print(f"  FLIP to {'taken' if o else 'not_taken'} via {dim[:60]}  {g[:60]}")
res = A.run_probe(cfg, f"c27verify{CLS}", seeds, keep=True, scenario=scen)
print(f"  probe produced {len(res)} dump(s) in scenario {scen!r}")
for name, r in res.items():
    print(f"  -- {name}")
    ok = True
    for g, o in gates:
        outs = A.outcomes_of(r, g)
        hit = o in outs
        ok &= hit
        print(f"       C literal want={'taken' if o else 'not_taken'} recorded={sorted(outs)} -> "
              f"{'MATCH' if hit else 'UNMET'}   {g[:66]}")
    m_outs = A.outcomes_of(r, c["expr"])
    print(f"       MEMBER recorded={A.recorded(r, c['expr'])} outcomes={sorted(m_outs)}   {c['expr'][:66]}")
    print(f"       => C realised: {ok};  member evaluated: {A.recorded(r, c['expr'])}")
    if ok and A.recorded(r, c["expr"]):
        print("       *** THIS RUN IS THE FALSIFIER: it matches C and evaluates the member ***")
print("C27-VERIFY-DONE")
