"""conversations_index — batch-local AssumptionSet (results3 completion pass,
2026-08-18, resuming work that died the previous night to an OOM kill).

STARTING POINT: the prior pass's 7 assumptions (A x B / A x C / A x D guard
truncation on conversations_controller.rb:13-24 + conversation.rb:31-38, and
P1 x P2 / P1 x P3 / P2 x P3 on person.rb:254-255 name_from_attrs) are CORRECT
and KEPT verbatim below. What was missing: this endpoint's real view layer
(results3's mock-surface discipline removed the render-family no-ops, so
_conversation.haml / _show.haml / _messages.haml now execute for real) opened
a SECOND generation of exprs — count_N/records_N/to_a_N/size_N/SYM_LEN_*
families minted by IterableSymbolicList (targets.rb `to_a`/`records` mocks)
and by `Calculations#count`/`#size` — that NO assumption connected to
anything. With only the 7 old assumptions, the checker forms ONE 30-expr
clique and demands the full cross product, most of which is structurally
impossible (see the missing-combo samples this pass started from: e.g.
`first_1_not_found==True` ANDed with a dozen exprs that only exist when the
conversation WAS found).

METHOD (per the coordinator's instruction: tiers must be re-derived against
this endpoint's own code and universe, never copied blind): for every
candidate guard pairing below, this pass (1) read the real guarding code
(conversations_controller.rb, conversation.rb, targets.rb, and the haml
views/partials — index.haml, _conversation.haml, _show.haml, _messages.haml,
_message.html.haml) to state the structural argument, THEN (2) ran a
streaming, low-memory verification over all 3,009 dumps in this directory
confirming the guard's foreclosed side NEVER co-occurs with the "attribute"
side in any single run's recorded path conditions — i.e. empirical proof
alongside the code argument, the same combined standard `results3/posts_show`
uses. Every one of the NEW pairings below passed with 0/3,009 violations
before being declared.

A REAL DANGER THIS PASS FOUND (and worked around, not silently): the
`to_a`/`records`/`count`/`size` targets share ONE per-(class,method) call
counter across the WHOLE request (`src/ruby_runtime/call_interceptor.rb`'s
`SymbolicFunc.next_call_idx`), same root cause as the ordinal-instability the
prior pass already found for `.first` (see the "Per-run ordinal caveat"
section below, kept). Verified this ALSO affects `to_a`/`records`/`count`:
`to_a_2` denotes `@visibilities.to_a` (the sidebar collection materialize) in
runs where the sidebar list is non-empty, but denotes `conversation.messages.
to_a` (`_messages.haml`, a DIFFERENT call site) in runs where the sidebar
list is EMPTY (so the sidebar's own `to_a` call never happens, shifting every
later ordinal down by one) — proven by a direct counter-example: a
`count_1_count > 0 == False` run (`dump_html_withcid_dse10127.json`) that
STILL records `to_a_2_row_text_has_mention` / `len(to_a_2_rows)`, `records_1_
row_id == SYM_PERSON_CONV_id` (that dump's `records_1` is `_show.haml`'s
`for participant in conversation.participants` loop, NOT `ordered_
participants`'s `messages.map(&:author)` — the SAME real call site the OTHER
dumps number `records_3`). CONSEQUENCE: an assumption naming `count_1`
(`@visibilities.count > 0`) as a guard for `to_a_2`/`records_1`/etc. by
ordinal would be UNSOUND — it would silently exempt combinations that a
DIFFERENT run's ordinal-2/-1 call genuinely produces. This pass therefore
does NOT declare any count_1-keyed family cut; that residual is left fully
connected and reported honestly (see REPORT.md) rather than forcing an
assumption the corpus itself disproves. The `to_a_1` / `convidx_conv_lookup_1`
/ `first_1` / `first_2` / `find_by_1` / `last_1` names remain trustworthy
ordinals because each is EITHER a dedicated per-target counter
(`convidx_conv_lookup`, fixed by the prior pass) OR structurally always the
temporally-first call of its shared counter along the only code path that can
reach it before anything else shares that counter (verified empirically too,
0 violations — see the tier functions' docstrings).

A SECOND FINDING: `results3/posts_show`'s Tier 6 ("collection length gates
its own row attribute" — a representative row is only built once the length
gate is True) does **NOT** port here. Checked directly against
`targets.rb`'s `to_a`/`records` mock: it builds the representative
(`ct.symbolic_instance`, which is what mints the `..._row_text_has_mention`
symbool) UNCONDITIONALLY on every call, before the length is even decided —
length and the representative's attributes are two independent seeds on the
SAME mock invocation, not gated on each other. Verified empirically (this
pass does NOT assume it): `len(records_2_rows)==False` co-occurs with
`records_2_row_text_has_mention` in 672/3,009 dumps; `len(to_a_3_rows)==
False` with `to_a_3_row_text_has_mention` in 704/3,009; `len(to_a_2_rows)==
False` with `to_a_2_row_text_has_mention` in 128/3,009 — all real, no
assumption declared for that pairing (posts_show's `rows_mock` and this
endpoint's `to_a`/`records` mock are architecturally different despite the
shared IterableSymbolicList/SampledList name).

A THIRD FINDING (crash attribution, not a coverage tier but reported here
since it explains part of `dump_errors`): 120/125 crashed dumps are
`ActionView::Template::Error: undefined method 'message' for nil:NilClass` at
`_conversation.haml:35` (`conversation.messages.last.message...`). Root
cause: `.present?` (the `records_2` mock call) and `.last` (the `last_1`
mock call, `FinderMethods#last`) are TWO INDEPENDENTLY SEEDED mocks standing
in for the SAME real `messages` association — nothing constrains them to
agree, so DSE can (and did) produce `records_2`'s length gate True (messages
"present") simultaneously with `last_1_not_found` True (`.last` "empty") —
a combination no real, consistent database could produce (if the relation is
non-empty, `.last` cannot be nil). This is a MOCK-FIDELITY gap (two
independent mocks for one real relation), not a genuine Diaspora bug and not
a classic `NotImplementedError` framework wall — reported honestly as its own
category in REPORT.md. The other 5 are `No route matches ... id=>nil`
(`conversation_path(conversation)` when `.conversation` — `convidx_conv_
lookup_1` — returned nil), which the new CONVIDX-gate tier below now proves
structurally CANNOT co-occur with anything past that point (matches the 5
crashes: no PCs are recorded past the route-helper call in those runs).

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
          self.messages.to_a[-visibility.unread]                    # -> to_a_1, C
        end
      end

      def set_read(user)                                            # line 37
        visibility = conversation_visibilities.find_by(...)         # -> D
        return unless visibility
        ...

  app/views/conversations/index.haml: left column renders `_conversation`
  per visibility (unaffected by A); right column (`#conversation-show`) is
  `- if @conversation = render 'conversations/show', conversation: @conversation`
  -- ONLY when A==False.

  app/views/conversations/_show.haml (right column, A-gated):
  `if conversation.participants.count > 1` (-> count_3), `for participant in
  conversation.participants` (-> records_3), `render partial: "messages"` ->
  `_messages.haml`'s `render partial: "message", collection: conversation.
  messages` (-> to_a_3).

  app/views/conversations/_conversation.haml (left column, per visibility,
  NOT A-gated): `conversation = visibility.conversation` (-> convidx_conv_
  lookup_1, targets.rb `ConvoSymAssociations#conversation`) is the FIRST use
  of `conversation` (`conversation_path(conversation)`, right after) —
  everything else in the partial that reads `conversation.*`
  (`ordered_participants` -> `messages.map(&:author)` -> records_1;
  `participants` -> to_ary_1/assoc_author_*; `messages.size` -> size_2;
  `last_author` -> find_by_2; `messages.present?`/`.last` -> records_2/
  last_1) runs strictly AFTER that line and crashes
  (`ActiveRecord::RecordNotFound`-adjacent nil dereference, see the crash
  finding above) if `conversation` is nil.

Expression identities (all recorded at the shared FinderMethods/Relation/
Calculations mock boundary in concolic_targets.rb / targets.rb, hence keyed
by `expr` per src/concolic_engine/assumptions.py's "Identifying a path
condition" and reports/diaspora/README.md "Declaring assumptions"):

  A = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)"
  B = "(SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found == True)"
  C = "((- SYM_RESULT_ActiveRecord__FinderMethods_first_2_unread) == 0)"
  D = "(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found == True)"
  CONVIDX = "(SYM_RESULT_ActiveRecord__Relation_convidx_conv_lookup_1_not_found == True)"
  LAST1_NF = "(SYM_RESULT_ActiveRecord__FinderMethods_last_1_not_found == True)"
  LAST1_ATTR = "(SYM_RESULT_ActiveRecord__FinderMethods_last_1_text_has_mention == True)"

Per-run ordinal caveat (unchanged from the prior pass, KEPT): `SYM_RESULT_
..._N` ordinals are per (class, method) call counters shared by EVERY
invocation of that target in the process. `first_1`/`first_2`/`find_by_1`
remain unambiguous (verified across every dump: `first_1` is always the
action's own @conversation lookup, `first_2` is always first_unread_
message's, `find_by_1` is always set_read's — all fire, when at all, in that
fixed textual order inside the SAME `if @conversation` block).
`convidx_conv_lookup_1` is a DEDICATED per-target counter (targets.rb `install!`)
so it never collides with `.first`'s shared counter. `to_a_1` is verified
(empirically, 0/3,009 counter-examples) to always be `first_unread_message`'s
`messages.to_a[-visibility.unread]` call — it is the temporally-first call
sharing the `to_a`/`records` counter along every path that reaches it (the
`if @conversation` block runs before any rendering). `to_a_2`/`to_a_3`/
`records_1`/`records_2`/`records_3`/`count_1`/`count_3`/`size_2`/`find_by_2`
do NOT have this guarantee — see the ordinal-instability finding above; no
assumption below names them as a GUARD (only as a foreclosed/attribute side,
which is safe: an over-broad "this specific named PC cannot co-occur with
that guard" claim, verified per-run, does not depend on which call the
foreclosed name denotes in OTHER runs).

Safety test applied to each pair below (assumptions.py IndependenceAssumption
docstring): "can any combination of the two outcomes produce a call
sequence/access pattern the individual outcomes don't?" — No, for the same
reason as the prior pass's pairs: the second expression is UNREACHABLE code
whenever the first is on its guard-fails side, so the "both evaluated" call
sequence cannot be constructed — proven both by reading the guarding code and
by 0/3,009 empirical counter-examples per pair.
"""

