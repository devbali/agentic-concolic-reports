#!/usr/bin/env python3
"""Check the 16-family items against the drained corpus.

For each 16-family missing item: does ANY dump in the fresh corpus contain
a run whose path covers the item's demanded outcomes?

Simplified witness check: the item demands a set of (expr-ish, outcome)
pairs. A run witnesses it iff for every demanded conjunct the run's events
contain a matching expr with taken == demanded outcome.

Focus on the row ordinal conjuncts first (the deterministic part), then the
data conjuncts.
"""
import glob
import json
import os
import re
import sys

HERE = '/home/dev/project/reports/diaspora/results3/people_show'
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run  # noqa: E402

_LEN_RE = re.compile(r"len\(([^()]+)\)")


def fix_len_names(dump: dict) -> dict:
    return json.loads(_LEN_RE.sub(r"SYM_LEN_\1", json.dumps(dump)))


data = json.load(open(os.path.join(HERE, 'coverage_summary_live.json')))
missing = data['missing']

# 16-family items: rows 4,5 only
ROW_RE = re.compile(r"Relation_records_(\d+)_rows")
fam16 = [it for it in missing
         if set(int(m.group(1)) for m in ROW_RE.finditer(it['node_constraint'])) == {4, 5}]
print(f"16-family items: {len(fam16)}")

# Load ALL runs' expr->taken maps (raw, before len rename — use the dump
# events directly like the checker does)
dumps = sorted(os.path.join(HERE, f) for f in os.listdir(HERE)
               if f.startswith("dump_") and f.endswith(".json"))
print(f"dumps on disk: {len(dumps)}")

run_exprs = []  # list of dict expr->set(taken) using SYM_LEN names
for p in dumps:
    try:
        raw = json.load(open(p))
        fixed = fix_len_names(raw)
        run = Run.from_dict(fixed)
    except Exception:
        continue
    outs = {}
    for pc in run.path_conditions:
        outs.setdefault(pc.expr, set()).add(bool(pc.taken))
    run_exprs.append(outs)
print(f"runs loaded: {len(run_exprs)}")


def split_conjuncts(nc):
    """Split 'A AND B AND C' into conjunct strings (naive — exprs have no
    nested AND parens at top level in these constraints)."""
    return [c.strip() for c in nc.split(" AND ")]


def check_witness(nc, run_outs):
    """True iff every conjunct's expr+outcome appears in run_outs."""
    for conj in split_conjuncts(nc):
        # conj is like "Not((X == Y))" or "(X == Y)" — normalized by the
        # checker is already in node_constraint form. Try direct expr match:
        if conj in run_outs and True in run_outs[conj]:
            continue
        # The run stores PathCondition(expr, taken) where expr is the RAW
        # expr and taken is bool. node_constraint uses _outcome_constraint
        # which wraps expr in Not(...) for False or bare for True.
        # So: bare conj -> taken True; Not(conj) -> taken False.
        if conj.startswith("Not(") and conj.endswith(")"):
            inner = conj[4:-1]
            if inner in run_outs and False in run_outs[inner]:
                continue
        else:
            if conj in run_outs and True in run_outs[conj]:
                continue
        return False
    return True


witnessed = 0
unwitnessed_items = []
for it in fam16:
    nc = it['node_constraint']
    ok = any(check_witness(nc, ro) for ro in run_exprs)
    if ok:
        witnessed += 1
    else:
        unwitnessed_items.append(it)

print(f"16-family witnessed by >=1 run: {witnessed}/{len(fam16)}")

# For unwitnessed: which conjuncts block? Show the first unwitnessed item's
# conjuncts with a global coverage count (how many runs have that conjunct T/F)
if unwitnessed_items:
    it = unwitnessed_items[0]
    print("\nFirst unwitnessed 16-item — conjunct coverage across corpus:")
    for conj in split_conjuncts(it['node_constraint']):
        t = sum(1 for ro in run_exprs if conj in ro and True in ro[conj])
        f = sum(1 for ro in run_exprs if conj in ro and False in ro[conj])
        print(f"  T={t:5d} F={f:5d}  {conj[:110]}")