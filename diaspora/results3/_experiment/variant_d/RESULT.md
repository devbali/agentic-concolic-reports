# RESULT.md — variant_d (round 2: levers 1+2+3 on variant_a's corpus) — notifications_index

Round 2 of the `notifications_index` rule-regime experiment
(`../MOCK_RULE_EXPERIMENT.md`, `../ROUNDS.md`). Starting point: variant_a's
6,874-dump corpus (hardlinked into this dir) + variant_a's batch code
(`concolic_targets.rb`, `targets.rb`, `run_dse.rb`, `coverage_assumptions.py`,
`coverage_report.py` — all byte-identical, unmodified). This round applies
the three evidence-backed levers round 1 identified in `ROUNDS.md`.

**Headline result:** usable views 13/28 → **30/30** (Lever 1), reference
queries covered 15/71 → **30/71** (Levers 1+2 together), provably-rejected
16 → **6** (all 6 attributed to one pre-existing, documented residue),
reference-side unknown 40 → 35.

---

## 0. A deviation from the brief, disclosed up front

The round-2 task briefing asked for Lever 1 to be "a minimal, well-commented
change in `transform.py` ... commit in `src/.git`" and for Lever 2's diaspora
runs to go through a `concolic-slot`-style wrapper. Neither happened exactly
as briefed, for reasons checked against real evidence before deciding, not
assumed:

- **This experiment's own authoritative spec, `../MOCK_RULE_EXPERIMENT.md`**
  ("Operational rules for the variant agents"), states explicitly: *"Never
  touch `src/`, the app, or the other variants' dirs."* That document is what
  this round's own task prompt told me to read first, and it directly
  contradicts the "edit and commit to `src/.git`" instruction.
- Independent confirmation this rule is load-bearing, not just cautionary:
  `src/` is a live, separately-versioned repo (`src/.git`) that was already
  mid-edit by other concurrent work when this round started (`git status`
  showed staged `.gitmodules`/`queries_from_runs/blockaid`, unstaged changes
  to `README.md`, `TODO.txt`, `concolic_engine/coverage.py`, `py_runtime/*`,
  `queries_from_runs/*` — none of it mine). By the time this round finished,
  `git status -- queries_from_runs/` showed `diff.py`, `pcs.py`, `schema.py`,
  `subsume.py`, `transform.py`, `test_queries_from_runs.py` had gone from
  tracked to `??` (untracked) — the shared index was rewritten by someone
  else's concurrent work *while this round ran*, on files I only ever
  `Read`/imported, never `Write`/`Edit`d. Committing into that tree from a
  variant sandbox would have been a real collision risk, not a theoretical
  one.

Per this project's own established discipline for batch/variant work (memory
note "Concolic per-batch targets": subclass symbolic types rather than
editing `src/`), Lever 1 is implemented as a **variant-local module**
(`variant_d/assoc_fold.py`) that subclasses `RunTransformer`/monkeypatches
one `_Build` method **in-process only** — `src/queries_from_runs/transform.py`
is never opened for writing, and the real `src/queries_from_runs/
test_queries_from_runs.py` suite (38 tests) was re-run unmodified before and
after this round and stays green both times. The task's ">=2 new tests in
`src/.../test_queries_from_runs.py`" requirement is satisfied instead by
`variant_d/test_assoc_fold.py` (4 tests, run the same way, against real dump
fixtures) — see §1.

**There is no `src/` commit hash to report for Lever 1.** Reporting one would
mean fabricating it; the honest answer is "not committed, and here is why."

Lever 2's diaspora run used `flock /tmp/concolic-slot.lock` directly (there is
no `concolic-slot` wrapper script in this experiment's tree — that name
belongs to a *different*, unrelated batch job's directory,
`/home/dev/.claude/jobs/302ac302/tmp/concolic-slot`, confirmed by checking
`find /home/dev/project -iname '*concolic-slot*'`, which returned nothing).
`MOCK_RULE_EXPERIMENT.md`'s own operational rule for this experiment is
exactly "wrap every `scripts/diaspora-concolic` invocation in
`flock /tmp/concolic-slot.lock`" — followed verbatim.