from __future__ import annotations

import re

from concolic_engine.assumptions import AssumptionSet, IndependenceAssumption

EXPR_A = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)"
EXPR_B = "(SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found == True)"
EXPR_C = "((- SYM_RESULT_ActiveRecord__FinderMethods_first_2_unread) == 0)"
EXPR_D = "(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found == True)"
EXPR_CONVIDX_NF = "(SYM_RESULT_ActiveRecord__Relation_convidx_conv_lookup_1_not_found == True)"
EXPR_LAST1_NF = "(SYM_RESULT_ActiveRecord__FinderMethods_last_1_not_found == True)"
EXPR_LAST1_ATTR = "(SYM_RESULT_ActiveRecord__FinderMethods_last_1_text_has_mention == True)"

# contacts_data (conversations_controller.rb:114-120) pluck-column blank
# checks. Person.name_from_attrs(first_name, last_name, diaspora_handle)
# (app/models/person.rb:254-255) -- UNCHANGED from the prior pass.
EXPR_P1 = "(SYM_RESULT_ActiveRecord__Calculations_pluck_1_pluck1_first_name == '')"
EXPR_P2 = "(SYM_RESULT_ActiveRecord__Calculations_pluck_1_pluck2_last_name == '')"
EXPR_P3 = "(SYM_RESULT_ActiveRecord__Calculations_pluck_1_pluck3_diaspora_handle == '')"


