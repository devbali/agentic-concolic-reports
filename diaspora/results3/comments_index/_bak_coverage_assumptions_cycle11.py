#!/usr/bin/env python3
"""comments_index — batch-local AssumptionSet, cycle 3 (2026-08-27).

Rewritten as a TIER-DERIVED builder (the conversations_index cycle-3 shape):
the PC universe now spans four request variants (anon/auth x json/mobile)
and grew a text-decision family (W1), has_one/belongs_to not-found decisions,
the discovery decision, the array-param decision and the mobile partial's
identity compares — a hand-enumerated pair list no longer scales, and every
declaration must still be a STRUCTURAL claim with a source line.

  TIER 0 — VARIANT EXCLUSIVITY. run_dse.rb fixes (signed-in?, format) for a
  run's whole duration (PostService#find! branches on `user`;
  `respond_with do |format|` json vs mobile). Exprs observed under DISJOINT
  variant sets can never share a path.

  TIER 1 — STRUCTURAL GATES. GATE_TABLE names every gate expr, its SOURCE
  LINE and the polarity/polarities that CLOSE a code region. For a gate G
  and polarity p in its closing set, every decision Y recorded in some run
  with G = !p and in NO run with G = p is foreclosed by G = p. A gate with an
  EMPTY closing set (display-only decisions, the key-length dispatch, the
  array-param shape, identity compares) declares nothing — their cross
  combinations are DEMANDED and explored. An expr absent from the table
  raises: an undocumented decision is a bug in this file, never a silent
  declaration.

  TIER 1b — pairs never co-evaluated that Tier 1 did not pair: in every
  variant where both occur they must be SEPARATED by a chain of documented
  gates (each recorded only on one side of the chain's polarity); a pair with
  no separating chain raises (it would be a coverage hole hidden as an
  assumption).

  TIER 2 — DISJOINT-REP LEAF DECISIONS: two closing-set-empty decisions on
  DIFFERENT symbolic reps (different owner-rep var prefix) — an identity
  compare of one mentioned person vs a handle compare of another — neither
  gate nor feed each other and every statement either can produce is keyed
  on its own rep. Gates (non-empty closing set), the key-length dispatch and
  the array-param shape are NEVER Tier-2 members (the engine rejected
  Length x ci_*_first in cycle 2; withdrawn assumptions are never
  re-declared in any form). Licensed by the engine's flip-both probe.

Source lines (read-only app code):
  post_service.rb:17-23  find!: `user` -> find_public! (anon) | EvilQuery (auth)
  post_service.rb:51-55  find_public!: not_found -> RecordNotFound; !public? -> NonPublic
  lib/evil_query.rb:102-105  post!: vis.first || author.first || public.first
  collection_association.rb:292  null_scope?: unpersisted owner -> NullRelation comments
  mentions_container.rb:16-21  mentioned_people: persisted? ? mentions.includes(...) : people_from_string(text)
  mentionable.rb:46-49  people_from_string: scan -> find_or_fetch_person_by_identifier
  person.rb:318-328 (targets.rb PersonFindOrFetchNaming)  first lookup; profile.present? guard; discovery; retry
  person.rb:247-252 / 371-375  name -> fix_profile -> Discovery.new.fetch_and_save -> reload
  message_renderer.rb:118-123  diaspora_links: DIASPORA_URL_REGEX match; `== "post"` -> Post.exists?(guid:)
  message_renderer.rb:64-71  render_mentions (mobile markdownified) -> Mentionable.format
  mentionable.rb:35  `people.find {|p| p.diaspora_handle == diaspora_id }`
  people_helper.rb:43 / 81-87  person_image_link profile.nil?; person_link_class self/hovercardable
  _comment.mobile.haml:17  `user_signed_in? && comment.author == current_user.person`
  association.rb find_target?  `!owner.new_record?` gates the association load
"""
from __future__ import annotations

import re
from collections import defaultdict

from concolic_engine.assumptions import AssumptionSet, IndependenceAssumption, OneSideUntrackedPathAssumption

_VARIANTS = ("anon_json", "auth_json", "anon_mobile", "auth_mobile")

