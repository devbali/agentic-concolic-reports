# results2/posts_show — rerun with symbolic entrypoint arguments

(Report authored by the batch agent; saved by the coordinating session.)

## Acceptance tests — PASSED (quoted from dumps)

- `dump_anon0001.json`: `"posts"."id" = $$(SYM_PARAM_id)`
- `dump_auth0001.json`: `SELECT posts.* FROM "posts" INNER JOIN "share_visibilities" ON "share_visibilities"."shareable_id" = "posts"."id" AND "share_visibilities"."shareable_type" = 'Post' WHERE "posts"."id" = $$(SYM_PARAM_id) AND "share_visibilities"."user_id" = $$(SYM_USER_PO_id)`
- `dump_anon0043.json`: `"posts"."guid" = $$(SYM_PARAM_id)` — guid-lookup sibling, reached via the new `Length(SYM_PARAM_id)` flip.

## New genuine branch from the symbolic param

`PostService#post_key` (`id_or_guid.to_s.length < 16 ? :id : :guid`):
`.to_s` on SymbolicString is identity, so `.length` yields SymbolicInt
`Length(SYM_PARAM_id)` and the compare records a PC (absent in the source
batch, where a concrete Integer recorded nothing). `flip_length_seed`
(ported from comments_index) inverts it by reseeding with a string of the
needed length.

## Symbolic user — pins removed, results

| attribute | source batch | this rerun |
|---|---|---|
| `user.id` | pinned 1 | symbolic — flows into `share_visibilities.user_id` in 200/200 auth dumps, no wall |
| `person.id` | pinned 1 | symbolic — flows into `participations.author_id` etc. (`$$(SYM_PERSON_PO_id)`), no wall |
| `guid` | pinned "abc123" | symbolic; genuinely unreached on posts#show (verified in service/presenter sources) |
| `person_id` | pinned 1 | symbolic; unreached — its only caller (`mark_user_notifications`) is mocked in the SHARED concolic_targets.rb (pre-existing wall mock §X1, closed before this rerun; not editable from a batch) |

No AR integer-cast wall materialized — posts_show is read-only; the one
write-path `to_i` wall was already mocked upstream.

## Association scoping

All five user associations rescoped from `Klass.all` to real FKs with
symbolic ids (`Aspect/Contact/Block.where(user_id: user.id)`,
`Photo/Participation.where(author_id: person.id)`). Only `participations`
fires on posts#show — confirmed scoped and symbolic.

## Known upstream quirk (present, not fixed)

`dump_anon0002.json`: `"posts"."guid" = $$(SYM_RESULT_ActiveRecord__FinderMethods_first_1_id)` —
the documented per-run call-ordinal var-naming bug in
`src/ruby_runtime/call_interceptor.rb`, triggered by the presenter's
re-invocations of `find!` (Like/ReshareService). Left as-is per briefing.

## Coverage

```json
{"endpoint": "posts_show", "coverage_complete": true, "tree_nodes": 51,
 "missing_branches": 0, "total_runs": 252, "total_path_conditions": 2794,
 "genuine": true, "vacuous": false,
 "dump_errors": {"Diaspora::NonPublic": 18, "ActiveRecord::RecordNotFound": 54},
 "solver_lost": 0, "assumptions": [], "assumptions_used": 0}
```

252 dumps (200 auth + 52 anon distinct paths). **Worklist honestly did NOT
drain** — both scenarios hit MAX_RUNS=300 (auth stack_remaining=1790, anon
13; `worklist_exhausted: false` in exploration_summary.json) — but the
checker's strict per-node semantics independently reports 0 missing branches
over the 51 discovered nodes: branch-coverage-complete, not
path-set-complete (main README distinction). `unflippable_pcs: {}` in both
scenarios. No assumptions were needed to reach complete.

## Errors

All real app outcomes: 54 RecordNotFound (404 path), 18 Diaspora::NonPublic
(private-post path), raised from both the top-level lookup and the
presenter's re-invocation chain. Zero NotImplementedError / framework walls
across 252 dumps.

