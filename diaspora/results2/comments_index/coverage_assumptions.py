#!/usr/bin/env python3
"""comments_index — batch-local coverage assumptions.

Combination-coverage semantics (src/concolic_engine/coverage.py, decision
2026-08-18): completeness demands every Z3-satisfiable combination of
outcomes over each maximal clique of the PC-expression dependence graph be
observed in a SINGLE run's executed path. With three distinct expressions
observed on this entrypoint —

  1. ``(Length(SYM_PARAM_post_id) < 16)``                         [length dispatch]
  2. ``(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)``  [finder outcome]
  3. ``(SYM_RESULT_ActiveRecord__FinderMethods_first_1_public == True)``    [post.public? outcome]

— the graph starts as one 3-clique (fully connected, no assumptions), which
demands all 8 outcome combinations. 4 are covered by the 6 executed runs
(2x length x 2x {not_found=False, public} in dse0001/02/07/08). The other 4
— every combination of ``not_found=True`` with a ``public`` outcome, at
either length — are permanently unobservable: see the IndependenceAssumption
below for the argument and code citations.

Usage: imported by coverage_report.py in this directory.
"""
from __future__ import annotations

import sys

sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.assumptions import AssumptionSet, IndependenceAssumption  # noqa: E402


NOT_FOUND_EXPR = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)"
PUBLIC_EXPR = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_public == True)"


def build() -> AssumptionSet:
    aset = AssumptionSet()

    # ------------------------------------------------------------------
    # IndependenceAssumption: not_found  ||  public
    # ------------------------------------------------------------------
    # Argued per COMPLETION_BRIEF.md / IndependenceAssumption docstring
    # ("can any combination of the two outcomes produce a call
    # sequence/access pattern the individual outcomes don't?" -> must be
    # provably NO).
    #
    # Both expressions come from a SINGLE finder call in this action's only
    # code path to a Post lookup, PostService#find_public! (comments_index
    # is anonymous, so PostService.new(nil)#find! -> #find_public!):
    #
    #   ruby_examples/dse-apps/apps/diaspora/app/services/post_service.rb:51-55
    #     def find_public!(id_or_guid)
    #       Post.where(post_key(id_or_guid) => id_or_guid).first.tap do |post|
    #         raise ActiveRecord::RecordNotFound, "..." unless post          # line 53
    #         raise Diaspora::NonPublic unless post.public?                  # line 54
    #       end
    #     end
    #
    # `.first` is mocked generically by finder_mock (this dir's
    # concolic_targets.rb:326-338, raise_on_missing: false for `.first`):
    #
    #     nf_name = "#{name}_not_found"
    #     not_found = symbool(nf_name, seed_for(nf_name, false), note: sql)
    #     if not_found == true
    #       raise ActiveRecord::RecordNotFound, ... if raise_on_missing      # false here
    #       nil                                        # <- returned as `post`
    #     else
    #       symbolic_instance(model_class(receiver), name, sql)             # <- only place
    #     end                                             #    a `_public` var/PC can exist
    #
    # When not_found == True, `.first` returns nil WITHOUT ever calling
    # symbolic_instance — so the `_public` symbolic var (and its PC, which
    # only fires from the `public?` reader defined inside symbolic_instance,
    # concolic_targets.rb:236-241) is never even CREATED for that call, let
    # alone evaluated. Back in find_public!, line 53's `unless post` then
    # raises RecordNotFound immediately, before line 54 (`post.public?`) is
    # ever reached. There is no Ruby-level way for a single run to record
    # BOTH `not_found == True` and any `public` outcome for the same finder
    # call: they sit on genuinely mutually-exclusive execution paths (test
    # #1 in the IndependenceAssumption docstring), and neither's downstream
    # target-function calls or arguments depend on the other in any way the
    # engine tracks (test #2) — when not_found=True the run terminates at
    # `head :not_found` (comments_controller.rb's rescue_from) with zero
    # further target calls.
    #
    # Empirically verified across all 6 dumps in this directory: the two
    # not_found=True runs (dse0004, dse0006) contain ZERO `_public`
    # path_condition or symbolic_vars events; all 4 not_found=False runs
    # (dse0001/02/07/08) contain exactly one. Confirms the static argument,
    # not just asserts it.
    #
    # Per-run-ordinal caveat (COMPLETION_BRIEF.md): both exprs always carry
    # the "_1" ordinal in every one of the 6 dumps — PostService#find_public!
    # makes exactly one finder call per run on this entrypoint, so "expr"
    # names the same decision (this action's only Post lookup) in every run
    # fed to the checker. Safe to key by expr alone.
    aset.add(IndependenceAssumption(
        expr_a=NOT_FOUND_EXPR,
        expr_b=PUBLIC_EXPR,
        description=(
            "post_service.rb#find_public! (lines 51-55): `unless post` "
            "(not_found==True) raises RecordNotFound and returns before "
            "`post.public?` (line 54) is ever reached, and the mocked "
            "finder (concolic_targets.rb finder_mock) never even "
            "constructs a symbolic_instance -- so no `_public` PC can "
            "exist -- when not_found==True. The two outcomes are on "
            "mutually exclusive execution paths; no combination of them "
            "produces an access pattern beyond what each covers alone."
        ),
        agent_notes=(
            "Verified empirically, not just statically: dse0004/dse0006 "
            "(not_found=True) contain zero `_public` events; all 4 "
            "not_found=False dumps contain exactly one. Same ordinal "
            "(_1) in all 6 dumps -- single finder call per run on this "
            "entrypoint, so expr-keying is safe per the per-run-ordinal "
            "caveat."
        ),
    ))

    return aset
