"""P39 — DECLARE THE 399 FORECLOSED GAPS AS (C, d) FORECLOSURE ASSUMPTIONS.

§106.1 classified 525 construction gaps as 124 constructible / 2 selection
misses / 399 FORECLOSED. The 399 have never been DECLARED as assumptions and
never witness-tested: their impossibility is an argument in a report, not a
licence the engine acts on. This script turns each into the `(C, d)` export
`foreclosure_gate.py` consumes:

    C = the cube's emptiness pins   (the `pins` the constructor derived,
                                     each a cube literal `(SYM_LEN_X != 0)`)
    d = the blocking gate           (the first gate of the gap that NO run
                                     realising C ever EVALUATES)

plus the mandatory positive control: the demand-universe member evaluated by
the most runs realising the same C (`_p23_enum._control_for`'s rule, recomputed
here from the same index the constructor used).

Read-only over `_p31_index_P35C.pkl` (48 943 profiles), `_p15_manifest_P35C.json`
and `_p31_gaps_P35C.json`. Writes ONE json; drives nothing.
"""
import json, os, pickle, re, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
IDXP = os.environ.get("P39_INDEX", os.path.join(HERE, "_p31_index_P35C.pkl"))
MANP = os.environ.get("P39_MANIFEST", os.path.join(HERE, "_p15_manifest_P35C.json"))
GAPP = os.environ.get("P39_GAPS", os.path.join(HERE, "_p31_gaps_P35C.json"))
OUT = os.environ.get("P39_OUT", os.path.join(HERE, "_p39_forecl_classes.json"))
DIAG = os.environ.get("P39_DIAG", os.path.join(HERE, "_p39_forecl_diag.json"))

idx = pickle.load(open(IDXP, "rb"))
exprs = idx["exprs"]; eidx = {e: i for i, e in enumerate(exprs)}
LENS = idx["lens"]; LIDX = {L: i for i, L in enumerate(LENS)}
dumps = idx["dumps"]
N = len(dumps)
print(f"index: {N} profiles, {len(exprs)} demand-universe exprs, {len(LENS)} lengths",
      flush=True)

# ---- transpose the per-dump masks into per-literal profile bitsets, exactly
#      the `_takes16`/`_evals16` shape the emitter's control rule uses.
evals = [0] * len(exprs)          # profiles that EVALUATED expr j
lz = [0] * len(LENS)              # profiles where length j is ZERO
lnz = [0] * len(LENS)             # ... NON-ZERO
universe = (1 << N) - 1
for di, (path, var, em, tm, ns, cm, dl0, dl1, dfm) in enumerate(dumps):
    bit = 1 << di
    m = em
    while m:
        j = (m & -m).bit_length() - 1
        evals[j] |= bit
        m &= m - 1
    m = dl0
    while m:
        j = (m & -m).bit_length() - 1
        lz[j] |= bit
        m &= m - 1
    m = dl1
    while m:
        j = (m & -m).bit_length() - 1
        lnz[j] |= bit
        m &= m - 1
print("transposed", flush=True)

_APIORD = re.compile(r"as_api_response_(\d+)_row_guid")

man = json.load(open(MANP))
gaps = {g["id"]: g for g in json.load(open(GAPP))}
print(f"manifest {len(man)} gaps; admissibility: "
      f"{dict(Counter(m['admissibility'] for m in man))}", flush=True)

_ctl_memo = {}


def control_for(amask):
    """The emitter's rule (`_p23_enum._control_for`): the demand-universe
    member the MOST profiles realising C are seen to evaluate. It shares the
    hard part (realising C) and differs only in the member, so a red control
    makes the class NOT-TESTABLE rather than a free PASS (X11)."""
    key = amask
    if key in _ctl_memo:
        return _ctl_memo[key]
    best, best_n = None, 0
    for j, ev in enumerate(evals):
        n = (amask & ev).bit_count()
        if n > best_n:
            best, best_n = exprs[j], n
    got = (best, best_n)
    _ctl_memo[key] = got
    return got


