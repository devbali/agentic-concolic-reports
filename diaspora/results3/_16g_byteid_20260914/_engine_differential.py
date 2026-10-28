#!/usr/bin/env python3
"""OLD-vs-NEW engine differential for the §16g edit (2026-09-14).

The endpoint byte-identity runs cover the flags-OFF path on real corpora.
This covers the paths those endpoints do NOT exercise — §16e alone and §16f
alone — by loading the PRE-EDIT `coverage.py` (from the dated backup) and the
CURRENT one in ONE process, under different module names, and comparing
`summary()` and the missing-cube set on random corpora at four settings:

    (1) all flags off        (2) foreclosure_conjunctions=True   [§16e]
    (3) foreclosure_subconjunctions=True  [§16f]   (4) + width 2

A single differing line is a failure. The §16g setting has no OLD counterpart
and is not compared.
"""
import importlib.machinery, importlib.util, os, random, sys

SRC = "/home/dev/project/src"
OLD = ("/home/dev/project/reports/diaspora/results3/_bak_src_20260914/"
       "coverage.py.pre_16g_20260914")
sys.path.insert(0, SRC)

import concolic_engine                                        # noqa: E402
from concolic_engine.coverage import CoverageChecker as NewCC  # noqa: E402
from concolic_engine.run import Run, SymbolicVar, PathCondition  # noqa: E402

# load the pre-edit module as a SECOND module inside the same package, so its
# relative imports (checkpoint / solver / assumptions / run) resolve normally
spec = importlib.util.spec_from_file_location(
    "concolic_engine.coverage_pre16g", OLD,
    loader=importlib.machinery.SourceFileLoader(
        "concolic_engine.coverage_pre16g", OLD))
old_mod = importlib.util.module_from_spec(spec)
sys.modules["concolic_engine.coverage_pre16g"] = old_mod
spec.loader.exec_module(old_mod)
OldCC = old_mod.CoverageChecker
print(f"OLD {OLD}\nNEW {concolic_engine.coverage.__file__}", flush=True)

EXPRS = ["(a > 0)", "(b > 0)", "(g1 > 0)", "(g2 > 0)",
         "(x > 0)", "(y > 0)", "(z > 0)"]
NAMES = ["a", "b", "g1", "g2", "x", "y", "z"]
VARS = [SymbolicVar(n, "Int") for n in NAMES]


def mkrun(label, outcomes):
    ev = []
    for e in EXPRS:
        if e not in outcomes:
            continue
        v = outcomes[e]
        if v is None:
            ev += [PathCondition(e, taken=True), PathCondition(e, taken=False)]
        else:
            ev.append(PathCondition(e, taken=v))
    return Run(symbolic_vars=list(VARS), events=ev,
               concrete_values={n: 1 for n in NAMES}, label=label)


def corpus(rng):
    esc1, esc2 = rng.random() < .5, rng.random() < .5
    conds = rng.sample(EXPRS, 2)
    want = (rng.random() < .5, rng.random() < .5)
    runs = []
    for i in range(rng.randint(10, 30)):
        o = {}
        for e in EXPRS:
            r = rng.random()
            if r < .55:
                o[e] = rng.random() < .5
            elif r < .62:
                o[e] = None
        if "(g1 > 0)" in o and o["(g1 > 0)"] is esc1:
            o.pop("(x > 0)", None)
        if "(g2 > 0)" in o and o["(g2 > 0)"] is esc2:
            o.pop("(y > 0)", None)
        if tuple(o.get(c) for c in conds) == want:
            o.pop("(z > 0)", None)
            o.pop("(a > 0)", None)
        if o:
            runs.append(mkrun(f"r{i}", o))
    return runs


SETTINGS = [
    ("all-off", {}),
    ("16e", {"foreclosure_conjunctions": True}),
    ("16f-W3", {"foreclosure_subconjunctions": True}),
    ("16f-W2", {"foreclosure_subconjunctions": True,
                "foreclosure_conjunction_width": 2}),
]


def strip(res):
    return [l for l in res.summary().splitlines()
            if not l.startswith("  Solver time:")]


bad = 0
n = int(os.environ.get("TRIALS", "120"))
rng = random.Random(20260914)
counts = {k: 0 for k, _ in SETTINGS}
for t in range(n):
    c = corpus(rng)
    if not c:
        continue
    for name, kw in SETTINGS:
        o = OldCC(c, max_missing_per_clique=64, **kw).check_coverage()
        w = NewCC(c, max_missing_per_clique=64, **kw).check_coverage()
        so, sw = strip(o), strip(w)
        mo = sorted(m.missing_constraint for m in o.missing)
        mw = sorted(m.missing_constraint for m in w.missing)
        do = o.assumptions_to_dict()
        dw = w.assumptions_to_dict()
        if so != sw or mo != mw or do != dw:
            bad += 1
            print(f"  *** DIFFER trial {t} setting {name}", flush=True)
            for x, y in zip(so, sw):
                if x != y:
                    print(f"      OLD {x}\n      NEW {y}", flush=True)
            break
        counts[name] += 1
print(f"\n{n} random corpora x {len(SETTINGS)} settings: "
      + ", ".join(f"{k} {v} identical" for k, v in counts.items()))
print(f"DIFFERENCES: {bad}")
print("ENGINE-DIFFERENTIAL-DONE" if bad == 0 else "ENGINE-DIFFERENTIAL-FAILED")
sys.exit(1 if bad else 0)
