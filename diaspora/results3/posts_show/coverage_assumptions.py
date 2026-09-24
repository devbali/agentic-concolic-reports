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

TIER 0 — scenario x format exclusivity: DELETED 2026-09-10. Its whole argument
was "these exprs' observed scenario sets are DISJOINT, so no single run's path
can contain both", and under the co-evaluation semantics (DISCIPLINE §16) the
engine derives that from the same evidence for itself. A declaration over a
pair no run co-evaluates relaxes nothing. `build` now filters any survivor with
the same property and PRINTS the count.

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

from concolic_engine.coverage import maximal_sets  # noqa: E402
from concolic_engine.assumptions import (  # noqa: F401
    AliasAssumption,
    AssumptionSet,
    IndependenceAssumption,
    UntrackedPathAssumption,
    OneSideUntrackedPathAssumption,
    SymbolicConstraintAssumption,
    PathSource,
)

# --- Alias (ported from notifications_index, 2026-09-09) -----------
# posts_show has the same call-ordinal identity problem as notifications_index
# and people_stream: measured over a 302-dump sample, list reads appear as
# CollectionProxy_records_{1,2,3,4} and Relation_records_{1,2,3,4,5,7} — the
# SAME logical read at different ordinals depending on the path prefix,
# because a symbolic result is named by WHEN the call happened
# (SymbolicFunc.next_call_idx), not by WHAT it is. That makes the checker
# demand combinations across ordinals no single path can realise, and makes
# demand seeds keyed on an ordinal inert whenever the path takes another.
# Re-key by the statement resolved to (binds kept, literals wildcarded).
# Identity is verified by the gate's Alias derived test, which FAILS
# on an unsound alias.
ALIAS_PATTERN = (r"SYM_RESULT_ActiveRecord__(?:Associations__CollectionProxy_records"
                 r"|Relation_records|Relation_to_ary)_\d+")
ALIASES = [AliasAssumption(
    result_pattern=ALIAS_PATTERN, key="statement",
    description="ordinal-named list reads identified by their statement (binds kept)",
    agent_notes=("the ordinal of posts_show's list reads is a function of the path "
                 "prefix; re-keyed by statement so one fact is one variable."))]


