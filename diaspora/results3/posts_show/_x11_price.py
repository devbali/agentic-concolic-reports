#!/usr/bin/env python3
"""X11 PRICING — what a SYMMETRIC flip-both test would decide on the six controls.

The shipped test FAILs only when the combination ADDS a shape:

    novel = trace(AB) - (base u trace(A) u trace(B));   FAIL iff novel

The proposed symmetric test compares the combination against the trace
PREDICTED under independence -- base with BOTH deltas applied:

    removed_X = base - trace(X);        added_X = trace(X) - base
    predicted = (base - removed_A - removed_B) | added_A | added_B
    FAIL iff trace(AB) != predicted

which additionally catches REMOVAL INTERACTION (A changes what B removes, or
the combination removes something neither single does).

Probes are driven IN MEMORY through the engine's own ProbeCache -- NOT with
`--keep`, which would leave probe dumps in the batch dir where a later
`find dump_*.json` would glob them in as corpus evidence.
"""
import importlib, json, os, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from end_to_end_completion_checker.assumption import assumption_checker as AC  # noqa: E402

cfg = json.load(open(os.path.join(HERE, "assumption_manifest.json")))
if cfg.get("canonicalize"):
    m, f = cfg["canonicalize"].split(":")
    sys.path.insert(0, cfg["batch_dir"])
    AC._CANON_FN = getattr(importlib.import_module(m), f)
    AC._ALIASES = []
name = sys.argv[1] if len(sys.argv) > 1 else "_tier2_negcontrol.json"
declared = json.load(open(os.path.join(HERE, name)))
print(f"== X11 pricing on {len(declared)} pairs from {name} ==", flush=True)

cache = AC.ProbeCache(cfg, False)


def traces(a, plan):
    ea, eb = a["expr_a"], a["expr_b"]
    da, db = AC.expr_dimension(ea), AC.expr_dimension(eb)
    snap = AC.pick_snapshot_with(cfg["batch_dir"], [ea, eb], [da, db])
    if snap is None:
        return None
    sp, sd = snap
    scen = (sd.get("concolic_scenario") or {}).get("name")
    seeds = dict(sd.get("concolic_seeds") or {})
    fa = AC.flipped_seeds(sd, seeds, ea, da)
    fb = AC.flipped_seeds(sd, seeds, eb, db)
    if fa is None or fb is None:
        return None
    rdb = AC._runtime_key(sd, db)
    fab = dict(fa)
    if rdb in fb:
        fab[rdb] = fb[rdb]
    else:
        fab.pop(rdb, None)
    cache.planning = plan
    ra, rb, rab = (cache.run(x, scen, f"x11_{i}") for i, x in enumerate((fa, fb, fab)))
    if plan:
        return "planned"
    if None in (ra, rb, rab):
        return None
    return (set(AC.access_trace(sd)), set(AC.trace_of(ra)),
            set(AC.trace_of(rb)), set(AC.trace_of(rab)), os.path.basename(sp))


for a in declared:
    try:
        traces(a, True)
    except Exception:
        pass
cache.planning = False
print(f"  [{len(cache.wanted)} distinct probes]", flush=True)
cache.execute()

rows = []
for a in declared:
    try:
        t = traces(a, False)
    except Exception as exc:
        t = None
        print(f"  ERROR {type(exc).__name__}: {exc}", flush=True)
    if not t:
        rows.append(dict(desc=a["description"][:70], shipped="NOT-TESTABLE",
                         symmetric="NOT-TESTABLE"))
        continue
    base, ta, tb, tab, snap = t
    novel = tab - (base | ta | tb)
    rem_a, add_a = base - ta, ta - base
    rem_b, add_b = base - tb, tb - base
    predicted = (base - rem_a - rem_b) | add_a | add_b
    extra, missing = tab - predicted, predicted - tab
    rows.append(dict(
        desc=a["description"][:70], snapshot=snap,
        shipped="FAIL" if novel else "PASS",
        symmetric="FAIL" if (extra or missing) else "PASS",
        novel=len(novel), removed_A=len(rem_a), removed_B=len(rem_b),
        added_A=len(add_a), added_B=len(add_b),
        extra=len(extra), missing=len(missing),
        base=len(base), tA=len(ta), tB=len(tb), tAB=len(tab)))
    r = rows[-1]
    print(f"  shipped={r['shipped']:<5} symmetric={r['symmetric']:<5} "
          f"|base|={r['base']} |A|={r['tA']} |B|={r['tB']} |AB|={r['tAB']} "
          f"remA={r['removed_A']} remB={r['removed_B']} addA={r['added_A']} "
          f"addB={r['added_B']} novel={r['novel']} extra={r['extra']} "
          f"missing={r['missing']}", flush=True)
    print(f"      {r['desc']}", flush=True)

json.dump(rows, open(os.path.join(HERE, "_x11_pricing.json"), "w"), indent=1)
print("\n=== X11 PRICING SUMMARY ===")
print("  shipped   :", dict(Counter(r["shipped"] for r in rows)))
print("  symmetric :", dict(Counter(r["symmetric"] for r in rows)))
print("wrote _x11_pricing.json")