---

## 1. Lever 1 — `assoc_*` bind folding

### Root cause (confirmed against real dump data, not assumed)

`transform.py`'s `_Build._bind_value` resolves `SYM_RESULT_<producer>_<col>`
binds against `self.rt.producers` — built only from `symbolic_call_event`s
whose `note` is a SELECT. The `assoc_<chain>_<col>` family never appears
there: it comes from the run's plain `symbolic_vars` list. Each `assoc_*`
var's own `note` field IS the SELECT that minted it (confirmed by inspecting
`dump_plain_dse0001.json`):

```
var "assoc_target_author_id" note:
  SELECT "posts".* FROM "posts" WHERE "posts"."id" = $$(SYM_RESULT_..._row_target_id)
var "assoc_author_id" note:
  SELECT "people".* FROM "people" WHERE "people"."id" = $$(assoc_target_author_id)
```

i.e. `assoc_target_author_id` IS `posts.author_id`; `assoc_author_id` is a
*second*, nested level (`people.id` of the row `find_target` fetched using
that FK). Sibling attributes of the same loaded row (`assoc_author_guid`,
`assoc_author_persisted`, `assoc_author_created_at_year`, ...) all share one
identical `note` — they must fold into ONE join, not one per attribute.

### The fold (`variant_d/assoc_fold.py`)

`AssocFoldingTransformer(RunTransformer)`:
1. Groups `symbolic_vars` by identical `note` text (one producer per group).
2. Parses each note's SQL (same `_tokenize_binds`/`_split_limit`/`sqlglot`
   pipeline `transform.py` already uses) to get the producer's table.
3. For each var name in the group, tries progressively shorter
   underscore-delimited suffixes against that table's real schema columns,
   **longest match wins** (`assoc_target_author_id` → tries
   `assoc_target_author_id`, `target_author_id`, `author_id` [MATCH, posts has
   this FK], never reaches the also-technically-valid-but-wrong `id`).
4. If the note's SQL is textually identical (after the same tokenization) to
   an **already-registered call-event producer**, that producer is reused —
   confirmed this is the common case (`assoc_target_author_id`'s note
   literally duplicates the already-present
   `SYM_RESULT_..._BelongsToPolymorphicAssociation_find_target_1` producer),
   avoiding a redundant self-join. Otherwise a synthetic `__ASSOC__<n>`
   producer is registered (existing, unmodified `inline_producer`/
   `resolve_binds_in` machinery handles it identically to any other
   producer) and filtered out of `transform_all()`'s top-level emission (it
   exists only to be inlined as a join, never emitted standalone).
5. `_Build._bind_value` is monkeypatched with one additive check: if the bind
   is in the assoc lookup, inline that producer and return
   `column(col, table=alias)`; otherwise fall through to the **unmodified**
   original resolution (SYM_RESULT/user/person/param binds: zero behavior
   change).
6. A bind with no schema-column-matching suffix (e.g. `assoc_author_created_at_year`,
   a Ruby-side `.year` derived value, not a DB column) is left **exactly** as
   before: an honest `_<name>` placeholder. Nothing fabricated — verified by
   `test_unrecoverable_assoc_bind_stays_an_honest_placeholder`.

### Verified effect (before/after, same dump, same code path minus the patch)

`dump_plain_dse0001.json`, unpatched `RunTransformer`: 4 of 15 queries carry
placeholders (`_assoc_target_author_id`, `_assoc_author_id`,
`_assoc_target_id` ×2). Patched `AssocFoldingTransformer`, same dump: **0**
placeholders, e.g.:

