#!/usr/bin/env python3
"""people_stream (results3) -- combination-coverage assumptions.

Starting point per the mission brief: results2/people_stream/coverage_
assumptions.py analyzed a 12-expression universe (people_controller.rb's
find_person before_action: diaspora_id? arm choice A, plus not_found/
closed_account/guid triples per arm B..L). Its Arguments 1-5 are PORTED
VERBATIM below (A-L, same expressions, same file:line -- people_controller.rb
/person.rb were not touched by the results3 discipline rebuild, so that
analysis still holds byte-for-byte) -- see each argument's docstring for the
original citation.

The results3 discipline rebuild (render family removed, Post.blocked_people/
Stream::Base#post_ids/#attach_user_likes DESCENDED -- see ../concolic_
targets.rb header) makes `stream`'s own body execute for real, adding 8 NEW
tracked expressions the results2 universe never reached:

    PN  = (SYM_PROFILE_PERSON_nsfw == True)
    FB1 = (SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found == True)
    FB2 = (SYM_RESULT_ActiveRecord__FinderMethods_find_by_2_not_found == True)
    R1T = (SYM_RESULT_ActiveRecord__Relation_records_1_row_text == '')
    R1C = (SYM_RESULT_ActiveRecord__Relation_records_1_row_comments_count == 0)
    R4T = (SYM_RESULT_ActiveRecord__Relation_records_4_row_text == '')
    R4G = (SYM_RESULT_ActiveRecord__Relation_records_4_row_guid == '')
    R4C = (SYM_RESULT_ActiveRecord__Relation_records_4_row_comments_count == 0)

Provenance (verified via dump note fields, `grep`-quoted below each var):
  - PN: Person#profile (has_one) -> Profile's own `nsfw` boolean column,
    read somewhere in the json-render presenter chain (PersonSymAssociations
    #profile, targets.rb Sec.1/8 -- every `person.profile` call in a run
    shares this ONE hardcoded var name, a pre-existing results2 design
    choice, not new here).
  - FB1: `SELECT "likes".* FROM "likes" WHERE "likes"."target_id" = $$(...)
    AND "likes"."target_type" = 'Post' AND "likes"."positive" = true` --
    the VIEWER'S like-lookup inside PostPresenter#build_interactions_json
    (`ActiveRecord::FinderMethods#find_by`, an INSTANCE-level find_by on an
    already-scoped relation -- a DIFFERENT declared target from F/G/J's
    `Core::ClassMethods.find_by`, hence a fresh ordinal family).
  - FB2: a Reshare-family `find_by` (`Post#reshare_for` -- `reshares.
    find_by(author_id: user.person.id)`, post.rb) reached from the json
    presenter chain; its `note` field independently surfaced a pre-existing
    `sql_for` rendering hiccup (`render_relation_sql failed: NoMethodError
    undefined method 'value' for #<Arel::Node...>`, harmless -- sql_for's
    own outer rescue caught it and fell back to the `args=...` form; a minor
    note-fidelity gap reported in REPORT.md, not fixed here).
  - R1T/R1C: attributes of ONE `ActiveRecord::Relation#records` mock
    invocation (design #4/Patch 4) whose SQL note is the `for_a_stream`
    posts query (`SELECT "posts".* ... WHERE "posts"."author_id" =
    $$(first_1_id) AND "posts"."created_at" < ...`).
  - R4T/R4G/R4C: attributes of a SEPARATE `#records` mock invocation (a
    later ordinal, "_4") whose rendered SQL note is IDENTICAL text to R1's
    -- both are reads against the (structurally) same `for_a_stream`-scoped
    relation, but the mock does NOT memoize `@records` across separate
    `.records`/`.to_a` calls (declare_target replaces the method body
    entirely, so AR's own real `@records ||=` memoization line never runs)
    -- each invocation mints an independent `symbolic_instance` with its own
    fresh var names. This is a genuine, reportable mock-fidelity gap (a real
    request would see the SAME row both times; our mock lets them vary
    independently) -- see REPORT.md. For COVERAGE purposes this is actually
    the safest direction to acknowledge: since nothing in either family's
    recorded PC expression contains the other family's symbol, they are
    ALREADY free variables in the checker's own term -- Argument 7 below
    just makes that explicit instead of leaving it to the default (implicit
    full-dependence) clique.

Arguments 6-8 (NEW, this pass) handle cross-family combinations between the
old 12-var find_person universe and the new 8-var stream-body universe;
within-NEW-family pairs (e.g. R1T x R1C, genuinely co-varying attributes of
the SAME representative row) are left UNDECLARED -- fully demanded, and
witnessed naturally by the corpus's 197 auth_json + 29 anon_json runs rather
than assumed away. See build()'s trailing comment for what remained missing
after this file was applied, if anything.
"""
from __future__ import annotations