# --- RENDER-ORDINAL IDENTITY (declared 2026-09-12; §78.9 -> §79) ------------
# ONE FACT, TWO NAMES: `SYM_RESULT_Anonymous_process_2` and
# `SYM_RESULT_Anonymous_process_3` are the SAME decision, and the demand
# universe must not ask them to disagree.
#
# WHAT THEY ARE. `Anonymous.process` is the wall mock (targets.rb W7) of
# `Diaspora::MessageRenderer::Processor.process`, called from ONE statement —
# `message_renderer.rb:264`, the private `MessageRenderer#process`, which
# every public renderer method funnels through with the instance's own
# `@text`. Corpus-wide (192 365 dumps, _p16_render_scan.py) EVERY ONE of the
# 557 489 calls to this target is at that one file:line. The mock's `returns`
# lambda is the IDENTITY on its argument (`v = m.value; ...build(v.to_s)`),
# so the result is a pure function of `args["message"]` — measured, 0
# determinism violations corpus-wide.
#
# WHY THE ORDINALS ARE ONE FACT (the evidence, all of it re-measured on the
# whole corpus for this declaration — §78.9 had it on samples):
#   * 117 715 runs make BOTH call 2 and call 3. In 117 715 of 117 715 the two
#     calls receive IDENTICAL arguments — args_equal_when_both_called
#     {True: 117715, False: 0}.
#   * 6 303 runs DECIDE both (`(... == '')` recorded for each). Joint
#     outcomes: (False,False) 3 226, (True,True) 3 077, (True,False) 0,
#     (False,True) 0. 6 303 co-evaluations, 0 disagreements.
#   * The ordinals of this statement DO carry different messages in general —
#     the per-run grouping signature (_p16_render_scan3.py) is `1,2` 43 313,
#     `1,2,3,4` 34 896, `1,2,3|4` 22 708, `1|2,3,4` 20 894, `1,2,3` 15 261,
#     `1,4|2,3` 12 691, `1|2,3|4` 6 843, `1|2,3` 4 422, `1|2` 1 750 — so this
#     is NOT a corpus in which the mock only ever sees one string (it sees
#     five). In EVERY one of those signatures ordinals 2 and 3 fall in the
#     SAME group. The split that does occur falls at 1| or |4, never at 2|3.
#   * Decisions are recorded on ordinals 2 and 3 ONLY (never 1, never 4), and
#     the only expression form over them is `(... == '')`.
#
# WHY IT IS A CONSTRAINT AND NOT AN `AliasAssumption`. §78.9 option (1) said
# "extend the alias assumption". MEASURED, IT CANNOT BE DONE THAT WAY without
# editing `src/`, which this batch may not do:
#   * `concolic_engine.assumptions._alias_core` skips any symbolic result
#     whose `symbolic_call` note is not a STATEMENT
#     (`is_statement_note` = /^(SELECT|INSERT|UPDATE|DELETE|WITH)/); this
#     target's note is the prose "Diaspora::MessageRenderer::Processor.process"
#     (the docstring names "a render probe" as the excluded case). Run on a
#     real dump, an `AliasAssumption(result_pattern=r'SYM_RESULT_Anonymous_
#     process_\d+', key='statement')` returns an EMPTY alias map: it is INERT,
#     it would retire nothing, and it would say in the ledger that something
#     had been declared.
#   * the gate's derived alias test (`assumption_checker._test_alias`) probes
#     by intervening on `len(<ordinal>_rows)` and by a k+1-row replay. There
#     is no list and no length dimension here, and the canonical name would
#     never appear in `_ALIAS_INDEX` — the test's own answer would be
#     "canonical name never produced by the CURRENT corpus".
# So the identity is declared as the equality it actually is. The two names
# are STRING results; the constraint is fed into every SMT query
# (`AssumptionSet.symbolic_constraints` -> `fixed_base`), and its only effect
# is on demand sets that contain BOTH decisions — where only one is a member
# the other stays free and no demand is lost. Verified with the engine's own
# solver: the two agreeing assignments stay SAT, the two disagreeing ones
# (which 201 of the 526 P15F witnesses demand) become UNSAT.
#
# SCOPE AND REVERSIBILITY. Ordinals 1 and 4 are deliberately NOT included:
# they carry different messages in 33 909 / 42 242 runs respectively and no
# run has ever decided them, so an equality over them would be both false and
# inert. `NO_RENDER_IDENTITY=1` withdraws this declaration without editing
# the file (the same knob shape as `NO_PINS`), so the pass can be re-run with
# and without it and the difference measured.
RENDER_IDENTITY = (SymbolicConstraintAssumption(
    z3_expr=("SYM_RESULT_Anonymous_process_2 == SYM_RESULT_Anonymous_process_3"),
    description=("Anonymous.process @ message_renderer.rb:264 — ordinals 2 and 3 are "
                 "ONE decision: one statement, one renderer instance, and a mock that "
                 "returns its own argument"),
    agent_notes=(
        "192 365-dump census (_p16_render_scan{,2,3}.py, 2026-09-12): all 557 489 "
        "calls of this target are at message_renderer.rb:264; the mock (targets.rb "
        "W7) returns args['message'] itself, 0 determinism violations; 117 715/117 715 "
        "runs that make both calls give them the SAME argument; 6 303 runs decide both "
        "-- (F,F) 3 226, (T,T) 3 077, disagreements 0; and although the statement's "
        "ordinals do carry different messages across a run (grouping signatures "
        "1,2,3|4, 1|2,3,4, 1,4|2,3, 1|2,3|4, ...), 2 and 3 are in the same group in "
        "every one of them. Ordinals 1 and 4 are never decided and are not covered. "
        "Declared as a constraint, not an AliasAssumption, because _alias_core is "
        "note-gated to SQL statements and returns an empty map for this target "
        "(measured) -- see the block comment above."),),)



