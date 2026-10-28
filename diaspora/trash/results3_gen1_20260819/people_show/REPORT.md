# results3/people_show — discipline-clean rebuild (2026-08-18)

(Agent-authored; saved and re-verified by coordinator.)

## Verdict (fresh checker run reproduces)
`coverage_complete: true, truncated: false, solver_lost: 0, missing: 0,
tree_nodes: 15, total_runs: 26 (both scenarios DRAINED), PCs: 182,
assumptions_used: 78, unevaluable: []`. dump_errors: 4×
ActionView::MissingTemplate — the genuine 404/closed-account rescue
rendering public/404 absent from the sandbox (same class as people_stream;
app tree untouched).

## Discipline deltas
Phase A patches 1-4 applied; render family removed (real profile page
renders); **Person#name DESCENDED** (first endpoint to take the audited
violation): name_from_attrs runs for real. New walls closed at leaves:
first_name/last_name String#split shims, PersonPresenter#description
.scrub, Sprockets asset-tag shadowing, a missing eager_files registration
(caught by absence-of-event), a stale profile prepend that bypassed
Patch 1, and a batch pluck override recovering the tags query.
mark_user_notifications + as_api_response VERIFIED unreached here.

## Win condition — families results2 never reached (verified in dumps)
`SELECT "photos".* FROM "photos" WHERE "photos"."author_id" =
$$(SYM_PERSON_via_user_id) AND public = true AND pending = false ...`
and the tags join `... "taggings"."taggable_id" = $$(assoc_profile_id) ...
AND (1=0)` (the 1=0 guard flagged for a future look), plus
profiles-by-person. 4 recovered query families vs results2's 3 shapes.

## Structural finding
people#show's template is largely a JS-shell — its stream/photos widgets
load via separate routes; the reference's 30 queries likely span the whole
profile experience across routes, not #show alone. Remaining gap:
signed-in-only queries (anonymous-only mission) + the (1=0) tags guard.
