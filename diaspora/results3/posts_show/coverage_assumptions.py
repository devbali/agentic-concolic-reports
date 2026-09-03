"""posts_show — batch-local AssumptionSet (results3 discipline rebuild,
2026-08-18).

Structural seed: results2/posts_show's 470-assumption, 6-tier
CALL-SITE-STABLE AssumptionSet (see that file's own docstring, kept below in
spirit). results3 removed the render family (the post page now renders for
real: comments/likes/reshares widgets, association/count queries),
descended `mark_user_notifications` and `Diaspora::Mentionable.
people_from_string`, and added a SECOND naming layer
(`PostsShowMentionLookupNaming`, targets.rb) for the two independent
`Person.find_or_fetch_by_identifier` call sites this opens up. The universe
grew from 30 exprs (results2) to ~90+ (results3, 4 scenarios) — re-verified
here against the NEW universe, not copied blind; every tier below is
regenerated programmatically from `all_exprs` (never hand-enumerated), so it
can't silently drift out of sync, and every tier's argument is restated for
why it still holds under the new mock surface.

SCENARIOS: 4, not 2 — `auth_html`/`anon_html`/`auth_json`/`anon_json`
(scenario x format; run_dse.rb SCENARIOS). Format is a genuine new
dimension: `PostsController#show`'s `format.json` branch (`with_interactions`
-> `PostInteractionPresenter#as_json`) never invokes `LikeService`/
`ReshareService#find_for_post` (the "like"/"reshare" CONTEXTS below) at
all — those only exist inside `with_initial_interactions`, which is
`format.html`-only (posts_controller.rb:24-30). So every `evilq_like_*`/
`evilq_reshare_*`/`findpublic_like`/`findpublic_reshare` expr is HTML-ONLY —
generalizing Tier 0 (scenario exclusivity) to the full 4-way partition
captures this for free, without a separate "format exclusivity" tier.

NAMING LAYERS (both endpoint-local, targets.rb):
  - `PostsShowFinderNaming` (ported from results2/posts_show, UNCHANGED):
    `evilq_{act,like,reshare}_{vis,author,public}` / `findpublic_{act,like,
    reshare}` — each fires at MOST ONCE per request, always ordinal "_1".
  - `PostsShowMentionLookupNaming` (NEW, mission item 4): `mention_lookup_
    {msg,json}_{first,retry}` — dedicates the (call-site x attempt) axis,
    but does NOT stabilize a THIRD axis this endpoint's real recursion opens
    up: `PostPresenter#as_json` recurses (reshares: -> a Reshare
    representative's OWN as_json -> its OWN build_text/build_mentioned_
    people_json, tagged the SAME "msg"/"json" context by the thread-local),
    and `CommentPresenter#as_json`'s own `mentioned_people` call is NOT
    tagged at all (defaults to "json" — PostsShowMentionLookupNaming.
    current_ctx's default). So `mention_lookup_json_first` can fire 1-5+
    times per request (observed in the corpus: `_first_1` through `_first_5`)
    — ordinal N denotes "the Nth call under the json context in THIS run",
    still a per-run counter, just narrowed to one context instead of the
    whole app. HONEST CONSEQUENCE (documented in REPORT.md, not silently
    assumed away): this file does NOT declare a same-N first/retry pairing
    (retry_1 is "the first retry that happened", not "the retry FOR
    first_1" — those can diverge whenever a later first_N is the one that
    actually misses) — that pairing would be UNSOUND to assume. The N-indexed
    mention_lookup exprs are therefore left demanding full combination
    coverage among themselves; only their OWN not_found (Tier 1, vacuously —
    they carry no attribute sibling, Person's columns aren't branched on
    further) and their relationship to the unrelated act/render families
    (Tier 1/5 below) are asserted.

TIER 0 — scenario x format exclusivity (generalizes results2's auth/anon-only
version to the full 4-way partition; same mechanism, wider label set).

TIER 1 — same-target "found vs attribute" impossibility (ported verbatim from
results2; regex WIDENED to also match `mention_lookup_*` dedicated targets,
not just `evilq_*`/`findpublic_*` — same `finder_mock`/`symbolic_instance`
mechanism underlies all three families: `Core::ClassMethods.find_by`
(design #2, aliased by PostsShowMentionLookupNaming) uses the identical
not_found-gates-attrs shape as `Relation#first` (design #1, aliased by
PostsShowFinderNaming) — `ConcolicTargets.finder_mock` is the SAME shared
lambda underneath both alias families):

  not_found = symbool(nf_name, ...)
  if not_found == true
    raise ... if raise_on_missing
    nil
  else
    symbolic_instance(model_class(receiver), name, sql)   # <- attrs built HERE
  end

TIER 5 (NEW) — "post-found gate": every expr that is NOT itself one of
PostsShowFinderNaming's own dedicated act-family exprs (evilq_act_*/
findpublic_act_1_*) can only be recorded once `act`'s lookup — PostsController
#show's OWN `post_service.find!(params[:id])` — has ALREADY succeeded
(posts_controller.rb:20-27 raises RecordNotFound/NonPublic otherwise, before
`PostPresenter.new`/render/mark_user_notifications/anything else on this
request's path ever runs). This is Tier 4's exact argument from results2,
GENERALIZED from the 3 old hand-named presenter exprs to the FULL new
render/presenter/mention/notification-marking surface (CollectionProxy
records/rows, as_api_response rows, find_by_1..N, mention_lookup_*,
assoc_root_*, assoc_profile_nsfw, assoc_status_message_*, len(...) gates,
like/reshare-context finders) — auto-discovered from `all_exprs`, not
hand-enumerated, so it tracks the corpus. Same redundancy/impossibility
split as before: (act's last attempt also failed, any post-found expr) is
IMPOSSIBLE; (act succeeded via any specific attempt, post-found expr) is
redundant (identical presenter/render code runs regardless of which act
attempt produced the post) and each side's own coverage is independently
demonstrated by execution.

TIER 6 (NEW) — collection length gates its own row attribute. `rows_mock`'s
`IterableSymbolicList` (targets.rb) only builds/reads a representative row's
attribute (`..._row_text_has_mention`, `..._row_guid`, ...) when its OWN
`(len(X) != 0)` gate is True — `__rows` returns `[]` before any
representative is ever touched otherwise (targets.rb, `IterableSymbolicList
#__rows`). Same "attribute requires found" shape as Tier 1, one structural
level up (collection non-emptiness instead of finder not_found), applied to
every `(len(X)!=0)` / `X`-prefixed-row-attribute pair actually observed.

Tiers 1b/2/3 (public-gates-attrs, within-context attempt-chain, cross-context
foreclosure) are ported UNCHANGED from results2 — their arguments are about
`PostsShowFinderNaming`'s dedicated targets specifically, which this pass
left untouched (see concolic_targets.rb file-header MOCK LEDGER).
"""

