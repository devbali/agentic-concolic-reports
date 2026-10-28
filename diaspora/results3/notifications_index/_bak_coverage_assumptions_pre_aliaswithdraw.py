#!/usr/bin/env python3
"""notifications_index — batch-local AssumptionSet (results3 completion drive,
2026-08-27). Rebuilt for the completion engine's MANDATORY assumption gate:
every declaration is a STRUCTURAL claim the engine's derived flip-probe test
verifies (no empirical-count Tier 1 — the engine would reject an unsound
independence and it would block completion; HARD RULE 5). Supersedes the
gen3 file (which predated the gate rules and the real-Devise principal).

CO-EVALUATION SEMANTICS (2026-09-10). The engine now demands a combination
only over decisions that SOME RUN EVALUATED TOGETHER, so a declaration over a
pair no run co-evaluates relaxes nothing and is not made. Four tiers went with
that rule, because non-co-evaluation WAS their whole argument:

  * TIER 0a (variant exclusivity) and TIER 0b (STI-type exclusivity) —
    "observed only under disjoint request variants / dispatch values, so no
    run records both". Disjoint observed sets ARE disjoint run sets.
  * `_tier_samerep_never_coeval` and P1 `_tier_unobservable_pairs` (the
    ~20 000 never-co-evaluated declarations, with their withdrawal/bypass
    machinery) — the rule they encoded is now the engine's default.
  * the corpus-evidence half of TIER 1c (empty-list forecloses a render-time
    decision "observed in disjoint runs"); its STRUCTURAL half stays, because
    a length gate and the row decisions it forecloses ARE co-evaluated on the
    non-empty arm.

What survives is exactly the declarations about pairs the corpus DOES
evaluate together, each a structural claim the gate's flip-both probe tests:

  TIER 2 — DISJOINT-OBJECT DECISIONS. Two decisions evaluated on DIFFERENT
    symbolic reps (different owner-rep var prefix) in this endpoint's render
    tree neither gate nor feed each other: every rep's decisions (its
    `_persisted`, its `_id == <principal>_person_id` own-profile compare, its
    `_guid == ''`, its `_profile_*_name` blank-name compare) are consumed by
    code reading only that rep, and every statement shape it can produce is
    keyed on its own id. Disjointness claim — licensed by the engine's
    flip-both access-trace probe. Decisions on the SAME rep stay dependent.

  ONE-SIDE-UNTRACKED — the Journey formatter's `<rep>_guid != StringVal('')`
    records only on the blank-guid path where it is value-forced False (the
    non-blank path is handled earlier and skips the compare). Its True side is
    structurally unreachable.

Source lines cited (read-only):
  app/controllers/notifications_controller.rb:25-58  index action
  app/views/notifications/_notification.haml:5  `note.type == "Notifications::StartedSharing"`
  app/helpers/people_helper.rb:81-86  person_link_class own-profile compare
  app/helpers/people_helper.rb:36-37  person_image_tag `person.profile.nil?`
  activerecord singular_association.rb find_target?: `!owner.new_record?`
  concolic_targets.rb finder_mock: `not_found == true` -> nil (no rep)
  targets.rb §5f: SYM_NOTE_TYPE_PROFILE STI dispatch
"""
from __future__ import annotations

import os
import re
from collections import defaultdict

from concolic_engine.assumptions import (AssumptionSet, IndependenceAssumption,
                                         OneSideUntrackedPathAssumption,
                                         UntrackedPathAssumption)
from concolic_engine.assumptions import AliasAssumption
from concolic_engine.coverage import maximal_sets

# P0/P1 (2026-09-08) — THE ALIAS. call_interceptor.rb names a result by call
# ordinal; on this endpoint the ordinal of every list read is a function of the
# path prefix (measured: records_4 = aspects in 1 909 runs, services in 1 254;
# 0 ambiguous contexts; never renumbered by a length seed), so one statement was
# many variables and one variable was many statements.
#
# P3 (2026-09-09) — WIDENED TO `loop` WHERE THE FALSIFIER ALLOWS IT, AND ONLY
# THERE. A decision is identified by WHAT produced it; for a LOOP that is the
# loop body rather than the exact statement, so a list's VARIANTS (an extra
# scope, an ordering, a page window) are one loop and a decision about a row is
# one node across them and across iterations. `AliasAssumption(key="loop")`
# keys by `loop_key` — table + binds, variants folded — and the row decisions
# and the length collapse with it because they are named after it.
#
# The gate's derived test was run over all 13 loop names before anything was
# declared (`_ALIAS_REFACTOR_20260909.md` §4). It PASSED for the five
# CollectionProxy families and REFUTED the widening for the three
# `Relation#records` mentions loops and — the one that mattered — for the
# paginated `Relation#to_ary` notifications list:
#
#   * `to_ary` notifications, the 4 WHERE-clause variants: FAIL on (ii).
#     Intervening on the four members has THREE different effects; at length 0
#     one variant removes a `photos` read the others do not. The typed variant
#     (`type = 'Notifications::StartedSharing'`) holds rows with no status
#     message target, so its rows do NOT lead to the photos/mentions chain the
#     plain variant's rows lead to. They are not one loop body. This is
#     violation 7's fact (DISCIPLINE §1) seen from the other side: the
#     notification TYPE decides the downstream statement set.
#   * `Relation#records` mentions x3: FAIL on (iii). Each is already ONE
#     statement — the widening merges nothing there — but a replay at k+1 rows
#     changes the target-call SHAPE set: the bulk preload goes from
#     `people.id IN (?, ?, ?)` to a different arity, and the policy consumer
#     PRESERVES `IN` arity (queries_from_runs/transform.py:589 short-circuits
#     `exp.In` out of conjunct cleaning; dedup is string-exact), so a different
#     arity is a different view. "One iteration sees them all" is false there.
#
# So the loop key is declared for the CollectionProxy families only. What it
# buys: photos 6 statement names -> 3 loop names — the six were THREE owner
# chains (`_row_target_guid`, `_row_target_mentions_container_guid`,
# `_row_target_mentions_container_commentable_guid`) each with an empty-scope
# `AND (1=0)` variant, and a different OWNER chain stays a different loop.
# aspects / services / tags / aspect_memberships are one loop name each either
# way. Measured on the 68 231-dump corpus: 435 tracked expressions -> 411,
# 2 050 maximal cliques -> 1 277, 606 496 satisfiable assignments -> 542 784
# (`_exact_enum.py`).
#
# NOT declared, and why: `Relation_to_ary` and `Relation_records` stay keyed by
# STATEMENT. `Relation_records_notifications` (the unread badge list) is the
# one loop that PASSES and is still not loop-keyed — it is minted through the
# same `Relation#records` call site as the three mentions loops that fail, so
# no pattern over ORDINAL names can select it alone. It loses nothing: it is
# one statement, hence one name, under either key.
#
# Neither P2 nor K1 is subsumed. They untrack the many-ARM of a root family's
# length; the alias only decides what that length is CALLED, and for
# aspects/services/tags/records_notifications it renames nothing (one name
# before, one name after). Both stay declared exactly as they were.
#
# Declared here so it is in the report's assumption list and probed by the
# gate's Alias derived test; APPLIED at load by
# coverage_report.canonicalize_ordinals (this batch drops notes after load).
# A FAIL withdraws.
_ALIAS_LOOP_PATTERN = r"SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_\d+"
_ALIAS_STMT_PATTERN = r"SYM_RESULT_ActiveRecord__(?:Relation_records|Relation_to_ary)_\d+"
# kept for readers of the earlier report / any tool that imported it
ALIAS_PATTERN = (r"SYM_RESULT_ActiveRecord__(?:Associations__CollectionProxy_records"
                 r"|Relation_records|Relation_to_ary)_\d+")
ALIASES = [
    AliasAssumption(
        result_pattern=_ALIAS_LOOP_PATTERN, key="loop", k=1,
        description="association list reads identified by the LOOP they iterate "
                    "(table + binds; variants and iterations folded)",
        agent_notes=("aspects/services/tags/photos/aspect_memberships. k=1: every "
                     "iteration aliases to the first. A different owner chain in the "
                     "binds stays a different loop (photos keeps 3 names). All five "
                     "families PASS the gate's Alias derived test — statement census, "
                     "intervention effects across the merged variants, and a k+1-row "
                     "replay with identical target-call shapes.")),
    AliasAssumption(
        result_pattern=_ALIAS_STMT_PATTERN, key="statement",
        description="Relation reads identified by their statement (binds kept)",
        agent_notes=("to_ary notifications x4 and Relation#records mentions x3 / unread "
                     "notifications. NOT widened to the loop: the to_ary variants FAIL "
                     "the gate on intervention effects (the typed variant's rows do not "
                     "reach the photos chain) and the mentions loops FAIL on the k+1 "
                     "replay (the bulk preload's IN arity follows the row count, and the "
                     "policy consumer preserves IN arity).")),
]

