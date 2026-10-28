#!/usr/bin/env python3
"""Exact combination census + REMAINING-CUBE EMITTER for posts_show.

PHASE-3 EXTENSION (2026-09-10, driver-level batching). Two changes on top of
`_exact_enum.py`, both batch-local, none in `src/`:

  (a) MEMORY. The ported census still builds the profile key as
      `frozenset((e, frozenset(o)) ...)`. `src/coverage.py` replaced that
      with `profile_key` (a blake2b digest) on 2026-09-10 because the churn,
      not the table, costs >10 GB on a 96 k-profile corpus. The census never
      got the fix; on p5 (31 054 profiles) it is the dominant term. Use
      `profile_key` when the engine exposes it.

  (b) EMIT. The census COUNTS `remaining = satisfiable - covered`. The
      demand round needs the remaining ASSIGNMENTS. Inside one leaf group
      the covered region is already decomposed into disjoint cubes by
      `subtract`; running the same subtraction against the leaf group's own
      prefix cube yields a disjoint cover of the REMAINING region instead.
      Each piece is a REMAINING CUBE: a partial assignment over the set's
      surviving members that (i) agrees with the leaf-group prefix, so it
      carries `g != o` for every foreclosing (g, o) on its path, and
      (ii) contains only assignments no run has observed. Sum of
      `cube_count` over the pieces == remaining, which is the built-in
      cross-check (`EMIT_CHECK`). Each piece is then handed to the SAME
      solver for a model, and written in the `missing[]` shape
      `_demand_root.py` already consumes (node_constraint / concrete_values).

usage: EMIT_OUT=<f.json> [EMIT_MAX_PER_SET=n] python3 -u _exact_enum_emit.py

--- original docstring follows ---


PORTED VERBATIM from notifications_index/_exact_enum.py (2026-09-10) for posts_show.
Three edits only: the optional loader helpers are hasattr-guarded, and the
two notifications-specific env blocks (ALIAS_OVERRIDE, PIN_UNREACHABLE) are
removed. The census maths, the foreclosure prune and --verify are untouched.

The engine's `missing` count is `demand sets x MAX_MISSING_PER_CLIQUE` — a set
count, never a gap (STATE_HANDOFF, correction 5). This tool answers the
question that number cannot: for the SAME universe the coverage pass builds
(same load path, same assumptions, same graph, same DEMAND SETS — since
2026-09-10 the maximal OBSERVED EVALUATION SETS projected by declared
independence, not the maximal cliques of a complete graph), how many
outcome assignments per set are SATISFIABLE, how many the corpus has
already observed, and how many REMAIN.

It is exact, and it is not a 2^w enumeration:

* SATISFIABLE — inside one demand set, expressions that share no Z3 variable are
  independent, so the set's satisfiable count is the PRODUCT over its
  variable-connected COMPONENTS of that component's satisfiable count. A
  component is small (it is the handful of decisions over one variable), so
  its count is enumerated exactly with the same solver the checker uses. The
  product is an exact bignum however wide the set is.

* OBSERVED — a run that evaluated the whole set covers a CUBE: the outcomes
  it fixed, free on any expression it recorded BOTH ways (exactly the engine's
  blocking clause, coverage.py step 6). The covered count is |union of cubes
  ∩ SAT|, computed by sum-of-disjoint-products over the distinct cubes, with
  each piece counted through the same component factorisation. `--cube-cap`
  bounds the disjointification work; a set that hits it is reported as a
  BOUND (covered >= x) and counted separately, never silently.

REMAINING = SATISFIABLE - COVERED.

usage: _exact_enum.py [--sample N] [--cube-cap N] [--json-out f] [--verify N]
   --verify N cross-checks N random demand sets' satisfiable count against a
   direct all-SAT enumeration (only sets narrow enough to enumerate).
"""
from __future__ import annotations

import json
import os
import random
import re
import sys
import time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.coverage import (CoverageChecker, _maximal_cliques,  # noqa: E402
                                      maximal_sets, _combo_constraint,
                                      _outcome_constraint, infer_foreclosures,
                                      restrict_foreclosures)
# DISCIPLINE §16e / §16f (2026-09-13). The census must NOT re-derive either
# relation: it imports the engine's own inference functions and applies them in
# the engine's own walk order (coverage.py step 6's witness loop). Guarded, so
# an older engine still loads this tool with LEAF_ENUM unavailable.
try:
    from concolic_engine.coverage import (  # noqa: E402
        profile_literal_masks, prefix_match_mask, conjunction_foreclosed,
        minimal_subconjunction)
    _HAVE_16EF = True
    # §16g (P35, 2026-09-15). Imported SEPARATELY and guarded on its own, so an
    # engine that has §16e/§16f but not §16g still loads this tool with §16g
    # simply unavailable rather than failing the whole import.
    try:
        from concolic_engine.coverage import wellfounded_drop_set  # noqa: E402
        _HAVE_16G = True
    except ImportError:                                      # pragma: no cover
        _HAVE_16G = False
except ImportError:                                          # pragma: no cover
    _HAVE_16EF = False
from concolic_engine.run import Run, PathSource  # noqa: E402
from concolic_engine.solver import check_satisfiability  # noqa: E402

import coverage_report as CR  # noqa: E402
import coverage_assumptions as CA  # noqa: E402
from coverage_assumptions import build as build_assumptions  # noqa: E402

TIMEOUT = int(os.environ.get("Z3_TIMEOUT_MS", "10000"))
# DEFAULT FLIPPED TO 0 (2026-09-11). This used to default to 1 and SKIP every
# leaf group with no observed cube, on the reading that "no run has ever walked
# this gate assignment" meant the group was unreachable and its assignments were
# a declared residue. people_stream REFUTED that: all 768 cubes it had labelled
# MULTI-GATE-FORECLOSED were reachable — 12/12 gate combinations realised by
# DIRECT CONSTRUCTION (fix the gates and the member outcomes from the
# enumerator's own SAT model, seed every ordinal backing each canonical) and
# driven to remaining = 0 with no declaration. The REACH_SPLIT statistic only
# ever answered "did the corpus produce this", never "can the program".
# RUNBOOK Phase 2 now requires construction before any residue claim, so the
# emitter must EMIT those groups, not hide them. Set EMIT_REACHABLE_ONLY=1
# only to reproduce the old (refuted) behaviour.
_REACH_ONLY = os.environ.get("EMIT_REACHABLE_ONLY", "0") != "0"

try:                                   # (a) the src/ memory fix, 2026-09-10
    from concolic_engine.coverage import profile_key as _pkey   # noqa: E402
    _PKEY = "profile_key (digest)"
except ImportError:                    # older engine — keep the ported form
    def _pkey(outcomes):
        return frozenset((e, frozenset(o)) for e, o in outcomes.items())
    _PKEY = "frozenset-of-pairs (no digest in this engine)"



def load_runs(sample=None):
    import glob
    _list = os.environ.get("DUMP_LIST")
    if _list:
        # A drive may be ADDING dumps to this directory while the census runs;
        # a fixed snapshot list is what makes the number reproducible.
        dumps = sorted(l.strip() for l in open(_list) if l.strip())
        dumps = [d if os.path.isabs(d) else os.path.join(HERE, d) for d in dumps]
        print(f"DUMP_LIST {_list}: {len(dumps)} dump files (fixed snapshot)",
              flush=True)
        sample = None
    else:
        dumps = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
        print(f"corpus POPULATION: {len(dumps)} dump files", flush=True)
    if sample:
        random.seed(int(os.environ.get("DUMP_SAMPLE_SEED", "20260901")))
        dumps = sorted(random.sample(dumps, sample))
        print(f"SAMPLED: {len(dumps)}", flush=True)
    runs = []
    for p in dumps:
        try:
            raw = json.load(open(p))
            if hasattr(CR, "canonicalize_ordinals"):
                CR.canonicalize_ordinals(raw)
            r = Run.from_dict(CR.fix_len_names(raw))
            if hasattr(CR, "apply_len_bounds"):
                r = CR.apply_len_bounds(r)
            if hasattr(CR, "share_run_objects"):
                r = CR.share_run_objects(r)
            runs.append(r)
        except Exception:
            pass
        del raw
    print(f"loaded {len(runs)} runs", flush=True)
    return runs


