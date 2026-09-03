#!/usr/bin/env python3
"""Batch-local diagnostic: for every pair of PC expressions in the corpus,
which outcome combinations were observed in a SINGLE run (the checker's
co-evaluation semantics), and whether coverage_assumptions.py declares the
pair independent. Pairs NEVER co-evaluated must be declared (structural
gating); pairs co-evaluated with missing combos need exploration or a
declaration with a written reason."""
import glob, json, os, sys, itertools, collections
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coverage_assumptions import build
from concolic_engine.assumptions import IndependenceAssumption, UntrackedPathAssumption
aset = build()
indep = set()
untracked = set()
for a in aset.assumptions:
    if isinstance(a, IndependenceAssumption): indep.add(frozenset((a.expr_a, a.expr_b)))
    if isinstance(a, UntrackedPathAssumption): untracked.add(a.expr)
combos = collections.defaultdict(set)
exprs = set()
for p in glob.glob(os.path.join(os.path.dirname(os.path.abspath(__file__)), "dump_*.json")):
    d = json.load(open(p))
    oc = {}
    for e in d["events"]:
        if e["type"] == "path_condition":
            oc.setdefault(e["expr"], set()).add(bool(e["taken"]))
    exprs |= set(oc)
    for a, b in itertools.combinations(sorted(oc), 2):
        for x in oc[a]:
            for y in oc[b]:
                combos[(a, b)].add((x, y))
short = lambda e: e.replace("SYM_RESULT_ActiveRecord__", "").replace("Core__ClassMethods_", "").replace("FinderMethods_", "").replace("Relation_", "").replace(" == True)", ")")
never, partial = [], []
for a, b in itertools.combinations(sorted(exprs - untracked), 2):
    if frozenset((a, b)) in indep: continue
    c = combos.get((a, b), set())
    if not c: never.append((a, b))
    elif len(c) < 4: partial.append((a, b, c))
print(f"{len(exprs)} exprs, {len(untracked)} untracked, {len(indep)} declared pairs")
print(f"\n-- NEVER co-evaluated and NOT declared ({len(never)}):")
for a, b in never: print("  ", short(a), "x", short(b))
print(f"\n-- co-evaluated with MISSING combos and NOT declared ({len(partial)}):")
for a, b, c in partial: print("  ", short(a), "x", short(b), "observed:", sorted(c))