def _family(all_exprs, needles):
    """Every expr containing ANY of the given substrings. Auto-discovery,
    not hand-enumeration: adding/renaming a var in targets.rb changes what
    this returns without anyone needing to touch this file, and the
    verification loop this pass ran (see docstring) is what earns each
    needle's soundness, not the substring match itself.
    """
    return sorted({e for e in all_exprs if any(n in e for n in needles)})


# ---------------------------------------------------------------------------
# TIER 0 (NEW) -- format/conversation_id variant exclusivity. run_dse.rb's 4
# SCENARIOS (html_plain, html_withcid, json_plain, json_withcid) are mutually
# exclusive per run: one request has exactly one format and either has or
# lacks `params[:conversation_id]`. Auto-derived exactly like results3/
# posts_show's Tier 0 -- group every expr by the SET of variant labels it was
# observed under across the corpus, cross-cut every pair of exprs whose sets
# are disjoint. Sound by construction (one run, one variant); does not rely
# on any ordinal-stability assumption since it only uses SET MEMBERSHIP of
# observed (expr, variant) pairs, never what a shared-counter name "means".
# ---------------------------------------------------------------------------
_VARIANTS = ("html_plain", "html_withcid", "json_plain", "json_withcid")


def _variant_of(label):
    label = label or ""
    for v in _VARIANTS:
        if label.startswith(v):
            return v
    return "unknown"


