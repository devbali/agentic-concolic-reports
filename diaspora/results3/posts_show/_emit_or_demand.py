#!/usr/bin/env python3
"""CONFINEMENT CENSUS — price DISCIPLINE §16c on one endpoint's snapshot.

    DUMP_LIST=<snapshot list> [MAX_CLIQUES=16384] [CUBE_CAP=20000] \\
        python3 confinement_census.py <batch_dir> [--enum-module MOD] [--json-out f]

Runs the endpoint's OWN exact enumerator (`_exact_enum_emit` on posts_show,
`_exact_enum` elsewhere — the module that carries `load_runs`,
`build_universe`, `census`, `var_index`) twice on the IDENTICAL universe:
once over the §16b demand sets, once over those sets projected by
confinement (`concolic_engine.coverage.restrict_confinement`, foreclosure
first) — so the two `EXACT:` lines are directly comparable with the batch's
own `_enum_*_cost.log` when the same DUMP_LIST and flags are used.

Reports, per the 2026-09-11 brief: decisions decided / undecidable; pairs
confined / overlapping / undecidable (co-evaluated, non-gate pairs — the
ones the demand is about); demanded / covered / remaining before -> after;
and the overlapping pairs with examples (real dependence the independence
flip-both probe was blind to, X11).

Written 2026-09-11 to be run by the ENDPOINT AGENT at its next pass, under
its own memory cap (a p5-sized census peaked at 3.3 GB). It declares nothing
and writes nothing into the batch directory unless --json-out points there.
The engine's own pass (`coverage_report.py`) applies the same projection and
prints the same decision/pair counts in `summary()`; this tool adds the
exact assignment counts the capped pass cannot give.
"""
import importlib
import json
import os
import sys
import time

BATCH = os.path.abspath(os.environ.get("BATCH", "."))
args = []
mod_name = args[args.index("--enum-module") + 1] if "--enum-module" in args else (
    "_exact_enum_emit" if os.path.exists(os.path.join(BATCH, "_exact_enum_emit.py"))
    else "_exact_enum")
sys.path.insert(0, BATCH)
sys.path.insert(0, "/home/dev/project/src")
EE = importlib.import_module(mod_name)
from coverage_assumptions import build as build_assumptions            # noqa: E402
from concolic_engine.assumptions import call_shape, shape_str            # noqa: E402
from concolic_engine.coverage import project_confinement   # noqa: E402

t0 = time.time()
runs = EE.load_runs()
A = build_assumptions(runs)
U = EE.build_universe(runs, A, int(os.environ.get("MAX_CLIQUES", "16384")))
if U is None:
    sys.exit("PROJECTION CAP HIT")
print(f"universe built in {time.time()-t0:.0f}s", flush=True)

# ---- footprints, over the SAME profiles the enumerator built ---------------
# Rebuild the profile index in the enumerator's insertion order (first
# profile wins, as in the engine's step 1) and accumulate per-profile trace
# union / intersection from the alias-applied runs (U["runs"]).
pkey = getattr(EE, "_pkey", None)
if pkey is None:
    from concolic_engine.coverage import profile_key as pkey
idx = {}
union, inter = [], []
shape_id = {}
for run in U["runs"]:
    outcomes = {}
    for pc in run.path_conditions:
        outcomes.setdefault(pc.expr, set()).add(bool(pc.taken))
    if not outcomes:
        continue
    tr = 0
    for ev in run.symbolic_call_events:
        if not ev.result_name:
            continue
        sh = call_shape(ev.target_name, ev.note, ev.args)
        j = shape_id.get(sh)
        if j is None:
            j = shape_id[sh] = len(shape_id)
        tr |= 1 << j
    k = pkey(outcomes)
    i = idx.get(k)
    if i is None:
        idx[k] = len(union)
        union.append(tr)
        inter.append(tr)
    else:
        union[i] |= tr
        inter[i] &= tr
assert len(union) == len(U["run_outcomes"]), "profile index does not match the enumerator's"
# ---- footprints, strictness, projection: the ENGINE's own helper ------------
# (same call the checker makes in step 5d — exact keying, co-evaluated keying
# as the fallback that makes gates measurable, the strict counterexample
# search, gates confinable with the closure rule)
side_seen = {}
for run in U["runs"]:
    outcomes = {}
    for pc in run.path_conditions:
        outcomes.setdefault(pc.expr, set()).add(bool(pc.taken))
    tr = 0
    for ev in run.symbolic_call_events:
        if ev.result_name:
            j = shape_id.get(call_shape(ev.target_name, ev.note, ev.args))
            if j is not None:
                tr |= 1 << j
    if not tr:
        continue
    for e, os_ in outcomes.items():
        k = 2 if len(os_) > 1 else (1 if True in os_ else 0)
        side_seen.setdefault(e, [0, 0, 0])[k] |= tr
