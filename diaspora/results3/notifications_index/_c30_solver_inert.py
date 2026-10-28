#!/usr/bin/env python3
"""C30 — IS THE 2026-09-14 `solver.py` NAME-CONTAINMENT CHANGE INERT ON THIS
ENDPOINT?

WHY THIS HAD TO BE ASKED. `src/concolic_engine/solver.py` was rewritten at
21:25 on 2026-09-14 by another agent's "name boundary containment" work, while
this endpoint's C29OFF1 coverage pass was checkpointed. The pass's own
checkpoint key noticed (`DISCARDING stale checkpoint ... input keys changed:
engine`) and restarted from zero, which is the system behaving correctly. But
it raises a question the restart does NOT answer: `C29ON1`'s `COMPLETE=True`
was computed under the OLD solver and any pass from now on runs under the NEW
one, so **are the two comparable at all?**

THE CHANGE, in behavioural terms. `solver.py` transports Z3 terms as PYTHON
SOURCE (`exec` a declaration, `eval` a constraint). A name that is not a legal
Python identifier — `len(X)` — used to make the declaration a SyntaxError
(swallowed per-line) and the constraint a NameError, so the variable was never
declared and the constraint silently vanished. The new code ENCODES such names
(`len(rows)` -> `Z3ID_len_0028rows_0029`), so they now declare and constrain
properly. That is a REAL semantic change wherever such a name reaches the
solver: it can turn a silently-dropped constraint into an enforced one, which
moves verdicts in the UNSAT direction.

WHY IT MAY NEVERTHELESS BE INERT HERE. The whole rewrite is guarded:

    subs = [(n, to_py_identifier(n)) for n in raw_names
            if not _is_plain_identifier(n) and not is_solver_term(n)]
    if not subs:
        return var_declarations, [list(e) for e in expr_lists], raw_names

If EVERY name this endpoint hands the solver is already a plain Python
identifier, `subs` is empty, the function returns its inputs unchanged, and
the three remaining hunks are identities too:

  * `raw_names = [d.split("=", 1)[0].strip()]` vs the old `d.split("=")[0]`
    — the same string unless a NAME contains `=`;
  * `eval_back.get(expr_str, expr_str)` — identity when `sane_evals is`
    elementwise equal to `eval_exprs`;
  * `local_env.get(to_py_identifier(name))` — identity when `name` is plain.

So the change is inert here IFF no name is non-plain and no name contains `=`.
That is a MEASUREMENT, and this is it. It reads the names the way the CHECKER
sees them — after `canonicalize_ordinals` (which is where `split_self_compare`
lives) and after `fix_len_names`, which is the step that turns the runtime's
`len(X)` into the solver-legal `SYM_LEN_X` — because a name that is non-plain
in a raw dump but plain by the time it reaches Z3 is not a counterexample.

A NON-ZERO count in `nonplain_after_fix` is a finding: it means C29ON1 and any
new pass are NOT comparable and the ON number must be recomputed.

  usage: DUMP_LIST=<snapshot> [SAMPLE=4000] [WORKERS=8] python3 -u _c30_solver_inert.py
Read-only.
"""
import collections
import json
import os
import random
import sys
import time
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from concolic_engine.assumptions import alias_map_for            # noqa: E402
from concolic_engine.solver import (_is_plain_identifier,        # noqa: E402
                                    is_solver_term, to_py_identifier)
import coverage_report as CR                                     # noqa: E402
from coverage_assumptions import ALIASES                         # noqa: E402

LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_c29_R1.txt"))
SAMPLE = int(os.environ.get("SAMPLE", "4000"))
WORKERS = int(os.environ.get("WORKERS", "8"))
SEED = int(os.environ.get("SEED", "20260914"))

FILES = [l.strip() for l in open(LIST) if l.strip()]
random.Random(SEED).shuffle(FILES)
FILES = FILES[:SAMPLE] if SAMPLE and SAMPLE < len(FILES) else FILES


