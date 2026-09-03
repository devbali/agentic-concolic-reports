#!/usr/bin/env python3
"""people_stream -- batch-local combination-coverage assumptions.

Rewritten for the "make diaspora_id? steer" completion pass (results2, see
COMPLETION_BRIEF.md and this dir's REPORT.md "Central finding" /
"ADDENDUM (completion pass)"). targets.rb section 7's mock previously
returned a plain Ruby bool from a `declare_target` "Body-skip mode" lambda,
which `call_interceptor.rb`'s own wrapper re-wraps through `to_symbolic` --
`to_symbolic(false)` produces a truthy `SymbolicBool` OBJECT, so the bare
`if diaspora_id?(username)` in `find_person` ALWAYS took the true branch.
Fixed by returning `nil` on the false side (the one value `to_symbolic`
passes through unwrapped, symbolic_func.rb:166-170) -- see targets.rb
section 7's inline comment for the full before/after. All 20 dumps were
regenerated fresh; the corpus grew to 27 dumps as the newly-reachable false
branch's own sub-tree got explored by two DELIBERATE worklist roots per
scenario (run_dse.rb's `explore` -- the default root, and a "person_id
blank" probe root; see run_dse.rb's own comment for why the probe needs to
force diaspora_id? False in the SAME seed set, and why the probe root must
be pushed BEFORE the default root on the LIFO stack).

------------------------------------------------------------------
THE 12 TRACKED PC EXPRESSIONS (first-seen order; all "_1" ordinal --
find_person's before_action fires exactly once per run, confirmed identical
across all 27 dumps EXCEPT for one important caveat below):

    A = (SYM_RESULT_PeopleController_diaspora_id__1_result == True)

  -- TRUE arm (diaspora_id?==True): people_controller.rb:132
     `Person.where({diaspora_handle: username.downcase}).first`
    B = (SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)
    C = (SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account == True)
    D = (SYM_RESULT_ActiveRecord__FinderMethods_first_1_guid == '')
    E = (SYM_RESULT_ActiveRecord__FinderMethods_first_1_guid != StringVal(''))

  -- FALSE arm (diaspora_id?==False): people_controller.rb:134
     `Person.find_from_guid_or_username({id: params[:id]||params[:person_id],
     username: username})`, which (person.rb:196-206) is ITSELF an
     if/elsif/else that this endpoint's route makes GENUINELY reachable on
     both non-else arms (unlike people_show, where params[:id] is always nil
     -- see person_id ORDINAL CAVEAT below):
       id-guid arm   (params[:id].present?, TRUE by default -- person_id
                       defaults "1", non-blank): `Person.find_by(guid:
                       params[:id])`
    F = (SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found == True)
    G = (SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_closed_account == True)
    H = (SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_guid == '')
    I = (SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_guid != StringVal(''))

       username arm  (params[:id].present?==False -- only reachable via the
                       run_dse.rb probe root's forced person_id=""):
                       `User.find_by_username(username)` then `u.person`
    F = SAME EXPRESSION as above -- see ORDINAL CAVEAT
    J = (SYM_PERSON_via_user_closed_account == True)
    K = (SYM_PERSON_via_user_guid == '')
    L = (SYM_PERSON_via_user_guid != StringVal(''))

------------------------------------------------------------------
ORDINAL CAVEAT (COMPLETION_BRIEF's "verify each expr names one decision
across all runs" -- like conversations_index had to):

F is NOT a single decision. `finder_mock` (concolic_targets.rb ~365-378)
names its boundary vars purely from the declared TARGET's own per-run call
ordinal (`SYM_RESULT_<Klass>.<method>_<idx>`), and `Person.find_by` /
`User.find_by_username` both route through the SAME declared target
(`ActiveRecord::Core::ClassMethods.find_by` -- concolic_targets.rb's
"DESIGN #2", since `User.find_by_username` is an ActiveRecord dynamic
finder that resolves to `find_by(username: ...)`, confirmed in the probe
dump: call site `dynamic_matchers.rb:66 in find_by_username`, receiver
class never recorded). Since AT MOST ONE of {id-guid arm, username arm}
ever runs per request (person.rb:197-201's if/elsif), and each is the
FIRST (and only) `find_by` call in its own run, BOTH arms produce a PC
literally named `SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_
found` -- verified directly: dump_anon_all0008 (id-guid arm, person_id="1")
and dump_anon_all0028 (username arm, person_id="") both record this EXACT
expr string. This is a genuine framework-mock limitation (same class as the
already-documented `finder_mock` ordinal scheme), not a bug introduced by
this pass -- it does not corrupt completeness because:
  (a) F's downstream companions (G,H,I vs J,K,L) use DIFFERENT var names
      (id-guid arm's closed_account/guid come from finder_mock's own
      symbolic_instance columns keyed "find_by_1_*"; username arm's come
      from a SEPARATE symbolic_instance call, UserSymPersonAssociation's
      `SYM_PERSON_via_user_*`) -- so F=False's TWO possible continuations
      (G-family vs J-family) are still fully distinguishable and both
      independently demanded/witnessed below;
  (b) F=True (not_found) is a genuinely OBSERVATIONALLY IDENTICAL 2-PC
      trace (A=False, F=True, nothing else -- people_controller.rb:140's
      raise fires before ANY other var in either arm could be recorded) --
      the two runtime paths that produce it are equivalent under every
      TRACKED expression, so one witness legitimately covers both (same
      "prefix coverage" principle the main README documents) -- confirmed:
      dump_anon_all0013 (id-guid, F=True) and the deduped-away username
      F=True excursion are byte-for-byte the same abstract trace.
No assumption is needed to "fix" this -- it is accounted for by treating F
as what it observably is: one shared not_found gate whose own value is
always independently re-derivable from context, and by never assuming F
independent of G/H/I/J/K/L below (they stay genuinely DEPENDENT, i.e. no
assumption pair is declared between F and its own arm's closed_account/
guid vars -- the checker must and does see both witnessed values, e.g.
F=False+G=True (0011) and F=False+G=False (0008/0009) for the id-guid side,
F=False+J=True (0031) and F=False+J=False (0028/0029) for the username
side).

------------------------------------------------------------------
Argument 1 -- not_found forecloses closed_account AND the redirect body,
PER ARM (people_controller.rb:127-142, extending the pre-fix file's
Argument 1 from one arm to three; F is shared so it forecloses BOTH
downstream families at once):

    def find_person
      username = params[:username]
      @person = if diaspora_id?(username)
          Person.where({diaspora_handle: username.downcase}).first  # B decided here
        else
          Person.find_from_guid_or_username(...)                    # F decided here (either arm)
        end
      raise ActiveRecord::RecordNotFound if @person.nil?             # line 140
      raise Diaspora::AccountClosed if @person.closed_account?       # line 141 -> C/G/J
    end

`finder_mock(raise_on_missing: false)` does NOT raise when not_found; it
returns `nil` and lets the caller branch. B==True / F==True means
`@person` is `nil`, and line 140's raise fires immediately -- before line
141 (C/G/J) OR `stream`'s redirect body (D/E, H/I, K/L) ever run.
`find_person` is a `before_action`; the raise aborts the whole chain.
Verified empirically: every B==True dump (anon_json0004, auth_json0004,
anon_all0006) has exactly 2 PCs (A,B); every F==True dump (anon_all0013,
anon_json0009, auth_json0009) has exactly 2 PCs (A,F) -- C/G/H/I/J/K/L are
simply absent in all of them, never just "false".

Safety test (assumptions.py IndependenceAssumption docstring): can
(B or F ==True, C/D/E/G/H/I/J/K/L==<anything>) produce a call sequence the
individual branches don't? No -- the not_found branch's call sequence ends
at the line-140 raise; there is no execution in which not_found==True and
any downstream var is also decided. Provable mutual exclusion.

------------------------------------------------------------------
Argument 2 -- closed_account forecloses the redirect body, PER ARM
(people_controller.rb:141 again + stream's `format.all` body)

Symmetric to Argument 1, one level in: when not_found==False (person
found), line 141 evaluates `@person.closed_account?` (C/G/J). If True,
`Diaspora::AccountClosed` is raised right there, still inside the
`find_person` before_action -- `stream`'s body (where D/E, H/I, K/L are
read) never runs. Verified empirically: every C==True dump has exactly 3
PCs (A,B,C); every G==True dump has exactly 3 PCs (A,F,G); every J==True
dump has exactly 3 PCs (A,F,J) -- the arm's own redirect-pair vars never
appear.

------------------------------------------------------------------
Argument 3 -- cross-arm mutual exclusion, NEW for this pass
(person.rb:196-206's if/elsif/else, people_controller.rb:134's `else`
branch of the OUTER diaspora_id? if):

    def self.find_from_guid_or_username(params)
      p = if params[:id].present?                                    # NOT a tracked expr (concrete
            Person.find_by(guid: params[:id])                        #   decision, same documented
          elsif params[:username].present? && u = User.find_by_username(params[:username])
            u.person                                                 #   Ruby-truthiness pattern as
          else                                                       #   every other blank?/present?
            nil                                                      #   in this experiment -- see
          end                                                        #   run_dse.rb's build_params)
      raise ActiveRecord::RecordNotFound unless p.present?
      p
    end

The id-guid arm (G,H,I) and the username arm (J,K,L) are mutually exclusive
arms of the SAME if/elsif: `params[:id].present?` picks AT MOST ONE of
them per request, structurally, regardless of that decision itself not
being a tracked PC. No run can record a var from BOTH families -- confirmed
across all 27 dumps: every A==False dump has EITHER {F,G,H,I}-family vars
XOR {F,J,K,L}-family vars, never both. This is the SAME safety-test
criterion as Argument 1/2 ("different if/elif/else branches"), just
applied to an untracked-guard split instead of a tracked one -- the
exclusivity is proven by the source code's control flow, not by the guard
being observable.

------------------------------------------------------------------
Argument 4 -- A picks the arm-family (people_controller.rb:129-138's outer
if/else), paired against EVERY OTHER tracked var (all 11) -- NOT just the
guard tier. EMPIRICAL CORRECTION (first draft of this file only paired A
against the guard tier B,C,F,G,J, by analogy with results2/people_show's
GUARD_VS_BRANCH pattern; running the checker showed that analogy doesn't
hold here -- the checker's clique construction demands the FULL pairwise
product between every pair of distinct expressions unless BOTH members of
the pair have an explicit assumption between THEM specifically, so B-D
foreclosure + A-B independence does NOT imply A-D is covered). Since B/C/D/E
only exist on the diaspora_id?==True branch and F/G/H/I/J/K/L only exist on
the ==False branch (exactly one branch runs per request), A is mutually
exclusive with all 11, not just the 5 "guard" ones -- same citation as
Argument 1/3's safety test.

------------------------------------------------------------------
Argument 4b -- the TRUE-arm tier {B,C,D,E} vs the FALSE-arm tier
{F,G,H,I,J,K,L}, FULL cross product (28 pairs). Same EMPIRICAL CORRECTION
as Argument 4: B/C/D/E and F/G/H/I/J/K/L never co-occur in any run (they
sit on opposite sides of the SAME people_controller.rb:129-138 if/else as
A itself), so every cross pair needs its own explicit independence, not
just the guard-tier members.

------------------------------------------------------------------
Argument 5 -- guid comparison's "taken" (True) side is unreachable
(framework internals), PER ARM's own guid pair (D/E, H/I, K/L) -- verbatim
extension of the pre-fix file's Argument 3, which already fully analyzed
this for D/E; H/I and K/L are the SAME `@person.guid` read through the
SAME `ActionDispatch::Journey::Formatter#generate` call sites
(action_dispatch/journey/formatter.rb:40-41), just for a `@person` that
came from a different finder -- the formatter code path is identical
either way, so the same proof applies verbatim to all three pairs:

    # actionpack-5.2.4.3/lib/action_dispatch/journey/formatter.rb
    39   route.parts.reverse_each do |key|
    40     break if defaults[key].nil? && parameterized_parts[key].present?   # <- D/H/K, then break
    41     next if parameterized_parts[key].to_s != defaults[key].to_s        # <- E/I/L, only if line 40 did NOT break
    42     break if required_parts.include?(key)

- guid non-blank (D/H/K==False): `present?` is true, `defaults[key].nil?`
  is true (`:id` has no route default) -> line 40's `break` fires -> the
  loop exits before line 41 ever executes. E/I/L is not merely false, it
  is never evaluated at all. Confirmed: D==False dumps (anon_all0001/0031),
  H==False dumps (anon_all0008), K==False dumps (anon_all0028) all carry
  zero E/I/L events respectively.
- guid blank (D/H/K==True): line 41 runs: `guid.to_s != ''` is *forced*
  False by string equality itself, given guid IS `''`. Confirmed: the only
  dumps that reach E/I/L at all (anon_all0002, anon_all0009, anon_all0029)
  all record it False.

So each pair's "taken" (True) outcome is provably unreachable by ANY run --
OneSideUntrackedPathAssumption, tracked_side="not_taken", per pair.

------------------------------------------------------------------
UNCHANGED FROM THE PRE-FIX FILE: json-format dumps (anon_json, auth_json)
never reach ANY guid pair at all (format.json never generates a URL via
the Journey formatter) -- consistent with zero D/E/H/I/K/L events in every
anon_json/auth_json dump; not a separate assumption, just corroborating
evidence for Argument 5's html-only reach.
"""