# --- RENDER TEXT SOURCE (declared 2026-09-13; P29 §88) ----------------------
# THE RENDERED TEXT IS THE POST'S TEXT: `(SYM_RESULT_Anonymous_process_3 == '')`
# is the SAME FACT as `(<the act-family finder that resolved the post>
# _text_empty == True)`.
#
# WHAT IT IS, from the source, not inferred. §79 already established (over
# 192 365 dumps) that every call of this target is `message_renderer.rb:264`,
# the private `MessageRenderer#process`, which every public renderer method
# funnels through with its own instance's `@text`, and that the wall mock
# (targets.rb W7) returns that argument ITSELF (`v = m.value;
# PcVisibleConcreteString.build(v.to_s, ...)`) with 0 determinism violations.
# posts_show renders THE POST, and the post is whichever of the four
# mutually-exclusive act-family finders resolved it. So the rendered string is
# empty exactly when that post's text is empty, and `..._text_empty` is the
# seed dimension that says so.
#
# THE CENSUS (`_p29_decmatrix.py` over the whole 48 368-profile pruned corpus
# `_snapshot_pruned_P26F2.txt`, 137 decisions, 0 unparseable):
#   `(SYM_RESULT_Anonymous_process_3 == '')` is evaluated in 4 685 profiles.
#   co-evaluated with          agree   DISAGREE
#     evilq_act_vis_1_text_empty      2 326   2 326        0
#     evilq_act_author_1_text_empty   1 253   1 253        0
#     evilq_act_public_1_text_empty     911     911        0
#     findpublic_act_1_text_empty       189     189        0
#                                     4 679   4 679        0
#   The remaining 6 P3-evaluating profiles record NO act-family `_text_empty`
#   at all (they are old wall-probe dumps `*_EMPTYTXT`, `*_W9b`, `*_W9c`) —
#   an absent antecedent, not a disagreement.
#   The four act finders are pairwise NEVER co-evaluated (0 profiles for all
#   six pairs), so exactly one is live in a run and the four constraints can
#   never conflict inside one demand set.
#   `(Anonymous_process_2 == '')` behaves identically (4 685 co-evaluations
#   with `_3`, 0 disagreements) — that is §79's RENDER_IDENTITY, unchanged.
#   No profile records `(Anonymous_process_3 == '')` BOTH ways.
#
# FALSIFIER (the same shape §79.3(b) used): ANY run that records
# `(SYM_RESULT_Anonymous_process_3 == '')` and the act-family finder's
# `_text_empty` decision with DIFFERENT values. Self-re-deriving: such a run
# enters the corpus and the census that licenses this declaration fails.
# Actively falsified by construction (P29, `_p29_probe_*`), not only scanned.
#
# WHY IT IS NOT AN `AliasAssumption` and not an `IndependenceAssumption`: for
# the same measured reason §79.1 gives — `_alias_core` is note-gated to SQL
# statements and returns an EMPTY map for this target — and because this is an
# EQUALITY between two decisions, which is what a `SymbolicConstraintAssumption`
# is for. Reversible with `NO_RENDER_TEXT_SOURCE=1`.
_RTS_ACT = ("SYM_RESULT_ActiveRecord__Relation_evilq_act_vis_1",
            "SYM_RESULT_ActiveRecord__Relation_evilq_act_author_1",
            "SYM_RESULT_ActiveRecord__Relation_evilq_act_public_1",
            "SYM_RESULT_ActiveRecord__Relation_findpublic_act_1")
_RTS_CENSUS = {"SYM_RESULT_ActiveRecord__Relation_evilq_act_vis_1": (2326, 0),
               "SYM_RESULT_ActiveRecord__Relation_evilq_act_author_1": (1253, 0),
               "SYM_RESULT_ActiveRecord__Relation_evilq_act_public_1": (911, 0),
               "SYM_RESULT_ActiveRecord__Relation_findpublic_act_1": (189, 0)}