_DISPATCH_RE = re.compile(r"\((SYM_NOTE_TYPE_PROFILE|SYM_POST_STI) == (\d+)\)")

# Attribute suffixes stripped to reach a rep's owner prefix.
_ATTR_SUFFIXES = ("_not_found", "_persisted", "_text_has_mention", "_text_nil",
                  "_mention_inline_name", "_unread", "_guid", "_subject",
                  "_public_details", "_birthday_year", "_author_id",
                  "_person_id", "_owner_id", "_count", "_size", "_id", "_rows",
                  "_first_name", "_last_name")


def _is_principal(var):
    return "person_id" in var or "devise_user_first" in var or \
        "SYM_USER_NI" in var or "SYM_PERSON_NI" in var


def _strip_suffix(var):
    for suf in _ATTR_SUFFIXES:
        if var.endswith(suf):
            return var[: -len(suf)]
    return var


def _rep_key(expr):
    s = expr.strip()
    # var-vs-var compare: the decision belongs to the NON-principal rep (the
    # principal is a shared comparand, not the subject).
    mvv = re.match(r"^\(([A-Za-z_][A-Za-z0-9_]*) (?:==|!=) ([A-Za-z_][A-Za-z0-9_]*)\)$", s)
    if mvv:
        l, r = mvv.group(1), mvv.group(2)
        cand = r if _is_principal(l) and not _is_principal(r) else (
               l if _is_principal(r) and not _is_principal(l) else l)
        return _strip_suffix(cand)
    m = re.match(r"^\(\(- ([A-Za-z_][A-Za-z0-9_]*)\)", s) or \
        re.match(r"^\(len\(([A-Za-z_][A-Za-z0-9_]*)\)", s) or \
        re.match(r"^\(SYM_LEN_([A-Za-z_][A-Za-z0-9_]*)", s) or \
        re.match(r"^\(([A-Za-z_][A-Za-z0-9_]*)", s)
    var = m.group(1) if m else s
    return _strip_suffix(var)


def _nested_pair(a, b):
    """The photos COLLECTION (CollectionProxy records = the post's photos) is
    loaded inside the target's photos branch, so its LENGTH is correlated with
    the target's guid (both live only on the text_nil==True / blank-message
    path). The gate proved `len(records..._rows) ⊥ target_guid` interacts
    (flip-both fires the photos COUNT). Keep JUST that class dependent
    (observed); every other records×target pair is genuinely disjoint and
    stays independent."""
    # Match on the LEFT VARIABLE, not the raw expression text (the expression
    # ends in `== '')`, so an endswith("_guid") on it never matched -- the
    # 2026-08-27 final gate re-FAILed exactly this pair; fixed here).
    va, vb = (_leftvar(a) or a), (_leftvar(b) or b)
    def _isphotoslen(x): return "CollectionProxy_records" in x and x.endswith("_rows")
    # 2026-08-27 final gate #2 FAILed photos-len x target-chain `_persisted`
    # (target / mentions_container / mentions_container_commentable) with the
    # same photos-COUNT combination shape -> the whole target-chain guid AND
    # persisted decisions stay dependent on the photos length. Withdrawn only.
    # `_author_persisted` is NOT in the failed set: in Mention runs records_2 is
    # post.photos and post_page_title reads post.author_name only when
    # photos.present?, so len==0 forecloses the author read (gate #2 PASSed
    # those pairs; they stay independent).
    def _istargetguid(x):
        return "_target" in x and (x.endswith("_guid")
                                   or (x.endswith("_persisted") and not x.endswith("_author_persisted")))
    return (_isphotoslen(va) and _istargetguid(vb)) or (_isphotoslen(vb) and _istargetguid(va))


def _observations(runs):
    """Per expr: dispatch-value-set (per dispatch var, and whether it was ever
    recorded with the var ABSENT), plus the corpus's CO-EVALUATION relation.

    2026-09-10 (co-evaluation semantics): the checker demands a combination
    only over decisions some run evaluated TOGETHER, so a pair no run
    co-evaluated carries no demand and an independence over it is inert. The
    pair set is derived exactly as the engine derives its demand universe —
    the runs' evaluation sets, reduced to the MAXIMAL ones (`maximal_sets`,
    imported from the engine so the two can never drift) — and every
    declaration below is filtered through it in `build`.
    """
    expr_dispatch = defaultdict(lambda: defaultdict(set))  # expr -> dvar -> {values}
    dispatch_absent = defaultdict(lambda: defaultdict(set))  # expr -> dvar -> {"absent"}
    all_exprs = set()
    eval_sets = set()
    for r in runs:
        # this run's dispatch values (one per dispatch var, if recorded True)
        dvals = {}
        for pc in r.path_conditions:
            m = _DISPATCH_RE.match(pc.expr)
            if m and pc.taken:
                dvals[m.group(1)] = int(m.group(2))
        seen = set()
        for pc in r.path_conditions:
            e = pc.expr
            seen.add(e)
            for dvar in ("SYM_NOTE_TYPE_PROFILE", "SYM_POST_STI"):
                if dvar in dvals:
                    expr_dispatch[e][dvar].add(dvals[dvar])
                else:
                    dispatch_absent[e][dvar].add("absent")
        if seen:
            eval_sets.add(frozenset(seen))
            all_exprs |= seen
    coeval = set()
    for s in maximal_sets(eval_sets):
        es = sorted(s)
        for i, a in enumerate(es):
            for b in es[i + 1:]:
                coeval.add(frozenset((a, b)))
    return sorted(all_exprs), expr_dispatch, dispatch_absent, coeval


def _tier0c_dispatch_independence(exprs, expr_dispatch, already):
    """The STI dispatch dimension (SYM_NOTE_TYPE_PROFILE / SYM_POST_STI seed)
    is INDEPENDENT of every non-dispatch decision: the type/post-STI value is
    a separate seeded input, and every other decision (a rep's persisted /
    guid / name / id compare, a count, params[:show]) is evaluated on its own
    seed. A type value gates WHICH downstream reads fire, but flipping it only
    ADDS or REMOVES a whole type-branch's reads — it never makes another
    decision's tree produce a NEW target-call shape in combination (the
    engine's flip-both access-trace probe licenses exactly this: type-gating
    removes shapes, it does not add any absent from the singles). Without this
    the checker demands unobservable combos like `TYPE==0 AND
    <started-sharing-only contact read>` (that read only exists under
    TYPE==6). Keep the dispatch compares MUTUALLY dependent (their bounded 8+2
    clique is covered in full)."""
    out = []
    dispatch = [e for e in exprs if _DISPATCH_RE.match(e)]
    nondispatch = [e for e in exprs if not _DISPATCH_RE.match(e)]
    for b in nondispatch:
        for d in dispatch:
            key = frozenset((b, d))
            if key in already:
                continue
            already.add(key)
            dvar = _DISPATCH_RE.match(d).group(1)
            out.append(IndependenceAssumption(
                expr_a=d, expr_b=b,
                description=f"dispatch-independence: {dvar} seed || {b[:40]}",
                agent_notes=(f"the {dvar} STI-dispatch seed is a separate input from the decision "
                             f"{b}; flipping the type only adds/removes a whole type-branch's reads "
                             "and never makes this decision's tree produce a target-call shape absent "
                             "from the individual branches — licensed by the engine's flip-both probe.")))
    return out


_LEFTVAR_RE = re.compile(r"^\(\(?-?\s*(?:len\(|SYM_LEN_)?([A-Za-z_][A-Za-z0-9_]*)")


def _leftvar(expr):
    m = _LEFTVAR_RE.match(expr.strip())
    return m.group(1) if m else None


def _tier0d_crossdispatch(exprs, already):
    """SYM_NOTE_TYPE_PROFILE (notification STI) and SYM_POST_STI (the target
    Post's STI) are TWO SEPARATE seeded inputs — flipping one never changes
    the other, and the photos query the Post-STI gates has the SAME shape
    under whichever notification type routed to a Post rep. So the TYPE and
    POST_STI compares are cross-independent; keep each var's OWN compares
    mutually dependent (their small bounded clique) but split the two."""
    out = []
    typ = [e for e in exprs if e.startswith("(SYM_NOTE_TYPE_PROFILE ==")]
    pst = [e for e in exprs if e.startswith("(SYM_POST_STI ==")]
    for a in typ:
        for b in pst:
            key = frozenset((a, b))
            if key in already:
                continue
            already.add(key)
            out.append(IndependenceAssumption(
                expr_a=a, expr_b=b,
                description=f"cross-dispatch: {a} || {b}",
                agent_notes="SYM_NOTE_TYPE_PROFILE (notification STI) and SYM_POST_STI (target Post STI) "
                            "are independent seeds; neither gates the other and the Post-STI photos query "
                            "shape is the same under any type routing to a Post — flip-both adds nothing."))
    return out


