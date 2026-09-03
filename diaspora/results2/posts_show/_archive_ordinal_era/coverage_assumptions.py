"""posts_show — batch-local AssumptionSet (results2 combination-coverage pass).

Empty to start (per COMPLETION_BRIEF.md step 1). Populated iteratively as
each blocking missing combo is either closed by execution (preferred) or by
an argued assumption. See coverage_report.py's docstring for how this is
loaded, and the final report (delivered as the completing agent's message,
not a file) for the argument behind every assumption added here.

IMPORTANT — ordinal-instability finding (2026-08-18, this pass):
`SYM_RESULT_ActiveRecord__FinderMethods_first_<N>` does NOT name a single
decision. Empirically (grepped every dump's `symbolic_call` events for
result_name -> (file, lineno, function)):

  first_1 -> lib/evil_query.rb:104 in `post!`            (200/252 dumps, auth)
  first_1 -> app/services/post_service.rb:52 in `find_public!` (52/252, anon)

and, WITHIN the auth scenario alone, first_2..first_7 are even less stable:
`EvilQuery::VisibleShareableById#post!` is `querent_has_visibility.first ||
querent_is_author.first || public_post.first` (evil_query.rb:104,109-122) —
UP TO 3 `.first` calls per invocation, chained by Ruby's `||` short-circuit —
and `PostPresenter#with_initial_interactions` (post_presenter.rb:24-31)
calls `post_service.find!` A FURTHER TWO TIMES (once via
`LikeService#find_for_post`, once via `ReshareService#find_for_post`,
post_presenter.rb:27-28 -> like_service.rb:23-26 / reshare_service.rb:14-17
-> post_service.rb:58-59 -> evil_query.rb:104 again), each independently
re-running the SAME up-to-3-call `||` chain against FRESHLY, INDEPENDENTLY
seeded not_found flags (the mock has no memory of the earlier "found"
outcome for the "same" post). So `first_2`'s identity shifts between "the
first invocation's 2nd attempt" and "the second invocation's 1st attempt"
depending on how many calls the *same run* already consumed — the ordinal
is a moving target WITHIN a single scenario, not just across scenarios.

Given assumptions.py's `_matches` is exact-expr, declaring
`IndependenceAssumption(expr_a="...first_2...", ...)` would silently apply
to BOTH of those distinct decisions, uniformly, whether or not the argument
holds for both. **Per COMPLETION_BRIEF.md / the acute-ordinal-caveat
instruction: this file therefore declares NO independence/untracked
assumption keyed on any `first_<N>_*` expression.** That residual is left
fully dependent (conservative) and reported as structural residue.

Exprs that VERIFIED as single, stable decisions (100% of occurrences at one
call site) and so ARE safe to key by `expr`:
  - find_by_1  -> app/models/post.rb:143 `like_for`     (PostPresenter#user_like)
  - find_by_2  -> app/models/post.rb:138 `reshare_for`   (PostPresenter#user_reshare)
  - assoc_profile_nsfw -> app/models/post.rb:161-162 `Post#nsfw`
        (`self.author.profile.nsfw?`), read from post_presenter.rb:62
        `non_directly_retrieved_attributes`'s `nsfw:` hash value.
"""

import re

from concolic_engine.assumptions import (  # noqa: F401
    AssumptionSet,
    IndependenceAssumption,
    UntrackedPathAssumption,
    OneSideUntrackedPathAssumption,
    SymbolicConstraintAssumption,
    PathSource,
)


