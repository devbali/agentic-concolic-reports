# STAGED checkpoint/resume patches — apply after the 2026-09-11 chains end

Owner rule, 2026-09-12: *anything that runs longer than ~10 minutes must
checkpoint its progress and resume from it on a rerun, instead of restarting
from zero.*

`notif-finish-20260911.service` and `posts-finish-20260911.service` were RUNNING
when these were written and will still IMPORT or READ every file below later in
their pipelines, so the live files were left untouched. Each patch sits beside
its target as `<file>.checkpoint_next`.

## Apply list — one line each, run only when BOTH are inactive

Check first: `systemctl --user is-active notif-finish-20260911.service posts-finish-20260911.service`
(both must print `inactive`/`failed`, not `active`).

```
mv /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py.checkpoint_next /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py
mv /home/dev/project/src/test_assumption_checker_checkpoint.py.checkpoint_next                          /home/dev/project/src/test_assumption_checker_checkpoint.py
mv /home/dev/project/src/queries_from_runs/subsume.py.checkpoint_next                                   /home/dev/project/src/queries_from_runs/subsume.py
mv /home/dev/project/reports/diaspora/results3/notifications_index/_c7_audits.sh.checkpoint_next        /home/dev/project/reports/diaspora/results3/notifications_index/_c7_audits.sh
mv /home/dev/project/reports/diaspora/results3/posts_show/_c7_audits.sh.checkpoint_next                 /home/dev/project/reports/diaspora/results3/posts_show/_c7_audits.sh
mv /home/dev/project/reports/diaspora/results3/people_stream/_c7_audits.sh.checkpoint_next              /home/dev/project/reports/diaspora/results3/people_stream/_c7_audits.sh
mv /home/dev/project/reports/diaspora/results3/posts_show/_engine_section.py.checkpoint_next            /home/dev/project/reports/diaspora/results3/posts_show/_engine_section.py
mv /home/dev/project/src/concolic_engine/completion.py.checkpoint_next                                  /home/dev/project/src/concolic_engine/completion.py
mv /home/dev/project/src/test_completion_audit_timeout.py.checkpoint_next                               /home/dev/project/src/test_completion_audit_timeout.py
mv /home/dev/project/reports/diaspora/results3/posts_show/completion_config.json.checkpoint_next     /home/dev/project/reports/diaspora/results3/posts_show/completion_config.json
```

`chmod +x` is not needed: the three `_c7_audits.sh` are invoked as
`bash "$B/_c7_audits.sh"` by `_p13c.sh` and via `systemd-run … "$B/_c7_audits.sh"`
by `_c11_audits_run.sh` — restore the executable bit anyway if you prefer
(`chmod 755`), since `mv` keeps the staged file's 644.

Then, once: `cd /home/dev/project/src && python3 -m pytest -q --ignore=queries_from_runs`
— 216 tests pass today, 223 after the staged assumption-checker test lands,
**237** with the audit-timeout test as well (14 tests; verified 2026-09-12 by
running the staged `completion.py` + its test on a shadow package, and
`test_confinement_e2e.py` — the only existing test that imports
`concolic_engine.completion` — re-run green against it).

## What each patch does (all OPT-IN; unset = today's behaviour, byte for byte)

