"""people_show — batch-local declared assumptions (results2 completion pass).

Every assumption here is keyed by EXPRESSION (see assumptions.py module
docstring / reports/diaspora/README.md "Declaring assumptions") and is
argued against the app code that hosts the decision, per
COMPLETION_BRIEF.md's safety test: "can any combination of the two
outcomes produce a call sequence/access pattern the individual outcomes
don't?"

------------------------------------------------------------------------
The seven tracked branch expressions in this endpoint (plus two length
pseudo-vars fixed up by coverage_report.py's fix_len_names — see there):

  A   = (SYM_DECISION_diaspora_id_username == True)
  NF1 = (SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)
  CA1 = (SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account == True)
  NF2 = (SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found == True)
  CA2 = (SYM_PERSON_via_user_closed_account == True)
  PD  = (SYM_PROFILE_PERSON_public_details == True)
  BY  = (SYM_PROFILE_PERSON_birthday_year <= 1004)
  REC1 = (SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1 != 0)
  REC2 = (SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2 != 0)

Control flow (people_controller.rb, person.rb, person_presenter.rb,
people_helper.rb — all read-only app source, cited below):

  find_person (people_controller.rb:127-142, before_action on show):
      @person = diaspora_id?(username) ? Person.where(...).first   # A=True -> NF1/CA1
                                        : find_from_guid_or_username(...)  # A=False -> NF2/CA2
      raise RecordNotFound if @person.nil?            # NF/NF2 == True -> 404, method returns via raise
      raise Diaspora::AccountClosed if @person.closed_account?   # CA1/CA2 == True -> redirect

  Both raises are rescue_from'd at the controller level (people_controller.rb
  17-27) and terminate the request BEFORE PeopleController#show (line 69) or
  any of its presenter code ever runs. So NF1/NF2/CA1/CA2 == True each
  foreclose everything downstream in the SAME run.

  Inside `show` (only reached when NF=False AND CA=False on whichever
  branch was taken): PersonPresenter#full_hash (person_presenter.rb:13-19)
  reads `public_details?` (PD) and, via `base_hash_with_contact` ->
  `has_contact?`/`is_blocked?` (person_presenter.rb:74,97-109), calls
  `.present?` on `current_user_person_block`/`current_user_person_contact`
  — for this endpoint's ONLY scenario (anonymous, current_user is nil in
  every run — run_dse.rb header), those are unconditionally `Block.none`/
  `Contact.none` (person_presenter.rb:97-98,101), i.e. real Rails
  NullRelations. REC1/REC2 are the length checks behind those two
  `.present?`/`.blank?` calls.

  full_hash_with_profile (person_presenter.rb:78-86) then branches on
  `attrs[:show_profile_info]` (== PD, since own_profile?/following are
  both concretely false for the anonymous scenario) to call either
  `private_hash` (PD=True — includes `formatted_birthday` ->
  people_helper.rb:20 `bday.year <= 1004`, i.e. BY) or `public_hash`
  (PD=False — birthday never read at all, BY doesn't exist in that run).

------------------------------------------------------------------------
EMPIRICAL VERIFICATION of REC1/REC2 (not just a source-reading argument):
a direct DSE probe (seed_overrides forcing
`len(SYM_RESULT_ActiveRecord__Relation_records_1/2)` to 3, i.e. clearly
non-empty) was run through the real harness
(/home/dev/.claude/jobs/302ac302/tmp/people_show_probe_records.rb via
concolic-slot) and the resulting dumps still recorded both PCs `taken:
false` (empty) regardless — because `Block.none`/`Contact.none` are
NullRelations whose emptiness Rails enforces independent of our length
mock's seed. The original prefix-directed worklist (exploration_summary.
json: worklist_exhausted=true, unflippable_pcs={}, run_errors={}) already
tried this flip as part of its normal traversal and converged to the same
10 paths, consistent with this. So the "non-empty" side of REC1/REC2 is
not merely unobserved — it is proven, by direct execution, unreachable in
this endpoint's only scenario. This is the ONE case in this file argued by
execution + code, not by code alone.
"""
import sys

sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.assumptions import (        # noqa: E402
    AssumptionSet,
    IndependenceAssumption,
    OneSideUntrackedPathAssumption,
)

A    = "(SYM_DECISION_diaspora_id_username == True)"
NF1  = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)"
CA1  = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account == True)"
NF2  = "(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found == True)"
CA2  = "(SYM_PERSON_via_user_closed_account == True)"
PD   = "(SYM_PROFILE_PERSON_public_details == True)"
BY   = "(SYM_PROFILE_PERSON_birthday_year <= 1004)"
REC1 = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1 != 0)"
REC2 = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2 != 0)"

GUARD_VS_BRANCH = (
    "people_controller.rb:129-138 `find_person`: `@person = diaspora_id?(username) "
    "? Person.where(...).first : Person.find_from_guid_or_username(...)` — an "
    "if/else. NF1/CA1 (first_1_*) only exist on the `diaspora_id?==True` branch; "
    "NF2/CA2 (find_by_1 / via_user_closed_account, from find_from_guid_or_username, "
    "person.rb:196-206) only exist on the `False` branch. Exactly one branch runs "
    "per request, so the other branch's guard PCs are simply absent from that run's "
    "trace — mutually exclusive per the IndependenceAssumption safety test's "
    "criterion 1 (\"different if/elif/else branches\")."
)

