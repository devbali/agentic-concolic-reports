#!/usr/bin/env python3
"""Round-9 analysis: per-tag statement multiset from the frames capture,
split into ENDPOINT statements (stack reaches comments_controller#index or one
of the action's own templates) and SCENARIO-BODY statements (everything else:
the harness salt cache, my probes).  Compares endpoint counts with the corpus
maxima for the same request class."""
import json, re, sys, collections

def shape(s):
    s = re.sub(r"'[^']*'", "'@'", str(s))
    s = re.sub(r'\b\d+\b', '@', s)
    s = re.sub(r'\?', '@', s)
    s = re.sub(r'@(\s*,\s*@)+', '@', s)
    return re.sub(r'\s+', ' ', s).strip().lower()

ENTRY = re.compile(r'comments_controller\.rb|views/comments/')
for path in sys.argv[1:]:
    fr = json.load(open(path))
    print('=' * 100)
    print(path, '   statements captured:', len(fr))
    per = collections.OrderedDict()
    for e in fr:
        tag = e.get('tag') or '(no tag / scenario body)'
        frames = ' '.join(e.get('frames') or [])
        zone = 'ENDPOINT' if ENTRY.search(frames) else 'BODY'
        per.setdefault(tag, {'ENDPOINT': collections.Counter(), 'BODY': collections.Counter()})
        per[tag][zone][shape(e['sql'])] += 1
    for tag, z in per.items():
        print('-' * 90)
        print('TAG', tag)
        for zone in ('ENDPOINT', 'BODY'):
            if not z[zone]:
                continue
            print('  [%s] %d statements' % (zone, sum(z[zone].values())))
            for k, v in z[zone].most_common():
                print('     x%-3d %s' % (v, k[:150]))
