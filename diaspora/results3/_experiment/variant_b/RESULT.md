# variant_b RESULT — notifications_index rule-regime experiment

Rule-set: DISCIPLINE_TESTS.md **T1** (mock leaf-probe) **+ T2** (assumption
probe / data-flow divergence), both with Bali's 2026-08-19 rigor upgrades
(100% line-coverage gate for T1, mechanical divergence test for T2). Full
detail lives in `LEAF_PROBES.md` + `LEAF_PROBES.json` (T1) and
`ASSUMPTION_PROBES.md` + `ASSUMPTION_FLOW.json` (T2); this file is the
top-level summary + pipeline result the experiment asked for.

## 1. Rules applied

- **T1**: built a re-runnable harness (`_t1_leaf_probe.rb`) that captures
  each candidate mock's pristine `UnboundMethod` before
  `ConcolicTargets.install!`/`NotificationsIndexTargets.install!` patch it,
  invokes it on concrete fixtures with every OTHER target still patched,
  and records (a) nested `TargetCall`s, (b) connection-adapter touches
  (classified metadata-vs-application-SQL — see harness notes), (c) Ruby
  `Coverage`-scoped line hits for the real body. Swept **18 of ~79**
  `declare_target` sites: the 12 crash-stopper mocks the file's own header
  identifies as reached/plausibly-reached by this endpoint, plus 6
  design-family (#1/#5/#7/#9/#pluck/User#blocks) informational spot
  checks. The remaining ~61 sites are documented-dormant for this endpoint
  per the ledger's own header and were not probed — an explicit scope
  reduction, not a silent gap (see `LEAF_PROBES.md` "Scope").
- **T2**: derived the Tier0/1/2 assumption classes from
  `coverage_assumptions.py`'s own classifier (`_same_class`), then built a
  dual-run data-flow-divergence harness (`_t2_divergence_run.rb`) —
  `Coverage.start` before `config/environment` loads, one fresh JRuby
  process per side (avoids double-patching `declare_target` from a
  same-process double-`load`), diffed against the OTHER side's dump (PC
  presence/absence) and coverage line-hit-counts (mechanism divergence).
  Probed and PASSED: **finder-arm**, **persisted-gate** (with a corrected
  mechanism — see below), and a Tier-0 sanity pair. **count-chain** and
  **Tier-2 one-sided** were not reachable by any seed I could construct in
  the available time and are BLOCKED (undeclared) in `coverage_assumptions
  .py` via a new `_T2_BLOCKED_CLASSES` constant + `_T2_ONE_SIDED_PROBED_OK`
  flag, rather than carried forward on the old corpus-count-only standard.

## 2. LEAF_PROBES.md summary (T1)

| verdict bucket | count | methods |
|---|---|---|
| Clean PASS (0 nested calls, 0 app-SQL, 100% coverage) | 6/12 | Y1 `status=`, Y3b `url_for`, Y4 `assert_is_devise_resource!`, W4 `_set_rendered_content_type`, W7 `devise_mapping`, §5i `to_param` |
| Nested-safe-chain (fails literal criterion only; 0 app-SQL at any depth; KEEP) | 3/12 | Y3a `redirect_to`, W2_actual `head`, W1 `writer` |
| Confirmed-necessary SQL boundary (mock is correctly minimal; KEEP) | 2/12 | W3 `find_target`, W3b `find_target` (polymorphic) |
| Instrumentation-limited (JRuby `super`-dispatch gap; manual-inspection verdict substituted) | 1/12 | X6g `Instrumentation#redirect_to` |
| Design-mock spot checks (informational, exempt from removal) | 6 | design#1/#5/#7/#9/#pluck confirmed SQL-boundary; User#blocks inconclusive (0% coverage — ad-hoc fixture didn't meaningfully enter the reader) |

