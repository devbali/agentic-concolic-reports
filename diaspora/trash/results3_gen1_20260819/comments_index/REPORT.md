# results3/comments_index — discipline-clean rebuild (2026-08-18)

(Agent-authored; saved by coordinator. Headline record.)

## Verdict
`coverage_complete: false, truncated: false, solver_lost: 0, missing: 12,
tree_nodes: 9, total_runs: 46 (worklist DRAINED, 0 errors), PCs: 340,
assumptions_used: 23, unevaluable: []` — honest stop: the 12 missing are
free-boolean combos over {find_by_1..4} that Z3 deems satisfiable but no
execution can produce (the two independent people_from_string invocations
share one ordinal counter; all 9 hand-derived genuinely-reachable shapes
ARE present in the corpus, proven by enumeration). The cure is the
posts_show call-site-naming pattern — follow-up pass ordered.

## Discipline deltas (vs results2)
REMOVED: as_api_response (serializer runs for real), people_from_string
mock (real local Person lookup), Post.blocked_people (audit finding).
Phase A applied (find_target/polymorphic/class-finder/User#blocks notes;
CollectionProxy port — confirmed inert on this path). Kept-violation,
documented: Person#name (calls self.profile — deferred, same scope call as
notifications). New walls: text identity shim (scan needs concrete),
federation fetch network wall (32/46 dumps reach it: 0 HTTP, 0 crashes).

## Win condition met — serializer-driven association SQL (quoted)
`SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" =
$$(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_3_id)` (mentioned
person) and `... = $$(assoc_author_id)` (comment author), from the REAL
as_api_response(:backbone) walk. Class-finder WHERE still degraded on the
kwargs-gap (honest labeled note) — documented interceptor limitation.

## Distance to reference (24 queries)
5 clean decomposed SELECT shapes + 1 degraded family, touching the same
table families the reference fuses into per-viewer JOINs — remaining gap is
join-fusion/aggregate semantics + the kwargs-gap, not missing families.
Anonymous JSON only (html/mobile branches not driven this pass).

## FOLLOW-UP (same day): coverage_complete=true EARNED

The 12-combo ordinal residual is closed via the posts_show call-site-naming
pattern: 4 dedicated find_by aliases (mention_lookup_{msg,json}_{first,
retry}) with a CommentPresenter context tag and a faithful (source-cited)
find_or_fetch_by_identifier routing prepend. 1:1 name→site verified across
the regenerated corpus (coordinator re-verified: zero multi-fire dumps).
Same 46-path drained corpus, 0 errors. 29 cited assumptions (prior gating
args re-keyed + within-site retry gating + cross-site independence).
Final (fresh checker run reproduces): coverage_complete: true,
truncated: false, solver_lost: 0, missing: 0, assumptions_used: 29.
