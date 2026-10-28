#!/usr/bin/env python3
"""PRICE SEPARABLE EFFECTS as an inference over the demand sets.

Owner, 2026-09-11: within a demand set, members whose FOOTPRINTS are pairwise
DISJOINT need per-member coverage, not the cross product -- the same shape of
inference as foreclosure, and like foreclosure it is inferred FROM THE CORPUS
rather than declared.

SOUNDNESS (and its precondition). footprint(D) is measured by the matched-
context differential: the shapes whose presence differs between runs identical
on every other evaluated decision and differing only on D. A shape that needs
BOTH outcomes -- `A=x AND B=y => Z` -- therefore appears in BOTH footprints:
holding B at y, flipping A toggles Z, so Z is in footprint(A); holding A at x,
flipping B toggles Z, so Z is in footprint(B). Disjointness of the two
footprints REFUTES the existence of such a Z. That is the falsifier, and it is
why disjoint footprints license dropping the cross product.

Preconditions, both checked and neither assumed:
  * TREE COMPLETE -- every decision observed both ways, else a footprint is
    measured over an arm the corpus never walked. p5: tree_missing = 0.
  * MATCHED CONTEXTS EXIST -- a decision with none is UNDECIDABLE and is never
    called separable from anything (its footprint is unmeasured, not empty).

This is a WHAT-IF: it declares nothing and writes nothing to
coverage_assumptions.py. Identical flags to `_enum_p5_cost.log` otherwise, so
the two `EXACT:` lines are directly comparable.
"""
import json, os, sys, time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
import _exact_enum_emit as EE                                  # noqa: E402
from coverage_assumptions import build as build_assumptions    # noqa: E402

F = json.load(open(os.path.join(HERE, "_footprints.json")))
FP = {e: int(m) for e, m in zip(F["exprs"], F["footprint"])}
CTX = {e: c for e, c in zip(F["exprs"], F["contexts"])}
decided = {e for e in FP if CTX.get(e, 0) > 0}
print(f"footprints: {len(FP)} decisions, {len(decided)} DECIDED, "
      f"{len(FP)-len(decided)} UNDECIDABLE", flush=True)

stats = Counter()


class Separable:
    """The batch's AssumptionSet, widened by MEASURED separability only."""

    def __init__(self, base):
        self._b = base

    def __getattr__(self, n):
        return getattr(self._b, n)

    def are_independent(self, sa, sb, ea, eb):
        if self._b.are_independent(sa, sb, ea, eb):
            stats["already_declared"] += 1
            return True
        if ea not in decided or eb not in decided:
            stats["undecidable"] += 1
            return False
        if FP[ea] & FP[eb]:
            stats["overlapping"] += 1
            return False
        stats["separable"] += 1
        return True


def main():
    t0 = time.time()
    runs = EE.load_runs()
    A = Separable(build_assumptions(runs))
    U = EE.build_universe(runs, A, int(os.environ.get("MAX_CLIQUES", "16384")))
    if U is None:
        print("PROJECTION CAP HIT"); return 2
    print(f"universe built in {time.time()-t0:.0f}s", flush=True)
    print("pair verdicts while building the graph: " +
          ", ".join(f"{k}={v}" for k, v in stats.most_common()), flush=True)
    res = EE.census(U, U["cliques"], EE.var_index(U["decls"]), {}, {}, 20000, 0,
                    use_forecl=True)
    res["pair_verdicts"] = dict(stats)
    json.dump(res, open(os.path.join(HERE, "_whatif_separable.json"), "w"), indent=1)
    print(f"DONE in {time.time()-t0:.0f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