# regex -> (closing polarities, description, source)
# M-13 / M-16: a list may carry a SECOND representative row, and that row runs
# the SAME per-row code with the SAME decision families (its text pipeline, its
# author/mention preload outcome, its discovery). Every row-scoped entry below
# therefore matches `_row_` OR `_row2_` — one documented family, two rows, not
# two undocumented families. (cycle 11)
GATE_TABLE = [
    # ---- anon post finder ----
    (r"_FinderMethods_first_1_not_found == True\)$", {True},
     "anon post lookup not found", "post_service.rb:51-53 RecordNotFound -> head :not_found (nothing after)"),
    (r"_FinderMethods_first_1_public == True\)$", {False},
     "anon post not public", "post_service.rb:54 NonPublic -> authenticate_user! (no comment level)"),
    (r"_FinderMethods_first_1_persisted == True\)$", {False},
     "anon post rep unpersisted", "collection_association.rb:292 null_scope? -> NullRelation comments (no comment level)"),
    # ---- signed-in visibility chain ----
    (r"_ci_vis_first_1_not_found == True\)$", {True, False},
     "share-visibility lookup outcome", "evil_query.rb:104 `||`: found -> its rep's decisions only; miss -> author/public lookups"),
    (r"_ci_author_first_1_not_found == True\)$", {True, False},
     "own-post lookup outcome", "evil_query.rb:104 `||`: found -> its rep's decisions only; miss -> public lookup"),
    (r"_ci_public_first_1_not_found == True\)$", {True},
     "public lookup not found", "post_service.rb:57-60 RecordNotFound -> head :not_found (nothing after)"),
    (r"_ci_(vis|author|public)_first_1_persisted == True\)$", {False},
     "signed-in post rep unpersisted", "collection_association.rb:292 null_scope? -> NullRelation comments"),
    # ---- comment rep ----
    # W4-2 / M-6 (round 4): the STI dispatch on `posts.type`. True (a value
    # outside the Post STI tree) closes everything after the finder: AR raises
    # SubclassNotFound while INSTANTIATING the returned row, so `post.public?`,
    # the comments read, the preloads, the mention loads and the exists?
    # probes are all unreachable — the post finder is the last statement.
    (r"_(?:first|ci_vis_first|ci_author_first|ci_public_first)_1_type == StringVal\('Photo'\)\)$", {True},
     "post row's STI type is outside the Post tree",
     "post_service.rb:52 `Post.where(...).first` -> inheritance.rb find_sti_class raises "
     "ActiveRecord::SubclassNotFound during instantiation; run terminal, no comment level"),
    (r"_(?:records|to_a)_\d+_row2?_persisted == True\)$", {True, False},
     "comment rep persisted", "mentions_container.rb:16-21: persisted -> mentions chain (no people_from_string); unpersisted -> people_from_string (no mentions chain)"),
    (r"_(?:records|to_a)_\d+_row2?_text_has_mention == True\)$", {False},
     "comment text carries a mention", "mentionable.rb:46-49 scan -> [] (no lookup); mobile render_mentions: no mention to format"),
    (r"_(?:records|to_a)_\d+_row2?_text_has_dlink == True\)$", {False},
     "comment text carries a diaspora:// link", "message_renderer.rb:118 DIASPORA_URL_REGEX no match -> no entity compare, no exists?"),
    (r"_(?:records|to_a)_\d+_row2?_text_dlink_is_post (==|!=) True\)$", {False},
     "diaspora link entity is post", "message_renderer.rb:121 `== \"post\"` False -> no Post.exists?"),
    # N3-3 (round 3): the mention's display name. `@{Name; handle}` makes
    # PeopleHelper#person_link use opts[:display_name] (people_helper.rb:28-33)
    # and NEVER call Person#name, so the whole name -> fix_profile ->
    # Discovery -> reload -> profiles re-read chain of that mention rep is
    # closed on the mobile path. (In json `as_api_response` calls `name`
    # unconditionally, so nothing is closed there and Tier 1's own
    # only-on-the-open-side test declares nothing.)
    (r"_(?:records|to_a)_\d+_row2?_text_mention_has_name == True\)$", {True},
     "mention markup carries a display name",
     "mentionable.rb:107-112 / people_helper.rb:28-33 `opts[:display_name] || person.name`"),
    # N3-2 (round 3): the link-count chain. Each `_geK` decision is nested
    # inside the previous one, so False closes every further link: the K-th
    # guid parameter, the K-th `Post.exists?` probe and the ge(K+1) decision
    # are only reachable on the True side.
    (r"_(?:records|to_a)_\d+_row2?_text_dlink_ge\d == True\)$", {False},
     "comment text carries a further diaspora:// link",
     "targets.rb text shim / message_renderer.rb:118-123 (one exists? probe per post-entity link)"),
    # W5-1 / M-7 (round 5), narrowed by Rule D (round 6) to the ONE step where
    # the key count is genuinely free — `Comment belongs_to :author`.
    # The DISTINCT-KEY count of a preload step.
    # ActiveRecord groups the owners by key and binds the unique keys, so
    # ten comments by one author give `people.id = ?`. False (one distinct
    # key) closes the second key's outcome decision `_k2_not_found` and
    # forecloses every bulk-IN note of that step.
    (r"_keys_many == True\)$", {False},
     "preload step binds two or more distinct keys",
     "activerecord Preloader::Association#owners_by_key (group_by => unique keys) + "
     "PredicateBuilder::ArrayHandler (1 key -> equality, 2+ -> IN)"),
    # W5-2 / M-8 (round 5): the SECOND key's load outcome. It closes
    # nothing — both arms preload and both leave a representative child —
    # but it decides how many parents the NESTED step binds, which is the
    # `IN` -> `=` shape the corpus could not produce.
    (r"_k2_not_found == True\)$", {True},
     "the preload step's second key matched no row",
     "activerecord Preloader#preload recurses over the records ACTUALLY LOADED: with the second key unmatched the next level binds ONE key, "
     "so that level has no distinct-key decision (`<child>_keys_many`) and no second-key outcome of its own — True closes the whole nested key-set region"),
    (r"_(?:records|to_a)_\d+_row2?_author_persisted == True\)$", set(),
     "comment author rep persisted (inert here: the has_one profile load runs for an unpersisted owner too — corpus fact)", "association.rb reader/reload"),
    # W3-1 (round 3): the decision is minted by the PRELOAD ATTACH as well as
    # by find_target now (one shared predicate, targets.rb
    # `dangling_belongs_to?`), and the mobile materialization names its lists
    # `to_a_*`, so the pattern covers both.
    (r"_(?:records|to_a)_\d+_row2?_person_not_found == True\)$", {True},
     "mention's person missing (mentions.person_id has no FK)", "targets.rb emit_includes_preloads / 8c(c): nil person -> no profiles preload and no decisions of that rep; json: `mentioned_people:[null]`; mobile: Mentionable.format on nil -> real 500 terminal"),
    (r"_records_\d+_row2?_person_persisted == True\)$", set(),
     "mentioned person rep persisted (inert: profile load runs either way — corpus fact)", "association.rb reader/reload"),
    # BOTH polarities close a region (person.rb:319
    #   `return person if person.present? && person.profile.present?`):
    #   False (profile found) -> early return: no discovery, no retry, no
    #     decision of a retried rep exists;
    #   True  (profile missing) -> the FIRST person is DISCARDED and the
    #     method returns the RETRY's person, so the first rep is never
    #     rendered — none of its display compares (guid blank check in
    #     person_path/journey formatter, `p.diaspora_handle == diaspora_id`
    #     in mentionable.rb:35, Person#name) can be recorded.
    (r"_mention_lookup_(msg|json)_first_1_profile_not_found == True\)$", {True, False},
     "first-attempt person's profile", "person.rb:319 `return person if person.present? && person.profile.present?` "
     "(False -> early return, no discovery/retry; True -> the first person is discarded, the RETRY's person is "
     "returned and rendered, so the first rep has no display compares)"),
    # D5 (2026-08-28): the signed-in principal's `User has_one :person` load.
    # True closes everything after evil_query.rb:110 — the share-visibility
    # SELECT is issued, then `@querent.person.id` (evil_query.rb:116) raises,
    # so the author/public finders and the whole comment level never run.
    (r"_devise_user_first_1_person_not_found == True\)$", {True},
     "signed-in user has no people row",
     "evil_query.rb:116-118 `@querent.person.id` on nil -> NoMethodError (a real 500) after the vis SELECT"),
    # N3-1 (round 3): the DEVISE PRINCIPAL's profile, read by
    # `set_grammatical_gender` before the action body. BOTH polarities close:
    # False (found) -> no fix_profile/discovery/reload for that rep (the
    # generic rule below); True -> `Person#gender` delegates to a nil profile
    # and raises Module::DelegationError in the callback, so the ACTION never
    # runs and none of its decisions exist.
    (r"_devise_user_first_1_person_profile_not_found == True\)$", {True, False},
     "signed-in principal's person has no profiles row",
     "person.rb:27-28 `delegate :gender, to: :profile` (no allow_nil) -> DelegationError in application_controller.rb:118-122, before the action body"),
    # BOTH polarities close (round 5): False (the profile was found) closes the
    # fix_profile -> Discovery -> reload chain of that rep; True closes the
    # step's SECOND-KEY outcome and the level below it — with zero rows loaded
    # there is no `_k2_not_found` decision and no nested step at all.
    (r"_profile_not_found == True\)$", {True, False},
     "has_one :profile missing",
     "targets.rb 8c(b) / emit_includes_preloads: found -> no fix_profile/discovery/reload for that rep; "
     "missing -> zero parents loaded, so no second-key decision and no nested preload"),
    # N3-1 (round 3) — Rule G: `users.language`. False (the locale is not an
    # inflected one) closes the whole `set_grammatical_gender` body: the
    # principal's profiles read, its not-found decision and the delegation
    # terminal are only reachable on the True side.
    # W4-1 / M-5 (round 4): the THIRD arm of `users.language`. An available
    # but non-inflected locale and an UNAVAILABLE one are different outcomes:
    # `I18n.locale = "xx"` raises `I18n::InvalidLocale` inside set_locale, so
    # True closes EVERYTHING — set_grammatical_gender, the whole action body,
    # every finder and every read. The only statement of such a run is the
    # `users` SELECT that resolved the principal.
    (r"_devise_user_first_1_language == StringVal\('xx'\)\)$", {True},
     "signed-in user's language is not an available locale",
     "application_controller.rb:100-108 set_locale -> I18n.locale= raises I18n::InvalidLocale "
     "(enforce_available_locales) before the action body; run terminal, one statement"),
    # BOTH polarities close a region, because a THREE-valued domain is encoded
    # as a chain of two binary compares (the same shape as the link-count
    # `_text_dlink_ge2/ge3/ge4` chain declared below):
    #   False — the locale is not the inflected one, so set_grammatical_gender
    #           does nothing: no `profiles` read on the principal, no
    #           `<principal>_person_profile_not_found` decision, no
    #           DelegationError terminal;
    #   True  — the value IS "pl", so the second compare (`== "xx"`, the
    #           unavailable-locale arm) is never evaluated at all. Nothing
    #           else is foreclosed: a `pl` run proceeds through the whole
    #           action body.
    (r"_devise_user_first_1_language == StringVal\('pl'\)\)$", {True, False},
     "signed-in user's locale is an inflected one",
     "application_controller.rb:100-108 set_locale + :118-122 set_grammatical_gender `I18n.inflector.inflected_locale?`; "
     "targets.rb identity shim: the three-valued language domain is a pl/xx/en compare chain, so pl == True forecloses the xx compare"),
    (r"_discovery_failed == True\)$", {True},
     "webfinger discovery failed", "targets.rb 8e: DiscoveryError -> fix_profile propagates (500 terminal) / find_or_fetch rescues nil (no retry)"),
    # ---- mention lookups (unpersisted branch) ----
    (r"_mention_lookup_(msg|json)_first_1_not_found == True\)$", {True, False},
     "mention lookup first attempt outcome", "person.rb:318-321: found -> that rep's decisions, early return unless profile absent; miss -> discovery + retry"),
    (r"_mention_lookup_(msg|json)_first_1_persisted == True\)$", set(),
     "first-attempt person persisted (inert: profile load runs either way — corpus fact)", "association.rb reader/reload"),
    (r"_mention_lookup_(msg|json)_retry_1_not_found == True\)$", {True},
     "mention lookup retry not found", "person.rb:327 nil -> compact: no decisions of a retried rep"),
    (r"_mention_lookup_(msg|json)_retry_1_persisted == True\)$", set(),
     "retried person persisted (inert: profile load runs either way — corpus fact)", "association.rb reader/reload"),
    # ---- decisions that close nothing (demanded in every combination) ----
    (r"^\(Length\(SYM_PARAM_post_id\) < 16\)$", set(),
     "post_key id/guid dispatch", "post_service.rb:64 (changes every finder's key column; engine-rejected as independent of the visibility chain — never declared)"),
    (r"^\(SYM_PARAM_post_id_is_array == True\)$", {True},
     "array post_id param shape", "post_service.rb:64 post_key: `id_or_guid.to_s.length` on an ARRAY is a concrete Array#to_s "
     "(no Length(SYM_PARAM_post_id) compare is ever evaluated) -> the IN-list finder; the array shape closes the key-length "
     "dispatch and nothing else (never declared against the visibility-chain not_found decisions)"),
    (r"_exists__\d+_exists == True\)$", set(),
     "Post.exists?(guid:) outcome", "message_renderer.rb:121 (display rewrite only)"),
    # D9 (2026-08-28): the length decision now exists on BOTH materializations
    # — `to_a` (mobile collection render) and `records` (json, through
    # Enumerable#map -> each). Empty closes every per-row region.
    (r"^\(len\(SYM_RESULT_ActiveRecord__Relation_(to_a|records)_\d+_rows\) != 0\)$|^\(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_(to_a|records)_\d+_rows != 0\)$", {False},
     "comment collection empty",
     "index.mobile.haml:3 collection render / base_presenter.rb:14 as_collection map: no rows -> no per-comment decisions"),
    # N4-3 (round 4) -> M-7 (round 5) -> Rule D (round 6) -> M-14 (round 7).
    # The ROW COUNT is a free fact of EVERY list again: `keys <= rows` only
    # BOUNDS it, and cycle 8's derivation of the comments row count from its
    # distinct-author count asserted "one distinct author => one comment",
    # which ten comments by one author trivially refutes. False (one row)
    # forecloses everything a second row can carry: the `_keys_many` decision,
    # the second key's outcome (`_k2_not_found`), and the second
    # representative row's own child decision (`_row2_..._not_found`).
    (r"^\(len\(SYM_RESULT_ActiveRecord__Relation_(to_a|records)_\d+_rows\) > 1\)$"
     r"|^\(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_(to_a|records)_\d+_rows > 1\)$", {False},
     "collection holds two or more rows",
     "M-7: the row count BOUNDS the distinct-key count but does not determine it; False (one row) forecloses the per-step `_keys_many` decision entirely"),
    (r"_guid == ''\)$", set(),
     "person_path guid blank (journey formatter)", "people_helper.rb:30/48 person_path(person) -> formatter blank-segment check (display)"),
    (r"_guid != StringVal\(''\)\)$", set(),
     "person_path guid present (journey formatter, blank path only)", "action_dispatch/journey/formatter.rb:41 (display)"),
    (r"_diaspora_handle == StringVal\(", {False},
     "mention handle matches the rendered mention", "mentionable.rb:35 people.find -> nil on mismatch -> MentionsInternal.mention_link returns the display name WITHOUT person_link (no guid compares, no name/fix_profile for that rep)"),
    (r"^\([A-Za-z_][A-Za-z0-9_]*_id == [A-Za-z_][A-Za-z0-9_]*_id\)$", set(),
     "identity compare (author == current person / person_link_class self)", "_comment.mobile.haml:17, people_helper.rb:84"),
    (r"^\([A-Za-z_][A-Za-z0-9_]*_id != [A-Za-z_][A-Za-z0-9_]*_id\)$", set(),
     "identity compare (negated)", "_comment.mobile.haml:17, people_helper.rb:84"),
]

