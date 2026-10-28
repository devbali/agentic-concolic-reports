#!/usr/bin/env python3
"""C29 step 4 — WHY the two cubes' conflicts exist: conditional evaluation
rates for the members the MUS names, and the wider MUS for the OFF cube.

Read-only, no corpus re-read.
"""
import itertools, json, os, pickle, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
S = pickle.load(open(os.path.join(HERE, "_c29_scan.pkl"), "rb"))
N, T, F, META, FILES = S["n"], S["T"], S["F"], S["meta"], S["files"]
ALL = (1 << N) - 1
sys.path.insert(0, HERE)
from _c29_dispatch import ON, OFF, P, V, DV, PH                  # noqa: E402

tb = lambda e: T.get(e, 0)
fb = lambda e: F.get(e, 0)
eb = lambda e: tb(e) | fb(e)
mask = lambda lit: tb(lit[0]) if lit[1] else fb(lit[0])
pc = lambda x: x.bit_count()
PPNF = f"({DV}_person_profile_not_found == True)"
PNF = f"({DV}_person_not_found == True)"
PH1 = f"({PH} > 1)"
PH0 = f"({PH} == 0)"
PHNZ = f"({PH} != 0)"
PH2 = "(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_photos_2a9cc6c3_rows > 1)"
TGT = f"({V}_row_target_not_found == True)"
ACT = f"(SYM_LEN_{V}_row_actors_row_rows > 1)"
TAP = f"({V}_row_target_author_profile_not_found == True)"
ROWS = f"(SYM_LEN_{V}_rows > 1)"
PERS = f"({V}_row_target_persisted == True)"


def A(sub):
    m = ALL
    for lit in sub:
        m &= mask(lit)
        if not m:
            return 0
    return pc(m)


def M(sub):
    m = ALL
    for lit in sub:
        m &= mask(lit)
    return m


def bits(m):
    out = []
    b = m.to_bytes((N + 7) // 8, "little")
    for bi, byte in enumerate(b):
        if byte:
            for k in range(8):
                if byte & (1 << k):
                    out.append(bi * 8 + k)
    return out


def rate(label, cond, targets):
    m = M(cond)
    print(f"\n-- {label}: {pc(m)} runs")
    for t in targets:
        print(f"     eval {pc(m & eb(t)):7d}   T {pc(m & tb(t)):7d}   "
              f"F {pc(m & fb(t)):7d}   {t[:96]}")


def mus(cube, width, cap=None):
    found = []
    for r in range(1, width + 1):
        for sub in itertools.combinations(range(len(cube)), r):
            if any(set(f) <= set(sub) for f in found):
                continue
            if A([cube[i] for i in sub]) == 0:
                found.append(sub)
        print(f"   width {r}: {len(found)} MUS so far", flush=True)
    return found


print(f"corpus {N}")
print("\n" + "=" * 78)
print("=== IS THE PRINCIPAL'S PROFILE DECISION WHAT GATES THE PER-ROW READS?")
print("=" * 78)
for lab, cond in (("person_profile_not_found == TRUE (principal profile MISSING)",
                   [(PPNF, True)]),
                  ("person_profile_not_found == FALSE (principal profile PRESENT)",
                   [(PPNF, False)]),
                  ("person_profile_not_found NEVER EVALUATED", None)):
    if cond is None:
        m = ALL & ~eb(PPNF)
        print(f"\n-- {lab}: {pc(m)} runs")
        for t in (PH1, PH2, ACT, TGT, TAP):
            print(f"     eval {pc(m & eb(t)):7d}   T {pc(m & tb(t)):7d}   "
                  f"F {pc(m & fb(t)):7d}   {t[:96]}")
        continue
    rate(lab, cond, [PH1, PH2, ACT, TGT, TAP, f"({P} == 2)", f"({P} == 3)"])

print("\n" + "=" * 78)
print("=== THE aa895602 STATEMENT IS THE UNPERSISTED-TARGET PHOTOS READ")
print("=== (Rails merges none! -> `AND (1=0)` into a new_record owner's scope)")
print("=" * 78)
for lab, cond in (("target_persisted == True", [(PERS, True)]),
                  ("target_persisted == False", [(PERS, False)])):
    rate(lab, cond, [PH1, PH2, PHNZ])

print("\n" + "=" * 78)
print("=== THE ON MUS {P==2 T, actors>1 T, ppnf T, photos_aa895602>1 F}")
print("=" * 78)
base = [(f"({P} == 2)", True), (ACT, True), (PPNF, True)]
m = M(base)
print(f"runs matching (P==2, actors>1, ppnf=T): {pc(m)}")
print(f"   of them evaluate photos_aa895602: {pc(m & eb(PH1))}  "
      f"(T {pc(m & tb(PH1))}, F {pc(m & fb(PH1))})")
for i in bits(m & eb(PH1)):
    print(f"   THE RUN: {os.path.basename(FILES[i])}  tag={META[i][0]} scen={META[i][1]}")
for drop, keep in (("ppnf", [(f"({P} == 2)", True), (ACT, True)]),
                   ("actors>1", [(f"({P} == 2)", True), (PPNF, True)]),
                   ("P==2", [(ACT, True), (PPNF, True)])):
    mm = M(keep)
    print(f"\n   drop {drop}: {pc(mm)} runs; evaluate photos_aa895602 in "
          f"{pc(mm & eb(PH1))} (T {pc(mm & tb(PH1))}, F {pc(mm & fb(PH1))})")

print("\n" + "=" * 78)
print("=== THE OFF CUBE — MUS at width up to 6")
print("=" * 78)
ms = mus(OFF, 6)
short = lambda e: (e.replace("SYM_RESULT_ActiveRecord__", "")
                    .replace("SYM_LEN_SYM_RESULT_ActiveRecord__", "LEN ")
                    .replace("Relation_to_ary_notifications_", "ntf/")
                    .replace("Associations__CollectionProxy_records_", "cp/")
                    .replace("FinderMethods_", "fm/"))
for sub in ms:
    print(f"\n  MUS {tuple(sub)}   A = 0")
    for i in sub:
        e, o = OFF[i]
        print(f"      L{i:<2} want={'T' if o else 'F'}  {short(e)}")
    for i in sub:
        rest = [OFF[j] for j in sub if j != i]
        mm = M(rest)
        e, o = OFF[i]
        print(f"      -> drop L{i}: A(others)={pc(mm):6d}  evaluate it in "
              f"{pc(mm & eb(e)):6d}  realise it in {pc(mm & mask((e, o))):6d}")
json.dump({"off_mus6": [list(x) for x in ms]},
          open(os.path.join(HERE, "_c29_why.json"), "w"), indent=1)
print("\nC29-WHY-DONE")