def _tier_guid_foreclosed_by_persisted(exprs, already):
    """On a target-chain rep, the guid compare is evaluated ONLY on the
    UNPERSISTED + BLANK-MESSAGE path: verified that forcing `_persisted` True
    makes the `_guid` PC vanish, and that whenever `_guid` is recorded
    `_text_nil` is True (the guid compare and text_nil==True are 100%
    co-recorded). So both `_persisted` and `_text_nil` FORECLOSE the guid
    compare on their opposite side; declare `_guid` independent of each (the
    engine's flip-both probe passes — flipping the guid on the foreclosed side
    is a no-op). Every guid×persisted / guid×text_nil combination is thereby
    removed from the demand; only the OBSERVABLE persisted×text_nil (photos)
    combos remain, covered by exploration."""
    out = []
    lv = {e: _leftvar(e) for e in exprs}
    gate = {}
    for e in exprs:
        v = lv[e]
        if not v:
            continue
        for suf in ("_persisted", "_text_nil"):
            if v.endswith(suf):
                gate.setdefault(v[: -len(suf)], {})[suf] = e
    for e in exprs:
        v = lv[e]
        if not v or not v.endswith("_guid") or "_target" not in v:
            continue
        prefix = v[: -len("_guid")]
        for suf in ("_persisted", "_text_nil"):
            g = gate.get(prefix, {}).get(suf)
            if not g:
                continue
            key = frozenset((e, g))
            if key in already:
                continue
            already.add(key)
            out.append(IndependenceAssumption(
                expr_a=g, expr_b=e,
                description=f"{suf} forecloses guid on {prefix[:40]}",
                agent_notes="the target-chain guid compare runs only on the UNPERSISTED + blank-message "
                            "path; persisted=True and text_nil=False each foreclose it (verified: the "
                            "guid PC only ever co-occurs with the unpersisted, text_nil==True state), so "
                            "the guid is independent of both."))
    return out



def _tier1c_empty_list_foreclosure(exprs, already):
    """cycle 2 (adversary N1 repair fallout). A list LENGTH is a decision now
    (`(SYM_LEN_<X>_rows == 0)`), and on its ZERO arm the list has no rows — so
    NONE of the decisions on that list's representative row (`<X>_row_*`) is
    evaluated in that run. Flipping the gate to its closing value only REMOVES
    those reads (never adds a statement shape), which is exactly what the
    engine's flip-both access-trace probe licenses; without it the checker
    demands unobservable combos like `len(...to_ary_1_rows) == 0 AND
    <that row>_sharing == True`.

    STRICTLY structural: the gate is the length var of list X, the foreclosed
    exprs are those whose left variable starts with X's own row prefix.
    """
    out = []
    lv = {e: _leftvar(e) for e in exprs}
    gates = []
    for e in exprs:
        v = lv[e]
        # NOTE: `_leftvar` normalizes away the `SYM_LEN_` prefix coverage_report
        # adds, so the gate is recognised by the variable's `_rows` suffix.
        if not v or not v.endswith("_rows"):
            continue
        if not e.replace(" ", "").endswith("==0)"):
            continue
        gates.append((e, v[: -len("s")]))  # "..._rows" -> "..._row"
    for g, rowprefix in gates:
        for b in exprs:
            if b == g:
                continue
            vb = lv[b]
            if not vb or not vb.startswith(rowprefix + "_"):
                continue
            key = frozenset((g, b))
            if key in already:
                continue
            already.add(key)
            out.append(IndependenceAssumption(
                expr_a=g, expr_b=b,
                description=f"empty list forecloses row decision [{rowprefix[-40:]}]",
                agent_notes=("on the zero-length arm of this list the representative row does "
                             "not exist, so no decision on it is evaluated; flipping the length "
                             "gate only removes those reads — licensed by the flip-both probe.")))

    return out


def _tier1_samerep_foreclosure(exprs, already):
    """Same-rep FORECLOSURE gates (gen3's finder-arm / value-chain classes,
    sound structural):
      * `<rep>_not_found == True` -> the finder returns nil, so NONE of the
        rep's own attribute / nested-association decisions (`<rep>_*`) exist
        on that arm. Declare the gate independent of every `<rep>_*` expr.
      * `<rep>_text_nil == True` -> text is nil, so `_text_has_mention` /
        `_mention_inline_name` on the same rep are never evaluated.
    Flipping the gate to its closing value only REMOVES the deeper decision's
    reads (never adds a shape), so the engine's flip-both probe licenses it;
    without it the checker demands unobservable combos like
    `not_found==True AND <rep>_persisted==True`."""
    out = []
    lv = {e: _leftvar(e) for e in exprs}
    gates = []
    for e in exprs:
        v = lv[e]
        if not v:
            continue
        if v.endswith("_not_found"):
            gates.append((e, v[: -len("_not_found")], "not_found"))
        elif v.endswith("_text_nil"):
            gates.append((e, v[: -len("_text_nil")], "text_nil"))
        # cycle 2 (adversary W1 repair): the diaspora-link family is nested
        # under its own gate — with `_text_has_dlink == False` the text carries
        # no `diaspora://` link at all, so the renderer's entity compare
        # (`_text_dlink_is_post`), the guid var (`_text_dlink_guid`) and the
        # `Post.exists?` decision it feeds are never evaluated. Same for the
        # profile display columns (`_disp_*`, bio/location).
        elif v.endswith("_text_has_dlink"):
            gates.append((e, v[: -len("_text_has_dlink")], "has_dlink"))
        elif v.endswith("_disp_has_dlink"):
            gates.append((e, v[: -len("_disp_has_dlink")], "disp_dlink"))
    for g, prefix, kind in gates:
        for b in exprs:
            if b == g:
                continue
            vb = lv[b]
            if not vb:
                continue
            same = (vb == prefix or vb.startswith(prefix + "_")) and vb != prefix + "_not_found"
            if kind == "text_nil":
                same = vb in (prefix + "_text_has_mention", prefix + "_mention_inline_name",
                              prefix + "_text_has_dlink", prefix + "_text_dlink_is_post",
                              prefix + "_text_dlink_guid")
            elif kind == "has_dlink":
                same = vb in (prefix + "_text_dlink_is_post", prefix + "_text_dlink_guid")
            elif kind == "disp_dlink":
                same = vb in (prefix + "_disp_dlink_is_post", prefix + "_disp_dlink_guid")
            if not same:
                continue
            key = frozenset((g, b))
            if key in already:
                continue
            already.add(key)
            out.append(IndependenceAssumption(
                expr_a=g, expr_b=b,
                description=f"{kind} forecloses same-rep {vb[:40]}",
                agent_notes=(f"gate {g} closes the rep chain `{prefix}`; on its closing arm the "
                             f"decision {b} is never evaluated (finder returns nil / text is nil). "
                             "Flipping the gate only removes that read — licensed by the flip-both probe.")))
    return out


def _tier2_disjoint_reps(exprs, already):
    # NOTE (rewritten 2026-09-10): under co-evaluation semantics only the
    # cross-rep pairs some run EVALUATES TOGETHER carry a demand, so only
    # those are declared (`build`'s co-evaluation filter drops the rest).
    # The 2026-08-27 note that stood here — "EVERY cross-rep pair must be
    # declared, including never-co-evaluated ones, or 260 blocking combos
    # come back" — was a fact about the complete-graph default, not about
    # this endpoint; those 260 combos were demands over pairs no execution
    # can produce.
    out = []
    ex = sorted(exprs)
    for i, a in enumerate(ex):
        # skip the dispatch compares themselves
        if _DISPATCH_RE.match(a):
            continue
        ka = _rep_key(a)
        for b in ex[i + 1:]:
            if _DISPATCH_RE.match(b):
                continue
            key = frozenset((a, b))
            if key in already:
                continue
            kb = _rep_key(b)
            if ka == kb or not ka or not kb:
                continue
            if _nested_pair(a, b):
                continue  # photos-collection nested under target -> dependent
            already.add(key)
            out.append(IndependenceAssumption(
                expr_a=a, expr_b=b,
                description=f"disjoint reps: [{ka}] || [{kb}]",
                agent_notes=(f"decisions on two different symbolic reps ({ka} vs {kb}); neither "
                             "gates the other and each statement shape either can produce is keyed "
                             "on its own rep's id. Disjointness — licensed by the engine's "
                             "flip-both access-trace probe.")))
    return out


