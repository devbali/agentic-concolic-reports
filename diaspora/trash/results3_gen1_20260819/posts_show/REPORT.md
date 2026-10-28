# results3/posts_show — discipline-clean rebuild (2026-08-18)

(Build agent's work, killed by the 12:19 OOM one minute after its final
assumptions edit; corpus deterministically regenerated and verified, REPORT
saved by coordinator. Sixth and final results3 endpoint, the largest.)

## Verdict — honest stop

`coverage_complete: false, truncated: true, solver_lost: 0,
unevaluable_exprs: [], tree_nodes: 89, missing (cap-4 sample): 500,
total_runs: 18,688, PCs: 675,716, assumptions_used: 2,045, 0 unparseable
dumps, dump_errors: {Diaspora::NonPublic: 180, ActiveRecord::RecordNotFound:
210}` — both error families are genuine app outcomes (anon viewing a
non-public post; unresolvable id/guid), not walls.

The residual demand space is a SINGLE giant clique crossing the JSON/HTML
serializer-recursion families — `as_api_response_N_row_{guid,text_has_
mention}` × `mention_lookup_{msg,json}_{first,retry}_N` × `find_by_N_{not_
found,text_has_mention}` × CollectionProxy/records `SYM_LEN` gates ×
`assoc_{root_guid,root_text_has_mention,status_message_text_has_mention,
profile_nsfw}` — every sampled missing combo is a 14–18-conjunct demand.
This is the same combinatorial wall results2/posts_show reported as its
honest stop ("well over the ~30-combo bar for targeted closure"), now on a
3× larger universe (89 exprs vs results2's 30). No amount of single-flip
DSE closes a demand space of that shape; forcing `complete` would be false.

Two honest-by-choice contributors, both pre-declared in
`coverage_assumptions.py`'s docstring (written 12:16–12:18, the agent's
last act — the rewrite is finished and coherent, verified):
- `mention_lookup_*_N` ordinals are per-run *within-context* counters
  (presenter recursion opens a third axis the naming layers don't pin), so
  a same-N first/retry pairing would be UNSOUND to assume — those exprs
  demand full combination coverage among themselves.
- results2's 3 hand-picked find_by_N presenter mappings were dropped
  (their premise broke: the STI type-dispatch fix re-ordered find_by
  ordinals — find_by_1 is now the poll_participation lookup, verified from
  dump notes). find_by_N × find_by_M pairs are left fully connected —
  conservative, not unsound.

## Corpus (regenerated 2026-08-18 evening, deterministic)

One `run_dse.rb` invocation, 4 scenarios, `MAX_RUNS=8000`
`TIME_BUDGET=1800` per scenario, 1116.5s total, JVM capped `-J-Xmx1000m`:

| scenario  | runs | distinct paths | stop                                   |
|-----------|------|----------------|----------------------------------------|
| auth_html | 8000 | 5302           | MAX_RUNS cap + STACK_LIMIT truncation  |
| anon_html | 8000 | 4696           | MAX_RUNS cap + STACK_LIMIT truncation  |
| auth_json | 8000 | 4846           | MAX_RUNS cap + STACK_LIMIT truncation  |
| anon_json | 8000 | 3844           | MAX_RUNS cap + STACK_LIMIT truncation  |

Provenance: the overnight corpus died at 12:19:02 when the kernel OOM
killer (triggered by a 3.3GB corpus-wide python load running beside the
DSE JVM on this swapless 7.8GB box) took down the coordinator mid-
`anon_json`; per-scenario summaries were never written. The rerun
reproduced the three completed scenarios' path counts EXACTLY
(5302/4696/4846 — prefix-directed DSE is deterministic) and completed
`anon_json` (3844 vs 2801 at kill time). The killed run's dumps are
preserved in `../../trash/posts_show_oomkilled_run_20260818/`.
`exploration_summary.json` carries all four per-scenario summaries.

Checker memory fix (coordinator, this dir's `coverage_report.py`):
`share_run_objects` flyweight — events/vars are frozen dataclasses shared
across runs — loads all 18,688 dumps + checks in 1.75GB peak RSS, 7 min.

## Discipline deltas (vs results2 — full ledger in concolic_targets.rb header)

REMOVED (real bodies now execute): render family (Z + Y2 — the post page
renders for real; mission item 1), `PostService#mark_user_notifications`
(X1 — the audit-confirmed 4-query cover-up; `IterableSymbolicList#concat`
added for `mark_mention_notifications_read`), `Diaspora::Mentionable.
people_from_string` (X6f — real local Person lookup; text identity shim;
federation discovery network wall — network never fires),
`build_mentioned_people_json` (X6k), `Post.blocked_people` (verified DEAD
on this endpoint's call graph — removed for discipline consistency).
Phase A note-fidelity patches 1/2/3 applied. NEW naming layer:
`PostsShowMentionLookupNaming` (two independent call sites into the same
Person lookup), alongside the ported-intact `PostsShowFinderNaming`.

KEPT-violations, documented: `as_api_response` (X3) deferred — 7 receivers
across 6 models, out of proportion, same call as people_show/people_stream;
`Person#name` (X6i) — same scope call as every sibling.

## Win condition met — mark_user_notifications queries recovered (quoted)

From the corpus, with symbolic binds:
- `SELECT "notifications".* FROM "notifications" WHERE "notifications".
  "recipient_id" = $$(SYM_USER_PO_id) AND "notifications"."target_type" =
  'Post' AND "notifications"."target_id" = $$(SYM_RESULT_ActiveRecord__
  Relation_evilq_act_vis_1_id)`
- `SELECT "mentions".* FROM "mentions" WHERE "mentions"."mentions_
  container_id" = $$(SYM_RESULT_ActiveRecord__Relation_evilq_act_vis_1_id)
  AND "mentions"."mentions_container_type" = 'Post' AND "mentions".
  "person_id" = $$(...)`
- `SELECT "mentions".* FROM "mentions" INNER JOIN comments ON mentions.
  mentions_container_id = comments.id AND mentions.mentions_container_type
  = 'Comment' WHERE "comments"."commentable_id" = $$(...)` (the joined
  mentions-in-comments query)
- `... "notifications"."target_type" = 'Mention' AND "notifications".
  "target_id" = $$(SYM_RESULT_ActiveRecord__Calculations_...)` (the
  pluck-fed Mention notifications query)

## Assumption tiers (2,045 applied, generated programmatically over all_exprs)

Tier 0 scenario×format 4-way exclusivity (auth/anon × html/json — like/
reshare CONTEXTS are html-only, posts_controller.rb:24-30); Tier 1
same-(name, ordinal)-target found-vs-attribute; Tier 1b public-gates-attrs;
Tier 2 attempt chains; Tier 3 cross-context; Tier 5 post-found-vs-act;
Tier 6 len-gates-row-attr. Arguments restated per tier in
coverage_assumptions.py against the new 89-expr universe.
