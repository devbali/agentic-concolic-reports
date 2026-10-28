#!/usr/bin/env python3
"""Is an IDENTITY variable's value DERIVED from a seeded input, or from
something no seed controls?

The test is a corpus-wide agreement check, not an argument: over a sample of
dumps, for every variable whose name ends in an identity suffix, compare the
value the RUNTIME minted (`symbolic_vars`) against the value the run was SEEDED
with (`concolic_seeds`). A key the runtime consumes agrees 100 % of the time;
a key nothing consumes either never appears as a seed, or appears and is
IGNORED (seed != minted). Names are the RAW per-run names; the identity family
is decided by suffix, and the `_rowN_` (N>=2) forms are counted separately
because they are a different construct (see the report).

usage: _ident_seed_scan.py [N_SAMPLE]
"""
import json, random, re, sys, collections

SUF = ('_person_id', '_row_id', '_guid', '_diaspora_handle')
ROWN = re.compile(r'_row([2-9]|\d\d+)_')

def fam(n):
    for s in SUF:
        if n.endswith(s):
            return ('rowN' + s) if ROWN.search(n) else s
    return None

N = int(sys.argv[1]) if len(sys.argv) > 1 else 800
snap = [l.strip() for l in open('_snapshot_20260910_164828.txt')]
random.seed(23)
sample = random.sample(snap, min(N, len(snap)))

minted = collections.Counter()       # var occurrences
seeded = collections.Counter()       # occurrences where a seed key exists
agree  = collections.Counter()       # ... and the minted value equals it
distinct = collections.defaultdict(set)
noseed_distinct = collections.defaultdict(set)  # values seen when NOT seeded
for p in sample:
    try:
        d = json.load(open(p))
    except Exception:
        continue
    sv = {v.get('name'): v.get('value') for v in (d.get('symbolic_vars') or [])}
    sd = d.get('concolic_seeds') or {}
    for n, val in sv.items():
        f = fam(n)
        if not f:
            continue
        minted[f] += 1
        distinct[f].add(repr(val))
        if n in sd:
            seeded[f] += 1
            if repr(sd[n]) == repr(val):
                agree[f] += 1
        else:
            noseed_distinct[f].add(repr(val))

print(f"sampled {len(sample)} dumps\n")
hdr = f"{'family':26s} {'minted':>8s} {'seeded':>8s} {'agree':>8s} {'agree%':>7s} {'distinct vals':>13s}"
print(hdr); print('-' * len(hdr))
for f in sorted(minted, key=lambda k: -minted[k]):
    a = 100 * agree[f] / seeded[f] if seeded[f] else float('nan')
    print(f"{f:26s} {minted[f]:8d} {seeded[f]:8d} {agree[f]:8d} {a:7.1f} {len(distinct[f]):13d}")
print("\nvalues seen when the var was NOT seeded (the runtime's own choice):")
for f in sorted(minted, key=lambda k: -minted[k]):
    vs = sorted(noseed_distinct[f])[:6]
    print(f"  {f:26s} {len(noseed_distinct[f])} distinct: {vs}")
