#!/usr/bin/env python3
"""C29 step 3 — the MINIMAL INFEASIBLE SUB-CONJUNCTIONS of the two blocking
cubes, over the corpus.

`_c25_mincond.py` asks "which member is never EVALUATED under the rest".  When
the rest is itself unmatched (A = 0) that question has no answer, and on these
two cubes A = 0 for almost every member.  The right question one level up is:
**which sub-conjunctions of the cube does the corpus never match at all**, and
which is the SMALLEST such?  Every minimal one is a co-realisation conflict the
corpus asserts; anything bigger is implied by it.

For each cube:
  * A(S) for every subset S up to width MUSW (default 4), reported as the
    MINIMAL infeasible subsets (no proper subset infeasible);
  * for each member d, the largest satisfiable sub-cube containing d;
  * for each minimal infeasible pair/triple, the per-literal breakdown:
    how many runs match each side, and whether the conflict is NEVER-EVALUATED
    (a foreclosure shape: the member is not merely the wrong value, it is not
    minted at all) or CONTRADICTED (both evaluated, never together).

Read-only, no corpus re-read.
"""
import itertools, json, os, pickle, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
S = pickle.load(open(os.environ.get("SCAN", os.path.join(HERE, "_c29_scan.pkl")), "rb"))
N, T, F, META = S["n"], S["T"], S["F"], S["meta"]
ALL = (1 << N) - 1
MUSW = int(os.environ.get("MUSW", "4"))
sys.path.insert(0, HERE)
from _c29_dispatch import ON, OFF, P, V, DV, PH                  # noqa: E402

tb = lambda e: T.get(e, 0)
fb = lambda e: F.get(e, 0)
eb = lambda e: tb(e) | fb(e)
mask = lambda lit: tb(lit[0]) if lit[1] else fb(lit[0])
pc = lambda x: x.bit_count()
short = lambda e: (e.replace("SYM_RESULT_ActiveRecord__", "")
                    .replace("SYM_LEN_SYM_RESULT_ActiveRecord__", "LEN ")
                    .replace("Relation_to_ary_notifications_", "ntf/")
                    .replace("Associations__CollectionProxy_records_", "cp/")
                    .replace("FinderMethods_", "fm/"))


def A(sub):
    m = ALL
    for lit in sub:
        m &= mask(lit)
        if not m:
            return 0, 0
    return pc(m), m


def mus(cube, width):
    """minimal infeasible subsets up to `width`"""
    found = []
    for r in range(1, width + 1):
        for sub in itertools.combinations(range(len(cube)), r):
            if any(set(f) <= set(sub) for f in found):
                continue
            a, _ = A([cube[i] for i in sub])
            if a == 0:
                found.append(sub)
    return found


def largest_sat(cube, keep):
    """largest subset of `cube` containing index `keep` with A > 0"""
    idx = [i for i in range(len(cube)) if i != keep]
    for drop in range(0, len(idx) + 1):
        best = None
        for out in itertools.combinations(idx, drop):
            sub = [i for i in range(len(cube)) if i == keep or i not in out]
            a, _ = A([cube[i] for i in sub])
            if a > 0 and (best is None or a > best[1]):
                best = (sub, a)
        if best:
            return best
    return ([keep], 0)


def explain(cube, sub):
    """for a minimal infeasible subset, say WHY: for each literal, the runs
    matching the OTHER literals, and what they do with this one."""
    out = []
    for i in sub:
        e, o = cube[i]
        rest = [cube[j] for j in sub if j != i]
        a, m = A(rest)
        if a == 0:
            out.append((i, e, o, 0, 0, 0, "n/a"))
            continue
        ev = pc(m & eb(e)); rl = pc(m & mask((e, o)))
        kind = ("NEVER-EVALUATED under the others" if ev == 0 else
                "EVALUATED but never with this outcome" if rl == 0 else "?")
        out.append((i, e, o, a, ev, rl, kind))
    return out


def run(name, cube):
    print(f"\n{'#'*78}\n### {name}   width {len(cube)}\n{'#'*78}")
    for i, (e, o) in enumerate(cube):
        print(f"  L{i:<2} want={'T' if o else 'F'}  {short(e)}")
    ms = mus(cube, MUSW)
    print(f"\n--- MINIMAL infeasible subsets up to width {MUSW}: {len(ms)}")
    for sub in ms:
        print(f"\n  MUS {tuple(sub)}   A = 0")
        for i in sub:
            e, o = cube[i]
            print(f"      L{i:<2} want={'T' if o else 'F'}  {short(e)}")
        for i, e, o, a, ev, rl, kind in explain(cube, sub):
            print(f"      -> drop L{i}: A(others)={a:6d}  of them evaluate L{i} "
                  f"in {ev:6d}  and realise it in {rl:6d}   [{kind}]")
    print(f"\n--- largest satisfiable sub-cube containing each member")
    for i in range(len(cube)):
        sub, a = largest_sat(cube, i)
        print(f"  L{i:<2} in a sat sub-cube of width {len(sub):2d} (A={a:6d}): "
              f"{sorted(sub)}   dropped {sorted(set(range(len(cube))) - set(sub))}")
    return ms


if __name__ == "__main__":
    print(f"corpus {N} runs; MUSW={MUSW}")
    a = run("ON  blocking cube (ON3 missing[0], conf ON)", ON)
    b = run("OFF blocking cube (OFF6 missing[0], conf OFF)", OFF)
    json.dump({"on_mus": [list(x) for x in a], "off_mus": [list(x) for x in b],
               "on": [[e, o] for e, o in ON], "off": [[e, o] for e, o in OFF]},
              open(os.path.join(HERE, "_c29_mus.json"), "w"), indent=1)
    print("\nC29-MUS-DONE")
