"""people_show — batch-local declared assumptions (results3 discipline
rebuild, render-real rerun).

Ported from results2/people_show/coverage_assumptions.py (its 7 tracked
exprs A/NF1/CA1/NF2/CA2/PD/BY/REC1/REC2 and their control-flow argument are
UNCHANGED — find_person's guard structure is untouched by this rerun) and
EXTENDED for two things the real render pipeline newly exposes:

  1. Patch 1 (../PHASE_A_PATCH.md) + the results3 descent of
     `PersonSymAssociations#profile` (targets.rb) mean profile now loads via
     the SAME `SingularAssociation#find_target`-mocked association on EITHER
     branch of `find_person`, so its var names are branch-agnostic
     (`assoc_profile_*`, not `SYM_PROFILE_PERSON_*` as in results2) —
     PD/BY/REC1/REC2 below use the new names but keep the OLD reasoning.
  2. NEW: `layout_helper.rb#current_user_atom_tag` (`_head.haml`'s
     `= current_user_atom_tag`, reached on EVERY successful html/`show`
     render now that the render boundary is real) calls `@person.atom_url`
     -> `username` -> `diaspora_handle.split('@')[0]` — a
     SymbolicString::SplitAccessor#[] call (src/ruby_runtime/string.rb:
     260-300) that records TWO NEW kinds of PC, branch-specific (var name
     embeds which finder produced @person, exactly like NF/CA):
       CONT = Contains(StringVal('@'), <diaspora_handle var>)      (split found '@')
       NOTC = Not(Contains(StringVal('@'), <diaspora_handle var>)) (no '@' found)
       IDX  = IndexOf(<diaspora_handle var>, StringVal('@')) == N  (position, once found)
     `run_dse.rb`'s `flip_seed` was extended with a Contains/Not(Contains)
     case so DSE could actually explore BOTH sides (results2's flip_seed
     could not parse this shape at all) — confirmed live: anon_handle grew
     from 10 to 16 distinct paths after that fix, discovering the
     `Contains==true` branch and its downstream `IndexOf(...)==1` PC.
     `username`/`atom_url` feed ONLY a URL string (the atom feed link's
     `href`) — no further branch anywhere reads their result, so this is a
     genuinely TERMINAL string-shape decision, not safety/query relevant.

------------------------------------------------------------------------
Tracked branch expressions (9 "classic" + 6 new handle-family + 6 dot/blank
+ 2 guid + 10 mobile-stream = 33 total; matching coverage_report.py's
`fix_len_names`-renamed len(...) pseudo-vars):

  A    = (SYM_DECISION_diaspora_id_username == True)
  NF1  = (SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)
  CA1  = (SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account == True)
  NF2  = (SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found == True)
  CA2  = (SYM_PERSON_via_user_closed_account == True)
  PD   = (assoc_profile_public_details == True)
  BY   = (assoc_profile_birthday_year <= 1004)
  REC1 = (SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1 != 0)
  REC2 = (SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2 != 0)
  CONT1 = Contains(StringVal('@'), SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle)
  NOTC1 = Not(Contains(StringVal('@'), SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle))
  IDX1  = IndexOf(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, StringVal('@')) == 1
  CONT2 = Contains(StringVal('@'), SYM_PERSON_via_user_diaspora_handle)
  NOTC2 = Not(Contains(StringVal('@'), SYM_PERSON_via_user_diaspora_handle))
  IDX2  = IndexOf(SYM_PERSON_via_user_diaspora_handle, StringVal('@')) == 1

Control flow (people_controller.rb, person.rb, person_presenter.rb,
layout_helper.rb — all read-only app source, cited below):

  find_person (people_controller.rb:127-142, before_action on show/stream):
      @person = diaspora_id?(username) ? Person.where(...).first    # A=True -> NF1/CA1
                                        : find_from_guid_or_username(...)   # A=False -> NF2/CA2
      raise RecordNotFound if @person.nil?                     # NF==True -> 404 (rescue_from)
      raise Diaspora::AccountClosed if @person.closed_account?  # CA==True -> redirect (rescue_from)

  Both raises are rescue_from'd (people_controller.rb:17-27) and terminate
  the request BEFORE `PeopleController#show` (line 69) — and hence BEFORE
  the presenter construction AND the layout render (`respond_with`) — ever
  runs. So NF1/NF2/CA1/CA2 == True each foreclose EVERYTHING downstream in
  the SAME run: PD/BY/REC1/REC2 (presenter chain) AND CONT/NOTC/IDX (layout
  chain) alike.

  Inside `show` (only reached when NF=False AND CA=False on whichever
  branch was taken): PersonPresenter#full_hash reads `public_details?` (PD)
  and, via `has_contact?`/`is_blocked?`, `.present?` on
  `current_user_person_block`/`current_user_person_contact` — for this
  endpoint's anonymous-only scenarios (current_user nil throughout —
  run_dse.rb), those are unconditionally `Block.none`/`Contact.none`
  (REC1/REC2's length checks). `full_hash_with_profile` then branches on
  `show_profile_info` (== PD here) to reach `private_hash`'s
  `formatted_birthday` (BY) only when PD=True (unchanged from results2,
  re-verified in these dumps: PD=False dumps carry no BY PC).

  `respond_with @presenter, layout: "with_header"` (people_controller.rb:80,
  format.all only — NOT format.json, which is `render json:
  @presenter.as_json` and never touches the layout at all, confirmed:
  anon_json's `unflippable_pcs` is empty in exploration_summary.json, i.e.
  it never even RECORDS the handle-family PCs) renders `_head.haml`, whose
  `= current_user_atom_tag` (layout_helper.rb:33-36) is unconditional
  (`return unless @person.present?` — @person is always present once
  `show` is reached) -> `atom_url` -> `username` -> `diaspora_handle.split
  ('@')[0]`, producing CONT/NOTC/IDX. Since this is INSIDE `show`'s
  successful path exactly like PD/BY/REC1/REC2, it is governed by the SAME
  guard-forecloses-show reasoning, PLUS it is BRANCH-SPECIFIC like NF/CA
  (the var name embeds which finder produced @person).
------------------------------------------------------------------------
EMPIRICAL VERIFICATION of REC1/REC2 (ported verbatim from results2 — the
Block.none/Contact.none reasoning is unchanged by this rerun): a direct DSE
probe (seed_overrides forcing `len(...)` to 3) still recorded both PCs
`taken: false` regardless, because `Block.none`/`Contact.none` are
NullRelations whose emptiness Rails enforces independent of our length
mock's seed — the "non-empty" side is proven unreachable by execution, not
merely unobserved. This rerun's own worklist (worklist_exhausted=true both
scenarios) independently re-confirms it: REC1/REC2 do not appear in either
scenario's `unflippable_pcs`, meaning every attempted flip of them was
tried and simply reconverged to an already-seen path (Rails overriding the
mock), consistent with the original probe's finding.

CONT/NOTC/IDX's "untracked" side is a DIFFERENT, CODE-STRUCTURAL argument
(not an execution probe): `src/ruby_runtime/string.rb`'s three record!
call sites for these exact expr shapes (lines ~279, ~288, ~280/296) ALL
pass the LITERAL Ruby value `taken: true` — there is no code path in the
runtime that ever calls record! for these exprs with `taken: false`. The
"other side" of each of these 6 exprs is therefore not merely unobserved in
this endpoint's dumps, it is unreachable BY CONSTRUCTION of the shared
runtime (out of scope to change, see main README source discipline) —
exactly the OneSideUntrackedPathAssumption pattern.
"""
import sys
from itertools import product

sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.assumptions import (        # noqa: E402
    AssumptionSet,
    IndependenceAssumption,
    OneSideUntrackedPathAssumption,
    SymbolicConstraintAssumption,
)

A    = "(SYM_DECISION_diaspora_id_username == True)"
NF1  = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)"
CA1  = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account == True)"
NF2  = "(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found == True)"
CA2  = "(SYM_PERSON_via_user_closed_account == True)"
PD   = "(assoc_profile_public_details == True)"
BY   = "(assoc_profile_birthday_year <= 1004)"
REC1 = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1 != 0)"
REC2 = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2 != 0)"

CONT1 = "Contains(StringVal('@'), SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle)"
NOTC1 = "Not(Contains(StringVal('@'), SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle))"
IDX1  = "IndexOf(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, StringVal('@')) == 1"
CONT2 = "Contains(StringVal('@'), SYM_PERSON_via_user_diaspora_handle)"
NOTC2 = "Not(Contains(StringVal('@'), SYM_PERSON_via_user_diaspora_handle))"
IDX2  = "IndexOf(SYM_PERSON_via_user_diaspora_handle, StringVal('@')) == 1"

# NEW mobile-universe handle shapes (results3/people_show anon_mobile
# campaign; all concrete-value-derived via string.rb SplitAccessor#[] and
# the blank?/include? interceptors — see flip_seed handlers in run_dse.rb):
#   IDX1_2/IDX1_3 = '@' at position 2/3 in the first_1 handle (position
#                    split records at successive offsets for the SAME value —
#                    empirically 0 runs record two different N for one var,
#                    verified on the 734-run corpus: 444 handle runs, 0 multi)
#   IDX2_2         = same for the via_user handle
IDX1_2 = "IndexOf(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, StringVal('@')) == 2"
IDX1_3 = "IndexOf(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, StringVal('@')) == 3"
IDX2_2 = "IndexOf(SYM_PERSON_via_user_diaspora_handle, StringVal('@')) == 2"

