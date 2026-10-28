#!/usr/bin/env python3
"""Did the one-flip round CONSTRUCT a matched context for the undecidable
decisions? (§76.2 class (b).)

§16c's exact keying, verbatim: a matched context for D is two runs that agree
on every OTHER evaluated expression (same evaluated set, same outcomes, same
both-sided set) and differ only in D's outcome. A run that recorded D both
ways is in none of D's contexts.

Scans a DUMP_LIST (use the round's own dumps PLUS their bases, or the whole
pruned snapshot) and reports, per target, whether such a pair now exists.
"""
import glob, json, os, sys, time
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from coverage_report import canonicalize_ordinals  # noqa: E402

targets = json.load(open(os.path.join(HERE, os.environ.get(
    "UNDEC_IN", "_undecidable_kinds_OD.json"))))
TGT = targets.get("addressable") or targets["undecidable"]
print(f"targets: {len(TGT)}")
files = []
for pat in os.environ.get("PATTERNS", "").split(","):
    if pat.strip():
        files += sorted(glob.glob(os.path.join(HERE, pat.strip())))
DL = os.environ.get("DUMP_LIST")
if DL:
    files += [l.strip() for l in open(DL) if l.strip()]
files = sorted(set(files))
print(f"dumps: {len(files)}", flush=True)

# per run: expr -> 0 (only False), 1 (only True), 2 (both)
runs = []
t0 = time.time()
for i, fp in enumerate(files):
    if i and i % 10000 == 0:
        print(f"  [{i}/{len(files)}] {time.time()-t0:.0f}s", flush=True)
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    canonicalize_ordinals(d)
    o = defaultdict(set)
    for e in d.get("events") or ():
        if e.get("type") == "path_condition":
            o[str(e.get("expr", ""))].add(bool(e.get("taken")))
    runs.append({k: (2 if len(v) > 1 else (1 if True in v else 0)) for k, v in o.items()})
    del d
print(f"loaded {len(runs)} run profiles in {time.time()-t0:.0f}s", flush=True)

found, absent = [], []
for e in TGT:
    ctx = defaultdict(set)
    n_eval = 0
    for r in runs:
        v = r.get(e)
        if v is None or v == 2:
            continue
        n_eval += 1
        key = frozenset((k, s) for k, s in r.items() if k != e)
        ctx[hash(key)].add(v)
    hits = sum(1 for s in ctx.values() if len(s) > 1)
    (found if hits else absent).append((e, hits, n_eval, len(ctx)))
print(f"\n=== MATCHED CONTEXT NOW EXISTS: {len(found)} of {len(TGT)} ===")
for e, h, n, c in sorted(found, key=lambda t: -t[1]):
    print(f"  CONSTRUCTED  contexts={h:<5} single-sided runs={n:<6} keys={c:<6} {e[:88]}")
print(f"\n=== STILL NO MATCHED CONTEXT: {len(absent)} ===")
for e, h, n, c in sorted(absent, key=lambda t: -t[2]):
    print(f"  NONE         single-sided runs={n:<6} distinct keys={c:<6} {e[:88]}")
json.dump({"constructed": [[e, h, n, c] for e, h, n, c in found],
           "still_none": [[e, h, n, c] for e, h, n, c in absent],
           "dumps": len(files)},
          open(os.path.join(HERE, os.environ.get("OUT", "_matched_ctx.json")), "w"), indent=1)
print("\nMATCHED CTX DONE")
