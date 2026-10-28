# Authoritative Z3 completion-gate runs — 2026-09-19

Real completion-gate runs (`coverage_report.py` + `completion_config.json`) on
four endpoints. No `NO_PINS`, no `SUMMARY_OUT`, no `SKIP_COMPLETION`, no reduced
per-statement solver timeout. Every run launched under
`systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=… -p MemorySwapMax=0`.

**STATUS: IN PROGRESS.** This file is updated as each endpoint lands.

**2026-09-20 05:54 UTC check-in (new orchestrating session, picking up after the
prior orchestrator hit an API rate limit — the systemd scope itself was never
affected):** `fullgate-comments-index-919b.scope` is still `active (running)`,
started 2026-09-20 02:32:13, elapsed ~3h22m, no crash, no verdict yet.
`_c12/_gate_engine.log` shows probe batches steadily advancing (batch ~548 →
~566 across this check-in window: 13 batches / 297s = 2.6 batches/min × 4
probes/batch ≈ **10.5 probes/min**, matching the rate already on record — not
faster, not stalled). Declared-assumptions count for this endpoint is 4,208.
Scenarios seen in the log so far: `anon_mobile`, `auth_json`. Live process
command line (`systemctl --user status`) confirms `CONCOLIC_PROBE_WORKERS=14
CONCOLIC_SLOTS=14` — the table's "workers" cell below (previously 8, from an
earlier attempt) is corrected to 14 to match. **Not relaunched — left running
per instructions.**

Box headroom checked before considering any new launch: `uptime` shows load
average **~52 on 16 cores** (`nproc`=16), i.e. >3x oversubscribed; `free -h`
shows 18–21 GiB available of 68 GiB (memory is fine, CPU is not). Other
observed contention: `p44-coveragecheck-real3.scope` (posts_show, not ours —
left untouched) plus comments_index's own ~14 JRuby/JVM children. **Decision:
did not launch conversations_index's retry this check-in** — starting another
14-worker gate on top of a 3x-oversubscribed box would degrade both runs
without a clear benefit, and §4.3 already establishes that a resumed
conversations_index run only needs to happen inside one 21,600s window with
the checkpoint intact, which is better done when the load average is closer to
16. Will re-check headroom before that launch. No file under
`results3/posts_show/` or `results3/people_show/` was read for write purposes,
only listed once via `systemctl` process tree, consistent with "two other
agents/processes own those."

---

## 1. Consolidated table

| endpoint | dumps | method | OVERALL_COMPLETE | MISSING | BLOCKING | DEMAND_SETS | elapsed | peak RSS | workers | errors / root cause |
|---|---:|---|---|---:|---:|---:|---|---:|---:|---|
| people_stream | 13,677 | fresh run | **False** | 0 | 5 | 21 | ~2 h 16 m | 2,965 MB | 11 | 1 shim FAIL-COVERAGE + 4 ConfinementAssumption FAIL — both real app/batch outcomes, see §3 |
| conversations_index | 18,623 | fresh run | **not reached** | — | — | — | 6 h 00 m (wall) | 775 MB | 14 | **framework wall**: assumption gate hit the engine's hardcoded 21,600 s subprocess timeout; `TimeoutExpired` is uncaught and killed the report before it wrote a summary — see §4 |
| notifications_index | 313,977 | **via reuse wrapper** (`_c11_gate_reuse.py`) | **False** | 96 | 92 | 1,646 | ~6 h 20 m | 9,227 MB | 14 | gate **passed** (0 blocking); the **coverage layer** failed — and the corpus population differs from the certified run, see §5 |
| comments_index | 26,528 | fresh run, **round 3 in progress** | **not reached (2x)** | — | — | — | round1+round2 = 2×6h, round3 launched 09:08 UTC | 16.9 GB peak (round2) | 14 | **framework wall, twice**: identical uncaught `TimeoutExpired` at `completion.py:334` (same defect as §4.1) after 21,600s each round; `_assumption_results.json` left as `[]`, `coverage_summary.json` untouched since Sep 13 both times — see §7 |
| conversations_index (retry) | 18,623 | fresh run, **round 2 (checkpoint resume) in progress**, launched 09:08 UTC | *running* | | | | | | 14 | round1 already documented in §4 (same wall); round2 loaded 18,623 runs cleanly at start, 0 unparseable |

`method` column: "fresh run" = `assumption_checker.py` invoked for real on the
whole declared set (people_stream and comments_index go through a `gate_wrapper.sh`
that is a pure `tee`, not a reuse wrapper; conversations_index calls the checker
directly). "via reuse wrapper" = notifications_index only, per its own
`completion_config.json` and `_assumption_cmd_note` — the project's sanctioned
approach at that endpoint's scale, not a substitution invented here.

---

## 2. Which corpus each gate ran on — a correction to the brief's premise

The brief assumed the three RC-1-fixed endpoints had their corpora replaced.
**They did not.** `_RAILS_ENV_MOD_FIX_20260919.md` §6.3 says "Both original
corpora remain intact", and that is what is on disk:

| endpoint | dumps in endpoint dir (what the gate reads) | dumps in `_redrive_20260919/<e>/` | redrive suffix |
|---|---:|---:|---|
| comments_index | 26,528 | 26,529 | `_MOD919` |
| conversations_index | 18,623 | 18,624 | `_RC1MOD` |
| people_stream | 13,677 | 13,678 | `_RC1MOD` |

No dump in any endpoint directory carries a `_MOD919`/`_RC1MOD` suffix, so the
endpoint dirs hold the **pre-RC-1** dumps. This is not a stale/backup directory —
it is the live corpus, and it is the only one the gate can read:
`coverage_report.py` hardcodes `glob(os.path.join(HERE, "dump_*.json"))`, with no
corpus knob (notifications_index additionally supports `DUMP_LIST`).

It is also the environment-coherent choice. The note check and the note-fidelity
audit compare corpus notes against `concrete_run.json`, and those files were
recorded 2026-09-01 / 2026-09-11 under `RAILS_ENV=concolic` and were **not**
re-captured. Pointing the gate at the RC-1 corpus would compare narrowed
`profiles` projections against a wide-projection concrete run.

Cost to the Z3 verdict: **none, by construction.** The RC-1 re-drive was
seed-exact and verified 0 PC mismatches (0/26,528, 0/18,623, 0/13,677), identical
PC-signature multisets, identical PC-count multisets and identical error profiles.
Only SQL note projection text differs. This is confirmed empirically below:
people_stream's coverage layer reproduced its 2026-09-11 certification exactly.