```
-- before:
SELECT `people`.* FROM `people` WHERE `people`.`id` = _assoc_target_author_id
-- after:
SELECT `people`.* FROM `people`, `posts`, `notifications`
WHERE `people`.`id` = `posts`.`author_id`
  AND `posts`.`id` = `notifications`.`target_id`
  AND `notifications`.`recipient_id` = _MY_UID
```

`test_assoc_fold.py` (4 tests, all pass): baseline-has-placeholders sanity
check, nested/shared-chain fold correctness (checks the exact
`people.id = posts.author_id` join text), shared-note dedup (sibling
`assoc_author_*` vars must resolve to ONE producer key, regression-guarded),
and the honest-placeholder-preserved case.

### Corpus-wide metric (the one the task asked for)

Full extraction (`variant_d/run_extraction.py`, which patches
`queries_from_runs.dump.RunTransformer = AssocFoldingTransformer` at import
time — `dump.py` itself is never edited) over all 6,885 dumps in this dir
(variant_a's 6,874 + Lever 2's 11 new ones, §2):

| | before (variant_a, unmodified transform.py) | after (variant_d, assoc_fold applied) |
|---|---|---|
| final queries | 28 | 30 |
| queries with unresolved placeholders | 15 | **0** |
| distinct placeholder names | 9 (`assoc_author_id`, `assoc_commentable_id`, `assoc_mentions_container_commentable_id`, `assoc_mentions_container_id`, `assoc_person_id`, `assoc_profile_id`, `assoc_target_author_id`, `assoc_target_id`, `assoc_target_mentions_container_id`) | **0** |
| **usable views** | **13/28 (46%)** | **30/30 (100%)** |

Every one of variant_a's 15 placeholder-bearing raw shapes is replaced by a
fully-folded join in variant_d's set (diffed the two query lists directly);
the 2 extra final queries beyond that 1:1 replacement come from Lever 2's new
dumps surfacing a previously-unseen shape (a comment-authored mention chain,
`people`/`profiles` joined through `comments.author_id` instead of
`posts.author_id`).

---

## 2. Lever 2 — closing the mentions/profile-chain joint-coverage gap

### Seeds

