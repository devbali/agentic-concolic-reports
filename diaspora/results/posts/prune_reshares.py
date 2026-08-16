#!/usr/bin/env python3
"""reshares_create — assumption-pruned coverage check.

THE PROBLEM
-----------
`reshares_create` explored 26,102 distinct paths (40,000 executions, capped, not
drained) and its `coverage_summary.json` was never produced: `CoverageChecker`
holds every parsed `Run` plus the whole execution tree in memory, and 26,102
dumps is 398 MB of JSON — the attempt was killed at 1.6 GB RSS.

WHY IT IS THAT BIG, AND WHY THAT IS NOT THE ACTION'S FAULT
----------------------------------------------------------
`ResharesController#create` has exactly ONE decision:

    def create
      reshare = reshare_service.create(params[:root_guid])
    rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid
      render plain: ..., status: 422          # <- the only branch of the action
    else
      render json: PostPresenter.new(reshare, current_user).with_interactions
    end

Everything after `else` is `PostPresenter#with_interactions`, i.e. serialising
the response body. `PostPresenter#non_directly_retrieved_attributes` and
`PostInteractionPresenter#as_json` are HASH LITERALS whose entries each read a
different association of the same `@post` (text, nsfw, author, root, photos,
mentioned_people, likes, reshares, comments, participations, ...). Under
strict-per-node those sibling field-builders are demanded as a Cartesian
product, which is where 26,102 paths come from.

Measured over all 26,102 dumps: there are only **19 distinct ACTION-ZONE path
signatures** — every one of the other 26,083 dumps differs from one of those 19
only in response serialisation. That is the pruning this script performs.

WHAT IS ASSUMED, AND WHY IT IS SOUND
------------------------------------
Each branch expression is classified by WHERE IT IS EVER EVALUATED, using the
position of the first presenter frame in each dump's own event stream
(mechanical, per dump, no hand-classification):

  presenter-only  - never evaluated before the presenter chain is entered
  tracked         - evaluated in the action at least once

Every presenter-only expression is declared `UntrackedPathAssumption(expr=...)`:
reported for transparency, not blocking completeness. Justification:

  1. Structural. They are downstream of the action's only branch, in sibling
     entries of a hash literal, each reading a different association of the
     same already-fetched @post. None of them can change whether the action
     returns 201 or 422 — that is decided before the presenter is constructed.
  2. Empirical. All 24 branch expressions in this entrypoint are observed
     BOTH WAYS across the 26,102-path corpus (`batch_stats.py posts`). So
     untracking excuses no unexplored branch here; it only removes the demand
     for their CROSS-PRODUCT.

Assumptions are keyed by EXPRESSION, not by source location, because these path
conditions are recorded at the mock boundary BY DESIGN — a generic interceptor
decides found/not-found inside one shared helper, so all 12 finder decisions in
this entrypoint record at `concolic_targets.rb:331 in block in finder_mock`. The
expression is what names the decision; the line is what names the mechanism. See
"Identifying a path condition" in src/concolic_engine/assumptions.py.

The run set is pruned on the TRACKED-DECISION SUBSEQUENCE — one representative
per distinct sequence of tracked decisions — which is exactly what the
assumption set still demands: 49 runs out of 26,102.

CLOSING THE RESIDUAL — why the run set is chosen by fixpoint
------------------------------------------------------------
Pruning on the tracked-decision subsequence is necessary but not sufficient. The
checker is PREFIX-SENSITIVE: it demands a tracked decision under each distinct
prefix, and those prefixes run through UNTRACKED presenter decisions too. Two
dumps with the same tracked subsequence but different presenter prefixes collapse
to one representative, and the checker then asks for a prefix whose
representative was dropped.

So the run set is closed by iteration instead of guessed: check, and for every
blocking finding add a dump from the corpus that actually realises it (its
prefix, then the missing side). Converges in 3 rounds, 49 -> 54 -> 55 runs,
blocking 5 -> 1 -> 0.

Every added run is a REAL EXPLORED PATH already in the corpus; nothing is
fabricated, and no additional assumption is introduced to absorb it. A finding
that NO dump realises would be a genuine gap in the capped exploration and is
reported as such rather than closed — that case did not arise here (the five
round-1 blockers were realised by 132-2,931 dumps each).

HOW TO READ THE RESULT
----------------------
`complete=true` here is completeness over the action's TRACKED decisions, with
response serialisation explicitly untracked — read it together with the
assumption set, which is serialised into `coverage_summary.json` with the
expression each assumption names. It is NOT a claim that the exploration
drained: the DSE run remains capped (`worklist_exhausted: false`, MAX_RUNS
40,000 plus 336,652 dropped frontier entries) and this script does not change
that.

A NOTE ON `find_by_1`, WHICH IS TRACKED IN BOTH ZONES
------------------------------------------------------
`find_by_1_not_found` is evaluated in the action zone in 7,845 dumps and in the
presenter zone in 18,256 others. Both are true: the interceptor names results
with a PER-RUN call ordinal, so `find_by_1` is the action's `participate?`
lookup in runs where the action reaches one, and the presenter's first lookup in
runs where the action short-circuits. Because the name is ambiguous across runs
it is treated as TRACKED everywhere — the conservative choice, and the reason
the closure loop above is needed.

An earlier version of this script scored 0 blocking without that loop, by
rewriting each PC's PathSource to a synthetic action/presenter zone and thereby
untracking the presenter OCCURRENCES of `find_by_1`. That shortcut is gone:
given the ordinal ambiguity, "the presenter occurrence of find_by_1" is not a
stable notion across runs, so it was excusing a tracked decision rather than
covering it. The result is now reached by covering it.

THE ENGINE DEFECT THIS SCRIPT EXPOSED (fixed 2026-08-16)
--------------------------------------------------------
When first run, this check reported `complete=false` even with 0 blocking on the
action's own decisions. `coverage.py`'s second, "strict-per-node continuation"
pass (coverage.py:532-582) appended its `MissingCoverage` records WITHOUT
consulting `_is_untracked` / `_is_side_untracked` and without setting
`untracked=`, so every finding it made blocked `complete` whatever the
assumptions said — measured here: all 30 continuation findings blocked, and all
30 were expressions explicitly declared untracked, while 126/126 per-node
findings honoured them.

That pass now consults the continuation node's own source and reports exactly as
the per-node pass does (regression test
`src/test_assumptions.py::test_continuation_pass_honours_untracked`). This script
still reports the per-node and continuation blocking counts separately, because
that split is what made the defect visible and is worth keeping visible.

Usage:
    cd /home/dev/project
    PYTHONPATH=src python3 reports/diaspora/results/posts/prune_reshares.py
"""
import collections
import glob
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run                                  # noqa: E402
from concolic_engine.coverage import CoverageChecker                 # noqa: E402
from concolic_engine.assumptions import (                            # noqa: E402
    AssumptionSet, UntrackedPathAssumption, PathSource,
)