from __future__ import annotations

import re

from concolic_engine.assumptions import (  # noqa: F401
    AssumptionSet,
    IndependenceAssumption,
    UntrackedPathAssumption,
    OneSideUntrackedPathAssumption,
    SymbolicConstraintAssumption,
    PathSource,
)

# Any dedicated per-call-site declared target this endpoint's two naming
# layers mint: PostsShowFinderNaming's evilq_{ctx}_{attempt}/findpublic_{ctx}
# (design #1, aliased off ActiveRecord::Relation#first) and
# PostsShowMentionLookupNaming's mention_lookup_{site}_{attempt} (design #2,
# aliased off ActiveRecord::Core::ClassMethods#find_by) — same shared
# `finder_mock` lambda underneath both (concolic_targets.rb), same
# not_found-gates-attributes shape. `(\d+)` captures the ordinal so same-
# target (name, N) pairs stay distinct from a DIFFERENT N of the same base
# name (Tier 1 only pairs a not_found with an attribute sharing the SAME
# ordinal — see the docstring's honest note on why cross-N pairing is not
# attempted for mention_lookup).
_NF_RE = re.compile(
    r"\(SYM_RESULT_ActiveRecord__(?:Relation|Core__ClassMethods)_"
    r"((?:evilq_[a-z]+_[a-z]+|findpublic_[a-z]+|mention_lookup_[a-z]+_[a-z]+))_(\d+)_not_found == True\)"
)
_ATTR_RE = re.compile(
    r"\(SYM_RESULT_ActiveRecord__(?:Relation|Core__ClassMethods)_"
    r"((?:evilq_[a-z]+_[a-z]+|findpublic_[a-z]+|mention_lookup_[a-z]+_[a-z]+))_(\d+)_(text|guid|public) "
)

CONTEXTS = ("act", "like", "reshare")
ATTEMPTS = ("vis", "author", "public")


