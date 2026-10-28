# Re-drive and re-extract status — 2026-09-18

Scope: commit the pending `src/` work, clean up `src/queries_from_runs/`,
determine which of the five **complete** endpoints (comments_index,
conversations_index, notifications_index, people_show, people_stream) carry a
dump corpus that predates a boundary/runtime fix, re-drive those, and re-extract
every in-scope endpoint's SQL access policy with the current alias-fixed
`transform.py`.

**posts_show is out of scope and was not touched.** Its `concolic_targets.rb` is
pinned at `627bac2c1199…` for a live campaign; `p44-coveragecheck-real1.scope`
was running throughout this task and was left alone.

---

## 1. Commits (all in `src/`, nested repo, branch `main`)

| commit | what |
|---|---|
| `481f25c` | `engine: move foreclosure_gate into concolic_engine, shim the old path` |
| `a94ce44` | `queries_from_runs tests: update 19 alias literals for hash-derived aliases` |
| `ce4bd78` | `queries_from_runs: drop 13 stale on-disk backup files; ignore *.bak*` |

Staged file-by-file (`git add <path>`); no `git add -A`, no amend, no
force-push, no hook skipping. Each message ends with the required
`Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` line.

### 1a. `481f25c` — foreclosure_gate relocation

The prior session's partial merge, verified rather than assumed:

* `foreclosure_gate.py` moved `end_to_end_completion_checker/assumption/` →
  `concolic_engine/`; its `assumption_checker` import became absolute.
* **Verified safe to move**: `foreclosure_cmd` is an opt-in key and *no*
  `completion_config.json` anywhere under `reports/diaspora/` sets it, so no
  live batch invokes the gate by path.
* **The compat shim is genuinely needed**: four posts_show scripts import the
  old path — `_p35_forecl_keep.sh`, `_p35_forecl_gate.sh`,
  `_p35_forecl_keep_all.sh`, `_p39_forecl_gate.sh` (the task brief named only
  the first). The shim was committed as part of this change.
* Both import paths were exercised and resolve to the same objects.
* `assumption_checker.py` (frozen, `ProbeCache`-keyed on its own
  `source_hash`) and `mock_note_check.py` (path hardcoded in every batch's
  `note_check_cmd`) deliberately did not move; both READMEs say why.

### 1b. `a94ce44` — 19 alias literals

Test-only follow-up to the comments_index alias-collision fix
(`_COMMENTS_PRECISION_FIX_20260917.md`). `transform.py` was already committed in
`82dd362`; only the test file lagged. Rendered joins/predicates are identical —
only the alias digit moved (`posts` → `posts347`, `people` → `people989`, …).

---

## 2. Cleanup of `src/queries_from_runs/` (`ce4bd78`)

### Removed: 13 stale backup files

Five generations across `app_config.py`, `dump.py`, `__init__.py`, `pcs.py`,
`plan.md`, `README.md`, `transform.py`, `test_queries_from_runs.py` and
`audits/exception_note_audit.py`:

```
*.bak_pre_provenance_20260915   *.bak_pre_simplify_20260915   (this one was
*.bak_pre_pcprune_20260915      *.bak_pre_appname_20260915     not in the brief)
*.bak_pre_rejected_20260916
```

All 13 were themselves **tracked and committed unmodified in HEAD**, so
`git rm` loses nothing — each is recoverable with `git show ce4bd78~1:<path>`.
Nothing under `src/`, `scripts/` or `reports/diaspora/` referenced any of them,
and the package's app-name walk matches `.py`/`.sh`/`.java`, so no test saw
them. `*.bak` / `*.bak_*` added to `.gitignore`.

### Not changed, and why

**The `diaspora` literal at `test_queries_from_runs.py:1924` is the legitimate
case, not a violation.** `_APP_NAMES_RE` is the *lint that enforces* the
"nothing in src/ may be app-specific" rule: `test_no_app_name_in_any_module`
and `test_no_app_name_in_the_subsume_harness_scripts` walk every `.py`/`.sh`/
`.java` in the package and fail if the name appears anywhere; the pattern line
exempts itself with an `# app-name-rule` marker so the rule can state itself.
Sourcing the token from `reports/diaspora/queries_config/app.json` would be
strictly worse — it would bake an app-tree path into `src/`, which the sibling
`test_no_app_path_defaults_in_the_package` explicitly forbids, and it would make
the lint silently vacuous whenever that config is absent. Left as is.