_PARAM_SHAPE = re.compile(r"Length\(SYM_PARAM_post_id\)|SYM_PARAM_post_id_is_array")


def _gate_info(expr):
    for rx, closing, desc, src in GATE_TABLE:
        if re.search(rx, expr):
            return closing, desc, src
    return "UNKNOWN", None, None


def _variant_of(label):
    for v in _VARIANTS:
        if (label or "").startswith(v):
            return v
    return "unknown"


_ATTR_SUFFIXES = ("_not_found", "_persisted", "_text_has_mention", "_text_has_dlink", "_text_dlink_is_post",
                  "_text_mention_has_name", "_text_dlink_ge2", "_text_dlink_ge3", "_text_dlink_ge4",
                  "_language", "_gender", "_type", "_keys_many", "_k2_not_found",
                  "_profile_not_found", "_failed", "_exists", "_diaspora_handle", "_author_id", "_person_id",
                  "_public", "_id")


def _strip_suffix(var):
    for suf in _ATTR_SUFFIXES:
        if var.endswith(suf):
            return var[: -len(suf)]
    return var


def _is_principal(var):
    return "devise_user_first" in var or var.startswith("SYM_USER_CI")


def _rep_key(expr):
    s = expr.strip()
    mvv = re.match(r"^\(([A-Za-z_][A-Za-z0-9_]*) (?:==|!=) ([A-Za-z_][A-Za-z0-9_]*)\)$", s)
    if mvv:
        l, r = mvv.group(1), mvv.group(2)
        cand = r if _is_principal(l) and not _is_principal(r) else (
            l if _is_principal(r) and not _is_principal(l) else l)
        return _strip_suffix(cand)
    m = re.match(r"^\(([A-Za-z_][A-Za-z0-9_]*)", s)
    return _strip_suffix(m.group(1)) if m else s