def _tier1_same_target_pairs(all_exprs):
    nf_expr = {}
    attr_exprs = {}
    for e in all_exprs:
        m = _NF_RE.match(e)
        if m:
            nf_expr[(m.group(1), m.group(2))] = e
            continue
        m = _ATTR_RE.match(e)
        if m:
            attr_exprs.setdefault((m.group(1), m.group(2)), []).append((m.group(3), e))

    out = []
    for base, attrs in attr_exprs.items():
        nf = nf_expr.get(base)
        if not nf:
            continue
        base_name = f"{base[0]}_{base[1]}"
        for attr_name, attr_expr in attrs:
            out.append(IndependenceAssumption(
                expr_a=nf, expr_b=attr_expr,
                description=f"{base_name}: not_found vs {attr_name} — attribute PC "
                             "only fires in finder_mock's 'found' branch",
                agent_notes=(
                    "finder_mock (concolic_targets.rb ~326-338): symbolic_instance "
                    "(the object whose columns/predicates the app subsequently "
                    f"reads, producing the '{attr_name}' PC) is built ONLY in the "
                    "not_found==False else-branch. (not_found=True, "
                    f"{attr_name}=*) is structurally impossible for target "
                    f"'{base_name}' — the attribute PC is never recorded in a run "
                    "where this target's not_found is True. `target_name` for "
                    f"this dedicated target is invariant ('...{base_name}'), so this "
                    "holds in every dump, not just most."
                ),
            ))
    return out


# ---------------------------------------------------------------------------
# TIER 2 — within-context attempt-chain guard (EvilQuery::VisibleShareableById
# #post!, lib/evil_query.rb:102-105):
#
#     querent_has_visibility.first || querent_is_author.first || public_post.first
#
# `author`'s target (`evilq_<ctx>_author`) is only CALLED AT ALL (hence its
# not_found PC, and — via Tier 1 — its attribute PCs, only ever exist) when
# `vis` failed (`vis_not_found == True`) — Ruby's `||` never evaluates the
# right operand once the left is truthy. `public`'s target is only called
# once BOTH `vis` and `author` failed. This forecloses not just the two
# targets' `not_found` exprs against each other but EVERY expr belonging to
# one attempt-family against EVERY expr belonging to another attempt-family
# in the SAME context: e.g. `evilq_act_vis_1_text` (which by Tier 1 only
# exists when vis SUCCEEDED) can never co-occur with ANY `evilq_act_author_*`
# expr (whose target was never even called in that run) — a full
# family-to-family cut, not just a not_found-to-not_found one. One cross-cut
# per (context, unordered attempt pair) — 9 total (3 contexts x 3 pairs),
# each removing every edge between the two families' expr sets.
# ---------------------------------------------------------------------------
def _tier2_attempt_chain_pairs(all_exprs):
    present = set(all_exprs)
    out = []
    for ctx in CONTEXTS:
        family = {a: [] for a in ATTEMPTS}
        for e in present:
            for a in ATTEMPTS:
                if e.startswith(f"(SYM_RESULT_ActiveRecord__Relation_evilq_{ctx}_{a}_1_"):
                    family[a].append(e)

        pairs = [("vis", "author"), ("vis", "public"), ("author", "public")]
        for a, b in pairs:
            if not family[a] or not family[b]:
                continue
            for ea in family[a]:
                for eb in family[b]:
                    out.append(IndependenceAssumption(
                        expr_a=ea, expr_b=eb,
                        description=f"evilq_{ctx}_{a} family || evilq_{ctx}_{b} family "
                                     "— `||`-chained attempts, mutually exclusive per run",
                        agent_notes=(
                            f"evil_query.rb:104: `querent_has_visibility.first || "
                            f"querent_is_author.first || public_post.first`. "
                            f"evilq_{ctx}_{b}'s target is only CALLED once "
                            f"evilq_{ctx}_{a} (and, if b=='public', also 'author') "
                            f"returned falsy (not_found==True) — Ruby's `||` short-"
                            f"circuits. Whenever any evilq_{ctx}_{a} expr fires at "
                            f"all (its target was called), that run's "
                            f"evilq_{ctx}_{b} target was EITHER never called "
                            f"(if {a} succeeded) or the two remain jointly "
                            f"reachable only through {a}'s 'failed' state, which "
                            f"Tier 1 already keys separately from {a}'s attribute "
                            f"exprs. Any {a}-family expr that exists in a run "
                            f"implies a definite {a} outcome (Tier 1: attribute "
                            f"exprs only exist on {a}'s success side, not_found "
                            f"only on either side) that is incompatible with "
                            f"{b}'s target ever having been called under the "
                            f"complementary {a}=success reading — so no single "
                            f"run can jointly witness an arbitrary pair from "
                            f"both families; each family's own coverage is "
                            f"independently demanded and satisfied by execution "
                            f"(see REPORT.md mapping table)."
                        ),
                    ))
    return out


