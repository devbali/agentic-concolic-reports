#!/usr/bin/env python3
"""C30 — for EVERY blocking gap set of a coverage summary, in one pass:

  (1) A(cube) and the LADDER — literals added in an order that keeps A > 0 for
      as long as possible, so the reader sees exactly where the corpus stops
      matching and how many runs were still standing one literal earlier;
  (2) per-literal DROP analysis — A(cube minus L), and of those runs how many
      EVALUATE L at all vs realise the demanded outcome. The distinction is the
      whole diagnosis: `evaluated 0` is the §40.5a shape (the variable is never
      MINTED, so the demand names something the run does not have), `evaluated
      but never with this outcome` is an ordinary value conflict;
  (3) the MINIMAL INFEASIBLE SUB-CONJUNCTIONS up to width MUSW;
  (4) for the literal the ladder dies on, the MATCHED-CONTEXT DIFFERENTIAL —
      take the runs that match the rest, split them by whether they evaluate
      that literal, and rank every other recorded literal by how much it
      separates the two sides. Those separators are the ENABLING GATES a build
      must write ALONGSIDE the cube (§40.5a: a statement-keyed alias is itself
      a condition);
  (5) the candidate BASES — runs matching the largest satisfiable sub-cube —
      with their tags and scenarios, which is what a build picks from.

This is `_c29_mus.py` + `_c29_enable.py` with the hard-coded ON/OFF cubes
removed: the cubes come from the summary, so the instrument is not specific to
one round's investigation.

  usage: GAPS=_c30_gaps_<stamp>.json SCAN=_c30_scan.pkl [MUSW=4] [ONLY=0,3]
         python3 -u _c30_analyze.py
Read-only.
"""
import collections
import itertools
import json
import os
import pickle
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAPS = os.environ.get("GAPS", os.path.join(HERE, "_c30_gaps.json"))
SCAN = os.environ.get("SCAN", os.path.join(HERE, "_c30_scan.pkl"))
MUSW = int(os.environ.get("MUSW", "4"))
OUT = os.environ.get("ANALYZE_OUT", os.path.join(HERE, "_c30_analyze.json"))
ONLY = os.environ.get("ONLY")
ONLY = {int(x) for x in ONLY.split(",")} if ONLY else None

S = pickle.load(open(SCAN, "rb"))
N, T, F, META, FILES = S["n"], S["T"], S["F"], S["meta"], S["files"]
ALL = (1 << N) - 1
EXPRS = sorted(set(T) | set(F))

tb = lambda e: T.get(e, 0)
fb = lambda e: F.get(e, 0)
eb = lambda e: tb(e) | fb(e)
pc = lambda x: x.bit_count()
mask = lambda lit: tb(lit[0]) if lit[1] else fb(lit[0])

_NOT = re.compile(r"^Not\((.*)\)$", re.S)


def lit(s):
    """`Not(E)` -> (E, False); `E` -> (E, True).

    The scan keys on the INNER path-condition expression and puts the run in
    T or F by the event's `taken` flag, so a node_constraint's `Not(...)`
    wrapper is exactly the F side. Anything that does not parse aborts rather
    than being silently treated as a positive literal.
    """
    s = s.strip()
    m = _NOT.match(s)
    if m:
        inner = m.group(1).strip()
        if inner.count("(") != inner.count(")"):
            raise SystemExit(f"unbalanced Not() payload: {s!r}")
        return (inner, False)
    if not (s.startswith("(") and s.endswith(")")):
        raise SystemExit(f"literal is neither Not(...) nor parenthesised: {s!r}")
    return (s, True)


short = lambda e: (e.replace("SYM_LEN_SYM_RESULT_ActiveRecord__", "LEN ")
                    .replace("SYM_RESULT_ActiveRecord__", "")
                    .replace("Relation_to_ary_notifications_", "ntf/")
                    .replace("Associations__CollectionProxy_records_", "cp/")
                    .replace("FinderMethods_", "fm/")
                    .replace("Relation_records_", "rel/"))


def A(sub):
    m = ALL
    for l in sub:
        m &= mask(l)
        if not m:
            return 0, 0
    return pc(m), m


def known(l):
    """Is this literal in the scan's universe at all? A literal the corpus has
    NEVER recorded on either side is not a value conflict — it is an expression
    no run has ever evaluated, and saying so is different from saying A = 0."""
    return eb(l[0]) != 0


