#!/usr/bin/env python3
"""HOW BIG IS THE LEVER? — the demand universe under ONE hypothetical declaration.

§54 measured that 8 201 of the 8 206 pairs the dependence graph joins share no
Z3 variable, and that no variable-connected component anywhere is larger than 2.
The obvious question for whoever decides the assumption layer is: if those pairs
WERE declared independent, what would this endpoint's demand universe be?

This answers it by MEASUREMENT, not estimate. It runs the identical census with
one thing changed: `are_independent(a, b)` also returns True when a and b share
no symbolic variable. Everything else — load path, assumptions, pins,
foreclosure inference, evaluation sets, the factorised counting — is untouched,
so the output is directly comparable to `_enum_p5_cost.log`.

IT IS A HYPOTHETICAL AND IT IS NOT A DECLARATION. Nothing is written to
`coverage_assumptions.py`; under DISCIPLINE each such pair (or, more usefully,
each row/finder FAMILY) needs its own ground-truth differential before it may be
declared. This only prices the work.
"""
import json, os, re, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
import _exact_enum_emit as EE                                  # noqa: E402
from coverage_assumptions import build as build_assumptions    # noqa: E402

# Z3 syntax that is not a symbolic variable.
_BUILTIN = {"Not", "And", "Or", "Implies", "If", "Length", "StringVal", "IntVal",
            "BoolVal", "True", "False", "Distinct", "Concat", "SubString",
            "IndexOf", "Contains", "PrefixOf", "SuffixOf", "Int", "String",
            "Bool", "ToInt", "ToStr", "Select", "Store"}
_ID = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_cache = {}


def sym_vars(e):
    if e not in _cache:
        _cache[e] = frozenset(t for t in _ID.findall(e) if t not in _BUILTIN)
    return _cache[e]


_FAM = [(re.compile(r"_[0-9a-f]{8}(?![0-9a-f])"), "_<hash>"),
        (re.compile(r"_[0-9]+_"), "_<n>_"),
        (re.compile(r"_[0-9]+(?=_rows|_ids|\b|\))"), "_<n>")]


def family(e):
    """The expression with its ORDINAL/HASH identity stripped, so per-row and
    per-finder instances of one decision collapse to one name. This is the
    granularity a declaration would actually be written at."""
    for rx, rep in _FAM:
        e = rx.sub(rep, e)
    return e


class WhatIf:
    """The batch's own AssumptionSet, with ONE relation widened."""

    def __init__(self, base):
        self._b = base
        self.widened = 0
        self.fam = {}

    def __getattr__(self, n):
        return getattr(self._b, n)

    def are_independent(self, sa, sb, ea, eb):
        if self._b.are_independent(sa, sb, ea, eb):
            return True
        if not (sym_vars(ea) & sym_vars(eb)):
            self.widened += 1
            k = tuple(sorted((family(ea), family(eb))))
            self.fam[k] = self.fam.get(k, 0) + 1
            return True
        return False


def main():
    t0 = time.time()
    runs = EE.load_runs()
    base = build_assumptions(runs)
    A = WhatIf(base)
    U = EE.build_universe(runs, A, int(os.environ.get("MAX_CLIQUES", "16384")))
    if U is None:
        print("PROJECTION CAP HIT"); return 2
    print(f"pairs WIDENED to independent by the hypothesis: {A.widened}", flush=True)
    fams = sorted(A.fam.items(), key=lambda kv: -kv[1])
    print(f"they fall into {len(fams)} FAMILY-PAIRS (ordinals/hashes stripped) — "
          f"a declaration is written per family-pair, not per pair:", flush=True)
    for (fa, fb), n in fams[:20]:
        print(f"   {n:6d}  {fa.split('__')[-1][:56]}   x   {fb.split('__')[-1][:56]}",
              flush=True)
    json.dump({"widened": A.widened,
               "family_pairs": [[list(k), v] for k, v in fams]},
              open(os.path.join(HERE, "_whatif_families.json"), "w"), indent=1)
    print(f"universe built in {time.time()-t0:.0f}s", flush=True)
    known = EE.var_index(U["decls"])
    res = EE.census(U, U["cliques"], known, {}, {}, 20000, 0, use_forecl=True)
    json.dump(res, open(os.path.join(HERE, "_whatif_indep.json"), "w"), indent=1)
    print(f"DONE in {time.time()-t0:.0f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