def _scenario_of(label):
    # results3: 4-way partition (run_dse.rb SCENARIOS keys are literally
    # auth_html/anon_html/auth_json/anon_json — labels are "<scenario>NNNN").
    # Generalizes results2's 2-way auth/anon split to the same mechanism;
    # `_tier0_scenario_exclusivity` below is otherwise UNCHANGED — it just
    # cross-cuts whichever partition `_scenario_of` returns.
    label = label or ""
    for scen in ("auth_html", "anon_html", "auth_json", "anon_json"):
        if label.startswith(scen):
            return scen
    return "auth" if label.startswith("auth") else "anon"


# ---------------------------------------------------------------------------
# TIER 0 — scenario x format exclusivity (auth_html/anon_html/auth_json/
# anon_json). PostService#find!
# (post_service.rb:16-22):
#
#     def find!(id_or_guid)
#       if user
#         find_non_public_by_guid_or_id_with_user!(id_or_guid)   # -> evilq_* family
#       else
#         find_public!(id_or_guid)                                # -> findpublic_* family
#       end
#     end
#
# `user` is PostService's own @user, fixed for the whole controller action
# (PostsController#post_service memoizes `PostService.new(current_user)`,
# and current_user itself is fixed per request by run_dse.rb's SCENARIOS
# loop — every run in this corpus is entirely "auth" (symbolic current_user)
# or entirely "anon" (current_user=nil), never mixed within one run). So the
# `evilq_*` family (only reachable via find_non_public_by_guid_or_id_with_user!)
# and the `findpublic_*` family (only reachable via find_public!) can NEVER
# both appear in the same run's path — proven empirically below: every expr
# in the corpus is exclusively auth-only, exclusively anon-only, or genuinely
# scenario-independent (Length(SYM_PARAM_id)<16 -- post_key dispatch runs
# regardless of user; assoc_profile_nsfw -- Post#nsfw reads the author's
# profile regardless of current_user). Declared programmatically as a full
# cross-cut between the auth-only and anon-only sets (not hand-enumerated),
# so it can never drift out of sync with the observed universe. This is the
# dominant clique-size reducer: without it every evilq_* expr is falsely
# demanded to combine with every findpublic_* expr, which both cannot happen
# (mutually exclusive scenarios) AND, empirically, blew up maximal-clique
# enumeration to 1000+ cliques of size 14-17 (see REPORT.md).
# ---------------------------------------------------------------------------
_SCENARIO_NAMES = ("auth_html", "anon_html", "auth_json", "anon_json")


def _tier0_scenario_exclusivity(runs):
    expr_scenarios = {}
    for r in runs:
        scen = _scenario_of(r.label)
        for pc in r.path_conditions:
            expr_scenarios.setdefault(pc.expr, set()).add(scen)

    # results3: 4-way partition, not 2-way. Group every expr by its exact
    # observed-scenario SET (usually a singleton — one of the 4 — but some
    # exprs are genuinely scenario-independent: Length(SYM_PARAM_id)<16 runs
    # regardless of auth/anon/format; assoc_profile_nsfw reads the author's
    # profile regardless of current_user; both appear in all 4 and correctly
    # stay fully connected below since their "set" isn't disjoint from
    # anything). Cross-cut every pair of exprs whose sets are DISJOINT (not
    # just the old auth-only-vs-anon-only special case) — this also captures
    # the NEW format axis for free: an evilq_like_*/evilq_reshare_*/
    # findpublic_like/findpublic_reshare expr's set is exactly {"auth_html"}
    # (format.json never invokes LikeService/ReshareService#find_for_post —
    # see docstring), disjoint from anything json-only or anon-only.
    by_set = {}
    for e, s in expr_scenarios.items():
        by_set.setdefault(frozenset(s), []).append(e)

    groups = sorted(by_set.items(), key=lambda kv: sorted(kv[0]))
    out = []
    for i, (set_a, exprs_a) in enumerate(groups):
        for set_b, exprs_b in groups[i + 1:]:
            if set_a & set_b:
                continue  # share at least one scenario — NOT provably exclusive
            for a in exprs_a:
                for b in exprs_b:
                    out.append(IndependenceAssumption(
                        expr_a=a, expr_b=b,
                        description=(
                            f"scenario/format exclusivity: {sorted(set_a)} vs "
                            f"{sorted(set_b)}"
                        ),
                        agent_notes=(
                            "post_service.rb:16-22 `find!`'s `if user` branch selects "
                            "EXCLUSIVELY the evilq_* family (auth) or the findpublic_* "
                            "family (anon) for the WHOLE request, never both — and "
                            "posts_controller.rb:20-30's format.html/format.json branches "
                            "are mutually exclusive per request too (LikeService/"
                            "ReshareService#find_for_post — the like/reshare CONTEXTS — "
                            "fire ONLY inside format.html's with_initial_interactions, "
                            "never from format.json's with_interactions). Every run in "
                            "this corpus is fixed to exactly one of the 4 run_dse.rb "
                            "SCENARIOS for its whole duration. Verified empirically: "
                            f"expr_a's observed scenario set is exactly {sorted(set_a)}, "
                            f"expr_b's is exactly {sorted(set_b)} across the corpus — "
                            "disjoint sets, so no single run's path can contain both."
                        ),
                    ))
    return out