RENDER_TEXT_SOURCE = tuple(
    SymbolicConstraintAssumption(
        z3_expr=("(SYM_RESULT_Anonymous_process_3 == '') == "
                 f"({_v}_text_empty == True)"),
        description=("Anonymous.process @ message_renderer.rb:264 renders THE POST's "
                     f"text: the rendered string is empty iff {_v}'s text is empty"),
        agent_notes=(
            f"P29 census over 48 368 profiles (_p29_decmatrix.py, 2026-09-13): "
            f"{_RTS_CENSUS[_v][0]} co-evaluations, {_RTS_CENSUS[_v][0]} agreements, "
            f"{_RTS_CENSUS[_v][1]} disagreements. The four act-family finders are "
            f"pairwise never co-evaluated, so exactly one of the four constraints is "
            f"ever active in a demand set. Falsifier: any run recording the two with "
            f"different values."))
    for _v in _RTS_ACT)


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


# ---------------------------------------------------------------------------
# ARGUMENT P — THE OVERNIGHT PINS (2026-09-10, installed by the completion
# drive agent).  A SEPARATE, COUNTED TIER: printed on its own
# (`OVERNIGHT_PINS=` in the `[assumptions]` line), reversed by one edit
# (`_OVERNIGHT_PINS = ()`), and built WITHOUT it under `NO_PINS=1` — so no
# number that depends on these is ever quoted without saying so.
#
# AUTHORITY.  Owner instruction 2026-09-10 (overnight), "continue working till
# all endpoints are complete", together with the standing direction in
# notifications `_COMPLETION_CAMPAIGN_20260910.md` §8 to INSTALL an
# unreachable-side pin rather than leave it a proposal — and the drive brief's
# condition that a genuinely unreachable side be DRIVEN AT TWICE first, rooted
# from every base that reaches the site.  Both rounds are recorded in
# `_COMPLETION_20260910.md` §8-§11.
#
# TWO FAMILIES, ON DIFFERENT ARGUMENTS.  They are kept apart deliberately: they
# have different evidence and different falsifiers, and pinning one has no
# bearing on the other.
#
#   P1  the three `SYM_LEN_..._records_N_rows != 0 :: taken` NullRelation sites
#   P2  the four `..._as_api_response_N_row_guid != StringVal('') :: taken`
#       framework short-circuits (the named defect, four instances here against
#       people_stream's one)
# ---------------------------------------------------------------------------

_NULLRELATION_TRUE_UNREACHABLE = (
    "targets.rb `rows_mock` short-circuits an ActiveRecord::NullRelation "
    "receiver BEFORE it consults any seed: `next IterableSymbolicList.new(0, "
    "name: \"#{name}_rows\", note: \"NullRelation (empty by definition, no "
    "SQL)\", representative: nil) if null_rel && receiver.is_a?(null_rel)`. The "
    "length is a hard-coded 0, so no seed can move it — MEASURED, not inferred: "
    "a rooted seed carrying len(...)=1 was ACCEPTED into the dump's "
    "concolic_seeds and the recorded var was still 0 with that note. And the "
    "hard-coded 0 is FAITHFUL rather than a mock defect: NullRelation is what "
    "`.none` returns and its `to_a` really is `[]` in the real app, so a real "
    "run cannot produce a non-empty result from that receiver either. Census "
    "through the engine's own load path (canonicalize_ordinals + fix_len_names) "
    "over a stride-40 scan of the 96 422-dump snapshot: this canonical name "
    "carries the NullRelation note in 100% of its observations, value 0 in "
    "100%. These canonical names denote NullRelation sites SPECIFICALLY because "
    "canonicalize_ordinals aliases a result by its NOTE and a NullRelation has "
    "no SQL to alias on, so it is the one `records` call that keeps its bare "
    "per-run ordinal. FALSIFIER: any run recording this expression `taken`; or, "
    "at code level, a `records` call on a NullRelation receiver whose length is "
    "not forced to 0 — remove the short-circuit and the seed takes effect. "
    "KNOWN LIMITATION, stated rather than hidden: the SET of such names is not "
    "closed, because a future run that puts a NullRelation at a new ordinal "
    "mints a new canonical name with the same unreachable side. That is the "
    "DecisionAlias defect (call_interceptor.rb:142-144) reaching the one case "
    "with no note to alias on; a stable alias for the NullRelation branch fixes "
    "it in targets.rb but needs a corpus regeneration."
)