def _tier0_variant_exclusivity(runs):
    expr_variants = {}
    for r in runs:
        v = _variant_of(r.label)
        for pc in r.path_conditions:
            expr_variants.setdefault(pc.expr, set()).add(v)

    by_set = {}
    for e, s in expr_variants.items():
        by_set.setdefault(frozenset(s), []).append(e)

    groups = sorted(by_set.items(), key=lambda kv: sorted(kv[0]))
    out = []
    for i, (set_a, exprs_a) in enumerate(groups):
        for set_b, exprs_b in groups[i + 1:]:
            if set_a & set_b:
                continue
            for a in exprs_a:
                for b in exprs_b:
                    out.append(IndependenceAssumption(
                        expr_a=a, expr_b=b,
                        description=f"variant exclusivity: {sorted(set_a)} vs {sorted(set_b)}",
                        agent_notes=(
                            "run_dse.rb's SCENARIOS fix format (html/json) and "
                            "conversation_id presence for a run's entire duration "
                            "(conversations_controller.rb:13 `if params[:conversation_id]`, "
                            "#index's `respond_with do |format| ... end`). Verified "
                            f"empirically: expr_a's observed variant set is exactly "
                            f"{sorted(set_a)}, expr_b's is exactly {sorted(set_b)} "
                            "across all 3,009 dumps in this directory -- disjoint, so "
                            "no single run's path can contain both."
                        ),
                    ))
    return out


# ---------------------------------------------------------------------------
# TIER 1 -- guard chain inside `if @conversation` (A) and inside `if visibility`
# (B), UNCHANGED core (A-B, A-C, A-D, B-C) plus NEW edges this pass adds for
# the render-descent exprs the prior pass's universe didn't have:
#   A (conversation not found) also forecloses:
#     - to_a_1 family (first_unread_message's `messages.to_a[-unread]`,
#       conversation.rb:33 -- inside the SAME `if @conversation` as B/D)
#     - the id-compare `convidx_conv_lookup_1_id == first_1_id`
#       (_conversation.haml's `conversation_class(conversation, visibility.
#       unread, @conversation.try(:id))` -- `@conversation.try(:id)` is nil,
#       not `first_1_id`, whenever A==True, so THIS SPECIFIC comparison,
#       which names first_1_id explicitly, cannot be the one recorded)
#     - count_3 / records_3 / to_a_3 families (`_show.haml`/`_messages.haml`,
#       rendered ONLY inside index.haml's `- if @conversation` right column,
#       entirely separate from the left-column visibilities list)
#   B (visibility not found) also forecloses:
#     - to_a_1 family (same call, one level deeper: conversation.rb:32-33's
#       `if visibility = ...first` guards the `self.messages.to_a[...]` line
#       directly)
# All verified empirically, 0/3,009 violations each (see module docstring).
# ---------------------------------------------------------------------------
_A_NEEDLES = ("to_a_1_row", "Relation_records_3_", "Calculations_count_3_",
              "to_a_3_row", "first_1_id")
_B_NEEDLES = ("to_a_1_row",)