| staged file | switch | unit that is checkpointed |
|---|---|---|
| `assumption_checker.py` | `ACHK_CHECKPOINT=<path>` | one JRuby PROBE REPLAY. `ProbeCache` persists each `(scenario, seeds)` record as it lands and serves it on a rerun before a single runner launch. Also `ACHK_RESULTS_JSONL=<path>`: one verdict row appended as it is decided (`--json-out` writes an EMPTY file on a kill, because `results = []` is what its `finally` sees). Keyed on the batch config + this module's source. |
| `test_assumption_checker_checkpoint.py` | — | 7 tests for the above (record round-trip exactness, no-launch replay, recorded `None` is a hit, stale config discarded, off by default). |
| `subsume.py` | `SUBSUME_CACHE=<path>` | the blockaid solver call for ONE query set (~42 min on people_stream). Keyed on the query list, the checker binary's mtime/size and `QFR_APP_CONFIG`'s content. Granularity is stated in the code: the pairwise loop is inside the Java, so a kill DURING the JVM still loses that invocation — per-pair resume needs `subsume/java/SubsumeChecker.java`. |
| `_c7_audits.sh` (×3) | `AUDITS_CHECKPOINT=1` | one AUDIT. Its output goes to `$B/_c7_audits.done/<name>.out` and a `.ok` marker is set on `EXIT=0`; a rerun replays a finished audit into the log instead of running it. The directory is discarded when the corpus (dump count + newest mtime) or the script's own hash changes. Known limit, written in the file: the key does NOT see a change to an audit TOOL under `src/` or `tools/` — bump the script or `rm -rf` the `.done` dir when one changes. |
| `completion.py` | `COMPLETION_AUDIT_TIMEOUT=<s>` (also `audit_timeout` in a completion config and `timeout` on one `audit_cmds` entry; precedence: the audit's own key > the env var > the batch's `audit_timeout` > 1800 = today's behaviour) | the DUMP-SIDE AUDITS' wall clock, plus: a timeout is now a **RED audit row** (`green:false`, `timed_out:<s>`) instead of a `subprocess.TimeoutExpired` that escapes `attach_to_summary`. This is the 2026-09-11 notifications_index loss: `run_audits` line 197 hard-coded `timeout=1800`, `cardinality_consistency_audit` was killed at 30 min, and because `coverage_report.py` writes `coverage_summary.json` only AFTER the gate, an 8 962 s coverage phase (114 610 runs) was thrown away. The audits scan the batch DIRECTORY (289 733 dumps), not the pass's DUMP_LIST, so their cost is not the pass's cost. |
| `test_completion_audit_timeout.py` | — | 14 tests: precedence of the three settings, unusable values fall back to 1800, a slow audit becomes a RED row and the next audit still runs, the blocking line names the TIMEOUT, `_tail` on str/bytes/None. |
| `_engine_section.py` | `ENGINE_CHECKPOINT=1` | (a) the WHOLE stage: a sidecar `<SUMMARY_OUT>.checkpoint_key` holds the digest of (`SUMMARY_IN`, `completion_config.json`); a match plus an existing completion section means the stage is not repeated. (b) exports `ACHK_CHECKPOINT` so the gate inside it resumes per probe. |
| `posts_show/completion_config.json` | — (a standing default) | adds `"audit_timeout": 21600`, the same key notifications_index already has LIVE. Staged, not applied live, because the RUNNING `_p13c.sh` stage 13c-2 reads this exact file (`_engine_section.py`: `cfg = json.load(open(HERE/completion_config.json))`). posts_show's two `extra_audit_cmds` scan a 183 351-dump / 36.07 GB directory (`empty_relation_emission` ~23 min) — under the old 1800 s wall with ~20 % of margin. `_p14_rerun_after_restart.sh` also passes `COMPLETION_AUDIT_TIMEOUT`, which BEATS this key; the key is what makes a HAND-run gate safe. |

## Already LIVE (not staged — verified safe to edit while the chains run)

- `src/concolic_engine/checkpoint.py` (new), `src/concolic_engine/coverage.py`
  (`COVERAGE_CHECKPOINT=<path>` → per-demand-set enumeration records),
  `src/test_checkpoint.py` (new, 21 tests).
- Both running passes had already imported `coverage.py` 2 h 37 m before the
  edit (verified: PIDs 4527 / 4572, and both `coverage_report.py` copies import
  `concolic_engine.coverage` at module top, line 42 — `concolic_engine.completion`
  is the only engine import they defer, at line 594 / 298). Neither remaining
  stage of either chain re-invokes `coverage_report.py`.

## NOT done, and why

- `_exact_enum.py` (`notifications_index`, `people_stream`, `posts_show`;
  measured 11–26 min per run). Insertion point is the per-clique loop
  (`for ci, clique in enumerate(cliques)` — posts_show:383, the other two:486)
  with one record per clique carrying `per[]`'s row plus `sat`/`covered`/
  `forecl`/`gate_counts`/`leaf_groups`/`bounded`. Not attempted because the
  notifications/people_stream variant (identical to each other, different from
  posts_show) also STREAMS `EMIT_REMAINING` assignments and maintains
  `reach_rem_per_set` / `emit_mismatch` inside that loop, so a faithful replay
  has to record those too; landing that untested against a real 10–26 min run
  was the wrong trade against the hours-long jobs above.
- JRuby drive batches. Resume EXISTS at chunk granularity and only within one
  TAG (`[ -f "$CD/done_${V}_${C}" ] && exit 0`, `CD="$B/_chunks/$TAG"`, in the
  `_chunk_drive.sh` / `_set_drive.sh` / `_enable_drive.sh` family);
  `_tree_drive.sh` and `_demand_drive.sh` have no markers at all, and
  `run_dse.rb` has NO seed ledger — under `SEEDS_ONLY=1` (which every drive
  script sets) its in-process `seen_seeds` check is explicitly disabled, and
  dumps are named by invocation suffix + run ordinal, never by seed. Changing
  that touches each endpoint's `run_dse.rb`, which is boundary-adjacent; raised
  rather than patched.

## 2026-09-12 addendum — the audit timeout that ate a 2 h 30 coverage phase

`notifications_index/_c11_pass_full.sh` (started 21:45, log `_c11_cov_full1.log`)
finished coverage in 8 962 s and then died at 01:30:12 with
`subprocess.TimeoutExpired` on `cardinality_consistency_audit`, raised at
`src/concolic_engine/completion.py:197` (`run_audits`, `timeout=1800`
hard-coded) through `completion.py:209` → `:274` (`attach_to_summary`) →
`notifications_index/coverage_report.py:596`. `coverage_summary.json` is
written at that file's line ~606, i.e. only AFTER the gate, so nothing was
written and the pass's whole result was lost. `/usr/bin/time` for the unit:
elapsed 3:44:34, max RSS 4 750 936 kB → the completion phase was
13 474 − 8 962 = **4 512 s**, of which 1 800 s was the killed audit and
**2 712 s** the four audits before it (`format_coverage`, `note_fidelity`,
`empty_relation_emission`, `noteless_call`). The audits take `{batch}` and
scan the batch DIRECTORY — **289 733 dumps** — not the pass's `DUMP_LIST`
(114 610 runs), which is why a limit that used to hold no longer does.

Landed for it:

- STAGED `completion.py` + its test (rows above).
- LIVE: `notifications_index/completion_config.json` gained
  `audit_timeout: 21600` (backup `_bak_completion_config_pre_c12.json`), so the
  gate is safe even when invoked by hand without the env var.
- LIVE, and safe: `notifications_index/coverage_report.py` now wraps
  `attach_to_summary` in `try/except` and writes the summary with the gate
  marked BLOCKING instead of dying (backup: `_bak_coverage_report_pre_c12_split.py`).
- LIVE, new: `notifications_index/_engine_section.py` — the posts_show split,
  ported. `SUMMARY_IN` / `SUMMARY_OUT`, `ENGINE_CHECKPOINT=1`, and it exports
  `ACHK_CHECKPOINT` + `ACHK_RESULTS_JSONL` (both reach `assumption_checker.py`
  through `_c11_gate_reuse.py`, which passes `dict(os.environ, …)`).
- LIVE, new: `notifications_index/_c12_rerun_after_restart.sh` — the ONE script
  the next operator runs after the restart. It refuses to start until this
  apply list is applied and both 2026-09-11 services are inactive.

**posts_show carries the same trap and its chain cannot be changed.**
`posts_show/completion_config.json` has no `audit_timeout` and two
`extra_audit_cmds` (`note_fidelity`, `empty_relation_emission`); `_p13c.sh`
stage 13c-2 runs them inside `_engine_section.py` over a **183 351-dump**
directory under the same 1800 s. Its coverage layer is already split out
(13c-1 writes `_cov_FINAL_OD0911.json` with `SKIP_COMPLETION=1`), so a timeout
there costs only the gate stage — but that stage would still die without
writing `coverage_summary.json`, and re-running it needs the applied patch
(or `audit_timeout` added to its config) to get past the same wall.

### Measured audit cost (2026-09-12), so the next limit is not a guess

Timed on `conversations_index` (18 623 dumps / 2.53 GB, avg 136 kB) and scaled
by BYTES, which is the honest scale — posts_show's dumps average 197 kB against
notifications' 135 kB:

| audit | conversations 2.53 GB | notifications 39.19 GB (289 733 dumps) | posts_show 36.07 GB (183 351 dumps) |
|---|---|---|---|
| `empty_relation_emission` | 98 s | **~25 min** | **~23 min** |
| `cardinality_consistency` | 228 s | **~59 min** (killed at 30) | not in its config |
| `noteless_call` | 59 s | ~15 min | not in its config |

The model reproduces C11 exactly: 25 + 15 min for the two big audits before the
kill plus a few minutes of `format_coverage` + `note_fidelity` = the observed
2 712 s, and `cardinality_consistency` needed ~3 550 s against a 1 800 s limit.
The live `_c7_audits.sh` run on the same directory is consistent
(`identity_symbolicity` 01:30:12→01:55:51 ≈ 26 min, `statement_note_lint`
≈ 20 min).

posts_show's `empty_relation_emission` at ~23 min sits UNDER the 1800 s wall
with only ~20 % of margin, so 13c-2 will probably survive it — but if it does
not, the crash costs the whole gate stage (its `_engine_section.py` is the
pre-checkpoint copy), not the coverage layer, which 13c-1 already wrote to
`_cov_FINAL_OD0911.json`.