def ladder(cube):
    """Add literals greedily, always choosing the one that keeps A largest.
    Reports where A first hits 0 and what was still standing before it."""
    rest = list(range(len(cube)))
    acc, rows = [], []
    while rest:
        best = None
        for i in rest:
            a, _ = A([cube[j] for j in acc] + [cube[i]])
            if best is None or a > best[0]:
                best = (a, i)
        a, i = best
        acc.append(i)
        rest.remove(i)
        rows.append((len(acc), a, i))
        if a == 0:
            # everything after this is 0 too; record the remainder unexplored
            break
    return rows, acc


def drops(cube):
    out = []
    for i, (e, o) in enumerate(cube):
        rest = [cube[j] for j in range(len(cube)) if j != i]
        a, m = A(rest)
        ev = pc(m & eb(e)) if a else 0
        rl = pc(m & mask((e, o))) if a else 0
        if not known((e, o)):
            kind = "EXPR NEVER RECORDED anywhere in the corpus"
        elif a == 0:
            kind = "rest itself unmatched"
        elif ev == 0:
            kind = "NEVER EVALUATED under the rest  (§40.5a shape: not minted)"
        elif rl == 0:
            kind = "evaluated, never with this outcome"
        else:
            kind = "satisfiable with the rest"
        out.append({"i": i, "expr": e, "want": o, "A_rest": a,
                    "evaluated": ev, "realised": rl, "kind": kind})
    return out


def mus(cube, width):
    found = []
    for r in range(1, width + 1):
        for sub in itertools.combinations(range(len(cube)), r):
            if any(set(f) <= set(sub) for f in found):
                continue
            a, _ = A([cube[i] for i in sub])
            if a == 0:
                found.append(sub)
    return found