_GUID_TRUE_UNREACHABLE = (
    "action_dispatch/journey/formatter.rb:40-41 (actionpack 5.2.4.3, stock gem, "
    "unmodified), reached from PostPresenter -> `author.as_api_response("
    ":backbone)` -> Person#as_json (app/models/person.rb:344-356), whose line "
    "351 is `url: Rails.application.routes.url_helpers.person_path(self)`. Line "
    "40's `break if defaults[key].nil? && parameterized_parts[key].present?` "
    "breaks the route-parts loop BEFORE line 41 (the '!=' pair's site) whenever "
    "the guid is non-blank. When the guid IS blank, line 41 does run and "
    "`guid.to_s != ''` is forced False by the value just established. So the "
    "'!=' pair's True outcome cannot be produced by any seed: the only path "
    "that evaluates it forces it False, and the alternative path never "
    "evaluates it at all. Identical in mechanism, site and evidence to "
    "people_stream's Argument 5 / 5b and to notifications' siblings. Corpus "
    "differential over this endpoint's own snapshot, through the engine's load "
    "path, two event sites only and byte-identical to the declared siblings "
    "(blank.rb:126 'blank?' '==' and formatter.rb:41 'block in generate' '!='): "
    "RE-MEASURED BY THE INSTALLING AGENT on a stride-8 scan of the 96 422-dump "
    "snapshot (12 053 dumps), through canonicalize_ordinals + fix_len_names - "
    "0 of 9 432 evaluations of the '!=' pair are taken (per family: 2 980 / "
    "2 620 / 1 824 / 2 008, all not_taken), in 4 788 runs that evaluate it, and "
    "530 runs show the other arm - the line-40 break, with the '!=' absent "
    "entirely. (The preflight's figures on the smaller snapshot were 9 613 / "
    "5 306 / 529; same shape, and the pin rests on the re-measurement.) "
    "FALSIFIER: any run recording this expression taken; at code level, a route "
    "default on person_path's :id segment (config/routes.rb has none) would "
    "stop the break and make the True side reachable."
)