import sys

sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.assumptions import (  # noqa: E402
    AssumptionSet,
    IndependenceAssumption,
    OneSideUntrackedPathAssumption,
    AliasAssumption,
)
from concolic_engine.coverage import maximal_sets  # noqa: E402

# --- Alias (ported from notifications_index, 2026-09-09) -----------
# The residual missing set is combinations over ordinal-named list reads: the
# SAME logical read (a post row's text / comments_count / guid) is
# `Relation_records_1` on some paths and `Relation_records_4` on others,
# because a symbolic result is named by WHEN the call happened
# (SymbolicFunc.next_call_idx), not by WHAT it is. This module's own docstring
# above lists R1T/R1C and R4T/R4G/R4C as SEPARATE expressions — that is the
# conflation, not five independent facts. Measured: in the R1 demand dumps
# records_4 fired 288x vs records_1 72x, and 10 rooted seeds naming records_1
# landed in runs where that ordinal never occurred, so the seed was inert.
# Re-key each read by the statement it resolved to (binds kept, literals
# wildcarded) so one fact is one variable. Verified by the gate's Alias
# derived test, which FAILS on an unsound alias.
ALIAS_PATTERN = (r"SYM_RESULT_ActiveRecord__(?:Associations__CollectionProxy_records"
                 r"|Relation_records|Relation_to_ary)_\d+")
ALIASES = [AliasAssumption(
    result_pattern=ALIAS_PATTERN, key="statement",
    description="ordinal-named list reads identified by their statement (binds kept)",
    agent_notes=("the ordinal of the stream's post/comment list reads is a function of "
                 "the path prefix; re-keyed by statement so one fact is one variable."))]


# ---------------------------------------------------------------------------
# find_person's 12-var universe (results2/people_stream Arguments 1-5,
# PORTED VERBATIM -- people_controller.rb/person.rb unchanged by results3).
# ---------------------------------------------------------------------------
A = "(SYM_RESULT_PeopleController_diaspora_id__1_result == True)"

B = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)"
C = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account == True)"
D = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_guid == '')"
E = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_guid != StringVal(''))"

F = "(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found == True)"
G = "(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_closed_account == True)"
H = "(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_guid == '')"
I = "(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_guid != StringVal(''))"

J = "(SYM_PERSON_via_user_closed_account == True)"
K = "(SYM_PERSON_via_user_guid == '')"
L = "(SYM_PERSON_via_user_guid != StringVal(''))"

# ---------------------------------------------------------------------------
# NEW for results3: the 8-var stream-body universe (see module docstring).
# ---------------------------------------------------------------------------
PN  = "(SYM_PROFILE_PERSON_nsfw == True)"
FB1 = "(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found == True)"
FB2 = "(SYM_RESULT_ActiveRecord__FinderMethods_find_by_2_not_found == True)"
R1T = "(SYM_RESULT_ActiveRecord__Relation_records_1_row_text == '')"
R1C = "(SYM_RESULT_ActiveRecord__Relation_records_1_row_comments_count == 0)"
R4T = "(SYM_RESULT_ActiveRecord__Relation_records_4_row_text == '')"
R4G = "(SYM_RESULT_ActiveRecord__Relation_records_4_row_guid == '')"
R4C = "(SYM_RESULT_ActiveRecord__Relation_records_4_row_comments_count == 0)"

NEW = [PN, FB1, FB2, R1T, R1C, R4T, R4G, R4C]