def _tier0(runs):
    ev = {}
    for r in runs:
        v = _variant_of(r.label)
        for pc in r.path_conditions:
            ev.setdefault(pc.expr, set()).add(v)
    by_set = {}
    for e, sv in ev.items():
        by_set.setdefault(frozenset(sv), []).append(e)
    groups = sorted(by_set.items(), key=lambda kv: sorted(kv[0]))
    out = []
    for i, (sa, ea) in enumerate(groups):
        for sb, eb in groups[i + 1:]:
            if sa & sb:
                continue
            for a in ea:
                for b in eb:
                    out.append(IndependenceAssumption(
                        expr_a=a, expr_b=b,
                        description=f"variant exclusivity: {sorted(sa)} vs {sorted(sb)}",
                        agent_notes=("run_dse.rb fixes (signed-in?, format) per run: post_service.rb:17-23 "
                                     "`user` dispatch and `respond_with do |format|` json/mobile. expr_a is "
                                     f"observed only under {sorted(sa)}, expr_b only under {sorted(sb)}.")))
    return out


def _observations(runs):
    pol_runs = defaultdict(lambda: defaultdict(set))
    run_exprs = []
    for i, r in enumerate(runs):
        seen = set()
        for pc in r.path_conditions:
            pol_runs[pc.expr][bool(pc.taken)].add(i)
            seen.add(pc.expr)
        run_exprs.append(seen)
    return pol_runs, run_exprs


