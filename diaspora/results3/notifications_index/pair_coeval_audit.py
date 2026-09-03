#!/usr/bin/env python3
"""Batch-local diagnostic (ported from comments_index): for every pair of PC
expressions in the corpus, which outcome combinations were observed in a
SINGLE run (the checker's co-evaluation semantics), and whether
coverage_assumptions.py declares the pair independent. Pairs NEVER
co-evaluated must be declared (structural gating); pairs co-evaluated with
missing combos need exploration or a declaration with a written reason.

Also lists DECLARED pairs that ARE co-evaluated somewhere (those are the
ones the engine's derived flip-probe test actually exercises — every
declaration here must be a structural gate, so this list should be empty).

    PYTHONPATH=src python3 <batch>/pair_coeval_audit.py [--show N]
"""
import glob, json, os, sys, itertools, collections
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from coverage_assumptions import build
from coverage_report import fix_len_names, share_run_objects, apply_len_bounds
from concolic_engine.run import Run
from concolic_engine.assumptions import IndependenceAssumption, UntrackedPathAssumption

show = int(sys.argv[sys.argv.index("--show") + 1]) if "--show" in sys.argv else 40

runs = []
combos = collections.defaultdict(set)
exprs = set()
for p in sorted(glob.glob(os.path.join(HERE, "dump_*.json"))):
    d = json.load(open(p))
    d = fix_len_names(d)
    runs.append(share_run_objects(apply_len_bounds(Run.from_dict(d))))
    oc = {}
    for e in d["events"]:
        if e["type"] == "path_condition":
            oc.setdefault(e["expr"], set()).add(bool(e["taken"]))
    exprs |= set(oc)
    for a, b in itertools.combinations(sorted(oc), 2):
        for x in oc[a]:
            for y in oc[b]:
                combos[(a, b)].add((x, y))

aset = build(runs)
indep = set()
untracked = set()
for a in aset.assumptions:
    if isinstance(a, IndependenceAssumption): indep.add(frozenset((a.expr_a, a.expr_b)))
    if isinstance(a, UntrackedPathAssumption): untracked.add(a.expr)

short = lambda e: (e.replace("SYM_RESULT_ActiveRecord__", "").replace("Core__ClassMethods_", "")
                    .replace("FinderMethods_", "").replace("Relation_", "").replace("Calculations_", "")
                    .replace("Associations__SingularAssociation_", "").replace(" == True)", ")"))
never, partial, declared_coeval = [], [], []
for a, b in itertools.combinations(sorted(exprs - untracked), 2):
    c = combos.get((a, b), set())
    if frozenset((a, b)) in indep:
        if c: declared_coeval.append((a, b, c))
        continue
    if not c: never.append((a, b))
    elif len(c) < 4: partial.append((a, b, c))
print(f"{len(runs)} runs, {len(exprs)} exprs, {len(untracked)} untracked, {len(indep)} declared pairs")
print(f"\n-- NEVER co-evaluated and NOT declared ({len(never)}):")
for a, b in never[:show]: print("  ", short(a), "x", short(b))
print(f"\n-- co-evaluated with MISSING combos and NOT declared ({len(partial)}):")
for a, b, c in partial[:show]: print("  ", short(a), "x", short(b), "observed:", sorted(c))
print(f"\n-- DECLARED independent but CO-EVALUATED somewhere ({len(declared_coeval)}) [should be 0]:")
for a, b, c in declared_coeval[:show]: print("  ", short(a), "x", short(b), "observed:", sorted(c))
