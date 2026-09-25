#!/usr/bin/env python3
"""OR-SHARING CENSUS — what a shared / two-sided footprint shape IS.

    DUMP_LIST=<snapshot> python3 or_sharing_census.py <batch_dir> <confinement_census.json> [--json-out f]

Under STRICT confinement a shape present with a decision on its other side —
via another decision — DISQUALIFIES the decision, and on posts_show that is
where the width lives (GC0911: overlapping 0, disqualified 2 416). The
coordinator's suspicion (2026-09-11): most of it is OR-sharing — the same
presenter query fed by several collections, present under A alone, under B
alone, under both — which is not interaction; only a shape needing BOTH on
(AND) or a non-monotone cell is.

For every co-evaluated pair of DECIDED decisions (both single-sided in some
profile) and every shape in fp(A) ∪ fp(B), the 2x2 over the co-evaluated
profiles: cell (side_A, side_B) -> present in some run / absent in all runs
(union / intersection over the runs of each profile). A cell with no profile
is UNOBSERVED. Orientation: the four (which side is "on") orientations are
tried; a shape is MONOTONE if some orientation makes reachability
non-decreasing in (A on, B on); its pattern (c00 c01 c10 c11) then names it:
  0111 OR        — present under A alone, B alone, both; never under neither
  0001 AND       — present only with both on: INTERACTION
  0011 / 0101    — A-only / B-only: not shared in this pair's table
  1111 ALWAYS    — reachable in every cell: neither decision's
  no monotone orientation -> NON-MONOTONE: INTERACTION
  (a '?' cell is UNOBSERVED; a pattern with '?' is classified only if every
   completion agrees, else UNDETERMINED, with the missing cell named)
Per pair: ALL-OR (every shape OR / A-only / B-only / ALWAYS), ANY-AND,
ANY-NONMONOTONE, UNDETERMINED. Counts by gate family. Read-only.
"""
import json
import os
import re
import sys
import time
from collections import Counter, defaultdict

BATCH = os.path.abspath(sys.argv[1])
CENSUS = sys.argv[2]
args = sys.argv[3:]
sys.path.insert(0, BATCH)
sys.path.insert(0, "/home/dev/project/src")
import coverage_report as CR                                     # noqa: E402
from concolic_engine.assumptions import call_shape, shape_str      # noqa: E402
from concolic_engine.coverage import profile_key                   # noqa: E402

t0 = time.time()
C = json.load(open(CENSUS))
FP = {e: set(v) for e, v in C["footprints"].items()}
decided = sorted(FP)
print(f"census {os.path.basename(CENSUS)}: {len(decided)} decided decisions, "
      f"pairs {C['pairs']}", flush=True)

files = [l.strip() for l in open(os.environ["DUMP_LIST"]) if l.strip()]
files = [f if os.path.isabs(f) else os.path.join(BATCH, f) for f in files]
print(f"scanning {len(files)} dumps (read-only)", flush=True)
eidx = {e: i for i, e in enumerate(decided)}
shape_id = {}
prof = {}              # key -> [evT mask, evF mask, evB mask, union, inter, n]
for n, p in enumerate(files):
    try:
        raw = json.load(open(p))
        CR.canonicalize_ordinals(raw)
        raw = CR.fix_len_names(raw)
    except Exception:
        continue
    outcomes = {}
    tr = 0
    for ev in raw.get("events") or ():
        t = ev.get("type")
        if t == "path_condition":
            outcomes.setdefault(str(ev.get("expr", "")), set()).add(bool(ev.get("taken")))
        elif t == "symbolic_call" and ev.get("result_name"):
            sh = call_shape(ev.get("target"), ev.get("note"), ev.get("args"))
            j = shape_id.get(sh)
            if j is None:
                j = shape_id[sh] = len(shape_id)
            tr |= 1 << j
    del raw
    if not outcomes:
        continue
    k = profile_key(outcomes)
    sl = prof.get(k)
    if sl is None:
        evT = evF = evB = 0
        for e, os_ in outcomes.items():
            i = eidx.get(e)
            if i is None:
                continue
            if len(os_) > 1:
                evB |= 1 << i
            elif True in os_:
                evT |= 1 << i
            else:
                evF |= 1 << i
        prof[k] = [evT, evF, evB, tr, tr, 1]
    else:
        sl[3] |= tr
        sl[4] &= tr
        sl[5] += 1
    if n % 5000 == 0:
        print(f"  [{n}/{len(files)}] profiles={len(prof)} shapes={len(shape_id)} {time.time()-t0:.0f}s", flush=True)