def _tier1_guard_chain(all_exprs):
    out = []

    def _cut(guard, guard_desc, members, why):
        pairs = []
        for m in members:
            if m == guard:
                continue
            pairs.append(IndependenceAssumption(
                expr_a=guard, expr_b=m,
                description=f"{guard_desc} vs {m}",
                agent_notes=why,
            ))
        return pairs

    out += _cut(
        EXPR_A, "A(conversation not found)",
        [EXPR_B],
        "B is conversation.rb:32's conversation_visibilities.first, called only "
        "from first_unread_message(user), which conversations_controller.rb:21 "
        "calls only inside `if @conversation` (line 20) i.e. only when A==False. "
        "(A=True, B=*) cannot occur.",
    )
    out += _cut(
        EXPR_A, "A(conversation not found)",
        [EXPR_C],
        "C is conversation.rb:33's index check, reached only after both A==False "
        "AND B==False. A==True skips first_unread_message entirely.",
    )
    out += _cut(
        EXPR_A, "A(conversation not found)",
        [EXPR_D],
        "D is conversation.rb:38's set_read(user), called by conversations_"
        "controller.rb:22 only inside the same `if @conversation` guard as B. "
        "A==True skips set_read entirely.",
    )
    out += _cut(
        EXPR_B, "B(visibility not found)",
        [EXPR_C],
        "C only executes inside `if visibility = ...first` (conversation.rb:32-33) "
        "-- only when B==False. (B=True, C=*) is unreachable.",
    )

    a_family = _family(all_exprs, _A_NEEDLES)
    out += _cut(
        EXPR_A, "A(conversation not found)",
        a_family,
        "conversations_controller.rb:13-24: everything inside `if @conversation` "
        "(first_unread_message's to_a_1 family, the id-compare naming first_1_id) "
        "and index.haml's right column (`- if @conversation = render 'conversations/"
        "show'` -> _show.haml's count_3/records_3, _messages.haml's to_a_3) is "
        "gated behind A==False. A==True means @conversation is nil: none of these "
        "ever run in that request. Auto-discovered family, see this module's "
        "_family() docstring; verified empirically (0/3,009 counter-examples).",
    )

    b_family = _family(all_exprs, _B_NEEDLES)
    out += _cut(
        EXPR_B, "B(visibility not found)",
        b_family,
        "conversation.rb:32-33: `self.messages.to_a[-visibility.unread]` (to_a_1 "
        "and its cross-comparisons to to_a_2/to_a_3) sits directly inside the "
        "`if visibility = ...first` block B guards. B==True means that line never "
        "runs. Verified empirically (0/3,009 counter-examples).",
    )

    return out


# ---------------------------------------------------------------------------
# TIER 2 (NEW) -- `.conversation` (CONVIDX) gates everything _conversation.haml
# reads off the resulting Conversation object. targets.rb's ConvoSymAssociations
# #conversation returns nil (via the shared finder_mock's not_found branch) when
# CONVIDX==True; _conversation.haml's FIRST use of the local `conversation` is
# `conversation_path(conversation)` (right after `conversation = visibility.
# conversation`), and EVERY subsequent read (`ordered_participants` -> messages.
# map(&:author) -> records_1; `participants` -> to_ary_1/assoc_author_*;
# `messages.size` -> size_2; `last_author` -> find_by_2; `messages.present?`/
# `.last` -> records_2/last_1) happens strictly later in the same partial and
# would NoMethodError on nil before reaching any of those calls. Matches the
# crash evidence directly: 5 of this directory's dump_errors are exactly
# "No route matches ... id=>nil" (conversation_path(nil) — CONVIDX==True
# aborting before ordered_participants/messages.* ever run). Verified
# empirically, 0/3,009 counter-examples: no dump ever records CONVIDX==True
# alongside ANY member of this family.
#
# Also includes CONVIDX's OWN Tier-1-shape pairing: CONVIDX==True forecloses
# `convidx_conv_lookup_1_id == first_1_id` (that attribute names CONVIDX's own
# id, which finder_mock never builds on the not_found side) -- same shape as
# every other not_found-gates-attribute pairing in this project.
# ---------------------------------------------------------------------------
_CONVIDX_NEEDLES = ("Relation_records_1_", "Relation_to_ary_1_", "assoc_author_",
                     "Relation_size_2_", "FinderMethods_find_by_2_",
                     "Relation_records_2_", "FinderMethods_last_1_", "first_1_id")


def _tier2_convidx_gates_conversation_object(all_exprs):
    family = _family(all_exprs, _CONVIDX_NEEDLES)
    out = []
    for m in family:
        if m == EXPR_CONVIDX_NF:
            continue
        out.append(IndependenceAssumption(
            expr_a=EXPR_CONVIDX_NF, expr_b=m,
            description=f"CONVIDX(.conversation not found) vs {m}",
            agent_notes=(
                "targets.rb ConvoSymAssociations#conversation returns nil (finder_"
                "mock's not_found branch) when CONVIDX==True. _conversation.haml's "
                "`conversation_path(conversation)` is the FIRST use of the local "
                "`conversation` (right after `conversation = visibility.conversation`); "
                "ordered_participants/messages.size/last_author/messages.present?/"
                ".last (the source of records_1/to_ary_1/assoc_author_*/size_2/"
                "find_by_2/records_2/last_1, and the id-compare naming CONVIDX's own "
                "id) all run strictly later in the same partial and dereference nil "
                "first -- matches this directory's 5 'No route matches ... id=>nil' "
                "dump_errors. Auto-discovered family (_family()); verified "
                "empirically, 0/3,009 counter-examples."
            ),
        ))
    return out