# =====================================================================
# TIER C7-A — cross-dimension length x length independence
# (ADJUDICATED 2026-09-04; see PAUSED_C7.md "ADJUDICATION — APPROVED").
#
# W-E (withdrawn 2026-08-29) covers length x read-gating-DECISION pairs:
# `(len(X) > 1)` is independent of NOTHING when the partner is a decision
# that gates a read — cardinality determines statement shape. It does NOT
# cover length x length pairs from DISJOINT root SELECT families (aspects /
# services / tags⋈tag_followings / notifications-list / notifications-
# unread / contact aspect_memberships — see the full-corpus family census
# in _c7_family_scan2_out.json). Every pair below PASSED the engine's
# flip-both probe (assumption_checker.py test_declared IndependenceAssumption
# branch — trace(flip-both) minus (base ∪ flip-A ∪ flip-B) EMPTY) in
# _probe14_results.json: 14 tested, 14 PASS, 0 FAIL, 0 NOT-TESTABLE.
#
# These are added DIRECTLY to the set (bypassing _addi): _withdrawn_
# independence would otherwise withdraw every one via _GT1_RE, which is
# exactly the W-E class this tier is adjudicated to override. They are also
# added to `already` so no later tier re-declares them (and W-E's note that
# withdrawn pairs stay in `already` is mirrored here for declared pairs).
#
# STAY-DEPENDENT (never declared, per the adjudication): to_ary x actors_row
# (nested), to_ary x mentions / target photos (nested via target),
# notifications-list x notifications-unread (same table, unread ⊂ list),
# same-family ordinal pairs (fact cache can return the same collection
# object), every length x DECISION (W-E), mentions x target photos (co-
# source).
_C7A_LEN_PAIRS = [
    # F1 aspects (records_2) x F2 services (records_3)
    ("(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_rows > 1)",
     "(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_3_rows > 1)"),
    # F1 aspects x F3 tags (records_6)
    ("(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_rows > 1)",
     "(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_6_rows > 1)"),
    # F1 aspects x F4 notifications list (to_ary_1)
    ("(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_rows > 1)",
     "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_ary_1_rows > 1)"),
    # F1 aspects x F5 notifications unread (Relation_records_1)
    ("(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_rows > 1)",
     "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1_rows > 1)"),
    # F1 aspects x F8 contact aspect_memberships (records_1)
    ("(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_rows > 1)",
     "(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_1_rows > 1)"),
    # F2 services x F3 tags
    ("(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_3_rows > 1)",
     "(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_6_rows > 1)"),
    # F2 services x F4 notifications list
    ("(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_3_rows > 1)",
     "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_ary_1_rows > 1)"),
    # F2 services x F5 notifications unread
    ("(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_3_rows > 1)",
     "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1_rows > 1)"),
    # F2 services x F8 contact aspect_memberships
    ("(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_3_rows > 1)",
     "(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_1_rows > 1)"),
    # F3 tags x F4 notifications list
    ("(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_6_rows > 1)",
     "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_ary_1_rows > 1)"),
    # F3 tags x F5 notifications unread
    ("(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_6_rows > 1)",
     "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1_rows > 1)"),
    # F3 tags x F8 contact aspect_memberships (mutually exclusive in corpus —
    # free PASS by construction, still declared per the adjudication)
    ("(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_6_rows > 1)",
     "(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_1_rows > 1)"),
    # F4 notifications list x F8 contact aspect_memberships
    ("(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_ary_1_rows > 1)",
     "(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_1_rows > 1)"),
    # F5 notifications unread x F8 contact aspect_memberships
    ("(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1_rows > 1)",
     "(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_1_rows > 1)"),
]


def _tier_c7a_crossdim_length(exprs, already):
    """The adjudicated cross-dimension length x length independence pairs.
    Bypasses the W-E withdrawal (which would withdraw every pair via _GT1_RE)
    — this tier IS the adjudicated override of W-E for the disjoint-root-
    family length pairs (PAUSED_C7.md ADJUDICATION, 2026-09-04)."""
    out = []
    ex = set(exprs)
    for a, b in _C7A_LEN_PAIRS:
        if a not in ex or b not in ex:
            continue  # only declare what this corpus actually records
        key = frozenset((a, b))
        if key in already:
            continue
        already.add(key)
        out.append(IndependenceAssumption(
            expr_a=a, expr_b=b,
            description=f"C7-A cross-dim len x len (disjoint root families): {a[:52]} || {b[:52]}",
            agent_notes=("ADJUDICATED 2026-09-04 (PAUSED_C7.md); flip-both probe PASS "
                         "(_probe14_results.json, 14/14 PASS, 0 FAIL). Root-disjoint SELECT "
                         "families: neither length gates the other's statement family; the "
                         "cardinality-vs-shape concern of W-E does not arise between two "
                         "statements that never share a row source. W-E override is scoped "
                         "to exactly these pairs.")))
    return out


# C7-A under P0 canonical names (2026-09-08). The 14 ordinal-keyed pairs above
# stop matching once results are named by statement. Of the 14 probes in
# _probe14_results.json only FIVE ran on a snapshot whose readings were the
# declared families (checked dump by dump): aspects x services, aspects x
# tags, services x tags, services x unread, tags x unread. Those five are the
# only claims that carry earned evidence and are re-instantiated here on the
# canonical names. The other nine (every pair involving records_2 read as
# photos, records_1 read as aspects, to_ary_1 read as unread, records_3 read
# as aspects, and tags x aspect_memberships which co-occurs in NO run) are
# NOT re-declared: they need a probe on a matching-reading snapshot first.
_C7A_FAMILY_PAIRS = [("aspects", "services"), ("aspects", "tags"), ("services", "tags"),
                     ("services", "unread"), ("tags", "unread")]
_C7A_FAMILY_RE = {
    "aspects":  re.compile(r"^\(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_aspects_[0-9a-f]{8}_rows > 1\)$"),
    "services": re.compile(r"^\(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_services_[0-9a-f]{8}_rows > 1\)$"),
    "tags":     re.compile(r"^\(SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_tags_[0-9a-f]{8}_rows > 1\)$"),
    "unread":   re.compile(r"^\(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_notifications_[0-9a-f]{8}_rows > 1\)$"),
}


def _tier_c7a_by_family(exprs, already):
    import sys as _sys
    out = []
    found = {f: [e for e in exprs if rx.match(e)] for f, rx in _C7A_FAMILY_RE.items()}
    for fa, fb in _C7A_FAMILY_PAIRS:
        ea, eb = found.get(fa, []), found.get(fb, [])
        if len(ea) != 1 or len(eb) != 1:
            print(f"[assumptions] C7-A by family: {fa} x {fb} skipped — "
                  f"{len(ea)}/{len(eb)} canonical `> 1` exprs (need exactly one each)",
                  file=_sys.stderr)
            continue
        key = frozenset((ea[0], eb[0]))
        if key in already:
            continue
        already.add(key)
        out.append(IndependenceAssumption(
            expr_a=ea[0], expr_b=eb[0],
            description=f"C7-A cross-dim len x len by family: {fa} || {fb}",
            agent_notes=("ADJUDICATED 2026-09-04 (PAUSED_C7.md); flip-both PASS in "
                         "_probe14_results.json on a snapshot whose readings ARE these "
                         "families (verified 2026-09-08). Root-disjoint SELECT families; "
                         "W-E override scoped to exactly this pair.")))
    return out


# --- P2: root-family many-arm (2026-09-09) --------------------------------
# ROOT FAMILIES are the SELECTs that bind ONLY the principal and own their own
# statement: aspects, services, tags JOIN tag_followings (PAUSED_C7 family
# census F1/F2/F3). After the Alias canonicalization each is ONE
# canonical name, so the family is read off the name rather than guessed from
# an ordinal — which is what made the pre-canonical version of this proposal
# unsafe (records_4/5/7/8 were 25-43% a DIFFERENT statement).
#
# CLAIM: the `> 1` arm of a root family's length carries no policy content.
#   * IterableSymbolicList#each yields the representative ONCE regardless of
#     length (targets.rb ~465), so the many-arm is a trace no-op by
#     construction;
#   * no note binds a row of these lists (measured: 0 for N>=3 in a 2 031-dump
#     census; photos and aspect_memberships DO bind rows and are EXCLUDED);
#   * across ~500 same-seed dump pairs differing only in one root-family
#     length, the many-arm added 0 statements and changed 0 multiplicities.
# The `== 0` arm stays TRACKED: an empty list genuinely removes statements.
#
# NOT ratified by the coordinator at time of writing (2026-09-09, user asleep,
# instruction was to keep working). It is declared so the engine's gate PROBES
# it: an UntrackedPath is verified by flipping the branch and requiring an
# identical target trace. A FAIL blocks complete and withdraws the tier.
_P2_ROOT_FAMILIES = ("aspects", "services", "tags")
_P2_RE = re.compile(
    r"^\(SYM_LEN_SYM_RESULT_\w*?CollectionProxy_records_(" +
    "|".join(_P2_ROOT_FAMILIES) + r")_[0-9a-f]{6,}_rows > 1\)$")