NOT_FOUND_FORECLOSES = (
    "people_controller.rb:140 `raise ActiveRecord::RecordNotFound if "
    "@person.nil?` fires immediately when the finder_mock's not_found "
    "boundary decides True (finder_mock(raise_on_missing: false) itself "
    "returns nil rather than raising, letting the caller's line-140 raise "
    "fire) -- before line 141's closed_account? check or stream's own "
    "redirect/json body (both several statements later) ever run. Verified: "
    "every not_found==True dump has EXACTLY 2 PCs (A + the not_found var), "
    "nothing else."
)

CLOSED_ACCOUNT_FORECLOSES = (
    "people_controller.rb:141 `raise Diaspora::AccountClosed if "
    "@person.closed_account?` fires immediately when closed_account "
    "decides True, still inside the find_person before_action -- stream's "
    "redirect/json body (where the arm's guid pair AND the new stream-body "
    "vars are read) never runs. Verified: every closed_account==True dump "
    "has EXACTLY 3 PCs (A + not_found + closed_account), nothing from "
    "stream's body ever appears."
)

A_VS_ARM_FAMILY = (
    "people_controller.rb:129-138 `find_person`: `@person = "
    "diaspora_id?(username) ? Person.where(...).first : "
    "Person.find_from_guid_or_username(...)` -- an if/else. B/C (first_1_*) "
    "only exist on the diaspora_id?==True branch; F/G/J only exist on the "
    "False branch (whichever of person.rb's own two non-else arms fired). "
    "Exactly one branch runs per request, so the OTHER branch's own "
    "not_found/closed_account guard vars are simply absent from that run's "
    "trace -- mutually exclusive per the IndependenceAssumption safety "
    "test's criterion 1 (different if/elif/else branches)."
)

GUID_TRUE_UNREACHABLE = (
    "action_dispatch/journey/formatter.rb:40-41 (actionpack 5.2.4.3, stock "
    "gem, unmodified), reached via stream's `format.all "
    "{ redirect_to person_path(@person) }` for WHICHEVER @person the arm "
    "produced: line 40's `parameterized_parts[key].present?` breaks the "
    "route-parts loop BEFORE line 41 (the '!=' pair's site) runs whenever "
    "the guid is non-blank (the '==' pair is False). When the guid IS "
    "blank (the '==' pair is True), line 41 does run, but `guid.to_s != "
    "''` is forced False by string equality with the just-established "
    "blank value. The '!=' pair's True outcome cannot be produced by any "
    "seed: the only path that evaluates it forces it False, and the "
    "alternative path never evaluates it at all."
)

# ---------------------------------------------------------------------------
# NEW arguments 6-8 (results3).
# ---------------------------------------------------------------------------
GUARD_FORECLOSES_STREAM_BODY = (
    "Direct extension of Arguments 1/2 above: `stream`'s ENTIRE body -- "
    "BOTH the html `format.all { redirect_to ... }` arm (where D/E/H/I/K/L "
    "are read) AND the json `format.json { render json: person_stream."
    "stream_posts.map { LastThreeCommentsDecorator.new(PostPresenter.new"
    "(p, current_user)) } }` arm (where the 8 NEW vars are read) -- only "
    "executes once `find_person`'s before_action returns without raising, "
    "i.e. after not_found==False AND closed_account==False on whichever arm "
    "produced @person (people_controller.rb:140-141). A True value on ANY "
    "of the five guard vars (B, C, F, G, J) means the before_action raised "
    "before `stream` itself was ever entered -- the json presenter chain "
    "(where every NEW var is read) never got a chance to run, exactly the "
    "same construction Arguments 1/2 already proved for D/E/H/I/K/L, just "
    "extended to the vars added when the render family (Section Z) was "
    "removed this pass."
)

A_VS_STREAM_BODY = (
    "A (diaspora_id?) only decides WHICH of find_person's two arms resolves "
    "@person (people_controller.rb:129-138); once @person is resolved (by "
    "EITHER arm), `stream`'s own body -- including every NEW var -- runs "
    "identically regardless of which arm produced it. `stream`'s source "
    "(people_controller.rb:93-100) never reads `diaspora_id?`'s result or "
    "any of its downstream vars. Independent by construction: different "
    "code, no shared symbol, and both A==True and A==False dumps reach the "
    "json body (confirmed -- auth_json corpus contains both)."
)

