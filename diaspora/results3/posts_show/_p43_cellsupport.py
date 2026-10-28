#!/usr/bin/env python3
"""P43 — CELL SUPPORT for the declared-pair 2x2.

Same load and same currency as `tools/declared_pair_2x2.py` (KEEP_NOTES), but
instead of a per-shape verdict it records, per pair and per 2x2 cell, how many
distinct (outcome,trace) PROFILES and how many RUNS sit in it, and for every
shape the checker classifies AND/NON-MONOTONE, the per-cell PROFILE COUNT in
which that shape is present.

Point: an `AND` earned in a cell holding one profile is thin evidence; an `AND`
whose present-cell holds thousands of profiles and whose three absent cells
hold thousands each is not.  Read-only.  Verdict: P43CS-DONE.
"""
import glob, importlib, json, os, sys, time
from collections import Counter, defaultdict

BATCH = os.path.abspath(sys.argv[1])
JSON_OUT = sys.argv[sys.argv.index("--json-out") + 1] if "--json-out" in sys.argv else None
sys.path.insert(0, BATCH); sys.path.insert(0, "/home/dev/project/src")
CR = importlib.import_module("coverage_report")
_shipped_fix = CR.fix_len_names
def _fix_keep(dump):
    saved = [(e.get("note"), e.get("args")) for e in dump.get("events") or ()]
    out = _shipped_fix(dump)
    for ev, (n_, a_) in zip(out.get("events") or (), saved):
        if n_ is not None: ev["note"] = n_
        if a_ is not None: ev["args"] = a_
    return out
CR.fix_len_names = _fix_keep
from concolic_engine.assumptions import call_shape, shape_str      # noqa: E402
from concolic_engine.coverage import classify_cells                # noqa: E402

t0 = time.time()
files = [l.strip() for l in open(os.environ["DUMP_LIST"]) if l.strip()]
files = [f if os.path.isabs(f) else os.path.join(BATCH, f) for f in files]
decl = json.load(open(os.environ["PAIRS_FILE"]))
pairs = [(a["expr_a"], a["expr_b"], a.get("description", "")) for a in decl
         if a.get("type") == "IndependenceAssumption"]
ONLY = os.environ.get("ONLY_CLASS")
if ONLY:
    pairs = [p for p in pairs if p[2].startswith(f"P43CLASS={ONLY}")]
print(f"{len(files)} dumps, {len(pairs)} pairs", flush=True)
wanted = set()
for a, b, _ in pairs: wanted.add(a); wanted.add(b)

shape_id = {}
prof = {}
for n, p in enumerate(files):
    if n and n % 8000 == 0:
        print(f"  {n}/{len(files)} {time.time()-t0:.0f}s profiles={len(prof)}", flush=True)
    try: d = CR.fix_len_names(json.load(open(p)))
    except Exception: continue
    if hasattr(CR, "canonicalize_ordinals"):
        try: CR.canonicalize_ordinals(d)
        except Exception: pass
    out, mask = {}, 0
    for ev in d.get("events") or ():
        ty = ev.get("type")
        if ty == "path_condition":
            e = ev.get("expr")
            if e in wanted: out.setdefault(e, set()).add(bool(ev.get("taken")))
        elif ty == "symbolic_call" and ev.get("result_name"):
            sh = call_shape(ev.get("target"), ev.get("note"), ev.get("args"))
            j = shape_id.get(sh)
            if j is None: j = shape_id[sh] = len(shape_id)
            mask |= 1 << j
    key = (frozenset((e, frozenset(v)) for e, v in out.items()), mask)
    rec = prof.get(key)
    if rec is None: prof[key] = [out, mask, 1]
    else: rec[2] += 1
names = [""] * len(shape_id)
for sh, j in shape_id.items(): names[j] = shape_str(sh)
print(f"{len(prof)} profiles, {len(shape_id)} shapes, {time.time()-t0:.0f}s", flush=True)

pairset = {(a, b) for a, b, _ in pairs}
union = defaultdict(dict); nprof = defaultdict(Counter); nrun = defaultdict(Counter)
percell = defaultdict(lambda: defaultdict(Counter))      # pair -> cell -> shape -> nprofiles
for out, mask, nr in prof.values():
    ev = {e: (True in v) for e, v in out.items() if len(v) == 1}
    for a, b in pairset:
        if a in ev and b in ev:
            c = (ev[a], ev[b]); k = (a, b)
            union[k][c] = union[k].get(c, 0) | mask
            nprof[k][c] += 1; nrun[k][c] += nr
            m = mask; pc = percell[k][c]
            while m:
                bb = m & -m; j = bb.bit_length() - 1; m ^= bb; pc[j] += 1

rows = []
for a, b, desc in pairs:
    k = (a, b); cells = union.get(k)
    if not cells or len(cells) < 2: continue
    u = 0
    for m in cells.values(): u |= m
    bad = []
    m = u
    while m:
        bb = m & -m; j = bb.bit_length() - 1; m ^= bb
        cls = classify_cells({c: (1 if mm >> j & 1 else 0) for c, mm in cells.items()})
        if cls in ("AND", "NON-MONOTONE"):
            bad.append({"shape": names[j], "cls": cls,
                        "present_profiles": {str(c): percell[k][c].get(j, 0) for c in cells},
                        "cell_profiles": {str(c): nprof[k][c] for c in cells},
                        "cell_runs": {str(c): nrun[k][c] for c in cells}})
    if bad:
        rows.append({"expr_a": a, "expr_b": b, "description": desc,
                     "cells": len(cells), "bad": bad})
print(f"\n{len(rows)} pair(s) with an AND/NON-MONOTONE shape")
thin = 0
for r in rows:
    mn = min(min(v for kk, v in b["cell_profiles"].items()) for b in r["bad"])
    if mn < 10: thin += 1
print(f"pairs whose thinnest 2x2 cell holds < 10 profiles: {thin}")
allbad = [b for r in rows for b in r["bad"]]
print(f"{len(allbad)} AND/NM shape instances")
import statistics
mins = [min(v for v in b["cell_profiles"].values()) for b in allbad]
if mins:
    print(f"  min cell profiles per instance: min={min(mins)} median={statistics.median(mins)} max={max(mins)}")
pres = [max(v for v in b["present_profiles"].values()) for b in allbad]
if pres:
    print(f"  profiles in the PRESENT cell:   min={min(pres)} median={statistics.median(pres)} max={max(pres)}")
if JSON_OUT:
    json.dump({"rows": rows, "profiles": len(prof)}, open(JSON_OUT, "w"), indent=1)
    print("wrote", JSON_OUT)
print("P43CS-DONE")