profiles = list(prof.values())
names = [None] * len(shape_id)
for sh, j in shape_id.items():
    names[j] = shape_str(sh)
sid = {s: j for j, s in enumerate(names)}
missing_fp = sum(1 for e in decided for s in FP[e] if s not in sid)
print(f"loaded {len(profiles)} profiles, {len(shape_id)} shapes; footprint shapes not in this "
      f"snapshot's shape universe: {missing_fp} (must be 0 for the names to match) {time.time()-t0:.0f}s", flush=True)

# ---- one pass over profiles: per co-evaluated pair, per cell (side_A, side_B),
# the union and intersection of the traces of the profiles in that cell -----
cells = {}             # (ia, ib) -> {(sa, sb): [union, inter]}
coev = defaultdict(int)
for evT, evF, evB, u, i_, _n in profiles:
    m = evT | evF
    x = m
    bits = []
    while x:
        b = x & -x
        bits.append(b.bit_length() - 1)
        x ^= b
    for a in range(len(bits)):
        ia = bits[a]
        sa = bool(evT >> ia & 1)
        for b in range(a + 1, len(bits)):
            ib = bits[b]
            coev[(ia, ib)] += 1
            d = cells.get((ia, ib))
            if d is None:
                d = cells[(ia, ib)] = {}
            key = (sa, bool(evT >> ib & 1))
            c = d.get(key)
            if c is None:
                d[key] = [u, i_]
            else:
                c[0] |= u
                c[1] &= i_
print(f"co-evaluated decided pairs: {len(coev)} ({time.time()-t0:.0f}s)", flush=True)

# ---- the 2x2 per (pair, shape) ---------------------------------------------
FAM = [(re.compile(r"SYM_LEN_.*_rows != 0"), "len-gate"),
       (re.compile(r"_not_found == True"), "not_found-gate"),
       (re.compile(r"_public == True"), "public-gate"),
       (re.compile(r"text_has_mention|text_empty"), "text"),
       (re.compile(r"Length\(SYM_PARAM_id\)"), "dispatch"),
       (re.compile(r"nsfw|guid|persisted|row_"), "row-attr")]


def fam(e):
    for rx, f in FAM:
        if rx.search(e):
            return f
    return "other"


def classify(cells):
    """cells: dict (sa, sb) -> 1 present-in-some / 0 absent-in-all; a missing
    key is an UNOBSERVED cell. Try the four orientations (which side is 'on');
    for each, enumerate the completions of the unobserved cells. An
    orientation is SOUND if every completion is monotone, POSSIBLE if some
    is. Returns one of OR / AND / A-only / B-only / ALWAYS / NEVER /
    OR-family (sound, several benign patterns) / UNDETERMINED(...) (only
    possible orientations) / NON-MONOTONE (no orientation possible)."""
    import itertools
    NAMES = {(0, 1, 1, 1): "OR", (0, 0, 0, 1): "AND", (0, 0, 1, 1): "A-only",
             (0, 1, 0, 1): "B-only", (1, 1, 1, 1): "ALWAYS", (0, 0, 0, 0): "NEVER"}
    sound, possible = [], []
    for fa in (False, True):
        for fb in (False, True):
            def cell(a_on, b_on):
                return cells.get((fa if a_on else not fa, fb if b_on else not fb))
            c = {"00": cell(0, 0), "01": cell(0, 1), "10": cell(1, 0), "11": cell(1, 1)}
            unknown = [k for k, v in c.items() if v is None]
            mono, non = set(), False
            for fill in itertools.product((0, 1), repeat=len(unknown)):
                v = dict(c); v.update(zip(unknown, fill))
                if v["00"] <= v["01"] and v["00"] <= v["10"] and v["01"] <= v["11"] and v["10"] <= v["11"]:
                    mono.add(NAMES.get((v["00"], v["01"], v["10"], v["11"]), "OTHER"))
                else:
                    non = True
            if mono and not non:
                sound.append(mono)
            elif mono:
                possible.append(mono)
    if sound:
        kinds = set().union(*sound) - {"NEVER"}
        if not kinds:
            return "NEVER"
        if len(kinds) == 1:
            return next(iter(kinds))
        return "OR-family" if kinds <= {"OR", "A-only", "B-only", "ALWAYS"} else "UNDETERMINED(AND?)"
    if possible:
        kinds = set().union(*possible) - {"NEVER"}
        return "UNDETERMINED(AND?)" if "AND" in kinds else "UNDETERMINED"
    return "NON-MONOTONE"


