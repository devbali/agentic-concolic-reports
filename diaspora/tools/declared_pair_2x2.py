#!/usr/bin/env python3
"""DECLARED-PAIR 2x2 CENSUS -- does the corpus contradict a DECLARED
IndependenceAssumption?

    DUMP_LIST=<file|-> python3 declared_pair_2x2.py <batch_dir> [--json-out f]

Read-only. For every DECLARED IndependenceAssumption pair (from the batch's
_assumptions_declared.json) that the corpus CO-EVALUATES (both decisions
single-sided in some profile, both polarities of each seen), build the 2x2 of
target-call SHAPE presence over the co-evaluated profiles and classify every
shape with the engine's own `classify_cells`:

  benign (OR / A-only / B-only / ALWAYS / NEVER / OR-family) -> no combination
  yields a presence the singles do not explain;
  AND / NON-MONOTONE                                          -> INTERACTION;
  UNDETERMINED(AND?)                                          -> open.

This is `infer_pair_tables` + `classify_cells` (coverage.py:1822-1898) applied
to DECLARED pairs, which nothing in the engine does today: declared
independence cuts the edge at coverage.py step 5, BEFORE confinement (step 5d)
ever sees the demand sets, so no footprint is ever measured for a declared
pair and §16c can neither classify it OVERLAPPING nor withdraw it.

Nothing here is endpoint-specific; the batch supplies its own loader.
"""
import glob, importlib, json, os, sys, time
from collections import Counter, defaultdict

BATCH = os.path.abspath(sys.argv[1])
args = sys.argv[2:]
JSON_OUT = args[args.index("--json-out") + 1] if "--json-out" in args else None
sys.path.insert(0, BATCH)
sys.path.insert(0, "/home/dev/project/src")
CR = importlib.import_module("coverage_report")
# C1 TRACE CURRENCY: some batches' fix_len_names pops `note`/`args`, which are
# two thirds of call_shape -- the footprint then degenerates to the bare target
# name. KEEP_NOTES=1 restores them for THIS census by wrapping the batch's own
# loader (tools/confinement_census.py does the same).
if os.environ.get("KEEP_NOTES") == "1":
    _shipped_fix = CR.fix_len_names

    def _fix_keep(dump):
        saved = [(e.get("note"), e.get("args")) for e in dump.get("events") or ()]
        out = _shipped_fix(dump)
        for ev, (n_, a_) in zip(out.get("events") or (), saved):
            if n_ is not None:
                ev["note"] = n_
            if a_ is not None:
                ev["args"] = a_
        return out

    CR.fix_len_names = _fix_keep
    print("[KEEP_NOTES=1] note/args retained for shape currency", flush=True)
from concolic_engine.assumptions import call_shape, shape_str      # noqa: E402
from concolic_engine.coverage import classify_cells                # noqa: E402

t0 = time.time()
DL = os.environ.get("DUMP_LIST")
if DL and DL != "-":
    files = [l.strip() for l in open(DL) if l.strip()]
    files = [f if os.path.isabs(f) else os.path.join(BATCH, f) for f in files]
else:
    files = sorted(glob.glob(os.path.join(BATCH, "dump_*.json")))
print(f"batch {BATCH}\n{len(files)} dumps (read-only)", flush=True)

decl = json.load(open(os.environ.get("PAIRS_FILE")
                    or os.path.join(BATCH, "_assumptions_declared.json")))
pairs = [(a["expr_a"], a["expr_b"], a.get("description", ""))
         for a in decl if a.get("type") == "IndependenceAssumption"
         and a.get("expr_a") and a.get("expr_b")]
print(f"{len(pairs)} declared IndependenceAssumption pairs", flush=True)
wanted = set()
for a, b, _d in pairs:
    wanted.add(a); wanted.add(b)

