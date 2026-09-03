#!/usr/bin/env python3
"""Batch-local corpus scanner: PC polarity table + note-shape table.
Usage: _scan_corpus.py [--sample N] [--pc REGEX] [--note REGEX]
"""
import glob, json, os, re, sys
from collections import Counter, defaultdict

args = sys.argv[1:]
def opt(f, d=None):
    return args[args.index(f)+1] if f in args else d
sample = int(opt('--sample', 0) or 0)
pcre = re.compile(opt('--pc', '.')) if '--pc' in args else None
nre = re.compile(opt('--note', '.')) if '--note' in args else None
HERE = os.path.dirname(os.path.abspath(__file__))
files = sorted(glob.glob(os.path.join(HERE, 'dump_*.json')))
if sample and len(files) > sample:
    step = len(files)/float(sample)
    files = [files[int(i*step)] for i in range(sample)]
pol = defaultdict(Counter)
notes = Counter()
nex = {}
n = 0
for p in files:
    try:
        d = json.load(open(p))
    except Exception:
        continue
    n += 1
    for ev in d.get('events') or []:
        t = ev.get('type')
        if t == 'path_condition':
            e = ev.get('expr') or ''
            if pcre is None or pcre.search(e):
                pol[e][bool(ev.get('taken'))] += 1
        elif t == 'symbolic_call' and nre is not None:
            nt = re.sub(r'\s+', ' ', str(ev.get('note') or ''))
            if nre.search(nt):
                notes[nt[:150]] += 1
                nex.setdefault(nt[:150], os.path.basename(p))
    if nre is not None:
        for sv in d.get('symbolic_vars') or []:
            nt = re.sub(r'\s+', ' ', str(sv.get('note') or ''))
            if nre.search(nt):
                notes[nt[:150]] += 1
                nex.setdefault(nt[:150], os.path.basename(p))
print(f"== scanned {n} dumps ==")
if pcre is not None:
    print(f"-- PCs matching ({len(pol)}) --")
    for e, c in sorted(pol.items(), key=lambda kv: -sum(kv[1].values())):
        print(f"  T={c[True]:7d} F={c[False]:7d}  {e[:150]}")
if nre is not None:
    print(f"-- notes matching ({len(notes)}) --")
    for nt, c in notes.most_common(40):
        print(f"  {c:8d}  {nt}   [{nex[nt]}]")
