#!/usr/bin/env python3
"""FOOTPRINT CENSUS — the matched-context differential, per tracked decision.

Owner's reframe (2026-09-11): what tier 2's cross-rep pairs have is not
independence, it is SEPARABLE EFFECTS — A and B gate DISJOINT sets of
statements. That is a CORPUS MEASUREMENT, not a flip-both probe, so X11 does
not apply to it.

footprint(D) = the set of target-call statement SHAPES whose PRESENCE differs
between runs that match on every OTHER evaluated decision and differ only on
D's outcome. Method is `notifications_index/_TRACE_PROJECTION_20260909.md` §4
(exact matched contexts — all other tracked exprs identical), which is the
keying that survived there; the variant-merged keying was shown invalid and is
not used.

Reported per decision: footprint size, number of matched contexts it was
measured over, and UNDECIDABLE where NO matched context exists. Undecidable is
NOT empty — a decision with no matched context has no measured footprint and
can never be called separable from anything.

Everything is integer masks: a run is (evaluated, taken, both-sided, trace), a
context key is those masks with D's bit cleared, so grouping is exact and
cheap rather than 137 x 31 054 set constructions.
"""
import json, os, sys, time
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from end_to_end_completion_checker.assumption import assumption_checker as AC  # noqa: E402
import coverage_report as CR  # noqa: E402

files = [l.strip() for l in open(os.environ["DUMP_LIST"]) if l.strip()]
files = [f if os.path.isabs(f) else os.path.join(HERE, f) for f in files]
print(f"scanning {len(files)} dumps", flush=True)

t0 = time.time()
eidx, shape_id = {}, {}
runs = []
for n, p in enumerate(files):
    try:
        d = json.load(open(p))
    except Exception:
        continue
    # CANONICALISE (fix, 2026-09-11). The first run of this census read RAW
    # dump exprs while every candidate pair is stated in the engine's
    # CANONICAL (statement-identified) namespace, so 791 of 1 733 pairs could
    # not be looked up at all and were miscounted as UNDECIDABLE. The engine's
    # own rewrite is applied here, exactly as `_exact_enum_emit.load_runs`
    # does, so both sides speak one namespace.
    if hasattr(CR, "canonicalize_ordinals"):
        CR.canonicalize_ordinals(d)
    ev = tk = bo = 0
    seen = {}
    for e in d.get("events") or ():
        if e.get("type") == "path_condition":
            x = str(e.get("expr", ""))
            i = eidx.get(x)
            if i is None:
                i = eidx[x] = len(eidx)
            t = bool(e.get("taken"))
            if i in seen and seen[i] != t:
                bo |= 1 << i
            seen[i] = t
            ev |= 1 << i
            if t:
                tk |= 1 << i
    tr = 0
    for s in AC.access_trace(d):
        j = shape_id.get(s)
        if j is None:
            j = shape_id[s] = len(shape_id)
        tr |= 1 << j
    runs.append((ev, tk, bo, tr))
    del d
    if n % 5000 == 0:
        print(f"  [{n}/{len(files)}] exprs={len(eidx)} shapes={len(shape_id)} "
              f"{time.time()-t0:.0f}s", flush=True)
print(f"loaded {len(runs)} runs; {len(eidx)} tracked exprs; "
      f"{len(shape_id)} distinct trace shapes; {time.time()-t0:.0f}s", flush=True)

names = [None] * len(eidx)
for e, i in eidx.items():
    names[i] = e

# ---- matched contexts -----------------------------------------------------
buckets = defaultdict(lambda: [0, 0, 0, 0])   # (i, ctx) -> [unionT, unionF, nT, nF]
for ev, tk, bo, tr in runs:
    m = ev & ~bo                               # single-sided decisions only
    x = m
    while x:
        b = x & -x
        i = b.bit_length() - 1
        x ^= b
        ctx = (ev & ~b, tk & ~b, bo)
        sl = buckets[(i, ctx)]
        if tk & b:
            sl[0] |= tr; sl[2] += 1
        else:
            sl[1] |= tr; sl[3] += 1
print(f"matched-context buckets: {len(buckets)}  ({time.time()-t0:.0f}s)", flush=True)

fp = [0] * len(eidx)
ctxn = [0] * len(eidx)
for (i, _ctx), (ut, uf, nt, nf) in buckets.items():
    if nt and nf:
        ctxn[i] += 1
        fp[i] |= ut ^ uf

dec = [i for i in range(len(eidx)) if ctxn[i] > 0]
und = [i for i in range(len(eidx)) if ctxn[i] == 0]
print(f"\n=== FOOTPRINT CENSUS ===")
print(f"tracked decisions      : {len(eidx)}")
print(f"DECIDED (>=1 matched context): {len(dec)}")
print(f"UNDECIDABLE (no matched context): {len(und)}")
print(f"\n{'footprint':>10}{'contexts':>10}  decision")
for i in sorted(dec, key=lambda i: (-fp[i].bit_count(), -ctxn[i]))[:25]:
    print(f"{fp[i].bit_count():>10}{ctxn[i]:>10}  {names[i][:88]}")
print(f"\nUNDECIDABLE (first 12):")
for i in und[:12]:
    print(f"{'-':>10}{0:>10}  {names[i][:88]}")
zero = [i for i in dec if fp[i] == 0]
print(f"\ndecisions with an EMPTY measured footprint: {len(zero)} of {len(dec)}"
      "   (they change no statement shape in any matched context)")

json.dump({"exprs": names,
           "footprint": [str(f) for f in fp],
           "contexts": ctxn,
           "n_shapes": len(shape_id), "n_runs": len(runs),
           "decided": dec, "undecidable": und},
          open(os.path.join(HERE, "_footprints.json"), "w"))
print(f"\nwrote _footprints.json ({time.time()-t0:.0f}s)")