def _p2_rootfamily_manyarm(exprs):
    """UntrackedPath for the `> 1` arm of each canonical ROOT-FAMILY length."""
    out = []
    for e in sorted(exprs):
        m = _P2_RE.match(e.strip())
        if not m:
            continue
        out.append(UntrackedPathAssumption(
            expr=e,
            description=f"P2 root-family many-arm ({m.group(1)})",
            agent_notes="root family: binds only the principal, owns its statement, "
                        "each yields the representative once, no note binds its rows. "
                        "The many-arm is a trace no-op; the == 0 arm stays tracked. "
                        "Verified by the gate's flip (identical trace) — FAIL withdraws."))
    return out


# K1 (2026-09-09, OWNER-APPROVED) — the UNREAD notifications ROOT FAMILY.
# Same tier and same criterion as P2, omitted from it only because _P2_RE
# matches `CollectionProxy_records_<family>` and this family is minted as
# `Relation_records_notifications` (notifications_controller.rb:44 ->
# User#unread_notifications, user.rb:109 = `notifications.where(unread: true)`).
#
# P2's criterion, verified on the WHOLE 68 231-dump corpus (not a sample):
#   * statement keys of the 10 716 many-arm runs MINUS the 57 353 not-taken
#     runs -> 0 shapes only on the many arm;
#   * notes binding `...notifications_<hash>_row` anywhere -> 0.
# So the list's cardinality determines NO statement shape: it owns one
# statement keyed on the principal, and nothing is keyed on its rows. The
# badge COUNT (:42) and the mobile header `.size` are separate result names
# (Calculations_count_2/3, Relation_size_1) and are NOT this variable.
#
# W-E does not apply: W-E's mechanism is a statement whose predicate operator
# follows the cardinality (`= ?` vs `IN (...)`). This family is never a
# preload key set and no read is keyed on it. The `== 0` / `== k` compares on
# the same variable STAY TRACKED, exactly as P2 keeps them.
#
# Falsifier (gate `assumption_checker.py` `test_declared`, UntrackedPath
# branch): flip the seed len(...records_1_rows) 1 <-> 3, replay, and require
# `delta = base ^ other` over target-call shapes to be EMPTY. FAIL withdraws.
# K1 inherits P2's status: declared and gate-probed, NOT ratified. If P2 is
# rejected, K1 falls with it.
_K1_RE = re.compile(
    r"^\(SYM_LEN_SYM_RESULT_\w*?Relation_records_notifications_[0-9a-f]{6,}_rows > 1\)$")


def _k1_unread_root_manyarm(exprs):
    """UntrackedPath for the `> 1` arm of the unread-notifications root family."""
    out = []
    for e in sorted(exprs):
        if not _K1_RE.match(e.strip()):
            continue
        out.append(UntrackedPathAssumption(
            expr=e,
            description="K1 unread-notifications root-family many-arm",
            agent_notes="root family: binds only the principal, owns its statement, "
                        "nothing is keyed on its rows (measured: 0 many-arm-only "
                        "statement shapes, 0 notes binding its rows over 68 231 runs). "
                        "The many-arm is a trace no-op; the == 0 arm stays tracked. "
                        "Verified by the gate's flip (identical trace) — FAIL withdraws. "
                        "Same tier as P2; falls if P2 is rejected."))
    return out


# ---------------------------------------------------------------------------
# _overnight_unreachable_pins (2026-09-10) — ONE branch outcome that this
# environment cannot produce. OWNER-INSTRUCTED; NARROWED THE SAME DAY.
#
# It began as THREE. T1/T2 (the federation discovery arm) were pinned because
# taking them SIGSEGVd the JVM before the dump was written, and the assumption
# gate could not even test that pin — it probes by FLIPPING the branch, which
# is the very action that aborts, so it reported
# `FAIL: flip probe produced no dump` (`_assum_pins_results.json`). The
# coordinator then AUTHORISED the boundary change that removes the cause:
# `targets.rb` §5h-bis now walls `DiasporaFederation::Discovery#fetch_and_save`
# in its RAISING form (the shape `comments_index` closed with). Both branches
# are OBSERVABLE now, so both pins are DELETED. Only T10 remains, and it
# PASSED the gate on its own merits.
#
# Authorisation. Owner instruction of 2026-09-10 ~08:00 ("continue working till
# all endpoints are complete"), relayed by the coordinator with the explicit
# direction to install these three pins as a separate, separately-counted tier
# rather than leaving them as proposals. Everything below is the evidence that
# was gathered BEFORE the instruction; the full write-up is
# `_COMPLETION_CAMPAIGN_20260910.md` §7.4 / §7.6 / §7.7 and the BOUNDARY
# CHANGES section of `AGENT_RUN.md`.
#
# This tier is DELIBERATELY REVERSIBLE: delete the remaining entry (or set
# `_OVERNIGHT_PINS = ()`) and the endpoint reports exactly as it did before.
# The report always carries BOTH numbers — shipped (with the pin) and
# `NO_PINS=1 SUMMARY_OUT=…` (without).
#
# Authorisation. Owner instruction of 2026-09-10 ~08:00 ("continue working till
# all endpoints are complete"), relayed by the coordinator with the explicit
# direction to install the unreachable-side pins as a separate,
# separately-counted tier rather than leaving them as proposals; then the
# coordinator's 2026-09-10 ruling authorising the `fetch_and_save` wall, which
# retired two of the three. Full write-up:
# `_COMPLETION_CAMPAIGN_20260910.md` §7.4 / §7.6 / §7.7 / §8, and the
# BOUNDARY CHANGES section of `AGENT_RUN.md`.
#
# ---- WHAT T1/T2 WERE, AND WHY THEY ARE GONE (kept as the record) ----------
#   (…Core__ClassMethods_find_by_1_not_found == True)         :: taken
#   (…Core__ClassMethods_find_by_1_profile_not_found == True) :: taken
# `find_by_1` is `Person.by_account_identifier`; either decision taking True
# sends `Person.find_or_fetch_by_identifier` (person.rb:318-329, reached from
# mentionable.rb:89) into `Discovery#fetch_and_save`, which SIGSEGVd in
# libcurl (`curl_easy_setopt` -> `__libc_free`, via com.kenai.jffi) BEFORE the
# dump was written. Evidence: control-vs-flip on one seed (base rc=0/1 path;
# base+flip rc=134/0 paths); 37 of 37 toxic seeds in the C32A bulk drive set
# one of the two, 0 of the 25.6 % that set neither; and the 2026-08-15
# registrations_create crash isolation reached the same conclusion. The gate
# could not test the pin — it probes by FLIPPING the branch, i.e. by doing the
# thing that aborts — and reported `FAIL: flip probe produced no dump`
# (`_assum_pins_results.json`). The coordinator then authorised the RAISING
# `fetch_and_save` wall (`targets.rb` §5h-bis, the form comments_index closed
# with), which removes the cause: smoke run
# `dump_json_plain_dse0001_C8WALLSMOKE.json` records
# `find_by_1_not_found == True :: taken`, rc=0, no `hs_err_pid`, with the
# wall's `call` event at person.rb:325. **A branch that can be driven is never
# argued**, so both pins are DELETED rather than kept.
#
# ---- T10 — the empty username (the one that remains) ----------------------
#   (…FinderMethods_devise_user_first_1_username == '') :: taken
# The compare is `String#blank?` (activesupport …/object/blank.rb:126) and
# fires ONLY in the two mobile variants, between `_drawer.mobile.haml:28` and
# `current_user.admin?` at `:40`. Line 33 of that same partial is
#     = link_to user_profile_path(current_user.username) do
# and config/routes.rb:189 is
# `get '/u/:username' => 'people#show', as: 'user_profile',
#  constraints: {username: /[^\/]+/}`.
# The helper's argument is evaluated BEFORE `link_to` runs, so every path that
# reaches the compare has already generated that URL, and `''` cannot generate
# it. MEASURED: 38 of 38 rooted runs with the seed honoured (`symbolic_vars`
# shows `value: ''`) reach 86-90 path conditions and then raise
# `No route matches {…:username=>""}` at journey/formatter.rb:57; the compare
# is never reached. app/models/user.rb:37-38 agrees — `username` is
# `presence: true`, format `/\A[A-Za-z0-9_]+\z/` — so no persisted row holds
# `''`.
# GATE VERDICT (2026-09-10, `_assum_pins_results.json`): **PASS** — "flipping
# the variable leaves the PC unevaluated — the other side is unreachable by
# construction". The gate re-derived the argument from its own probe.
# FALSIFIER: any run that records that compare as taken, which needs the route
# constraint or the drawer's ordering to change.
# ---------------------------------------------------------------------------
_OVERNIGHT_PINS = (
    ("(SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_username == '')",
     "T10: _drawer.mobile.haml:33 generates /u/:username two lines above the "
     "compare and routes.rb:189 constrains it to /[^/]+/; 38/38 rooted runs "
     "raise No route matches before the compare; user.rb:37-38 forbids '' "
     "in the table anyway. GATE 2026-09-10: PASS."),
)