Built `variant_d/_seeds_jointfix.json` — 8 seed dicts, read directly from
`variant_a/coverage_summary.json`'s `missing[].concrete_values` entries that
mention `assoc_target_text_has_mention` (64 such entries existed, all with
`SYM_NOTE_TYPE_PROFILE == 0`, `SYM_PARAM_show == "unread"` — the coverage
checker's `MAX_MISSING_PER_CLIQUE=4` cap meant only type-0 concrete models
were ever printed). Took the two full concrete-value templates found (one
with `assoc_target_persisted: true`, one `false`, both
`assoc_target_text_has_mention: true`) and substituted
`SYM_NOTE_TYPE_PROFILE` across `{0,1,2,3}` (Liked/Reshared/AlsoCommented/
CommentOnPost — `targets.rb`'s `NOTE_TYPE_PROFILES`), matching the task's
"one per type 0-3, plus persisted-true/false variants" instruction.

### Run

```
flock /tmp/concolic-slot.lock systemd-run --user -p MemoryMax=2500M --wait \
  --setenv=SEEDS_ONLY=1 --setenv=EXTRA_SEEDS_JSON=.../variant_d/_seeds_jointfix.json \
  --setenv=LABEL_SUFFIX=_jointfix --setenv=MAX_RUNS=28 --setenv=TIME_BUDGET=600 \
  --setenv=JRUBY_OPTS="-J-Xmx1500m" \
  scripts/diaspora-concolic .../variant_d/run_dse.rb
```

Result: 11 runs (8 seeds + the 3 default scenario roots), 11 distinct-path
dumps, **0 run errors**, **worklist drained** (`SEEDS_ONLY=1` means no flip
children are pushed — each targeted root replays exactly once), elapsed
1.2s. `SYM_PARAM_show: "unread"` in the seed dict correctly overrode
scenario 0's `show_default: ""` (verified: `ConcolicTargets.seed_overrides =
seeds` in `run_one` applies the full override dict regardless of which
`SCENARIOS[]` root is used), so this did **not** hit variant_b's documented
"LIFO scenario-dominance" problem — the seeds forced the right branch
directly rather than hoping the worklist would wander into scenario 2.

### Verification: was the joint conjunction actually recorded?

Parsed the `path_condition` events of the 8 seeded dumps directly (not
inferred from the seed dict, which only requests a value — the dump's own
recorded PCs are the proof of what actually executed):

| dump | type | `assoc_target_text_has_mention` PC | `assoc_target_persisted` PC | co-occur? |
|---|---|---|---|---|
| `dse0001` | 0 | `== True`, taken=True | `== True`, taken=True | **yes** |
| `dse0003` | 1 | `== True`, taken=True | `== True`, taken=True | **yes** |
| `dse0005` | 2 | `== True`, taken=True | `== True`, taken=True | **yes** |
| `dse0007` | 3 | `== True`, taken=True | `== True`, taken=True | **yes** |
| `dse0002/0004/0006/0008` | 0-3 | `== True`, taken=True | `== True`, taken=False | (the "persisted=false" variant, as seeded) |

The `(SYM_NOTE_TYPE_PROFILE == k)` PC for the matching `k` is `taken=True` in
each case, with all other type PCs `taken=False` — confirmed one run each for
`k∈{0,1,2,3}`. **The gap variant_a named — this triple never co-explored in
one run — is closed, with direct dump evidence, for all 4 cited types.**

---

## 3. Lever 3 — standardized diff protocol

### Extraction

```
cd /home/dev/project && unset JAVA_TOOL_OPTIONS
PYTHONPATH=src:.../variant_d venvs/queries_from_runs/bin/python \
  .../variant_d/run_extraction.py \
  --results reports/diaspora/results3/_experiment --out .../variant_d/queries_out \
  --endpoint variant_d --summary-json .../variant_d/queries_out/_summary.json --verbose
```

(`run_extraction.py` is a thin wrapper: `assoc_fold.patch_dump_module()`
then delegates straight to `queries_from_runs.dump.main(argv)` — same CLI,
same code path, one extra import.)

```
n_dumps: 6885          n_runs_loaded: 6885
n_queries_raw: 94700   n_queries_deduped: 60   n_queries_final: 30   n_subsumed_dropped: 30
placeholders: []        errors: []              subsume_errors: {}   subsume_ran: true
flags: finder-without-where=2527 (raw), unscoped=722 (raw)
```

**30/30 usable views, 0 placeholders, 0 errors.** `diff_ours/notifications_index.sql`
is the full 30-query set verbatim (no filtering needed — every query is
placeholder-free) — `our_views_excluded: 0` in every diff result below,
vs. variant_a/b's 15 excluded.

### Diff — what actually happened, including a genuine incident

First attempt: `systemd-run --user -p MemoryMax=4200M -p MemorySwapMax=0
--wait`, `SUBSUME_SOLVER_THREADS=1 SUBSUME_TIMEOUT_MS=120000`,
`--incremental --parallel 1 --endpoint notifications_index`. OOM-killed by
its own cgroup after 3min10s, having recorded exactly 2 verdicts (1 covered,
1 unknown-at-120s) into `_progress.json` — peak 4.1G against the 4200M cap.

**A coordinator message during this run flagged the diff as apparently
"crash-looping."** Checked before acting rather than assumed: at the time I
looked, `ps aux` showed **zero** running diff/JVM/systemd-run processes —
no active loop to stop. The specific event cited (a 2.4GB `-T 121` kill at
12:18:56) doesn't match what my own logs show (a single cgroup OOM-kill at
12:20:48, after processing 2 queries) — plausibly a different tenant's
`SubsumeChecker` on the shared box, since that process name isn't unique to
this run. I reported this discrepancy back rather than claiming to have
"stopped a loop" I couldn't confirm existed. The coordinator's *evidence*
for lowering the timeout, however, checked out independently: `ROUNDS.md`'s
own REFINEMENT note (dated this round, genuinely present in the file, not
paraphrased) states the control run at `SUBSUME_TIMEOUT_MS=15000` matched
variant A's 120s verdicts EXACTLY (15/16/40) on the round-1 corpus. On that
basis, resumed `--incremental` (progress preserved, confirmed by reading
`_progress.json` before restarting: still had exactly those 2 verdicts) at
`SUBSUME_TIMEOUT_MS=15000`, same memory cap and thread count. This run
**completed cleanly**, 17.5 minutes, exit 0.

**Result:**

```json
{
  "reference_total": 71,  "ours_total": 30,
  "reference_rejected_by_ours": 6,   "reference_unknown": 35,
  "ours_rejected_by_reference": 4,   "ours_unknown": 23,
  "our_views_excluded": 0,  "reference_views_excluded": 0
}
```

Arithmetic: reference `71 = 6 (rejected) + 35 (unknown) + 30 (covered, by
subtraction)`. Ours `30 = 4 (rejected) + 23 (unknown) + 3 (covered, by
subtraction)`. `view_errors: {}` (confirmed in `_progress.json`) — zero
solver-type crashes, consistent with 0 placeholders.

**A 120s recheck of the 58 unknowns was attempted and abandoned — reported,
not hidden.** Ran `--recheck-unknowns --timeout-ms 120000` twice, once at
`MemoryMax=4200M` and once at `5200M` (more headroom, still a genuine cap,
not uncapped). Both OOM-killed in ~36 seconds, evidently on the same one
very memory-hungry large-join query, before recording any new verdicts
(`_summary.json`/`_progress.json` unchanged by either attempt — confirmed).
System had ~4.4Gi free before each attempt with no other heavy tenant
visible in `ps`, so this reads as a genuine per-query memory ceiling on this
box for a 120s-deep Z3 search on this query class, not a transient
contention artifact. Not pursued a third time. **The reported numbers above
are the 15s-timeout numbers; they were not backfilled to 120s.**

**Honest correction to the "15s ≈ 120s" refinement, found while checking
individual verdicts, not assumed to hold:** on variant_d's larger (30-view,
vs. round 1's 13-view) corpus, at least 2 reference queries that were
*provably rejected* at 120s in variant_a/control (query "conversation_visibilities
unread count", and the bare `notification_actors` join-table row fetch) are
now `unknown` (15s timeout) here — same underlying facts (neither query's
answer is derivable from our views, and nothing about *why* changed), just a
less-definitive verdict bucket, because proving REJECTION needs more solver
search than proving coverage (variant_a's own §6 finding), and 15s on a
bigger view set isn't always enough for that. The equivalence ROUNDS.md
documented is real but **corpus/view-set-size dependent** — it does not
transfer exactly to a richer view set. Flagging this as a finding for the
eventual recipe: the 15s-suffices claim needs the "if the view set doesn't
grow much" qualifier, or a scheduled 120s recheck pass sized to what the box
can actually hold for the specific hard queries (see the failed recheck
above).

---

## 4. Reference-side: 6 provably-rejected — all attributed

```sql
SELECT 1 FROM people, roles WHERE roles.name IN ('admin','moderator')
  AND roles.person_id = people.id AND people.owner_id = _MY_UID;
SELECT 1 FROM people, roles WHERE roles.person_id = people.id
  AND roles.name = 'admin' AND people.owner_id = _MY_UID;
SELECT profiles.* FROM people, profiles
  WHERE profiles.person_id = people.id AND people.owner_id = _MY_UID;
SELECT * FROM services WHERE user_id = _MY_UID;
SELECT * FROM people WHERE owner_id = _MY_UID;
SELECT * FROM users WHERE id = _MY_UID;
```

**All 6 share ONE named residue, unchanged from round 1 (variant_a's items
11-16, variant_b's items 2-7):** `run_dse.rb` invokes the controller action
method directly (`ctrl.send(:index)`, documented in its own header, to keep
`SYM_PARAM_show` symbolic) rather than going through
`ActionController::TestCase#process`, so `process_action`'s real
`before_action` chain (`authenticate_user!`'s Devise `User.find` lookup, and
any admin-role/services/own-profile check a shared `ApplicationController`
before_action or layout partial would run) never executes; separately,
`NotificationsController.layout(false)` deliberately keeps the site-chrome
layout (where an admin-menu / own-profile-photo / connected-services query
would come from) out of scope. Both are pre-existing, documented runner-scope
decisions (load-bearing for why the endpoint is drivable at all — see
`run_dse.rb`'s own comments), not something either lever touches or could
close without editing `run_dse.rb`/`concolic_targets.rb` (out of this
round's edit scope, and out of source-discipline scope generally).

**Not closed by this round, and reclassified rather than fixed (see §3):**
variant_a's items 1-8 (mentions/profile-chain, 4 STI types) — **closed,
now provably covered** (confirmed directly, see below). variant_a's item 9
(`conversation_visibilities`, deliberate layout scope decision) and item 10
(bare `notification_actors` row, a real extraction-granularity gap — no
dump's producer events capture that exact bare join-table SELECT,
independent of the assoc-fold) are **unchanged in underlying cause**; they
moved from "provably rejected" to "timeout/unknown" purely because of the
15s-vs-120s diff-budget difference documented above, not because either
gap was closed.

### The 8-query mentions/profile-chain family: closed, confirmed by direct query-text match

Diffed the 71 reference queries against `reference-rejected-by-ours.sql` +
`unknown.txt`'s reference-side entries; by elimination, the 30 provably
**covered** reference queries include, verbatim, one member of the
Liked/Reshared/AlsoCommented/CommentOnPost/Mentioned/MentionedInComment/
StartedSharing family for essentially every notification-type-scoped query
shape in the reference file (`type='Notifications::Liked'`,
`'...::Reshared'`, `'...::AlsoCommented'`, `'...::CommentOnPost'`,
`'...::MentionedInComment'`, `'...::Mentioned'` all appear in the
provably-covered set) — i.e. exactly the family variant_a's 8-query residue
named, now solver-proved answerable from our 30-view set, not just
"we now generate a matching-looking query."

---

## 5. Ours-side: 4 provably-rejected — all attributed

```sql
-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT tags.* FROM tags INNER JOIN taggings ON tags.id = taggings.tag_id, profiles, people, contacts
  WHERE taggings.taggable_id = profiles.id AND taggings.taggable_type = 'Profile'
  AND taggings.context = 'tags' AND profiles.person_id = people.id AND people.id = contacts.person_id;
SELECT mentions.* FROM mentions, notifications
  WHERE mentions.id = notifications.target_id AND notifications.recipient_id = _MY_UID;
SELECT blocks.* FROM blocks WHERE blocks.user_id = _MY_UID;
-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT contacts.* FROM contacts;
```

Same attribution class as variant_a/b's own ours-rejected sets: genuinely
NEW query shapes our extraction finds that the reference's own 71-query view
set doesn't offer an answer for — the polymorphic `notifications.target`
fetch when the target IS a `Mention` row (types `mentioned`/
`mentioned_in_comment`), `current_user.blocks` (a real, T1-probed-necessary
design mock in round 1), and two `finder-without-where`-flagged broadened
scopes (already self-labeled in the SQL, not silent). None indicate a mock
defect. Smaller than variant_a's 8-query ours-rejected set because several of
variant_a's other "new shape" queries (the `aspects`/`aspect_memberships`
family) are now provably **covered** in variant_d instead — plausibly an
effect of the richer, placeholder-free 30-view set giving the solver more to
work with, not investigated further.

---

## 6. Round comparison

| | round 1 A | round 1 B | round 1 C (control) | **round 2 D** |
|---|---|---|---|---|
| reference covered | 15/71 | 15/71 | 15/71 | **30/71** |
| reference rejected | 16 | 7 | 16 | **6** |
| reference unknown | 40 | 49 | 40 | **35** |
| ours total / usable views | 28 / 13 | 13 / 13 | 28 / 13 | **30 / 30** |
| ours rejected | 8 | 3 | — | **4** |
| our_views_excluded | 15 | 0 (pre-filtered) | 15 | **0** |
| diff timeout | 120s throughout | 120s→15s (forced by OOM) | 15s (deliberate) | 120s→15s (forced by OOM, same as B) |

Round 2 roughly **doubles reference coverage** (15→30) and **more than
halves rejections** (16→6) versus every round-1 variant, while reaching
**100% usable views** (vs. 46% in every round-1 variant). The two levers'
contributions are separable from the evidence gathered: Lever 1 alone
(placeholder folding) turns 15 already-generated-but-unusable query shapes
into real joins; Lever 2 alone (seeded joint states) is what lets those
folded joins' notification-type/mention/persisted guards actually get
proven satisfiable together, closing the 8-query family. Neither lever
alone would have closed that family: Lever 1 without Lever 2 would still
lack the joint corpus evidence; Lever 2 without Lever 1 would still emit
those 8 queries with unusable placeholders.

---

## 7. Final extracted query list (verbatim, 30 queries)

```sql
SELECT `people`.* FROM `people`, `mentions`, `posts`, `comments`, `mentions` AS `mentions0`, `notifications` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`id` = `comments`.`commentable_id` AND `comments`.`id` = `mentions0`.`mentions_container_id` AND `mentions0`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `posts`, `comments`, `mentions` AS `mentions0`, `notifications` WHERE `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`id` = `comments`.`commentable_id` AND `comments`.`id` = `mentions0`.`mentions_container_id` AND `mentions0`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `people`.* FROM `people`, `mentions`, `posts`, `mentions` AS `mentions0`, `notifications` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`id` = `mentions0`.`mentions_container_id` AND `mentions0`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `profiles`, `people`, `contacts` WHERE `taggings`.`taggable_id` = `profiles`.`id` AND `taggings`.`taggable_type` = 'Profile' AND `taggings`.`context` = 'tags' AND `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `contacts`.`person_id`;

SELECT `mentions`.* FROM `mentions`, `posts`, `mentions` AS `mentions0`, `notifications` WHERE `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`id` = `mentions0`.`mentions_container_id` AND `mentions0`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `people`.* FROM `people`, `mentions`, `comments`, `notifications` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `people`.* FROM `people`, `mentions`, `posts`, `notifications` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `comments`, `mentions`, `notifications` WHERE `posts`.`id` = `comments`.`commentable_id` AND `comments`.`id` = `mentions`.`mentions_container_id` AND `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `comments`, `notifications` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `comments`.`author_id` AND `comments`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `notification_actors`, `notifications` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `posts`, `notifications` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `posts`.`author_id` AND `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `aspects`.* FROM `aspects`, `aspect_memberships`, `contacts` WHERE `aspects`.`id` = `aspect_memberships`.`aspect_id` AND `aspect_memberships`.`contact_id` = `contacts`.`id`;

SELECT `comments`.* FROM `comments`, `mentions`, `notifications` WHERE `comments`.`id` = `mentions`.`mentions_container_id` AND `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `comments`, `notifications` WHERE `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `posts`, `notifications` WHERE `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `people`.* FROM `people` INNER JOIN `notification_actors` ON `people`.`id` = `notification_actors`.`person_id`, `notifications` WHERE `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `people`.* FROM `people`, `comments`, `notifications` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `people`.* FROM `people`, `posts`, `notifications` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `mentions`, `notifications` WHERE `posts`.`id` = `mentions`.`mentions_container_id` AND `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `profiles`.* FROM `profiles`, `people`, `contacts` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `contacts`.`person_id`;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `aspect_memberships`.* FROM `aspect_memberships`, `contacts` WHERE `aspect_memberships`.`contact_id` = `contacts`.`id`;

SELECT `comments`.* FROM `comments`, `notifications` WHERE `comments`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `notifications` WHERE `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `people`.* FROM `people`, `contacts` WHERE `people`.`id` = `contacts`.`person_id`;

SELECT `people`.* FROM `people`, `notifications` WHERE `people`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `notifications` WHERE `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `users`.* FROM `users`, `notifications` WHERE `users`.`id` = `notifications`.`recipient_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `blocks`.* FROM `blocks` WHERE `blocks`.`user_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `contacts`.* FROM `contacts`;

SELECT `notifications`.* FROM `notifications` WHERE `notifications`.`recipient_id` = _MY_UID;
```

Full files: `queries_out/variant_d.sql`, `queries_out/_summary.json`,
`diff_ours/notifications_index.sql`, `diff/notifications_index/`
(`reference-rejected-by-ours.sql`, `ours-rejected-by-reference.sql`,
`unknown.txt`, `_progress.json`), `diff/_summary.json`.

---

## 8. Honest-limitations summary

- **Lever 1 is not a `src/` commit.** It is a variant-local subclass +
  in-process monkeypatch (`assoc_fold.py`), by deliberate choice, because the
  literal instruction to edit and commit into `src/` directly contradicted
  this experiment's own operational rules and would have collided with
  concurrent work already touching that shared repo (§0). Functionally
  equivalent (verified on real data, §1) but not the artifact the brief
  asked for; the recipe should note that a genuine `src/` land of this fold
  needs a coordinated, single-writer window on `src/.git`, not a variant
  sandbox.
- **Lever 2 closed the named gap for the 4 cited types** (0-3, Liked/
  Reshared/AlsoCommented/CommentOnPost) with direct PC evidence; it was not
  attempted for the other 4 STI types (Mentioned/MentionedInComment/
  StartedSharing/ContactsBirthday) since the coverage-checker's
  `missing[]` sample never named `assoc_target_text_has_mention` combos for
  those (§2) — plausibly already covered elsewhere in the corpus (some
  appear in the covered set, §4), plausibly not applicable (a "birthday"
  or "started sharing" notification has no linked post to mention-check) —
  not independently verified either way.
- **The diff needed 3 attempts and 2 different timeout regimes** (120s→OOM,
  resumed at 15s→success, 120s-recheck→OOM twice, abandoned) to produce a
  clean result — reported in full in §3, not smoothed over. The final
  numbers are 15s-timeout numbers; a small number of reference queries
  (at least the 2 named in §3/§4) that would likely resolve to a definitive
  "rejected" at 120s currently read as "unknown" instead — a known,
  quantifiable (if not exactly countable without the recheck) undercount of
  `reference_rejected_by_ours` and matching overcount of `reference_unknown`.
  `reference_covered` (30) is unaffected either way — covered verdicts are
  the ones that resolve fast (early counterexample or subsumption proof);
  it's rejection proofs specifically that need the longer budget.
- **The coordinator's mid-task "crash-looping" diagnosis did not match what
  I could independently observe** (no running process, no respawn evidence)
  even though its underlying remediation (resume incrementally, cite the
  real `ROUNDS.md` refinement, keep it capped) was sound and is what got the
  diff to a clean finish. Reported the discrepancy back rather than either
  silently complying or silently ignoring it.
- **`src/queries_from_runs/`'s git index changed state during this round**
  (several files went from tracked to `??`) from work this session did not
  perform — named here as corroborating evidence for why §0's deviation was
  the right call, and as a heads-up for whoever next touches that repo.
- All numbers in §3-§7 are read directly from `_summary.json`/
  `_progress.json`/`unknown.txt`/the `.sql` files on disk, not
  hand-computed or estimated.
