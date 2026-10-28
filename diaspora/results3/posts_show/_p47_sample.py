#!/usr/bin/env python3
"""Build a scenario-stratified SYMLINK sample of a corpus, for fast checking.

usage: _p47_sample.py [--corpus DIR] [--out DIR] [--n N] [--seed S]

WHY. The three completion checks cost time proportional to the corpus:
`note_fidelity_audit.py` in particular has NO dump-list scoping — it globs its
batch argument unconditionally — which is why its `audit_timeout` is 21600 s.
Iterating note repairs against a six-figure corpus is hours per attempt.

MEASURED, 2026-09-25: a 20 000-dump stratified sample of the OLD corpus
reproduced the FULL-corpus verdicts EXACTLY — `note_fidelity RED = 26`, the
identical note_check MISMATCH targets, and the same 4 over-emission shapes.
That is what made it possible to enumerate the real fix list in minutes rather
than working from a truncated stored tail. Use a sample to ITERATE; use the
whole corpus only for the pass you intend to ship.

Stratified by scenario because the scenarios are wildly unbalanced (the old
corpus was 157 931 auth_html against 5 494 anon_html), and a uniform sample
would under-represent the small ones — which are exactly where several of the
RED shapes live.

Symlinks, not copies: the sample costs no disk and cannot drift from the
corpus.
"""
import argparse
import collections
import glob
import os
import random
import re
import sys

B = '/home/dev/project/reports/diaspora/results3/posts_show'
SCEN = re.compile(r'dump_(?:auth|anon)_(?:html|json)')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--corpus', default=os.path.join(B, 'v2'))
    ap.add_argument('--out', default=os.path.join(B, '_p47_sample'))
    ap.add_argument('--n', type=int, default=20000)
    ap.add_argument('--seed', type=int, default=20260925)
    a = ap.parse_args()

    files = glob.glob(os.path.join(a.corpus, 'dump_*.json'))
    if not files:
        sys.exit(f'no dumps in {a.corpus}')
    by = collections.defaultdict(list)
    for f in files:
        m = SCEN.search(os.path.basename(f))
        by[m.group(0) if m else 'other'].append(f)

    random.seed(a.seed)
    per = max(1, a.n // max(1, len(by)))
    sel = []
    for k in sorted(by):
        take = min(per, len(by[k]))
        sel += random.sample(by[k], take)
        print(f'  {k}: {len(by[k])} available -> {take}')
    # if a scenario was smaller than its share, top up from the largest pool
    if len(sel) < a.n:
        pool = [f for f in files if f not in set(sel)]
        extra = min(a.n - len(sel), len(pool))
        if extra:
            sel += random.sample(pool, extra)
            print(f'  topped up {extra} from the remaining pool')

    os.makedirs(a.out, exist_ok=True)
    for old in glob.glob(os.path.join(a.out, 'dump_*.json')):
        os.unlink(old)
    for f in sel:
        dst = os.path.join(a.out, os.path.basename(f))
        if not os.path.exists(dst):
            os.symlink(os.path.abspath(f), dst)

    # the checks need these beside the dumps
    for aux in ('concrete_run.json', 'concrete_aliases.json'):
        src, dst = os.path.join(B, aux), os.path.join(a.out, aux)
        if os.path.exists(src) and not os.path.exists(dst):
            os.symlink(src, dst)

    lst = os.path.join(a.out, '_dumps.txt')
    with open(lst, 'w') as fh:
        for f in sorted(sel):
            fh.write(os.path.abspath(f) + '\n')
    print(f'\nsample: {len(sel)} dumps -> {a.out}\ndump list: {lst}')


if __name__ == '__main__':
    main()