# WHAT-IF (2026-09-11): WHATIF_PAIRS=<json> — a list of [a, b] pairs to treat as
# confined whatever the footprints say (e.g. the OR-monotone pairs from
# or_sharing_census.py). Measurement before a rule change; nothing declared.
forced = set()
if os.environ.get("WHATIF_PAIRS"):
    forced = {tuple(sorted(p)) for p in json.load(open(os.environ["WHATIF_PAIRS"]))}
    print(f"WHAT-IF: {len(forced)} pair(s) forced confined from {os.environ['WHATIF_PAIRS']}", flush=True)
pj = project_confinement(U["active"], U["expr_order"], U["run_outcomes"], union, inter,
                         side_seen, [frozenset(c) for c in U["cliques"]], U["by_gate"], U["bit"],
                         int(os.environ.get("MAX_CLIQUES", "16384")), force_confined=forced)
fp, ctxn, disqualified = pj["footprint"], pj["ctxn"], pj["disqualified"]
names = [None] * len(shape_id)
for sh, j in shape_id.items():
    names[j] = shape_str(sh)
decided = [e for e in U["active"] if ctxn.get(e, 0)]
undecidable = [e for e in U["active"] if not ctxn.get(e, 0)]
confined_dec = [e for e in decided if e not in disqualified]
print(f"\n=== FOOTPRINTS (engine namespace, after aliasing; {len(shape_id)} shapes) ===")
print(f"decisions: {len(U['active'])} active -> DECIDED {len(decided)} "
      f"({len(pj['coevaluated'])} by the co-evaluated keying, i.e. gates) "
      f"(strictly CONFINED {len(confined_dec)}, DISQUALIFIED {len(disqualified)}) / UNDECIDABLE {len(undecidable)}")
for e, hits in sorted(disqualified.items(), key=lambda kv: -len(kv[1]))[:10]:
    print(f"  DISQUALIFIED {len(hits):>3} two-sided shape(s)  {e[:80]}")
for e in sorted(decided, key=lambda e: (-bin(fp[e]).count('1'), -ctxn[e]))[:15]:
    print(f"  {bin(fp[e]).count('1'):>4} shapes {ctxn[e]:>6} ctx  {e[:90]}")
print(f"  empty DECIDED footprints: {sum(1 for e in decided if not fp[e])}")

order = {e: i for i, e in enumerate(U["expr_order"])}
confined, overlapping, und_pairs, dq_pairs = pj["confined"], pj["overlapping"], pj["undecidable"], pj["disq_pairs"]
new_cliques = [sorted(d, key=order.__getitem__) for d in pj["demands"]]
print(f"OR-sharing (round 5): {len(pj.get('or_pairs', ()))} pair(s) licensed by the 2x2 alone; "
      f"{len(pj.get('and_pairs', ()))} refused (AND / non-monotone / undetermined cell)")
print(f"\n=== PAIRS (co-evaluated) ===")
print(f"confined {len(confined)} / overlapping {len(overlapping)} / disqualified {len(dq_pairs)} / undecidable {len(und_pairs)}; "
      f"demand sets {len(U['cliques'])} -> {len(new_cliques)} ({pj['splits']} split)")
print("overlapping pairs — real dependence the flip-both probe was blind to (X11); top by shared shapes:")
for (a, b), n in sorted(overlapping.items(), key=lambda kv: -kv[1])[:12]:
    print(f"  shared={n:>3}  {a[:70]}  x  {b[:70]}")
    ex = [names[j] for j in range(len(names)) if fp[a] >> j & 1 and fp[b] >> j & 1][:2]
    for s_ in ex:
        print(f"           e.g. {s_[:110]}")


# ---- EMIT the OR-REFINED remaining set --------------------------------------
# THE FIX (coordinator, 2026-09-11). Every construction round so far emitted
# from `_exact_enum_emit.py`'s own census, which runs over the §16b
# foreclosure-pruned demand sets — `EMIT: ... (of remaining=52145853279826)`,
# the 5.2e13 universe. Under OR-confinement the demand is per-member sums
# inside each part, so §16b's product cubes are a DIFFERENT SET from what the
# OR census counts as remaining; a round built from them can only hit the OR
# remaining by accident. That is what 32 and 11 closed assignments look like.
# This emits from `new_cliques` — the SAME universe confinement_census.py
# censuses as 16c — so the targets are the ones actually outstanding.
known = EE.var_index(U["decls"])
cube_cap = int(os.environ.get("CUBE_CAP", "20000"))
print(f"\n=== EMIT over the OR-REFINED demand: {len(new_cliques)} parts ===", flush=True)
r = EE.census(U, new_cliques, known, {}, {}, cube_cap, 0, use_forecl=True,
              emit=os.environ["EMIT_OUT"],
              emit_max_per_set=int(os.environ.get("EMIT_MAX_PER_SET", "8")),
              emit_cap=int(os.environ.get("EMIT_CAP", "0")))
print(f"OR-refined: sets={r['cliques']} satisfiable={r['satisfiable']} "
      f"covered={r['covered']} remaining={r['remaining']} bounded={r.get('bounded_cliques')}")