# ---------------------------------------------------------------------------
# TIER 3 — cross-CONTEXT foreclosure. PostPresenter#with_initial_interactions
# (post_presenter.rb:24-31), reached only from PostsController#show's html
# branch (posts_controller.rb:20-27) AFTER `post_service.find!` (the "act"
# lookup) has ALREADY succeeded (post_service.rb:58-61 raises
# ActiveRecord::RecordNotFound before `show` can reach the presenter unless
# `find_non_public_by_guid_or_id_with_user!`/`find_public!` returned an
# object):
#
#     def with_initial_interactions
#       as_json.tap do |post|
#         post[:interactions].merge!(
#           likes:    LikeService.new(current_user).find_for_post(@post.id)...,
#           reshares: ReshareService.new(current_user).find_for_post(@post.id)...
#         )
#       end
#     end
#
# So EVERY "like"-context or "reshare"-context expr (any evilq_like_*/
# evilq_reshare_*/findpublic_like/findpublic_reshare expr) can only be
# recorded in a run where the "act"-context lookup already succeeded. Per
# the same redundancy argument as Tier 2 (not just "impossible" but "adds no
# NEW call sequence"): LikeService#find_for_post / ReshareService#find_for_post
# run their OWN independent find! (a fresh EvilQuery::VisibleShareableById or
# find_public! invocation) whose outcome does not depend on, and does not
# influence, WHICH of act's three attempts succeeded — only THAT act
# succeeded at all. So the joint combination of "act's specific successful
# attempt" x "like/reshare's outcome" reveals nothing beyond each family's
# own coverage. Likewise `likes:` and `reshares:` (post_presenter.rb:27-28)
# are two structurally-parallel, unconditionally-both-evaluated calls (Ruby
# hash literal, no short-circuit between them, same shape as the existing
# find_by_1/find_by_2 "independent finds" assumption below) whose outcomes
# don't influence each other's query or code path — cut mutually too.
#
# Declared as a full pairwise cross-cut between the three context families
# (act, like, reshare), scoped per scenario (evilq_* for auth,
# findpublic_* for anon — Tier 0 already separates the scenarios, this just
# adds the context axis within each).
# ---------------------------------------------------------------------------
def _context_family(all_exprs, ctx):
    out = []
    for e in all_exprs:
        if (e.startswith(f"(SYM_RESULT_ActiveRecord__Relation_evilq_{ctx}_") or
                e.startswith(f"(SYM_RESULT_ActiveRecord__Relation_findpublic_{ctx}_")):
            out.append(e)
    return out


def _tier3_cross_context_pairs(all_exprs):
    families = {ctx: _context_family(all_exprs, ctx) for ctx in CONTEXTS}
    out = []
    for c1, c2 in (("act", "like"), ("act", "reshare"), ("like", "reshare")):
        for e1 in families[c1]:
            for e2 in families[c2]:
                out.append(IndependenceAssumption(
                    expr_a=e1, expr_b=e2,
                    description=f"context foreclosure: {c1} family || {c2} family",
                    agent_notes=(
                        "post_presenter.rb:24-31 with_initial_interactions runs "
                        "LikeService#find_for_post/ReshareService#find_for_post "
                        "(like_service.rb:23-26, reshare_service.rb:14-17) only "
                        "after PostsController#show's own post_service.find! "
                        "('act') already succeeded (post_service.rb raises "
                        "RecordNotFound/NonPublic otherwise, aborting before "
                        "with_initial_interactions runs — posts_controller.rb:"
                        "20-27). Each context runs its OWN independent find! "
                        "(fresh EvilQuery::VisibleShareableById#post! or "
                        "find_public! invocation per targets.rb's "
                        "PostsShowFinderNaming); one context's specific "
                        "outcome/attempt-of-success does not influence another "
                        "context's query shape or code path, so their joint "
                        "combination reveals no call sequence neither family's "
                        "own coverage already provides (same test as Tier 2, "
                        "applied across contexts instead of within one)."
                    ),
                ))
    return out