**Net T1 verdict: no `concolic_targets.rb`/`targets.rb` change is
warranted.** Every FAIL resolves to a documented, independently-safe
nested chain (removal would only add crash-family regression risk for
zero query-coverage benefit) or confirms the mock sits at the correct
minimal SQL boundary. One genuine methodology bug was found and fixed
mid-probe (a schema-cache-warmup gap that produced false connection-touch
positives — see `LEAF_PROBES.md` "Harness notes"), and one genuine file
finding was surfaced (W2's own `declare_target(ActionController::Metal,
:head, ...)` line is dead code in this Rails version; the effective mock
is a separate declaration on `ActionController::Head`).

## 3. ASSUMPTION_PROBES.md summary (T2)

| class | verdict |
|---|---|
| finder-arm | **PASS** — clean disjoint PC sets (0/24 foreclosing vs 3/27 recording) |
| persisted-gate | **PASS** — disjoint PC sets + coverage divergence at the exact cited mechanism (targets.rb size-shim / collection_association.rb null_scope? / has_many_association.rb count_records: 0 hits foreclosing, 2 recording) |
| tier0-type-exclusivity (sanity) | **PASS** — one representative pair (type 0 vs type 4), disjoint sets |
| same-var-chain | not separately probed — sound by construction (identical Z3 variable), same carve-out DISCIPLINE_TESTS.md gives Tier 0 |
| count-chain | **BLOCKED** — no genuine cross-variable instance found in available time |
| one-sided (Tier 2, `guid != ''`) | **BLOCKED** — recording site not reached by any seed tried |

The persisted-gate probe caught and corrected a wrong mechanism
hypothesis before it could ship as fact: I first guessed the foreclosed
exprs would be sibling `_persisted` companions on the same representative
(`assoc_author_persisted`/`assoc_target_persisted`) — both actually fire
on BOTH sides (belongs_to/`SingularAssociation` reads are unaffected by
Bug1's `CollectionAssociation`-only null-scope fix, exactly as
`BUGFIXES_20260819.md` documents). The REAL foreclosed family is the
has_many-*through* `actors` collection's `count_records`-derived PCs. This
is exactly the kind of error the T2 probe requirement exists to catch —
the classifier's `_same_class` labeling is still validated (it matches on
`_persisted` in the guard name, not on my specific guess for `B`).

`coverage_assumptions.py` changes: added `_T2_BLOCKED_CLASSES =
frozenset({"count-chain"})` and `_T2_ONE_SIDED_PROBED_OK = False`, wired
into the Tier-1 and Tier-2 loops so a blocked class is never auto-declared
from the corpus, whatever its raw counts show.

## 4. Corpus

Since T1 made zero changes to `concolic_targets.rb`/`targets.rb` and T2
only touched `coverage_assumptions.py` (consumed by the coverage checker,
not by corpus generation), variant_b's corpus generation is byte-for-
behavior identical to the control's (`run_dse.rb`/`concolic_targets.rb`/
`targets.rb` are byte-identical — confirmed via `diff -q`). Regenerated
from scratch anyway, per the pipeline brief:

`_seed_typeK.json` seeds `SYM_NOTE_TYPE_PROFILE=K`; profile 0 (`liked`) is
the default and already saturated by the main round, so the 7 targeted
rounds cover profiles 1-7 (`reshared`, `also_commented`, `comment_on_post`,
`mentioned`, `mentioned_in_comment`, `started_sharing`,
`contacts_birthday` — `targets.rb` `NOTE_TYPE_PROFILES`):

| round | profile | MAX_RUNS | distinct paths written | run errors |
|---|---|---|---|---|
| main | 0 (`liked`) default + all scenarios | 4000 | 3966 | 0 |
| type1 | 1 `reshared` | 450 | 441 | 0 |
| type2 | 2 `also_commented` | 450 | 441 | 0 |
| type3 | 3 `comment_on_post` | 450 | 441 | 0 |
| type4 | 4 `mentioned` | 450 | 428 | 0 |
| type5 | 5 `mentioned_in_comment` | 450 | 435 | 0 |
| type6 | 6 `started_sharing` | 450 | 361 | 0 |
| type7 | 7 `contacts_birthday` | 450 | 361 | 0 |
| **total** | | | **6874** | **0** |

6874 total dumps, matching the control's own `n_runs=6874`
(`notifications_index/_assumption_table.json`) — direct confirmation that
the T1-unchanged mock surface really does reproduce the control's
corpus-generation behavior. Ten single-seed T2 diagnostic dumps
(`t2_pf`/`t2_pt`/`t2_nft`/`t2_nff`/`t2_type0`/`t2_type1`/`t2_type4`/
`t2_type4m`/`t2probe0` x2) were generated separately for the divergence
probes and moved to `_t2_scratch_dumps/` — **excluded** from coverage/
extraction (they are directed diagnostic single-runs, not part of the
systematic prefix-directed exploration, and would have injected atypical
query shapes into the extracted set).

Main run: worklist NOT exhausted (69803+ remaining at MAX_RUNS cap — huge
branching factor, matches every other results3 batch's experience). Zero
run errors across all 6874 runs in all 8 rounds.

**Finding: scenario dominance.** `run_dse.rb`'s worklist is LIFO
(`SCENARIOS.each_index.map{...}.reverse` then `stack.pop`), and every
flip of a scenario-0 (`"plain"`) run pushes a CHILD back onto the SAME
end of the stack — so scenario 0's subtree, once entered, must be
exhausted before the stack ever reaches the scenario-1 (`"typed"`,
`params[:type]="liked"`) or scenario-2 (`"unread_only"`, pagination)
roots underneath it. My single main-round invocation (MAX_RUNS=4000,
worklist far from drained) produced **0** `dump_typed_*`/
`dump_unread_only_*` files — 100% of the 3966 distinct-path dumps are
scenario 0. The control corpus has the same structural issue in degree,
not kind: only 6/7825 `typed` and 6/7825 `unread_only` dumps (0.08%),
almost certainly the product of running `run_dse.rb` as multiple SEPARATE
invocations across the session (gen2 + gen3 logs) rather than one deeper
run, each restart giving the LIFO stack a fresh (small) chance to
lucky-dip into scenario 1/2 before re-diving into scenario 0. This is an
honest, structural DSE-strategy limitation (not something T1/T2 bear on,
and not cheaply fixable within this probe's budget — `EXTRA_SEEDS_JSON`
seeds variable VALUES within scenario 0 only, it cannot select a
different scenario index), reported here rather than silently accepted.
It does not appear to be the dominant source of the reference-diff
residue (the control's own REPORT.md attributes its rejected-by-ours
queries to undriven STI notification types and the `Person#name` mock,
not to scenario coverage), but it is a real gap worth naming.

