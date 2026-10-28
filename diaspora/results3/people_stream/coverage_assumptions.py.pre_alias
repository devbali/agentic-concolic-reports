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
)

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

ARM_VS_ARM = (
    "person.rb:196-206 `find_from_guid_or_username`'s "
    "`if params[:id].present? ... elsif params[:username].present? && u = "
    "User.find_by_username(...) ... else nil end` -- an if/elsif whose two "
    "non-else arms (id-guid via Person.find_by(guid:) vs username via "
    "User.find_by_username+u.person) are mutually exclusive per request, "
    "structurally, independent of params[:id].present? itself not being a "
    "tracked PC (same documented Ruby-truthiness-decides-concretely "
    "pattern as every other blank?/present? call in this experiment -- "
    "run_dse.rb build_params). Confirmed: no dump ever records vars from "
    "both the {find_by_1_closed_account,find_by_1_guid} family and the "
    "{SYM_PERSON_via_user_closed_account,SYM_PERSON_via_user_guid} family "
    "together."
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

SCENARIO_MUTUAL_EXCLUSION = (
    "R1T/R1C (`records_1_row_*`) and the auth-only cluster {FB1, FB2, R4T, "
    "R4G, R4C} never co-occur in any run, VERIFIED empirically (grepped the "
    "full corpus's path_condition events by scenario prefix): records_1_row "
    "vars appear ONLY in anon_json dumps, the auth-only cluster appears "
    "ONLY in auth_json dumps. Root cause: `Stream::Base#like_posts_for_"
    "stream!` (lib/stream/base.rb) `return posts unless @user` -- the ENTIRE "
    "post_ids/attach_user_likes/Like.where chain (which is what produces "
    "FB1 and, via ordinal-shifting the outer stream_posts.map's own "
    "#records call to '_4' instead of '_1', R4T/R4G/R4C too) is SQL-free "
    "no-op for anon (@user is nil in anon_json/anon_all -- run_dse.rb's "
    "SCENARIOS/run_one) and only actually queries when a signed-in "
    "@user is present (auth_json). `Post#reshare_for` (FB2, post.rb) has "
    "its own explicit `return unless user` guard, same root cause. This is "
    "a scenario-level mutual exclusion (run_dse.rb's `signed_in` flag is "
    "FIXED per scenario, never flips within one run), the same class of "
    "argument as FORMAT_MUTUAL_EXCLUSION below, just keyed on user "
    "identity presence instead of response format."
)

FORMAT_MUTUAL_EXCLUSION = (
    "PeopleController#stream's `respond_to do |format| format.all { "
    "redirect_to ... }; format.json { render json: ... } end` "
    "(mime_responds.rb `Collector#negotiate_format` -> `request.negotiate_"
    "mime`) resolves to EXACTLY ONE format per request. D/E/H/I/K/L are "
    "read only by the html arm's `person_path(@person)` route generation "
    "(ActionDispatch::Journey::Formatter, only invoked for a redirect); the "
    "8 NEW vars are read only by the json arm's real render pipeline. A "
    "single run's request.format is fixed per scenario (anon_all is html, "
    "anon_json/auth_json are json -- run_dse.rb SCENARIOS), so no run ever "
    "records a var from both families -- confirmed: zero dumps in the "
    "corpus contain both a guid-pair var and any NEW var."
)


def _pair(expr_a: str, expr_b: str, why: str) -> IndependenceAssumption:
    return IndependenceAssumption(
        expr_a=expr_a, expr_b=expr_b,
        description="mutually exclusive / foreclosed per app control flow -- see agent_notes",
        agent_notes=why,
    )


def build() -> AssumptionSet:
    assumptions = []

    # --- Argument 1: not_found forecloses closed_account + redirect, per arm (9 pairs) ---
    for guard, downstream in ((B, [C, D, E]), (F, [G, H, I, J, K, L])):
        for d in downstream:
            assumptions.append(_pair(guard, d, NOT_FOUND_FORECLOSES))

    # --- Argument 2: closed_account forecloses redirect, per arm (6 pairs) ---
    for closed, redir in ((C, [D, E]), (G, [H, I]), (J, [K, L])):
        for r in redir:
            assumptions.append(_pair(closed, r, CLOSED_ACCOUNT_FORECLOSES))

    # --- Argument 3: id-guid arm vs username arm, all cross pairs (9 pairs) ---
    for x in (G, H, I):
        for y in (J, K, L):
            assumptions.append(_pair(x, y, ARM_VS_ARM))

    # --- Argument 4: A vs every other OLD tracked var (11 pairs) ---
    for g in (B, C, D, E, F, G, H, I, J, K, L):
        assumptions.append(_pair(A, g, A_VS_ARM_FAMILY))

    # --- Argument 4b: TRUE-arm tier vs FALSE-arm tier, full cross (28 pairs) ---
    for t in (B, C, D, E):
        for f in (F, G, H, I, J, K, L):
            assumptions.append(_pair(t, f, A_VS_ARM_FAMILY))

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

    # --- Argument 8 (NEW): html-only guid pairs vs NEW (json-only), mutually
    #     exclusive response formats (6*8=48 pairs) ---
    for html_var in (D, E, H, I, K, L):
        for n in NEW:
            assumptions.append(_pair(html_var, n, FORMAT_MUTUAL_EXCLUSION))

    # --- Argument 9 (NEW): anon-json-only R1 family vs auth-json-only
    #     cluster, mutually exclusive per signed_in scenario (2*5=10 pairs) ---
    for r1 in (R1T, R1C):
        for auth_only in (FB1, FB2, R4T, R4G, R4C):
            assumptions.append(_pair(r1, auth_only, SCENARIO_MUTUAL_EXCLUSION))

    return AssumptionSet(assumptions=assumptions)


if __name__ == "__main__":
    print(build())