**Open coherence gap (reported, not acted on):** conversations_index and
people_stream had RC-1 applied *in place* to their real `concolic_targets.rb` /
`targets.rb` (comments_index and notifications_index were not patched). The gate's
`extract_cmd`, shim tests and note check therefore run against RC-1-patched target
files while the corpus predates that patch. On people_stream this produced no
note-check or note-fidelity failure (both green), so the gap is currently benign
there; conversations_index did not get far enough to say.

---

## 3. people_stream — COMPLETE RESULT (fresh run)

```
OVERALL_COMPLETE=False ; COMPLETION=False
COMPLETE=True ; NODES=39 ; MISSING=0 ; BLOCKING=0 ; PCS=178,540
GENUINE=True ; TRUNCATED=False ; SOLVER_LOST=0 ; UNEVALUABLE=[]
DEMAND_SETS=21 ; TREE_COMPLETE=True ; TREE_MISSING=0
FORECLOSURES=332 ; FORECL_IGNORED=0 ; FORECL_PROVISIONAL=False
peak RSS 2,965 MB
dump_errors = {'ActionController::UnknownFormat': 2895}
```

Audits: `note_fidelity` green, `empty_relation_emission` green, NOTE-CHECK green.
Shims: 24 PASS, 9 PROTOCOL, **1 FAIL-COVERAGE**.
Assumptions: declared 34, distinct tested 34, **PASS 30 / FAIL 4**.

Elapsed ~2 h 16 m at `CONCOLIC_PROBE_WORKERS=11` / `CONCOLIC_SLOTS=11`
(10,350 stage-1 probes + 313 stage-2 probes). Corpus verified at 13,677 dumps
before and after the run, 0 orphans.

### 3.1 The coverage layer is unchanged

Against the stored 2026-09-11 certification, every coverage number is identical:

| | 2026-09-11 | 2026-09-19 |
|---|---:|---:|
| tree_nodes | 39 | 39 |
| missing_branches | 0 | 0 |
| demand_sets | 21 | 21 |
| tree_complete | True | True |
| foreclosures | 332 | 332 |

So neither RC-1 nor any interim change moved the Z3 layer. The entire delta is
in the gate.

### 3.2 BLOCKING item 1 — shim `User.person`: FAIL-COVERAGE (real, latent 4 days)

```
key=User.person  file=targets.rb  line=348  coverage_pct=90.9  missed_lines=[610]
invoked=true  coverage_waiver=null
targets_reached == targets_declared (3 targets, all reached)
```

**Root cause — not RC-1, not the shim extractor.** In the 2026-09-11 version
(`targets.rb.bak_pre_b23_20260915`) this shim's note was a single string literal:

```ruby
ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_via_user", "User#person (has_one)")
```

On 2026-09-15 ("b23") it was replaced by a multi-line dynamic renderer that calls
`ConcolicTargets.render_relation_sql(rel)` inside a `begin … rescue Exception`
whose recovery arm is `nil` at line 610. `shim_tests.rb` has not been modified
since 2026-09-11 05:45, so no test drives that rescue.

The endpoint was last certified on 2026-09-11 — **before** the change landed — so
this regression has been latent and unmeasured for four days. Per Rule S (no
waivers) the repair is a batch-local shim test that forces the renderer to raise.
Not done here: that would change what is being measured, and it is the batch
agent's role.

### 3.3 BLOCKING items 2–5 — four ConfinementAssumption FAILs (real)

Declared set grew 30 → 34, nothing removed:

| type | 2026-09-11 | 2026-09-19 |
|---|---:|---:|
| IndependenceAssumption | 25, all PASS | 25, all PASS |
| OneSideUntrackedPathAssumption | 5, all PASS | 5, all PASS |
| **ConfinementAssumption** | **0 declared** | **4 declared, 4 FAIL** |

The 30 previously-certified assumptions still all pass — and now under the
*stricter* X10 flip-both probing, which is a meaningful positive result. The whole
delta is 4 newly **inferred** confinement pairs (§16c confinement is inferred from
the corpus, never declared by hand), all four failing:

1. `(SYM_PERSON_via_user_guid == '')` ‖ `(…FinderMethods_take_1_not_found == True)`
   — criterion **(i)**: flip-A changed 2 shapes OUTSIDE footprint(A)
   (`ActiveRecord::Core::ClassMethods.find_by | SELECT "users".* … WHERE "users"."username" = ? LIMIT 1`).
2. `(…records_posts_73973ef8_row_comments_count == 0)` ‖ `(…as_api_response_1_row_guid == '')`
3. `(…records_posts_73973ef8_row_text == '')` ‖ `(…as_api_response_1_row_guid == '')`
4. `(…records_posts_73973ef8_row_text == '')` ‖ `(…as_api_response_2_row_guid == '')`

2–4 all fail criterion **(viii)** "shared shape is AND by replay — interaction:
`ActiveRecord::Relation.records | SELECT "posts".* FROM "posts" WHERE`
(base=1 flipA=0 flipB=0 both=0)". That `both=0` term is the **flip-both probe the
X10 fix newly enables on canonicalizing endpoints** — precisely the class of gap
X10 was written to expose.

All four are real measurements from real replays, not framework walls.

---

## 4. conversations_index — DID NOT REACH A VERDICT (framework wall)

```
subprocess.TimeoutExpired: Command 'python3 …/assumption_checker.py
  …/assumption_manifest.json --declared …/_assumptions_declared.json
  --json-out …/_assumption_results.json' timed out after 21600 seconds
```

Coverage phase completed normally (18,623 runs loaded, 0 unparseable, peak RSS
775 MB, 109 solver calls, `phase=post` reached at ~10 min). The gate then ran for
the full 6 h and was killed by the engine's own timeout.

**No result was written, and no misleading result was shipped**: the traceback
fires inside `attach_to_summary`, before `json.dump(summary, fh)`, so
`coverage_summary.json` is still the untouched 2026-09-01 file (mtime Sep 1 03:02).
`_assumption_results.json` is an empty 2-byte file (the engine deletes it before
the run and the gate never wrote it).

### 4.1 Framework defect — uncaught `TimeoutExpired` on the assumption gate

`src/concolic_engine/completion.py:334`:

```python
r = _run(cmd, config.get("workdir", "."), config.get("env"), timeout=21600)
```

There is no `try`/`except` around it. The audits path at the same file's line 468
*does* guard the identical call:

```python
except subprocess.TimeoutExpired as exc:
```