def _pair(expr_a: str, expr_b: str, why: str) -> IndependenceAssumption:
    return IndependenceAssumption(
        expr_a=expr_a, expr_b=expr_b,
        description="mutually exclusive / foreclosed per app control flow -- see agent_notes",
        agent_notes=why,
    )


def _coeval_pairs(runs):
    """The corpus's CO-EVALUATION relation — every pair of decisions some run
    evaluated together, derived exactly as the engine derives its demand
    universe (the runs' evaluation sets, reduced to the MAXIMAL ones)."""
    sets = set()
    for r in runs or ():
        s = frozenset(pc.expr for pc in r.path_conditions)
        if s:
            sets.add(s)
    out = set()
    for s in maximal_sets(sets):
        es = sorted(s)
        for i, a in enumerate(es):
            for b in es[i + 1:]:
                out.add(frozenset((a, b)))
    return out


def build(runs=None) -> AssumptionSet:
    assumptions = []

    # --- Argument 1: not_found forecloses closed_account + redirect, per arm (9 pairs) ---
    for guard, downstream in ((B, [C, D, E]), (F, [G, H, I, J, K, L])):
        for d in downstream:
            assumptions.append(_pair(guard, d, NOT_FOUND_FORECLOSES))

    # --- Argument 2: closed_account forecloses redirect, per arm (6 pairs) ---
    for closed, redir in ((C, [D, E]), (G, [H, I]), (J, [K, L])):
        for r in redir:
            assumptions.append(_pair(closed, r, CLOSED_ACCOUNT_FORECLOSES))

    # --- Argument 4: A vs every other OLD tracked var (11 pairs) ---
    for g in (B, C, D, E, F, G, H, I, J, K, L):
        assumptions.append(_pair(A, g, A_VS_ARM_FAMILY))

    # --- Argument 5: guid '!=' side untracked-true, per arm (3 pairs) ---
    for taken_true_expr in (E, I, L):
        assumptions.append(OneSideUntrackedPathAssumption(
            expr=taken_true_expr,
            tracked_side="not_taken",
            description="guid!='' can only ever be observed False (framework short-circuit)",
            agent_notes=GUID_TRUE_UNREACHABLE,
        ))

    # --- Argument 6 (NEW): guard family (B,C,F,G,J) forecloses ALL of NEW (5*8=40 pairs) ---
    for guard in (B, C, F, G, J):
        for n in NEW:
            assumptions.append(_pair(guard, n, GUARD_FORECLOSES_STREAM_BODY))

    # --- Argument 7 (NEW): A vs NEW, unrelated code paths (1*8=8 pairs) ---
    for n in NEW:
        assumptions.append(_pair(A, n, A_VS_STREAM_BODY))

    # CO-EVALUATION FILTER (2026-09-10). The engine demands a combination only
    # over decisions some run evaluated TOGETHER, so an independence over a
    # pair no run co-evaluates relaxes nothing. Four whole arguments went with
    # that rule — 3 (arm vs arm), 4b (TRUE-arm tier vs FALSE-arm tier), 8
    # (html-only vs json-only) and 9 (anon-json vs auth-json), 95 declared
    # pairs, every one of them a MUTUAL-EXCLUSION argument, i.e. exactly the
    # claim the engine now makes for itself. This filter drops any survivor
    # with the same property and says how many, so the deletions are auditable
    # rather than asserted.
    if runs is not None:
        coeval = _coeval_pairs(runs)
        kept, inert = [], 0
        for a in assumptions:
            if isinstance(a, IndependenceAssumption) and \
                    frozenset((a.expr_a, a.expr_b)) not in coeval:
                inert += 1
                continue
            kept.append(a)
        print(f"[assumptions] declared={len(kept)} "
              f"INERT(never-co-evaluated, not declared)={inert}", file=sys.stderr)
        assumptions = kept
    return AssumptionSet(assumptions=assumptions)


if __name__ == "__main__":
    print(build())
