#!/usr/bin/env python3
"""Cycle-6 answer to the coordinator's tier-2 question (ADVERSARY_WINS §7).

Is the disjoint-rep tier "mechanically generated over rep pairs that never
co-evaluate", i.e. an artefact of giving each row of a list its own rep?

Measures, on the live corpus:
  1. distinct PC expressions and distinct REP KEYS (the tier's unit);
  2. the tier's size against the complete graph it is the complement of;
  3. ORDINAL-DUPLICATE reps: two rep prefixes that, IN THE SAME RUN, carry the
     IDENTICAL rendered statement — the §7 defect (one fact, many variables);
  4. co-evaluation: how many cross-rep pairs are ever recorded in one run.
"""
import glob, json, os, re, sys
from collections import defaultdict, Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from coverage_assumptions import _rep_key, _DISPATCH_RE   # noqa: E402

args = sys.argv[1:]
sample = int(args[args.index('--sample')+1]) if '--sample' in args else 1500
files = sorted(glob.glob(os.path.join(HERE, 'dump_*.json')))
if sample and len(files) > sample:
    step = len(files)/float(sample)
    files = [files[int(i*step)] for i in range(sample)]

exprs = set()
runs_of = defaultdict(set)
dup_pairs = Counter()
dup_example = {}
for i, p in enumerate(files):
    d = json.load(open(p))
    seen = set()
    for ev in d.get('events') or ():
        if ev.get('type') == 'path_condition':
            e = ev['expr']
            exprs.add(e); runs_of[e].add(i); seen.add(e)
    # ordinal-duplicate detection: rep base -> rendered statement
    by_note = defaultdict(set)
    for sv in d.get('symbolic_vars') or ():
        n = str(sv.get('name') or ''); nt = re.sub(r'\s+', ' ', str(sv.get('note') or ''))
        if not nt.upper().startswith('SELECT'):
            continue
        m = re.match(r'^(SYM_RESULT_[A-Za-z0-9_]*?_(?:\d+))(?:_|$)', n)
        if m:
            by_note[nt].add(m.group(1))
    for nt, bases in by_note.items():
        if len(bases) > 1:
            for a in sorted(bases):
                for b in sorted(bases):
                    if a < b:
                        dup_pairs[(a, b)] += 1
                        dup_example.setdefault((a, b), (os.path.basename(p), nt[:110]))

exprs = sorted(exprs)
rep = {e: _rep_key(e) for e in exprs}
reps = sorted({v for v in rep.values() if v})
nd = [e for e in exprs if not _DISPATCH_RE.match(e)]
cross = 0
coeval = 0
for i, a in enumerate(nd):
    for b in nd[i+1:]:
        if rep[a] and rep[b] and rep[a] != rep[b]:
            cross += 1
            if runs_of[a] & runs_of[b]:
                coeval += 1
print(f"== tier2 audit: {len(files)} dumps sampled ==")
print(f"distinct PC exprs            : {len(exprs)}")
print(f"distinct REP KEYS            : {len(reps)}")
print(f"complete graph over exprs    : {len(exprs)*(len(exprs)-1)//2}")
print(f"cross-rep pairs (tier2 unit) : {cross}")
print(f"  ... of which CO-EVALUATED  : {coeval} ({100.0*coeval/max(cross,1):.1f}%)")
print(f"  ... never co-evaluated     : {cross-coeval}")
print()
print(f"-- ORDINAL-DUPLICATE reps (same rendered statement, same run) : {len(dup_pairs)} pairs --")
for (a, b), c in dup_pairs.most_common(15):
    f, nt = dup_example[(a, b)]
    print(f"  {c:6d} runs  {a}  ==  {b}")
    print(f"          {nt}   [{f}]")
if not dup_pairs:
    print("  none — every rep in the corpus is a distinct rendered query (§7 satisfied)")
print()
print("-- rep keys --")
for r in reps:
    print("   ", r)
