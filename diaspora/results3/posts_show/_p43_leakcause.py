#!/usr/bin/env python3
"""P43 — WHY DID THE FOOTPRINT LEAK?  Corpus producer census for the three
shapes that refute the 189 LEAK pairs.

Read-only.  One pass over a dump list (N workers).  For every tracked decision
D and every LEAKED shape Z, the corpus contingency

      n(D=T, Z present) n(D=T, Z absent) n(D=F, Z present) n(D=F, Z absent)

restricted to runs where D is single-sided.  Two questions it answers:

  * Is Z STRICTLY ONE-SIDED w.r.t. D across the corpus?  If Z appears on BOTH
    arms of D in real runs, then Z is not D's to control: the gate replay's
    dZ was collateral of the seed perturbation, and the LEAK is a
    mis-measurement of the FOOTPRINT, not evidence that D produces Z.
  * WHICH decision IS Z's producer — the decision for which Z is strictly
    one-sided with both arms populated.  That is the "third decision" the
    §16c criterion asks for by name.

Same currency as the gate: `call_shape` under KEEP_NOTES.  Verdict: P43LC-DONE.
"""
import glob, importlib, json, os, sys, time
from collections import Counter, defaultdict
from multiprocessing import Pool

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
from concolic_engine.assumptions import call_shape, shape_str  # noqa: E402

LEAKED = [
 'ActiveRecord::Associations::SingularAssociation.find_target | SELECT "posts".* FROM "posts" WHERE "posts"."guid" = ? | ',
 'Photo.url | Photo#url | ',
 'Photo.url | Photo#url | name:str',
]

def work(paths):
    cnt = defaultdict(lambda: [0, 0, 0, 0, 0, 0])   # per (expr, zi): TT TF FT FF ... (+ unused)
    seen = Counter(); nz = Counter(); n = 0
    for p in paths:
        try: d = CR.fix_len_names(json.load(open(p)))
        except Exception: continue
        if hasattr(CR, "canonicalize_ordinals"):
            try: CR.canonicalize_ordinals(d)
            except Exception: pass
        out = {}; shapes = set()
        for ev in d.get("events") or ():
            t = ev.get("type")
            if t == "path_condition":
                out.setdefault(ev.get("expr"), set()).add(bool(ev.get("taken")))
            elif t == "symbolic_call" and ev.get("result_name"):
                shapes.add(shape_str(call_shape(ev.get("target"), ev.get("note"), ev.get("args"))))
        n += 1
        zpres = [z in shapes for z in LEAKED]
        for i, z in enumerate(zpres):
            if z: nz[i] += 1
        for e, v in out.items():
            if len(v) != 1: continue
            seen[e] += 1
            side = True in v
            for i, z in enumerate(zpres):
                cnt[(e, i)][(0 if side else 2) + (0 if z else 1)] += 1
    return dict(cnt), dict(seen), dict(nz), n

if __name__ == "__main__":
    t0 = time.time()
    DL = os.environ.get("DUMP_LIST")
    if DL and DL != "-":
        files = [l.strip() for l in open(DL) if l.strip()]
        files = [f if os.path.isabs(f) else os.path.join(BATCH, f) for f in files]
    else:
        files = sorted(glob.glob(os.path.join(BATCH, "dump_*.json")))
    W = int(os.environ.get("WORKERS", "4"))
    print(f"{len(files)} dumps, {W} workers", flush=True)
    CH = [files[i::W * 8] for i in range(W * 8)]
    tot = defaultdict(lambda: [0, 0, 0, 0, 0, 0]); seen = Counter(); nz = Counter(); N = 0
    with Pool(W) as pool:
        for k, (c, s, z, n) in enumerate(pool.imap_unordered(work, CH)):
            for key, v in c.items():
                t = tot[key]
                for i in range(4): t[i] += v[i]
            seen.update(s); nz.update(z); N += n
            print(f"  chunk {k+1}/{len(CH)}  N={N}  {time.time()-t0:.0f}s", flush=True)
    print(f"\nruns {N}   elapsed {time.time()-t0:.0f}s")
    for i, z in enumerate(LEAKED):
        print(f"\n===== LEAKED SHAPE {i}: {z[:110]}")
        print(f"      present in {nz.get(i,0)} of {N} runs ({100.0*nz.get(i,0)/max(N,1):.1f} %)")
        rows = []
        for (e, j), v in tot.items():
            if j != i: continue
            tt, tf, ft, ff = v[:4]
            if tt + tf == 0 or ft + ff == 0: continue        # decision not two-armed
            rows.append((e, tt, tf, ft, ff))
        # STRICT producers: Z present on exactly one arm, never the other
        prod = [r for r in rows if (r[1] and not r[3]) or (r[3] and not r[1])]
        both = [r for r in rows if r[1] and r[3]]
        print(f"      two-armed decisions: {len(rows)}   STRICT one-sided for Z: {len(prod)}"
              f"   Z on BOTH arms: {len(both)}")
        print("      --- STRICT one-sided (candidate producers), top 12 by support ---")
        for e, tt, tf, ft, ff in sorted(prod, key=lambda r: -(r[1] + r[3]))[:12]:
            print(f"        T:{tt:7d}/{tt+tf:7d}  F:{ft:7d}/{ft+ff:7d}   {e[:105]}")
    if JSON_OUT:
        json.dump({"N": N, "shapes": LEAKED, "nz": {str(k): v for k, v in nz.items()},
                   "counts": {f"{e}\x00{j}": v[:4] for (e, j), v in tot.items()},
                   "seen": seen}, open(JSON_OUT, "w"))
        print("wrote", JSON_OUT)
    print("P43LC-DONE")