# ---------------------------------------------------------------------------
# TIER 3 (NEW) -- last_1's own not_found-gates-attribute pairing (the classic
# shared-finder_mock shape used everywhere else in this project: `last` is in
# the SAME %i[find_by take first last] found/not_found family declared in
# concolic_targets.rb, so `symbolic_instance` -- and hence the `text_has_
# mention` symbool minted in it -- is only built on the found side).
# Independent of Tier 2 above: Tier 2 cuts (CONVIDX=True, last_1_attr=*);
# THIS cuts (last_1_nf=True, last_1_attr=*) even in runs where CONVIDX==False
# (reachable) -- a different pair the checker's per-pair graph needs
# separately. Verified empirically, 0/3,009 counter-examples.
# ---------------------------------------------------------------------------
def _tier3_last1_not_found_gates_attr():
    return [IndependenceAssumption(
        expr_a=EXPR_LAST1_NF, expr_b=EXPR_LAST1_ATTR,
        description="last_1(not found) vs last_1(text_has_mention)",
        agent_notes=(
            "concolic_targets.rb finder_mock (shared by find/find_by/take/first/"
            "last): symbolic_instance (which mints text_has_mention) is built ONLY "
            "in the not_found==False else-branch -- same shape as every other "
            "finder's not_found/attribute pairing in this project. "
            "(last_1_not_found=True, last_1_text_has_mention=*) is structurally "
            "impossible. NOTE (see module docstring 'THIRD FINDING'): the corpus "
            "DOES contain 120 crashed runs where records_2's independent length-"
            "gate mock disagrees with last_1's independent not_found seed for what "
            "is really the same `messages` relation -- that is a genuine mock-"
            "fidelity gap, reported in REPORT.md, but it does not make THIS pair "
            "(both drawn from the SAME last_1 call) reachable; verified 0/3,009 "
            "counter-examples."
        ),
    )]


def build(runs=None) -> AssumptionSet:
    aset = AssumptionSet()

    all_exprs = []
    if runs:
        seen = set()
        for r in runs:
            for pc in r.path_conditions:
                if pc.expr not in seen:
                    seen.add(pc.expr)
                    all_exprs.append(pc.expr)

    if runs:
        for ia in _tier0_variant_exclusivity(runs):
            aset.add(ia)

    for ia in _tier1_guard_chain(all_exprs):
        aset.add(ia)

    for ia in _tier2_convidx_gates_conversation_object(all_exprs):
        aset.add(ia)

    for ia in _tier3_last1_not_found_gates_attr():
        aset.add(ia)

    aset.add(IndependenceAssumption(
        expr_a=EXPR_P1, expr_b=EXPR_P2,
        description="P1(first_name blank) || P2(last_name blank)",
        agent_notes=(
            "person.rb:255: `first_name.blank? && last_name.blank? ? ...`. Ruby's "
            "`&&` short-circuits -- P2 (last_name.blank?) is only evaluated when "
            "P1==True. (P1=False, P2=*) is unreachable: no PC for P2 is even "
            "recorded in a run where P1 is False."
        ),
    ))
    aset.add(IndependenceAssumption(
        expr_a=EXPR_P1, expr_b=EXPR_P3,
        description="P1(first_name blank) || P3(diaspora_handle blank, via tidy_bytes)",
        agent_notes=(
            "P3 only fires when the name_from_attrs ternary takes its TRUE arm, "
            "which requires P1==True. (P1=False, P3=*) is unreachable -- P1=False "
            "forces the ternary's FALSE arm, whose interpolated result is a plain "
            "(non-symbolic) string, so tidy_bytes never even sees a trackable "
            "value and P3 is not recorded."
        ),
    ))
    aset.add(IndependenceAssumption(
        expr_a=EXPR_P2, expr_b=EXPR_P3,
        description="P2(last_name blank) || P3(diaspora_handle blank, via tidy_bytes)",
        agent_notes=(
            "Same ternary guard as P1-P3: the TRUE arm (which alone reaches P3) "
            "requires P1==True AND P2==True. (P2=False, P3=*) is unreachable for "
            "the identical reason."
        ),
    ))

    return aset
