"""conversations_index — batch-local declared assumptions.

Every assumption here is an ``IndependenceAssumption`` closing a guard-
truncation combo: a PC that is only ever EVALUATED inside the ``if``
branch gated by another PC's TRUE/found outcome, so the crossed combo
(outer guard on the "skip" side + inner PC observed at all) can never be
produced by any execution — Z3 doesn't know that, so without the
assumption it reports the combo "missing" forever.

App code cited (read-only; nothing here edits it):

  app/controllers/conversations_controller.rb, #index (lines 13-24):

      if params[:conversation_id]
        @conversation = Conversation.joins(...).where(...).first   # -> A
        if @conversation
          @first_unread_message_id = @conversation.first_unread_message(current_user).try(:id)
          @conversation.set_read(current_user)
        end
      end

  app/models/conversation.rb:

      def first_unread_message(user)                                # line 31
        if visibility = self.conversation_visibilities.where(...).first   # -> B
          self.messages.to_a[-visibility.unread]                    # -> C
        end
      end

      def set_read(user)                                            # line 37
        visibility = conversation_visibilities.find_by(...)         # -> D
        return unless visibility
        ...
      end

Expression identities (all recorded at the shared FinderMethods mock
boundary in concolic_targets.rb, hence keyed by `expr` per
src/concolic_engine/assumptions.py's "Identifying a path condition" and
reports/diaspora/README.md "Declaring assumptions" — NOT by source, since
every finder decision shares one mock source line):

  A = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)"
      Conversation.joins(...).where(...).first  (line 14-18, the action's
      own conversation_id lookup)
  B = "(SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found == True)"
      conversation_visibilities.where(person_id:...).where('unread > 0').first
      (conversation.rb:32, inside first_unread_message)
  C = "((- SYM_RESULT_ActiveRecord__FinderMethods_first_2_unread) == 0)"
      messages.to_a[-visibility.unread] index check (conversation.rb:33,
      SampledList#[] in targets.rb records `((- VAR) == 0)` for idx==0)
  D = "(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found == True)"
      conversation_visibilities.find_by(person_id:...) (conversation.rb:38,
      inside set_read)

Per-run ordinal caveat (assumptions.py, README "Declaring assumptions") — a
REAL bug this pass found and fixed, not just verified: `SYM_RESULT_..._N`
ordinals are per (class, method) call counters shared by EVERY invocation of
that target in the process (src/ruby_runtime/call_interceptor.rb:138,
`SymbolicFunc.next_call_idx(func_name)`). The generic FinderMethods#first
mock is one such shared target, and this action calls `.first` at up to
THREE call sites (the action's own lookup, first_unread_message's visibility
lookup, and — only in the JSON format branch —
`@visibilities.map(&:conversation)`'s per-visibility lookup, see
ConvoSymAssociations#conversation in targets.rb). Depending on which of the
first two fired earlier in a given run, the THIRD call site's ordinal
silently shifted: `first_3` in `format=json + conversation found` runs,
`first_2` in `format=json + conversation NOT found` runs (colliding
TEXTUALLY with the visibility lookup's own name, B, above — a different
decision wearing B's name), and `first_1` in `format=json`, no `cid` runs
(colliding with A's name). A checker fed that mix would silently conflate
three unrelated decisions into one node. FIX (targets.rb `install!`):
`@visibilities.map(&:conversation)` now calls a dedicated
`convidx_conv_lookup` target (aliased off `.first`'s behaviour via
`ConcolicTargets.finder_mock`, declared separately so it gets its own
per-run counter) instead of `.first` directly — it is always
`SYM_RESULT_ActiveRecord__Relation_convidx_conv_lookup_1_not_found` in every
run that reaches it, regardless of prefix. Verified across every
`dump_json_*` in this directory (json_plain and json_withcid, both
regenerated after the fix). `first_1`/`first_2`/`find_by_1` remain
unambiguous: verified across every dump that `first_1` is always the
action's own @conversation lookup (the only `first` call before
first_unread_message can run), `first_2` is always
first_unread_message's visibility lookup, and `find_by_1` is always
set_read's — all three, when they fire at all, fire in that fixed textual
order within the SAME `if @conversation` block, and (post-fix) no other
`first`/`find_by` call in this action can land before or between them.
`convidx_conv_lookup_1` (E below) does NOT sit inside the
params[:conversation_id] guard,
so it genuinely combines with A/B/C/D in json_withcid runs and is not
independent of them.

Safety test applied to each pair below (assumptions.py
IndependenceAssumption docstring): "can any combination of the two
outcomes produce a call sequence/access pattern the individual outcomes
don't?" — No: the second expression of every pair is UNREACHABLE code
whenever the first is on its "guard fails" side, so the "both evaluated"
call sequence the combo would need literally cannot be constructed. The
pair's other combos (first expr on its "guard passes" side) remain fully
demanded because both A=False and (whichever of B/D) fire in the SAME
run whenever the guard passes — that requirement is not weakened by
dropping the cross-edge to the impossible side, it is unaffected by it.
"""

