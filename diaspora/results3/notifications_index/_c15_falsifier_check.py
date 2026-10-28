#!/usr/bin/env python3
"""C15 — cross-check the ENGINE's §16e inference against the §19.2 falsifier.

The engine (`coverage.py`, DISCIPLINE §16e) infers a conjunction foreclosure
from its own profile table. `_c14_falsifier.py` computed the same predicate
independently, from inverted bitsets over the dump index, per leaf group. If
the two agree the inference is the falsifier, implemented — and it must agree
TO THE UNIT on the partition: every (prefix, member) the engine forecloses
must be B = 0 with A > 0 in the index, and every prefix the engine reports as
`unmatched_gate_conjunctions` must be A = 0.

  usage: C15_SUMMARY=<pass json> [C15_INDEX=_c14_index_R2.pkl] python3 _c15_falsifier_check.py

Mask semantics are the falsifier's, which are §16b's: `em` = evaluated at
least once, `tm` = taken TRUE at least once, so a literal is matched by
"took it that way at least once".
"""
import json, os, pickle, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
SUM = os.environ.get("C15_SUMMARY", os.path.join(HERE, "_cov_C15_C15R2.json"))
INDEX = os.environ.get("C15_INDEX", os.path.join(HERE, "_c14_index_R2.pkl"))
OUT = os.environ.get("C15_CHECK_OUT", os.path.join(HERE, "_c15_falsifier_check.json"))

t0 = time.time()
idx = pickle.load(open(INDEX, "rb"))
exprs = idx["exprs"]; eidx = {e: i for i, e in enumerate(exprs)}
dumps = idx["dumps"]
N = len(dumps)
NB = (N + 7) // 8
TB = [bytearray(NB) for _ in exprs]; FB = [bytearray(NB) for _ in exprs]
EB = [bytearray(NB) for _ in exprs]
for i, (_p, _v, em, tm, _ns, _cm) in enumerate(dumps):
    by, bit = i >> 3, 1 << (i & 7)
    m = em
    while m:
        bb = m & -m; j = bb.bit_length() - 1; m ^= bb
        EB[j][by] |= bit
        (TB if (tm >> j) & 1 else FB)[j][by] |= bit
to_int = lambda ba: int.from_bytes(bytes(ba), "little")
TB = [to_int(x) for x in TB]; FB = [to_int(x) for x in FB]; EB = [to_int(x) for x in EB]
ALL = (1 << N) - 1
print(f"index {os.path.basename(INDEX)}: {N} dumps, {len(exprs)} exprs "
      f"({time.time()-t0:.0f}s)", flush=True)

s = json.load(open(SUM))
fore = s.get("conjunction_foreclosure_list") or []
unmatched = s.get("unmatched_gate_conjunction_prefixes") or []
print(f"summary {os.path.basename(SUM)}: conj={s.get('conjunction_foreclosures')} "
      f"groups={s.get('conjunction_foreclosure_groups')} "
      f"unmatched={s.get('unmatched_gate_conjunctions')} "
      f"(lists carry {len(fore)} / {len(unmatched)}, capped at 200)", flush=True)


def amask(prefix):
    m = ALL
    unknown = 0
    for g, side in prefix:
        j = eidx.get(g)
        if j is None:
            unknown += 1
            continue
        m &= TB[j] if side == "taken" else FB[j]
    return m, unknown


rows = {"foreclosures": [], "unmatched": []}
agree = dis = unknown_expr = 0
for rec in fore:
    pfx = [tuple(x) for x in rec["prefix"]]
    d = rec["member"]
    m, unk = amask(pfx)
    A = m.bit_count()
    j = eidx.get(d)
    B = (m & EB[j]).bit_count() if j is not None else None
    ok = (A > 0 and B == 0)
    if unk or j is None:
        unknown_expr += 1
    elif ok:
        agree += 1
    else:
        dis += 1
    rows["foreclosures"].append({"member": d, "A": A, "B": B,
                                 "unknown_exprs": unk + (0 if j is not None else 1),
                                 "agrees": bool(ok)})
u_agree = u_dis = u_unknown = 0
for pfx in unmatched:
    pfx = [tuple(x) for x in pfx]
    m, unk = amask(pfx)
    A = m.bit_count()
    if unk:
        u_unknown += 1
    elif A == 0:
        u_agree += 1
    else:
        u_dis += 1
    rows["unmatched"].append({"A": A, "unknown_exprs": unk, "agrees": bool(A == 0 and not unk)})

print()
print("=== ENGINE §16e  vs  §19.2 FALSIFIER (index bitsets) ===")
print(f"  conjunction foreclosures checked : {len(fore)}")
print(f"     A>0 and B=0  (AGREE)          : {agree}")
print(f"     DISAGREE                      : {dis}")
print(f"     expr not in the index         : {unknown_expr}")
print(f"  unmatched (A=0) prefixes checked : {len(unmatched)}")
print(f"     A=0 in the index (AGREE)      : {u_agree}")
print(f"     DISAGREE                      : {u_dis}")
print(f"     expr not in the index         : {u_unknown}")
json.dump({"index": os.path.basename(INDEX), "index_dumps": N,
           "summary": os.path.basename(SUM),
           "agree": agree, "disagree": dis, "unknown": unknown_expr,
           "unmatched_agree": u_agree, "unmatched_disagree": u_dis,
           "unmatched_unknown": u_unknown, "rows": rows}, open(OUT, "w"))
print(f"\nC15-FALSIFIER-CHECK-DONE {OUT}  "
      f"VERDICT={'AGREE' if (dis == 0 and u_dis == 0) else 'DISAGREE'}")