**`audits/README.md`, `subsume/README.md`** name diaspora in prose only, to
point at `reports/diaspora/queries_config/` as where an app's config and
fixtures live. The app-name walk covers code, not docs, by design.

**`subsume/classes/*.class`** are committed build output that `build.sh`
regenerates only when the directory is missing. Un-committing them would make
first use require a JVM build — a behaviour change, not a cleanup. Flagged, not
decided.

### The blockaid submodule: left dirty on purpose

`queries_from_runs/blockaid` shows `src/test/resources/DiasporaTest/policies.sql`
locally deleted. **This is not our diaspora leakage, and the deletion is not a
forgotten cleanup — it is the reference quarantine.**

* `blockaid` is vendored upstream (`github.com/blockaid-project/blockaid`).
  `DiasporaTest` is one of *its own* published benchmarks, alongside
  `AutolabTest` and `SpreeTest` — each of which still carries the identical
  6-file fixture set including its own `policies.sql`. Diaspora appears there as
  upstream's example, which is also why the package's app-name walk lists
  `blockaid` in `_SKIP_DIRS` ("the vendored submodule is not ours").
* The deleted file is a 19 KB hand-written **reference access policy for
  diaspora** (`-- my_info`, `SELECT users.* FROM users WHERE users.id = _MY_UID;`
  …) — precisely the oracle this experiment is run blind to. It was removed as
  part of the 2026-08-26 reference quarantine; its siblings are in
  `/home/dev/_reference_locked`, mode `d---------`, timestamped `Aug 26 18:19`,
  the same minute as `DiasporaTest/`'s own mtime.

So: committing the deletion would fork vendored third-party history and bake an
experiment-integrity measure into an upstream repo; restoring the file would
un-quarantine the reference. Neither is a cleanup. **The submodule pointer was
not bumped and the file was not restored** — the dirty submodule is the correct
state and the only thing `git status` shows in `src/` now.

### Tests after cleanup

| suite | result |
|---|---|
| `queries_from_runs/test_queries_from_runs.py` | **115 passed, 3 skipped** (baseline) |
| `test_subsume_workers` + `test_query_ops` + `test_statement_note_lint` | 39 passed |
| `test_conjunction_foreclosure`, `test_subconjunction_foreclosure`, `test_completion_audit_timeout`, `test_assumptions`, `test_names`, `test_checkpoint` | 115 passed |

The 3 skips are env-gated and expected: `QFR_TEST_RUNNER_RB` (line 381),
`QFR_APP_CONFIG` (line 1296), `QFR_TEST_DUMP_DIR` (line 1429). (The brief named
two of these three env vars.)

---

## 3. Which endpoints needed re-driving

Decided on **direct corpus evidence**, not on dates alone. Every corpus was
grepped for each defect's own note signature, and every generated policy was
scanned for unresolved `SYM_RESULT_…` placeholders in actual SQL (as opposed to
header prose).

| endpoint | dumps | corpus dated | B-1 note | B-3 note | unresolved in SQL | verdict |
|---|---|---|---|---|---|---|
| comments_index | 26,528 | 2026-09-01 | 0 | 0 | **0** | already current |
| conversations_index | 18,623 | 2026-08-31 | 0 | 0 | 0 (1 in header prose) | already current |
| notifications_index | 313,977 | 09-01…09-15 | 0 | (prose only, resolves) | 0 (5 in header prose) | already current |
| people_show | 12,997 | 2026-09-05 | **9,359** | 0 | **18** (`find_by_1_id`) | **needs re-drive — BLOCKED, see §5** |
| people_stream | 13,677 | 2026-09-11 | 0 | **13,612** | **7** (6 × `as_api_response`) | **re-driven, see §4** |

Notes on the three that were already current:

* **comments_index** — the X3/X6f/X6i mock removals were *verified live*, not
  assumed: 0 dumps carry the `as_api_response`, `Person#name` or
  `people_from_string` mock notes; 26,491 of 26,528 dumps carry real
  `diaspora_handle` lookups (X6f's real
  `find_or_fetch_by_identifier` → `find_by(diaspora_handle:)` family); the
  policy carries 47 real `FROM profiles` reads (X6i's real `self.profile`
  association read) and exactly the differentiated mention-identity aliases the
  precision-fix report predicted (`people70`, `people197`, `people340`,
  `people844`, `people941`, `people942`, …). No re-drive needed.
