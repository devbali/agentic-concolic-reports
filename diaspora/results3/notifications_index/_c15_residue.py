#!/usr/bin/env python3
"""C15 — what the 84 remaining gap-sets are, after §16e.

For each remaining witness leaf, from the dump index: A = runs agreeing with
EVERY literal of the leaf (per-literal, the falsifier's reading), and, per
member, whether any run agreeing with the leaf's OTHER literals evaluates it.
A leaf with A = 0 has never been walked whole; the question is then whether
that is a driving gap or a reachability one.
"""
import json, os, pickle, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
idx = pickle.load(open(os.environ.get("C15_INDEX", HERE + "/_c14_index_R2.pkl"), "rb"))
exprs = idx["exprs"]; eidx = {e: i for i, e in enumerate(exprs)}; dumps = idx["dumps"]
N = len(dumps); NB = (N + 7) // 8
TB = [bytearray(NB) for _ in exprs]; FB = [bytearray(NB) for _ in exprs]; EB = [bytearray(NB) for _ in exprs]
for i, (_p, _v, em, tm, _ns, _cm) in enumerate(dumps):
    by, bit = i >> 3, 1 << (i & 7)
    m = em
    while m:
        bb = m & -m; j = bb.bit_length() - 1; m ^= bb
        EB[j][by] |= bit
        (TB if (tm >> j) & 1 else FB)[j][by] |= bit
ti = lambda b: int.from_bytes(bytes(b), "little")
TB = [ti(x) for x in TB]; FB = [ti(x) for x in FB]; EB = [ti(x) for x in EB]
ALL = (1 << N) - 1


def load(p):
    out = []
    for i, l in enumerate(open(p)):
        if i == 0:
            continue
        r = json.loads(l); v = r.get("v") or {}
        for c in (v.get("combos") or ()):
            out.append((r["k"], [(e, bool(o)) for e, o in c]))
    return out


for tag, path in (("C14 (§16b)", HERE + "/_cov_c14_C14R2.ckpt.jsonl"),
                  ("C15 (§16e)", HERE + "/_cov_c15_C15R2.ckpt.jsonl")):
    lv = load(path)
    a0 = walked = notin = 0
    widths = {}
    for _k, cube in lv:
        m = ALL; unk = 0
        for e, o in cube:
            j = eidx.get(e)
            if j is None:
                unk += 1; continue
            m &= TB[j] if o else FB[j]
        widths[len(cube)] = widths.get(len(cube), 0) + 1
        if unk:
            notin += 1
        elif m:
            walked += 1
        else:
            a0 += 1
    print(f"{tag}: {len(lv)} witness leaves   "
          f"NO RUN matches the whole leaf (A=0): {a0}   some run does: {walked}   "
          f"expr not in index: {notin}")
    print("   leaf widths: " + ", ".join(f"{k}:{v}" for k, v in sorted(widths.items())[:14]))