classes, diag = [], []
stat = Counter()
for m in man:
    gid = m["gap"]
    g = gaps[gid]
    adm = m["admissibility"]
    if adm != "pins only (no base walks every gate)":
        stat["not-blocked (constructs or gates walk)"] += 1
        diag.append({"gap": gid, "class": "CONSTRUCTIBLE", "admissibility": adm})
        continue
    # ---- C: the cube's emptiness pins, as cube literals.
    C, unindexed = [], []
    amask = universe
    for L, w in m["pins"]:
        j = LIDX.get(L)
        if j is None:
            unindexed.append(L)          # unminted anywhere: cannot condition on it
            continue
        C.append([f"({L} != 0)", bool(w)])
        amask &= (lnz[j] if w else lz[j])
    A = amask.bit_count()
    if not C:
        stat["NO-PINS (nothing to condition on)"] += 1
        diag.append({"gap": gid, "class": "NO-PINS", "unindexed": unindexed})
        continue
    if A == 0:
        stat["A(C)=0 (no profile realises the pins)"] += 1
        diag.append({"gap": gid, "class": "A0", "pins": len(C)})
        continue
    # ---- d: the first gate of the gap that NO run realising C ever EVALUATES.
    blocking, evaluated_gates = None, []
    for e, o in (g.get("gates") or {}).items():
        j = eidx.get(e)
        if j is None:
            continue
        b = (amask & evals[j]).bit_count()
        if b == 0:
            if blocking is None:
                blocking = e
        else:
            evaluated_gates.append([e, b])
    if blocking is None:
        stat["NOT FORECLOSED (every gate is evaluated under C)"] += 1
        diag.append({"gap": gid, "class": "SELECTION-MISS-CANDIDATE",
                     "A": A, "gates_evaluated": evaluated_gates})
        continue
    ctl, ctl_b = control_for(amask)
    ordm = _APIORD.search(blocking)
    stat["FORECLOSED"] += 1
    stat[f"  ordinal {ordm.group(1) if ordm else '-'}"] += 1
    classes.append({
        "conditioning": C,
        "member": blocking,
        "A": A,
        "control_member": ctl,
        "control_B": ctl_b,
        "A_popcount": A,
        "gap": gid,
        "set": m["set"],
        "width": m["width"],
    })
    diag.append({"gap": gid, "class": "FORECLOSED", "A": A,
                 "member": blocking, "pins": len(C),
                 "unindexed_pins": unindexed,
                 "control_B": ctl_b})

# ---- dedupe: several gaps can share the same (C, d). The gate tests a CLASS,
#      so collapse them and record the multiplicity rather than probing twice.
seen, uniq = {}, []
for c in classes:
    k = (tuple((e, o) for e, o in c["conditioning"]), c["member"])
    if k in seen:
        seen[k]["gaps"].append(c["gap"])
        continue
    c = dict(c)
    c["gaps"] = [c.pop("gap")]
    seen[k] = c
    uniq.append(c)

print("\n=== P39 DECLARATION ===", flush=True)
for k, v in stat.most_common():
    print(f"  {k:<46} {v}", flush=True)
print(f"  distinct (C,d) classes over the foreclosed gaps: {len(uniq)} "
      f"(from {len(classes)} gaps)", flush=True)
nc = Counter(len(c["conditioning"]) for c in uniq)
print(f"  |C| histogram: {dict(sorted(nc.items()))}", flush=True)
print(f"  with a positive control: {sum(1 for c in uniq if c['control_member'])}"
      f"  without: {sum(1 for c in uniq if not c['control_member'])}", flush=True)
json.dump(uniq, open(OUT, "w"), indent=1)
json.dump(diag, open(DIAG, "w"), indent=1)
print(f"  wrote {OUT}", flush=True)