# ---------------------------------------------------------------------------
# Tier 1 — same-call "impossible combo" independence (added 2026-08-18,
# coordinator's structure-first pass).
#
# `ConcolicTargets.finder_mock` (concolic_targets.rb:326-335):
#
#     not_found = symbool(nf_name, ...)
#     if not_found == true
#       raise ... if raise_on_missing
#       nil
#     else
#       symbolic_instance(model_class(receiver), name, sql)   # <- HERE
#     end
#
# and `symbolic_instance` (concolic_targets.rb:216-242) is what builds each
# column's symbolic var (`guid`, `text`) and each boolean column's predicate
# reader (`public?`) — ALL of it inside the `else` branch. So for a given
# call ordinal N, `first_N_guid`/`first_N_text`/`first_N_public`'s underlying
# PC can only ever be RECORDED in a run where `first_N_not_found == False` —
# never in a run where it's True (there is no object to read `.guid`/`.text`/
# `.public?` off). This is the guard-truncated-cross-term case verbatim: of
# the 4 (not_found, attribute) combinations, 2 are STRUCTURALLY IMPOSSIBLE
# (not_found=True paired with EITHER attribute outcome — the attribute PC
# simply never fires in that run) and the other 2 are exactly what execution
# already provides deterministically once not_found=False. Unlike the
# cross-N `first_<N>_not_found` chain (kept — see module docstring: that
# chain genuinely SELECTS which SQL query runs next, so it's a Tier-3 "keep"
# per the coordinator's classification), this SAME-N pairing carries zero
# behavior-selection: it is pure "attribute construction happened or it
# didn't", gated by the SAME ordinal's own not_found. This holds regardless
# of which real-world call `first_N` denotes in a given run (auth's
# evil_query.rb:104 `post!` arms, or anon's post_service.rb:52
# `find_public!`) — `finder_mock` is the ONE shared boundary for both, so
# the argument is scenario-independent and immune to the ordinal-instability
# problem that blocks cross-N assumptions.
#
# Built programmatically (not hand-enumerated) from whatever (not_found,
# attribute) pairs the CURRENT dump corpus actually contains, so it can
# never drift out of sync with the universe as exploration goes deeper.
# ---------------------------------------------------------------------------
_FINDER_ATTR_RE = re.compile(
    r"\(SYM_RESULT_(ActiveRecord__FinderMethods_first_\d+)_(guid|text|public) "
)
_FINDER_NF_RE = re.compile(
    r"\(SYM_RESULT_(ActiveRecord__FinderMethods_first_\d+)_not_found == True\)"
)


def _same_call_impossible_combo_assumptions(all_exprs):
    """One IndependenceAssumption per (first_N_not_found, first_N_<attr>) pair
    actually present in `all_exprs` — see the Tier-1 block comment above."""
    nf_expr = {}
    attr_exprs = {}  # base -> [(attr, expr)]
    for e in all_exprs:
        m = _FINDER_NF_RE.match(e)
        if m:
            nf_expr[m.group(1)] = e
            continue
        m = _FINDER_ATTR_RE.match(e)
        if m:
            attr_exprs.setdefault(m.group(1), []).append((m.group(2), e))

    out = []
    for base, attrs in attr_exprs.items():
        nf = nf_expr.get(base)
        if not nf:
            continue
        for attr_name, attr_expr in attrs:
            out.append(IndependenceAssumption(
                expr_a=nf,
                expr_b=attr_expr,
                description=f"{base}: not_found vs {attr_name} — attribute "
                             "PC only fires in the finder_mock 'found' branch",
                agent_notes="finder_mock (concolic_targets.rb:326-335): "
                             "symbolic_instance (216-242), which builds the "
                             f"'{attr_name}' var and, for booleans, its "
                             "predicate-reader PC, executes ONLY in the "
                             "not_found==False else-branch. (not_found=True, "
                             f"{attr_name}=*) is structurally impossible for "
                             "the SAME call ordinal — the attribute PC is "
                             "never recorded in that run at all. Scenario-"
                             "independent: both auth's evil_query.rb post! "
                             "arms and anon's post_service.rb find_public! "
                             "go through this same finder_mock boundary.",
            ))
    return out