def _tier1(pol_runs, run_exprs):
    out, declared = [], set()
    for g, pols in pol_runs.items():
        closing, desc, src = _gate_info(g)
        if closing == "UNKNOWN":
            raise RuntimeError(f"undocumented PC expr (add it to GATE_TABLE): {g}")
        if not closing or True not in pols or False not in pols:
            continue
        for p in closing:
            closed_runs, open_runs = pols[p], pols[not p]
            when_closed = set().union(*(run_exprs[i] for i in closed_runs))
            when_open = set().union(*(run_exprs[i] for i in open_runs))
            for y in sorted(when_open - when_closed):
                if y == g or frozenset((g, y)) in declared:
                    continue
                declared.add(frozenset((g, y)))
                out.append(IndependenceAssumption(
                    expr_a=g, expr_b=y,
                    description=f"{desc} ({g} = {p}) forecloses {y}",
                    agent_notes=(f"GATE {g} = {p} closes: {src}. {y} is recorded only on the open side "
                                 f"({len(open_runs)} open-side runs, none of the {len(closed_runs)} closed-side runs).")))
    return out, declared


def _separate(pol_runs, pair, ra, rb, subset, depth=0):
    if not ra or not rb:
        return []
    if depth >= 4:
        return None
    for g, pols in pol_runs.items():
        if g in pair:
            continue
        closing = _gate_info(g)[0]
        if not closing:
            continue  # only DOCUMENTED closing polarities can separate
        for p in closing:
            side = pols[p] & subset
            if not side or not (ra <= side or rb <= side):
                continue
            ra2, rb2 = ra & side, rb & side
            if not ra2 or not rb2:
                return [(g, p)]
            if (ra2, rb2) != (ra, rb):
                tail = _separate(pol_runs, pair, ra2, rb2, side, depth + 1)
                if tail is not None:
                    return [(g, p)] + tail
    return None