def build_universe(runs, assumptions, max_cliques):
    """coverage.py steps 1, 3, 4, 5 — the SAME universe the pass builds.

    2026-09-10: the demand universe is the MAXIMAL OBSERVED EVALUATION SETS,
    each projected by declared independence — not the maximal cliques of a
    complete graph. `cliques` in this tool now means "demand sets"; the name
    is kept so the census JSON stays readable against earlier runs.
    """
    ck = CoverageChecker(runs, assumptions=assumptions, max_cliques=max_cliques)
    runs = ck.runs                       # aliases already applied
    expr_order, expr_source = [], {}
    profiles = {}
    for run in runs:
        outcomes = {}
        for pc in run.path_conditions:
            if pc.expr not in expr_source:
                expr_order.append(pc.expr)
                expr_source[pc.expr] = (pc.source if isinstance(pc.source, PathSource) else None)
            outcomes.setdefault(pc.expr, set()).add(bool(pc.taken))
        if outcomes:
            profiles.setdefault(_pkey(outcomes), outcomes)
    run_outcomes = list(profiles.values())
    decls = ck._merged_declarations()
    fixed_base = list(assumptions.symbolic_constraints()) + ck._merged_bounds()

    parseable = []
    for e in expr_order:
        if check_satisfiability([f"Or({e}, Not({e}))"], decls, TIMEOUT).satisfiable:
            parseable.append(e)
    untracked, pinned, active = [], {}, []
    for e in parseable:
        src = expr_source[e]
        if assumptions.is_untracked(src, e):
            untracked.append(e)
            continue
        for side, outcome in (("taken", True), ("not_taken", False)):
            if assumptions.is_one_side_untracked(src, side, e):
                pinned[e] = not outcome
        active.append(e)
    adj = {e: set() for e in active}
    for i, ea in enumerate(active):
        for eb in active[i + 1:]:
            if assumptions.are_independent(expr_source[ea], expr_source[eb], ea, eb):
                continue
            adj[ea].add(eb); adj[eb].add(ea)
    aset = set(active)
    eval_sets = maximal_sets(frozenset(e for e in o if e in aset) for o in run_outcomes)
    projected = []
    for s in eval_sets:
        if all(len(adj[v] & s) == len(s) - 1 for v in s):
            projected.append(s)
            continue
        parts = _maximal_cliques(sorted(s), {v: adj[v] & s for v in s}, cap=max_cliques)
        if parts is None:
            return None
        projected.extend(frozenset(p) for p in parts)
    # ORDER MATTERS: the checker orders a demand set by FIRST-SEEN expression
    # order and the foreclosure prune is order-sensitive (a gate must precede
    # what it forecloses), so the census must use the identical order or it
    # counts a different set of edges. Route through the same key.
    _ord = {e: i for i, e in enumerate(expr_order)}
    cliques = [sorted(d, key=_ord.__getitem__) for d in maximal_sets(projected)]
    print(f"evaluation sets={len(eval_sets)} -> demand sets={len(cliques)}", flush=True)
    # FORECLOSURE (DISCIPLINE §16b, 2026-09-10): inferred from the corpus, the
    # same call the checker makes. FORECLOSURE=0 reproduces the set-level
    # (2026-09-10 morning) census on the identical snapshot, for the delta.
    forecl, bit, prof_masks = infer_foreclosures(active, run_outcomes)
    by_gate = {}
    for (g, o), fm in forecl.items():
        by_gate.setdefault(g, []).append((o, fm))
    print(f"foreclosures inferred: {sum(bin(m).count('1') for m in forecl.values())} "
          f"(gate,outcome)->decision pairs over {len(by_gate)} gates", flush=True)

    # TREE COMPLETENESS — the precondition of BOTH the combination claim and
    # the foreclosure inference (DISCIPLINE §16 / §16b). Same computation the
    # checker's `_unobserved_sides` does over the active expressions.
    seen = {}
    for o in run_outcomes:
        for e, v in o.items():
            seen.setdefault(e, set()).update(v)
    tree_missing = []
    for e in active:
        for outcome in (True, False):
            if outcome in seen.get(e, ()) or pinned.get(e, outcome) != outcome:
                continue
            if check_satisfiability(fixed_base + [_outcome_constraint(e, outcome)],
                                    decls, TIMEOUT).satisfiable:
                tree_missing.append(f"{e} :: {'taken' if outcome else 'not_taken'}")
    print(f"tree_missing={len(tree_missing)}  tree_complete={not tree_missing}",
          flush=True)
    for tm in tree_missing:
        print(f"   TREE-MISSING {tm}", flush=True)
    return dict(runs=runs, expr_order=expr_order, active=active, adj=adj,
                cliques=cliques, decls=decls, fixed_base=fixed_base,
                pinned=pinned, untracked=untracked, run_outcomes=run_outcomes,
                by_gate=by_gate, bit=bit, prof_masks=prof_masks,
                tree_missing=tree_missing)


_IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def var_index(decls):
    return {d.split("=", 1)[0].strip() for d in decls}


def vars_of(expr, known, cache):
    if expr not in cache:
        cache[expr] = frozenset(t for t in _IDENT.findall(expr) if t in known)
    return cache[expr]


def base_coupling(fixed_base, known, cache):
    """Variable groups that `fixed_base` JOINS (§85.6).

    `components` may only split a clique where the WHOLE conjunction splits.
    `fixed_base` is part of that conjunction, so any base constraint mentioning
    more than one declared variable ties those variables together and the
    per-component product is no longer exact. Returns the list of such variable
    sets, computed once per census.
    """
    out = []
    for c in fixed_base:
        vs = vars_of(str(c), known, cache)
        if len(vs) > 1:
            out.append(vs)
    return out


def components(clique, known, cache, coupling=()):
    """Partition a clique's expressions by SHARED Z3 VARIABLE (union-find),
    AND by any `fixed_base` constraint that spans several of those variables
    (§85.6 — without this the product over components over-counts, because it
    assumes the base factorises over the same partition and on this endpoint
    the RENDER_IDENTITY base constraint does not)."""
    parent = {e: e for e in clique}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]; x = parent[x]
        return x

    by_var = {}
    for e in clique:
        for v in vars_of(e, known, cache):
            by_var.setdefault(v, []).append(e)
    for es in by_var.values():
        for e in es[1:]:
            ra, rb = find(es[0]), find(e)
            if ra != rb:
                parent[ra] = rb
    # a base constraint over >1 declared variable makes those variables ONE group
    for vs in coupling:
        merged = [e for v in vs for e in by_var.get(v, ())]
        for e in merged[1:]:
            ra, rb = find(merged[0]), find(e)
            if ra != rb:
                parent[ra] = rb
    groups = {}
    for e in clique:
        groups.setdefault(find(e), []).append(e)
    return list(groups.values())


def comp_models(comp, fixed_base, decls, pinned, memo):
    """Every SATISFIABLE outcome tuple of one component (exact, by enumeration
    over the component's own 2^m — m is the number of decisions on one
    variable group, not the clique width)."""
    key = tuple(sorted(comp))
    if key in memo:
        return memo[key]
    m = len(key)
    if m > 20:
        raise RuntimeError(f"component of {m} expressions — not a variable group")
    out = []
    for bits in range(1 << m):
        combo = [(e, bool(bits >> i & 1)) for i, e in enumerate(key)]
        if any(e in pinned and o != pinned[e] for e, o in combo):
            continue
        r = check_satisfiability(list(fixed_base) + [_combo_constraint(combo)], decls, TIMEOUT)
        if r.satisfiable:
            out.append(dict(combo))
    memo[key] = (key, out)
    return memo[key]


