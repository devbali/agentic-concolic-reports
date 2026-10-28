#!/usr/bin/env python3
"""Per-GATE-COMBINATION realisation table for the GC0911 construction drive.

RUNBOOK Phase 2 (2026-09-11): a remaining cube may not be called residue until
it has been CONSTRUCTED and REPLAYED. Classify each constructed gate outcome,
per key, in the dumps the drive actually produced:

  REALISED    — seeded and observed with the seeded value
  CONTRADICTED— seeded, evaluated, observed with the OTHER value  <- the only
                thing that is impossibility evidence
  UNEVALUATED — seeded but the decision was never reached on that path
"""
import glob, json, os, re, sys
from collections import Counter, defaultdict
sys.path.insert(0, "."); sys.path.insert(0, "/home/dev/project/src")
from coverage_report import canonicalize_ordinals
from concolic_engine.names import NameSpace

cubes = json.load(open(os.environ.get("EMIT_IN", "_enum_emit_gateaware.json")))["missing"]
gates_of = {}
for c in cubes:
    g = c.get("gates") or {}
    if g:
        gates_of[tuple(sorted((k, bool(v)) for k, v in g.items()))] = g
print(f"gate combinations constructed: {len(gates_of)}")
wanted = {}
for combo in gates_of:
    for k, v in combo:
        wanted.setdefault(k, set()).add(v)
print(f"distinct GATE decisions across them: {len(wanted)}")

TAG = os.environ.get("DRIVE_TAG", "GC0911")
files = sorted(glob.glob(f"dump_*{TAG}*.json"))
print(f"drive dumps: {len(files)}")
per = Counter(); bykey = defaultdict(Counter)
# 2026-09-14 NAME-BOUNDARY FIX (concolic_engine.names). `wanted`'s gate exprs
# come from the ENUMERATOR: checker spelling (`SYM_LEN_X`) and canonical
# ordinals. A dump's `concolic_seeds` is what the RUNTIME consumed: `len(X)`,
# raw ordinals (`canonicalize_ordinals` deliberately leaves seeds alone), and
# `obs` is canonicalized but NOT len-renamed. The old `seeds.get(dim)` /
# `obs.get(g)` therefore missed on EVERY length gate -- 11 of the 40 gate
# decisions in `_enum_emit_gateaware.json` -- and the miss was read as "not
# seeded in this run", so the whole length family was invisible to the only
# test in this file that produces impossibility evidence. NameSpace.resolve
# crosses the boundary; XBOUND counts how often it had to, so the next reader
# sees it instead of rediscovering it.
XBOUND = Counter()
for p in files:
    try:
        d = json.load(open(p))
    except Exception:
        continue
    amap = canonicalize_ordinals(d)
    seeds = d.get("concolic_seeds") or {}
    NS = NameSpace(seeds, name="dump concolic_seeds", alias_map=amap)
    obs = defaultdict(set)
    for e in d.get("events") or ():
        if e.get("type") == "path_condition":
            obs[str(e.get("expr", ""))].add(bool(e.get("taken")))
    OBS = NameSpace(obs, name="observed path conditions", alias_map=amap)
    for g in wanted:
        m = re.match(r"^\(\s*([A-Za-z_][A-Za-z0-9_]*)", g)
        dim = m.group(1) if m else None
        if not dim:
            continue
        sv = NS.resolve(dim)
        if sv is None:
            continue                      # genuinely not seeded in this run
        if dim not in seeds:
            XBOUND["seed key reached only across the name boundary"] += 1
        o = OBS.resolve(g)
        if o and g not in obs:
            XBOUND["observed PC reached only across the name boundary"] += 1
        if not o:
            per["UNEVALUATED"] += 1; bykey[g]["UNEVALUATED"] += 1
        elif len(o) == 1 and next(iter(o)) == bool(sv):
            per["REALISED"] += 1; bykey[g]["REALISED"] += 1
        elif bool(sv) in o:
            per["REALISED(both-sided)"] += 1; bykey[g]["REALISED"] += 1
        else:
            per["CONTRADICTED"] += 1; bykey[g]["CONTRADICTED"] += 1
    del d
if XBOUND:
    print("\n=== NAME-BOUNDARY CROSSINGS (would have been silent misses) ===")
    for k, v in XBOUND.most_common():
        print(f"  {k:52s} {v}")
print("\n=== GATE OUTCOMES ACROSS THE DRIVE ===")
for k, v in per.most_common():
    print(f"  {k:22s} {v}")
contra = {g: c for g, c in bykey.items() if c["CONTRADICTED"] and not c["REALISED"]}
print(f"\nGATES THAT FLIPPED BACK DESPITE THEIR SEED (never realised) — the ONLY")
print(f"impossibility evidence: {len(contra)} of {len(bykey)} gates seen")
for g, c in sorted(contra.items(), key=lambda kv: -kv[1]["CONTRADICTED"])[:15]:
    print(f"  contradicted x{c['CONTRADICTED']:<5} {g[:96]}")
part = {g: c for g, c in bykey.items() if c["CONTRADICTED"] and c["REALISED"]}
print(f"\ngates realised at least once (NOT residue): {sum(1 for c in bykey.values() if c['REALISED'])}")
print(f"gates both realised and contradicted (context-dependent): {len(part)}")
json.dump({"per": dict(per),
           "contradicted_only": {g: dict(c) for g, c in contra.items()},
           "bykey": {g: dict(c) for g, c in bykey.items()}},
          open("_gc_realise.json", "w"), indent=1)
print("\nwrote _gc_realise.json")