# ---------------------------------------------------------------------------
# TIER 4 — presenter fields ({find_by_1, find_by_2, assoc_profile_nsfw}) vs
# the "act" finder family. PostsController#show (posts_controller.rb:20-27)
# builds `presenter = PostPresenter.new(post, current_user)` and calls
# `presenter.with_initial_interactions` (-> as_json ->
# non_directly_retrieved_attributes -> build_interactions_json/nsfw) ONLY
# once `post = post_service.find!(params[:id])` ("act") succeeded — same
# guard as Tier 3, one level earlier: `find!` raises RecordNotFound/NonPublic
# (post_service.rb:53-56/60) before `show` reaches the presenter at all
# unless act's lookup returned an object.
#
# Whether act succeeded via `vis`, `author`, or `public` (auth) — or via the
# single findpublic_act attempt (anon) — does not change WHAT the presenter
# subsequently reads (nsfw reads @post.author.profile; find_by_1/find_by_2
# read Like/Reshare keyed on @post/current_user): identical presenter code
# runs regardless of which act attempt produced `post`. So:
#   - whichever act-family expr represents "the LAST attempt tried also
#     failed" (evilq_act_public_1_not_found / findpublic_act_1_not_found)
#     being True means act's ENTIRE lookup failed -> presenter never runs ->
#     (that expr=True, any presenter expr=*) is impossible;
#   - any act-family expr's "succeeded" reading is compatible with the
#     presenter firing, but WHICH attempt succeeded is irrelevant to the
#     presenter's own behavior, so cross-verifying "attempt X succeeded" x
#     "presenter field Y" adds nothing beyond each side's own coverage
#     (execution already demonstrates both, see REPORT.md) — same
#     redundancy argument as Tier 2/3.
# Declared as a full cut between {find_by_1, find_by_2, assoc_profile_nsfw}
# and every evilq_act_*/findpublic_act_1_* expr (not just the "last attempt"
# ones) for the same uniform reason Tier 3 disconnects whole families rather
# than hand-picking sides.
# ---------------------------------------------------------------------------
# NOT cut by Tier 5 even though it isn't act-family: this expr fires BEFORE
# `find!` even runs (post_service.rb:66 post_key dispatch, needed to BUILD
# the query act/like/reshare all use) and is scenario/format-independent —
# it stays fully connected to everything, same as results2's treatment.
_SCENARIO_INDEPENDENT = frozenset({"(Length(SYM_PARAM_id) < 16)"})


def _tier5_post_found_vs_act(all_exprs):
    """results3 generalization of results2's Tier 4. `_PRESENTER_EXPRS` there
    was a hand-picked 3-expr list (find_by_1/find_by_2/assoc_profile_nsfw) —
    this pass's render-family removal opens up dozens more exprs that are
    ALL, by the same posts_controller.rb:20-27 guard, only reachable once
    act's lookup has already produced a `post` (render/presenter/
    mark_user_notifications/mention-lookup code all run strictly after
    `post = post_service.find!(params[:id])` returns): CollectionProxy
    records/rows (comments/likes/participations/reshares materialization),
    as_api_response rows, every find_by_N (like_for/reshare_for/poll_
    participation/...), every mention_lookup_* (msg/json sites), assoc_root_*
    (Reshare#absolute_root), assoc_profile_nsfw, assoc_status_message_*
    (STI-representative text/date shims). Auto-discovered as "every expr
    that is not itself an act/like/reshare-context dedicated-finder expr and
    not the one scenario-independent post_key dispatch expr" rather than
    hand-enumerated, so a mock/naming change can't silently desync this tier
    from the corpus the way a hardcoded list would.
    """
    act_family = set(_context_family(all_exprs, "act"))
    like_family = set(_context_family(all_exprs, "like"))
    reshare_family = set(_context_family(all_exprs, "reshare"))
    non_cuttable = act_family | like_family | reshare_family | _SCENARIO_INDEPENDENT
    post_found = [e for e in all_exprs if e not in non_cuttable]

    out = []
    for pe in post_found:
        for ae in sorted(act_family):
            out.append(IndependenceAssumption(
                expr_a=pe, expr_b=ae,
                description="post-found-only expr vs act-family finder — render/"
                             "presenter/notification/mention code runs only once "
                             "act's lookup succeeded (any attempt)",
                agent_notes=(
                    "posts_controller.rb:20-27: `post = post_service.find!"
                    "(params[:id])` ('act') must succeed (post_service.rb raises "
                    "RecordNotFound/NonPublic otherwise) before `PostPresenter.new"
                    "(post, current_user)`, `mark_user_notifications`, or the real "
                    "render pipeline (show.html.haml / with_interactions) ever "
                    "runs. Which of act's vis/author/public attempts (or, anon, "
                    "the single findpublic_act attempt) produced `post` does not "
                    "change what runs afterward — identical downstream code runs "
                    "regardless of which attempt succeeded. So this pair is "
                    "either impossible (this act-family expr's value implying "
                    "the whole act lookup failed, so nothing post-found-only ever "
                    "ran) or redundant (implying act succeeded, in which case "
                    "the post-found expr's own coverage — demonstrated via "
                    "execution independent of which attempt succeeded — already "
                    "accounts for it). Auto-discovered pairing, see this "
                    "function's docstring."
                ),
            ))
    return out