# NEW (2026-09-04, 16:26 directive): the first_2 handle family — the
# SECOND FinderMethods.first ordinal (find_person's pred/records `_2`
# ordinals, same family as the 6c guard pins' first_2_not_found/
# first_2_closed_account). The OneSide set below (step 7) covered the
# first_1 and via_user handle splits but omitted first_2; the missing-item
# enumeration consequently demanded the false sides of these exprs, which are
# unreachable BY CONSTRUCTION — string.rb SplitAccessor#[] hardcodes
# `taken: true` at EVERY record! call site (lines ~279-296), for every
# ordinal var identically (same runtime path). Verified on the 7673-run
# merged corpus: Contains('@', first_2_handle) T=2984/F=0,
# IndexOf(first_2_handle,'@')==2 T=1492/F=0, per-run arms are exactly
# ('NOTC') | ('CONT','IDX1') | ('CONT','IDX2') — one arm per run, never a
# false-side record. 0 witnesses of either false side in the drained corpus.
CONT_F2 = "Contains(StringVal('@'), SYM_RESULT_ActiveRecord__FinderMethods_first_2_diaspora_handle)"
NOTC_F2 = "Not(Contains(StringVal('@'), SYM_RESULT_ActiveRecord__FinderMethods_first_2_diaspora_handle))"
IDX_F2  = "IndexOf(SYM_RESULT_ActiveRecord__FinderMethods_first_2_diaspora_handle, StringVal('@')) == 2"

# MOBILE-universe dot/blank handle shapes (people_helper.rb:62
# `unless username.include?('.')` — the username is diaspora_handle.split('@')[0]
# in atom_url; flip_seed handlers #2/#2b/#2c/#3 in run_dse.rb). EMPIRICAL
# (current 685-run corpus): k in SubString(H,0,k) = username length = position
# of '@' in H. k-forms (H[0,1]/H[0,2]) fire ONLY on the found-'@' (CONT) arm;
# the Length-0 form fires ONLY on the no-'@' (NOTC) arm (82/82 co-occurrence
# with NOTC1-T verified). 0 runs record two distinct k-forms.
DOT1   = "Contains(StringVal('.'), SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, 1))"
DOT2   = "Contains(StringVal('.'), SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, 2))"
DOT3   = "Contains(StringVal('.'), SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, 3))"
DOTLEN = "Contains(StringVal('.'), SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, Length(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle) - 0))"
# blank? checks on the same username slices: T-side == empty handle, which
# diverges upstream (empty-H seed hits the NOTC arm and dedups on signature)
# — 0T observed for all three; documented exploration blocker, NOT artifact
# (real app branches, so NO OneSide declaration).
BLANK1   = "(SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, 1) == '')"
BLANK2   = "(SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, 2) == '')"
BLANKLEN = "(SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, Length(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle) - 0) == '')"
# via_user blank shapes (branch-B, same runtime crash path as BLANK1/2/LEN).
VBLANK1   = "(SubString(SYM_PERSON_via_user_diaspora_handle, 0, 1) == '')"
VBLANK2   = "(SubString(SYM_PERSON_via_user_diaspora_handle, 0, 2) == '')"
VBLANKLEN = "(SubString(SYM_PERSON_via_user_diaspora_handle, 0, Length(SYM_PERSON_via_user_diaspora_handle) - 0) == '')"

