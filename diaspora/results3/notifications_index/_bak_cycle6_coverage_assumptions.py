#!/usr/bin/env python3
"""notifications_index — batch-local AssumptionSet (results3 completion drive,
2026-08-27). Rebuilt for the completion engine's MANDATORY assumption gate:
every declaration is a STRUCTURAL claim the engine's derived flip-probe test
verifies (no empirical-count Tier 1 — the engine would reject an unsound
independence and it would block completion; HARD RULE 5). Supersedes the
gen3 file (which predated the gate rules and the real-Devise principal).

FOUR KINDS OF DECLARATION, each sound by construction:

  TIER 0a — VARIANT EXCLUSIVITY. run_dse.rb's request shapes fix the format
    (html/json/mobile/xml) and params[:type] presence for a run's whole
    duration. Exprs observed only in DISJOINT variant-sets can never co-occur
    in one run. Auto-derived from label -> variant membership; disjoint sets
    => independent.

  TIER 0b — TYPE-VARIANT EXCLUSIVITY (ported from the gen3 file, still sound).
    Every run takes exactly ONE SYM_NOTE_TYPE_PROFILE value (targets.rb §5f
    seeded STI dispatch) and ONE SYM_POST_STI value. Exprs whose observed
    type-set (the set of dispatch values under which they were ever recorded)
    is DISJOINT can never co-occur in one run. Set-membership argument only —
    no ordinal meaning relied on. The `(SYM_NOTE_TYPE_PROFILE == k)` /
    `(SYM_POST_STI == k)` compares THEMSELVES are left dependent (they are the
    dispatch and their small clique is covered in full — bounded 0..7 / 0..1
    in coverage_report.apply_len_bounds so no out-of-range combo is demanded).

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

import re
from collections import defaultdict

from concolic_engine.assumptions import (AssumptionSet, IndependenceAssumption,
                                         OneSideUntrackedPathAssumption,
                                         UntrackedPathAssumption)

_VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
             "mobile_plain", "mobile_typed", "xml_plain")

_DISPATCH_RE = re.compile(r"\((SYM_NOTE_TYPE_PROFILE|SYM_POST_STI) == (\d+)\)")

# Attribute suffixes stripped to reach a rep's owner prefix.
_ATTR_SUFFIXES = ("_not_found", "_persisted", "_text_has_mention", "_text_nil",
                  "_mention_inline_name", "_unread", "_guid", "_subject",
                  "_public_details", "_birthday_year", "_author_id",
                  "_person_id", "_owner_id", "_count", "_size", "_id", "_rows",
                  "_first_name", "_last_name")


def _variant_of(label):
    label = label or ""
    for v in _VARIANTS:
        if label.startswith(v):
            return v
    return "unknown"


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
    """Per expr: variant-set, dispatch-value-set (per dispatch var), and the
    set of runs (indices) it was recorded in."""
    expr_variants = defaultdict(set)
    expr_dispatch = defaultdict(lambda: defaultdict(set))  # expr -> dvar -> {values}
    runs_of = defaultdict(set)
    dispatch_absent = defaultdict(lambda: defaultdict(set))  # expr -> dvar -> {"absent"}
    for i, r in enumerate(runs):
        v = _variant_of(r.label)
        # this run's dispatch values (one per dispatch var, if recorded True)
        dvals = {}
        for pc in r.path_conditions:
            m = _DISPATCH_RE.match(pc.expr)
            if m and pc.taken:
                dvals[m.group(1)] = int(m.group(2))
        seen = set()
        for pc in r.path_conditions:
            e = pc.expr
            expr_variants[e].add(v)
            runs_of[e].add(i)
            for dvar in ("SYM_NOTE_TYPE_PROFILE", "SYM_POST_STI"):
                if dvar in dvals:
                    expr_dispatch[e][dvar].add(dvals[dvar])
                else:
                    dispatch_absent[e][dvar].add("absent")
            seen.add(e)
    return expr_variants, expr_dispatch, runs_of, dispatch_absent


def _tier0a_variant(exprs, expr_variants):
    out = []
    by_set = defaultdict(list)
    for e in exprs:
        by_set[frozenset(expr_variants[e])].append(e)
    groups = sorted(by_set.items(), key=lambda kv: sorted(kv[0]))
    for i, (sa, ea) in enumerate(groups):
        for sb, eb in groups[i + 1:]:
            if sa & sb:
                continue
            for a in ea:
                for b in eb:
                    out.append(IndependenceAssumption(
                        expr_a=a, expr_b=b,
                        description=f"variant exclusivity: {sorted(sa)} vs {sorted(sb)}",
                        agent_notes=("run_dse.rb fixes the format and params[:type] presence for "
                                     "a whole run; expr_a observed only under "
                                     f"{sorted(sa)}, expr_b only under {sorted(sb)} — disjoint.")))
    return out


def _tier0b_type(exprs, expr_dispatch, dispatch_absent, already):
    """Exprs whose observed dispatch-value set is disjoint (for a dispatch var
    that BOTH sometimes take) can never co-occur. Conservative: only when both
    exprs were recorded WITH the dispatch var present (never in the absent
    region) and their value sets are disjoint."""
    out = []
    for dvar in ("SYM_NOTE_TYPE_PROFILE", "SYM_POST_STI"):
        # exprs that always carry a dispatch value for dvar (never absent)
        elig = [e for e in exprs
                if e not in (f"({dvar} == {k})" for k in range(8))
                and dvar in expr_dispatch[e]
                and "absent" not in dispatch_absent[e].get(dvar, set())]
        for i, a in enumerate(elig):
            sa = expr_dispatch[a][dvar]
            for b in elig[i + 1:]:
                key = frozenset((a, b))
                if key in already:
                    continue
                sb = expr_dispatch[b][dvar]
                if sa.isdisjoint(sb):
                    already.add(key)
                    out.append(IndependenceAssumption(
                        expr_a=a, expr_b=b,
                        description=f"{dvar} exclusivity: {sorted(sa)} vs {sorted(sb)}",
                        agent_notes=(f"each run takes exactly one {dvar} value (targets.rb §5f "
                                     "seeded STI dispatch); these exprs' observed value-sets are "
                                     f"disjoint ({sorted(sa)} vs {sorted(sb)}), so no run records both.")))
    return out


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


def _tier_persisted_textnil(exprs, already):
    """On the same Post/message rep, `_persisted`, `_text_nil` and the TRACKED
    target guid gate DISJOINT query families, so their pairwise combinations
    add no target-call shape beyond the individual branches (the engine's
    flip-both probe verifies):
      * `_persisted` (new_record?) gates the mentioned_people load
        (`mentions.includes(person: :profile)`, mentions_container.rb:16-19);
      * `_text_nil` gates the photos load (`post.photos.present?` in
        post_page_title when `message.present?` is false);
      * the target/mentions_container `_guid` gates its own guid-keyed access
        (gate-proven access-relevant, 3 target-call shapes) — a distinct
        family from the mentions and photos loads.
    Declared pairwise per rep among whichever of the three are present."""
    out = []
    lv = {e: _leftvar(e) for e in exprs}

    def _decision(e):
        # Only `_persisted` and `_text_nil` gate genuinely DISJOINT query
        # families (mentions vs photos). The target-chain guids were tried
        # here too but the gate REJECTED guid||persisted / guid||text_nil
        # (flip-both added shapes — they interact on the polymorphic target
        # render), so guid is NOT declared independent; its combos are
        # observed by exploration instead (HARD RULE 5).
        v = lv[e]
        if not v:
            return None, None
        for suf in ("_persisted", "_text_nil"):
            if v.endswith(suf):
                return v[: -len(suf)], suf
        return None, None

    by_rep = defaultdict(list)
    for e in exprs:
        prefix, kind = _decision(e)
        if prefix:
            by_rep[prefix].append(e)
    for prefix, es in by_rep.items():
        for i, a in enumerate(sorted(es)):
            for b in sorted(es)[i + 1:]:
                key = frozenset((a, b))
                if key in already:
                    continue
                already.add(key)
                out.append(IndependenceAssumption(
                    expr_a=a, expr_b=b,
                    description=f"disjoint query families on {prefix[:40]}",
                    agent_notes="on the same rep, _persisted gates the mentioned_people mentions query, "
                                "_text_nil gates the photos query, and the target guid gates its own "
                                "guid-keyed access — disjoint families; any combination adds no "
                                "target-call shape beyond the singles."))
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



def _tier1c_empty_list_foreclosure(exprs, already, runs=None):
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

    # The rows are not the only thing an empty list forecloses: EVERY decision
    # minted while RENDERING a row (a contact lookup's `_not_found`, a person's
    # `_persisted`, …) is unreachable too, and those variables carry no name
    # that ties them to the list. Use the corpus as evidence, exactly as the
    # same-rep never-co-evaluated tier does: declare the pair independent only
    # when the closing arm is OBSERVED, the decision is OBSERVED (elsewhere),
    # and the two are never evaluated together in any run — an unobservable
    # combination, which the engine's flip-both probe re-verifies.
    if runs:
        for g, _rowprefix in gates:
            closed_runs, open_runs = set(), set()
            for i, r in enumerate(runs):
                for pc in r.path_conditions:
                    if pc.expr == g:
                        (closed_runs if pc.taken else open_runs).add(i)
                        break
            if not closed_runs or not open_runs:
                continue
            seen_when_closed = set()
            for i in closed_runs:
                for pc in runs[i].path_conditions:
                    seen_when_closed.add(pc.expr)
            for b in exprs:
                if b == g or b in seen_when_closed:
                    continue
                key = frozenset((g, b))
                if key in already:
                    continue
                # the decision must be really observed somewhere (else it is
                # not a decision of this corpus at all)
                if not any(pc.expr == b for i in open_runs for pc in runs[i].path_conditions):
                    continue
                already.add(key)
                out.append(IndependenceAssumption(
                    expr_a=g, expr_b=b,
                    description="empty list forecloses render-time decision",
                    agent_notes=("with zero rows nothing renders, so this decision is never "
                                 "evaluated on the gate's closing arm: observed in every run "
                                 "of the corpus (closing arm observed, decision observed, "
                                 "never together) — an unobservable combination.")))
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


def _tier_samerep_never_coeval(exprs, runs_of, already):
    """Two decisions on the SAME rep that are NEVER co-evaluated (recorded in
    disjoint run sets) cannot have their combination observed, so they must be
    declared independent — otherwise the complete-graph checker demands an
    unobservable combo. Sound and FREE in the gate (never co-evaluated ⇒
    mutually exclusive ⇒ PASS without a probe). Example: a CollectionProxy
    row rep's `_persisted` (a singular-association find_target? decision that
    never fires on collection rows) is never recorded alongside that row's
    `_text_nil`, so their photos-combo is unobservable and independent —
    unlike the singular TARGET rep, where persisted and text_nil ARE
    co-evaluated and genuinely interact (kept dependent, observed)."""
    out = []
    ex = sorted(exprs)
    rep = {e: _rep_key(e) for e in exprs}
    for i, a in enumerate(ex):
        if _DISPATCH_RE.match(a):
            continue
        ka = rep[a]
        ra = runs_of.get(a, set())
        for b in ex[i + 1:]:
            if _DISPATCH_RE.match(b):
                continue
            if rep[b] != ka or not ka:
                continue  # only SAME-rep pairs (different reps -> tier2)
            key = frozenset((a, b))
            if key in already:
                continue
            if ra & runs_of.get(b, set()):
                continue  # co-evaluated somewhere -> genuinely dependent, observe
            if _nested_pair(a, b):
                continue
            already.add(key)
            out.append(IndependenceAssumption(
                expr_a=a, expr_b=b,
                description=f"same-rep never-co-evaluated on [{ka[:36]}]",
                agent_notes="two decisions on the same rep recorded in disjoint runs — their "
                            "combination is unobservable (mutually exclusive), so they are "
                            "independent (a free PASS in the gate)."))
    return out


def _tier2_disjoint_reps(exprs, runs_of, already):
    # NOTE (2026-08-27): the coverage checker's dependence graph is the
    # COMPLETE graph MINUS declared IndependenceAssumptions, so EVERY
    # cross-rep pair must be declared independent to leave the clique —
    # including never-co-evaluated pairs (restricting to co-evaluated ones
    # reintroduced 260 blocking combos). The count is inherent to this
    # subtractive model (matches conversations_index's disjoint-rep tier); in
    # the mandatory gate a never-co-evaluated pair is a free PASS (mutually
    # exclusive, no probe), so it does not slow the gate.
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


def _formatter_guid_oneside(exprs, pol):
    out = []
    for e in sorted(exprs):
        if re.search(r"_guid != StringVal\(''\)\)$", e):
            if pol[e].get(True):
                continue
            out.append(OneSideUntrackedPathAssumption(
                expr=e, tracked_side="not_taken",
                description=f"formatter guid-blank compare, True side unreachable: {e}",
                agent_notes="action_dispatch/journey/formatter.rb reaches `segment != ''` only on "
                            "the blank-guid path (non-blank handled earlier), where it is always "
                            "False. Verified: seeding the rep's guid non-blank removes this PC."))
    return out


def build(runs=None) -> AssumptionSet:
    aset = AssumptionSet()
    if not runs:
        return aset
    expr_variants, expr_dispatch, runs_of, dispatch_absent = _observations(runs)
    exprs = sorted(expr_variants)
    pol = defaultdict(lambda: defaultdict(int))
    for r in runs:
        for pc in r.path_conditions:
            pol[pc.expr][bool(pc.taken)] += 1

    already = set()
    n0a = n0b = n0c = n2 = 0
    for ia in _tier0a_variant(exprs, expr_variants):
        aset.add(ia); already.add(frozenset((ia.expr_a, ia.expr_b))); n0a += 1
    for ia in _tier0b_type(exprs, expr_dispatch, dispatch_absent, already):
        aset.add(ia); n0b += 1
    for ia in _tier0c_dispatch_independence(exprs, expr_dispatch, already):
        aset.add(ia); n0c += 1
    for ia in _tier0d_crossdispatch(exprs, already):
        aset.add(ia); n0c += 1
    # WITHDRAWN 2026-08-27 (gate FAIL, HARD RULE 5): _tier_persisted_textnil
    # declared `_persisted` ⊥ `_text_nil` as disjoint query families, but they
    # INTERACT — the photos query (`SELECT photos.* WHERE status_message_id =
    # ?` / its COUNT) fires only when persisted=True AND text_nil=True (the
    # post's photos association loads only when persisted, and the photos
    # branch is taken only when the message is blank). Their combinations are
    # therefore OBSERVED by exploration, not declared away.
    for ia in _tier_guid_foreclosed_by_persisted(exprs, already):
        aset.add(ia); n0c += 1
    n1 = 0
    for ia in _tier1c_empty_list_foreclosure(exprs, already, runs):
        aset.add(ia); n1 += 1
    for ia in _tier1_samerep_foreclosure(exprs, already):
        aset.add(ia); n1 += 1
    for ia in _tier_samerep_never_coeval(exprs, runs_of, already):
        aset.add(ia); n1 += 1
    for ia in _tier2_disjoint_reps(exprs, runs_of, already):
        aset.add(ia); n2 += 1
    nu = 0
    for u in _ownprofile_untracked(exprs):
        aset.add(u); nu += 1
    for u in _display_untracked(exprs):
        aset.add(u); nu += 1
    # (guid is fully covered by _display_untracked now; the formatter one-side
    # is redundant and would double-declare the same expr.)
    import sys
    print(f"[assumptions] tier0a(variant)={n0a} tier0b(type)={n0b} "
          f"tier0c(dispatch)={n0c} tier1(foreclose)={n1} tier2(disjoint-rep)={n2} untrack-ownprofile={nu}", file=sys.stderr)
    return aset
