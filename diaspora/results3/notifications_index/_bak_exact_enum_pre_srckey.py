#!/usr/bin/env python3
"""Exact combination census for this batch's canonical universe.

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

import hashlib
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
from concolic_engine.run import Run, PathSource  # noqa: E402
from concolic_engine.solver import check_satisfiability  # noqa: E402

import coverage_report as CR  # noqa: E402
import coverage_assumptions as CA  # noqa: E402
from coverage_assumptions import build as build_assumptions  # noqa: E402

# ALIAS_OVERRIDE lets this tool measure the SAME corpus under a different
# declaration without editing the batch: "statement" is the pre-2026-09-09
# single statement-keyed alias over every list read, "loop" the full widening
# the gate refuted, "off" no alias at all. Unset = whatever the batch declares.
_OV = os.environ.get("ALIAS_OVERRIDE")
if _OV:
    from concolic_engine.assumptions import AliasAssumption  # noqa: E402
    _ALL = (r"SYM_RESULT_ActiveRecord__(?:Associations__CollectionProxy_records"
            r"|Relation_records|Relation_to_ary)_\d+")
    _sel = {"statement": [AliasAssumption(result_pattern=_ALL, key="statement")],
            "loop": [AliasAssumption(result_pattern=_ALL, key="loop", k=1)],
            "off": []}[_OV]
    CR.ALIASES = CA.ALIASES = _sel
    print(f"ALIAS_OVERRIDE={_OV}: {[(a.key, a.k) for a in _sel]}", flush=True)

TIMEOUT = int(os.environ.get("Z3_TIMEOUT_MS", "10000"))


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
            CR.canonicalize_ordinals(raw)
            runs.append(CR.share_run_objects(CR.apply_len_bounds(
                Run.from_dict(CR.fix_len_names(raw)))))
        except Exception:
            pass
        del raw
    print(f"loaded {len(runs)} runs", flush=True)
    return runs



def _profile_key(outcomes):
    """A compact, exact key for an outcome profile (see the note at the call
    site). Same equivalence class as the engine's frozenset key."""
    return hashlib.blake2b(
        ";".join(f"{e}:{'1' if True in outcomes[e] else ''}"
                 f"{'0' if False in outcomes[e] else ''}"
                 for e in sorted(outcomes)).encode(),
        digest_size=16).digest()


def _rss():
    try:
        with open("/proc/self/status") as f:
            for l in f:
                if l.startswith("VmRSS:"):
                    return f"{int(l.split()[1])/1048576:.2f} GB"
    except Exception:
        pass
    return "?"


def build_universe(runs, assumptions, max_cliques):
    """coverage.py steps 1, 3, 4, 5 — the SAME universe the pass builds.

    2026-09-10: the demand universe is the MAXIMAL OBSERVED EVALUATION SETS,
    each projected by declared independence — not the maximal cliques of a
    complete graph. `cliques` in this tool now means "demand sets"; the name
    is kept so the census JSON stays readable against earlier runs.
    """
    print(f"[mem] entering build_universe: RSS {_rss()} runs={len(runs)}", flush=True)
    ck = CoverageChecker(runs, assumptions=assumptions, max_cliques=max_cliques)
    print(f"[mem] CoverageChecker built: RSS {_rss()}", flush=True)
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
            # MEMORY (2026-09-10, §12.7). The engine's own key here is
            # `frozenset((e, frozenset(o)) for e, o in outcomes.items())`
            # (src/concolic_engine/coverage.py:717) and it is RETAINED for every
            # DISTINCT profile, so it doubles the profile table: one tuple and
            # one 1-2 element frozenset per expression, per profile, purely to
            # be a dict key. At 96 148 distinct profiles that killed this census
            # three times (rc=137 at 8G and twice at 11G), with RSS 2.55 GB on
            # entry and the kill inside THIS loop.
            # A 16-byte digest of the same information is the same equivalence
            # relation (blake2b over the canonical serialisation of the sorted
            # items; collision probability over 10^5 profiles ~1e-29) and it
            # keeps 16 bytes per profile instead of ~2 objects per expression.
            # The VALUES are unchanged, so every later step reads exactly what
            # it read before.
            profiles.setdefault(
                _profile_key(outcomes), outcomes)
    run_outcomes = list(profiles.values())
    print(f"[mem] profiles built: {len(run_outcomes)} distinct, RSS {_rss()}", flush=True)
    decls = ck._merged_declarations()
    print(f"[mem] declarations merged: RSS {_rss()}", flush=True)
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
    # PROGRESS (2026-09-10, §12.7): the 96 148-profile corpus killed this
    # function twice (rc=137 at 8G and at 11G) with the last flushed line being
    # the `[assumptions]` one, so the phase was invisible. These prints make the
    # projection phase say where it is; -u makes them survive a SIGKILL.
    print(f"[mem] adjacency built: RSS {_rss()}", flush=True)
    print(f"profiles={len(run_outcomes)} active={len(aset)} "
          f"untracked={len(untracked)} pinned={len(pinned)}", flush=True)
    eval_sets = maximal_sets(frozenset(e for e in o if e in aset) for o in run_outcomes)
    _w = sorted((len(s) for s in eval_sets), reverse=True)[:8]
    print(f"evaluation sets={len(eval_sets)} widest={_w}", flush=True)
    projected = []
    for _si, s in enumerate(eval_sets):
        if _si % 100 == 0:
            print(f"  projecting [{_si}/{len(eval_sets)}] width={len(s)} "
                  f"projected_so_far={len(projected)}", flush=True)
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