def bits(m, cap=None):
    out = []
    b = m.to_bytes((N + 7) // 8, "little")
    for bi, byte in enumerate(b):
        if byte:
            for k in range(8):
                if byte & (1 << k):
                    out.append(bi * 8 + k)
                    if cap and len(out) >= cap:
                        return out
    return out


def differential(ctx, target):
    """Runs matching `ctx`, split by whether they EVALUATE `target`'s expr.
    Returns the literals that separate the two sides."""
    a, m = A(ctx)
    if not a:
        return None
    pos = m & eb(target[0])
    neg = m & ~eb(target[0])
    np_, nn = pc(pos), pc(neg)
    if not np_ or not nn:
        return {"ctx": a, "evaluating": np_, "not_evaluating": nn, "rows": []}
    rows = []
    for e in EXPRS:
        for o, bs in ((True, tb(e)), (False, fb(e))):
            x = pc(pos & bs) / np_
            y = pc(neg & bs) / nn
            if abs(x - y) > 0.35 and max(x, y) > 0.5:
                rows.append({"d": round(abs(x - y), 4), "evaluating_rate": round(x, 4),
                             "not_evaluating_rate": round(y, 4), "expr": e, "want": o})
    rows.sort(key=lambda r: -r["d"])
    return {"ctx": a, "evaluating": np_, "not_evaluating": nn, "rows": rows[:25]}


def largest_sat(cube):
    """Largest subset of the cube with A > 0, and its matching runs."""
    n = len(cube)
    for drop in range(0, n + 1):
        best = None
        for out in itertools.combinations(range(n), drop):
            keep = [i for i in range(n) if i not in out]
            a, m = A([cube[i] for i in keep])
            if a > 0 and (best is None or a > best[0]):
                best = (a, keep, m)
        if best:
            return best
    return (0, [], 0)


def run_one(gi, g):
    cube = [lit(s) for s in g["members"]]
    print(f"\n{'#'*78}\n### BLOCKING[{gi}]   width {len(cube)}\n{'#'*78}")
    for i, (e, o) in enumerate(cube):
        k = "" if known((e, o)) else "   <-- EXPR NEVER RECORDED"
        print(f"  L{i:<2} want={'T' if o else 'F'}  T={pc(tb(e)):6d} F={pc(fb(e)):6d}  {short(e)}{k}")

    a_full, _ = A(cube)
    print(f"\n  A(full cube) = {a_full}")

    rows, order = ladder(cube)
    print(f"\n--- LADDER (greedy, widest-first)")
    prev = N
    dies_on = None
    for w, a, i in rows:
        flag = ""
        if a == 0:
            flag = "   <-- DIES HERE"
            dies_on = i
        print(f"    +L{i:<2} -> width {w:2d}  A = {a:7d}{flag}      {short(cube[i][0])[:70]}")
        prev = a
    if dies_on is None:
        print("    the whole cube is matched by the corpus — this set is NOT a "
              "construction problem (re-check the summary)")

    d = drops(cube)
    print(f"\n--- PER-LITERAL DROP (A of the cube WITHOUT that literal)")
    for r in d:
        print(f"    L{r['i']:<2} A(rest)={r['A_rest']:7d}  evaluate={r['evaluated']:6d} "
              f" realise={r['realised']:6d}   [{r['kind']}]")

    ms = mus(cube, MUSW)
    print(f"\n--- MINIMAL INFEASIBLE SUB-CONJUNCTIONS up to width {MUSW}: {len(ms)}")
    for sub in ms:
        print(f"    MUS {tuple(sub)}:")
        for i in sub:
            print(f"        L{i:<2} want={'T' if cube[i][1] else 'F'}  {short(cube[i][0])[:78]}")

    # the differential is run for the literal the ladder dies on, and for every
    # literal whose drop row says NEVER EVALUATED — those are the §40.5a shape
    diffs = {}
    targets = {r["i"] for r in d if r["evaluated"] == 0 and r["A_rest"] > 0}
    if dies_on is not None:
        targets.add(dies_on)
    for i in sorted(targets):
        ctx = [cube[j] for j in range(len(cube)) if j != i]
        # if the rest is itself unmatched, widen: use the largest sat sub-cube
        # that excludes i, so the differential has a context to work in
        if A(ctx)[0] == 0:
            a_ls, keep, _ = largest_sat([c for j, c in enumerate(cube) if j != i])
            idx = [j for j in range(len(cube)) if j != i]
            ctx = [cube[idx[k]] for k in keep]
        r = differential(ctx, cube[i])
        diffs[i] = r
        print(f"\n--- MATCHED-CONTEXT DIFFERENTIAL for L{i}  ({short(cube[i][0])[:60]})")
        if r is None:
            print("    context itself unmatched even after widening — no differential")
            continue
        print(f"    context {r['ctx']} runs: evaluate L{i} in {r['evaluating']}, "
              f"do not in {r['not_evaluating']}")
        if not r["rows"]:
            print("    no separator above the 0.35 threshold "
                  "(one side empty, or nothing discriminates)")
        for x in r["rows"][:12]:
            print(f"      {'T' if x['want'] else 'F'} {x['evaluating_rate']*100:5.1f}% vs "
                  f"{x['not_evaluating_rate']*100:5.1f}%   {short(x['expr'])[:78]}")

    a_ls, keep, m_ls = largest_sat(cube)
    dropped = sorted(set(range(len(cube))) - set(keep))
    print(f"\n--- LARGEST SATISFIABLE SUB-CUBE: width {len(keep)} of {len(cube)}, "
          f"A = {a_ls}; dropped {dropped}")
    sample = bits(m_ls, 8)
    tags = collections.Counter(META[i][0] for i in bits(m_ls))
    scens = collections.Counter(META[i][1] for i in bits(m_ls))
    print(f"    candidate bases by tag:      {dict(tags.most_common(8))}")
    print(f"    candidate bases by scenario: {dict(scens.most_common(8))}")
    for i in sample:
        print(f"      e.g. {os.path.basename(FILES[i])}")

    return {"i": gi, "width": len(cube), "A_full": a_full,
            "ladder": [{"width": w, "A": a, "lit": i} for w, a, i in rows],
            "dies_on": dies_on, "drops": d,
            "mus": [list(x) for x in ms],
            "differentials": {str(k): v for k, v in diffs.items()},
            "largest_sat": {"width": len(keep), "A": a_ls, "keep": keep,
                            "dropped": dropped,
                            "tags": dict(tags), "scenarios": dict(scens),
                            "sample": [os.path.basename(FILES[i]) for i in sample]},
            "members": g["members"]}


def main():
    G = json.load(open(GAPS))
    blocking = G["blocking"]
    print(f"corpus {N} runs, {len(EXPRS)} exprs; gaps {GAPS}; MUSW={MUSW}")
    print(f"BLOCKING sets: {len(blocking)}")
    out = []
    for g in blocking:
        if ONLY is not None and g["i"] not in ONLY:
            continue
        out.append(run_one(g["i"], g))
    json.dump(out, open(OUT, "w"), indent=1)
    print(f"\nwrote {OUT}")
    print("C30-ANALYZE-DONE")


if __name__ == "__main__":
    main()