# THE TWO DRIVES CAME FIRST, AND BOTH FAILED — that is what authorises these.
#
#   round TR0910a  `_tree_root.py`, the 8 richest bases per (target, variant),
#                  verbatim base seeds + one flip:      45 seeds ->    43 runs
#   round TR0910w  `_tree_root_wide.py`, EVERY DISTINCT base seed dict in the
#                  corpus that reaches the site (t06/t08 exhaustively; t01-t05
#                  capped at 300 distinct contexts per variant):
#                                                    3 024 seeds -> 3 024 runs
#
# `_tree_check.py` over the wide round, through the engine's own load path:
# HIT=0 for all seven, with the expression EVALUATED on the other side 1 399 /
# 514 / 1 111 / 1 159 / 1 209 / 291 / 134 times respectively — so the seeds
# landed in the right contexts and the branch did not move. 0 JVM aborts, every
# seed produced exactly one dump.
_OVERNIGHT_PINS = tuple(
    OneSideUntrackedPathAssumption(
        expr=f"(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_{_n}_rows != 0)",
        tracked_side="not_taken",
        description=("len(records)!=0 can only ever be observed False at this "
                     "call site: it is an ActiveRecord::NullRelation, whose "
                     "length rows_mock hard-codes to 0 -- OVERNIGHT PIN"),
        agent_notes=_NULLRELATION_TRUE_UNREACHABLE,
    # ORDINAL 5 ADDED 2026-09-10 (drive §47.3). The bulk round BV3A0910 minted
    # a FOURTH NullRelation canonical name, which §9 had predicted in writing
    # ("the set of such names is NOT closed"). Same evidence, re-measured on
    # this endpoint's own grown corpus rather than inherited: 39/39
    # observations carry the note 'NullRelation (empty by definition, no SQL)'
    # and value 0, and the round's own runs show the seed ACCEPTED and
    # CONTRADICTED at exactly the NullRelation receivers — (1,0) 3, (2,0) 4,
    # (4,0) 3 against (0,0) 236 / (1,1) 227 / (2,2) 216 / (4,4) 242 at the
    # real-SQL receivers sharing the raw ordinal.
    ) for _n in (5, 7, 8, 10)
) + tuple(
    OneSideUntrackedPathAssumption(
        expr=f"(SYM_RESULT_ActsAsApi__Collection_as_api_response_{_n}_row_guid "
             f"!= StringVal(''))",
        tracked_side="not_taken",
        description=("guid!='' can only ever be observed False (framework "
                     "short-circuit at journey/formatter.rb:40) -- OVERNIGHT PIN"),
        agent_notes=_GUID_TRUE_UNREACHABLE,
    ) for _n in (1, 2, 3, 4)
)


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

    # --- ARGUMENT P: THE OVERNIGHT PINS (separate, counted, reversible) ---
    import os as _os
    _pins = () if _os.environ.get("NO_PINS") else _OVERNIGHT_PINS
    for _p in _pins:
        aset.add(_p)

    # --- RENDER-ORDINAL IDENTITY (2026-09-12, §79): declared, counted and
    # reversible exactly like the pins above. See the block comment at the
    # head of this file for the 192 365-dump evidence and for why it is a
    # SymbolicConstraintAssumption rather than an AliasAssumption.
    _rid = () if _os.environ.get("NO_RENDER_IDENTITY") else RENDER_IDENTITY
    for _r in _rid:
        aset.add(_r)

    # --- RENDER TEXT SOURCE (2026-09-13, P29 §88): declared, counted and
    # reversible exactly like RENDER_IDENTITY above. See the block comment at
    # the head of this file for the 48 368-profile census and the falsifier.
    _rts = () if _os.environ.get("NO_RENDER_TEXT_SOURCE") else RENDER_TEXT_SOURCE
    for _r in _rts:
        aset.add(_r)

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

    # CO-EVALUATION FILTER (2026-09-10). The engine demands a combination only
    # over decisions some run evaluated TOGETHER, so an independence over a
    # pair no run co-evaluates relaxes nothing. TIER 0 (scenario/format
    # exclusivity) went with that rule: its whole argument was "these exprs'
    # observed scenario sets are DISJOINT, so no single run's path contains
    # both" — which is exactly the claim the engine now makes for itself, from
    # the same evidence. It was "the dominant clique-size reducer"; under the
    # new semantics there is nothing for it to reduce. This filter drops any
    # survivor with the same property and says how many.
    if runs:
        sets = set()
        for r in runs:
            e = frozenset(pc.expr for pc in r.path_conditions)
            if e:
                sets.add(e)
        coeval = set()
        for e in maximal_sets(sets):
            es = sorted(e)
            for i, a in enumerate(es):
                for b in es[i + 1:]:
                    coeval.add(frozenset((a, b)))
        kept, inert = [], 0
        for a in aset.assumptions:
            if isinstance(a, IndependenceAssumption) and \
                    frozenset((a.expr_a, a.expr_b)) not in coeval:
                inert += 1
                continue
            kept.append(a)
        import sys
        print(f"[assumptions] declared={len(kept)} "
              f"INERT(never-co-evaluated, not declared)={inert} "
              f"OVERNIGHT_PINS={len(_pins)} "
              f"RENDER_IDENTITY={len(_rid)} "
              f"RENDER_TEXT_SOURCE={len(_rts)}", file=sys.stderr)
        aset.assumptions = kept
    return aset