from __future__ import annotations

from concolic_engine.assumptions import AssumptionSet, IndependenceAssumption

EXPR_A = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)"
EXPR_B = "(SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found == True)"
EXPR_C = "((- SYM_RESULT_ActiveRecord__FinderMethods_first_2_unread) == 0)"
EXPR_D = "(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found == True)"

# contacts_data (conversations_controller.rb:114-120) pluck-column blank
# checks. Person.name_from_attrs(first_name, last_name, diaspora_handle)
# (app/models/person.rb:254-255):
#
#   first_name.blank? && last_name.blank? ? diaspora_handle : "#{...}".strip
#
# P1 = first_name.blank?, P2 = last_name.blank? (short-circuit `&&`: only
# evaluated when P1==True), P3 = diaspora_handle.blank? — NOT checked in
# name_from_attrs itself; it fires downstream, when the ternary's TRUE arm
# (P1==True AND P2==True) returns the still-symbolic `diaspora_handle`,
# which flows into ERB::Util.h -> ActiveSupport's unwrapped_html_escape ->
# Multibyte::Unicode.tidy_bytes, whose fast path itself blank?-checks its
# input (confirmed empirically: the pluck3 PC's recorded source is
# unicode.rb:227 in tidy_bytes, NOT blank.rb like P1/P2 -- see a
# dump_json_withcid_*.json with pluck1/pluck2 both taken=True). When the
# ternary's FALSE arm is taken instead (P1==False, or P1==True with
# P2==False), name_from_attrs returns a freshly-interpolated PLAIN (non-
# symbolic) string, so tidy_bytes never sees `diaspora_handle` and P3
# records no PC at all in that run.
EXPR_P1 = "(SYM_RESULT_ActiveRecord__Calculations_pluck_1_pluck1_first_name == '')"
EXPR_P2 = "(SYM_RESULT_ActiveRecord__Calculations_pluck_1_pluck2_last_name == '')"
EXPR_P3 = "(SYM_RESULT_ActiveRecord__Calculations_pluck_1_pluck3_diaspora_handle == '')"


