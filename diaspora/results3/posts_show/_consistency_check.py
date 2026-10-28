#!/usr/bin/env python3
"""BRIEF STEP 3 — the two implementations, checked against each other on ONE
snapshot: the CHECKER's `missing[]` vs the EXACT ENUMERATOR's remaining set.

Run against a pass's own snapshot and its own summary JSON, so nothing is
compared across populations.

  SUMMARY=<pass summary.json> DUMP_LIST=<the pass's pruned snapshot> \
  PYTHONPATH=/home/dev/project/src python3 -u _consistency_check.py

Two layers:

A. THE UNIVERSE. The pass prints NODES, DEMAND_SETS, FORECLOSURES,
   TREE_MISSING. The enumerator recomputes each from the same load path. Any
   disagreement is a defect in one of the two, and is named, not averaged.

B. CONTAINMENT. Every non-untracked `missing[]` witness must be a member of
   the enumerator's REMAINING region on this snapshot, i.e.
     (i)  SATISFIABLE under the pass's own fixed base + the checker-scope pins;
     (ii) NOT OBSERVED — no run profile in the corpus agrees with the whole
          assignment (an expression a run recorded BOTH ways agrees with
          either outcome, which is the engine's own blocking-clause rule).
   A witness failing (i) is a demand for an impossible assignment; one failing
   (ii) is a demand for something the corpus already contains. Either is a bug.
   The reverse direction is NOT checkable and is not claimed: `missing[]` is
   capped at MAX_MISSING_PER_CLIQUE per set BY DESIGN, so the enumerator's
   remaining set is a strict superset whenever any set has more than the cap.
"""
import json, os, re, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
import _exact_enum_emit as EE                                   # noqa: E402
from coverage_assumptions import build as build_assumptions     # noqa: E402
from concolic_engine.coverage import _combo_constraint, _outcome_constraint  # noqa: E402
from concolic_engine.solver import check_satisfiability         # noqa: E402

SUMMARY = os.environ["SUMMARY"]
t0 = time.time()
runs = EE.load_runs()
A = build_assumptions(runs)
U = EE.build_universe(runs, A, int(os.environ.get("MAX_CLIQUES", "16384")))
assert U is not None, "PROJECTION CAP HIT"
print(f"universe built in {time.time()-t0:.0f}s", flush=True)

# ---------- A. universe identity -------------------------------------------
n_forecl = sum(len(v) for v in U["by_gate"].values())
n_forecl_pairs = sum(bin(m).count("1") for _g, lst in U["by_gate"].items() for _o, m in lst)
print(f"\nA. UNIVERSE (enumerator, this snapshot)")
print(f"   NODES={len(U['active'])}  DEMAND_SETS={len(U['cliques'])}  "
      f"FORECLOSURE_PAIRS={n_forecl_pairs}  TREE_MISSING={len(U['tree_missing'])}  "
      f"PINNED={len(U['pinned'])}  UNTRACKED={len(U['untracked'])}")

# ---------- B. containment --------------------------------------------------
S = json.load(open(SUMMARY))
missing = [m for m in S.get("missing", []) if not m.get("untracked")]
print(f"\nB. CONTAINMENT: {len(missing)} non-untracked missing[] witnesses "
      f"from {SUMMARY}")

# corpus profiles, for the OBSERVED test
profs = U["run_outcomes"]
by_expr = {}
for i, o in enumerate(profs):
    for e in o:
        by_expr.setdefault(e, set()).add(i)

_NOT = re.compile(r"^Not\((.*)\)$", re.S)

def conjuncts(nc):
    out = []
    for part in (nc or "").split(" AND "):
        part = part.strip()
        if not part:
            continue
        w = True
        m = _NOT.match(part)
        if m:
            part, w = m.group(1).strip(), False
        elif part.startswith("NOT "):
            part, w = part[4:].strip(), False
        out.append((part, w))
    return out

setmap = {}                       # expr -> the demand sets containing it
for ci, cl in enumerate(U["cliques"]):
    for e in cl:
        setmap.setdefault(e, []).append(ci)

unsat = []; observed = []; unknown_expr = []; ok = 0
for mi, m in enumerate(missing):
    cj = conjuncts(m.get("node_constraint"))
    bad = [e for e, _w in cj if e not in U["adj"]]
    if bad:
        unknown_expr.append((mi, bad[:2]))
        continue
    # (i) satisfiable under the checker's pin scope over the containing set
    grp = None
    for ci in setmap.get(cj[0][0], ()):
        s = set(U["cliques"][ci])
        if all(e in s for e, _w in cj):
            grp = U["cliques"][ci]
            break
    fixed = list(U["fixed_base"]) + [
        _outcome_constraint(e, U["pinned"][e]) for e in (grp or [e for e, _ in cj])
        if e in U["pinned"]]
    r = check_satisfiability(fixed + [_combo_constraint(sorted(cj))], U["decls"], EE.TIMEOUT)
    if not r.satisfiable:
        unsat.append((mi, m.get("node_constraint")[:200]))
        continue
    # (ii) not observed by any profile
    cand = None
    for e, _w in cj:
        s = by_expr.get(e, set())
        cand = set(s) if cand is None else (cand & s)
        if not cand:
            break
    hit = None
    for pi in (cand or ()):
        o = profs[pi]
        if all(w in o[e] for e, w in cj):
            hit = pi
            break
    if hit is not None:
        observed.append((mi, hit, m.get("node_constraint")[:200]))
        continue
    ok += 1
    if mi % 200 == 0:
        print(f"   [{mi}/{len(missing)}] ok so far={ok}", flush=True)

print(f"\nCONSISTENCY VERDICT ({time.time()-t0:.0f}s)")
print(f"   witnesses checked           : {len(missing)}")
print(f"   IN the enumerator's remaining: {ok}")
print(f"   UNSAT under the pin scope    : {len(unsat)}   <- bug if > 0")
print(f"   ALREADY OBSERVED in corpus   : {len(observed)}   <- bug if > 0")
print(f"   expression not in the universe: {len(unknown_expr)}   <- bug if > 0")
for mi, nc in unsat[:5]:
    print(f"     UNSAT#{mi}: {nc}")
for mi, pi, nc in observed[:5]:
    print(f"     OBSERVED#{mi} by profile {pi}: {nc}")
for mi, ex in unknown_expr[:5]:
    print(f"     UNKNOWN#{mi}: {ex}")
json.dump({"checked": len(missing), "in_remaining": ok, "unsat": unsat[:50],
           "observed": [(a, b, c) for a, b, c in observed[:50]],
           "unknown_expr": unknown_expr[:50],
           "nodes": len(U["active"]), "demand_sets": len(U["cliques"]),
           "forecl_pairs": n_forecl_pairs, "tree_missing": U["tree_missing"]},
          open(os.environ.get("OUT", os.path.join(HERE, "_consistency.json")), "w"), indent=1)