---

## ADDENDUM (2026-08-18): combination-coverage final state — HONEST INCOMPLETE

Supersedes the coverage sections above. Final (verified by coordinator):
`coverage_complete: false, truncated: true, solver_lost: 0,
unevaluable_exprs: [], tree_nodes: 28, total_runs: 4278,
missing_branches: 3072 (cap-sampled; true count larger), assumptions_used: 18`.

What was achieved:
- Hollow-universe bug fixed (SYM_PARAM_id registered inside the run window;
  verified declared in dumps) and the corpus fully regenerated: 4,278 dumps
  (auth capped at 4,226 distinct paths, stack_remaining=29,453; anon
  DRAINED at 52), 54,946 PCs, zero unparseable, zero framework walls; all
  806 dump errors are genuine app outcomes (788 RecordNotFound, 18
  NonPublic, including deeper presenter re-query failure paths).
- 18 sound assumptions: 15 programmatic same-ordinal impossibility pairs
  (finder_mock builds attribute vars only on the not_found=False branch)
  + 3 presenter field-builder independences (disjoint tables/models).

Why completion is out of reach without deeper changes — the per-run ordinal
instability is structural here: EvilQuery#post! makes up to 3 finder
attempts and is invoked up to 3× per request (action + LikeService +
ReshareService re-queries), so `first_N` denotes DIFFERENT real decisions
depending on scenario and prior outcomes (empirically: first_1 =
evil_query.rb:104 in all auth dumps but post_service.rb:52 in all anon
dumps). Guard-truncation independence therefore cannot be soundly keyed on
any fixed expr, the graph stays near-complete (28 nodes minus 18 scattered
edges → 1,536 maximal cliques of ~27), and the demand space stays
combinatorially large. Force-closing it would require unsound assumptions;
declined per instructions.

Paths to genuine completion (coordinator's assessment):
1. Batch-local expr stabilization — dedicated named targets per call SITE
   (the conversations_index precedent, extended: per-relation wrappers for
   EvilQuery's three attempts and per-service invocation naming), then
   regenerate; guard tiers become declarable and cliques collapse.
2. Engine-level fix of the documented per-run-ordinal naming
   (call_interceptor.rb) — resolves this class everywhere but renames every
   expression; a src/ decision for Bali.

---

## ADDENDUM 2 (2026-08-18): CALL-SITE-STABLE restart — GENUINELY COMPLETE

Supersedes the honest-incomplete addendum above. Verified by the
coordinating session (fresh checker run + independent dump sampling):

`coverage_complete: true, truncated: false, solver_lost: 0,
unevaluable_exprs: [], missing_branches: 0 (proven at cap 256),
tree_nodes: 30, total_runs: 4278, assumptions_used: 371,
checker_elapsed: ~19s.`

- **Naming layer** (targets.rb, PostsShowFinderNaming): thread-local
  context (act/like/reshare) + per-attempt relation tagging gives 12
  dedicated finder targets (evilq_<ctx>_<attempt>, findpublic_<ctx>).
  1:1 identity proven: 25,866 events, every ordinal `_1`, SQL
  fingerprints 0 mismatches corpus-wide. The ordinal-instability blocker
  is gone.
- **Exploration reached a true fixpoint**: auth 26,114 runs → 4,226
  distinct paths, worklist DRAINED (previously capped with 29k pending);
  anon drained. All 806 dump errors are genuine app 404/NonPublic
  outcomes; zero framework walls.
- **470 declared / 371 used assumptions** in tiered families (scenario
  exclusivity, found-vs-attribute impossibility, public-gates-attributes,
  ||-short-circuit attempt chains, cross-context foreclosure, presenter
  independence), each with code citations and the safety-test argument.
  With the drained worklists, every REACHABLE combination was executed;
  assumptions account only for the provably-unobservable remainder.
- Old ordinal-era corpus remains archived in `_archive_ordinal_era/`.