def build() -> AssumptionSet:
    aset = AssumptionSet()

    aset.add(IndependenceAssumption(
        expr_a=EXPR_A, expr_b=EXPR_B,
        description="A(conversation not found) || B(visibility not found)",
        agent_notes=(
            "B is conversation.rb:32's conversation_visibilities.first, called "
            "only from first_unread_message(user), which conversations_controller.rb:21 "
            "calls only inside `if @conversation` (line 20) i.e. only when A==False "
            "(conversation WAS found). When A==True the whole `if @conversation` body "
            "is skipped and B is never evaluated in that run -- (A=True, B=*) cannot "
            "occur. (A=False, B=*) is unaffected: both fire together in every run that "
            "enters the guard, so that combo is still demanded via the {B,find_by_1,"
            "convidx_conv_lookup_1} clique the checker forms after this edge is dropped."
        ),
    ))
    aset.add(IndependenceAssumption(
        expr_a=EXPR_A, expr_b=EXPR_C,
        description="A(conversation not found) || C(first-unread index == 0)",
        agent_notes=(
            "C is conversation.rb:33's `messages.to_a[-visibility.unread]` index "
            "check, reached only after both A==False AND B==False (see the B-C "
            "assumption below). A==True skips the entire first_unread_message call, "
            "so C never evaluates -- (A=True, C=*) is unreachable. Transitively "
            "implied by A-B and B-C, declared explicitly since the checker's "
            "dependence graph is over expression PAIRS, not transitive closures."
        ),
    ))
    aset.add(IndependenceAssumption(
        expr_a=EXPR_A, expr_b=EXPR_D,
        description="A(conversation not found) || D(set_read visibility not found)",
        agent_notes=(
            "D is conversation.rb:38's set_read(user) -> conversation_visibilities."
            "find_by(person_id:...), called by conversations_controller.rb:22 only "
            "inside the same `if @conversation` guard as B (line 20). A==True skips "
            "set_read entirely -- (A=True, D=*) is unreachable, same argument as A-B."
        ),
    ))
    aset.add(IndependenceAssumption(
        expr_a=EXPR_B, expr_b=EXPR_C,
        description="B(visibility not found) || C(first-unread index == 0)",
        agent_notes=(
            "C only executes inside `if visibility = ...first` (conversation.rb:32-33) "
            "-- i.e. only when B==False (a visibility WAS found and bound to the local "
            "`visibility`). When B==True the `if` body never runs and C is never "
            "evaluated -- (B=True, C=*) is unreachable. (B=False, C=*) is unaffected: "
            "whenever C fires, B is False in that same run by construction, so the "
            "demand is still satisfied by real runs; the checker regroups C into the "
            "{C, find_by_1, convidx_conv_lookup_1} clique with B dropped, and every combo there is "
            "still fully demanded and, per REPORT.md, closed by execution."
        ),
    ))

    aset.add(IndependenceAssumption(
        expr_a=EXPR_P1, expr_b=EXPR_P2,
        description="P1(first_name blank) || P2(last_name blank)",
        agent_notes=(
            "person.rb:255: `first_name.blank? && last_name.blank? ? ...`. Ruby's "
            "`&&` short-circuits -- P2 (last_name.blank?) is only evaluated when "
            "P1==True. (P1=False, P2=*) is unreachable: no PC for P2 is even "
            "recorded in a run where P1 is False. (P1=True, P2=*) is unaffected -- "
            "both fire in the same run whenever P1 is True, so that combo stays "
            "demanded via whichever clique P1/P2 land in with the A-E finder exprs "
            "(both remain fully cross-connected to A-E; only the P1-P2-P3 trio's "
            "internal edges are pruned here)."
        ),
    ))
    aset.add(IndependenceAssumption(
        expr_a=EXPR_P1, expr_b=EXPR_P3,
        description="P1(first_name blank) || P3(diaspora_handle blank, via tidy_bytes)",
        agent_notes=(
            "P3 only fires when the name_from_attrs ternary takes its TRUE arm, "
            "which requires P1==True (see EXPR_P3 comment above). (P1=False, P3=*) "
            "is unreachable -- P1=False forces the ternary's FALSE arm, whose "
            "interpolated result is a plain (non-symbolic) string, so tidy_bytes "
            "never even sees a trackable value and P3 is not recorded."
        ),
    ))
    aset.add(IndependenceAssumption(
        expr_a=EXPR_P2, expr_b=EXPR_P3,
        description="P2(last_name blank) || P3(diaspora_handle blank, via tidy_bytes)",
        agent_notes=(
            "Same ternary guard as P1-P3: the TRUE arm (which alone reaches P3) "
            "requires P1==True AND P2==True. (P2=False, P3=*) is unreachable for "
            "the identical reason -- P2=False forces the FALSE arm, no symbolic "
            "value reaches tidy_bytes, no PC for P3."
        ),
    ))

    return aset