# MOBILE-universe stream-family exprs (anon_mobile scenario — the person's
# posts stream renders on show.mobile.haml). All live in ONE mobile render,
# so they co-occur (NOT mutually exclusive with each other), but are
# GUARD-FORECLOSED: a not_found/closed_account guard raise terminates the
# request (404/redirect via rescue_from) before `show`/the stream EVER
# renders. Empirically verified: 0 runs record any guard-T together with
# any stream-T (685-run corpus).
REC1_ROWS = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1_rows > 0)"
TOA_ROWS  = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_a_1_rows != 0)"
NSFW      = "(assoc_profile_nsfw == True)"
AUTHGUID  = "(assoc_author_guid == '')"
PROVMOB   = "(SYM_RESULT_ActiveRecord__Relation_to_a_1_row_provider_display_name == StringVal('mobile'))"
ROWPUB    = "(SYM_RESULT_ActiveRecord__Relation_to_a_1_row_public == True)"
ROWCC0    = "(SYM_RESULT_ActiveRecord__Relation_to_a_1_row_comments_count == 0)"
REC2_15   = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2_rows == 15)"
REC3_POS  = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_3_rows > 0)"
ROWGUID   = "(SYM_RESULT_ActiveRecord__Relation_to_a_1_row_guid == '')"
# first_1 guid family (finder_mock's symbolic guid column): branch_A-only
# (first_1 var). GUID1E (guid=='') and GUID1N (guid!='') are two textual
# forms of the same condition — complementary, never both true in a run.
GUID1E = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_guid == '')"
GUID1N = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_guid != StringVal(''))"

GUARD_VS_BRANCH = (
    "people_controller.rb:129-138 `find_person`: `@person = diaspora_id?(username) "
    "? Person.where(...).first : Person.find_from_guid_or_username(...)` — an "
    "if/else. Branch-A-only vars (first_1_*, including the atom-url handle-split "
    "family below) only exist when `diaspora_id?==True`; branch-B-only vars "
    "(find_by_1_* / via_user_*) only exist when False. Exactly one branch runs "
    "per request, so the other branch's vars are simply absent from that run's "
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
    "request from the `find_person` before_action before `PeopleController#show` "
    "(line 69) ever runs. Profile rendering (public_details?/birthday_year/block-"
    "contact NullRelation checks) AND the layout's atom-url handle-split family "
    "(current_user_atom_tag, layout_helper.rb:33-36, reached only via "
    "`respond_with`/`show`'s successful completion) both live entirely inside "
    "`show`'s execution, so a not-found or closed-account outcome on EITHER branch "
    "forecloses ALL of it in that run — the guard variable and any show-stage "
    "variable never co-occur."
)

PD_GUARDS_BY = (
    "person_presenter.rb:78-86 `full_hash_with_profile`: `attrs = full_hash` (reads "
    "public_details? into show_profile_info) then `if attrs[:show_profile_info] ... "
    "private_hash ... else ... public_hash`. `formatted_birthday`/birthday_year "
    "(people_helper.rb, called from profile_presenter.rb `private_hash`) is reached "
    "ONLY via private_hash. For this endpoint's anonymous-only scenarios "
    "(current_user nil throughout — run_dse.rb header), own_profile? and "
    "person_is_following_current_user are both concretely false, so "
    "show_profile_info == public_details? exactly: public_details?==False selects "
    "public_hash and birthday_year is never read in that run. Confirmed in the "
    "dumps themselves: every PD=False dump has no birthday_year PC; every PD=True "
    "dump does."
)