def cube_count(comps_models, cube):
    """SAT assignments of a clique inside one cube (a partial assignment)."""
    n = 1
    for key, models in comps_models:
        c = sum(1 for mdl in models
                if all(cube[e] == mdl[e] for e in key if e in cube))
        if c == 0:
            return 0
        n *= c
    return n


def subtract(cubes, c, cap):
    """cubes \\ c as a list of disjoint cubes (standard cube subtraction)."""
    out = []
    for d in cubes:
        if any(e in d and d[e] != v for e, v in c.items()):
            out.append(d); continue           # disjoint already
        rest = d
        for e, v in c.items():
            if e in rest:
                continue
            piece = dict(rest); piece[e] = not v
            out.append(piece)
            rest = dict(rest); rest[e] = v
            if len(out) > cap:
                return None
        # `rest` is fully inside c — dropped
    return out


def leaves(group, local, bit, cap=200000, feasible=None):
    """The pruned tree's leaf GROUPS: (prefix cube over the gates, surviving
    member tuple). With no foreclosure this is exactly one group, (empty prefix, S) —
    the flat set-level demand. See coverage.py's module docstring, §16b."""
    gates = [g for g in group if (g, True) in local or (g, False) in local]
    out = []
    stack = [(0, (), 0)]
    while stack:
        i, assigned, dropped = stack.pop()
        while i < len(gates) and (dropped >> bit[gates[i]] & 1):
            i += 1
        if i == len(gates):
            surv = tuple(e for e in group if not (dropped >> bit[e] & 1))
            out.append((dict(assigned), surv))
            if len(out) > cap:
                return None
            continue
        g = gates[i]
        for o in (False, True):
            nxt = assigned + ((g, o),)
            # PRUNE an UNSAT prefix: a variable model determines every
            # expression, so a prefix with no model over the whole set has no
            # model over any surviving subset either — the group would carry
            # sat = 0 and covered = 0. Skipping it changes no total.
            if feasible is not None and not feasible(nxt):
                continue
            stack.append((i + 1, nxt, dropped | local.get((g, o), 0)))
    return out



def _emit_item(U, ci, clique, group, pre, surv, cube, n):
    """One REMAINING CUBE -> the `missing[]` entry `_demand_root.py` consumes.

    `cube` already contains the leaf group's prefix, i.e. an outcome for every
    foreclosing gate on the path to `surv` — that is the `g != o` the brief
    asks for, taken from the checker's OWN foreclosure relation rather than
    re-derived. Pins are applied at the CHECKER'S SCOPE (over the whole demand
    set, not the surviving members) — the people_stream lesson recorded in
    --verify — so the model is one the checker would accept.
    """
    combo = sorted(cube.items())
    fixed = list(U["fixed_base"]) + [
        _outcome_constraint(e, U["pinned"][e]) for e in group if e in U["pinned"]]
    r = check_satisfiability(fixed + [_combo_constraint(combo)], U["decls"], TIMEOUT)
    if not r.satisfiable or not r.model:
        return None
    nc = " AND ".join(e if v else f"Not({e})" for e, v in combo)
    return {"clique": ci, "width": len(clique), "surviving": len(surv),
            "gates": {e: v for e, v in pre.items()},
            "assignments": str(n),
            "node_constraint": nc,
            "concrete_values": r.model}


def main():
    args = sys.argv[1:]

    def opt(flag, default=None):
        return args[args.index(flag) + 1] if flag in args else default
    sample = int(opt("--sample", 0)) or None
    cube_cap = int(opt("--cube-cap", "20000"))
    verify = int(opt("--verify", "0"))
    t0 = time.time()
    runs = load_runs(sample)
    assumptions = build_assumptions(runs)
    U = build_universe(runs, assumptions, int(os.environ.get("MAX_CLIQUES", "16384")))
    if U is None:
        print("PROJECTION CAP HIT — an evaluation set has more maximal cliques "
              "than MAX_CLIQUES; universe not enumerable at this cap"); return 2
    cliques = U["cliques"]
    known = var_index(U["decls"])
    vcache, memo = {}, {}
    deg = sorted(((len(v), k) for k, v in U["adj"].items()), reverse=True)
    print("top-8 hubs by degree: " + "; ".join(
        f"{d} {e.split('__')[-1][:64]}" for d, e in deg[:8]), flush=True)
    print(f"nodes(active)={len(U['active'])} untracked={len(U['untracked'])} "
          f"pinned={len(U['pinned'])} cliques={len(cliques)} "
          f"(built in {time.time()-t0:.0f}s)", flush=True)

    emit = os.environ.get("EMIT_OUT") or None
    emit_max = int(os.environ.get("EMIT_MAX_PER_SET", "0"))
    emit_cap = int(os.environ.get("EMIT_CAP", "0"))
    print(f"profile key: {_PKEY}; emit={emit} max_per_set={emit_max} cap={emit_cap}",
          flush=True)
    modes = os.environ.get("FORECLOSURE", "1").split(",")
    results = {}
    for mode in modes:
        results[mode] = census(U, cliques, known, vcache, memo, cube_cap,
                               verify, use_forecl=(mode != "0"),
                               emit=(emit if mode != "0" else None),
                               emit_max_per_set=emit_max, emit_cap=emit_cap)
    if len(modes) > 1:
        print("\nDELTA (identical corpus snapshot, identical assumptions):")
        for mode in modes:
            r = results[mode]
            print(f"  FORECLOSURE={mode}: sets={r['cliques']} "
                  f"satisfiable={r['satisfiable']} covered={r['covered']} "
                  f"remaining={r['remaining']} wide(>=13)={r['wide']} "
                  f"wide_mass={r['wide_mass']}")
    if opt("--json-out"):
        json.dump(results, open(opt("--json-out"), "w"), indent=1)
    print("P23-ENUM-DONE", flush=True)
    return 0



# ===========================================================================
# DISCIPLINE §16e / §16f IN THE CENSUS — the LEAF ENUMERATION path
# ===========================================================================
# Opt-in (`CENSUS_LEAF_ENUM=1`); with it unset every line below is dead and the
# census is byte-for-byte the §86.1 one.
#
# WHY A DIFFERENT COUNTING METHOD IS NEEDED AT ALL. The census counts a demand
# set's satisfiable assignments as the PRODUCT over variable-connected
# components. Under §16b that is exact because a LEAF IS A FULL ASSIGNMENT over
# the leaf group's surviving members, so "assignments" and "leaves" are the same
# unit. §16f coarsens the leaf: a member foreclosed under a sub-conjunction of
# the literals fixed EARLIER IN THE WALK is not part of the leaf and contributes
# no literal, so one leaf now covers 2^k assignments and the product no longer
# counts leaves. The leaves are enumerated instead, with the same
# `cube_count`-based feasibility prune `leaves()` already uses, and the unit
# stays "leaves" — which under both flags off is exactly the old number. That
# equality is the reproduction check (`CENSUS_LEAF_ENUM=1` with both flags off
# must print §85.5's 27 359 / 22 212 / 5 147).
#
# NOTHING IS RE-DERIVED. `conjunction_foreclosed` and `minimal_subconjunction`
# are the engine's; the walk order is `restrict_foreclosures`' group order, the
# accumulator is the literals fixed so far, and a dropped member contributes no
# literal — coverage.py step 6's witness loop, verbatim in structure.
_LEAF_ENUM = os.environ.get("CENSUS_LEAF_ENUM", "0") == "1"
_LEAF_CAP = int(os.environ.get("CENSUS_LEAF_CAP", "400000"))
_SC_W = int(os.environ.get("FORECLOSURE_CONJUNCTION_WIDTH", "3"))
_SC_BUDGET = int(os.environ.get("FORECLOSURE_CONJUNCTION_BUDGET", "20000"))
# §16g WELL-FOUNDED DROPS — OPT-IN, DEFAULT OFF (P35, 2026-09-15).
# §16f draws its conditioning set C from the walk PREFIX; §16g draws it from
# the whole leaf cube, with a foundedness condition (every literal of C must
# belong to a KEPT member) resolved as a LEAST FIXED POINT, so the answer is
# unique and order-independent. The engine has implemented this since
# 2026-09-14 and it has never been enabled on this batch. Nothing here is
# re-derived: `wellfounded_drop_set` is the engine's own function, called with
# the engine's own `minimal_subconjunction` as its probe.
_WF_ON = os.environ.get("FORECLOSURE_WELLFOUNDED_DROPS", "0") == "1"


