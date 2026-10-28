#!/usr/bin/env python3
"""C29 step 5 — is `row_target_persisted == False` the ENABLING GATE the cube
does not carry, and has any builder ever written it?"""
import json, os, pickle, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
S = pickle.load(open(os.path.join(HERE, "_c29_scan.pkl"), "rb"))
N, T, F, META, FILES = S["n"], S["T"], S["F"], S["meta"], S["files"]
ALL = (1 << N) - 1
sys.path.insert(0, HERE)
from _c29_dispatch import ON, OFF, P, V, DV, PH                  # noqa: E402
tb = lambda e: T.get(e, 0); fb = lambda e: F.get(e, 0)
eb = lambda e: tb(e) | fb(e); pc = lambda x: x.bit_count()
mask = lambda lit: tb(lit[0]) if lit[1] else fb(lit[0])
PERS = f"({V}_row_target_persisted == True)"
PPNF = f"({DV}_person_profile_not_found == True)"
ACT = f"(SYM_LEN_{V}_row_actors_row_rows > 1)"
PH1 = f"({PH} > 1)"
ROWS = f"(SYM_LEN_{V}_rows > 1)"
TGT = f"({V}_row_target_not_found == True)"
TAP = f"({V}_row_target_author_profile_not_found == True)"


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


print(f"corpus {N}")
print("\n=== the enabling gate, per dispatch arm")
print(f"{'k':>4} {'P==k T':>8} {'& pers=F':>9} {'& pers=T':>9} {'& pers unevaluated':>19} {'& photos_aa evaluated':>22}")
for k in list(range(8)) + ["oor"]:
    if k == "oor":
        m = ALL
        for j in range(8):
            m &= fb(f"({P} == {j})")
    else:
        m = tb(f"({P} == {k})")
    print(f"{str(k):>4} {pc(m):>8} {pc(m & fb(PERS)):>9} {pc(m & tb(PERS)):>9} "
          f"{pc(m & ~eb(PERS)):>19} {pc(m & eb(PH1)):>22}")

print("\n=== ON cube with the enabling gate ADDED, one literal at a time")
cube = ON
names = ["P==2", "!P3", "!P4", "!P5", "!P6", "!P7", "pnf=F", "tgt_nf=F",
         "actors>1", "tauth_nf=F", "ppnf=T", "photos<=1"]
acc = [(PERS, False)]
print(f"   start: target_persisted=F                         A={pc(M(acc)):7d}")
for i, lit in enumerate(cube):
    acc.append(lit)
    print(f"   + {names[i]:<12} {('T' if lit[1] else 'F')}  A={pc(M(acc)):7d}")

print("\n=== OFF cube with the enabling gate ADDED, one literal at a time")
names2 = ["!P0", "!P1", "!P2", "P==3", "!P4", "!P5", "!P6", "!P7", "pnf=F",
          "rows>1", "tgt_nf=F", "actors>1", "tauth_nf=F", "ppnf=F", "photos>1"]
acc = [(PERS, False)]
print(f"   start: target_persisted=F                         A={pc(M(acc)):7d}")
for i, lit in enumerate(OFF):
    acc.append(lit)
    print(f"   + {names2[i]:<12} {('T' if lit[1] else 'F')}  A={pc(M(acc)):7d}")

print("\n=== which runs ever SEEDED a `_persisted` key, and for which base?")
seedk = collections.Counter(); tagc = collections.Counter()
m = fb(PERS)
idx = bits(m)
print(f"runs recording {PERS[:70]} FALSE: {len(idx)}")
for i in idx[:4000]:
    try:
        d = json.load(open(FILES[i]))
    except Exception:
        continue
    tagc[META[i][0]] += 1
    for k in (d.get("concolic_seeds") or {}):
        if k.endswith("_persisted"):
            seedk[k] += 1
print("  top tags:", tagc.most_common(10))
print("  seeded *_persisted keys (first 4000 of them):")
for k, v in seedk.most_common(12):
    print(f"     {v:6d}  {k}")

print("\n=== and across the WHOLE corpus, how many runs seed ANY *_persisted key?")
import random
random.seed(11)
sam = random.sample(range(N), 3000)
any_seed = collections.Counter()
for i in sam:
    try:
        d = json.load(open(FILES[i]))
    except Exception:
        continue
    ks = [k for k in (d.get("concolic_seeds") or {}) if k.endswith("_persisted")]
    any_seed["seeded" if ks else "not seeded"] += 1
    for k in ks:
        any_seed["key:" + k] += 1
for k, v in any_seed.most_common(12):
    print(f"   {v:6d}  {k}")
print("\nC29-GATE-DONE")
