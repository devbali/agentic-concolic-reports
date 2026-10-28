#!/usr/bin/env python3
"""Compare ORIGINAL (pre-guard) vs NEW (post-guard) missing[] guard sign.

For each missing item, report whether guard tokens appear as:
  POS  : `(X_..._not_found == True)`  -> demands the guard var == True
  NEG  : `Not((X_..._not_found == True))` -> demands the guard var == False
  none : no guard token

Compare across the two snapshots and report counts + which guards appear.
"""
import json, sys

SNAP = {
    "original": "/tmp/coverage_summary_ORIGINAL_64missing.json",
    "new": "coverage_summary.json",
}

def analyze(path):
    cs = json.load(open(path))
    miss = cs.get("missing") or []
    out = []
    for m in miss:
        nc = m["node_constraint"]
        guards = {}  # var -> sign ('pos'|'neg')
        # find positive:  (X == True)  where X ends in _not_found/_closed_account
        # find negated:   Not((X == True))
        i = 0
        while True:
            j = nc.find("== True", i)
            if j < 0:
                break
            # find start of this ==context: walk back to previous ' AND '
            k = nc.rfind(" AND ", 0, j)
            # check negated: is there a 'Not(' before k within small window
            neg = False
            before = nc[max(0, k - 4):k]
            if nc[max(0, k - 4):k].endswith("Not((") or nc[max(0, k - 3):k].endswith("Not(("):
                neg = True
            # extract variable from context
            seg = nc[k + 5:j].strip()
            var = seg.strip("()").strip().split(" == ")[0].strip()
            var = var.strip("()")
            # context for negation more robustly: the segment to the left
            # may be `Not((X` meaning var is inside Not(
            if "Not((" in seg:
                neg = True
                var = seg.split("Not((")[-1].split(" == ")[0].strip()
            if var.endswith("_not_found") or var.endswith("_closed_account"):
                guards[var] = "neg" if neg else "pos"
            i = j + 6
        out.append(guards)
    return out, miss

import collections
for label, path in SNAP.items():
    guards, miss = analyze(path)
    ns = collections.Counter()
    signc = collections.Counter()
    for g in guards:
        n = len(g)
        if n == 0:
            ns["none"] += 1
        else:
            ns["has_guard"] += 1
            sig = set(g.values())
            if sig == {"pos"}:
                signc["pos_only"] += 1
            elif sig == {"neg"}:
                signc["neg_only"] += 1
            elif sig == {"pos", "neg"}:
                signc["mixed"] += 1
    print(f"\n=== {label}: {len(miss)} missing ===")
    print("  no-guard:", ns["none"], " has-guard:", ns["has_guard"])
    print("  sign of guards:", dict(signc))
    # distinct guard vars + sign
    vc = collections.Counter()
    for g in guards:
        for var, sg in g.items():
            vc[(var, sg)] += 1
    print("  distinct (var, sign):")
    for (var, sg), c in sorted(vc.items()):
        print(f"     {c:4d}  {sg:3s}  {var}")
