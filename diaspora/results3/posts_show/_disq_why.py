#!/usr/bin/env python3
"""WHY is each of the 73 DISQUALIFIED decisions disqualified? (read-only)

Strict one-sidedness removes a decision D when some shape in its footprint also
appears with D on its OFF side. That happens for two very different reasons:

  OR-SHARED      the off-side appearance is explained by ANOTHER producer E
                 whose 2x2 with that shape is MONOTONE (present under either
                 alone and under both) — the OR case, one level EARLIER than
                 the pair test, so D never reaches it;
  TWO-SIDED      genuinely two-sided: present AND absent with D on the same
                 side across matched contexts, or an AND / non-monotone cell —
                 real evidence that D does not control the shape.

Streaming scan (raw dumps, canonicalised, bitmasks) so it fits a 2 G cap; the
engine's own `call_shape` is used so the shapes are the engine's shapes.

THIS IS A MEASUREMENT, NOT A PROPOSAL. Admitting OR-shared decisions at the
DECISION level would weaken strict one-sidedness, which the owner asked for and
asked the tests to try to disprove. Nothing here is implemented or installed.
"""
import json, os, sys
from collections import defaultdict
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, ".")
from concolic_engine.assumptions import call_shape, shape_str
from coverage_report import canonicalize_ordinals

DISQ = set(json.load(open("_and_reconcile.json"))["disqualified_decisions"])
files = [l.strip() for l in open(os.environ["DUMP_LIST"]) if l.strip()]
print(f"disqualified decisions: {len(DISQ)}; scanning {len(files)} dumps", flush=True)

eidx, sidx = {}, {}
runs = []
for n, p in enumerate(files):
    try: d = json.load(open(p))
    except Exception: continue
    canonicalize_ordinals(d)
    out = defaultdict(set); tr = 0
    for ev in d.get("events") or ():
        t = ev.get("type")
        if t == "path_condition":
            out[str(ev.get("expr", ""))].add(bool(ev.get("taken")))
        elif t == "symbolic_call" and ev.get("result_name"):
            sh = shape_str(call_shape(ev.get("target"), ev.get("note"), ev.get("args") or {}))
            j = sidx.setdefault(sh, len(sidx)); tr |= 1 << j
    ev_m = tk_m = bo_m = 0
    for e, o in out.items():
        i = eidx.setdefault(e, len(eidx)); ev_m |= 1 << i
        if True in o: tk_m |= 1 << i
        if len(o) > 1: bo_m |= 1 << i
    runs.append((ev_m, tk_m, bo_m, tr))
    del d
    if n % 8000 == 0: print(f"  [{n}/{len(files)}] exprs={len(eidx)} shapes={len(sidx)}", flush=True)
print(f"loaded {len(runs)} runs; {len(eidx)} exprs; {len(sidx)} shapes", flush=True)
names = [None]*len(eidx)
for e, i in eidx.items(): names[i] = e

def sides(i):
    """shapes seen with decision i on side True / False (single-sided runs)."""
    on = off = 0
    for ev, tk, bo, tr in runs:
        if not (ev >> i & 1) or (bo >> i & 1): continue
        if tk >> i & 1: on |= tr
        else: off |= tr
    return on, off

def monotone_explainer(sbit, i):
    """Is shape `sbit` OR-monotone under some OTHER decision E? i.e. E has a
    2x2 for this shape with no cell that is present-only-with-both and no
    same-side present/absent split."""
    for j in range(len(eidx)):
        if j == i: continue
        cells = {}
        for ev, tk, bo, tr in runs:
            if not (ev >> j & 1) or (bo >> j & 1): continue
            k = bool(tk >> j & 1)
            cells.setdefault(k, [0, 0])[0 if (tr >> sbit & 1) else 1] += 1
        if len(cells) != 2: continue
        # monotone: one side always has it, the other never does
        a, b = cells[True], cells[False]
        if (a[1] == 0 and b[0] == 0) or (b[1] == 0 and a[0] == 0):
            return names[j]
    return None

or_only, two_sided, detail = [], [], {}
for e in sorted(DISQ):
    i = eidx.get(e)
    if i is None: continue
    on, off = sides(i)
    both = on & off
    if not both:
        detail[e] = ("no-offending-shape", None); continue
    offending = [b for b in range(len(sidx)) if both >> b & 1]
    expl, unexpl = [], []
    for sb in offending[:40]:
        x = monotone_explainer(sb, i)
        (expl if x else unexpl).append(sb)
    if unexpl:
        two_sided.append(e); detail[e] = ("TWO-SIDED", len(unexpl))
    else:
        or_only.append(e); detail[e] = ("OR-SHARED-ONLY", len(expl))
print(f"\n=== WHY THE {len(DISQ)} ARE DISQUALIFIED ===")
print(f"  OR-SHARED ONLY (every offending shape has a monotone explainer): {len(or_only)}")
print(f"  GENUINELY TWO-SIDED                                            : {len(two_sided)}")
print(f"  no offending shape found in this scan                          : {len(DISQ)-len(or_only)-len(two_sided)}")
print("\nOR-SHARED-ONLY decisions (candidates the owner would rule on):")
for e in or_only[:18]: print(f"    {e[:100]}")
json.dump({"or_only": or_only, "two_sided": two_sided,
           "detail": {k: list(v) for k, v in detail.items()}},
          open("_disq_why.json", "w"), indent=1)
print("\nwrote _disq_why.json")