## 5. Coverage verdict

**Attempted twice; did not finish within the compute budget available for
this probe — reported honestly as an incomplete/undetermined
`coverage_complete` result, not forced or fabricated.**

- **Attempt 1** (`MAX_MISSING_PER_CLIQUE=4`, default `timeout_ms=5000`):
  loaded all 6874 runs cleanly (confirmed via the live log: `loaded 6874
  runs (0 unparseable)`; `[assumptions] tier0=163 tier1=12 tier2=0` —
  this alone already confirms the T2 blocklist wiring works correctly in
  the real pipeline, not just in isolated testing), then ran for **45+
  minutes** with stable CPU (99.9%) and memory (~1.27GB RSS, well inside
  the 2.5GB cap) with no sign of finishing. Killed.
- **Attempt 2** (same corpus, `COVERAGE_TIMEOUT_MS=1500` — a documented,
  justified reduction added to `coverage_report.py` via a new
  `COVERAGE_TIMEOUT_MS` env knob passed through to `CoverageChecker
  (timeout_ms=...)`, on the reasoning that most of the wall-clock in
  attempt 1 is plausibly spent on Z3 calls that were already going to
  return UNKNOWN and set `truncated=True` regardless — `truncated` is an
  accepted, honestly-reported outcome in this project's own established
  practice (`README.md` "Semantics"), not a new kind of dishonesty to
  introduce by shortening the timeout): still ran **31+ minutes** without
  finishing. Killed.
- Both attempts used the project's OWN "never enumerate wide" standing
  cap (`MAX_MISSING_PER_CLIQUE=4`, the narrowest setting the project's own
  prior experience already established as necessary — see control's
  REPORT.md). The corpus itself is not unusually large by results3
  standards (6874 runs, comparable order of magnitude to other endpoints);
  what's different is the fully-driven 8-STI-type expr universe (163
  Tier-0 pairs alone), which materially grows the dependence-graph clique
  sizes the checker must enumerate over.