pair_rows = []
shape_class = Counter()
for (ia, ib), ncoev in coev.items():
    A, B = decided[ia], decided[ib]
    shapes = sorted((FP[A] | FP[B]) & set(sid))
    shared = (FP[A] & FP[B]) & set(sid)
    classes = {}
    pc = cells[(ia, ib)]
    for s in shapes:
        j = sid[s]
        # cell -> 1 if the shape is present in SOME run of the cell, else 0
        cl = classify({key: (1 if (c[0] >> j & 1) else 0) for key, c in pc.items()})
        classes[s] = cl
        shape_class[cl] += 1
    kinds = set(classes.values())
    if not shapes:
        verdict = "NO-SHAPES"
    elif "NON-MONOTONE" in kinds:
        verdict = "ANY-NONMONOTONE"
    elif "AND" in kinds:
        verdict = "ANY-AND"
    elif any(k.startswith("UNDETERMINED") for k in kinds):
        verdict = "UNDETERMINED"
    else:
        verdict = "ALL-OR"
    pair_rows.append({"a": A, "b": B, "coeval_profiles": ncoev, "verdict": verdict,
                      "fam": tuple(sorted((fam(A), fam(B)))),
                      "shared": len(shared), "shapes": len(shapes),
                      "classes": Counter(classes.values()),
                      "shape_classes": classes})

print(f"\n=== OR-SHARING CENSUS ({time.time()-t0:.0f}s) ===")
print(f"pairs examined (co-evaluated, both decided): {len(pair_rows)}")
vc = Counter(r["verdict"] for r in pair_rows)
for k, v in vc.most_common():
    print(f"  {k:<18}{v}")
print("\n(pair, shape) classifications:")
for k, v in shape_class.most_common():
    print(f"  {k:<20}{v}")
print("\nby family pair (verdict counts):")
byfam = defaultdict(Counter)
for r in pair_rows:
    byfam[r["fam"]][r["verdict"]] += 1
for f, c in sorted(byfam.items(), key=lambda kv: -sum(kv[1].values())):
    print(f"  {f[0]:<16}x {f[1]:<16} " + "  ".join(f"{k}={v}" for k, v in c.most_common()))
print("\nANY-AND / NON-MONOTONE pairs (first 12), with the offending shape:")
n = 0
for r in pair_rows:
    if r["verdict"] in ("ANY-AND", "ANY-NONMONOTONE"):
        bad = [s for s, c in r["shape_classes"].items() if c in ("AND", "NON-MONOTONE")]
        print(f"  {r['verdict']:<16} {r['a'][:60]} x {r['b'][:60]}\n      {r['shape_classes'][bad[0]]}: {bad[0][:100]}")
        n += 1
        if n >= 12:
            break
if "--json-out" in args:
    out = args[args.index("--json-out") + 1]
    json.dump({"pairs": [{**r, "classes": dict(r["classes"])} for r in pair_rows],
               "shape_class_counts": dict(shape_class), "verdict_counts": dict(vc)},
              open(out, "w"))
    print(f"wrote {out}")
print(f"DONE {time.time()-t0:.0f}s")