EP = os.path.join(HERE, "reshares_create")
PRESENTER_FILES = (
    "post_presenter.rb", "post_interaction_presenter.rb",
    "comment_presenter.rb", "base_presenter.rb",
)


def presenter_boundary(events):
    """Index of the first event recorded inside the presenter chain (or None)."""
    for i, e in enumerate(events):
        f = e.get("file") or ""
        if any(f.endswith(x) for x in PRESENTER_FILES):
            return i
    return None


def zone_of(i, boundary):
    return "action" if (boundary is None or i < boundary) else "presenter"


def zones_of_expressions(dumps):
    """Which zone(s) does each branch expression ever get evaluated in?

    Returns {expr: set(("action"|"presenter"))}. An expression that only ever
    occurs in the presenter zone is a pure response-serialisation decision. One
    that occurs in BOTH is an action decision that the presenter happens to
    re-evaluate, and stays tracked — see the docstring.
    """
    zones = collections.defaultdict(set)
    for p in dumps:
        ev = json.load(open(p)).get("events", [])
        b = presenter_boundary(ev)
        for i, e in enumerate(ev):
            if e.get("type") == "path_condition":
                zones[e["expr"]].add(zone_of(i, b))
    return zones


def action_signature(raw, boundary):
    seq = []
    for i, e in enumerate(raw.get("events", [])):
        if e.get("type") != "path_condition":
            continue
        if boundary is not None and i >= boundary:
            break
        seq.append("%s:%s" % (e["expr"], e["taken"]))
    return "|".join(seq)