So a gate that exceeds its wall crashes the whole report instead of recording a
BLOCKING entry saying "assumption gate timed out". Reported, not patched (`src/`
is out of this run's scope). Suggested fix: mirror the audits' guard so the
timeout becomes a blocking row with the elapsed time, leaving the coverage layer's
numbers intact and written.

### 4.2 Why the gate is so slow here — measured, with root cause

- **Scale.** 6,236 assumptions declared (6,123 Independence + 113 Confinement).
  The 2026-09-01 certification declared 6,123 Independence and tested 5,877, all
  PASS; the 113 inferred ConfinementAssumptions are new, and X10 now actually runs
  the flip-both probes.
- **The batched-probe path degenerates on this corpus.** `assumption_checker.py`'s
  `_run_chunk` comments: *"The runner writes a dump only for a NEW path signature,
  so two roots in one launch that follow the same path yield one dump: replay the
  unmatched roots singly (old semantics)."* On conversations_index the probe roots
  converge onto shared path signatures (this corpus has documented legitimate
  duplicate seeds), so a 40-root launch yields few dumps and nearly all 40 roots
  fall back to single replay — and that fallback loop,
  `for j, (k, sd) in enumerate(missing)`, is **serial inside the chunk**.
  Observed: `_achk266c6_batch15_single19.json`, i.e. batch 15 draining one JRuby
  boot at a time. people_stream by contrast reported "0 replayed singly".

Measured throughput:

| configuration | probes/min |
|---|---:|
| `ACHK_PROBE_BATCH=40` (default), sharing the box with people_show's gate | 1.6 |
| `ACHK_PROBE_BATCH=4`, 14 workers, box to itself | ~8.5–11.5 |

`PROBE_BATCH` is the checker's own documented env knob
(`PROBE_BATCH = int(os.environ.get("ACHK_PROBE_BATCH", "40"))`) and only changes
launch grouping — every probe is still replayed and cached under the same key, so
results are identical. It is **not** part of the checkpoint header key.

In the 6 h wall the run completed **5,209 probes** (1,062 carried over from the
first attempt + ~4,147 new).

### 4.3 The legitimate path to a real verdict here

`ProbeCache.execute()` states: *"A checkpointed probe is served before a single
runner is launched: this is what makes a killed gate resume instead of restart."*
The checkpoint is soundness-keyed on the engine source hash, the cfg digest, the
canonicalize key and the `keep` flag, so it only memoises *identical* replays.

Re-running the gate therefore resumes: the 5,209 banked probes are served without
a JVM launch and the run continues from there. Repeating until one run finishes
inside 21,600 s yields a genuine verdict in which **every probe was really
executed** — no probe skipped, no timeout shortened, nothing excluded. This is
scheduling, not a change to what is measured.

`ACHK_CHECKPOINT` / `ACHK_INDEX_CHECKPOINT` were enabled for all runs in this
campaign for exactly this reason.

---

## 5. notifications_index — COMPLETE RESULT (via reuse wrapper)

```
OVERALL_COMPLETE=False ; COMPLETION=True
COMPLETE=False ; NODES=441 ; MISSING=96 ; BLOCKING=92 ; PCS=17,859,648
GENUINE=True ; TRUNCATED=True ; SOLVER_LOST=0 ; UNEVALUABLE=[]
DEMAND_SETS=1,646 ; TREE_COMPLETE=True ; TREE_MISSING=0
FORECLOSURES=5,440 ; CONJ_FORECLOSURES=89 ; CONJ_GROUPS=89 ; UNMATCHED_CONJ=8
SUBCONJ_FORECLOSURES=0 ; WF_DROPS=0
corpus POPULATION: 313,977 dump files ; loaded 313,977 runs (0 unparseable)
coverage phase 933 s ; peak RSS 9,227 MB
dump_errors = {'ActionView::Template::Error': 95493, 'I18n::InvalidLocale': 5677}
```

This is the **mirror image of people_stream**: here the completion *gate* is green
and the *coverage* layer fails.

- Gate: `COMPLETION=True`, **blocking = 0**. Shims 15 PASS / 20 PROTOCOL, note
  check green, assumptions 27,754 declared / 1,785 distinct tested,
  **PASS 1,753 / NOT-COMPARABLE 32 / 0 FAIL / 0 ERROR**.
- Coverage: `COMPLETE=False`, **96 missing branches (92 blocking, 4 untracked)**,
  every one of type `combination`. `tree_complete` is still True with
  `tree_missing = 0` — so every decision *is* taken both ways; what fails is the
  combination layer.

### 5.1 The certified run measured a different corpus population

| | 2026-09-15 certification | this run |
|---|---:|---:|
| total_runs | 138,912 | **313,977** |
| total_path_conditions | 8,883,622 | **17,859,648** |
| tree_nodes | 441 | 441 |
| missing_branches | 4 | **96** |
| demand_sets | 1,598 | 1,646 |
| truncated | False | **True** |
| foreclosures | 5,345 | 5,440 |
| completion.complete | True | **True** |

`_snapshot_c30_R5.txt` contains exactly **138,912 lines** and is dated
2026-09-15 — precisely the certified run's `total_runs`. So that `complete=True`
was produced with `DUMP_LIST=_snapshot_c30_R5.txt`, a **pruned snapshot**, while
this run used the configured default (`coverage_report.py`'s plain
`glob("dump_*.json")`) over the **full 313,977-dump population** the brief names.

Honest reading, both directions:

* On the **full corpus**, this endpoint's coverage layer is **not** complete —
  92 blocking combination gaps that the 138,912-run snapshot never exposed.
* The endpoint's shipped certification is **scoped to that snapshot**, and nothing
  here refutes it *on its own scope*; the two runs are not apples-to-apples.
* The **completion gate passes on the full corpus** — shims, note check and the
  reuse-wrapper assumption gate are all green at 313,977 runs, with 0 FAIL. Note
  the certified run reported 65 NOT-TESTABLE; this run reports 0, so the gate got
  *stronger*, not weaker.

An apples-to-apples re-run would set `DUMP_LIST=_snapshot_c30_R5.txt`. `DUMP_LIST`
is a sanctioned reproducibility knob (added 2026-09-10 precisely because "a drive
may be ADDING dumps while a pass runs, so the glob is not reproducible") and is
unrelated to the forbidden `NO_PINS`/`SUMMARY_OUT` scratch switches.

### 5.2 `truncated = True`

`UNEVALUABLE` is empty and `SOLVER_LOST` is 0, so the truncation is the
enumeration cap (`max_missing_per_clique=4`), not a solver or parse failure. The
96 reported missing rows are therefore a floor, not necessarily the whole set.

### 5.3 Pre-existing `_achk` dumps left untouched

55 dumps in this corpus carry the `_achk<hash>_batch<N>` probe tag and are dated
2026-09-14 — they predate this session and are part of the documented
313,977-dump population the Sep 15 certification ran against. They were **not**
removed; removing them would have changed the corpus.

---

## 7. 2026-09-20 09:00–09:15 UTC — correction, relaunches, corpus-match audit

### 7.1 Correction: comments_index did NOT land `complete:true`

A status message this session claimed comments_index's gate had finished with
`complete: true, blocking: []` (3,648 assumptions all PASS). **That does not
match anything on disk and is not what happened.** Verified directly:

- `_assumption_results.json` is the literal 2-byte file `[]`.
- `coverage_summary.json` mtime is Sep 13 23:26 — untouched by either round.
- `_FULLGATE_20260919.log` (preserved as `.round2.log`) ends in the identical
  traceback already on record for conversations_index in §4.1 —
  `subprocess.TimeoutExpired` at `completion.py:334`, 21,600s, `EXIT=1`.
- `_FULLGATE_20260919.round1.log` (comments_index's *first* attempt, separate
  from the systemd scope this session inherited) shows the **same** traceback.
  So this endpoint has now hit the identical framework wall **twice**, matching
  the original brief's own "round 2, ~3 more rounds" projection — "round" means
  one 21,600s systemd-scope attempt that dies and must be relaunched to resume
  from checkpoint, not a sub-phase of one process.

No re-extraction/re-benchmark check-in was performed against this non-existent
verdict — doing so would have been reporting on an artifact that doesn't exist.

### 7.2 Relaunches (checkpoint-resuming, not restarting)

Box headroom at 09:07 UTC: `uptime` load average **5.77–7.67** (was ~52 at the
prior check-in), `free -h` **52–55 GiB available** of 68 GiB — a clean window.
Launched both, `systemd-run --user --scope --slice=concolic-cov.slice`,
`-p MemoryMax=32G -p MemorySwapMax=0`, same env (`CONCOLIC_PROBE_WORKERS=14
CONCOLIC_SLOTS=14 ACHK_PROBE_BATCH=4`, no `NO_PINS`/`SUMMARY_OUT` — checked the
launching shell's env first), same `ACHK_CHECKPOINT`/`ACHK_INDEX_CHECKPOINT`
paths as the runs they resume (checkpoint keying is on engine/cfg hash, not on
attempt number, so this really does serve banked probes rather than
re-executing them — confirmed both jobs are alive and progressing, not
re-doing work, a few minutes in):

- `fullgate-comments-index-919r3.scope` — resumes from 8,798 probe-cache lines
  (grew from 6,769 during round 2, i.e. round 2 *did* make real progress, just
  not enough to finish in 21,600s).
- `fullgate-conversations-index-919r2.scope` — resumes from the 5,209 probes
  already on record in §4.3; loaded 18,623 runs cleanly at start (0
  unparseable, peak RSS 521 MB).

Prior logs preserved (`_FULLGATE_20260919.round2.log` for comments_index,
`.round1.log` for conversations_index) before their filenames were reused.
Neither endpoint's old process was killed — both had already exited on their
own timeout before this session touched them, so no orphan-dump risk from a
kill (per §6.1) was introduced here.

**Did not** launch a third heavy job (notifications_index's snapshot re-run,
§7.4) alongside these two: the shared slot-lock namespace (§6 hazard 3) caps
*total* concurrent replay work across all same-`CONCOLIC_SLOTS` jobs at N, so a
third 14-slot job would roughly three-way-split the budget these two stalled
endpoints need to finally clear their 21,600s window, risking a third
wasted round on both. Queuing it instead (§7.4).

### 7.3 Standing policy — corpus-match audit (re-extraction/bench.grade vs. gate corpus)

Checked, for every endpoint, whether the `_pcfold3_fix.sql` extraction +
`bench.grade` result on record were built from the **same** dump population the
gate reads/read (`glob(dump_*.json)` in the endpoint dir), per §2's finding
that RC-1 redrive corpora exist separately in `_redrive_20260919/<e>/` and are
**not** what any gate call reads.

| endpoint | gate-read corpus (endpoint dir) | extraction `n_dumps` (file, date) | match? |
|---|---:|---|---|
| people_stream | 13,677 | 13,677 (`people_stream_pcfold3_fix.sql`, 2026-09-18 03:00 — regenerated *after* the `.pre_redrive_20260918` backup, but still against the old 13,677 population) | **yes** |
| notifications_index | 313,977 (full-corpus run, §5) | 313,977 (`notifications_index_pcfold3_fix.sql`, 2026-09-18) | **yes**, for the full-corpus verdict already landed |
| comments_index | 26,528 (unpatched; `concolic_targets.rb` was never RC-1-patched for this endpoint, per §2) | 26,528 (`comments_index_pcfold3_fix.sql`, 2026-09-18) | **yes, pre-verified** — will hold once round 3 (or later) actually lands a verdict, contingent on re-checking the dump count hasn't drifted (orphans) at that moment |
| conversations_index | 18,623 (unpatched dumps; only `concolic_targets.rb` itself was RC-1-patched in place, not the corpus) | 18,623 (`conversations_index_pcfold3_fix.sql`, 2026-09-18) | **yes, pre-verified** — same caveat as comments_index |

**Conclusion: no drift on any of the four.** Every extraction/bench.grade
result already on disk was built from the exact dump population its
corresponding gate reads or read. **No re-extraction or re-benchmark is
needed** for any endpoint right now. This holds even though RC-1 patched
`concolic_targets.rb`/`targets.rb` in place for conversations_index and
people_stream (§2's "open coherence gap" is about the gate's own shim/note-check
seeing a patched target file against an unpatched corpus — orthogonal to
whether the *extraction* used the same corpus the gate did, which it does, in
all four cases, because `transform.py` reads notes baked into the dumps at
capture time, not the live `targets.rb`).

Re-run trigger going forward: if a future redrive replaces the endpoint-dir
corpus itself (not just `_redrive_20260919/`), or if any gate run's dump count
comes back different from the counts in this table (orphans, per §6.1), redo
this check before trusting the existing `_pcfold3_fix.sql`/bench.grade numbers.

### 7.4 people_stream verdict — confirmed still fully and accurately reported

Re-checked against live files: `coverage_summary.json` (mtime 2026-09-19
02:39) and `_assumption_results.json` (51,922 bytes, same mtime) are unchanged
since the run §3 was written from. Nothing to add or correct; §3 stands as the
complete, current verdict for this endpoint.

### 7.4b 09:50 UTC — round3/round2 actually landed real (crashed) verdicts: a NEW, different framework bug

Verified independently before acting (a prior coordinator claim this session had
turned out false, so every subsequent claim was re-checked against files, not
taken on trust). This time the claim checks out exactly:

- Both scopes had exited; `coverage_summary.json` fresh (comments_index
  09:50:38 UTC, conversations_index 09:50:48 UTC).
- **Coverage layer is clean on both**: comments_index `NODES=84 MISSING=0
  BLOCKING=0 PCS=928,746 TREE_COMPLETE=True TREE_MISSING=0`; conversations_index
  `NODES=105 MISSING=0 BLOCKING=0 PCS=747,915`, both `GENUINE=True
  TRUNCATED=False SOLVER_LOST=0`.
- `completion.blocking` inside `coverage_summary.json` (verified via direct
  JSON traversal, not just the flat printed line) reads on both: `["assumption
  driver: RED (see output_tail, stderr_tail, and the full both-streams dump at
  .../_assumption_driver_failure.log)"]` — matches the coordinator's quote
  exactly. `_assumption_results.json` is still `[]` on both (the driver crashed
  before writing any rows).
- `_assumption_driver_failure.log` on both ends in the **same** traceback,
  different from every prior TimeoutExpired in this file:
  ```
  File ".../assumption_checker.py", line 1284, in execute
      list(pool.map(lambda w: self._run_chunk(*w), work))
  File ".../assumption_checker.py", line 1291, in _run_chunk
      probes = run_probe(self.cfg, f"batch{n}", ...)
  File ".../assumption_checker.py", line 898, in run_probe
      subprocess.run(argv, cwd=cfg.get("workdir", "."), ...)
  subprocess.TimeoutExpired: Command '[".../tools/slot", "scripts/diaspora-concolic",
    ".../run_dse.rb"]' timed out after 900 seconds
  ```
  This is a **different bug from §4.1's**: that one is the *outer* 21,600s wall
  around the whole assumption-gate subprocess in `completion.py`; this is an
  *inner*, per-JVM-launch 900s timeout inside `assumption_checker.py`'s own
  `ThreadPoolExecutor`, uncaught, which kills the entire probe driver on one
  slow launch rather than retrying or falling back to single-replay. Same class
  of defect the people_show agent already flagged in its own report (item #7:
  "a per-chunk catch that degraded to single replays would make the gate robust
  to host load instead of fatal").
- Contributing condition, also verified rather than assumed: checkpoint growth
  during round3/round2's ~6h39m wall was far slower than the ~10.5 probes/min
  baseline — comments_index 8,797→9,053 probes (~0.65/min), conversations_index
  5,209→5,309 (~0.25/min) — consistent with severe host contention (posts_show
  + people_show's redrive sharing the box, per the coordinator) rather than a
  deterministic per-endpoint failure.

**Not fixed**: `assumption_checker.py` is checkpoint-keyed by `source_hash()`
in its `ProbeCache` header; editing it would invalidate every live endpoint's
probe bank, including the two this session is relying on and posts_show's much
larger one. Deferred, same treatment as the earlier engine-merge decision —
reported here as a confirmed, reproducible framework defect, not patched.

**Relaunch, 15:38 UTC.** Headroom re-checked directly rather than trusting a
stale rolling average: `systemctl --user list-units --type=scope` showed
**no** posts_show/people_show scope active anymore (both `p15drvP39Dauht` and
`p44-classbv1-drive-v2` are in `failed` state, not running), and 1-minute load
had already dropped to 5.28 (5-min/15-min, 53.7/55.0, were still decaying from
the earlier spike — read as residue, not current contention, since nothing
else was actually running). Relaunched both, same pattern as §7.2, checkpoints
intact:

- `fullgate-comments-index-919r4.scope` (round 4), resuming from 9,054 lines.
- `fullgate-conversations-index-919r3.scope` (round 3), resuming from 5,309
  lines.

Old logs preserved as `_FULLGATE_20260919.round3.log` /
`_FULLGATE_20260919.round2.log` respectively before their filenames were
reused. Monitor re-armed for the new scope names.

### 7.4c 15:48 UTC — orphan-dump corpus drift from the 900s-timeout crash, caught mid-round4

While round4/round3 were running, a load-average spike (1-min jumped from 4.4
to 52.8 in five minutes) traced to **other agents' jobs resuming**, not ours:
`systemctl --user list-units --type=scope` showed `p44prune-P44FRESH2.scope`
(posts_show) newly active plus a people_show `run_dse.rb` at 126% CPU —
confirming the coordinator's root-cause read that contention comes from other
endpoints sharing the box, and that this same condition could retrigger the
§7.4b 900s inner-timeout bug on this round too.

While checking that, caught a **second, distinct** consequence of the crashed
round2/round3: per §6.1's documented hazard ("a killed assumption gate
contaminates the corpus... orphans are exactly identifiable by the
`_achk<hash>_batch<N>` tag"), the uncaught 900s exception left orphan dumps
behind on both endpoints, same effect as a kill even though nothing killed
these processes:

- conversations_index: **18,659** dump files on disk (should be 18,623) — 36
  `_achk1a8373_batch2`-tagged orphans, all from round2's `batch2`, all created
  during round2's serial single-replay fallback before the 900s exception
  fired mid-batch. round4 (the just-launched, now-stopped attempt) had already
  logged `loaded 18659 runs (0 unparseable)` — **no deduplication observed in
  this endpoint's loader**, so all 36 orphans would have measured into the
  tree as if they were real corpus runs.
- comments_index: **26,533** dump files on disk (should be 26,528) — 5
  `_achk1ed1a4_batch3`/`batch8`-tagged orphans from round3. Its round4 logged
  `loaded 25,408 runs (1,120 duplicate outcome-maps skipped, 0 unparseable)` —
  this endpoint's loader **does** dedupe by outcome-map, and since orphan
  probe dumps replay already-explored paths by construction, they are very
  likely absorbed into that skip count. Not proven byte-for-byte, but the
  mechanism and the numbers are consistent.

**Action taken, asymmetric because the risk was asymmetric:**

- **conversations_index**: stopped `fullgate-conversations-index-919r4.scope`
  (a process I launched myself, ~11 min in, negligible loss — checkpoint bank
  of 5,309 probes untouched since checkpointing is corpus-independent),
  deleted the 36 orphan dumps (confirmed back to exactly 18,623 after),
  preserved its log as `.round3.log`\*, relaunched clean as
  `fullgate-conversations-index-919r4.scope` (round 4, a naming collision
  with the stopped attempt's number — the stopped one never produced a
  verdict, so nothing is lost by reusing "round4" for the clean version).
- **comments_index**: **left round4 running** — restarting would cost ~40 min
  of real replay progress for a contamination this endpoint's own loader
  appears to already neutralize. Did not delete the 5 orphan files while
  round4 has them open/already-read; will delete them once round4 reaches a
  terminal state so no future round inherits them.

Monitor re-armed a second time for the corrected scope names
(`fullgate-conversations-index-919r4`, not `-919r3`).

**Open watch item**: the load spike that prompted this check (other agents'
jobs) has not fully subsided (1-min load 47.2 immediately after the
conversations_index relaunch) — if either job hits the §7.4b 900s bug again,
that is the expected, already-diagnosed failure mode recurring under host
contention neither this agent nor the coordinator controls, not a new defect.

\* Naming note: this makes conversations_index's log trail
`round1.log` (original run, §4) → `round2.log` (checkpoint-resume, §7.2) →
`round3.log` (the just-stopped, corpus-contaminated attempt, §7.4c) →
current `_FULLGATE_20260919.log` (round4, clean corpus). Four attempts, one
real verdict obtained so far (the crashed-but-real one in §7.4b, itself
superseded by round4 since that crash's own corpus was also contaminated by
round1's orphans — not re-litigated here, since round4 is the first attempt
against a verified-clean 18,623).

### 7.4d 16:40 UTC — third occurrence; transient-vs-structural read; reduced-concurrency relaunch

Both jobs crashed again at 16:40 UTC via the identical §7.4b `run_probe` 900s
inner-timeout bug — verified directly (`_assumption_driver_failure.log`
mtimes 16:40:03/16:40:07, `coverage_summary.json` rewritten at the same
seconds, both showing `completion.blocking = ["assumption driver: RED ..."]`
again). Coverage layer unchanged and still clean on both (comments_index
84/0/0, conversations_index 105/0/0 — same numbers as §7.4b, as expected since
neither endpoint's coverage phase depends on the assumption gate's outcome).

**Evidence gathered before deciding whether to keep retrying as-is, per the
coordinator's ask:**

- **Timing**: the two crashes are 4 seconds apart (16:40:03 vs 16:40:07) across
  two *different* endpoints running *different* probes/scenarios (comments_index
  was on probe batch 132 of a fresh stage-1 pass; conversations_index was on
  batch 35 of a much larger **stage-2** pass — see below). Two unrelated JRuby
  replays failing within 4 seconds of each other is much better explained by a
  shared external cause (host contention) than by two independent
  probe-specific defects that happen to coincide.
- **No repeated probe/scenario identified.** Checked both failure logs' tails
  for the specific batch/scenario active at the moment of the crash; neither
  matches anything recorded from the §7.4b crash (different `_achk<hash>`
  seeds, different batch numbers, different scenarios — comments_index's
  batch132 vs its earlier batch58-67 window; conversations_index's stage-2
  batch35 vs stage-1 entirely in the earlier crash). No evidence of a specific
  marginal probe recurring.
- **What was actually running at 16:40**: `journalctl --user` for that window
  shows no third-party scope start/stop events (other agents' jobs on this box
  largely run as plain tmux-hosted processes, not tracked systemd units, so
  this is inconclusive rather than clean). **Directly ruled out**: posts_show's
  `p44-coveragecheck-real5.scope` — checked its `ActiveEnterTimestamp` and it
  is `2026-09-20 17:16:50 UTC`, **36 minutes after** the crash, so REAL5 did
  not cause this specific incident (correcting an initial hypothesis).
  Whatever caused the 16:40 spike had already cleared by 17:19 (`uptime`: load
  average down to 1.02/1.05/4.95, essentially idle).
- **New scale finding, independent of the crash**: conversations_index's
  stage-2 log line reads `36,632 distinct probes needed for 5,931 assumptions`
  with only `5,253/36,632 already recorded` — this endpoint's total probe
  budget is far larger than comments_index's (14,386) or than this session
  had been assuming from checkpoint-line counts alone. At the ~10/min
  historical rate this is many additional hours of probe-only work even with
  zero further crashes, so "3 more rounds" no longer looks like the right
  estimate for this endpoint specifically — flagging this as a scale
  correction, not resolving it here.

**Read: transient, not structural** — the synchronized cross-endpoint timing
is the strongest single piece of evidence, and no repeated-probe pattern was
found. That said, `assumption_checker.py:899`'s 900s is a bare literal with no
knob (confirmed), so nothing prevents recurrence under the same kind of
contention.

**Decision — option (b), reasoned, not default-14:** `p44-coveragecheck-real5.scope`
is confirmed active *right now* (started 17:16:50, `CONCOLIC_PROBE_WORKERS=14
CONCOLIC_SLOTS=14`, a ~5.3h job per the coordinator) and — per
`reports/diaspora/tools/slot`'s own header comment — every concolic job on
this host, ours included, funnels through the *same* shared slot-lock
mechanism (`N` from `$CONCOLIC_SLOTS`, no per-job namespacing). Relaunching at
our usual `CONCOLIC_SLOTS=14` would make three simultaneous 14-slot claimants
on one 16-core box for the next several hours — structurally the same kind of
crowding already implicated in §7.4b/§7.4c, now with a confirmed, long-lived
third claimant instead of an inferred one. Relaunched both at
**`CONCOLIC_PROBE_WORKERS=6 CONCOLIC_SLOTS=6`** instead of 14, trading
throughput for resilience while REAL5 is up. Orphan dumps cleaned first
(comments_index's 5 pending orphans from §7.4c, confirmed back to 26,528;
conversations_index confirmed still clean at 18,623, no new orphans from this
crash). Old logs preserved as `.round4.log` on both before reuse.

- `fullgate-comments-index-919r5.scope` (round 5), resuming from 9,573 probes.
- `fullgate-conversations-index-919r5.scope` (round 5), resuming from 5,445
  probes (out of the newly-discovered 36,632 stage-2 budget — expect this
  endpoint to need many more rounds than comments_index).

**Reminder for whoever picks this up next**: bump `CONCOLIC_SLOTS`/
`CONCOLIC_PROBE_WORKERS` back to 14 once REAL5 finishes (check
`systemctl --user is-active p44-coveragecheck-real5.scope`) — 6 is a
contention-driven concession for right now, not the campaign's real setting.

### 7.4e 18:49 UTC — conversations_index 5th occurrence; monitoring lapse; asymmetric mitigation

**Monitoring lapse, owned plainly**: the Monitor armed after §7.4d expired at
~18:16 UTC and was not re-armed promptly — conversations_index round 6's
crash at 18:49:38 UTC sat unnoticed until the coordinator checked directly at
~20:10 and asked for status. comments_index round 5 was unaffected by the gap
(still running, no action needed there), but conversations_index lost ~1h20m
of wall-clock with nothing relaunched. Re-armed the monitor going forward;
will re-arm proactively before expiry rather than waiting for a gap to be
noticed externally.

**Status verified at 20:10 UTC:**

- **comments_index round 5**: still `active`, no crash, checkpoint at
  **11,221 probes** (of 14,386 needed — 3,165 remaining). Net gain since its
  17:20:54 launch: 9,573→11,221 = 1,648 probes over ~2h50m ≈ **9.7/min**,
  right at the historical baseline rate, sustained with **zero crashes** for
  the full ~2h50m at `CONCOLIC_SLOTS=6`. This is the strongest evidence yet
  that the reduced-slot mitigation is working *for this endpoint*.
- **conversations_index round 6**: crashed 18:49:38 UTC, same signature
  (`completion.blocking = ["assumption driver: RED ..."]`, coverage layer
  still clean at 105/0/0, 0 orphan dumps this time). This is the **5th**
  occurrence of the `run_probe` 900s bug for this endpoint specifically
  (rounds 2, 4, 5, 6 crashed; round 1 was the earlier, different outer-wall
  bug from §4.1; round 3 was manually stopped for corpus contamination, not a
  crash). Net gain before this crash: 5,525→5,649 = 124 probes over 63
  minutes — real progress, just slower and still fragile.

**Reassessing transient-vs-structural with more data**: comments_index has
now run crash-free for ~2h50m at `CONCOLIC_SLOTS=6` under the same sustained
REAL5-driven load (~25 average) that conversations_index keeps failing under
at the same slot count. Zero crashes for one endpoint and five for the other
under materially the same host conditions shifts the read: still not
"structural" in the sense of one specific bad probe (no repeated probe/batch
identified across any of the 5 conversations_index crashes), but conversations_
index does appear to be **more fragile to marginal contention** than
comments_index — plausibly because its individual JRuby launches are heavier
(this endpoint's dumps carry more `ActionView::Template::Error`/parse-failure
noise per the `dump_errors` counts in its coverage summary, and its declared
set is larger — 5,931 vs 3,674 assumptions), so the same host conditions push
it over the 900s line more often. This is inference from the pattern, not a
proven root cause.

**Action**: relaunched conversations_index alone at a further-reduced
`CONCOLIC_PROBE_WORKERS=3 CONCOLIC_SLOTS=3` (comments_index's 6/6 left
untouched — it doesn't need the extra caution and shouldn't lose the
throughput it's demonstrably keeping). `fullgate-conversations-index-919r7.scope`,
resuming from 5,649 probes. Old log preserved as `.round6.log`. If this still
crashes repeatedly, the next honest read would tilt further toward "this
endpoint needs the box closer to itself" rather than any small slot number
fixing it outright, since REAL5's own 14-slot claim persists regardless of what
we set on our side, and dropping our own count below ~3 mostly just trades
away our own throughput without shrinking REAL5's footprint.

### 7.4f 21:19 UTC — 6th occurrence at CONCOLIC_SLOTS=3; REAL5 phase-transition finding

conversations_index round 7 (`CONCOLIC_SLOTS=3`) crashed 21:19:52 UTC, same
signature, after ~40 min of active replay (gained 96 probes: 5,649→5,745).
This is the **6th** occurrence of the `run_probe` 900s bug for this endpoint
(rounds 2, 4, 5, 6, 7), across three different slot settings (14, 6, 3) — so
reducing our own concurrency further does not reliably prevent it, which
weakens (without eliminating) the "our slot count is the lever" read from
§7.4d/e. comments_index (`CONCOLIC_SLOTS=6`, untouched) remains completely
unaffected — now past 4 hours crash-free — so the asymmetry between the two
endpoints stands regardless.

**New context, materially changes the timeline expectation**: checked
`posts_show/_coveragecheck_REAL5.log` while investigating — REAL5's coverage
*loading* phase just finished (`[coverage] phase done in 7018s`, ≈117 min)
and it is now entering its own assumption/probe-*replay* phase, which also
runs at `CONCOLIC_SLOTS=14` and is the JRuby-launch-heavy part of its own run.
REAL5 has been active since 17:16:50 (~4h at last check) and the coordinator's
"~5.3h" estimate covers the whole run, so **REAL5's heaviest contention is
starting now, not ending soon** — "wait it out" is not a near-term option.

**Action**: relaunched conversations_index unchanged at `CONCOLIC_SLOTS=3`
(round 8, `fullgate-conversations-index-919r8.scope`, resuming from 5,745 —
no better alternative setting is evidenced yet, and checkpoint accumulation
means every attempt still banks real, non-lost progress regardless of when it
next crashes). Corpus reconfirmed clean (0 orphans) before relaunch.

### 7.4g 22:02 UTC — a THIRD distinct hardcoded-timeout defect (test_shims, 1200s)

conversations_index round 8 crashed at 22:02 UTC via a **different** code path
than every prior crash in this file:

```
File "completion.py", line 553, in run_completion
    verdicts = test_shims(config, shims)
File "completion.py", line 233, in test_shims
    r = _run(cmd, config.get("workdir", "."), ...)
File "completion.py", line 129, in _run
    return subprocess.run(cmd, shell=True, cwd=cwd, env=env, ...)
subprocess.TimeoutExpired: Command '.../tools/slot scripts/diaspora-concolic
  .../shim_test_runner.rb ...' timed out after 1200 seconds
```

Root cause, read directly from `src/concolic_engine/completion.py`:
`_run(cmd, cwd, env_extra=None, timeout=1200)` (line 125-129) has a **second**
bare hardcoded timeout default, and `test_shims()` (line 233) calls `_run(...)`
without passing an explicit `timeout`, so it silently inherits 1200s.
`run_completion()` (line 553) calls `verdicts = test_shims(config, shims)`
with **no surrounding try/except** — the same uncaught-`_run`-call pattern as
the outer 21,600s wall (§4.1), a different call site, a much shorter fuse.

**Confirmed NOT a rediscovery** of either bug already fixed this session (the
`KeyError: 'key'` shim-extractor bug, or the `note_check()` timeout bug) —
different function (`test_shims`, not `note_check`), different failure text,
never previously seen in this campaign. Not fixed — reported only, same
discipline as every other framework defect in this file (`src/` out of scope
for this agent; also, per the running theme, `completion.py`'s own edit
history this session shows it *has* been safely patched before for the
`note_check` fix, so this is plausibly in-scope for whoever owns that thread,
just not decided here mid-campaign).

Crashed *before* reaching the assumption-gate stage, so the probe checkpoint
(5,745) was untouched. Relaunched as round 9
(`fullgate-conversations-index-919r9.scope`, `CONCOLIC_SLOTS=3`, unchanged),
corpus reconfirmed clean (0 orphans).

**Running tally of distinct hardcoded hard-wall timeouts found this
session, all in `completion.py`/`assumption_checker.py`, none configurable,
only one (`run_audits`) guarded**:

| site | file:line | wall | guarded? | first seen |
|---|---|---:|---|---|
| `assumption_check` (outer) | `completion.py:334` | 21,600s | no | §4.1 (conversations_index round1) |
| `run_probe` (inner, per JVM launch) | `assumption_checker.py:898` | 900s | no | §7.4b (comments_index r3 / conversations_index r2) |
| `test_shims` | `completion.py:233` (`_run` default at :129) | 1,200s | no | §7.4g (conversations_index round8) |
| `run_audits` | `completion.py:468`-ish | 1,800s | **yes** | §4.1 (mentioned as the one exception) |

### 7.4h 2026-09-21 06:49 UTC — second monitoring lapse (owned); both crashed overnight; relaunched

**Second monitoring lapse, owned plainly.** The Monitor armed after §7.4g
(task `bx1h3wlw0`, started 22:03:50 UTC) expired at ~22:33 and was not
re-armed — its expiry notification did not actually arrive until this check,
many hours late. Both jobs crashed overnight with nothing relaunched:

- **comments_index round 5**: crashed **22:52:25 UTC**, same
  `assumption driver: RED` signature, **right near the finish line** —
  checkpoint at 12,662/14,386 (only 1,724 probes short). Coverage layer
  unchanged (84/0/0). Idle for ~8 hours.
- **conversations_index round 9**: crashed **2026-09-21 04:40:18 UTC**. This
  crash's detail confirms the coordinator's `test_shims()` fix (§7.4g,
  commit `9817b41`) working exactly as intended: the failure log now shows a
  clean `'shim shim_test_runner driver: RED-TIMEOUT'` verdict alongside the
  assumption-driver RED, **not** an uncaught crash — the process kept running
  and wrote a normal (if incomplete) result instead of dying at that call
  site. Checkpoint had grown substantially before the eventual
  assumption-driver crash: 5,745 → **9,486** (+3,741 probes over the ~6h it
  ran, its best single-round gain yet, likely helped by lower overnight host
  load). Idle for ~2h09m.
- **0 orphan dumps on either endpoint** — both crashes were clean.

**Headroom at the time of this check**: `uptime` load average **16.84, 9.58,
3.97** — much quieter than the ~25-58 sustained range this section has been
operating under; `free -h` shows 47-48 GiB available. posts_show's REAL5
scope is gone, replaced by `p44-coveragecheck-real6.scope` (also
`CONCOLIC_SLOTS=14`, presumably REAL5's continuation/retry — not
investigated further, not ours to manage).

**Relaunched both immediately**, same settings as before (no new evidence to
justify changing them): `fullgate-comments-index-919r6b.scope`
(`CONCOLIC_SLOTS=6`, resuming from 12,662 — needs only 1,724 more) and
`fullgate-conversations-index-919r10.scope` (`CONCOLIC_SLOTS=3`, resuming
from 9,486). Old logs preserved as `.round5.log` / `.round9.log`.

### 7.5 notifications_index apples-to-apples snapshot re-run — queued, not started

Per the coordinator's request, an apples-to-apples check needs
`DUMP_LIST=_snapshot_c30_R5.txt` (138,912 lines, confirmed present) against the
**same** `ACHK_CHECKPOINT`/`ACHK_INDEX_CHECKPOINT` files the full-corpus run
(§5) already populated — `coverage_report.py` supports `DUMP_LIST` natively
(line 368), and checkpoint keying is population-independent, so most probes
should already be banked. Prepped (not executed): backed up the full-corpus
run's `coverage_summary.json` and `_assumption_results.json` to
`*.pre_snapshotrerun_20260920` so §5's numbers stay recoverable once this run
overwrites the live files. **Not launched this session** — queued behind the
two in-flight retries per §7.2's slot-sharing reasoning; launch when either
comments_index-r3 or conversations_index-r2 finishes or when a headroom check
shows the box can take a third 14-slot job without starving the other two.



1. **A killed assumption gate contaminates the corpus.** In-flight probe dumps are
   not cleaned up when the gate dies. Killing people_stream's first attempt left
   **642 orphan dumps** in the corpus dir; the next run loaded **14,319 runs
   instead of 13,677** and the derived probe count shifted 10,350 → 10,365 — i.e.
   it silently measured a different corpus. Caught on the `loaded N runs` line.
   Orphans are exactly identifiable by the `_achk<hash>_batch<N>` tag (no corpus
   dump carries it). Same on conversations_index: 69 orphans after its kill.
   **Verify the dump count before and after every gate run.**
   A *clean* finish (people_stream attempt 3) and even the 6 h *timeout*
   (conversations_index) both left 0 orphans — only an external kill leaks.
2. **`exploration_summary.json` is overwritten by every gate run**, because the
   probe runner writes it. It is not a gate input (no reference to it anywhere in
   `src/concolic_engine/` or `src/end_to_end_completion_checker/`). Pre-run copies
   saved as `exploration_summary.json.gate919_overwrite`; originals restored from
   `_redrive_20260919/_bak/`.
3. **Slot sizing is shared state.** `tools/slot` takes `/tmp/concolic-slot-$i.lock`
   for `i` in `1..N`, so an agent running `CONCOLIC_SLOTS=14` and one running
   `CONCOLIC_SLOTS=12` overlap on slots 1–12. Observed live: locks 1–11 and 13
   singly held, slots 12 and 14 with queued waiters. It is correct (mutual
   exclusion holds) but the larger-N agent wins races. Check
   `systemd-cgls --user-unit concolic.slice` before sizing — `uptime` alone is not
   enough, and load average lags badly.
4. **Parallelism is bounded by chunk count, not by `CONCOLIC_PROBE_WORKERS`.**
   `ThreadPoolExecutor` gets one task per chunk; with `PROBE_BATCH=40` and few
   probes per scenario the pool may only ever have 1–2 live threads regardless of
   a worker setting of 14. Verified by `Threads:` in `/proc/<checker>/status`.
5. **conversations_index has no `gate_wrapper.sh` tee**, unlike comments_index
   (`_c12/`) and people_stream (`_c1/`). Since `completion.py:_run` uses
   `capture_output=True`, its gate's stdout is invisible until the process ends —
   so there is no live progress signal and, on a crash, only the engine's tail.
   Adding the same two-line tee wrapper the sibling endpoints already use would
   cost nothing semantically. Not added here, to avoid changing a config mid-campaign.

## 7. Known issues checked and NOT hit

- **`KeyError: 'key'`** (shim extractor, fixed in `c4e1446`): not reproduced.
  `src` HEAD verified at `c4e1446`; `shim_extractor.rb` smoke-tested directly on
  people_stream's targets — exit 0, every row carries `"key"`. people_stream's
  full shim pass ran 34 shims with no extractor error.
- **Scratch/counterfactual mode**: `NO_PINS`, `SUMMARY_OUT` and `SKIP_COMPLETION`
  were absent from the launching environment (verified) and never set. Every run
  took the real `attach_to_summary` path.
