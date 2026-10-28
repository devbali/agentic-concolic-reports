#!/usr/bin/env python3
"""Rebuild `_ctgt_sample/` — the concrete run's target-discovery sample.

usage: _p47_mk_ctgt_sample.py [--corpus DIR] [--out DIR] [--stride N] [--apply]

WHY THIS EXISTS. `_concrete_targets.rb` derives the concrete round's traced
target list with `targets_from_corpus(_ctgt_sample)`, NOT from the batch dir:
`targets_from_corpus` JSON-parses every `dump_*.json` it is pointed at, so
pointing it at a six-figure corpus costs ~10 minutes per scenario. The sample
is a SYMLINK directory holding a greedy set cover of the corpus's distinct
`symbolic_call` target names — the list it yields is identical to the one the
whole corpus yields, and it is still read off real dumps rather than typed out.

WHY IT MUST BE REBUILT FOR v2. The shipped sample (4 symlinks, 28 targets) was
computed 2026-09-10 against the OLD corpus and points into it. The v2 corpus
adds at least one target the old one never had — `ActiveRecord::Calculations.
pluck`, which only started minting a frame once `pluck` came out of the
`_descend` deny-list. If the sample is not rebuilt, the concrete run will not
trace `pluck`, the `mentions INNER JOIN comments` statement will still be
tagged "(outside any target frame)", and mock_note_check stays RED for a
reason that has nothing to do with the corpus.

SEQUENCE: re-drive -> rebuild this sample -> regenerate concrete_run.json ->
run the checks. See _P47_HANDOFF_20260925.md §5.

The cover is verified, not assumed: the script scans the corpus (strided),
builds the cover, then re-derives the target set FROM THE COVER and asserts it
equals the full set. It refuses to install a sample that misses anything.
"""
import argparse
import glob
import json
import os
import sys

B = '/home/dev/project/reports/diaspora/results3/posts_show'


def targets_of(path):
    try:
        d = json.load(open(path))
    except Exception:
        return set()
    return {ev['target'] for ev in (d.get('events') or [])
            if ev.get('type') == 'symbolic_call' and ev.get('result_name')
            and ev.get('target')}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--corpus', default=os.path.join(B, 'v2'))
    ap.add_argument('--out', default=os.path.join(B, '_ctgt_sample_v2'))
    ap.add_argument('--stride', type=int, default=10,
                    help='scan every Nth dump (the shipped sample used 10)')
    ap.add_argument('--apply', action='store_true',
                    help='also repoint _ctgt_sample -> the new dir (keeps a .bak)')
    ap.add_argument('--compare-to', default=os.path.join(B, '_ctgt_sample'),
                    help='an earlier sample whose target set the new corpus must COVER')
    ap.add_argument('--allow-lost', action='store_true',
                    help='apply even though targets from --compare-to are missing '
                         '(only after deciding it is an unreached path, not a regression)')
    a = ap.parse_args()

    files = sorted(glob.glob(os.path.join(a.corpus, 'dump_*.json')))
    if not files:
        sys.exit(f'no dumps in {a.corpus}')
    scan = files[::a.stride]
    print(f'corpus {len(files)} dumps; scanning every {a.stride}th = {len(scan)}')

    per = {}
    universe = set()
    for f in scan:
        t = targets_of(f)
        if t:
            per[f] = t
            universe |= t
    print(f'distinct symbolic_call targets in the scan: {len(universe)}')

    # greedy set cover
    cover, remaining = [], set(universe)
    while remaining:
        best = max(per, key=lambda f: len(per[f] & remaining))
        gain = per[best] & remaining
        if not gain:
            break
        cover.append(best)
        remaining -= gain
    if remaining:
        sys.exit(f'REFUSING: {len(remaining)} target(s) uncovered: {sorted(remaining)[:5]}')

    # verify the cover by re-deriving from it alone
    got = set()
    for f in cover:
        got |= targets_of(f)
    missing = universe - got
    if missing:
        sys.exit(f'REFUSING: cover re-derivation missed {sorted(missing)}')
    print(f'cover: {len(cover)} dump(s) covering all {len(universe)} targets, 0 uncovered')

    os.makedirs(a.out, exist_ok=True)
    for old in glob.glob(os.path.join(a.out, 'dump_*.json')):
        os.unlink(old)
    for f in cover:
        os.symlink(os.path.abspath(f), os.path.join(a.out, os.path.basename(f)))
    print(f'wrote {len(cover)} symlink(s) -> {a.out}')
    for t in sorted(universe):
        print(f'    {t}')

    # REGRESSION GATE. A target the OLD corpus minted but the new one does not
    # means one of two things, and they need opposite responses:
    #   (a) exploration has not reached that path yet -- drive more; or
    #   (b) one of the phase-(a) fixes silently stopped a mock from firing.
    # Either way it must not pass silently, because the concrete run derives
    # its traced targets from this sample: a target missing here is a target
    # the concrete round will never tag, and mock_note_check will then report
    # its statements as "(outside any target frame)" -- RED for a reason that
    # looks like a corpus problem and is not.
    if a.compare_to and os.path.isdir(a.compare_to):
        prev = set()
        for f in glob.glob(os.path.join(a.compare_to, 'dump_*.json')):
            prev |= targets_of(f)
        lost = prev - universe
        if lost:
            print(f'\n*** {len(lost)} target(s) in {os.path.basename(a.compare_to)} '
                  f'are ABSENT from this corpus:', file=sys.stderr)
            for t in sorted(lost):
                print(f'      {t}', file=sys.stderr)
            print('    Decide which it is before applying: unreached path '
                  '(drive more) or a mock that stopped firing (a real '
                  'regression). Re-run with --allow-lost once decided.',
                  file=sys.stderr)
            if a.apply and not a.allow_lost:
                sys.exit('REFUSING --apply while targets are missing')
        else:
            print(f'regression gate: v2 covers all {len(prev)} target(s) of '
                  f'{os.path.basename(a.compare_to)}')

    if a.apply:
        live = os.path.join(B, '_ctgt_sample')
        if os.path.exists(live) and not os.path.islink(live):
            bak = live + '.bak_pre_v2_20260925'
            if not os.path.exists(bak):
                os.rename(live, bak)
                print(f'preserved the old sample -> {os.path.basename(bak)}')
        if os.path.islink(live):
            os.unlink(live)
        os.symlink(a.out, live)
        print(f'_ctgt_sample -> {a.out}')
    else:
        print('\n(dry run: pass --apply to repoint _ctgt_sample at it)')


if __name__ == '__main__':
    main()