* **conversations_index / notifications_index** — neither carries a B-1 or B-3
  defect signature, and nothing in `_MOCK_NOTE_FIXES_20260916.md` names either
  endpoint. Their only `SYM_RESULT_` occurrences are the devise principal leaf
  (`devise_user_first_1_person_id` / `_username`) appearing in POLICY_HEADER
  prose — the declared post-auth principal, not an unresolved bind in a
  statement. **Not driven speculatively.**
* B-4 (`Arel::Nodes::Casted#value`) is already fixed in the people_show,
  people_stream and notifications_index copies of `concolic_targets.rb`
  (the 2026-08-19 "bug-2b" fix, `node.val`). Only posts_show's pinned copy still
  has `out << node.value` — consistent with TODO.md, and out of scope.

---

## 4. people_stream re-drive — done, faithful, and it worked

### Why it was safe to replay, and how faithfulness was preserved

people_stream is the one in-scope endpoint where a *replay* (as opposed to a
fresh exploration) is actually possible:

* **every one of its 13,677 dumps records its own `concolic_seeds`**, and all
  13,677 seed sets are distinct;
* its `run_dse.rb` already carries the `EXTRA_SEEDS_JSON` + `SEEDS_ONLY` replay
  hook (ported from notifications_index, with the 2026-09-10 drift fix that
  disables state/path dedup and suppresses the flip frontier during replay), so
  a replay explores nothing new and emits exactly one dump per seed;
* B-4 is already fixed in *this* endpoint's `concolic_targets.rb` (the
  2026-08-19 `node.val` fix), so B-3's note carry-through can actually render
  relation SQL instead of falling into its prose fallback.

The seeds were taken **from the existing corpus itself** — grouped by the
scenario that produced them — so no seed or base was re-selected.

**One runner-local change was needed** (`reports/diaspora/results3/` is a
write-freely zone per CLAUDE.md; `src/` and `concolic_targets.rb` were not
touched): people_stream's runner had no `SCENARIO_ONLY`, so it replays every
seed under all three scenarios. That would have tripled the corpus *and*
evaluated each seed in scenarios it was never explored in — i.e. it would have
made the replay unfaithful. A `SCENARIO_ONLY` knob was added, in the same shape
people_show's runner already has, guarded so that omitting it leaves
exploration behaving exactly as before.

### Pre-flight evidence that the re-drive actually fixes B-3

A 3-seed smoke replay was run first and diffed against the originals:

| | note on `…as_api_response_1_row_id` |
|---|---|
| old dump | `ActsAsApi::Collection#as_api_response` (prose — nothing can join to it) |
| replayed | `SELECT "people".* FROM "people" WHERE "people"."id" = $$(SYM_RESULT_ActiveRecord__Relation_records_6_row_person_id) LIMIT 1` |

The smoke dumps were deleted before the real drive.

### The drive

```
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=12G \
    --unit=redrive-people-stream  _drive_people_stream.sh
```

one JRuby pass per scenario, `SEEDS_ONLY=1`, `LABEL_SUFFIX=_RD918`,
`MAX_RUNS=<#seeds>+10`, `TIME_BUDGET=14400`:

| scenario | seeds | dumps produced | wall |
|---|---:|---:|---|
| anon_all | 2,901 | **2,901** | 02:36:40 → 02:37:54 |
| anon_json | 3,277 | **3,277** | 02:37:54 → 02:41:21 |
| auth_json | 7,499 | **7,499** | 02:41:21 → 02:51:23 |
| **total** | **13,677** | **13,677** | ~15 min |

Exact 1:1 seed→dump for every scenario. Peak scope memory 1.0 GiB of the 12 GiB
cap; box load stayed ≤ 4 with ~40 GiB free alongside the still-running
`p44-coveragecheck-real1.scope`.

### Corpus handling (the original is untouched)

The runner can only write into its own directory, so the fresh dumps were
written there under the `_RD918` label and then moved out:

* fresh corpus → `results3/_redrive_20260918/people_stream/` (13,677 dumps,
  169 MB), with the pre-drive `exploration_summary.json` copied in as the param
  pool source (request params are fixed per endpoint and unchanged by a note
  refresh);
* **`results3/people_stream/` still holds its original 13,677 dumps, all still
  dated 2026-09-11, with 0 `_RD918` leftovers and its original
  `exploration_summary.json` restored** (the drive overwrites that file; the
  pre-drive copy was saved first and put back, and the drive's own version kept
  as `_exploration_summary_people_stream_REDRIVE.json`).

Nothing about the proven-complete corpus was mutated, so the existing
completeness claim still rests on exactly the artifact it was made against.