GUARD_SEQUENCE = (
    "people_controller.rb:140-141 `find_person`: `raise ActiveRecord::RecordNotFound "
    "if @person.nil?` then `raise Diaspora::AccountClosed if @person.closed_account?` "
    "— sequential guards on the SAME @person. If the first raises (not_found==True), "
    "the method exits before the second line ever executes, so the closed_account "
    "check's PC is never recorded in that run. Not-found and closed-account can never "
    "both appear in one run's trace."
)

GUARD_FORECLOSES_SHOW = (
    "people_controller.rb:17-27 `rescue_from ActiveRecord::RecordNotFound` (renders "
    "404) and `rescue_from Diaspora::AccountClosed` (redirects) both terminate the "
    "request from the `find_person` before_action (line 11) before `PeopleController#"
    "show` (line 69) ever runs. Profile rendering (public_details?, birthday_year, "
    "and the block/contact NullRelation checks) all live inside `show`'s presenter "
    "construction, so a not-found or closed-account outcome on EITHER branch "
    "forecloses all of it in that run — the guard variable and the profile variable "
    "never co-occur."
)

PD_GUARDS_BY = (
    "person_presenter.rb:78-86 `full_hash_with_profile`: `attrs = full_hash` (reads "
    "public_details? into show_profile_info) then `if attrs[:show_profile_info] ... "
    "private_hash ... else ... public_hash`. `formatted_birthday`/birthday_year "
    "(people_helper.rb:20-25, called from profile_presenter.rb:37 `private_hash`) is "
    "reached ONLY via private_hash. For this endpoint's anonymous-only scenario "
    "(current_user nil throughout — run_dse.rb header), own_profile? and "
    "person_is_following_current_user are both concretely false, so "
    "show_profile_info == public_details? exactly: public_details?==False selects "
    "public_hash and birthday_year is never read in that run. Confirmed in the dumps "
    "themselves: dump_anon_handle_0001 (PD=False) has no birthday_year PC at all; "
    "0002/0003/0016/0017 (PD=True) all do."
)

REC_ALWAYS_WITH_PROFILE_STAGE = (
    "person_presenter.rb:16,74,97-101: `is_blocked?`/`has_contact?` (evaluated "
    "unconditionally inside full_hash, same call as public_details?) call `.present?` "
    "on `current_user_person_block`/`current_user_person_contact`, which for the "
    "anonymous scenario are always `Block.none`/`Contact.none` — reached at the same "
    "point as public_details?, gated by the same NF/CA guards, but not gated BY "
    "public_details? itself (present in dumps with PD=True and PD=False alike)."
)


def _pair(expr_a, expr_b, why):
    return IndependenceAssumption(
        expr_a=expr_a, expr_b=expr_b,
        description="mutually exclusive per app control flow — see agent_notes",
        agent_notes=why,
    )


def build() -> AssumptionSet:
    guards_A_side = [NF1, CA1]
    guards_B_side = [NF2, CA2]
    all_guards = guards_A_side + guards_B_side
    profile_exprs = [PD, BY, REC1, REC2]

    assumptions = []

    # 1. A vs every guard var: A picks exactly one branch, the OTHER branch's
    #    guard vars don't exist in that run. (4 pairs)
    for g in all_guards:
        assumptions.append(_pair(A, g, GUARD_VS_BRANCH))

    # 2. NF1 vs CA1, NF2 vs CA2: sequential guard, not_found forecloses the
    #    closed_account check on the SAME @person. (2 pairs)
    assumptions.append(_pair(NF1, CA1, GUARD_SEQUENCE))
    assumptions.append(_pair(NF2, CA2, GUARD_SEQUENCE))

    # 3. Cross-branch guard pairs (NF1/CA1 vs NF2/CA2): both sides are on
    #    mutually exclusive branches of the SAME if/else as #1. (4 pairs)
    for g1 in guards_A_side:
        for g2 in guards_B_side:
            assumptions.append(_pair(g1, g2, GUARD_VS_BRANCH))

    # 4. Every guard var vs every profile-stage var (PD, BY, REC1, REC2):
    #    not_found/closed_account forecloses `show` (and hence all profile
    #    rendering) entirely for that run. (4 guards x 4 profile = 16 pairs)
    for g in all_guards:
        for p in profile_exprs:
            assumptions.append(_pair(g, p, GUARD_FORECLOSES_SHOW))

    # 5. PD vs BY: public_details?==False selects public_hash, which never
    #    reads birthday_year at all. (1 pair)
    assumptions.append(_pair(PD, BY, PD_GUARDS_BY))

    # Total independence pairs: 4 + 2 + 4 + 16 + 1 = 27.
    # Kept DEPENDENT (not exempted): A-PD, A-BY, A-REC1, A-REC2, PD-REC1,
    # PD-REC2, BY-REC1, BY-REC2, REC1-REC2 — all genuinely co-reachable
    # combinations (profile stage reachable under either branch, with REC1/
    # REC2 reached alongside PD regardless of PD's own value), and every
    # combo they induce is already witnessed in the existing 10 dumps.

    # 6. REC1/REC2: the "non-empty" outcome is proven unreachable for this
    #    scenario by DIRECT EXECUTION (see module docstring's probe) — untrack
    #    only that side, keep the (always-observed) empty side demanded.
    for rec in (REC1, REC2):
        assumptions.append(OneSideUntrackedPathAssumption(
            expr=rec,
            tracked_side="not_taken",
            description="non-empty side proven unreachable by direct DSE probe (NullRelation)",
            agent_notes=REC_ALWAYS_WITH_PROFILE_STAGE,
        ))

    return AssumptionSet(assumptions=assumptions)