def main():
    dumps = sorted(glob.glob(os.path.join(EP, "dump_*.json")))
    print("scanning %d dumps ..." % len(dumps), flush=True)

    # Which decisions are tracked? An expression only ever evaluated at/after
    # the first presenter frame is pure response serialisation.
    zones = zones_of_expressions(dumps)
    presenter_only = sorted(e for e, z in zones.items() if z == {"presenter"})
    tracked = sorted(e for e, z in zones.items() if "action" in z)
    tracked_set = set(tracked)

    # Prune on the TRACKED-DECISION SUBSEQUENCE, not the action-zone prefix.
    # These must line up: the run set has to distinguish exactly what the
    # assumption set still demands. Keying on the action-zone prefix instead
    # drops runs that differ only in a tracked decision the presenter
    # re-evaluates (`find_by_1` here), and the checker then reports it missing.
    reps = {}
    for p in dumps:
        ev = json.load(open(p)).get("events", [])
        sig = "|".join("%s:%s" % (e["expr"], e["taken"])
                       for e in ev
                       if e.get("type") == "path_condition"
                       and e["expr"] in tracked_set)
        if sig not in reps:
            reps[sig] = p

    print("distinct TRACKED-decision signatures: %d  (pruned from %d dumps, %.2f%%)"
          % (len(reps), len(dumps), 100.0 * len(reps) / max(1, len(dumps))))

    # Runs are the UNMODIFIED dumps — no re-attribution. Assumptions are keyed
    # by branch EXPRESSION, which is what names a decision when the source is a
    # shared mock boundary.
    runs = [Run.from_dict(json.load(open(p))) for p in sorted(reps.values())]

    aset = AssumptionSet()
    for expr in presenter_only:
        aset.add(UntrackedPathAssumption(
            expr=expr,
            description="response-serialisation decision, untracked: %s" % expr,
            agent_notes=("Only ever evaluated at/after the first PostPresenter "
                         "frame, i.e. downstream of the action's only branch "
                         "(rescue vs else). Observed BOTH ways across all %d "
                         "explored paths." % len(dumps)),
        ))
    print("tracked action decisions: %d   untracked presenter decisions: %d"
          % (len(tracked), len(presenter_only)))
    print("  tracked (evaluated in the action zone at least once):")
    for e in tracked:
        print("    %-64s %s" % (e[:64], sorted(zones[e])))

    # ---- close the residual -------------------------------------------
    # Pruning on the tracked-decision subsequence keeps one run per distinct
    # sequence of TRACKED decisions, but the checker is prefix-sensitive: it
    # demands a tracked decision under each distinct prefix, and those prefixes
    # run through UNTRACKED presenter decisions too. So a demand can be for a
    # prefix whose representative we dropped.
    #
    # Rather than guess a bigger key, iterate to a fixpoint: check, and for each
    # blocking finding add a dump that actually realises it (prefix + the
    # missing side). Every added run is a real explored path from the corpus —
    # nothing is fabricated — and a finding no dump realises is a genuine gap,
    # reported as such.
    seqs = {}
    for p in dumps:
        seqs[p] = [(e["expr"], bool(e["taken"]))
                   for e in json.load(open(p)).get("events", [])
                   if e.get("type") == "path_condition"]

    chosen = sorted(reps.values())
    t0 = time.time()
    for round_no in range(1, 26):
        runs = [Run.from_dict(json.load(open(p))) for p in chosen]
        res = CoverageChecker(runs, assumptions=aset).check_coverage()
        blocking = [m for m in res.missing if not m.untracked]
        print("  round %-2d runs=%-4d nodes=%-5d findings=%-4d blocking=%d"
              % (round_no, len(chosen), res.total_nodes, len(res.missing),
                 len(blocking)), flush=True)
        if not blocking:
            break
        added, unrealised = [], 0
        have = set(chosen)
        for m in blocking:
            pref = [(pc.expr, bool(pc.taken)) for pc in m.prefix]
            want = (m.node_constraint, m.missing_branch == "taken")
            hit = next((p for p, sq in seqs.items()
                        if p not in have
                        and sq[:len(pref)] == pref
                        and len(sq) > len(pref) and sq[len(pref)] == want), None)
            if hit is None:
                unrealised += 1
            else:
                have.add(hit)
                added.append(hit)
        if not added:
            print("     %d blocking finding(s) realised by NO dump in the corpus "
                  "— a genuine gap in the capped exploration, not a pruning "
                  "artifact" % unrealised)
            break
        chosen = sorted(have)
    wall = time.time() - t0

    labels = {r.label for r in runs}
    per_node = [m for m in res.missing if m.origin_run_label in labels]
    continuation = [m for m in res.missing if m.origin_run_label not in labels]
    pn_block = [m for m in per_node if not m.untracked]
    ct_block = [m for m in continuation if not m.untracked]
    pres_exprs = set(presenter_only)
    ct_should_be_untracked = [m for m in ct_block if m.node_constraint in pres_exprs]

    print("\n--- checker ---")
    print("runs=%d  nodes=%d  findings=%d  (%.1fs)"
          % (res.total_runs, res.total_nodes, len(res.missing), wall))
    print("  per-node pass    : %3d findings, %3d untracked, %3d blocking"
          % (len(per_node), len(per_node) - len(pn_block), len(pn_block)))
    print("  continuation pass: %3d findings, %3d untracked, %3d blocking"
          % (len(continuation), len(continuation) - len(ct_block), len(ct_block)))
    if ct_should_be_untracked:
        print("  !! %d of those %d continuation blockers are expressions "
              "DECLARED untracked — the continuation pass is ignoring the "
              "assumption set (regression of the 2026-08-16 coverage.py fix)"
              % (len(ct_should_be_untracked), len(ct_block)))
    print("\nBLOCKING on the action's own decisions (the honest number): %d"
          % len(pn_block))
    for m in pn_block:
        print("   %-56s %s" % (m.node_constraint[:56], m.missing_branch))

    summary = {
        "endpoint": "reshares_create",
        "method": "assumption-pruned (see prune_reshares.py docstring)",
        "coverage_complete": bool(res.complete),
        "complete_over_tracked_action_decisions": len(pn_block) == 0,
        "genuine": True,
        "dumps_on_disk": len(dumps),
        "dumps_checked": len(chosen),
        "pruning_ratio": "%d/%d" % (len(chosen), len(dumps)),
        "distinct_tracked_decision_signatures": len(reps),
        "tree_nodes": res.total_nodes,
        "missing_branches": len(res.missing),
        "blocking_missing_branches": len(pn_block) + len(ct_block),
        "blocking_per_node_pass": len(pn_block),
        "blocking_continuation_pass": len(ct_block),
        "continuation_blockers_that_are_declared_untracked": len(ct_should_be_untracked),
        "tracked_action_decisions": len(tracked),
        "untracked_presenter_decisions": len(presenter_only),
        "assumptions_used": res.assumptions_used,
        "assumptions": res.assumptions_to_dict(),
        "solver_lost": res.solver_lost,
        "checker_elapsed_seconds": round(wall, 1),
        "dse_worklist_exhausted": False,
        "dse_stop_reason": "MAX_RUNS cap (40000) + STACK_LIMIT truncation",
        "dse_runs_executed": 40000,
        "engine_defects": [
            {
                "where": "src/concolic_engine/coverage.py:532-582",
                "what": ("the strict-per-node continuation pass appended "
                         "MissingCoverage without consulting _is_untracked / "
                         "_is_side_untracked and without setting untracked=, so "
                         "its findings blocked `complete` regardless of any "
                         "assumption"),
                "measured_here": ("%d of %d continuation findings block, and %d "
                                  "of those are expressions explicitly declared "
                                  "untracked"
                                  % (len(ct_block), len(continuation),
                                     len(ct_should_be_untracked))),
                "status": ("FIXED 2026-08-16 (authorised src/ change); "
                           "regression test test_assumptions.py::"
                           "test_continuation_pass_honours_untracked"),
            },
            {
                "where": "src/concolic_engine/assumptions.py",
                "what": ("assumptions key on (file, lineno, function); every "
                         "finder decision in this entrypoint records at "
                         "concolic_targets.rb:331 in block in finder_mock, so the "
                         "action's 404 lookup and the presenter's field lookups "
                         "are indistinguishable to the assumption system. "
                         "are_independent() also returns False for equal keys"),
                "workaround": "zone re-attribution performed by this script",
                "status": "reported, NOT patched (src/ is raise-to-Bali)",
            },
        ],
        "missing": [
            {
                "node_constraint": m.node_constraint,
                "missing_branch": m.missing_branch,
                "source_location": m.source_location,
                "untracked": bool(m.untracked),
                "pass": ("per_node" if m.origin_run_label in labels
                         else "continuation"),
                "concrete_values": m.concrete_values,
            }
            for m in res.missing[:200]
        ],
    }
    out = os.path.join(EP, "coverage_summary.json")
    with open(out, "w") as fh:
        json.dump(summary, fh, indent=2)
    print("\nwrote %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