# ---------------------------------------------------------------------------
# TIER 6 (NEW, results3) — collection length gates its own row attribute.
# targets.rb's `rows_mock`/pluck/ids all build an `IterableSymbolicList`
# whose `__rows` (targets.rb) returns `[]` — no representative touched at
# all — whenever its OWN `(len(X) != 0)` gate is False; a representative
# row's attribute (`..._row_text_has_mention`, `..._row_guid`, ...) can only
# ever be read (and hence recorded) once that SAME list's length gate fired
# True. Same "attribute requires found" shape as Tier 1, one structural
# level up (collection non-emptiness instead of finder not_found).
# Auto-paired by matching a `len(X)` expr's `X` against every OTHER expr
# whose name is prefixed by that same `X` (e.g. `len(..._records_1_rows)`
# pairs with `..._records_1_row_text_has_mention`, which is NOT the same
# string but shares the `..._records_1_row` stem once the `len(...)`/`rows`
# suffix is stripped).
# ---------------------------------------------------------------------------
# NOTE: coverage_report.py's `fix_len_names` (ported from results3/
# people_stream/notifications_index — `len(X)` is a valid Z3 identifier but
# not a valid Python one, so the checker's declaration builder crashes on it
# and would otherwise dump the expr into unevaluable_exprs) renames every
# `len(X)` -> `SYM_LEN_X` in the raw dump JSON BEFORE `Run.from_dict` ever
# runs — so by the time THIS function sees `all_exprs`, the length-gate
# exprs already read `(SYM_LEN_X != 0)`, never the original `(len(X) != 0)`.
# Match the POST-rename form.
_LEN_RE = re.compile(r"\(SYM_LEN_([A-Za-z0-9_]+) != 0\)")


def _tier6_len_gates_row_attr(all_exprs):
    len_exprs = {}
    for e in all_exprs:
        m = _LEN_RE.match(e)
        if m:
            len_exprs[m.group(1)] = e  # e.g. "..._records_1_rows" -> "(SYM_LEN_... != 0)"

    out = []
    for var_name, len_expr in len_exprs.items():
        if not var_name.endswith("_rows"):
            continue
        stem = var_name[: -len("_rows")]  # "..._records_1"
        row_prefix = f"({stem}_row"  # matches "(..._records_1_row_text_has_mention ..."
        for e in all_exprs:
            if e == len_expr or not e.startswith(row_prefix):
                continue
            out.append(IndependenceAssumption(
                expr_a=len_expr, expr_b=e,
                description=f"{stem}: collection empty vs its own row attribute — "
                             "representative row only read when non-empty",
                agent_notes=(
                    "targets.rb IterableSymbolicList#__rows returns [] (no "
                    "representative touched) whenever its own length gate is "
                    "False; a representative row's attribute PC can only be "
                    f"recorded in a run where `{len_expr}` was observed True for "
                    f"THIS SAME list ({stem}). (len==False, row-attribute=*) is "
                    "structurally impossible for this specific collection var."
                ),
            ))
    return out