def _tier1b(runs, pol_runs, run_exprs, already):
    out = []
    exprs = sorted(pol_runs)
    runs_of = {e: pols[True] | pols[False] for e, pols in pol_runs.items()}
    variant_runs = defaultdict(set)
    for i, r in enumerate(runs):
        variant_runs[_variant_of(r.label)].add(i)
    for i, a in enumerate(exprs):
        for b in exprs[i + 1:]:
            if frozenset((a, b)) in already or (runs_of[a] & runs_of[b]):
                continue
            seps = []
            for v, vruns in variant_runs.items():
                ra, rb = runs_of[a] & vruns, runs_of[b] & vruns
                if not ra or not rb:
                    continue
                chain = _separate(pol_runs, (a, b), ra, rb, vruns)
                if chain is None:
                    raise RuntimeError(f"never co-evaluated pair with no separating documented gate in {v}: {a} || {b}")
                seps.append((v, chain))
            if not seps:
                continue
            already.add(frozenset((a, b)))
            why = "; ".join(f"in {v}: " + " then ".join(f"{g} = {p} (site: {_gate_info(g)[2]})" for g, p in chain)
                            for v, chain in seps)
            out.append(IndependenceAssumption(
                expr_a=a, expr_b=b,
                description="separated by " + "/".join("+".join(_gate_info(g)[1] for g, _ in chain) for _, chain in seps),
                agent_notes="Never co-evaluated: " + why + ". Decisions of code regions on opposite sides of that gate."))
    return out


