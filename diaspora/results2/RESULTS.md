# results2 — final per-entrypoint results (2026-08-18)

All six reference endpoints, rerun with fully symbolic entrypoint arguments
and completed under **combination-coverage semantics** (every Z3-satisfiable
combination of branch outcomes observed in a single run's executed path,
relaxed only by explicitly argued assumptions). Every row was independently
verified by a fresh checker run before being recorded here.

| entrypoint | dumps (distinct paths) | runs executed | worklist drained | universe (PC exprs) | total PCs | complete | assumption arguments → pairs used⁰ | non-SQL wall mocks (batch-local)¹ | naming/scoping shims¹ | dump errors (all genuine app outcomes) | unevaluable exprs |
|---|---|---|---|---|---|---|---|---|---|---|---|
| comments_index | 6 | 15 | yes | 3 | 16 | ✅ | 1 → 1 | ≈5 | 0 | none | 0 |
| conversations_index | 96 | ~3,545² | yes² | 8 | 556 | ✅ | ~3 → 7 | ≈3 | 1 naming + 2 scoping | none | 0 |
| notifications_index | 6 | 9³ | yes³ | 1 | 6 | ✅ | 0 → 0 | ≈2 | 1 rescope | none | 0 |
| people_show | 10 | 28 | yes | 9 | 50 | ✅ | 6 → 29 | ≈6 | 0 | none | 0 |
| people_stream | 27 | 87 | yes (×3 scenarios) | 12 | 84 | ✅ | 5 → 66 | ≈9 | 0 | none | 0 |
| posts_show | 4,278 | 26,427 | yes (auth 26,114 → 4,226 paths; anon 313 → 52) | 30 | 54,946 | ✅ | ~8 → 371 | ≈6 | 12 naming targets + 4 naming prepends ⁴ | 788 RecordNotFound, 18 NonPublic | 0 |

⁰ Assumptions are declared as PAIRWISE dependence-edge removals, so one
*argument* (a single piece of code-cited reasoning, e.g. "every run is
auth-or-anon, so auth-only and anon-only exprs never co-occur") fans out
programmatically across a family cross-product of pairs. "Arguments" counts
the distinct pieces of reasoning in `coverage_assumptions.py`; "pairs used"
is the engine's `assumptions_used` (edges actually removed from the
observed universe). posts_show's 30-expr graph has C(30,2)=435 edges: 371
removed by ~8 arguments, 64 kept — the kept edges (dispatch × outcomes,
attempt-selection chains) are where the real combination demands live.

¹ **Crash-free runtime accounting.** Two layers make the runs crash-free:

- **Shared framework layer** (each dir's private `concolic_targets.rb`,
  identical for all six, incl. the collect_binds bind-ordering fix):
  **64 mock declarations — ~54 of them non-SQL wall closures** (render /
  render_to_string no-ops, `escape_segment`, `people_from_string`,
  `as_api_response`, `Photo#url`, `gon`, Sidekiq push stubs, Stream::Base
  leaves incl. `post_ids`/`attach_user_likes`, `Post.blocked_people`,
  presenter leaves, `User#retract/mine?/confirm_email/add_to_streams`,
  `StatusMessage#tag_name_max_length`, …) and 10 the SQL query-boundary
  family (finders / relation rows / calculations / `find_by_sql`).
- **Batch-local wall mocks** (per-endpoint `targets.rb`, the column above,
  classified by purpose): list-iteration mocks (`IterableSymbolicList`
  rows on Relation/CollectionProxy), truthiness-boundary decisions
  (`diaspora_id?`), string-op identity shims (`SymUsernameString` /
  `SymEntrypointString` for `downcase`/`blank?`), association readers on
  symbolic instances (`PersonSymAssociations`, `UserSymPersonAssociation`,
  polymorphic belongs_to), and sampled-value walls (`pluck` strings,
  `SuccIntValue`-class helpers). Naming aliases (posts_show's 12
  call-site targets + 4 context prepends, conversations'
  `convidx_conv_lookup`) and association *rescoping* shims are counted
  separately — they exist for expression identity / query scoping, not
  crash avoidance. Counts marked ≈ because a few shims serve dual
  purposes (e.g. `ConvoSymAssociations` both scopes and prevents
  association-reader crashes).

The end state: **zero `NotImplementedError`/framework crash walls remain
in any final corpus** — every dump `error` across all ~30k runs is a
genuine app outcome (404 / NonPublic), never a runtime crash.

² conversations_index explored across three runner invocations (1,500 +
2,000 + 45 runs; the runner overwrites `exploration_summary.json`, see its
`completion_pass_2026_08_18` block). Its json-format variants were
regenerated after the ordinal-collision fix (`convidx_conv_lookup`
dedicated target).

³ notifications_index: 9 runs → 6 distinct paths, worklist drained (its
exploration summary uses a different field layout; values from its final
report). Its single PC expression is genuinely the endpoint's only
symbolic branch — the Haml-partial branch behind the shared render mock is
a documented framework-wide limitation, not an endpoint gap.

⁴ posts_show's 13 targets include the 12 **call-site naming aliases**
(`evilq_{act,like,reshare}_{vis,author,public}`, `findpublic_{act,like,reshare}`)
that eliminated the per-run ordinal instability — 25,866 finder events,
every ordinal `_1`, SQL fingerprints matched 1:1 corpus-wide. The old
ordinal-era corpus is archived in `posts_show/_archive_ordinal_era/`.

## Assumption totals

**~23 distinct arguments → 474 pairwise removals in force** across the six
endpoints (1→1, ~3→7, 0→0, 6→29, 5→66, ~8→371), every pair expr-keyed,
argued with file:line citations (and, where applicable, execution probes or
corpus-wide empirical checks) in each endpoint's `coverage_assumptions.py`,
and audited against the goal that no exempted combination can hide a
distinct SQL-issuing call. The dominant
patterns: guard-truncation (a raise forecloses the inner check),
if/else–arm exclusivity, `||` short-circuit attempt chains, cross-context
foreclosure, and provably-unreachable sides (framework short-circuits,
NullRelation) — plus scenario exclusivity for posts_show's auth/anon split.

## src/-level findings produced by this effort

1. **Registered-vars trap (FIXED in src/, both runtimes)**: values built
   before `interceptor.run` were wiped from the dump's declarations;
   named scalars now self-register when they record a PC.
2. **Bind-rotation root cause (fixed in the per-dir concolic_targets.rb
   copies)**: JRuby ivar ordering on Arel SelectStatement swapped WHERE
   binds into LIMIT/OFFSET slots on paginated queries.
3. **Per-run ordinal naming** (`SYM_RESULT_<func>_<idx>`): names are
   positions, not identities — neutralized batch-locally via call-site
   naming (posts_show, conversations_index); an engine-level fix remains
   open for Bali.
4. **Truthiness auto-wrap**: a mock cannot return `false` (re-wrapped
   truthy); the `true`/`nil` boundary pattern steers correctly
   (people_stream's dispatch fix).

Downstream: `queries_from_runs/` (generated per-endpoint SQL + the
blockaid diff vs the reference policies) is produced from these corpora —
see `queries_from_runs/_summary.json` and `queries_from_runs/diff/`.