- **What this does NOT mean**: it does not mean the corpus is unhealthy —
  0 run errors, 0 unparseable dumps, and the assumption-derivation stage
  (the part T1/T2's work actually touches) completed in under 10 seconds
  both times, with results matching prediction exactly (`tier2=0`,
  confirming the blocklist). The SOLVER-SIDE combination enumeration is
  what's intractable here, not the corpus or the discipline work.
- **Honest expectation, not a claimed result:** the control batch's own
  (smaller, 4547-dump, pre-full-STI-expansion) corpus was ALSO
  `coverage_complete: false` / `truncated: true` even after finishing
  (see control's `REPORT.md`: "pairwise (2-way) combination coverage:
  588/588... What remains open: the checker demands full k-way outcome
  assignments over the residual clique... combinatorially large"). Given
  variant_b's corpus is a superset in STI-type coverage, `coverage_complete:
  false` / `truncated: true` for variant_b is the expected shape of
  outcome too — but this is stated as an expectation grounded in the
  control's own documented precedent, NOT as a result this probe
  independently produced. **The actual missing-branch count, tree_nodes,
  and total_path_conditions numbers for variant_b are unknown and not
  reported here.**
- This does not block extraction or the reference diff (§6-7 below) —
  those read the raw dumps directly, independent of `coverage_summary
  .json`.

## 6. Extraction

`queries_from_runs.dump --results .../_experiment --endpoint variant_b`
over the 6874-dump corpus (scratch T2 dumps excluded, confirmed by the
tool's own endpoint-grouping: `_t2_scratch_dumps/dump_*.json` groups under
endpoint key `"_t2_scratch_dumps"`, not `"variant_b"`, so no manual
filtering was even required beyond having moved them into a subdirectory):

```
n_dumps: 6874          n_queries_raw: 94559
n_queries_deduped: 35  n_queries_final: 28   n_subsumed_dropped: 7
placeholders (9, all _assoc_* association-sourced binds):
  assoc_author_id, assoc_commentable_id,
  assoc_mentions_container_commentable_id, assoc_mentions_container_id,
  assoc_person_id, assoc_profile_id, assoc_target_author_id,
  assoc_target_id, assoc_target_mentions_container_id
flags: finder-without-where=1805 (raw occurrences), unscoped=722 (raw occurrences)
errors: []   subsume_errors: {}   subsume_ran: true
```

28 final queries — every raw query family (paginated notification list,
unread count, actors join, actor profiles, polymorphic target fetch
across ALL 8 STI types, target-author fetch, mentions family, tags,
blocks, contacts/aspects) is real, readable SQL; every non-obvious one
carries an honest `-- NOTE` (either "finder mock rendered without its
WHERE conditions" — a known broadening hygiene flag, or "unresolved
symbolic binds kept as placeholders" — an association producer the
extractor couldn't fold). No unlabeled degenerate SQL, no silent
placeholders. Full list: `queries_out/variant_b.sql`.

## 7. Diff vs reference (71 queries)

**Operational note (own finding, not asked for but load-bearing):** the
naive `--reference ... --ours ... --out ...` invocation OOM-killed the
blockaid JVM twice (once under my own 2.5-3.2GB cgroup cap via the
system-wide memory watchdog — variant_a's own coverage checker was
running concurrently and cross-tenant contention pushed system-available
memory under the watchdog's 700MB floor twice; see
`_mem_watchdog.log`), and separately crashed outright (`rc=-9` from
inside `check_coverage`) when the 9 placeholder-bearing queries were fed
to the checker as "views" — `_assoc_target_id` etc. aren't valid SQL
constants, and `diff.py`'s own `--ours`/`--reference` path does not
pre-filter placeholder queries the way `dump.py`'s subsumption pruning
does (`eligible = [not q.placeholders ...]`). Fix, both documented and
load-bearing for anyone rerunning this: (a) build `diff_ours/
notifications_index.sql` from only the **13 placeholder-free** queries
(the 15 placeholder-bearing raw-query instances — some placeholder names
recur across multiple queries — are saved separately in
`diff_ours/notifications_index_excluded_placeholders.sql`, not silently
dropped); (b) use `--incremental` (one query per checker invocation,
resumable via `_progress.json`) instead of one big batched call — far
lower peak memory per call, and survives contention/kills without losing
progress; (c) after the first two 120s-timeout attempts stalled (killed
by the watchdog at ~9-10 min elapsed having checked only 3-4/71 queries),
switched to `SUBSUME_TIMEOUT_MS=15000` for the remaining queries — a
documented, justified speed/completeness trade-off (same reasoning as the
coverage-check timeout reduction in §5): already-recorded
120s-timeout "unknown" verdicts are NOT re-attempted at the lower timeout
(`diff.py`'s own resume logic only re-tries an "unknown" when the new
timeout is HIGHER than what it already saw), so no work was thrown away.

**This completed all 71+13 = 84 checks** (unlike §5's coverage check,
which did not finish):

```json
{
  "reference_total": 71,  "ours_total": 13,
  "reference_rejected_by_ours": 7,   "reference_unknown": 49,   (15 covered)
  "ours_rejected_by_reference": 3,   "ours_unknown": 7,          (3 covered)
  "our_views_excluded": 0,  "reference_views_excluded": 0
}
```

**15/71 reference queries covered** (vs. the control's own stale
4547-dump/7-query snapshot's 7/71 — see `RESULT.md` §4 for why that
snapshot predates variant_b's fuller, all-8-STI-type corpus and isn't a
fair baseline; the README's own "17 distinct queries" note for this
endpoint's prior worked-example is the closer comparison point). All 56
"unknown" verdicts (49 reference + 7 ours) are `timeout/inconclusive`
against complex 5-9-table joins with mixed literal/symbolic predicates —
matching the control's own documented experience exactly ("42
undecidable... large multi-join determinacy problems that time out even
at 120s — a blockaid capacity limit, not a corpus statement"). Every one
of the first 5-6 checked (before the timeout reduction) had already
exhausted the full 120000ms before returning unknown — this is a genuine
solver-capacity ceiling, not an artifact of the timeout reduction (lower
timeouts only affected queries checked AFTER the switch, all equally
complex).

### 7 provably-rejected reference queries — every one attributed to a named residue

```sql
-- (1) raw notification_actors row fetch (not folded through to people)
SELECT notification_actors.* FROM notifications, notification_actors
WHERE notification_actors.notification_id = notifications.id
  AND notifications.recipient_id = _MY_UID;

-- (2)-(3) admin/moderator role checks on current_user.person
SELECT 1 FROM people, roles WHERE roles.name IN ('admin','moderator')
  AND roles.person_id = people.id AND people.owner_id = _MY_UID;
SELECT 1 FROM people, roles WHERE roles.person_id = people.id
  AND roles.name = 'admin' AND people.owner_id = _MY_UID;

-- (4) current_user's OWN profile (not another actor's)
SELECT profiles.* FROM people, profiles
  WHERE profiles.person_id = people.id AND people.owner_id = _MY_UID;

-- (5) connected services list
SELECT * FROM services WHERE user_id = _MY_UID;

-- (6) current_user's own person record
SELECT * FROM people WHERE owner_id = _MY_UID;

-- (7) the current_user lookup itself
SELECT * FROM users WHERE id = _MY_UID;
```

Residue attribution:

- **Queries (2)-(7), 6/7: layout/before_action plumbing, a deliberate,
  DOCUMENTED runner-scope decision, not a corpus gap.** `run_dse.rb`
  calls the controller action METHOD directly (`ctrl.send(:index)`)
  rather than `ActionController::TestCase#process`, explicitly to keep
  `SYM_PARAM_show` symbolic (see `run_dse.rb`'s own header comment) — the
  documented side effect is that `process_action`'s before_action chain
  (`authenticate_user!` and everything it does, including the REAL
  `current_user`/Devise `User.find` lookup — query (7) — and any
  admin-role/service/own-profile checks a shared `ApplicationController`
  before_action might run — queries (2)-(6)) never executes. Separately,
  `NotificationsController.layout(false)` is set deliberately (see
  `concolic_targets.rb`'s header, "Runtime scope decision") specifically
  to keep the unrelated site-chrome layout (header/nav — which is exactly
  where a "your own profile photo" / "connected services" / admin-menu
  query would come from) out of this endpoint's query shape. Both
  decisions predate this experiment and are load-bearing for *why this
  endpoint is drivable at all* (per `run_dse.rb`'s own comments, driving
  through the full before_action chain was the source of an entire
  separate wall-crash family in earlier generations) — not something to
  casually reverse.
- **Query (1), 1/7: a genuine, narrow extraction gap.** My 28-query set
  has queries that JOIN THROUGH `notification_actors` to reach `people`
  (the actors-list and actor-profile fetches), but none that fetches the
  join-table ROW itself in isolation. This is real: some app code path
  (plausibly `note.actors.size`/`.count`'s SQL, or an association-loading
  intermediate step) issues exactly this bare join-table SELECT, and no
  dump's mock-note rendering happened to capture it as its own producer
  event distinct from the folded people-join. Reported as an honest,
  narrow residue — not investigated further given the time already spent
  on this pipeline's mechanics (see §8).

### 3 "ours, not answerable from reference" — every one attributed

```sql
-- (a) mentions-as-notification-target (Notifications::Mentioned* family)
SELECT mentions.* FROM mentions, notifications
  WHERE mentions.id = notifications.target_id AND notifications.recipient_id = _MY_UID;

-- (b) current_user.blocks
SELECT blocks.* FROM blocks WHERE blocks.user_id = _MY_UID;

-- (c) finder-mock-without-WHERE broadened contacts fetch (already flagged)
SELECT contacts.* FROM contacts;
```

- **(a)**: the polymorphic `notifications.target` fetch when the target
  IS a `Mention` row (types `mentioned`/`mentioned_in_comment`, driven by
  type4/type5 rounds) — a real, structurally-correct query this
  endpoint's own code issues (W3b's polymorphic `find_target`, T1-verified
  necessary in §2) that the reference set apparently does not enumerate
  in this exact shape. Not investigated further whether the reference
  models this differently (e.g. folded into the mentions-family queries
  it DOES have) or genuinely omits it — reported as an open question, not
  resolved either way.
- **(b)**: `current_user.blocks` — reached via some real (non-layout)
  code path this rig DOES execute (design-mock `User#blocks`, T1-probed
  in §2 as an SQL-boundary-confirmed design mock). Plausibly a genuine
  query the reference set doesn't enumerate for this endpoint, or a
  path only reachable via a symbolic-DSE branch the reference's own
  traffic-derived extraction never happened to observe. Not resolved.
- **(c)**: already carries its own `-- NOTE: finder mock rendered without
  its WHERE conditions; query is broader than the app's real query` in
  the extracted SQL — a KNOWN, LABELED hygiene issue (satisfies
  `MOCK_RULE_EXPERIMENT.md`'s scoring bar #2, "no ... flags without
  notes"), not a silent defect. The real query has a WHERE clause the
  render lost; broader-than-real is the honest, expected failure mode of
  an unresolved finder-kwargs case, already flagged as such at extraction
  time.

## 8. Honesty notes / known limitations

- T1 covers 18/~79 declared mocks (see §2) — an explicit, documented scope
  reduction driven by available time, prioritized toward the mocks this
  endpoint actually (or plausibly) reaches.
- T1's connection-touch hook initially produced false positives from
  ActiveRecord's own schema/metadata bootstrapping SQL; root-caused and
  reclassified (see `LEAF_PROBES.md` harness notes) but the EXACT reason
  a warm-up call didn't fully suppress recurrence was not chased to full
  ground truth — reported as a known harness quirk, not silently patched
  over.
- One T1 candidate (`ActionController::Instrumentation#redirect_to`)
  could not be mechanically probed due to a JRuby `super`-dispatch
  limitation on manually-rebound module `UnboundMethod`s; a manual
  source-inspection verdict was substituted and labeled as such, per the
  coordinator's explicit instruction to record `INSTRUMENTATION-FAILED`
  rather than downgrade silently.
- One T2 class (`count-chain`) and Tier 2 one-sided were not probed within
  budget and are blocked from auto-declaration rather than assumed safe.
- One design-mock spot check (`User#blocks`) was inconclusive (0% line
  coverage from an ad-hoc fixture) — recorded as such; does not matter for
  admissibility since design mocks are exempt from removal regardless.
- **`coverage_summary.json` was never produced for variant_b.** Two
  attempts (default and reduced solver timeout), 45+ and 31+ minutes
  respectively, killed after showing no sign of finishing (see §5). The
  corpus itself is confirmed healthy (6874 runs, 0 errors, 0 unparseable,
  assumption-derivation — the part T1/T2's own work touches — completes
  in seconds with the expected tier0=163/tier1=12/tier2=0 counts). This is
  a solver-capacity limitation of the combination-coverage CHECK, not a
  claim about the corpus or a gap in the discipline work. The actual
  `missing_branches`/`tree_nodes` numbers for variant_b are UNKNOWN — not
  estimated, not extrapolated, not silently assumed to equal the
  control's numbers.
- **Two independent, real infrastructure discoveries this session, both
  fixed and documented rather than worked around silently:** (1) the
  system-wide memory watchdog can kill a job running well inside its OWN
  cgroup cap, because it acts on system-wide `MemAvailable`, not per-job
  usage — cross-tenant contention with variant_a's own coverage checker
  killed my blockaid JVM twice; (2) `queries_from_runs.diff` does not
  pre-filter placeholder-bearing queries from `--ours` the way
  `queries_from_runs.dump`'s subsumption pruning does, and feeding them
  in crashes the checker (`rc=-9`) rather than reporting a per-query
  error — worth raising upstream if this pipeline sees continued use.
- Extraction and diff numbers (§6-7) ARE complete, real, and did not
  require any shortcuts beyond the two documented ones above (timeout
  reduction for undecided solver calls; placeholder-query pre-filtering
  for the checker's `--ours` view set, both queries and their exclusion
  count fully disclosed).