def _overnight_unreachable_pins(exprs):
    """OneSideUntracked('not_taken' tracked) for each unobservable side."""
    out = []
    present = set(exprs)
    for e, why in _OVERNIGHT_PINS:
        if e in present:
            out.append(OneSideUntrackedPathAssumption(
                expr=e, tracked_side="not_taken",
                description="overnight unreachable pin (owner-instructed 2026-09-10)",
                agent_notes=why))
    return out


# ===========================================================================
# OWNER ROOT PIN (2026-09-11) — the FICTIONAL principal
# ===========================================================================
# Coordinator ruling of 2026-09-11, deciding §16 of
# `_COMPLETION_CAMPAIGN_20260910.md`: "(b) Install the ROOT pin only:
# OneSideUntracked on `devise_user_first_1_person_not_found`'s NOT-FOUND side
# — the fictional state." Installed here as its OWN tier, counted and printed
# separately from `_OVERNIGHT_PINS`, so the line says exactly what it costs and
# deleting the tuple is a one-line reversal.
#
# THE PIN
#   (…FinderMethods_devise_user_first_1_person_not_found == True) :: taken
# i.e. only the FOUND side is demanded; "the signed-in principal has no Person"
# is removed from the demand universe.
#
# EVIDENCE 1 — the app cannot produce it.
#   ruby_examples/dse-apps/apps/diaspora/app/models/user.rb
#     47    validates :person, presence: true
#     48    validates_associated :person
#     54    has_one :person, inverse_of: :owner, foreign_key: :owner_id
#     55    has_one :profile, through: :person
#   and the only construction path, `User.build` -> `setup` (l. 407-427), ends
#   in `self.set_person(Person.new(...))` (l. 424, and `set_person` at 429-432)
#   after `self.valid?`. A persisted, valid `User` therefore always has a
#   `Person`; `current_user.person` being nil is a state the mock can mint and
#   the application cannot reach.
#
# EVIDENCE 2 — nothing downstream is unique to the pinned side. From the §16b
#   inferred foreclosure relation over the 96 299-profile pruned corpus
#   (`_forecl.json`, the engine's own `infer_foreclosures`):
#       decisions evaluated ONLY under the NOT-FOUND (taken) side:  0
#       decisions evaluated ONLY under the FOUND (not_taken) side: 22
#   So pinning hides no query: there is no downstream statement that only the
#   fictional principal reaches. The 22 the other way are the ordinary
#   person/profile reads that only happen once a person exists.
#
# EVIDENCE 3 — what it removes, measured on `_remaining_e1.jsonl` (the exact
#   enumerated remaining set, 24 122 assignments): 424 of the 1 560
#   MULTI-GATE-FORECLOSED cubes fix this side, and 3 047 of the 22 562
#   REACHABLE ones do — ~3 471 assignments in total. The 3 047 are "reachable"
#   only because the mock produced the fictional root, so removing them is the
#   point of the pin, not collateral.
#
# WHAT THIS PIN DOES **NOT** DO. It does not account for the 1 560. The other
# 1 136 of them fix the FOUND side and stay demanded; per the same ruling they
# are DRIVING BACKLOG, not a declaration — the corpus already produces the
# "find_by_1 hit ∧ find_by_2 miss" shape they need in 38 of 771 co-evaluating
# runs (§16.3, witnesses named there). The 16-pin unconditional cover was
# REJECTED by the same ruling: it would have deleted 5 582 legitimate
# reachable cubes (24.7 %).
#
# FALSIFIER. Any run that records this compare TAKEN with a target-call shape
# not already seen under the found side — i.e. a real downstream query reached
# only by a person-less principal. Evidence 2 is the standing measurement of
# that, and it is re-derived by every `_forecl_dump.py` run.
# WITHDRAWN 2026-09-11, BEFORE IT EVER SHIPPED A NUMBER — and the withdrawal
# is the measurement, not a change of mind.
#
# The ruling's own condition was "keep it only if its side is still never
# realised". It is realised constantly: over a 20 000-dump random sample of the
# 111 130-profile pruned corpus, the compare is recorded
#     TAKEN     (person NOT found)  3 466   (17.3 %)
#     not_taken (person found)     14 887
# with the variable minted `True` in exactly those 3 466 runs — e.g.
# `dump_html_plain_dse0849.json` (an ORIGINAL corpus dump, not a demand seed),
# `dump_html_plain_dse0227_C32Ahtmp0000r0.json`,
# `dump_json_typed_dse0292_DR2jsotr0.json`. No construction was needed to find
# them; the runner produces the side as a matter of course.
#
# Why the evidence looked sufficient and was not. `user.rb:47-48,54` is a fact
# about the real Rails app, and the "0 decisions / 0 statements evaluated ONLY
# under that side" measurement is a fact about what is DOWNSTREAM of it —
# neither is a statement about whether THIS harness can walk the branch, and
# the branch is a seeded boolean the harness sets freely. "The application
# cannot reach this state" and "this endpoint's decision cannot take this
# outcome" are different claims, and only the second licenses a pin. That is
# the same error §16 rejected for the 16-pin cover, arrived at from the other
# direction.
#
# A branch that can be driven is never argued (the rule that retired T1/T2).
# These 3 471 assignments are DRIVING BACKLOG.
_OWNER_ROOT_PIN = ()


def _owner_root_pin(exprs):
    """OneSideUntracked('not_taken' tracked): only the FOUND side is demanded."""
    out = []
    present = set(exprs)
    for e, why in _OWNER_ROOT_PIN:
        if e in present:
            out.append(OneSideUntrackedPathAssumption(
                expr=e, tracked_side="not_taken",
                description="owner root pin (fictional person-less principal, "
                            "owner-ruled 2026-09-11)",
                agent_notes=why))
    return out


def _ownprofile_untracked(exprs):
    """The person_link_class own-profile compare `current_user.person ==
    person` (people_helper.rb:81-86) decides ONLY a CSS class ("self" vs
    "hovercardable") — it issues NO query and reaches NO target either way.
    Every var-vs-var compare of a rendered person's id against the principal
    (`<X>_(id|person_id|author_id) == <principal>_person_id`) is exactly this
    display-only branch (the only place on this endpoint comparing a rendered
    person to current_user.person). Its outcome is irrelevant to the access
    pattern, so the branch is UntrackedPath: flipping it leaves the target
    trace identical (the engine verifies). (Semantically the actor of a
    notification is never its recipient, so the True side is also real-
    impossible — but access-irrelevance is the sound, checkable criterion.)"""
    out = []
    for e in sorted(exprs):
        m = re.match(r"^\(([A-Za-z_][A-Za-z0-9_]*) (?:==|!=) ([A-Za-z_][A-Za-z0-9_]*)\)$", e.strip())
        if not m:
            continue
        l, r = m.group(1), m.group(2)
        if _is_principal(l) != _is_principal(r):  # exactly one side is the principal
            out.append(UntrackedPathAssumption(
                expr=e,
                description=f"own-profile compare, display-only (CSS class): {e[:60]}",
                agent_notes="people_helper.rb person_link_class `current_user.person == person` decides "
                            "only a CSS class; no query/target differs on either side — access-irrelevant, "
                            "so the branch is untracked (flip leaves the target trace identical)."))
    return out