shape_id = {}
prof = {}                      # profkey -> [outcomes dict, shape-mask, n runs]
for n, p in enumerate(files):
    if n and n % 4000 == 0:
        print(f"  {n}/{len(files)}  {time.time()-t0:.0f}s  profiles={len(prof)}", flush=True)
    try:
        d = CR.fix_len_names(json.load(open(p)))
    except Exception:
        continue
    if hasattr(CR, "canonicalize_ordinals"):
        try:
            CR.canonicalize_ordinals(d)
        except Exception:
            pass
    out, mask = {}, 0
    for ev in d.get("events") or ():
        ty = ev.get("type")
        if ty == "path_condition":
            e = ev.get("expr")
            if e in wanted:
                out.setdefault(e, set()).add(bool(ev.get("taken")))
        elif ty == "symbolic_call" and ev.get("result_name"):
            sh = call_shape(ev.get("target"), ev.get("note"), ev.get("args"))
            j = shape_id.get(sh)
            if j is None:
                j = shape_id[sh] = len(shape_id)
            mask |= 1 << j
    key = (frozenset((e, frozenset(v)) for e, v in out.items()), mask)
    rec = prof.get(key)
    if rec is None:
        prof[key] = [out, mask, 1]
    else:
        rec[2] += 1

print(f"loaded: {len(prof)} distinct (outcome, trace) profiles, "
      f"{len(shape_id)} distinct shapes, {time.time()-t0:.0f}s", flush=True)
shape_names = [""] * len(shape_id)
for sh, j in shape_id.items():
    shape_names[j] = shape_str(sh)

profs = list(prof.values())
# per pair: cell (sa, sb) -> union mask
tables = defaultdict(dict)
pairset = {(a, b) for a, b, _ in pairs}
for out, mask, _n in profs:
    ev = {e: (True in v) for e, v in out.items() if len(v) == 1}
    for a, b in pairset:
        if a in ev and b in ev:
            d = tables[(a, b)]
            c = (ev[a], ev[b])
            d[c] = d.get(c, 0) | mask

rows, tally = [], Counter()
for a, b, desc in pairs:
    cells = tables.get((a, b))
    if not cells:
        tally["NOT-CO-EVALUATED (inert)"] += 1
        continue
    if len(cells) < 2:
        tally["ONE CELL ONLY"] += 1
        continue
    universe = 0
    for m in cells.values():
        universe |= m
    bad, undet, nb = [], [], 0
    u = universe
    while u:
        bb = u & -u
        j = bb.bit_length() - 1
        u ^= bb
        cls = classify_cells({k: (1 if m >> j & 1 else 0) for k, m in cells.items()})
        if cls in ("AND", "NON-MONOTONE"):
            bad.append((shape_names[j], cls))
        elif cls in ("UNDETERMINED", "UNDETERMINED(AND?)"):
            undet.append((shape_names[j], cls))
        else:
            nb += 1
    verdict = ("INTERACTION" if bad else
               "OPEN" if undet else "BENIGN")
    tally[verdict] += 1
    tally[f"  cells={len(cells)}"] += 1
    if bad or undet:
        rows.append({"expr_a": a, "expr_b": b, "description": desc,
                     "verdict": verdict, "cells": len(cells),
                     "n_benign": nb,
                     "interaction": bad[:8], "n_interaction": len(bad),
                     "undetermined": undet[:4], "n_undetermined": len(undet)})

print("\n=== DECLARED-PAIR 2x2 RESULT ===")
for k, v in sorted(tally.items()):
    print(f"  {k:<28} {v}")
rows.sort(key=lambda r: (-r["n_interaction"], -r["n_undetermined"]))
print(f"\n--- {len(rows)} pair(s) with a non-benign shape; top 15 ---")
for r in rows[:15]:
    print(f"\n[{r['verdict']}] AND/NM={r['n_interaction']} UNDET={r['n_undetermined']} "
          f"benign={r['n_benign']} cells={r['cells']}")
    print(f"   A: {r['expr_a'][:100]}")
    print(f"   B: {r['expr_b'][:100]}")
    print(f"   {r['description'][:130]}")
    for s, c in r["interaction"][:4]:
        print(f"     {c:<13} {s[:150]}")
    for s, c in r["undetermined"][:2]:
        print(f"     {c:<13} {s[:150]}")
if JSON_OUT:
    json.dump({"batch": BATCH, "pairs": len(pairs), "profiles": len(profs),
               "shapes": len(shape_id), "tally": dict(tally), "rows": rows},
              open(JSON_OUT, "w"), indent=1)
    print(f"\nwrote {JSON_OUT}")
print(f"elapsed {time.time()-t0:.0f}s")
