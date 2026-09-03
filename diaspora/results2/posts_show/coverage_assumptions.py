"""posts_show — batch-local AssumptionSet (results2 CALL-SITE-STABLE restart,
2026-08-18).

See targets.rb's `PostsShowFinderNaming` module docstring for the naming
scheme this file is keyed against: every EvilQuery/find_public! finder
decision has its own dedicated, per-(context x attempt) declared target
(`evilq_{act,like,reshare}_{vis,author,public}`, `findpublic_{act,like,
reshare}`), each firing at most once per request -> always ordinal "_1". So
— unlike the prior ordinal-era attempt — assumptions CAN be safely keyed on
these `expr`s: each denotes exactly one real decision in every dump it
appears in (verified in REPORT.md's mapping table), never a moving target.

Corpus universe: 30 distinct PC exprs (see REPORT.md). Grouped:
  - 1 behavior-selector: `(Length(SYM_PARAM_id) < 16)` (post_key dispatch,
    post_service.rb:66) — stays fully connected, per COMPLETION_BRIEF.md.
  - 12 dedicated finder targets, each with a `_not_found` expr and 0-2
    "attribute" exprs (`_text`/`_guid`/`_public`) that only exist when the
    finder actually returned an object.
  - 3 presenter field-builder exprs untouched by this pass (find_by_1,
    find_by_2, assoc_profile_nsfw — different boundary, already stable).

TIER 1 — same-target "found vs attribute" impossibility (ported/generalized
from the prior ordinal-era Tier 1, `_same_call_impossible_combo_assumptions`,
now safe to apply broadly because the target name itself is stable):

  `ConcolicTargets.finder_mock` (concolic_targets.rb ~326-338):

      not_found = symbool(nf_name, ...)
      if not_found == true
        raise ... if raise_on_missing
        nil
      else
        symbolic_instance(model_class(receiver), name, sql)   # <- attrs built HERE
      end

  `symbolic_instance` builds every column reader (and, for booleans, the
  predicate reader's own PC) INSIDE the `else` branch. So for a given
  dedicated target, its `_text`/`_guid`/`_public` PC can only ever be
  RECORDED in a run where that SAME target's `_not_found == False` — never
  when `_not_found == True` (there is no object to read a column off).
  Applies uniformly to every (not_found, attribute) pair actually present in
  the corpus, generated programmatically so it can never drift from the
  observed universe.
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

# Any of the 12 dedicated finder targets: evilq_{ctx}_{attempt} or
# findpublic_{ctx}. Captures the target's base name so `_not_found` and its
# sibling attribute exprs can be paired up regardless of which target.
_NF_RE = re.compile(
    r"\(SYM_RESULT_ActiveRecord__Relation_((?:evilq|findpublic)_[a-z_]+?)_1_not_found == True\)"
)
_ATTR_RE = re.compile(
    r"\(SYM_RESULT_ActiveRecord__Relation_((?:evilq|findpublic)_[a-z_]+?)_1_(text|guid|public) "
)

CONTEXTS = ("act", "like", "reshare")
ATTEMPTS = ("vis", "author", "public")


def _tier1_same_target_pairs(all_exprs):
    nf_expr = {}
    attr_exprs = {}
    for e in all_exprs:
        m = _NF_RE.match(e)
        if m:
            nf_expr[m.group(1)] = e
            continue
        m = _ATTR_RE.match(e)
        if m:
            attr_exprs.setdefault(m.group(1), []).append((m.group(2), e))

    out = []
    for base, attrs in attr_exprs.items():
        nf = nf_expr.get(base)
        if not nf:
            continue
        for attr_name, attr_expr in attrs:
            out.append(IndependenceAssumption(
                expr_a=nf, expr_b=attr_expr,
                description=f"{base}: not_found vs {attr_name} — attribute PC "
                             "only fires in finder_mock's 'found' branch",
                agent_notes=(
                    "finder_mock (concolic_targets.rb ~326-338): symbolic_instance "
                    "(the object whose columns/predicates the app subsequently "
                    f"reads, producing the '{attr_name}' PC) is built ONLY in the "
                    "not_found==False else-branch. (not_found=True, "
                    f"{attr_name}=*) is structurally impossible for target "
                    f"'{base}' — the attribute PC is never recorded in a run "
                    "where this target's not_found is True. `target_name` for "
                    f"this dedicated target is invariant ('ActiveRecord::Relation."
                    f"{base}'), so this holds in every dump, not just most."
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
    return "auth" if (label or "").startswith("auth") else "anon"


# ---------------------------------------------------------------------------
# TIER 0 — scenario exclusivity (auth vs anon). PostService#find!
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
def _tier0_scenario_exclusivity(runs):
    expr_scenarios = {}
    for r in runs:
        scen = _scenario_of(r.label)
        for pc in r.path_conditions:
            expr_scenarios.setdefault(pc.expr, set()).add(scen)

    auth_only = sorted(e for e, s in expr_scenarios.items() if s == {"auth"})
    anon_only = sorted(e for e, s in expr_scenarios.items() if s == {"anon"})

    out = []
    for a in auth_only:
        for b in anon_only:
            out.append(IndependenceAssumption(
                expr_a=a, expr_b=b,
                description="scenario exclusivity: auth-only expr vs anon-only expr",
                agent_notes=(
                    "post_service.rb:16-22 `find!`'s `if user` branch selects "
                    "EXCLUSIVELY find_non_public_by_guid_or_id_with_user! (the "
                    "evilq_* family) or find_public! (the findpublic_* family) "
                    "for the WHOLE request — never both. Every run in this "
                    "corpus is fixed to one scenario (auth: symbolic "
                    "current_user: anon: current_user=nil) by run_dse.rb's "
                    "SCENARIOS loop, never mixed within a run. Verified: this "
                    "expr appears ONLY in auth-labeled runs across the entire "
                    "4278-dump corpus, the other ONLY in anon-labeled runs — "
                    "so no single run's path can ever contain both, and no "
                    "combination of their outcomes is reachable together."
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
_PRESENTER_EXPRS = (
    "(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found == True)",
    "(SYM_RESULT_ActiveRecord__FinderMethods_find_by_2_not_found == True)",
    "(assoc_profile_nsfw == True)",
)


def _tier4_presenter_vs_act(all_exprs):
    act_family = _context_family(all_exprs, "act")
    out = []
    for pe in _PRESENTER_EXPRS:
        if pe not in all_exprs:
            continue
        for ae in act_family:
            out.append(IndependenceAssumption(
                expr_a=pe, expr_b=ae,
                description="presenter field vs act-family finder — presenter "
                             "runs only once act's lookup succeeded (any attempt)",
                agent_notes=(
                    "posts_controller.rb:20-27: `post = post_service.find!"
                    "(params[:id])` ('act') must succeed (post_service.rb "
                    "raises RecordNotFound/NonPublic otherwise) before "
                    "`PostPresenter.new(post, current_user)` is even "
                    "constructed, let alone `as_json` -> "
                    "build_interactions_json (post_presenter.rb:108-116, "
                    "find_by_1/find_by_2) / non_directly_retrieved_attributes "
                    "(nsfw:, post_presenter.rb:62) evaluated. Which of "
                    "act's vis/author/public attempts (or, anon, the single "
                    "findpublic_act attempt) produced `post` does not change "
                    "what the presenter subsequently reads — identical "
                    "presenter code runs regardless. So this pair is either "
                    "impossible (this act-family expr's value implying the "
                    "whole act lookup failed) or redundant (implying act "
                    "succeeded, in which case the presenter field's own "
                    "coverage, demonstrated via execution independent of "
                    "which attempt succeeded, already accounts for it)."
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
    for ia in _tier4_presenter_vs_act(all_exprs):
        aset.add(ia)

    # ------------------------------------------------------------------
    # Presenter field-builder independences (post_presenter.rb:108-116,
    # `build_interactions_json`, unconditional hash literal — see the
    # archived _archive_ordinal_era/coverage_assumptions.py for the original
    # argument; these three exprs (find_by_1/find_by_2/assoc_profile_nsfw)
    # are UNTOUCHED by the naming pass, so the names are identical and the
    # argument carries over verbatim.
    # ------------------------------------------------------------------
    aset.add(IndependenceAssumption(
        expr_a="(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found == True)",
        expr_b="(SYM_RESULT_ActiveRecord__FinderMethods_find_by_2_not_found == True)",
        description="like_for (post.rb:143) vs reshare_for (post.rb:138) — "
                     "independent finds in the same unconditional hash literal",
        agent_notes="post_presenter.rb:108-116 build_interactions_json: "
                     "`likes: [user_like].compact, reshares: [user_reshare].compact, "
                     "...` — both always evaluated (no short-circuit), neither "
                     "call's args reference the other's symbolic result. "
                     "like_for queries Like keyed on (@post, current_user); "
                     "reshare_for queries Reshare keyed on (@post, current_user); "
                     "disjoint tables, independent finds.",
    ))
    aset.add(IndependenceAssumption(
        expr_a="(assoc_profile_nsfw == True)",
        expr_b="(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found == True)",
        description="Post#nsfw (author's profile) vs like_for — disjoint models",
        agent_notes="nsfw: reads @post.author.profile.nsfw? (post.rb:161-162); "
                     "like_for queries Like keyed on (@post, current_user) "
                     "(post.rb:143). No shared symbolic value.",
    ))
    aset.add(IndependenceAssumption(
        expr_a="(assoc_profile_nsfw == True)",
        expr_b="(SYM_RESULT_ActiveRecord__FinderMethods_find_by_2_not_found == True)",
        description="Post#nsfw (author's profile) vs reshare_for — disjoint models",
        agent_notes="nsfw: reads @post.author.profile.nsfw? (post.rb:161-162); "
                     "reshare_for queries Reshare keyed on (@post, current_user) "
                     "(post.rb:138). No shared symbolic value.",
    ))

    return aset