def _display_untracked(exprs):
    """DISPLAY-ONLY decision families — branches whose outcome changes only
    rendered text / CSS and issues NO query and reaches NO target either way,
    so the branch is irrelevant to the access pattern (UntrackedPath: flip
    leaves the target trace identical; the engine verifies). Per code reading:
      * `_guid == ''` / `_guid != ''` — person_link_class / remote_or_hovercard
        hovercard-link display (people_helper.rb).
      * `_first_name == ''` / `_last_name == ''` / `_profile_first_name` /
        `_profile_last_name` — Person.name_from_attrs (a SHIM reaching zero
        targets): the blank-name -> handle fallback is a display name.
      * `_public_details == True` — PersonPresenter show_profile_info: public
        vs private profile hash reads more columns of the SAME loaded profile
        rep, no new query.
      * `_birthday_year <= 1004` (and other year compares) — birthday_format
        date-format choice (display).
      * `_count < N` / `_count == N` / `_count > N` — the badge count
        (`> 0`), the actor sentence (`number_of_actors < 4`) and the i18n
        pluralization (`== 1`): display only. The row CARDINALITY is the list
        LENGTH (`len(...)`, kept), not these count compares.
    KEPT (access-relevant, covered by exploration): `_persisted`, `_not_found`,
    `_text_nil`, `_text_has_mention`, `_mention_inline_name`, `len(...)`."""
    out = []
    # `_text_has_mention` / `_mention_inline_name` only SELECT the seeded text
    # STRING; nothing that reads it issues a query on this endpoint (the
    # message title renderer is mocked X6l, and people_from_string is mocked
    # to [] X6f — mentioned_people never queries). (`_text_nil` is KEPT — it
    # gates the photos query in post_page_title; `_persisted` is KEPT — it
    # gates the mentioned_people mentions query.)
    #
    # WITHDRAWN 2026-08-27 after the gate FAILED three of these (HARD RULE 5,
    # never re-declared): `_sharing`/`_receiving` (the contact relationship
    # compare in PersonPresenter#relationship's `.find` picks a branch that
    # DOES change the access trace) and the NOTIFICATION-TARGET-chain guids
    # (`..._target_..._guid`) — flipping the target/mention-container guid
    # changed target-call shapes, so it is access-relevant. The actor/person
    # guids (person_link hovercard) remain display-only (all PASSed the gate),
    # so guid is still untracked EXCEPT on the `_target` chain.
    display_suffix = ("_guid", "_first_name", "_last_name",
                      "_public_details", "_birthday_year",
                      "_text_has_mention", "_mention_inline_name")
    for e in sorted(exprs):
        # skip var-vs-var (handled by _ownprofile_untracked) and dispatch
        if _DISPATCH_RE.match(e):
            continue
        v = _leftvar(e)
        if not v:
            continue
        # ALL notification-TARGET-chain guids are access-relevant (the gate
        # rejected untracking `_target_guid`, `_mentions_container_guid` AND
        # the deeper `_commentable_guid` — flipping each changed target-call
        # shapes). Do NOT untrack any guid on the `_target` chain; only the
        # actor/person hovercard guids stay untracked (all PASSed). Target
        # guid combos are observed by exploration.
        if v.endswith("_guid") and "_target" in v:
            continue
        is_count = ("_count" in v) and bool(re.search(r"(==|<=|>=|<|>)\s*-?\d+\)$", e))
        is_display = any(v.endswith(suf) for suf in display_suffix) or is_count
        if not is_display:
            continue
        out.append(UntrackedPathAssumption(
            expr=e,
            description=f"display-only branch (no query differs): {e[:55]}",
            agent_notes="the outcome changes only rendered text / CSS / date-format / pluralization "
                        "(hovercard guid, name_from_attrs display name, public-vs-private profile hash "
                        "of the loaded rep, badge/actor-sentence count) and issues no query and reaches "
                        "no target either way — access-irrelevant (flip leaves the target trace identical)."))
    return out


# =====================================================================
# WITHDRAWN — declarations the MANDATORY assumption gate REJECTED
# (cycle 6, 2026-08-28; gate of 2026-08-28 14:08: 17 471 PASS / 28 FAIL).
#
# HARD RULE: a rejected declaration is WITHDRAWN. It is never re-declared in
# another form, never moved to UntrackedPath, and never narrowed to "the one
# rep that failed" — the gate's probe picks ONE snapshot per declaration, so a
# sibling PASS on another rep is a property of the probe corpus, not of the
# code. Each class below is withdrawn WHOLE, and the combinations it used to
# exempt are demanded by the coverage checker and covered by exploration.
#
#   W-A  UntrackedPath over a DISPLAY-suffix decision (`_guid`, `_first_name`,
#        `_last_name`, `_public_details`, `_birthday_year`, `_text_has_mention`,
#        `_mention_inline_name`).  20 of the 28 FAILs; every suffix in the
#        family failed on at least one rep ("flipping the branch changed 3/4/10
#        target-call shape(s)"). The mechanism is real: a blank first/last name
#        reaches `Person#name` -> `fix_profile` -> `reload`
#        (`SELECT "people".* … LIMIT 1`), and `_text_has_mention` gates the
#        mentions read. The ONLY survivor of `_display_untracked` is the badge
#        COUNT compare (`…_count_2_count > 0`), which the gate PASSed and whose
#        outcome changes an i18n string.
#   W-B  UntrackedPath over the own-profile var-vs-var compare
#        (`_ownprofile_untracked`).  FAILed on
#        `…_to_ary_1_row_actors_row_id == …_devise_user_first_1_person_id`
#        (3 target-call shapes). The tier also mis-matched `X == True` as a
#        var-vs-var compare (its regex accepts `True` as a variable), which is
#        how `…_devise_user_first_1_person_not_found == True` — a real has_one
#        not-found decision — was ever declared display-only. Withdrawn whole.
#   W-C  Independence between an STI DISPATCH compare (`SYM_POST_STI`,
#        `SYM_NOTE_TYPE_PROFILE`) and a `_not_found` decision.  FAILed on
#        `SYM_POST_STI == 0/1` x `…_mentions_container[_commentable]_author_
#        profile_not_found` ("flip both produced 4 target-call shapes absent
#        from base/flip-A/flip-B: find_target ; reload ; load_intermediate").
#        The dispatch value decides WHICH chain the not-found decision sits on,
#        so the pair is genuinely joint. Dispatch-independence survives for
#        every other decision kind.
#   W-D  Independence between the profile-DISPLAY link family (`_disp_has_dlink`,
#        `_disp_dlink_is_post`, `_disp_dlink_guid`) and a contact-relationship
#        decision (`_sharing` / `_receiving`) or a person-identity var-vs-var
#        compare.  FAILed on 4 pairs ("flip both produced `exists?` +
#        `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT 1`):
#        `_sharing` is what makes `PersonPresenter` render the bio at all, so
#        the bio's diaspora-link probe is gated by it.
# =====================================================================
_DISPLAY_SUFFIXES_WITHDRAWN = ("_guid", "_first_name", "_last_name",
                               "_public_details", "_birthday_year",
                               "_text_has_mention", "_mention_inline_name")
_DISP_LINK_SUFFIXES = ("_disp_has_dlink", "_disp_dlink_is_post", "_disp_dlink_guid")
_REL_SUFFIXES = ("_sharing", "_receiving")

_VARVAR_RE = re.compile(r"^\(([A-Za-z_][A-Za-z0-9_]*) (?:==|!=) ([A-Za-z_][A-Za-z0-9_]*)\)$")


def _is_varvar_identity(expr):
    m = _VARVAR_RE.match(expr.strip())
    return bool(m) and m.group(2) not in ("True", "False")


def _withdrawn_untracked(u):
    """W-A / W-B. Survivors: the badge COUNT compare, and the Journey
    formatter's `<rep>_guid != StringVal('')` — a DIFFERENT expression at a
    DIFFERENT site (action_dispatch/journey/formatter.rb:41) from the rejected
    `<rep>_guid == ''` blank test, PASSing on all three of its instances, and
    the one whose True side actionpack cannot reach at all (the non-blank guid
    is handled before the compare). The rejected form is the blankness test the
    app itself branches on."""
    e = u.expr
    if _is_varvar_identity(e) or _VARVAR_RE.match(e.strip()):
        return True                      # W-B (incl. the `X == True` mis-match)
    v = _leftvar(e)
    if not v:
        return False
    if v.endswith("_guid"):
        return bool(re.search(r"==\s*(?:StringVal\(\s*''\s*\)|'')\s*\)$", e.strip()))
    if any(v.endswith(suf) for suf in _DISPLAY_SUFFIXES_WITHDRAWN if suf != "_guid"):
        return True                      # W-A
    return False


_GT1_RE = re.compile(r"^\(\s*(?:len\(|SYM_LEN_)[A-Za-z0-9_]+\)?\s*>\s*1\s*\)$")