# ---------------------------------------------------------------------------
# TIER 1b — same-target "public gates later attributes" (findpublic_* only).
# targets.rb's FindPublicRouting#find_public! (faithfully reproducing
# post_service.rb:51-56):
#
#     Post.where(post_key(id_or_guid) => id_or_guid).public_send(tag).tap do |post|
#       raise ActiveRecord::RecordNotFound, "..." unless post
#       raise Diaspora::NonPublic unless post.public?
#     end
#
# `post.public?` is checked and, if False, raises Diaspora::NonPublic
# IMMEDIATELY inside find_public! — before control ever returns to the
# caller. So for a findpublic_* target with BOTH a `_public` expr and a
# `_text`/`_guid` attribute expr (the latter read later, by the presenter's
# `build_text`/`as_json` for "act" or by the `.reshares` association's
# `root_guid`-keyed lookup for "reshare" — see targets.rb naming module
# docstring), `_public == False` structurally forecloses the `_text`/`_guid`
# expr from EVER being recorded in that same run — same "guard" shape as
# Tier 1's not_found/attribute pairing, just one level deeper (both exprs
# are themselves gated behind not_found==False already, per Tier 1; THIS
# tier additionally gates the later attribute behind `public==True` too).
# The `public==True` side remains reachable and already demonstrated by
# execution independent of this pairing (see REPORT.md) — evilq_* targets
# have no `_public` expr at all (EvilQuery::VisibleShareableById#post!
# never checks post.public? — it is the authenticated-visibility path, not
# the public-only one), so this tier only ever applies to findpublic_*.
# ---------------------------------------------------------------------------
def _tier1b_public_gates_attrs(all_exprs):
    present = set(all_exprs)
    out = []
    for ctx in CONTEXTS:
        base = f"findpublic_{ctx}"
        pub = f"(SYM_RESULT_ActiveRecord__Relation_{base}_1_public == True)"
        if pub not in present:
            continue
        for suffix in ("text", "guid"):
            attr = f"(SYM_RESULT_ActiveRecord__Relation_{base}_1_{suffix} == '')"
            if attr not in present:
                continue
            out.append(IndependenceAssumption(
                expr_a=pub, expr_b=attr,
                description=f"{base}: public vs {suffix} — {suffix} only read "
                             "after find_public!'s public? guard passes",
                agent_notes=(
                    "targets.rb FindPublicRouting#find_public! (faithfully "
                    "reproducing post_service.rb:51-56): `raise "
                    "Diaspora::NonPublic unless post.public?` fires INSIDE "
                    f"find_public!, before control returns to the caller — "
                    f"so `{base}_1_public == False` means the whole request "
                    f"aborts (Diaspora::NonPublic, caught by "
                    f"posts_controller.rb's rescue_from) before the "
                    f"presenter/association code that reads `{suffix}` ever "
                    f"runs. ({base}_1_public=False, {suffix}=*) is "
                    f"structurally impossible; the True side remains "
                    f"reachable and demonstrated by execution independent "
                    f"of this specific pairing."
                ),
            ))
    return out


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
        for ia in _tier0_scenario_exclusivity(runs):
            aset.add(ia)
    for ia in _tier1_same_target_pairs(all_exprs):
        aset.add(ia)
    for ia in _tier1b_public_gates_attrs(all_exprs):
        aset.add(ia)
    for ia in _tier2_attempt_chain_pairs(all_exprs):
        aset.add(ia)
    for ia in _tier3_cross_context_pairs(all_exprs):
        aset.add(ia)
    for ia in _tier5_post_found_vs_act(all_exprs):
        aset.add(ia)
    for ia in _tier6_len_gates_row_attr(all_exprs):
        aset.add(ia)

    # results3 NOTE: results2's 3 hand-picked "presenter field-builder"
    # assumptions (find_by_1 vs find_by_2, both vs assoc_profile_nsfw) are
    # DROPPED here, not ported — their premise no longer holds. The STI
    # type-dispatch fix (targets.rb, `model_class`: bare Post -> StatusMessage)
    # means the representative post now has a `poll` association StatusMessage
    # carries that bare Post didn't, so find_by_1 is now a poll_participation
    # lookup (post_presenter.rb's poll_participation_answer_id), find_by_2 is
    # like_for, find_by_3 is reshare_for — verified by reading a sample dump's
    # symbolic_call notes (find_by_1's note: `SELECT "poll_participations".*
    # ... WHERE poll_id = $$(assoc_poll_id)`), not assumed. Re-deriving a
    # hand-picked, semantically-named replacement for every find_by_N (up to
    # _9 observed, from presenter recursion into reshare/root representatives
    # — see this file's docstring) was judged disproportionate for this pass;
    # Tier 5 above already cuts every find_by_N against the act-family (the
    # axis that mattered most for clique-size reduction in results2). find_by_N
    # vs find_by_M pairs among THEMSELVES are left fully connected — a
    # conservative (safe, not unsound) choice that leaves some residual
    # missing combos in that specific sub-family, reported honestly in
    # REPORT.md rather than reintroducing a stale hardcoded mapping.

    return aset