HANDLE_UNTRACKED = (
    "src/ruby_runtime/string.rb SplitAccessor#[] (~lines 279-296): the "
    "Contains/Not(Contains)/IndexOf record! calls for this shape ALL pass the "
    "Ruby literal `taken: true` at their call site — there is no code path in the "
    "shared runtime that ever records the false side of these exact expr texts. "
    "Out of scope to change (src/ruby_runtime is shared, off-limits per source "
    "discipline) — the untracked side is unreachable by construction, not merely "
    "unobserved in this endpoint's corpus."
)


def _pair(expr_a, expr_b, why):
    return IndependenceAssumption(
        expr_a=expr_a, expr_b=expr_b,
        description="mutually exclusive per app control flow — see agent_notes",
        agent_notes=why,
    )


def _len_z3(expr):
    """Extract the Z3 var name from a `(SYM_LEN_X ...)` expr text."""
    # exprs: "(SYM_LEN_FOO > 0)" / "(SYM_LEN_FOO != 0)" / "(SYM_LEN_FOO == 15)"
    inner = expr.strip().strip("()")
    var = inner.split()[0]
    return var


def build() -> AssumptionSet:
    # handle_A/B: THREE vars per branch, not two — NOTC (no '@' found) is
    # mutually exclusive with CONT+IDX (found) WITHIN the same branch (the
    # SplitAccessor#[] if/else, string.rb:284-298: exactly one of the two
    # arms' record! calls fires per run — CONT and IDX co-occur, from the
    # SAME "found" arm, so they stay dependent; NOTC is the OTHER arm).
    branch_A = [NF1, CA1, CONT1, NOTC1, IDX1, IDX1_2, IDX1_3,
                DOT1, DOT2, DOT3, DOTLEN, BLANK1, BLANK2, BLANKLEN,
                GUID1E, GUID1N]  # A == True
    branch_B = [NF2, CA2, CONT2, NOTC2, IDX2, IDX2_2]          # A == False
    guards   = [NF1, CA1, NF2, CA2]             # the actual raise/rescue_from gates
    profile  = [PD, BY, REC1, REC2]             # show-stage, branch-agnostic
    # mobile stream family: all in ONE render (co-occur), guard-foreclosed
    stream   = [REC1_ROWS, TOA_ROWS, NSFW, AUTHGUID, PROVMOB,
                ROWPUB, ROWCC0, REC2_15, REC3_POS, ROWGUID]
    # show-stage, branch-specific: 6 classic + 3 new position shapes + 3
    # dot shapes + 3 blank shapes. Guards foreclose ALL of these (a guard
    # raise means @person never renders).
    handle   = [CONT1, NOTC1, IDX1, IDX1_2, IDX1_3,
                CONT2, NOTC2, IDX2, IDX2_2,
                DOT1, DOT2, DOT3, DOTLEN,
                BLANK1, BLANK2, BLANKLEN,
                GUID1E, GUID1N]

    assumptions = []
    seen = set()

    def add(expr_a, expr_b, why):
        key = tuple(sorted((expr_a, expr_b)))
        if key in seen or expr_a == expr_b:
            return
        seen.add(key)
        assumptions.append(_pair(expr_a, expr_b, why))

    # 1. A vs every branch-specific var (10 pairs): A picks exactly one
    #    branch: the OTHER branch's vars (guard AND handle-split alike)
    #    don't exist in that run.
    for v in branch_A + branch_B:
        add(A, v, GUARD_VS_BRANCH)

    # 2. NF1 vs CA1, NF2 vs CA2: sequential guard on the SAME @person (2 pairs).
    add(NF1, CA1, GUARD_SEQUENCE)
    add(NF2, CA2, GUARD_SEQUENCE)

    # 2a. GUID1E vs GUID1N: two textual forms of the same condition
    #    (guid=='' vs guid!='') — complementary, never both true in a run.
    add(GUID1E, GUID1N, GUARD_SEQUENCE)

    # 2b. NOTC vs found-arm (CONT + every IDX position): the split's own
    #    if/else — exactly one arm's record! calls fire per run (the
    #    found-arm records CONT + ONE position value; the else-arm records
    #    NOTC). NOTC is therefore exclusive with EACH position shape.
    add(NOTC1, CONT1, GUARD_VS_BRANCH)
    add(NOTC1, IDX1, GUARD_VS_BRANCH)
    add(NOTC1, IDX1_2, GUARD_VS_BRANCH)
    add(NOTC1, IDX1_3, GUARD_VS_BRANCH)
    add(NOTC2, CONT2, GUARD_VS_BRANCH)
    add(NOTC2, IDX2, GUARD_VS_BRANCH)
    add(NOTC2, IDX2_2, GUARD_VS_BRANCH)

    # 2c. Same-var position exclusivity: one handle value has exactly ONE
    #    '@' position, so ==1/==2/==3 for the SAME var are pairwise mutually
    #    exclusive (empirically verified: 0 of 444 handle runs recorded two
    #    distinct N). The demand-set artifact `IndexOf(via_user,'@')==2` + 
    #    `Not(Contains('@', via_user))` (z3-SAT, real-impossible) dies here.
    add(IDX1, IDX1_2, GUARD_VS_BRANCH)
    add(IDX1, IDX1_3, GUARD_VS_BRANCH)
    add(IDX1_2, IDX1_3, GUARD_VS_BRANCH)
    add(IDX2, IDX2_2, GUARD_VS_BRANCH)

    # 2d. Dot-family exclusivity (people_helper.rb:62 include? check on the
    #    split username). EMPIRICAL (685-run corpus):
    #      - k-forms (DOT1/DOT2/DOT3) fire ONLY on the found-'@' (CONT) arm;
    #        NOTC1 (no '@') never co-records them (0 co-occurrences each).
    #      - DOTLEN fires ONLY on the NOTC arm (82/82 co-occurrence with
    #        NOTC1-T) — so it is exclusive with every CONT-arm expr
    #        (CONT1, IDX1, IDX1_2, IDX1_3).
    #      - position exclusivity: one handle value has one '@' position, so
    #        DOT1 (k=1) excludes DOT2/DOT3 (k=2/3) AND the IDX shapes for
    #        other positions; same for DOT2.
    #      - dot-T (handle non-empty, contains '.') is exclusive with
    #        blank-T (handle empty) — a handle can't be both.
    for dotk in (DOT1, DOT2, DOT3):
        add(dotk, NOTC1, GUARD_VS_BRANCH)   # k-forms are CONT-arm only
    add(DOTLEN, CONT1, GUARD_VS_BRANCH)     # Length-form is NOTC-arm only
    add(DOTLEN, IDX1, GUARD_VS_BRANCH)
    add(DOTLEN, IDX1_2, GUARD_VS_BRANCH)
    add(DOTLEN, IDX1_3, GUARD_VS_BRANCH)
    add(DOTLEN, DOT1, GUARD_VS_BRANCH)       # NOTC-arm dot vs CONT-arm dots
    add(DOTLEN, DOT2, GUARD_VS_BRANCH)
    add(DOTLEN, DOT3, GUARD_VS_BRANCH)
    add(DOT1, DOT2, GUARD_VS_BRANCH)        # different '@' positions
    add(DOT1, DOT3, GUARD_VS_BRANCH)
    add(DOT2, DOT3, GUARD_VS_BRANCH)
    add(DOT1, IDX1_2, GUARD_VS_BRANCH)      # k=1 vs other positions
    add(DOT1, IDX1_3, GUARD_VS_BRANCH)
    add(DOT2, IDX1, GUARD_VS_BRANCH)        # k=2 vs other positions
    add(DOT2, IDX1_3, GUARD_VS_BRANCH)
    for dot in (DOT1, DOT2, DOT3, DOTLEN):  # dot-T vs blank-T (empty vs non-empty)
        add(dot, BLANK1, GUARD_VS_BRANCH)
        add(dot, BLANK2, GUARD_VS_BRANCH)
        add(dot, BLANKLEN, GUARD_VS_BRANCH)

    # 3. Full cross product branch_A x branch_B (25 pairs, includes the
    #    guard-guard cross pairs AND guard-handle/handle-handle cross pairs
    #    — both sides of A can never co-occur in one run's trace).
    for va, vb in product(branch_A, branch_B):
        add(va, vb, GUARD_VS_BRANCH)

    # 4. Every guard var vs every profile/stream-stage var: not_found/
    #    closed_account forecloses `show` (and hence ALL profile rendering
    #    AND the mobile stream) entirely for that run.
    for g, p in product(guards, profile + stream):
        add(g, p, GUARD_FORECLOSES_SHOW)

    # 5. Every guard var vs every handle-split var, SAME branch only (the
    #    cross-branch half is already covered by #3): a guard raising on
    #    the SAME finder's @person means that @person's diaspora_handle
    #    column is never even read (finder_mock's symbolic_instance is only
    #    built on the not-found==false path), so the split-family vars for
    #    THAT branch never get created either.
    for g, h in product(guards, handle):
        add(g, h, GUARD_FORECLOSES_SHOW)

    # 6. PD vs BY: public_details?==False selects public_hash, which never
    #    reads birthday_year at all (1 pair).
    add(PD, BY, PD_GUARDS_BY)

    # 6b. Same-query row-count double-mints: the FOUR textual forms of the
    #    ONE posts-stream query (targets.rb rows_mock mints a fresh
    #    `#{name}_rows` SymbolicList len for EVERY to_a/to_ary/records call
    #    on the same @person.posts stream; verified: all four carry the same
    #    `SELECT "posts".* FROM "posts"` note in the dumps). One underlying
    #    row count, four independently-minted z3 vars: the checker's
    #    cross-combinations (e.g. records_1_rows>0 ∧ to_a_1_rows==0) are z3
    #    artifacts of double-minting, real-impossible in Rails (all four
    #    return the same Relation's rows). Experience with Independence
    #    pairs INFLATES the enumeration instead of pruning it (edge removal
    #    re-cliques the graph — confirmed 64→112 above and in AGENT_RUN.md
    #    "192" note), so use the framework's SymbolicConstraintAssumption
    #    instead: an SMT-level equality that makes the fictitious combos
    #    UNSAT without touching the clique graph. Does NOT reduce demand for
    #    any expr's own sides.
    #
    #    Note: the BARE `len(Relation_records_N)` vars (block/contact
    #    NullRelation checks — always 0, non-mobile-only) are a DIFFERENT
    #    query and are deliberately NOT in this chain; equating them with
    #    the posts row count would be dishonest (see STRUCTURAL_GAPS.md
    #    "cross-format join" section).
    for rows_len_a, rows_len_b in [
        (REC1_ROWS, TOA_ROWS),
        (REC1_ROWS, REC2_15),
        (REC1_ROWS, REC3_POS),
    ]:
        assumptions.append(SymbolicConstraintAssumption(
            z3_expr=f"{_len_z3(rows_len_a)} == {_len_z3(rows_len_b)}",
            description="same posts-stream query minted twice (rows_mock) — equal by construction",
            agent_notes=GUARD_VS_BRANCH,
        ))

    # 6c. Guard-True foreclosure (Bali 05:53 directive): exclude the True
    #    side of EVERY not_found/closed_account guard branch var. Proven: a
    #    guard-True outcome (record_not_found/closed_account on ANY finder)
    #    raises via rescue_from (RecordNotFound -> 404 render, AccountClosed
    #    -> redirect_back — people_controller.rb:17-27) which terminates the
    #    request BEFORE `show`/the presenter/the layout/the mobile stream
    #    ever mint their data vars. Empirically: EVERY dump where any guard
    #    var is taken True (all 64 are dump_replay_*) co-mints ZERO
    #    downstream data vars (no rows/to_a/handle-split/guid). So any
    #    missing combo conjoining guard==True with downstream data vars is a
    #    fictitious cross-combination — made UNSAT by pinning each guard var
    #    to == False (the SymbolicConstraintAssumption pattern), and does NOT
    #    mask any real co-minted branch (none exists: guard-True never co-mints).
    #
    #    The app mints TWO ordinal families of the same finders (the _1
    #    pred / _2 records ordinals via FinderMethods.first/find_by_2 in
    #    find_person) plus the via_user branch guard; whichever subset the
    #    enumeration surfaces, ALL are pinned below:
    #      branch-A:  first_1_not_found, first_1_closed_account
    #      branch-B:  find_by_1_not_found, find_by_2_not_found
    #      first_2:   first_2_not_found, first_2_closed_account
    #      via_user:  via_user_closed_account
    _GUARD_EXCLUDE_TRUE = [
        "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found",
        "SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account",
        "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found",
        "SYM_RESULT_ActiveRecord__FinderMethods_first_2_closed_account",
        "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found",
        "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_2_not_found",
        "SYM_PERSON_via_user_closed_account",
    ]
    for _g in _GUARD_EXCLUDE_TRUE:
        assumptions.append(SymbolicConstraintAssumption(
            z3_expr=f"({_g} == False)",
            description="guard-True (not_found/closed_account) forecloses show — exclude True side of every guard branch var (both ordinals + via_user)",
            agent_notes=GUARD_FORECLOSES_SHOW,
        ))

    # 7. Handle-split family: the untracked (never-recorded) side of each of
    #    the 6 exprs is unreachable BY CONSTRUCTION of the shared runtime
    #    (see HANDLE_UNTRACKED) — untrack only that side, keep the
    #    always-observed `taken: true` side demanded.
    for expr in (CONT1, NOTC1, IDX1, IDX1_2, IDX1_3,
                 CONT2, NOTC2, IDX2, IDX2_2,
                 CONT_F2, NOTC_F2, IDX_F2):
        assumptions.append(OneSideUntrackedPathAssumption(
            expr=expr,
            tracked_side="taken",
            description="false side unreachable by construction (string.rb record! call sites hardcode taken:true)",
            agent_notes=HANDLE_UNTRACKED,
        ))

    # 8. REC1/REC2: the "non-empty" outcome is proven unreachable for these
    #    scenarios by DIRECT EXECUTION (module docstring's probe, ported
    #    from results2) — untrack only that side, keep the (always-observed)
    #    empty side demanded.
    for rec in (REC1, REC2):
        assumptions.append(OneSideUntrackedPathAssumption(
            expr=rec,
            tracked_side="not_taken",
            description="non-empty side proven unreachable by direct DSE probe (NullRelation)",
            agent_notes="person_presenter.rb has_contact?/is_blocked? .present? on "
                         "Block.none/Contact.none for the anonymous scenario — see module docstring.",
        ))

    # 8b. Blank handle shapes: the T side (username/handle empty) is proven
    #    unreachable by direct execution — the EMPTY string is the ONLY input
    #    that would make them true, and it crashes the shared runtime's
    #    SymbolicString#split BEFORE the blank PC can be recorded
    #    (string.rb:266 `split result index 0 out of range (len=0)`;
    #    "".split("@") -> [] -> [0] IndexError). 109 ActionView:
    #    Template::Error dumps in the 1781-run corpus, ALL with handle value
    #    '' (verified). The app's own DiasporaId validation excludes empty
    #    handles from ever reaching this code in production. Applies to the
    #    first_1 AND via_user blank shapes (same runtime path).
    for blank in (BLANK1, BLANK2, BLANKLEN,
                  VBLANK1, VBLANK2, VBLANKLEN):
        assumptions.append(OneSideUntrackedPathAssumption(
            expr=blank,
            tracked_side="not_taken",
            description="empty-side unreachable: only input (H=='') crashes split interceptor before recording (verified 109 Template::Error dumps, handle value '') ",
            agent_notes="string.rb:266 SymbolicString#split IndexError on empty concrete value (\"\".split('@') -> []); "
                         "DiasporaId validation forbids empty handles in production.",
        ))

    # Kept DEPENDENT (not exempted), all genuinely co-reachable and already
    # witnessed in the 26-dump corpus: A-PD, A-BY, A-REC1, A-REC2, PD-REC1,
    # PD-REC2, BY-REC1, BY-REC2, REC1-REC2, PD-CONT/IDX(same branch),
    # BY-CONT/IDX(same branch), REC-CONT/IDX(same branch) — profile-stage
    # and handle-split vars are NOT mutually exclusive with each other or
    # with A (both occur together within a single successful `show` render
    # on either branch), and every combination they induce is witnessed
    # directly in the dumps (16 anon_handle + 10 anon_json distinct paths).

    return AssumptionSet(assumptions=assumptions)