### Result

Re-extracted over the fresh corpus with the same
`_pcfold3_parallel.py --shards 8 --cap 2 --suffix _pcfold3` recipe (under
`--unit=reextract-people-stream`, `MemoryMax=16G`, 463 s). Previous outputs kept
as `people_stream_pcfold3_{base,fix}.sql.pre_redrive_20260918`.

| | pre-re-drive | post-re-drive |
|---|---:|---:|
| raw queries | 337,674 | **354,291** |
| distinct (shape, preds) | 536 | **602** |
| statements (base / fix) | 159 / 159 | **169 / 169** |
| PC predicates pre-prune | 1,388 | **1,636** |
| PC predicates kept | 132 | **146** |
| `profiles` reads | 13 | **18** |
| **unresolved `SYM_RESULT_` in SQL** | **7** (6 × `as_api_response`) | **0** |
| `as_api_response` references | 6 | **0** |

**people_stream's policy is now fully resolved** — every bind has a producing
SELECT. `SYM_PERSON_via_user` still appears (46 occurrences, was 47), which is
correct: X1 is a *named principal leaf*, not an unresolved result placeholder,
and is the deferred Rule-T item in §7.

## 5. people_show: re-drive is BLOCKED — escalating, not guessing

people_show genuinely needs the B-1 re-drive (9,359 of its 12,997 dumps carry
the `WHERE unavailable -- interceptor drops kwargs for *rest-signature finder
methods` note, and 18 statements in its policy are unresolved
`SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id`). The B-1 fix is
present and committed in `src/ruby_runtime/call_interceptor.rb:131-158`.

**It cannot be done as specified, for two independent reasons.** I stopped
rather than pushing through, per the brief.

1. **The seeds were never recorded, so "the same seeds" do not exist on disk.**
   `people_show/run_dse.rb`'s `run_one(prefix, label, seeds)` sets
   `ConcolicTargets.seed_overrides = seeds.merge(scen[:seeds] || {})` but never
   writes `seeds` into the dump. Confirmed: **0 of 12,997** people_show dumps
   contain a `concolic_seeds` key, there is no seed file anywhere in the
   directory, and the runner has no `EXTRA_SEEDS_JSON` / `SEEDS_ONLY` /
   `KEEP_DUMPS` support at all. (people_stream and notifications_index all
   record `concolic_seeds` and support the replay hook; people_show is the
   odd one out.) The dumps' `symbolic_results` are *observed* values, not the
   forced subset, and replaying them wholesale is exactly what that runner's
   own header calls unsound — `SYM_RESULT_<func>_<idx>` ordinals are per-run
   and not stable across runs.

2. **Running the runner would destroy the existing corpus first.**
   `people_show/run_dse.rb:710` is an unguarded
   `Dir.glob(File.join(DIR, "dump_*.json")).each { |f| File.delete(f) }` — no
   `KEEP_DUMPS` check, unlike people_stream's. Invoking it wipes all 12,997
   dumps of the proven-complete corpus *before* producing a fresh, differently
   explored one. That is an irreversible loss of the artifact behind a
   completeness claim this task is explicitly told not to re-verify.

Re-exploring from scratch would also violate "do not change which seeds/bases
are selected": prefix-directed DSE with `COMPOSE_CAP` picks its own frontier,
so a fresh run is a different corpus, not a note refresh.

**What a human needs to decide** (any of these is a real change, none is
unilateral):

* add seed recording (`dump["concolic_seeds"] = seeds`) + the
  `EXTRA_SEEDS_JSON`/`SEEDS_ONLY` replay hook + a `KEEP_DUMPS` guard to
  `people_show/run_dse.rb`, then drive a *fresh* base corpus once and accept
  that the completeness proof must be re-established for it; **or**
* accept a fresh exploration of people_show and re-run the coverage checker on
  it (explicitly out of scope for this task); **or**
* leave people_show's 18 `find_by_1_id` statements unresolved for now and note
  them as a known corpus-age gap.

Nothing was run against people_show. Its corpus and runner are untouched.

## 6. Final extraction results

All five in-scope endpoints, extracted with the current alias-fixed
`transform.py` (hash-derived, producer-stable table aliases) via
`_pcfold3_parallel.py`. Four were produced by the run that finished
2026-09-18T02:04 (`_run_pcfold3_refix_20260917.sh`, `VERDICT_PCFOLD3_REFIX_ALL_DONE`
— comments_index had been done separately at 00:29); people_stream was
re-extracted at 03:00 over its re-driven corpus.