class _LeafCap(Exception):
    """This demand set produced more §16f leaves than CENSUS_LEAF_CAP."""


def leaf_enum_set(group, local, bit, lg, cm_by_lg, pre_surv, U, dmask,
                  prof_masks, masks16, conj_on, subconj_on, subconj_f,
                  pmask_f, gate_set, record_conj, record_subconj,
                  record_wf=None):
    """Every §16e/§16f LEAF of one demand set, plus the set's blocking cubes.

    Returns the leaves: a list of ``(cube, cm)``.

    * the cube is the leaf's kept
      literals (a dict), ``cm`` the component models of the leaf group it came
      from, so satisfiability inside the leaf is still counted exactly.
      Leaves are DEDUPLICATED PER SET, which is what the engine does by
      blocking the coarsened combo (§16f's documented containment case:
      dropping a gate can make a leaf a sub-cube of a sibling). Under both
      flags off the dedup is a no-op — two leaf groups disagree on a gate —
      and a leaf is a full assignment, so the count is the product census's.
    """
    takes, evals, universe = masks16
    out = []
    seen = set()
    for (pre, surv), cm in zip(pre_surv, cm_by_lg):
        gate_lits = tuple((g, pre[g]) for g in group if g in pre)
        drop = set()
        pin0 = set()
        if conj_on:
            fm, a_cnt = conjunction_foreclosed(
                gate_lits, [e for e in surv if e not in pre],
                takes, evals, universe, match_mask=pmask_f(gate_lits))
            record_conj(gate_lits, fm, a_cnt)
            drop.update(fm)
            # §16g PIN: this leaf group's §16e drop rests on every gate of the
            # prefix being IN the cube, so §16g may not take one out from under
            # it. Mirrors coverage.py's `wf_pin |= {e for e, _o in pfx}`.
            if fm:
                pin0 |= {e for e, _o in gate_lits}
        walk = [e for e in surv if e not in drop]

        stack = [(0, {}, (), frozenset(pin0))]
        while stack:
            i, cube, acc, pin = stack.pop()
            # skip the members this prefix forecloses; a dropped member
            # contributes NO literal, so `acc` is unchanged (coverage.py's
            # emission walk).
            while i < len(walk):
                e = walk[i]
                hit = subconj_f(acc, e) if subconj_on else None
                if hit is None:
                    break
                record_subconj(hit[0], e, hit[1])
                # §16g PIN: this §16f drop rests on the literals of C, so no
                # §16g drop may remove the member that supplied one of them.
                pin = pin | {x for x, _y in hit[0]}
                i += 1
            if i == len(walk):
                # ---- §16g WELL-FOUNDED DROPS (opt-in, default OFF).
                # The same relation as §16f with the conditioning set drawn
                # from the WHOLE surviving cube instead of the walk prefix,
                # resolved as the LEAST FIXED POINT of the founded-drop
                # operator. `pin` names the members whose literals already
                # justify an applied §16e/§16f drop on THIS leaf, which is
                # what keeps the combined drop set founded and makes the
                # nesting §16g subset-of §16f true BY CONSTRUCTION -- §16g
                # only ever ADDS drops, it never rescues a member §16f took.
                # Nothing is re-derived here: `wellfounded_drop_set` is the
                # engine's, probed with the engine's `minimal_subconjunction`.
                if _WF_ON and subconj_on and acc:
                    wf_hits = wellfounded_drop_set(
                        tuple(acc), subconj_f, pin,
                        matched=lambda red: bool(
                            prefix_match_mask(red, takes, universe)))
                    if wf_hits:
                        for _e, _o in acc:
                            got = wf_hits.get(_e)
                            if got is None:
                                continue
                            if record_wf is not None:
                                record_wf(got[0], _e, got[1])
                        cube = {k: v for k, v in cube.items()
                                if k not in wf_hits}
                        if not cube:
                            continue
                key = tuple(sorted(cube.items()))
                if key not in seen:
                    seen.add(key)
                    # the leaf group's gate prefix, RESTRICTED to the gates the
                    # leaf still carries (§16f may drop a gate; a dropped one is
                    # not part of the cube and must not be reported as fixed).
                    out.append((dict(cube), cm,
                                {g: v for g, v in pre.items() if g in cube}))
                    if len(out) > _LEAF_CAP:
                        raise _LeafCap()
                continue
            e = walk[i]
            vals = (pre[e],) if e in pre else (False, True)
            for o in vals:
                nxt = dict(cube)
                nxt[e] = o
                if cube_count(cm, nxt) > 0:
                    stack.append((i + 1, nxt, acc + ((e, o),), pin))
    return out