# REP-CHAIN MODEL (cycle 3, after the bounded probe: 1,220 witnesses = 305
# cliques x cap 4, every clique = {Length, is_array} x a post-chain gate x
# the comment rep's text/persisted gates x ONE rep chain). Every decision
# belongs to exactly one chain; decisions in DIFFERENT chains are declared
# independent (rule 2 of assumptions.py: no data flow, every statement
# either can produce is keyed on its own chain's rows — licensed by the
# engine's flip-both probe), decisions in the SAME chain stay dependent.
#   param       Length(post_id) / post_id_is_array — the request's key shape
#   post        the post finders (anon first_1_*, ci_*_first_1_*, devise) —
#               which finder runs and what it returns
#   comment_rep the comment row's own decisions (persisted, text_*), and the
#               collection length
#   author / mention_person_N / lookup_msg / lookup_json / exists_N — one
#               chain per downstream rep family
# THE ENGINE-REJECTED CLASS IS NEVER DECLARED: param x the visibility-chain
# not_found decisions (ci_vis/ci_author/ci_public_first_1_not_found) — the
# key shape changes which finder runs NEXT and its statement shape, so the
# combination reaches guid-keyed author/public finder shapes (cycle 2). Those
# pairs stay demanded. (param x everything else was verified PASS by the
# engine in cycle 2 — the key selects a column of the POST finders only;
# no downstream chain binds on it.)
_PARAM = re.compile(r"Length\(SYM_PARAM_post_id\)|SYM_PARAM_post_id_is_array")
_POST = re.compile(r"_FinderMethods_(first|ci_vis_first|ci_author_first|ci_public_first|devise_user_first)_1_")
_COMMENT_REP = re.compile(r"_(records|to_a)_\d+_row2?_(persisted|text_has_mention|text_has_dlink|text_dlink_is_post"
                          r"|text_mention_has_name|text_dlink_ge\d) == "
                          r"|len\(SYM_RESULT_ActiveRecord__Relation_to_a_|SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_a_")
_REJECTED_POST = re.compile(r"_ci_(vis|author|public)_first_1_not_found == True\)$")
# ENGINE-REJECTED, round 5 (2026-08-29): param x the STI type decision. The
# key shape decides WHICH COLUMN each post finder binds; the type decision
# decides whether the run survives instantiation. Flipping BOTH reaches a
# guid-keyed visibility SELECT in the SubclassNotFound state — a target-call
# shape neither single flip produces — so the engine refused the pair. It is
# never declared again, in any form; those combinations stay DEMANDED.
_REJECTED_TYPE = re.compile(r"_1_type == StringVal\('Photo'\)\)$")


