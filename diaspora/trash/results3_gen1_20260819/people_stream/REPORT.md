# results3/people_stream — discipline-clean rebuild (2026-08-18)

(Agent-authored; saved and verified by coordinator.)

## Verdict (fresh checker run reproduces)
`coverage_complete: true, truncated: false, solver_lost: 0, missing: 0,
tree_nodes: 20, total_runs: 237, PCs: 1938, assumptions_used: 172,
unevaluable: []`. All three scenario worklists DRAINED (true fixpoints).
dump_errors: 6× ActionView::MissingTemplate — the GENUINE 404-rescue branch
rendering public/404, which the sandbox fixture lacks (environment gap, app
tree off-limits; PCs recorded).

## Discipline deltas
Removed: render family + default_render (real stream page renders).
Descended: Post.blocked_people, Stream::Base#post_ids,
attach_user_likes — the results2-documented swallowed viewer-likes query is
RECOVERED: `SELECT "likes".* WHERE "likes"."author_id" =
$$(SYM_PERSON_PS_id) AND "likes"."target_id" = $$(...) AND target_type =
'Post'` — present in 192/237 dumps (coordinator-verified) + a second likes
query from build_interactions_json. Person#posts rescoped to real FK
(genuine bind in anon_json); Person#blocks scoped but dead here (verified).
Kept/deferred violation: as_api_response (5 PostPresenter call sites) —
the biggest named residual, same deferral class as notifications.
New leaf shims: redirect performed?-marking (exposed by the default_render
removal), IterableSymbolicList#reverse/#inject, SymbolicList
as_api_response 0-length shim, CollectionProxy port (per patch table).

## Corpus / universe
anon_all 39→11 (drained), anon_json 128→29 (drained), auth_json 968→197
(drained). 20 exprs = the 12-var find_person family (unchanged from
results2) + 8 stream-body vars opened by the descents (scenario-exclusive
groups verified empirically). 172 cited assumptions.

## Distance to reference (168)
13 distinct query-shaped calls (results2: 5): 10 clean bind-carrying
shapes + 2 kwargs-gap-degraded class finders + 1 note-degraded reshare.
Residual accounted: representative sampling (by design), the deferred
as_api_response descent, the kwargs gap. Bare-truthiness gap noted:
has_hidden_shareables_of_type? records no PC (documented class).