`base` = pruning as shipped (`reliable_only=False`); `fix` =
`--reliable-pruning-witnesses` arm. Both arms come from one identical
extraction, per the ground-truth-differential discipline.

| endpoint | dumps | raw queries | distinct (shape,preds) | stmts base | stmts fix | PC preds pre-prune | PC kept base | PC kept fix | unresolved SYM_RESULT |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `comments_index` | 26,528 | 413,594 | 407 | 155 | 155 | 1,230 | 166 | 166 | 0 |
| `conversations_index` | 18,623 | 404,127 | 2,023 | 353 | 465 | 8,772 | 1,471 | 2,275 | 1 † |
| `notifications_index` | 313,977 | 6,169,265 | 1,208 | 135 | 142 | 2,312 | 13 | 47 | 5 † |
| `people_show` | 12,997 | 367,393 | 493 | 59 | 61 | 3,241 | 109 | 131 | **18** ‡ |
| `people_stream` | 13,677 | 354,291 | 602 | **169** | **169** | 1,636 | **146** | **146** | **0** |

† Header prose only — the declared devise principal leaf
(`devise_user_first_1_person_id` / `_username`) named in a POLICY_HEADER comment
and in the seed documentation. No statement carries an unresolved bind.

‡ Real: 18 × `SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id`, the B-1
residue. Clears only with a re-drive, which is blocked — see §5.

Outputs (per endpoint, in `results3/queries_from_runs/`):
`<endpoint>_pcfold3_base.sql`, `<endpoint>_pcfold3_fix.sql`,
`_summary_<endpoint>_pcfold3.json`; logs in `scratchpad_pcfold3_logs/`.

**Completeness was not re-checked for any endpoint**, per explicit instruction:
the Z3 coverage checker was not run. For people_stream that is sound in the
strict sense — the replayed seed set is byte-for-byte the seed set the existing
proof was made against, and only note text changed.

## 7. Escalated, not attempted

Per the brief, not touched and not worked around:

* **X1** — `SYM_PERSON_via_user` fixed mint name (people_stream, 19
  statements). Rule T: needs a corpus-wide naming ruling from whoever owns
  `principal.binds`. Still visible in the re-driven corpus as expected
  (`SYM_PERSON_via_user_closed_account`, `_guid` in the skipped-PC census) —
  the re-drive fixes B-3 only, and was never going to move X1.
* **`posts.guid = posts0.id` type mismatch** — posts_show, 9 statements. Rule T
  *and* out of scope; its exact mint site is still untraced.
* **B-4 / B-5** — posts_show only; `concolic_targets.rb` pinned for the live
  campaign.
* **people_show re-drive** — see §5. This one is *not* in TODO.md as a known
  blocker; it is a finding of this pass.

---

## 8. Incidental observation: the posts_show coverage check failed (not caused by this task)

`p44-coveragecheck-real1.scope` — the live posts_show job that was running when
this task started — **exited 1 at 02:55**, after 2 h 26 m and a 13.1 GB peak. It
was never touched by this task, but the failure is worth flagging to whoever
owns that campaign.

Its **coverage phase succeeded** (190,267 runs, 1,133 assumptions, done in
2,402 s, 8 clean heartbeats). It then died in the completion step:

```
File ".../posts_show/coverage_report.py", line 515, in main
  attach_to_summary(summary, json.load(fh))
File "/home/dev/project/src/concolic_engine/completion.py", line 201, in extract_shims
  ShimSpec(key=row["key"])   # fail fast on a malformed extractor row
KeyError: 'key'
```

i.e. a **malformed shim-extractor row in posts_show's own config**, caught by
`extract_shims`' deliberate fail-fast check. The expensive coverage result is
presumably recoverable without a re-run if the offending row is repaired.

**Ruled out as a cause of this task's work**, for the record:

* `concolic_engine/completion.py`'s mtime is `2026-09-18 00:18` — ten minutes
  *before* the job started (00:28:46) — and it has not been written since. This
  task committed that file's already-on-disk content at 02:27; `git commit`
  changes no bytes in the working tree.
* `git show 481f25c -- concolic_engine/completion.py` contains **zero** hunks
  touching `extract_shims` or the `row["key"]` line; that commit only
  re-pointed `foreclosure_gate` import paths and docstrings.
* The only on-disk deletions this task made were the 13 `.bak` files under
  `src/queries_from_runs/`, which are not importable modules and are not on
  this job's code path at all.