def components(clique, known, cache):
    """Partition a clique's expressions by SHARED Z3 VARIABLE (union-find)."""
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
    # NO_PINS=1 — census WITHOUT the declared overnight unreachable pins
    # (the counterfactual half; see coverage_report.py).
    if os.environ.get("NO_PINS"):
        _b = len(assumptions.assumptions)
        assumptions.assumptions = [
            a for a in assumptions.assumptions
            if not str(getattr(a, "description", "")).startswith(
                "overnight unreachable pin")]
        print(f"NO_PINS: {_b - len(assumptions.assumptions)} overnight pins removed "
              f"for this census", flush=True)
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

    modes = os.environ.get("FORECLOSURE", "1").split(",")
    results = {}
    for mode in modes:
        results[mode] = census(U, cliques, known, vcache, memo, cube_cap,
                               verify, use_forecl=(mode != "0"))
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
    return 0


def census(U, cliques, known, vcache, memo, cube_cap, verify, use_forecl=True):
    t0 = time.time()
    tot_sat = 0
    tot_cov = 0
    bounded = 0
    widths = Counter()
    per = []
    bit, prof_masks = U["bit"], U["prof_masks"]
    by_gate = U["by_gate"] if use_forecl else {}
    print(f"\n=== CENSUS foreclosure={'ON' if use_forecl else 'OFF (set-level)'}",
          flush=True)
    tot_forecl = 0
    tot_leafgroups = 0
    gate_counts = Counter()
    # REACH_SPLIT (2026-09-10, §13): is a remaining assignment REACHABLE?
    #
    # §16b infers foreclosure PAIRWISE: (g,o) forecloses d only if no run with
    # g=o evaluates d. That misses DISJUNCTIVE reachability -- if d is
    # evaluated when g1=a OR g2=b, runs with g1!=a still evaluate d (via g2=b),
    # so no pairwise foreclosure is inferred, and the cube {g1!=a, g2!=b, d=x}
    # stays DEMANDED even though no run can ever be in a position to walk it.
    #
    # The leaf-group formulation already carries the test. A leaf group is a
    # pair (pre, surv): a gate prefix `pre` and the decisions that survive it.
    # The census computes `cubes` = the observed profiles whose evaluated
    # members of this set are EXACTLY `surv` AND which agree with `pre`. So:
    #   cubes == 0  ->  NO run has ever walked this set of decisions under this
    #                   gate assignment. Every one of the group's `sat`
    #                   assignments is demanded by the declared model and
    #                   unreachable in the corpus: MULTI-GATE-FORECLOSED.
    #   cubes >= 1  ->  some run walked exactly this context, so the group's
    #                   uncovered assignments are an honest driving backlog.
    reach_sat = 0
    unreach_sat = 0
    unreach_groups = 0
    reach_groups = 0
    unreach_ex = []
    reach_rem_per_set = []
    for ci, clique in enumerate(cliques):
        group, local, _ign = restrict_foreclosures(clique, by_gate, bit)
        tot_forecl += sum(bin(m).count("1") for m in local.values())
        for (g, o), m in local.items():
            gate_counts[f"{g} :: {'taken' if o else 'not_taken'}"] += bin(m).count("1")
        widths[len(clique)] += 1
        cm_full = [comp_models(c, U["fixed_base"], U["decls"], U["pinned"], memo)
                   for c in components(list(group), known, vcache)]
        lg = leaves(group, local, bit,
                    feasible=lambda a: cube_count(cm_full, dict(a)) > 0)
        if lg is None:          # leaf-group cap: report as a BOUND, never hide
            bounded += 1
            per.append(dict(width=len(clique), comps=0, sat=0, covered=0,
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
        for pre, surv in lg:
            comps = components(list(surv), known, vcache)
            cm = [comp_models(c, U["fixed_base"], U["decls"], U["pinned"], memo)
                  for c in comps]
            # demanded leaves of this group = models over `surv` agreeing with
            # the gate prefix `pre`
            _sat_lg = cube_count(cm, pre)
            sat += _sat_lg
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
        if is_bound:
            bounded += 1
        tot_sat += sat
        tot_cov += covered
        reach_rem_per_set.append((sat - covered, ci, len(clique)))
        per.append(dict(width=len(clique), comps=len(lg), sat=sat,
                        covered=covered, bound=is_bound, cubes=ncubes,
                        leaf_groups=len(lg),
                        forecl=sum(bin(m).count("1") for m in local.values())))
        if ci % 200 == 0:
            print(f"  [{ci}/{len(cliques)}] sat={sat} covered={covered} "
                  f"width={len(clique)} leaf_groups={len(lg)}", flush=True)

    if os.environ.get("REACH_SPLIT"):
        _rem = tot_sat - tot_cov
        _rr = reach_sat - tot_cov
        print("\n=== REACHABILITY SPLIT of the remaining assignments (§13) ===",
              flush=True)
        print(f"  leaf groups: {reach_groups} with an observed compatible walk, "
              f"{unreach_groups} with NONE", flush=True)
        print(f"  demanded {tot_sat}  covered {tot_cov}  remaining {_rem}",
              flush=True)
        print(f"  REACHABLE remaining        {_rr:7d}  "
              f"{100*_rr/max(_rem,1):5.1f} %   (some run walked these decisions "
              f"under these gates)", flush=True)
        print(f"  MULTI-GATE-FORECLOSED      {unreach_sat:7d}  "
              f"{100*unreach_sat/max(_rem,1):5.1f} %   (no run ever has)",
              flush=True)
        unreach_ex.sort(reverse=True)
        print("  largest MULTI-GATE-FORECLOSED leaf groups (sat, set, width, "
              "survivors, gate prefix):", flush=True)
        for sat_lg, ci, w, ns, pre in unreach_ex[:8]:
            gates = "; ".join(f"{e.split('__')[-1][:70]}={'T' if o else 'F'}"
                              for e, o in pre)
            print(f"    sat={sat_lg:6d} set#{ci} width={w} survivors={ns}\n"
                  f"        gates: {gates}", flush=True)
        reach_rem_per_set.sort(reverse=True)
        print("  largest REACHABLE per-set remaining: " +
              ", ".join(f"set#{ci}(w{w})={r}" for r, ci, w in
                        reach_rem_per_set[:8]), flush=True)
        json.dump(dict(demanded=tot_sat, covered=tot_cov, remaining=_rem,
                       reachable_remaining=_rr,
                       multigate_foreclosed=unreach_sat,
                       reach_groups=reach_groups, unreach_groups=unreach_groups,
                       top_unreachable=[(a, b, c, d, list(e))
                                        for a, b, c, d, e in unreach_ex[:200]],
                       top_reachable_sets=reach_rem_per_set[:200]),
                  open(os.path.join(HERE, "_reach_split.json"), "w"), indent=1)
        print("  wrote _reach_split.json", flush=True)

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
                if any(e in U["pinned"] and o != U["pinned"][e] for e, o in leaf):
                    continue
                if check_satisfiability(list(U["fixed_base"]) + [_combo_constraint(leaf)],
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