def _withdrawn_independence(ia):
    a, b = ia.expr_a, ia.expr_b
    va, vb = (_leftvar(a) or ""), (_leftvar(b) or "")
    # W-E (cycle 6, gate of 2026-08-29): a LIST-CARDINALITY decision
    # `(len(X) > 1)` is independent of NOTHING. Since DISCIPLINE §13 Rule D the
    # cardinality DETERMINES the statement shape — `= $(key)` for one row,
    # `IN ($(k1), $(k2), …)` for many — so flipping it together with any
    # decision that gates a read produces a bulk statement absent from both
    # singles. 9 of the gate's 12 FAILs were exactly this, on
    # `SYM_NOTE_TYPE_PROFILE`, `_target_is_photo`, `_text_nil` and the contact
    # finders' `_not_found`. Withdrawn as a class: the cardinality's
    # combinations are OBSERVED, never declared.
    if _GT1_RE.match(a.strip()) or _GT1_RE.match(b.strip()):
        return True
    # W-F: two NOT-FOUND decisions, or a not-found and a person-identity
    # compare, on the contact/principal finder family. With one fact per
    # rendered query (§7) these arms share the finder memo, so the pair
    # produces a `FinderMethods.find_by` shape neither single has (3 FAILs).
    def _nf(v):
        return v.endswith("_not_found")
    if (_nf(va) and _nf(vb)) or \
       (_nf(va) and _is_varvar_identity(b)) or (_nf(vb) and _is_varvar_identity(a)):
        return True
    # W-C: dispatch x not_found
    disp = [x for x in (a, b) if _DISPATCH_RE.match(x)]
    if disp:
        other_v = vb if _DISPATCH_RE.match(a) else va
        if other_v.endswith("_not_found"):
            return True
    # W-D: profile-display link family x contact relationship / identity compare
    def _link(v):
        return any(v.endswith(suf) for suf in _DISP_LINK_SUFFIXES)

    def _partner(v, expr):
        return any(v.endswith(suf) for suf in _REL_SUFFIXES) or _is_varvar_identity(expr)
    if (_link(va) and _partner(vb, b)) or (_link(vb) and _partner(va, a)):
        return True
    return False


class IndexedAssumptionSet(AssumptionSet):
    """Batch-local PERFORMANCE subclass (2026-09-08), same semantics as
    AssumptionSet. The engine asks `are_independent` once per expr pair and
    the base class scans EVERY assumption per call; with the canonical
    universe (~70k expr-keyed declarations, hundreds of exprs) that is
    pairs x assumptions ~ 1e10 matches. Expr-keyed independences (no source
    declared) are exact set lookups, so they are indexed once; any
    source-keyed declaration still goes through the base class. Verified
    equal to the base implementation on a sample in build()."""

    def _index(self):
        if getattr(self, "_idx", None) is None or self._idx_n != len(self.assumptions):
            from concolic_engine.assumptions import _declared
            idx, other = set(), False
            for a in self.assumptions:
                if isinstance(a, IndependenceAssumption):
                    if a.expr_a and a.expr_b and not _declared(a.source_a) and not _declared(a.source_b):
                        idx.add(frozenset((a.expr_a, a.expr_b)))
                    else:
                        other = True
            self._idx, self._idx_other, self._idx_n = idx, other, len(self.assumptions)
        return self._idx

    def are_independent(self, source_a, source_b, expr_a="", expr_b=""):
        idx = self._index()
        if expr_a and expr_b:
            if expr_a == expr_b:
                return False
            if frozenset((expr_a, expr_b)) in idx:
                return True
            if not self._idx_other:
                return False
        return AssumptionSet.are_independent(self, source_a, source_b, expr_a, expr_b)


def build(runs=None) -> AssumptionSet:
    aset = IndexedAssumptionSet()
    if not runs:
        return aset
    exprs, expr_dispatch, dispatch_absent, coeval = _observations(runs)

    already = set()
    n0c = n1 = n2 = 0
    nw_i = [0]
    n_inert = [0]
    # P0/P1 (2026-09-08): the decision alias is DECLARED here so it is in the
    # report's assumption list and the gate probes it; the renaming itself is
    # done at load by coverage_report.canonicalize_ordinals (this batch drops
    # notes after load, so the engine's own apply_aliases finds nothing left
    # to rename and is a no-op on these runs).
    for al in ALIASES:
        aset.add(al)

    def _addi(ia, counter_inc):
        """Add an IndependenceAssumption unless (a) no run ever evaluated the
        pair together — under co-evaluation semantics (2026-09-10) there is no
        demand to relax and the declaration would be pure noise in the report
        and in the gate — or (b) its CLASS was withdrawn by the gate (the
        WITHDRAWN block above). Either way the pair stays in `already` so no
        later tier can re-declare it in another form."""
        key = frozenset((ia.expr_a, ia.expr_b))
        already.add(key)
        if key not in coeval:
            n_inert[0] += 1
            return 0
        if _withdrawn_independence(ia):
            nw_i[0] += 1
            return 0
        aset.add(ia)
        return counter_inc

    for ia in _tier0c_dispatch_independence(exprs, expr_dispatch, already):
        n0c += _addi(ia, 1)
    for ia in _tier0d_crossdispatch(exprs, already):
        n0c += _addi(ia, 1)
    # WITHDRAWN 2026-08-27 (gate FAIL, HARD RULE 5): _tier_persisted_textnil
    # declared `_persisted` ⊥ `_text_nil` as disjoint query families, but they
    # INTERACT — the photos query (`SELECT photos.* WHERE status_message_id =
    # ?` / its COUNT) fires only when persisted=True AND text_nil=True (the
    # post's photos association loads only when persisted, and the photos
    # branch is taken only when the message is blank). Their combinations are
    # therefore OBSERVED by exploration, not declared away. (The function
    # itself was deleted 2026-09-10 — dead code since the withdrawal.)
    for ia in _tier_guid_foreclosed_by_persisted(exprs, already):
        n0c += _addi(ia, 1)
    for ia in _tier1c_empty_list_foreclosure(exprs, already):
        n1 += _addi(ia, 1)
    for ia in _tier1_samerep_foreclosure(exprs, already):
        n1 += _addi(ia, 1)
    # C7-A — adjudicated cross-dimension length x length independence (the
    # W-E override for disjoint-root-family length pairs). MUST run BEFORE
    # _tier2_disjoint_reps: tier2 adds every cross-rep pair (length ones
    # included) to `already`, which would skip every C7-A pair. Added
    # DIRECTLY (bypasses _withdrawn_independence by adjudication); each pair
    # passed the flip-both probe (_probe14_results.json: 14/14 PASS, 0 FAIL).
    # Still filtered by co-evaluation: an adjudicated pair no run evaluates
    # together relaxes nothing.
    n_c7a = 0
    for ia in list(_tier_c7a_crossdim_length(exprs, already)) + \
            list(_tier_c7a_by_family(exprs, already)):
        if frozenset((ia.expr_a, ia.expr_b)) not in coeval:
            n_inert[0] += 1
            continue
        aset.add(ia)
        n_c7a += 1
    for ia in _tier2_disjoint_reps(exprs, already):
        n2 += _addi(ia, 1)
    nu = 0
    nw_u = 0
    _k1_list = list(_k1_unread_root_manyarm(exprs))
    n_k1 = 0
    for u in (list(_ownprofile_untracked(exprs)) + list(_display_untracked(exprs))
              + list(_p2_rootfamily_manyarm(exprs)) + _k1_list):
        if _withdrawn_untracked(u):
            nw_u += 1
            continue
        aset.add(u); nu += 1
        if u in _k1_list:
            n_k1 += 1
    # (guid is fully covered by _display_untracked now; the formatter one-side
    # is redundant and would double-declare the same expr.)
    # OVERNIGHT PINS — counted and printed SEPARATELY so the line says exactly
    # what they cost, and so deleting the tier is a one-line reversal.
    n_pin = 0
    for u in _overnight_unreachable_pins(exprs):
        aset.add(u); n_pin += 1
    # OWNER ROOT PIN — its own counter, for the same reason.
    n_root = 0
    if os.environ.get("NO_ROOT_PIN") != "1":
        for u in _owner_root_pin(exprs):
            aset.add(u); n_root += 1
    import sys
    print(f"[assumptions] tier0c(dispatch)={n0c} tier1(foreclose)={n1} "
          f"tier2(disjoint-rep)={n2} C7-A(cross-dim-len)={n_c7a} untracked={nu} "
          f"K1={n_k1} OVERNIGHT_PINS={n_pin} OWNER_ROOT_PIN={n_root} "
          f"WITHDRAWN(indep)={nw_i[0]} WITHDRAWN(untracked)={nw_u} "
          f"INERT(never-co-evaluated, not declared)={n_inert[0]} "
          f"exprs={len(exprs)} co-evaluated-pairs={len(coeval)}", file=sys.stderr)
    # self-check of the index against the base implementation (a loosened
    # check without a test that still fails is indistinguishable from a
    # deleted check — DISCIPLINE §14): 2 000 random pairs must agree.
    import random as _rnd
    _rnd.seed(20260908)
    _ex = list(exprs)
    for _ in range(2000):
        _a, _b = _rnd.choice(_ex), _rnd.choice(_ex)
        assert aset.are_independent(None, None, _a, _b) == \
            AssumptionSet.are_independent(aset, None, None, _a, _b), (_a, _b)
    return aset
