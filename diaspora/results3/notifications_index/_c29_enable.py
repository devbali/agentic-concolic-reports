#!/usr/bin/env python3
"""C29 step 6 — the ENABLING GATES of the `photos_aa895602` read, found by a
matched-context differential rather than guessed.

Context: the runs that already match the cube's other literals.  Split them by
whether they EVALUATE `photos_aa895602` at all, and rank every other recorded
literal by how much it separates the two sides.  The top separators are what a
constructed seed has to write in addition to the cube.
"""
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
PH1 = f"({PH} > 1)"
EXPRS = sorted(set(T) | set(F))


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


def differential(label, ctx):
    m = M(ctx)
    pos = m & eb(PH1)          # evaluates the photos read
    neg = m & ~eb(PH1)
    np_, nn = pc(pos), pc(neg)
    print(f"\n{'='*78}\n=== {label}\n    context runs {pc(m)}  -> evaluate photos_aa895602 in {np_}, not in {nn}")
    if not np_ or not nn:
        print("    (one side empty - no differential)")
        for i in bits(pos)[:10]:
            print(f"      + {os.path.basename(FILES[i])} tag={META[i][0]}")
        return
    rows = []
    for e in EXPRS:
        for o, bs in ((True, tb(e)), (False, fb(e))):
            a = pc(pos & bs) / np_
            b = pc(neg & bs) / nn
            if abs(a - b) > 0.35 and max(a, b) > 0.5:
                rows.append((abs(a - b), a, b, e, o))
    rows.sort(reverse=True)
    print(f"    top separators (|rate difference| > 0.35):")
    for d, a, b, e, o in rows[:28]:
        print(f"      {'T' if o else 'F'} {a*100:5.1f}% vs {b*100:5.1f}%   {e[:104]}")


print(f"corpus {N}")
ON_ctx = [(PERS, False)] + ON[:-1]           # everything but the photos literal
OFF_ctx = [(PERS, False)] + OFF[:-1]
differential("ON cube minus the photos literal, WITH target_persisted=F", ON_ctx)
differential("OFF cube minus the photos literal, WITH target_persisted=F", OFF_ctx)
differential("target_persisted=F AND P==2 only", [(PERS, False), (f"({P} == 2)", True)])
differential("target_persisted=F AND P==3 only", [(PERS, False), (f"({P} == 3)", True)])
print("\nC29-ENABLE-DONE")