from __future__ import annotations

import sys

sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.assumptions import (  # noqa: E402
    AssumptionSet,
    IndependenceAssumption,
    OneSideUntrackedPathAssumption,
)

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

NOT_FOUND_FORECLOSES = (
    "people_controller.rb:140 `raise ActiveRecord::RecordNotFound if "
    "@person.nil?` fires immediately when the finder_mock's not_found "
    "boundary decides True (finder_mock(raise_on_missing: false) itself "
    "returns nil rather than raising, letting the caller's line-140 raise "
    "fire) -- before line 141's closed_account? check or stream's own "
    "redirect body (both several statements later) ever run. Verified: "
    "every not_found==True dump has EXACTLY 2 PCs (A + the not_found var), "
    "nothing else."
)

CLOSED_ACCOUNT_FORECLOSES = (
    "people_controller.rb:141 `raise Diaspora::AccountClosed if "
    "@person.closed_account?` fires immediately when closed_account "
    "decides True, still inside the find_person before_action -- stream's "
    "redirect body (where the arm's guid pair is read) never runs. "
    "Verified: every closed_account==True dump has EXACTLY 3 PCs (A + "
    "not_found + closed_account), the arm's guid pair never appears."
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


def _pair(expr_a: str, expr_b: str, why: str) -> IndependenceAssumption:
    return IndependenceAssumption(
        expr_a=expr_a, expr_b=expr_b,
        description="mutually exclusive per app control flow -- see agent_notes",
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

    # --- Argument 4: A vs every other tracked var (11 pairs) ---
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

    return AssumptionSet(assumptions=assumptions)


if __name__ == "__main__":
    print(build())
