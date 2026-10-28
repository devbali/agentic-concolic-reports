#!/usr/bin/env python3
"""Compare the != '' textual-dual across all guid vars: which have TRUE
witnesses, which never do. Establish the pattern for the proof."""
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

cov = collections.defaultdict(lambda: [0, 0])
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
        run = Run.from_dict(fix_len_names(raw))
    except Exception:
        continue
    seen = set()
    for pc in run.path_conditions:
        if "guid" in pc.expr or "== ''" in pc.expr or "!= StringVal('')" in pc.expr:
            cov[pc.expr][0 if pc.taken else 1] += 1

print("=== all guid / empty-string expr forms (T / F) ===")
for e, (t, f) in sorted(cov.items()):
    print("  T=%6d F=%6d  %s" % (t, f, e[:130]))