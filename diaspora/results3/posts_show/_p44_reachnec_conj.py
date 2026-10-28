#!/usr/bin/env python3
"""P44 -- CONJUNCTION reach-necessity, one target expression at a time.

`_p44_reachnec.py` only tests whether a SINGLE (f=o) forecloses target `e`'s
evaluation. Class C misses (HANDOVER item 4) may be gated by a CONJUNCTION the
single-condition tool cannot see: neither f1=o1 nor f2=o2 alone forecloses e,
but f1=o1 AND f2=o2 together do.

This is a MEASUREMENT over the existing frozen index (no new driving, no src/
change, no assumption declared) -- it only widens what `_p44_missreason.py`'s
COND table can offer the constructor. A pair found here is a candidate PIN for
the seed constructor, not a completeness inference and NOT §16f (which
inferred a demand-tree PRUNING; this only helps a seed find a base realising a
genuine conjunction of preconditions for a member the constructor currently
scores as "no known condition").

Pure-python bigint bitmasks (no numpy in this environment): one bit per dump,
per (atom, dump) membership. Intersection = AND, "any" = != 0, count = bit_count().

usage: P44_INDEX=<pkl> P44_TARGET='<expr text>' python3 _p44_reachnec_conj.py
"""
import os, pickle, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
IDX = os.environ.get("P44_INDEX", os.path.join(HERE, "_p44_index_UNION2.pkl"))
MIN_RUNS = int(os.environ.get("P44_MIN_RUNS", "200"))
TARGET = os.environ.get("P44_TARGET", "(assoc_status_message_text_has_mention == True)")


def build_mask(bits):
    """bits: iterable of 0/1 -> one python int, bit i == bits[i]."""
    nbytes = (len(bits) + 7) // 8
    ba = bytearray(nbytes)
    for i, b in enumerate(bits):
        if b:
            ba[i >> 3] |= (1 << (i & 7))
    return int.from_bytes(bytes(ba), "little")


t0 = time.time()
idx = pickle.load(open(IDX, "rb"))
exprs = idx["exprs"]; lens = idx["lens"]; dumps = idx["dumps"]
N = len(dumps)
print(f"index {IDX}: {N} dumps, {len(exprs)} exprs, {len(lens)} lens, MIN_RUNS={MIN_RUNS}", flush=True)

if TARGET not in exprs:
    print(f"TARGET not in exprs: {TARGET!r}"); sys.exit(2)
e_idx = exprs.index(TARGET)

EM = [d[2] for d in dumps]
eval_e = build_mask([(EM[i] >> e_idx) & 1 for i in range(N)])
ne = eval_e.bit_count()
print(f"target evaluated in {ne} / {N} runs ({100.0*ne/N:.1f} %)", flush=True)

# build atom masks: (name, polarity) -> int bitmask over dumps
atoms = {}
TM = [d[3] for d in dumps]; DFM = [d[8] for d in dumps]
for j, ex in enumerate(exprs):
    if j == e_idx:
        continue
    atoms[(ex, True)] = build_mask([(TM[i] >> j) & 1 for i in range(N)])
    atoms[(ex, False)] = build_mask([(DFM[i] >> j) & 1 for i in range(N)])
DL0 = [d[6] for d in dumps]; DL1 = [d[7] for d in dumps]
for k, L in enumerate(lens):
    name = f"({L} != 0)"
    atoms[(name, True)] = build_mask([(DL1[i] >> k) & 1 for i in range(N)])
    atoms[(name, False)] = build_mask([(DL0[i] >> k) & 1 for i in range(N)])
print(f"{len(atoms)} atoms built in {time.time()-t0:.1f}s", flush=True)

items = [(k, v) for k, v in atoms.items() if v.bit_count() >= MIN_RUNS]
print(f"{len(items)} atoms with >= {MIN_RUNS} runs", flush=True)

# single-condition sanity check: should reproduce "no known condition" for a
# genuine Class-C member (if it finds one, missreason's COND table is missing it)
single = []
for (name, o), a in items:
    if (a & eval_e) == 0:
        single.append((name, o, a.bit_count()))
print(f"\nSINGLE-CONDITION forecloses: {len(single)}")
for name, o, n in single[:10]:
    print(f"   {name} = {o}   (n={n})")

# pairwise conjunction check: keep only atoms where e IS sometimes evaluated
# alongside that atom alone (else it's already a single-condition finding)
nonforecl = [(k, v) for k, v in items if (v & eval_e) != 0]
print(f"\n{len(nonforecl)} atoms individually non-foreclosing (candidates for pairing)")

found = []
t1 = time.time()
npairs = 0
for i in range(len(nonforecl)):
    (n1, o1), a1 = nonforecl[i]
    for j in range(i + 1, len(nonforecl)):
        (n2, o2), a2 = nonforecl[j]
        if n2 == n1:
            continue
        inter = a1 & a2
        c = inter.bit_count()
        if c < MIN_RUNS:
            continue
        npairs += 1
        if (inter & eval_e) == 0:
            found.append((n1, o1, n2, o2, c))
print(f"\n{npairs} pairs met MIN_RUNS co-occurrence, tested in {time.time()-t1:.1f}s")
print(f"\nGENUINE 2-WAY CONJUNCTION preconditions (neither side alone forecloses, "
      f"the pair together does, n>={MIN_RUNS}): {len(found)}")
for n1, o1, n2, o2, c in sorted(found, key=lambda r: -r[4])[:20]:
    print(f"   n={c:6d}   {n1[:200]} = {o1}   AND   {n2[:200]} = {o2}")
print("P44-REACHNEC-CONJ-DONE")