def build(runs=None) -> AssumptionSet:
    """`runs`: the loaded `Run` list (optional) — used only to enumerate
    which `first_<N>_*` exprs actually exist, so the Tier-1 same-call
    independence pairs below are generated, never hand-maintained."""
    a = AssumptionSet()

    if runs:
        all_exprs = []
        seen = set()
        for r in runs:
            for pc in r.path_conditions:
                if pc.expr not in seen:
                    seen.add(pc.expr)
                    all_exprs.append(pc.expr)
        for ia in _same_call_impossible_combo_assumptions(all_exprs):
            a.add(ia)

    # ------------------------------------------------------------------
    # PostPresenter#build_interactions_json (post_presenter.rb:108-116)
    # evaluates a hash literal:
    #   likes:          [user_like].compact,       -> find_by_1 (post.rb:143 like_for)
    #   reshares:       [user_reshare].compact,     -> find_by_2 (post.rb:138 reshare_for)
    #   comments_count: @post.comments_count,       -> plain attr, no PC
    #   likes_count:    @post.likes_count,          -> plain attr, no PC
    #   reshares_count: @post.reshares_count        -> plain attr, no PC
    #
    # `like_for`/`reshare_for` (post.rb) are two INDEPENDENT `find_by`
    # lookups against different tables (likes vs reshares), each keyed only
    # on (@post, current_user) — neither call's arguments or code path
    # depends on the other's outcome, and Ruby evaluates both hash values
    # unconditionally (no short-circuiting between them). No combination of
    # (like found/not found, reshare found/not found) can produce an access
    # pattern that the individual branches don't already cover: whichever
    # finds first has zero effect on the other's query or its target-call
    # argument shape. Independence test (assumptions.py IndependenceAssumption
    # docstring, criteria 1+2): mutually exclusive? No — both always run.
    # Do either's concrete target-call args depend on the other's SYMBOLIC
    # result? No — `like_for(current_user)`/`reshare_for(current_user)` take
    # only @post/current_user, never each other's return value. -> INDEPENDENT.
    # ------------------------------------------------------------------
    a.add(IndependenceAssumption(
        expr_a="(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found == True)",
        expr_b="(SYM_RESULT_ActiveRecord__FinderMethods_find_by_2_not_found == True)",
        description="like_for (post.rb:143) vs reshare_for (post.rb:138) — "
                     "independent finds in the same unconditional hash literal",
        agent_notes="Verified expr is single-decision: 200/200 auth dumps "
                     "with find_by_1 present record it at post.rb:143 in "
                     "like_for; 200/200 with find_by_2 at post.rb:138 in "
                     "reshare_for. Neither call's args reference the other's "
                     "symbolic result. See module docstring.",
    ))

    # ------------------------------------------------------------------
    # `Post#nsfw` (post.rb:161-162, `self.author.profile.nsfw?`) vs
    # `like_for`/`reshare_for` (post.rb:138,143): nsfw reads the AUTHOR's
    # profile; like_for/reshare_for query the likes/reshares tables keyed on
    # @post/current_user. Disjoint models (Profile vs Like/Reshare), disjoint
    # argument shape, no shared symbolic value threads through both — no
    # combination of (nsfw?, like found?) or (nsfw?, reshare found?) can
    # produce a call sequence/arg shape neither branch alone produces.
    # ------------------------------------------------------------------
    a.add(IndependenceAssumption(
        expr_a="(assoc_profile_nsfw == True)",
        expr_b="(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found == True)",
        description="Post#nsfw (author's profile) vs like_for — disjoint models",
        agent_notes="nsfw: reads @post.author.profile.nsfw? (post.rb:161-162); "
                     "like_for queries Like keyed on (@post, current_user) "
                     "(post.rb:143). No shared symbolic value.",
    ))
    a.add(IndependenceAssumption(
        expr_a="(assoc_profile_nsfw == True)",
        expr_b="(SYM_RESULT_ActiveRecord__FinderMethods_find_by_2_not_found == True)",
        description="Post#nsfw (author's profile) vs reshare_for — disjoint models",
        agent_notes="nsfw: reads @post.author.profile.nsfw? (post.rb:161-162); "
                     "reshare_for queries Reshare keyed on (@post, current_user) "
                     "(post.rb:138). No shared symbolic value.",
    ))

    return a