def _chain(expr):
    if _PARAM.search(expr):
        return "param"
    if _POST.search(expr) and not re.search(r"== [A-Za-z_][A-Za-z0-9_]*\)$", expr.strip()):
        return "post"
    mcr = _COMMENT_REP.search(expr)
    if mcr:
        # M-16 (cycle 11): a list now carries TWO representative rows, and the
        # two rows are DISJOINT REPS — two different comments, two different
        # texts. Collapsing them into one `comment_rep` chain made the checker
        # demand every cross-row combination of two independent text pipelines
        # (200 of them after the second row appeared), none of which any single
        # statement depends on. The chain key therefore carries the ROW, so a
        # row-1 decision and a row-2 decision are a Tier-2 disjoint-rep pair —
        # and the assumption GATE flip-probes each one, so if the two rows do
        # interact (a terminal on row 1 forecloses row 2) the probe says FAIL
        # and the assumption is withdrawn. Decisions on the SAME row stay in
        # one chain and are still demanded, as they must be.
        mrow = re.search(r"_((?:records|to_a)_\d+_row2?)_", expr)
        return f"comment_rep:{mrow.group(1)}" if mrow else "comment_rep"
    s = expr.strip()
    mvv = re.match(r"^\(([A-Za-z_][A-Za-z0-9_]*) (?:==|!=) ([A-Za-z_][A-Za-z0-9_]*)\)$", s)
    if mvv:
        l, r = mvv.group(1), mvv.group(2)
        var = r if _is_principal(l) and not _is_principal(r) else l
    else:
        m = re.match(r"^\(([A-Za-z_][A-Za-z0-9_]*)", s)
        var = m.group(1) if m else s
    for rx in (r"(_mention_lookup_(?:msg|json))_", r"(_(?:records|to_a)_\d+_row2?_author)", r"(_(?:records|to_a)_\d+_row2?_person)",
               r"(_exists__\d+)"):
        m = re.search(rx, var)
        if m:
            return m.group(1)
    return _strip_suffix(var)


def _never_declare(a, b):
    """The engine-rejected classes: param x visibility-chain not_found (cycle 2),
    and param x the STI type decision (round 5)."""
    for rx in (_REJECTED_POST, _REJECTED_TYPE):
        if (_PARAM.search(a) and rx.search(b)) or (_PARAM.search(b) and rx.search(a)):
            return True
    return False


def _tier2(pol_runs, already):
    out = []
    leaf = sorted(pol_runs)
    for i, a in enumerate(leaf):
        for b in leaf[i + 1:]:
            if frozenset((a, b)) in already or _never_declare(a, b):
                continue
            ka, kb = _chain(a), _chain(b)
            if ka == kb:
                continue
            already.add(frozenset((a, b)))
            _, da, sa = _gate_info(a)
            _, db, sb = _gate_info(b)
            out.append(IndependenceAssumption(
                expr_a=a, expr_b=b,
                description=f"disjoint rep chains: {da} [{ka}] || {db} [{kb}]",
                agent_notes=(f"Chain-local decisions on two different rep chains ({ka} vs {kb}). "
                             f"Site A: {sa}. Site B: {sb}. Neither closes a region nor feeds the other's "
                             "operands; every statement either can produce is keyed on its own rep. "
                             "Licensed by the engine's flip-both access-trace probe.")))
    return out


def _formatter_guid_oneside(pol_runs):
    """action_dispatch/journey/formatter.rb:41 compares a route segment
    `!= ''` ONLY on the blank-guid path (the non-blank path is handled by an
    earlier branch and never reaches this compare), so the True side of every
    `<rep>_guid != StringVal('')` is structurally unreachable — a Rails
    constant, not an app decision (verified on conversations_index: seeding
    the guid non-blank removes the PC entirely). One-side-untracked ONLY
    while the True side is never observed; if it ever occurs, nothing is
    untracked."""
    out = []
    for e in sorted(pol_runs):
        if re.search(r"_guid != StringVal\(''\)\)$", e) and not pol_runs[e].get(True):
            out.append(OneSideUntrackedPathAssumption(
                expr=e, tracked_side="not_taken",
                description=f"formatter guid-blank compare, True side unreachable: {e}",
                agent_notes="journey/formatter.rb:41 reaches `segment != ''` only on the blank path — always False there."))
    return out


def build(runs=None) -> AssumptionSet:
    aset = AssumptionSet()
    if not runs:
        return aset
    for ia in _tier0(runs):
        aset.add(ia)
    pol_runs, run_exprs = _observations(runs)
    t1, declared = _tier1(pol_runs, run_exprs)
    for ia in t1:
        aset.add(ia)
    # Tier 2 before Tier 1b: leaf decisions on different reps are declared
    # disjoint whether or not the corpus happened to co-evaluate them; Tier 1b
    # then only judges the remaining (gate-involving) never-co-evaluated pairs.
    for ia in _tier2(pol_runs, declared):
        aset.add(ia)
    for ia in _tier1b(runs, pol_runs, run_exprs, declared):
        aset.add(ia)
    for u in _formatter_guid_oneside(pol_runs):
        aset.add(u)
    return aset
