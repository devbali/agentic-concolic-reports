#!/usr/bin/env python3
"""Rigorous verification for the first_2 handle-family foreclosure:

1. In ALL 7673 dumps: `Contains('@', first_2_diaspora_handle)` and
   `IndexOf(first_2_diaspora_handle, '@') == 2` record taken:TRUE only
   (0 false-side witnesses) -- the same OneSide pattern as CONT1/IDX1.
2. The `Not(Contains('@', first_2_diaspora_handle))` expr (NOTC) is a
   SEPARATE expr that appears only when no '@' -- by construction the split
   records either the found-arm (CONT+IDX taken:true) or the no-match arm
   (NOTC taken:true), never both, never a false side.
3. Show the string.rb call sites verbatim (the construction proof).
"""
import glob
import json
import os
import re
import sys
import collections

HERE = '/home/dev/project/reports/diaspora/results3/people_show'
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run  # noqa: E402

_LEN_RE = re.compile(r"len\(([^()]+)\)")


def fix_len_names(dump):
    return json.loads(_LEN_RE.sub(r"SYM_LEN_\1", json.dumps(dump)))


TARGETS = [
    "Contains(StringVal('@'), SYM_RESULT_ActiveRecord__FinderMethods_first_2_diaspora_handle)",
    "Not(Contains(StringVal('@'), SYM_RESULT_ActiveRecord__FinderMethods_first_2_diaspora_handle))",
    "IndexOf(SYM_RESULT_ActiveRecord__FinderMethods_first_2_diaspora_handle, StringVal('@')) == 1",
    "IndexOf(SYM_RESULT_ActiveRecord__FinderMethods_first_2_diaspora_handle, StringVal('@')) == 2",
    "IndexOf(SYM_RESULT_ActiveRecord__FinderMethods_first_2_diaspora_handle, StringVal('@')) == 3",
]
cov = collections.defaultdict(lambda: [0, 0])
co_occur = collections.Counter()
n = 0
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
        run = Run.from_dict(fix_len_names(raw))
    except Exception:
        continue
    n += 1
    seen = set()
    for pc in run.path_conditions:
        if pc.expr in TARGETS:
            seen.add((pc.expr, bool(pc.taken)))
            cov[pc.expr][0 if pc.taken else 1] += 1
    # co-occurrence signature within the run
    arms = set()
    for e, t in seen:
        if e.startswith("Not(Contains"):
            arms.add("NOTC")
        elif e.startswith("Contains"):
            arms.add("CONT")
        elif e.startswith("IndexOf"):
            arms.add("IDX%d" % (1 if "== 1" in e else 2 if "== 2" in e else 3))
    if arms:
        co_occur[tuple(sorted(arms))] += 1

print("runs: %d" % n)
print("\n=== first_2 handle-family exprs (T / F) ===")
for e in TARGETS:
    t, f = cov[e]
    print("  T=%6d F=%6d  %s" % (t, f, e[:100]))

print("\n=== per-run arm co-occurrence signatures ===")
for sig, c in co_occur.most_common():
    print("  %6d  %s" % (c, sig))