def names_of(p):
    """Every variable name the checker would DECLARE for this run, in the
    checker's own spelling."""
    try:
        d = json.load(open(p))
    except Exception:
        return None
    alias_map_for([(e.get("result_name"), e.get("note"))
                   for e in d.get("events") or ()
                   if e.get("type") == "symbolic_call"], ALIASES)
    CR.canonicalize_ordinals(d)
    raw = set()
    for sv in d.get("symbolic_vars") or ():
        if isinstance(sv, dict) and sv.get("name"):
            raw.add(str(sv["name"]))
    # `fix_len_names` mutates the dump IN PLACE and is the step that turns the
    # runtime's `len(X)` into the solver-legal `SYM_LEN_X`, so it is applied
    # to the dump exactly as the pass applies it, and the names are re-read
    # afterwards. Reading them before AND after is what separates "non-plain
    # in the dump" (harmless, the pass renames it) from "non-plain at Z3"
    # (the thing that decides this question).
    CR.fix_len_names(d)
    fixed = set()
    for sv in d.get("symbolic_vars") or ():
        if isinstance(sv, dict) and sv.get("name"):
            fixed.add(str(sv["name"]))
    return raw, fixed


def work(chunk):
    raw, fixed = set(), set()
    for p in chunk:
        r = names_of(p)
        if r:
            raw |= r[0]
            fixed |= r[1]
    return raw, fixed


def main():
    t0 = time.time()
    chunks = [FILES[i::WORKERS * 4] for i in range(WORKERS * 4)]
    raw, fixed = set(), set()
    with Pool(WORKERS) as pool:
        for r, f in pool.imap_unordered(work, chunks):
            raw |= r
            fixed |= f
    print(f"sampled {len(FILES)} dumps in {time.time()-t0:.0f}s; "
          f"{len(raw)} distinct RAW variable names, "
          f"{len(fixed)} after fix_len_names", flush=True)

    def classify(names, label):
        nonplain = sorted(n for n in names if not _is_plain_identifier(n))
        terms = [n for n in nonplain if is_solver_term(n)]
        real = [n for n in nonplain if not is_solver_term(n)]
        witheq = sorted(n for n in names if "=" in n)
        print(f"\n--- {label}: {len(names)} distinct names")
        print(f"    non-plain-identifier : {len(nonplain)}")
        print(f"      of those, SOLVER TERMS (left alone by BOTH versions): {len(terms)}")
        for n in terms[:10]:
            print(f"         term  {n[:110]}")
        print(f"      of those, REAL NAMES that the new code ENCODES "
              f"and the old code DROPPED: {len(real)}")
        for n in real[:20]:
            print(f"         NAME  {n[:110]}  ->  {to_py_identifier(n)[:60]}")
        print(f"    names containing '=' : {len(witheq)}")
        for n in witheq[:5]:
            print(f"         {n[:110]}")
        return len(real), len(witheq)

    classify(raw, "RAW names, as the dump carries them")
    n_real, n_eq = classify(fixed, "AFTER fix_len_names — what Z3 actually receives")

    print()
    if n_real == 0 and n_eq == 0:
        print("VERDICT: the 2026-09-14 solver.py name-containment change is "
              "PROVABLY INERT on this endpoint.")
        print("  Every name reaching the solver is already a plain Python "
              "identifier, so `_contain_names` returns its inputs unchanged "
              "(`if not subs`), and the three remaining hunks are identities.")
        print("  C29ON1 (old solver) and any new pass ARE comparable.")
        print("SOLVER-INERT=True")
    else:
        print(f"VERDICT: NOT INERT — {n_real} real non-plain name(s), "
              f"{n_eq} name(s) containing '='.")
        print("  The old solver DROPPED constraints over these names "
              "(SyntaxError on the declaration, NameError on the constraint); "
              "the new one enforces them. Verdicts can move in the UNSAT "
              "direction, so C29ON1 must be RECOMPUTED before it is compared "
              "with any new pass.")
        print("SOLVER-INERT=False")
    print("C30-SOLVER-INERT-DONE")


if __name__ == "__main__":
    main()