def census(U, cliques, known, vcache, memo, cube_cap, verify, use_forecl=True,
           emit=None, emit_max_per_set=0, emit_cap=0):
    t0 = time.time()
    # §85.6 fix. `components` may only split a clique where the WHOLE
    # conjunction splits, and `fixed_base` is part of that conjunction. Any
    # base constraint over more than one declared variable (on this endpoint,
    # RENDER_IDENTITY) ties those variables together; without this the product
    # over components counts assignments the conjunction refuses, which is
    # exactly the 1 757 "model-less" pieces of §83.1/§85. Computed once here,
    # in the function that owns both `components` call sites, so BOTH entry
    # points (this module's main() and _p26_emit_or.py, which calls census()
    # directly) get it.
    coupling = base_coupling(U["fixed_base"], known, vcache)
    print(f"base coupling: {len(coupling)} fixed_base constraint(s) span >1 "
          f"declared variable -> components merged accordingly "
          f"(distinct vars touched "
          f"{len(set().union(*coupling)) if coupling else 0})", flush=True)

    # ---- §16e / §16f, the ENGINE'S OWN inference, applied in ITS walk order.
    # Off unless CENSUS_LEAF_ENUM=1; then FORECLOSURE_CONJUNCTIONS / _SUB-
    # CONJUNCTIONS select the relation (both off = the reproduction control).
    _CONJ_ON = _SUBCONJ_ON = False
    _MASKS16 = ({}, {}, 0)
    _conj_classes, _subconj_classes = {}, {}
    _wf_classes = {}
    if _LEAF_ENUM:
        if not _HAVE_16EF:
            raise RuntimeError("CENSUS_LEAF_ENUM=1 but this engine has no §16e/§16f")
        _SUBCONJ_ON = os.environ.get("FORECLOSURE_SUBCONJUNCTIONS", "0") == "1"
        _CONJ_ON = (os.environ.get("FORECLOSURE_CONJUNCTIONS", "0") == "1"
                    or _SUBCONJ_ON)             # §16f IMPLIES §16e (§16f nesting)
        _MASKS16 = profile_literal_masks(U["active"], U["run_outcomes"])
        if _WF_ON and not _HAVE_16G:
            raise RuntimeError(
                "FORECLOSURE_WELLFOUNDED_DROPS=1 but this engine has no §16g "
                "(`wellfounded_drop_set` absent from concolic_engine.coverage)")
        print(f"LEAF ENUM ON: §16e={'ON' if _CONJ_ON else 'OFF'} "
              f"§16f={'ON' if _SUBCONJ_ON else 'OFF'} "
              f"W={_SC_W} budget={_SC_BUDGET} over {len(U['run_outcomes'])} profiles",
              flush=True)
    _takes16, _evals16, _universe16 = _MASKS16
    _pm_memo = {(): _universe16}

    def _pmask_f(prefix):
        m = _pm_memo.get(prefix)
        if m is None:
            m = _pmask_f(prefix[:-1]) & _takes16.get(prefix[-1], 0)
            _pm_memo[prefix] = m
        return m

    _sc_memo = {}

    def _subconj_f(acc, member):
        """The engine's `minimal_subconjunction`, memoized per (acc, member)."""
        key = (acc, member)
        if key in _sc_memo:
            return _sc_memo[key]
        got = minimal_subconjunction(acc, member, _takes16, _evals16,
                                     _universe16, width=_SC_W,
                                     budget=_SC_BUDGET)
        if len(_sc_memo) < 400000:
            _sc_memo[key] = got
        return got

    def _record_conj(prefix, members, a_cnt):
        if a_cnt == 0:
            if prefix:
                _conj_classes.setdefault("unmatched", set()).add(prefix)
            return
        if members:
            _conj_classes.setdefault("groups", set()).add(prefix)
            for d in members:
                _conj_classes.setdefault("pairs", set()).add((prefix, d))

    def _record_subconj(cond, member, a_cnt):
        _subconj_classes[(cond, member)] = a_cnt

    def _record_wf(cond, member, a_cnt):
        _wf_classes[(cond, member)] = a_cnt

    _ctl_memo = {}

    def _control_for(cond):
        """A POSITIVE CONTROL member for the conditioning set `cond`.

        The foreclosure claim for (C, d) is `B(C,d) = 0`, and its gate test is
        a CONSTRUCTION attempt: build a run realising C that evaluates d. A
        construction attempt fails SILENTLY, so a constructor that can build
        nothing would hand every class a free PASS (the X11 lesson). The
        control is therefore a member the corpus DEMONSTRABLY evaluates under
        the SAME C -- it shares the hard part (realising C) and differs only
        in the member, so if the machinery cannot build the control it cannot
        vouch for the claim either, and the class is NOT-TESTABLE.

        Returns `{"control_member": m, "control_B": popcount}` or
        `{"control_member": None, "control_B": 0}` when no member of the
        demand universe is ever evaluated under C -- which is itself worth
        recording, because then C admits no construction target at all.
        """
        if cond in _ctl_memo:
            return _ctl_memo[cond]
        amask = _universe16
        for lit in cond:
            amask &= _takes16.get(lit, 0)
        best, best_n = None, 0
        if amask:
            for m_, ev in _evals16.items():
                n = (amask & ev).bit_count()
                if n > best_n:
                    best, best_n = m_, n
        got = {"control_member": best, "control_B": best_n,
               "A_popcount": amask.bit_count()}
        _ctl_memo[cond] = got
        return got
    tot_sat = 0
    tot_cov = 0
    bounded = 0
    emitted = []           # the REMAINING CUBES, in `missing[]` shape
    _nsets_emitted = 0
    # `zero` counts region pieces with NO satisfiable model. A piece is empty
    # exactly when its assignment is unsatisfiable OR it puts a PINNED
    # one-sided expression on its untracked side (`comp_models` filters those,
    # so they never enter SAT and are never part of `remaining`). That is the
    # brief's skip-and-count: those cubes are DECLARED, not driven, and the
    # count is printed so a skipped demand can never look like a covered one.
    emit_stats = dict(cubes=0, mass=0, zero=0, capped_sets=0, region_bound=0,
                      mismatch=0, no_model=0, unreach_skipped=0,
                      pieces=0, piece_mass=0)
    # P23 (2026-09-12): STREAMED emission. The parent tool buffered every
    # emitted cube in `emitted` and wrote one JSON at the end, so a kill lost
    # the whole census and an uncapped emit was a memory risk. Here each cube
    # is appended to a JSONL as soon as it is built and flushed every 200, so
    # a kill loses at most the tail. `emitted` is kept ONLY as a counter.
    _fh = None
    if emit is not None:
        _fh = open(emit + ".jsonl", "w")
    # REACH_SPLIT — PORTED from notifications_index/_exact_enum.py (§13, its own
    # 2026-09-10 work), unchanged in substance. §16b infers foreclosure
    # PAIRWISE: (g,o) forecloses d only if no run with g=o evaluates d. That
    # misses DISJUNCTIVE reachability — if d is evaluated when g1=a OR g2=b,
    # runs with g1!=a still evaluate d via g2=b, so no pairwise foreclosure is
    # inferred and the cube {g1!=a, g2!=b, d=x} stays DEMANDED although no run
    # can ever be in a position to walk it. The leaf-group formulation already
    # carries the test: a group whose observed-cube set is EMPTY is one no run
    # has ever walked under that gate assignment.
    reach_sat = 0; unreach_sat = 0; reach_groups = 0; unreach_groups = 0
    unreach_ex = []; reach_rem_per_set = []
    widths = Counter()
    per = []
    bit, prof_masks = U["bit"], U["prof_masks"]
    # per-profile TRUE / BOTH-WAYS bitmaps, built ONCE: the §16f blocking side
    # walks a profile's own assignment and must tell a single-outcome member
    # from one recorded both ways (the latter contributes no literal, exactly
    # as a both-sided gate does not join §16e's P).
    _pm_true, _pm_both = [], []
    if _LEAF_ENUM:
        for _o in U["run_outcomes"]:
            _tm = _bm = 0
            for _e, _os in _o.items():
                _j = bit.get(_e)
                if _j is None:
                    continue
                if len(_os) == 2:
                    _bm |= 1 << _j
                elif True in _os:
                    _tm |= 1 << _j
            _pm_true.append(_tm)
            _pm_both.append(_bm)
    by_gate = U["by_gate"] if use_forecl else {}
    print(f"\n=== CENSUS foreclosure={'ON' if use_forecl else 'OFF (set-level)'}",
          flush=True)
    tot_forecl = 0
    tot_leafgroups = 0
    gate_counts = Counter()
    # P23 — NARROW SETS FIRST. `build_universe` hands the demand sets widest
    # first, and a per-set emit cap under a global cap then spends the whole
    # budget on the widest sets — the ones whose remaining assignment mass is
    # astronomical and which no round can close — while the narrow sets, which
    # are the ones a round CAN take clean, get nothing. Ascending width changes
    # no total (the census sums over the same sets) and makes the streamed
    # batch usable before the run finishes. `ci` stays the ORIGINAL index, so
    # a cube's set identity is comparable across runs.
    _order = sorted(enumerate(cliques), key=lambda t: len(t[1]))
    print(f"census order: ascending width "
          f"({len(_order[0][1])} .. {len(_order[-1][1])})", flush=True)
    for _pos, (ci, clique) in enumerate(_order):
        group, local, _ign = restrict_foreclosures(clique, by_gate, bit)
        local_gates = [g for g in group
                       if (g, True) in local or (g, False) in local]
        gate_set = set(local_gates)
        tot_forecl += sum(bin(m).count("1") for m in local.values())
        for (g, o), m in local.items():
            gate_counts[f"{g} :: {'taken' if o else 'not_taken'}"] += bin(m).count("1")
        widths[len(clique)] += 1
        cm_full = [comp_models(c, U["fixed_base"], U["decls"], U["pinned"], memo)
                   for c in components(list(group), known, vcache, coupling)]
        lg = leaves(group, local, bit,
                    feasible=lambda a: cube_count(cm_full, dict(a)) > 0)
        if lg is None:          # leaf-group cap: report as a BOUND, never hide
            bounded += 1
            per.append(dict(ci=ci, width=len(clique), comps=0, sat=0, covered=0,
                            bound=True, cubes=0, leaf_groups=-1))
            continue
        tot_leafgroups += len(lg)
        dmask = 0
        for e in group:
            dmask |= 1 << bit[e]
        # profiles indexed by WHICH members of this set they evaluated: a leaf
        # group is covered only by runs whose evaluated members are EXACTLY
        # its surviving ones (invariant 2, a closed prefix).
        bymask = {}
        for pi, pm in enumerate(prof_masks):
            k = pm & dmask
            if k:
                bymask.setdefault(k, []).append(pi)
        sat = 0
        covered = 0
        is_bound = False
        ncubes = 0
        set_emitted = 0
        set_remaining_seen = 0
        set_skipped = 0
        set_pieces = 0
        if _LEAF_ENUM:
            # ---- §16e/§16f LEAF ENUMERATION (opt-in) ----------------------
            # The unit is the LEAF, which under both flags off is the full
            # assignment the product census counts — that identity is the
            # reproduction check. `cm` per leaf group is reused so
            # satisfiability inside a leaf is still exact.
            cms = []
            pre_surv = []
            for pre, surv in lg:
                pre_surv.append((pre, surv))
                cms.append([comp_models(c, U["fixed_base"], U["decls"],
                                        U["pinned"], memo)
                            for c in components(list(surv), known, vcache,
                                                coupling)])
            # BLOCKING CUBES, per SET (the engine builds `blocks` once per
            # demand set, step 6). A profile qualifies for a leaf group whose
            # SURVIVING members are exactly the ones it evaluated (§16b's
            # closed prefix, invariant 2) and which agrees with the prefix;
            # with §16f on, a profile whose unevaluated members are all
            # foreclosed under the literals it DOES fix qualifies too — the
            # "both sides move" rule, tested only on UNEVALUATED members
            # exactly as coverage.py does.
            blocking = []
            bseen = set()
            for pre, surv in pre_surv:
                smask = 0
                for e in surv:
                    smask |= 1 << bit[e]
                for pi in bymask.get(smask, ()):
                    outcomes = U["run_outcomes"][pi]
                    cube = {}
                    bad = False
                    for e in surv:
                        o = outcomes[e]
                        if len(o) == 1:
                            v = next(iter(o))
                            if e in pre and pre[e] != v:
                                bad = True
                                break
                            cube[e] = v
                    if bad:
                        continue
                    k = tuple(sorted(cube.items()))
                    if k not in bseen:
                        bseen.add(k)
                        blocking.append(cube)
            if _SUBCONJ_ON:
                # PARTIAL runs that §16f now lets block — "both sides move"
                # (§16f). The walk runs over the profile's OWN assignment, in
                # group order; a member recorded both ways contributes no
                # literal; only UNEVALUATED members are tested, which is not a
                # shortcut but a theorem (every literal of `acc` is one this
                # profile matches, so a member it evaluates has B >= 1).
                # Deduplicated by the profile's SHAPE over this set —
                # (evaluated, true, both-ways) bitmaps — so the walk runs once
                # per distinct shape, not once per profile.
                seen_shapes = set()
                for pi, pm in enumerate(prof_masks):
                    k0 = pm & dmask
                    if not k0 or k0 == dmask:
                        continue
                    tm = _pm_true[pi] & dmask
                    bm = _pm_both[pi] & dmask
                    sk = (k0, tm, bm)
                    if sk in seen_shapes:
                        continue
                    seen_shapes.add(sk)
                    dropb = 0
                    for g in local_gates:
                        gb = 1 << bit[g]
                        if not (k0 & gb):
                            continue
                        if bm & gb:
                            dropb |= (local.get((g, True), 0)
                                      & local.get((g, False), 0))
                        else:
                            dropb |= local.get((g, bool(tm & gb)), 0)
                    if dmask & ~k0 & ~dropb == 0:
                        continue                 # already a closed prefix
                    if _CONJ_ON:
                        pt = tuple((g, bool(tm & (1 << bit[g])))
                                   for g in local_gates
                                   if (k0 >> bit[g] & 1)
                                   and not (dropb >> bit[g] & 1)
                                   and not (bm >> bit[g] & 1))
                        survb = [e for e in group
                                 if not (dropb >> bit[e] & 1)
                                 and e not in gate_set]
                        fmb, ab = conjunction_foreclosed(
                            pt, survb, _takes16, _evals16, _universe16,
                            match_mask=_pmask_f(pt))
                        _record_conj(pt, fmb, ab)
                        for d in fmb:
                            dropb |= 1 << bit[d]
                    if dmask & ~k0 & ~dropb == 0:
                        continue
                    accb = ()
                    cube = {}
                    ok = True
                    for e in group:
                        eb = 1 << bit[e]
                        if dropb & eb:
                            continue
                        if not (k0 & eb):
                            hit = _subconj_f(accb, e)
                            if hit is None:
                                ok = False
                                break
                            _record_subconj(hit[0], e, hit[1])
                            continue
                        if bm & eb:
                            continue             # both ways: no literal
                        v = bool(tm & eb)
                        cube[e] = v
                        accb = accb + ((e, v),)
                    if not ok or not cube:
                        continue
                    kk = tuple(sorted(cube.items()))
                    if kk not in bseen:
                        bseen.add(kk)
                        blocking.append(cube)
            ncubes = len(blocking)
            try:
                lvs = leaf_enum_set(
                    group, local, bit, lg, cms, pre_surv, U, dmask, prof_masks,
                    _MASKS16, _CONJ_ON, _SUBCONJ_ON, _subconj_f, _pmask_f,
                    gate_set, _record_conj, _record_subconj,
                    record_wf=_record_wf)
            except _LeafCap:
                is_bound = True
                lvs = []
            sat = len(lvs)
            for cube, cm, lpre in lvs:
                n = cube_count(cm, cube)
                # a leaf is COVERED iff EVERY satisfiable assignment inside it
                # is blocked — the engine emits a witness as soon as one is
                # not (Z3 answers `fixed AND NOT blocks`), so a partially
                # covered leaf is MISSING.
                covn = 0
                dis = []
                for b in blocking:
                    if any(e in cube and cube[e] != v for e, v in b.items()):
                        continue
                    m = dict(cube)
                    m.update(b)
                    pieces = [m]
                    for prev in dis:
                        nxt = []
                        for pc in pieces:
                            sres = subtract([pc], prev, cube_cap)
                            if sres is None:
                                nxt = None
                                break
                            nxt.extend(sres)
                        if nxt is None:
                            pieces = None
                            break
                        pieces = nxt
                    if pieces is None:
                        is_bound = True
                        break
                    for pc in pieces:
                        covn += cube_count(cm, pc)
                    dis.append(m)
                if is_bound:
                    break
                if covn >= n:
                    covered += 1
                    continue
                # REMAINING leaf -> one emitted cube, taken from the leaf's
                # UNCOVERED region so the model handed to the driver is one no
                # run has walked (the same `subtract` the region emitter uses).
                set_remaining_seen += 1
                set_pieces += 1
                emit_stats["pieces"] += 1
                emit_stats["piece_mass"] += n - covn
                if emit is None:
                    continue
                if emit_max_per_set and set_emitted >= emit_max_per_set:
                    continue
                if emit_cap and emit_stats["cubes"] >= emit_cap:
                    continue
                region = [dict(cube)]
                for b in dis:
                    nxt = []
                    for r_ in region:
                        sres = subtract([r_], b, cube_cap)
                        if sres is None:
                            nxt = None
                            break
                        nxt.extend(sres)
                    if nxt is None:
                        region = None
                        break
                    region = nxt
                if region is None:
                    emit_stats["region_bound"] += 1
                    continue
                item = None
                for r_ in region:
                    nr = cube_count(cm, r_)
                    if nr == 0:
                        continue
                    item = _emit_item(U, ci, clique, group, lpre,
                                      sorted(cube), r_, nr)
                    if item is not None:
                        break
                if item is None:
                    emit_stats["no_model"] += 1
                    continue
                item["leaf"] = {e: v for e, v in sorted(cube.items())}
                _fh.write(json.dumps(item) + "\n")
                emitted.append(1)
                set_emitted += 1
                emit_stats["cubes"] += 1
                emit_stats["mass"] += n - covn
                if emit_stats["cubes"] % 200 == 0:
                    _fh.flush()
        else:
            for pre, surv in lg:
                comps = components(list(surv), known, vcache, coupling)
                cm = [comp_models(c, U["fixed_base"], U["decls"], U["pinned"], memo)
                      for c in comps]
                # demanded leaves of this group = models over `surv` agreeing with
                # the gate prefix `pre`
                sat += cube_count(cm, pre)
                # covered: runs whose evaluated members of the set are EXACTLY the
                # surviving ones (invariant 2 — a closed prefix) and which agree
                # with the prefix. Their cube is over `surv`.
                smask = 0
                for e in surv:
                    smask |= 1 << bit[e]
                cubes = set()
                for pi in bymask.get(smask, ()):
                    outcomes = U["run_outcomes"][pi]
                    cube = {}
                    bad = False
                    for e in surv:
                        o = outcomes[e]
                        if len(o) == 1:
                            v = next(iter(o))
                            if e in pre and pre[e] != v:
                                bad = True
                                break
                            cube[e] = v
                    if bad:
                        continue
                    cubes.add(tuple(sorted(cube.items())))
                ncubes += len(cubes)
                _sat_lg = cube_count(cm, pre)
                if not cubes:
                    unreach_sat += _sat_lg
                    unreach_groups += 1
                    if _sat_lg and len(unreach_ex) < 4000:
                        unreach_ex.append((_sat_lg, ci, len(clique), len(surv),
                                           tuple(sorted(pre.items()))))
                else:
                    reach_sat += _sat_lg
                    reach_groups += 1
                disjoint = []
                for cube in sorted(cubes, key=len):
                    d = dict(cube)
                    d.update(pre)            # the leaf group's own restriction
                    pieces = [d]
                    for prev in disjoint:
                        nxt = []
                        for p in pieces:
                            sres = subtract([p], prev, cube_cap)
                            if sres is None:
                                nxt = None; break
                            nxt.extend(sres)
                        if nxt is None:
                            is_bound = True; break
                        pieces = nxt
                        if len(pieces) > cube_cap:
                            is_bound = True; break
                    if is_bound:
                        break
                    for p in pieces:
                        covered += cube_count(cm, p)
                    disjoint.append(d)
                if is_bound:
                    break
                # ---- (b) THE REMAINING REGION of this leaf group ----------------
                # `disjoint` holds the OBSERVED cubes (each already restricted to
                # the prefix). Subtracting them from the prefix cube leaves a
                # DISJOINT COVER OF WHAT NO RUN HAS OBSERVED. Every piece with a
                # non-zero model count is a demand target; the pieces' counts sum
                # to sat - covered, which is checked below per set.
                # EMIT_REACHABLE_ONLY (default OFF since 2026-09-11): a leaf group with NO observed
                # cube is one no run has ever walked under this gate assignment
                # (the REACH_SPLIT test above). Its assignments are demanded by the
                # declared model and unreachable in the corpus, so a seed built for
                # one has no base to root on and cannot be honoured. They are
                # COUNTED (unreach_sat) and not driven — the same skip-and-count
                # discipline the pins get, on a different ground.
                if emit is not None and _REACH_ONLY and not cubes:
                    emit_stats["unreach_skipped"] += 1
                    set_skipped += 1
                elif emit is not None:
                    region = [dict(pre)]
                    for d in disjoint:
                        nxt = []
                        for r in region:
                            sres = subtract([r], d, cube_cap)
                            if sres is None:
                                nxt = None
                                break
                            nxt.extend(sres)
                        if nxt is None or len(nxt) > cube_cap:
                            region = None
                            break
                        region = nxt
                    if region is None:
                        emit_stats["region_bound"] += 1
                    else:
                        for r in region:
                            n = cube_count(cm, r)
                            if n == 0:
                                emit_stats["zero"] += 1
                                continue
                            set_remaining_seen += n
                            # PIECE COUNT IS UNCAPPED — the cap governs how many
                            # cubes are BUILT (each costs a Z3 model), never how
                            # many are counted, so the reported per-set remaining
                            # distribution is exact even on a capped run.
                            set_pieces += 1
                            emit_stats["pieces"] += 1
                            emit_stats["piece_mass"] += n
                            if emit_max_per_set and set_emitted >= emit_max_per_set:
                                continue
                            if emit_cap and emit_stats["cubes"] >= emit_cap:
                                continue
                            item = _emit_item(U, ci, clique, group, pre, surv, r, n)
                            if item is None:
                                emit_stats["no_model"] += 1
                                continue
                            _fh.write(json.dumps(item) + "\n")
                            emitted.append(1)
                            set_emitted += 1
                            emit_stats["cubes"] += 1
                            emit_stats["mass"] += n
                            if emit_stats["cubes"] % 200 == 0:
                                _fh.flush()
        if is_bound:
            bounded += 1
        # The region-mass cross-check is exact only when EVERY leaf group of
        # this set contributed; a set with skipped (unreachable) groups is
        # excluded from the check rather than reported as a mismatch.
        if emit is not None and not is_bound and not set_skipped:
            if set_remaining_seen != sat - covered:
                emit_stats["mismatch"] += 1
                print(f"  EMIT-MISMATCH set#{ci}: region mass {set_remaining_seen}"
                      f" != sat-covered {sat - covered}", flush=True)
            if emit_max_per_set and set_emitted >= emit_max_per_set:
                emit_stats["capped_sets"] += 1
        tot_sat += sat
        tot_cov += covered
        per.append(dict(ci=ci, width=len(clique), comps=len(lg), sat=sat,
                        covered=covered, bound=is_bound, cubes=ncubes,
                        leaf_groups=len(lg), region_pieces=set_pieces,
                        emitted=set_emitted,
                        forecl=sum(bin(m).count("1") for m in local.values())))
        if _fh is not None and _pos % 25 == 0:
            _fh.flush()
            print(f"  CKPT {_pos}/{len(cliques)} set#{ci} w={len(clique)} "
                  f"pieces={emit_stats['pieces']}"
                  f" emitted={emit_stats['cubes']} sets_emitted={_nsets_emitted}"
                  f" rem_so_far={tot_sat-tot_cov}"
                  f" wall={time.time()-t0:.0f}s", flush=True)
        if set_emitted:
            _nsets_emitted += 1
        if _pos % 200 == 0:
            print(f"  [{_pos}/{len(cliques)}] set#{ci} sat={sat} covered={covered} "
                  f"width={len(clique)} leaf_groups={len(lg)}", flush=True)

    if _LEAF_ENUM:
        print(f"\n  §16e: pairs={len(_conj_classes.get('pairs', ()))} "
              f"groups={len(_conj_classes.get('groups', ()))} "
              f"unmatched={len(_conj_classes.get('unmatched', ()))}", flush=True)
        _sc_conds = {c for c, _d in _subconj_classes}
        print(f"  §16f: (C,d) classes={len(_subconj_classes)} "
              f"conditioning sets={len(_sc_conds)} "
              f"widths={sorted({len(c) for c in _sc_conds})}", flush=True)
        _scp = os.environ.get("SUBCONJ_CLASSES_OUT")
        if _scp:
            json.dump([dict({"conditioning": [[e, bool(o)] for e, o in c],
                             "member": d, "A": a},
                            **_control_for(c))
                       for (c, d), a in sorted(_subconj_classes.items(),
                                               key=lambda kv: (-kv[1], kv[0][1]))],
                      open(_scp, "w"), indent=1)
            print(f"  wrote §16f classes -> {_scp}", flush=True)
        if _WF_ON:
            _wf_conds = {c for c, _d in _wf_classes}
            print(f"  §16g: (C,d) classes={len(_wf_classes)} "
                  f"conditioning sets={len(_wf_conds)} "
                  f"widths={sorted({len(c) for c in _wf_conds})}", flush=True)
            _wfp = os.environ.get("WF_CLASSES_OUT")
            if _wfp:
                json.dump([dict({"conditioning": [[e, bool(o)] for e, o in c],
                                 "member": d, "A": a_},
                                **_control_for(c))
                           for (c, d), a_ in sorted(_wf_classes.items(),
                                                    key=lambda kv: (-kv[1], kv[0][1]))],
                          open(_wfp, "w"), indent=1)
                print(f"  wrote §16g classes -> {_wfp}", flush=True)

    wide = [p for p in per if p["width"] >= 13]
    if verify:
        random.seed(1)
        idx = [i for i, p in enumerate(per) if p["width"] <= 12]
        for i in random.sample(idx, min(verify, len(idx))):
            clique = cliques[i]
            # INDEPENDENT recomputation: derive every LEAF by brute force over
            # the set's 2^w total assignments (each one walked through the
            # foreclosure prune), dedup, and all-SAT each leaf directly. With
            # foreclosure off this is the old whole-set all-SAT, unchanged.
            group, local, _ig = restrict_foreclosures(clique, by_gate, bit)
            _pinned_fixed = list(U["fixed_base"]) + [
                _outcome_constraint(e, U["pinned"][e])
                for e in group if e in U["pinned"]]
            seen, n = set(), 0
            for bits in range(1 << len(group)):
                assign = {e: bool(bits >> j & 1) for j, e in enumerate(group)}
                dropped, leaf = 0, []
                for e in group:
                    if dropped >> bit[e] & 1:
                        continue
                    o = assign[e]
                    leaf.append((e, o))
                    dropped |= local.get((e, o), 0)
                key = tuple(leaf)
                if key in seen:
                    continue
                seen.add(key)
                # PIN SCOPE (2026-09-10, people_stream): the checker pins a
                # `OneSideUntracked` expression over the WHOLE demand set
                # (coverage.py: `for expr in group: if expr in pinned: fixed
                # .append(...)`), including a member the prefix foreclosed
                # away. A leaf-local pin filter therefore counts leaves the
                # checker never demands — a width-2 set {guid=='' , guid!=''}
                # with `guid!=''` pinned False scored allsat=2 against the
                # checker's 1. Use the checker's scope so this stays an
                # INDEPENDENT recomputation of the SAME quantity.
                if check_satisfiability(_pinned_fixed + [_combo_constraint(leaf)],
                                        U["decls"], TIMEOUT).satisfiable:
                    n += 1
            ok = (n == per[i]["sat"])
            print(f"  VERIFY clique#{i} width={len(clique)}: leaves={len(seen)} "
                  f"allsat={n} factorised={per[i]['sat']} "
                  f"{'OK' if ok else 'MISMATCH'}", flush=True)

    print(f"\nEXACT: nodes={len(U['active'])} cliques={len(cliques)} "
          f"satisfiable={tot_sat} covered={tot_cov} remaining={tot_sat - tot_cov} "
          f"bounded_cliques={bounded} wall={time.time()-t0:.0f}s")
    print(f"FORECLOSURE: applied={tot_forecl} pairs; leaf groups={tot_leafgroups}")
    for g, n in gate_counts.most_common(12):
        print(f"   TOP-GATE {n:6d}  {g}")
    print("clique width histogram (top): " +
          ", ".join(f"{w}x{n}" for w, n in widths.most_common(10)))
    print(f"wide sets (width>=13): {len(wide)} holding "
          f"{sum(p['sat'] - p['covered'] for p in wide)} of the remaining")
    if os.environ.get("REACH_SPLIT"):
        _rem = tot_sat - tot_cov
        _rr = reach_sat - tot_cov
        print("\n=== REACHABILITY SPLIT of the remaining assignments ===", flush=True)
        print(f"  leaf groups: {reach_groups} with an observed compatible walk, "
              f"{unreach_groups} with NONE", flush=True)
        print(f"  demanded {tot_sat}  covered {tot_cov}  remaining {_rem}", flush=True)
        print(f"  REACHABLE remaining     {_rr}  {100.0*_rr/max(_rem,1):5.2f} %"
              "   (some run walked these decisions under these gates)", flush=True)
        print(f"  MULTI-GATE-FORECLOSED   {unreach_sat}  "
              f"{100.0*unreach_sat/max(_rem,1):5.2f} %   (no run ever has)", flush=True)
        unreach_ex.sort(reverse=True)
        print("  largest MULTI-GATE-FORECLOSED leaf groups:", flush=True)
        for sat_lg, ci, w, ns, pre in unreach_ex[:6]:
            gates = "; ".join(f"{e.split('__')[-1][:60]}={'T' if o else 'F'}"
                              for e, o in pre)
            print(f"    sat={sat_lg} set#{ci} width={w} survivors={ns}\n"
                  f"        gates: {gates}", flush=True)
        json.dump(dict(demanded=str(tot_sat), covered=str(tot_cov), remaining=str(_rem),
                       reachable_remaining=str(_rr), multigate_foreclosed=str(unreach_sat),
                       reach_groups=reach_groups, unreach_groups=unreach_groups,
                       top_unreachable=[(str(a), b, c, d, list(e))
                                        for a, b, c, d, e in unreach_ex[:200]]),
                  open(os.path.join(HERE, os.environ.get("REACH_OUT", "_reach_split.json")), "w"),
                  indent=1)
        print("  wrote the reachability split", flush=True)

    if emit is not None:
        print(f"\nEMIT: remaining cubes={emit_stats['cubes']} "
              f"mass={emit_stats['mass']} (of remaining={tot_sat - tot_cov}) "
              f"no_model={emit_stats['no_model']} zero_pieces={emit_stats['zero']} "
              f"unreachable_groups_skipped={emit_stats['unreach_skipped']} "
              f"region_bound={emit_stats['region_bound']} "
              f"capped_sets={emit_stats['capped_sets']} mismatch_sets={emit_stats['mismatch']}")
        _fh.flush(); _fh.close()
        json.dump({"missing": [], "emit_stats": emit_stats,
                   "jsonl": emit + ".jsonl",
                   "source": "_p23_enum.py", "remaining_total": str(tot_sat - tot_cov)},
                  open(emit, "w"))
        print(f"EMIT: streamed {emit_stats['cubes']} entries -> {emit}.jsonl"
              f"  (region pieces seen {emit_stats['pieces']})")
    return {"nodes": len(U["active"]), "cliques": len(cliques),
            "satisfiable": str(tot_sat), "covered": str(tot_cov),
            "remaining": str(tot_sat - tot_cov),
            "bounded_cliques": bounded,
            "foreclosures_applied": tot_forecl,
            "leaf_groups": tot_leafgroups,
            "wide": len(wide),
            "wide_mass": str(sum(p["sat"] - p["covered"] for p in wide)),
            "wall_s": round(time.time() - t0),
            "tree_missing": U["tree_missing"],
            "top_gates": gate_counts.most_common(25),
            "widths": dict(widths),
            "per_clique": [dict(p, sat=str(p["sat"]), covered=str(p["covered"]))
                           for p in per]}


if __name__ == "__main__":
    sys.exit(main())
