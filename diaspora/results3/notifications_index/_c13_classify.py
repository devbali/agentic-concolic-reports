#!/usr/bin/env python3
"""C13 — classify a construction drive PER KEY (RUNBOOK Phase 2: nothing is
residue until a constructed run was driven and explained per key).

Per demanded (gap, expr):
  HONOURED         some replay run of that gap evaluated the decision WITH the
                   demanded outcome;
  CONTRADICTED     it was EVALUATED and took the OTHER outcome in every replay
                   run despite its seed — the only shape that is impossibility
                   evidence;
  NEVER-EVALUATED  no replay run reached it — a statement about the walk, not
                   about the program.

Per gap: REALISED (one run took the WHOLE cube), else CONTRADICTED if any key
is contradicted, else UNEVALUATED.

usage: TAG=C13A python3 -u _c13_classify.py
"""
import glob, json, os, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals   # noqa: E402

_UNLEN = re.compile(r"len\(([^()]+)\)")
# error signatures, from §22 / _c11_residual.py (measured over 4 000 dumps)
_DECL = re.compile(r"first_name|as_api_response")
_FAITH = re.compile(r"mentions_container|linked_object")
_GON = re.compile(r"gon_helper")
TAG = os.environ.get("TAG", "C13A")
GAPS = os.environ.get("C13_GAPS", os.path.join(HERE, "_c13_gaps.json"))
OUT = os.environ.get("C13_CLASSIFY", os.path.join(HERE, f"_c13_classify_{TAG}.json"))

gaps = {g["id"]: g for g in json.load(open(GAPS))}
print(f"gaps: {len(gaps)}   tag: {TAG}", flush=True)
files = sorted(glob.glob(os.path.join(HERE, f"dump_*_{TAG}*.json")))
print(f"replay dumps: {len(files)}", flush=True)

hit = defaultdict(Counter)      # gap -> expr -> runs with demanded outcome
opp = defaultdict(Counter)      # gap -> expr -> runs with the other outcome
runs = Counter(); realised = Counter(); errs = Counter()
t0 = time.time()
for n, fp in enumerate(files):
    if n and n % 5000 == 0:
        print(f"  {n}/{len(files)}  {time.time()-t0:.0f}s", flush=True)
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    gid = (d.get("concolic_seeds") or {}).get("__c13gap__")
    if gid is None or gid not in gaps:
        continue
    runs[gid] += 1
    _e = d.get("error") or {}
    _m = f"{_e.get('type','')} {_e.get('message','')} {_e.get('traceback','')}"
    errs["" if not _e else
         ("declared" if _DECL.search(_m) else
          "faithful" if _FAITH.search(_m) else
          "gon" if _GON.search(_m) else "other")] += 1
    canonicalize_ordinals(d)
    pcs = defaultdict(set)
    for e in d.get("events") or ():
        if e.get("type") != "path_condition":
            continue
        ex = e["expr"]; tk = bool(e.get("taken"))
        pcs[ex].add(tk)
        ex2 = _UNLEN.sub(r"SYM_LEN_\1", ex)
        if ex2 != ex:
            pcs[ex2].add(tk)
    ok = True
    for ex, want in gaps[gid]["cube"]:
        if ex not in pcs:
            ok = False; continue
        if want in pcs[ex]:
            hit[gid][ex] += 1
        else:
            opp[gid][ex] += 1; ok = False
    if ok:
        realised[gid] += 1
    del d

keycnt = Counter(); gapv = Counter(); contra = Counter(); never = Counter()
per_gap = {}
for gid, g in gaps.items():
    if not runs[gid]:
        gapv["NOT-DRIVEN"] += 1
        per_gap[gid] = "NOT-DRIVEN"
        keycnt["NOT-DRIVEN"] += len(g["cube"])
        continue
    bad = []
    for ex, _w in g["cube"]:
        if hit[gid].get(ex):
            keycnt["HONOURED"] += 1
        elif opp[gid].get(ex):
            keycnt["CONTRADICTED"] += 1; contra[ex] += 1; bad.append(ex)
        else:
            keycnt["NEVER-EVALUATED"] += 1; never[ex] += 1
    v = "REALISED" if realised[gid] else ("CONTRADICTED" if bad else "UNEVALUATED")
    gapv[v] += 1
    per_gap[gid] = v

print(f"\n=== PER-KEY ({sum(keycnt.values())} demanded keys) ===")
for k in ("HONOURED", "CONTRADICTED", "NEVER-EVALUATED", "NOT-DRIVEN"):
    n = keycnt.get(k, 0)
    print(f"  {k:16s} {n:6d}  ({100.0*n/max(1,sum(keycnt.values())):.1f} %)")
print(f"\n=== PER-GAP ({len(gaps)}) ===")
for k in ("REALISED", "UNEVALUATED", "CONTRADICTED", "NOT-DRIVEN"):
    n = gapv.get(k, 0)
    print(f"  {k:14s} {n:5d}  ({100.0*n/max(1,len(gaps)):.1f} %)")
print(f"  replay runs: {sum(runs.values())}  fully realising: {sum(realised.values())}")
print("\ndump error census of the replay:", dict(errs.most_common(8)))
if contra:
    print("\n  DECISIONS THAT FLIPPED BACK DESPITE THEIR SEED (impossibility evidence):")
    for e, n in contra.most_common(15):
        print(f"    {n:5d} gaps  {e[:110]}")
else:
    print("\n  NO decision flipped back despite its seed.")
print("\n  decisions NEVER REACHED (a statement about the walk, not the program):")
for e, n in never.most_common(15):
    print(f"    {n:5d} gaps  {e[:110]}")
json.dump({"tag": TAG, "gaps": len(gaps), "per_key": dict(keycnt),
           "per_gap_verdict": dict(gapv), "runs": sum(runs.values()),
           "contradicted": contra.most_common(80),
           "never_evaluated": never.most_common(80),
           "errors": errs.most_common(20),
           "per_gap": per_gap}, open(OUT, "w"), indent=1)
print(f"\nC13-CLASSIFY-DONE {OUT}")
