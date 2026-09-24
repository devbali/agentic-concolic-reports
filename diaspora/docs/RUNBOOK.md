# RUNBOOK — the process, end to end

The operational companion to `CHECKS.md` (what each check IS) and
`DISCIPLINE.md` (the rules D1–D3 and Rule T). This file is the whole agent
flow: who does what, with which tool, in what order, and what closes an
endpoint. Reference-free throughout — completion is judged against the app's
own real execution and the corpus's internal consistency, never against a
reference policy.

Legend: ▸ script (mechanical, exit-code gated) · ✎ LLM/judgment task ·
⛭ gap (named in §Gaps; interim procedure given).

---

## 0. Actors

| actor | is | may edit | may NOT |
|---|---|---|---|
| **coordinator** (the main session) | drives the sweep, one endpoint at a time | `src/**`, the shared target boundary, the process docs | — |
| **batch agent** (one per endpoint) | builds and repairs a batch until the engine says `complete: true` | only its own `reports/diaspora/results3/<endpoint>/**` | `src/**`, the app, the shared target boundary (Rule T3 — it reports `BOUNDARY CHANGES` instead) |
| **adversary** (one per endpoint per round) | attacks a corpus the engine already called complete, with REAL runs | only its own `<endpoint>/adversary*/**` | anything else; it reports, never repairs |

No actor ever reads a reference policy: `ruby_examples/dse-apps/policies/**`
is quarantined and nothing named REFERENCE / diff_* / OURS_ / SUBSET_ /
_progress.json / unknown.txt may be opened.

## 1. What "done" means

An endpoint is finished only when all three, on the SAME corpus, agree:

1. **the completion engine** — `coverage_summary.json` ends with
   `"complete": true` (coverage complete AND `completion.blocking == []`,
   with the assumption gate, shim tests and note check inside it);
2. **the SQL-consumer audits** — all five exit 0 (coordinator runs them);
3. **the adversary** — a round with **zero wins** (coordinator launches it).

A win at (3), or a defect found at (2), reopens (1). A target-boundary
defect reopens **every** endpoint from scratch (`DISCIPLINE.md` §8, Rule T2).

## 2. The loop, in order

```
 batch agent:  port/repair → corpus rounds → concrete scenarios → engine report ─┐
                        ▲                                                        │
                        └──────────── blocking list ──────────────────────────── │
 coordinator:  hardening lint (tools/hardening_lint.py)  ◀────── complete:true ───┘
               → 5 audits (src/queries_from_runs/audits/)
               → adversary round  → wins? ─ yes → back to the batch agent
                                          └ no  → endpoint DONE → extraction
```

## 3. The tools

**Engine (target-generic, `src/`):**

| tool | run by | what it decides |
|---|---|---|
| `concolic_engine/coverage.py` (via the batch's `coverage_report.py`) | batch agent | every branch combination **that some run evaluated together** is covered or exempted by a declared assumption, AND every decision has been taken both ways (`tree_complete` — the precondition; DISCIPLINE §16, 2026-09-10) |
| `concolic_engine/completion.py` | same call | orchestrates the gate; writes `completion` + `complete` into `coverage_summary.json`; a missing note check or assumption gate is itself BLOCKING |
| `end_to_end_completion_checker/assumption/assumption_checker.py` | the engine (mandatory) | every declared assumption, tested by type via replay (Independence / UntrackedPath / OneSideUntracked / SymbolicConstraint) |
| `end_to_end_completion_checker/mock/mock_note_check.py` | the engine | each target's real statements have a corpus note of that shape |
| `ruby_runtime/completion_checker/shim_extractor.rb` + `shim_test_runner.rb` | the engine | every shim mock RUNS in a test: zero target invocations at 100% line coverage. No waivers (DISCIPLINE §9, Rule S) — if it cannot run as-is, the test supplies the minimal justified mocks that make it runnable |
| `ruby_runtime/completion_checker/concrete_run_probe.rb` + `concrete_env.rb` | batch agent & adversary | a REAL run (sqlite fixtures, no mocks) with frame-tagged target calls and statements |

**SQL-consumer checks (`src/queries_from_runs/audits/`, coordinator runs them):**
`identity_symbolicity_audit` (principal binds symbolic) ·
`policy_loadability_audit <batch> <policy.sql>` (POLICY-side, after extraction:
every statement of the shipped file LOADS and no bind is left unresolved) · `statement_note_lint`
(Class S note shapes) · `bind_resolution_audit` (every `$(VAR)` resolves under
the fold's rules) · `skipped_pcs_audit --patched <fold dir>` — the dir MUST be
`_experiment/variant_d`: `variant_e` lacks the violation-8 `StringVal`
unwrapper and DROPS every string-equality branch. Still load-bearing as of
2026-08-29: on comments_index variant_e drops 28 768 PCs where variant_d
drops 0. It passes on conversations_index only because that corpus contains
no PC of the affected shape — a constraint is not retired because one
corpus stops exercising it (every
recorded PC parses in the fold) · `pc_visibility_audit --gate` (app-compared columns are PC-visible) ·
`empty_relation_emission_audit` (no note reads a row of a list that is empty in
that same run — the over-emission class the note check structurally cannot see) ·
`cardinality_consistency_audit` (a run's own cardinality decision agrees with
the key shape of the notes it emits) · `noteless_call_audit` (no target call is
recorded WITHOUT a note — a falsy return
loses the statement it stands for, and the policy loses it too).
Invoke with `--setenv=PYTHONPATH=/home/dev/project/src` under `systemd-run`.

**Project tools (`reports/diaspora/tools/`):**
`hardening_lint.py` (the past adversary wins as a pre-check — run BEFORE every
adversary round and after every repair) · `note_fidelity_audit.py` (projection
fidelity of notes vs real statements) · `statement_diff.py` · `complement_audit.py`.

**Docs:** `DISCIPLINE.md` (rules, Class S/B, Rule T) · `CHECKS.md` (each check
in detail) · `TARGET_FUNCTIONS.md` (what the targets ARE) ·
`ADVERSARY_WINS.md` (the ledger + cross-endpoint patterns) ·
`end_to_end_completion_checker/concrete/CONCRETE_CHECKER.md` (the adversary
brief, handed to each adversary verbatim).

## 4. Operations (7 GB / 4 CPU box)

**Serialisation is OUR practice, not the engine's.** Nothing in `src/`
knows about locks or host quirks: a batch expresses them in its own config
— the assumption manifest's `runner` string carries the `flock` prefix, and
`env` in `completion_config.json` / `assumption_manifest.json` carries host
environment (e.g. clearing `JAVA_TOOL_OPTIONS`). The engine just runs the
command it is given, with the env it is given.

- **two locks, always in this order** (2026-08-27 — the JRuby lock alone let
  two agents' Python phases collide at 6 of 7 GB and the loser was
  OOM-killed):
  - the read-only dump AUDITS do not take the heavy lock: each is a bounded
    scan (~500 MB under its own `MemoryMax`) and queueing them behind a
    multi-hour coverage pass starves the checking phase for no benefit;
  - `flock /tmp/concolic-heavy.lock` around every MEMORY-heavy Python phase —
    an extraction, a big analysis script; one such phase machine-wide.
    **NEVER wrap `coverage_report.py`: it TAKES THIS LOCK ITSELF**
    (`_HEAVY_PATH` / `fcntl.flock(LOCK_EX)` near line 56). `flock(2)` is not
    reentrant across processes, so `flock … python3 coverage_report.py` makes
    the child block forever on a lock its own parent holds — verified in
    `/proc/locks` as holder 777853 with waiter 777854 on the same inode,
    notifications_index 2026-09-01 12:02, caught by the deadlock guard in
    1 m 47 s. Invoke the report DIRECTLY inside its `systemd-run` unit; mutual
    exclusion is preserved by its own lock, and the "a launcher that dies takes
    its flock with it" property is stronger that way, because the lock lives in
    the process doing the work rather than in a wrapper that can outlive it.
    This line previously said to wrap every heavy phase without naming the
    exception, so following it literally produced the hang — the batch agent
    was right and the doc was wrong. The assumption GATE does not take it: it is
    JRuby-bound and small (its probes take the slot lock per launch), and
    holding heavy across a multi-hour gate starves the other batches;
  - `flock /tmp/concolic-slot.lock` around every `scripts/diaspora-concolic …`
    — one JRuby machine-wide. The gate takes heavy first, then slot per
    launch; nothing ever takes slot then heavy, so there is no deadlock.
  the lock must be taken INSIDE the systemd unit, not in the launcher shell:
  if the launcher dies (a tool-call timeout kills it), the `flock` dies with
  it and the lock is released while the unit is still computing — the work
  outlives its own mutex (comments_index, 2026-08-28). Likewise, verify a job
  by its OWN output (the report's last lines plus the artifact's `completion`
  section), never by a DONE marker: the marker is written by the wrapper,
  which is exactly the part that dies.
  Each lock is taken EXACTLY ONCE per command — a wrapper that already holds
  it must not have `flock` again inside it (2026-08-27: a nested
  `flock slot … flock slot …` self-deadlocked and blocked the box for 11
  minutes with no JVM running). `unset JAVA_TOOL_OPTIONS` always;
- long jobs in `systemd-run --user --unit=<name> -p MemoryMax=… -p
  MemorySwapMax=0`, writing progress and a DONE marker to a log; the engine
  report needs ~5.5–6.3 GB at 20k dumps — run it alone;
- the dump loader must be lean — walk `fix_len_names` in place (no
  `json.dumps`/`loads` round-trip), drop `note`/`args`/`traceback` from
  events and `note` from symbolic_vars before `Run.from_dict` (the coverage
  tree never reads them; the note check and audits read the dump FILES), and
  `del raw` per iteration: 22 148 runs went from OOM at 6.3 GB to a 608 MB
  peak. Print peak RSS at the end of every report;
- ~30 ms per concolic run, but ~60–90 s of JRuby boot per LAUNCH: cost is
  dominated by launches (rounds, probes, scenarios), not by runs;
- **a report in flight when a tool is fixed is stale for that check.** The
  engine's gate runs whatever the audit command pointed at when the report
  started, so a corpus can pass a corrected audit standalone and still fail
  the same audit inside a report launched before the fix (conversations_index
  2026-08-29). After fixing a check, re-run the report — or, better, have the
  report print each audit's verdict in a PRE-FLIGHT before it takes the heavy
  lock, so a stale capture cannot pass unnoticed;
- a coverage-only pass (SKIP_COMPLETION) writes `complete: false` with
  "completion gate did not run" — never trust a summary whose `completion`
  section is empty, and never read a summary from a killed report;
- **`MAX_MISSING_PER_CLIQUE` is no longer needed for driving** (2026-09-12,
  DISCIPLINE §16d). The checker now spends ONE Z3 query per demand set and
  the per-set witness cap defaults to **1**: a covered set proves itself with
  a single UNSAT, an uncovered one names one leaf, and the counterexample in
  that leaf's `concrete_values` is what the next run is built from — one
  counterexample is one run, so a second witness for the same set buys the
  demand round nothing and costs a full query on a larger formula. Drop the
  variable from the launch line; set it only to LOOK at a set (a diagnostic,
  not a stage). On the people_stream 70 % subset the whole check went from
  765 s (old engine, cap 4) to 24 s at the new default, with the same 12
  demand sets flagged and the same `tree_missing`. Two consequences to
  expect in a summary: `missing_branches` is now roughly "sets with a gap"
  rather than up to four witnesses each, and `truncated` is True on any
  incomplete pass (the pass stops AT the cap by design — `complete` was
  already false, so nothing is weakened, but `truncated` no longer
  distinguishes "cut short" from "incomplete");
- **`FORECLOSURE_CONJUNCTIONS` — foreclosure over gate CONJUNCTIONS**
  (2026-09-13, DISCIPLINE §16e). `CoverageChecker(foreclosure_conjunctions=
  True)` infers the §16b relation over the gate conjunctions the demand
  already contains: for a leaf group's gate prefix `P`, a surviving member
  `d` no run matching `P` ever evaluates is not part of that leaf. It is
  **OFF by default in the engine** — every summary written before that date
  reproduces byte-for-byte with the flag unset, which is what keeps the
  closed endpoints closed — and a batch turns it on in its OWN
  `coverage_report.py` where `CoverageChecker(` is built.
  notifications_index has the knob wired as `FORECLOSURE_CONJUNCTIONS`
  (default `1` THERE; set `0` for the differential half). Three things to
  expect in a summary: `conjunction_foreclosures` /
  `conjunction_foreclosure_groups` (the pairs and leaf groups applied, with
  a capped `conjunction_foreclosure_list`), a `PROVISIONAL` marker whenever
  `tree_complete` is False (same reading as a §16b foreclosure), and
  **`unmatched_gate_conjunctions`** — the `A = 0` class, leaf groups whose
  gate prefix NO run of the corpus matches. That class is NOT an inference
  and its demand is NOT dropped: the prefixes are printed so the driver can
  CONSTRUCT them. The flag is part of the step-6 checkpoint key, so a
  checkpoint written with it off is rotated to `<file>.stale` rather than
  replayed with it on — keep the two settings on different checkpoint paths
  if you want both to resume. The inferred foreclosures also reach the
  assumption gate through `assumptions_to_dict()` as
  `ConjunctionForeclosureAssumption` (`inferred: True`), whose derived test
  builds a run matching `P` with the member's own inputs seeded to force its
  evaluation: the member being evaluated is a FAIL and withdraws the
  foreclosure;
- **`FORECLOSURE_SUBCONJUNCTIONS` — foreclosure over a SUB-conjunction**
  (2026-09-13, DISCIPLINE §16f). `CoverageChecker(foreclosure_subconjunctions
  =True, foreclosure_conjunction_width=W)` — W defaults to **3** — infers the
  same relation one conjunction NARROWER: a member `d` is foreclosed under
  any conjunction `C` of literals already fixed EARLIER in the leaf's walk,
  `|C| <= W`, with `A(C) > 0` and `B(C, d) = 0`. Two things §16e cannot do
  and this can: `C` may contain NON-gate members, and `d` may itself be a
  GATE. It is **OFF by default in the engine** and turning it on IMPLIES
  `foreclosure_conjunctions` (§16f's drop set is §16e's union the walk's,
  which is what makes the nesting hold by construction); with it off, a
  `foreclosure_conjunctions=True` pass is byte-identical to a pre-§16f one.
  notifications_index has the knob wired as `FORECLOSURE_SUBCONJUNCTIONS`
  (default `0`; `FORECLOSURE_CONJUNCTION_WIDTH` sets W). Expect in a summary:
  `subconjunction_foreclosures` / `subconjunction_foreclosure_conditions`
  with a capped, structured `subconjunction_foreclosure_list` carrying
  `(C, member, A)`, the same `PROVISIONAL` marker, and — because a GATE can
  now be foreclosed — a FALL in `unmatched_gate_conjunctions` where the A = 0
  class was one unrealisable gate. The flag AND the width are part of the
  step-6 checkpoint key, so the three settings never share a checkpoint
  path. Cost is bounded by W: the minimal-`C` search is a bounded set cover
  (`minimal_subconjunction`), memoized per (fixed literals, member), and
  `foreclosure_conjunction_budget` (default 20 000 nodes) makes exhaustion a
  NON-inference rather than a hang. The inferred classes reach the assumption
  gate as `SubconjunctionForeclosureAssumption` (`inferred: True`), whose
  derived test is §16e's probe with `C` in place of `P`;

- **`FORECLOSURE_WELLFOUNDED_DROPS` — WELL-FOUNDED drops, `C` from the whole
  leaf** (2026-09-14, DISCIPLINE §16g). `CoverageChecker(foreclosure_
  wellfounded_drops=True, foreclosure_conjunction_width=W)` — W defaults to
  **3** — lifts §16f's `C ⊆ acc` (walk-prefix) restriction: `C` may be drawn
  from ANYWHERE in the leaf's own cube, including literals that sit LATER in
  the walk than the member they foreclose, provided **every literal of `C`
  belongs to a member that is itself KEPT**. That condition is resolved as
  the LEAST FIXED POINT of a monotone operator (`coverage.
  wellfounded_drop_set`), so the answer is unique and independent of the
  order the members are visited in; two members that foreclose each other
  drop NEITHER. A second condition is not optional: the reduced leaf must be
  MATCHED by at least one profile (`A(reduced) > 0`), or the whole drop set
  is refused — §16e's "A = 0 is absence, not evidence" applied to the LEAF.
  It is **OFF by default in the engine** and turning it on IMPLIES
  `foreclosure_subconjunctions` (hence `foreclosure_conjunctions`); with it
  off, a `foreclosure_subconjunctions=True` pass is byte-identical to a
  pre-§16g one — proved on people_stream and comments_index, whose summaries
  reproduce to the byte against the pre-edit engine. notifications_index has
  the knob wired as `FORECLOSURE_WELLFOUNDED_DROPS` (default `0`). Expect in
  a summary: `wellfounded_drops` / `wellfounded_drop_conditions` with a
  capped, structured `wellfounded_drop_list` carrying `(C, member, A)`, the
  same `PROVISIONAL` marker, and a `WF_DROPS=...;WF_CONDS=...` verdict line.
  The flag is folded into the step-6 checkpoint key **only when it is on**,
  so every §16e/§16f checkpoint written before 2026-09-14 still replays
  untouched. Cost is the same bounded set cover §16f uses, on a pool that is
  the whole cube instead of a prefix. The inferred classes reach the
  assumption gate as `SubconjunctionForeclosureAssumption` marked
  `wellfounded: True` / `section: "16g"` — the SAME payload and the SAME
  probe, because `C` is still at most W literals to flip from a base that
  records the member. **One caveat to carry into any report**: unlike §16f,
  §16g cannot promise the leaf COUNT is monotone or that every printed
  witness lies inside a printed §16f witness. Its drop set depends on the
  leaf AND on the pins its §16e/§16f justifications leave, so one §16f leaf
  can coarsen two ways; every §16g leaf is still a strict SUB-cube of its
  §16f leaf (weaker demand, not larger) and §16f-complete still implies
  §16g-complete, which is the claim. See DISCIPLINE §16g;
- agents must wait with Monitor until-loops on a log marker and re-check the
  log themselves; the coordinator keeps a 15-min stall tick and nudges any
  agent whose job finished while it slept.

### Long jobs must run CHECKPOINTED (owner rule, 2026-09-12)

**Anything that can run longer than ~10 minutes is launched with its
checkpoint on, so a kill costs the unit in flight and nothing else.** The rule
came from the two final passes of 2026-09-11, which held everything in memory
for 2 h 30 and would have written their first byte at the end. Every mechanism
below is OPT-IN and keyed on its own inputs — with the variable unset the job
behaves exactly as it always did, and a checkpoint whose key does not match
(a changed corpus, assumption set, knob, or the engine's own source) is
DISCARDED with a notice and rotated to `<file>.stale`, never silently reused.
Set them in the `env …` line of the stage that launches the job, not globally,
and give each stage its OWN file next to its other artefacts:
`COVERAGE_CHECKPOINT=$B/_cov_<tag>.ckpt.jsonl` for `coverage_report.py` (the
checker's per-demand-set Z3 enumeration — the hours-long phase; a resumed pass
skips every set already recorded and produces a byte-identical summary);
`ACHK_CHECKPOINT=$B/_achk_probes.jsonl` for the assumption gate (one record per
JRuby probe replay, which is the whole cost of the gate ONCE the probes start)
plus `ACHK_RESULTS_JSONL=$B/_achk_rows.jsonl` so a killed gate leaves the verdict
rows it did produce (`--json-out` alone writes an EMPTY file on a kill) and
`ACHK_INDEX_CHECKPOINT=$B/_achk_index.ckpt.jsonl` +
`ACHK_DERIVE_CHECKPOINT=$B/_achk_derive.ckpt.jsonl` for the gate's two
PRE-PROBE phases — see the paragraph below, which is where posts_show spent
5 h 59 m on 2026-09-12 without launching one probe;
`ENGINE_CHECKPOINT=1` for `_engine_section.py` (skips the stage outright when
`SUMMARY_OUT` is already there for these exact inputs, and turns on the gate's
probe log for it); `AUDITS_CHECKPOINT=1` for `_c7_audits.sh` (each audit's
output is kept under `$B/_c7_audits.done/` and an audit that finished with
`EXIT=0` is replayed into the log instead of re-run — the whole directory is
dropped when the corpus or the script changes); `SUBSUME_CACHE=$B/_subsume.jsonl`
for the blockaid subsumption stage (the verdicts for one query set, so a rerun
of an extraction does not redo the ~42-minute JVM pass; the cached unit is the
whole call — a kill *during* the JVM still loses it). A rerun without the same
path is a rerun from zero: keep the path stable across a stage's retries, and
delete the file (not edit it) when you want a genuinely fresh pass.

**2026-09-13 — the two WHOLE-STAGE keys now digest every input, not a sample of
them.** `_engine_section.py`'s `<SUMMARY_OUT>.checkpoint_key` (format v2, all
three copies identical) keys on SUMMARY_IN + `completion_config.json` *and* on
every file the config or one of its commands names — `shim_tests.rb`,
`_shims_extracted.json`, `targets.rb` / `concolic_targets.rb`, `concrete_run` +
aliases, the assumption manifest and gate wrapper, and each `audit_cmds` /
`extra_audit_cmds` SCRIPT's source — plus the batch's `coverage_assumptions.py`
/ `_confinement_withdrawn.json` / `_prior_footprints.json` (a missing optional
file digests as `ABSENT`, never an error), the engine sources
(`completion.py`, `assumption_checker.py`) and the `ACHK_*` / `CONCOLIC_*` /
`COMPLETION_*` / `QFR_APP_CONFIG` knobs as the process received them, because
v1 digested only the first two and would have skipped the stage and replayed a
stale `OVERALL_COMPLETE=False` after comments_index ported two shim tests
(`comments_index/_RESTORED_20260913.md` §3); `_c7_audits.sh`'s
`AUDITS_CHECKPOINT` key adds the audit scripts' own source (every `*.py` under
`src/queries_from_runs/audits` and `reports/diaspora/tools`, plus the batch's
own audit scripts) and `QFR_APP_CONFIG` to its corpus + self hash, closing its
stated "the key does not see a CHANGE to an audit TOOL" limit; both now log a
`[checkpoint] key inputs: …` line naming every component, and the engine
section's sidecar carries a format note plus one `#   label path digest` row
per input, so the record shows what was digested.

**A long job must also SAY what it is doing.** The gate's cost is not only its
probes: before the first probe it parses every dump in the batch
(`corpus_index`) and then derives, per declaration, which probes the verdicts
will need. On 2026-09-12 posts_show's engine section sat in that phase for
5 h 59 m at 2.5-3.7 GB — zero JRuby children, an empty `_achk_rows.jsonl`, four
lines in the log — and was killed as a suspected hang. Measured on a 2 000-dump
slice of that corpus: index 54 s, derivation 69 s PER confined pair, 1 571 dump
re-parses per pair, because a pair re-derived from scratch what is a property
of a DECISION (posts_show's 2 315 pairs are 112 distinct decisions) and every
snapshot selection re-scanned the whole index. Three variables, all opt-in:
`ACHK_HEARTBEAT_S=60` prints `[corpus-index] … 41000/194262 elapsed 640s rate
64/s eta 2400s rss 2900MB` and the same for `[derive-probes]` and `[verdicts]`,
so a slow phase can be told from a hung one (0 turns it off);
`ACHK_INDEX_CHECKPOINT=$B/_achk_index.ckpt.jsonl` records one row per dump
(~350 MB on posts_show), keyed on the corpus, the declared set, the
canonicalization hook and the engine's source, so a relaunch replays the index
in minutes instead of re-reading 36 GB of JSON;
**2026-09-14 — that key is now INCREMENTAL: only what decides how a row is
COMPUTED (the engine's source, the canonicalization hook and the ALIAS
declarations) still invalidates the whole log, while corpus membership is
settled row by row against each dump's own size and mtime, so a round that
added dumps re-indexes exactly those dumps (comments_index, 26 528 dumps:
35.7 s from scratch, 2.1 s to resume unchanged, 2.4 s for 400 new, every one
of them byte-identical in fingerprint to a from-scratch index of the same
corpus — a full rebuild was the reason notifications' C22 declined to run its
engine section at all), a dump that vanished loses its row and the log is
compacted, and the rest of the declared set — which reaches a row only
through the aliases — no longer moves the key, so one round's index serves
the next: point every round of an endpoint at ONE index log, never a
per-round name, and note that a SECOND gate in the same batch directory
cannot share the log (one writer takes a `<log>.lock`; the other indexes
uncached, which is a full pass) — evidence in
`results3/_idx_proof_20260914/`.**
`ACHK_DERIVE_CHECKPOINT=$B/_achk_derive.ckpt.jsonl` does the same for the
derivation that follows it — one row per confined DECISION, holding its profile
representatives and their flipped seeds as deltas against the index, so a
resumed gate opens no dump for them at all — that one is deliberately NOT
incremental and stays keyed on the corpus and the declared set, because a
representative set and the profile COUNT that decides testability are
properties of the corpus as a whole, so a corpus that grew can legitimately
change a derivation and keeping the old record would be unsound.
`ACHK_CONF_PROFILES` is unchanged
and still a budget knob, not a speed one. `ENGINE_CHECKPOINT=1` sets all of these for you
in `_engine_section.py`. NOTE where the lines come out: `completion.py` CAPTURES
the gate's stdout, so the live file is the gate wrapper's tee —
`$B/_c1/_gate_engine.log` — not the stage log.

**And a long job must not be able to lose a finished result.** The gate's
dump-side audits ran under a hard-coded 1800 s in
`concolic_engine/completion.py:run_audits`, and a `TimeoutExpired` there came
out of `attach_to_summary` — so on 2026-09-11 notifications_index's final pass
threw away an 8 962 s coverage phase because `cardinality_consistency_audit`
(which needs ~59 min on that 289 733-dump directory) was killed at 30 min and
`coverage_report.py` writes its summary only AFTER the gate. Two rules follow.
(1) Run the FINAL pass SPLIT: `SKIP_COMPLETION=1` + `SUMMARY_OUT` for the
coverage layer, then `_engine_section.py` with `SUMMARY_IN` for the gate
(posts_show `_p13c.sh` 13c-1/13c-2 is the model; notifications_index
`_c12_rerun_after_restart.sh` is the ported one). (2) Size the audit limit:
`COMPLETION_AUDIT_TIMEOUT=<s>` for one invocation, `audit_timeout` in the
batch's `completion_config.json` as its standing default, or `timeout` on a
single `audit_cmds` entry — precedence in that order, 1800 s when all are
unset. A timeout is now a RED audit row (`timed_out: <s>`), which blocks
`complete` but leaves the section, and the summary, intact. Remember the audits
take `{batch}` and scan the batch DIRECTORY, so their cost tracks the dumps on
disk, not the pass's `DUMP_LIST`.

*Availability, 2026-09-12:* `COVERAGE_CHECKPOINT` is LIVE
(`src/concolic_engine/checkpoint.py` + `coverage.py`), and so are
`ACHK_CHECKPOINT` / `ACHK_RESULTS_JSONL` / `ACHK_INDEX_CHECKPOINT` /
`ACHK_DERIVE_CHECKPOINT` / `ACHK_HEARTBEAT_S` (`assumption_checker.py`; tests
`src/test_assumption_checker_checkpoint.py`, `…_index.py`). The other four were
written while the 2026-09-11 chains were still running and are staged as
`<file>.checkpoint_next` — see
`reports/diaspora/results3/_CHECKPOINT_STAGED_20260912.md` for the apply list;
until it is applied, setting those variables does nothing. The audit-timeout patch above
(`completion.py` + `test_completion_audit_timeout.py`) is in the same apply
list. Two long jobs are NOT covered yet and that file says why:
`_exact_enum.py` (11-26 min) and the JRuby drives (resume only per chunk,
within one TAG).

---

## Phase 0 — batch setup

- ✎ Author `run_dse.rb` (entrypoint wiring, symbolic user, scenarios,
  AUTH_CHAIN) and the batch-local `concolic_targets.rb`/`targets.rb`
  from the notifications_index templates. The portable repair toolkit
  ports with them: `emit_includes_preloads`, pluck projection + order
  columns, `assoc_base_name` owner-qualified names, the find_by
  thread-local conditions capture, `TypeLinkedString` for STI pins.
- ✎ Start the batch's ledgers: mock ledger (every mock named shim mock
  or target mock), pin ledger, assumption ledger.

## Phase 1 — the mock-construction loop (repeat per wall until the
endpoint renders clean). Verification: **THE MOCK CHECKER, deterministic
form** (Bali directive 2026-08-25 — "make it more just like a script
that is run"; the manifest form had probed 4 of 13 live mocks and never
touched the Person#name violation):

- ▸ **`mock_note_check.py <concrete_run.json> <batch>`** — the primary,
  ZERO-authorship check for every SQL-issuing target mock at once: the
  concrete run tags each real statement with the target-function frame
  it was issued under (frame thread-local in the tracer +
  sql.active_record capture); per target, real statement shapes are
  diffed against that target's corpus notes (any-target fallback for
  frame nesting, annotated NOTE-OK*; batch alias map applies). Verdicts:
  NOTE-OK / NOTE-MISSING (junk-note-over-SQL-body — the Person#name
  class) / NOTE-MISMATCH (no note anywhere — the swallowed-statement
  class). First run on comments_index: converged to exactly ONE red, the
  mentions-table read — the root cause of the reference diff's 9-query
  family, found by script alone.
- ▸ (retired to trash 2026-08-26; the engine's shim extraction replaced it) **`mock_coverage_audit.py <batch> <manifest>`** — the completeness
  gate: every live corpus target must be probed or carry a reasoned
  waiver; exit 1 on anything unlisted.
- ▸ `mock_checker.rb <batch>/mock_manifest.rb` (manifest form, JRuby
  `--debug`) — REDUCED ROLE: shim-mock probes (zero-target + M2 100%
  line coverage need per-mock fixtures by nature) and coverage top-ups
  for branches the concrete scenario does not reach. The target-note
  entries are subsumed by mock_note_check.
- ▸ **THE COMPLETION CHECKER — `src/concolic_engine/completion.py`**
  (Bali, 2026-08-25: a module of the concolic engine, peer of
  CoverageChecker): the engine owns "are the mocks complete?" exactly as
  it owns "is exploration complete?", and both verdicts land in the SAME
  final report — `coverage_summary.json` gains a `completion` section
  and an overall `complete` = coverage_complete AND completion.complete
  (each batch's coverage_report.py calls `attach_to_summary` when a
  completion_config.json is present). Zero coupling kept: every
  runtime-specific step is a configured subprocess command; the
  (retired wrapper; call `python3 -m concolic_engine.completion` / the batch's coverage_report.py) `completion_checker.py` CLI was a
  thin wrapper. Shim verification is the ENGINE'S responsibility, never
  agent-triggered:
  1. EXTRACT — `shim_extractor.rb` (runtime-specific, static) derives
     the AUTHORITATIVE shim list from the batch's own runner code
     (singleton stubs, prepends, dynamic define_methods; value-class
     plumbing tagged). First comments run: 18 installations, including
     `obj.image_url` — a real app-code shim NO manifest had ever listed.
  2. TEST — `shim_test_runner.rb` (runtime-specific) executes the
     agent-PROVIDED body per engine-enumerated key
     (`<batch>/shim_tests.rb`): zero-target probe + 100%
     executable-line coverage of the real body (coverage_waiver
     available for framework bodies, reason recorded). A key the agent
     omits is a NO-TEST red — omission is impossible to hide.
  3. NOTE CHECK — mock_note_check folded in.
  4. ASSUMPTIONS (Bali, 2026-08-26 — roped into the engine too): when
     the batch config carries `assumption_manifest` + `assumption_cmd`,
     the engine runs the assumption driver (corpus scan + flip probe per
     entry) AND cross-checks the coverage checker's DECLARED assumptions
     against the manifest — every assumption the coverage verdict relied
     on must be VERIFIED by a manifest entry whose seeded dimension
     appears in its expr; unverified declared assumptions block
     completion, listed by name.
  5. REPORT — the `completion` section of coverage_summary.json (also
     `completion_report.json` when run standalone): per-shim verdicts,
     note-check, assumptions {manifest, declared, verified, unverified,
     driver result}; `complete` requires all green.

  Shim-test contract clarification (Bali question, 2026-08-26): the
  OUTSIDE of the shimmed function is NOT mocked — real app, real fixture
  DB, real global state, real callees; the probe only observes. Fixture
  authorship may SET state (column values, params, config toggles such
  as AppConfig camo) to reach branches — provisioning, never
  substitution. Checker bug found by that question: the method-range
  scanner miscounted `x = if ...` as a modifier-if, truncating ranges
  and reporting 100% over lines that never ran (Profile#image_url's camo
  branch); fixed in both runners.
  Comments first run: 3 PASS at 100% (engine caught an 83.3% fixture
  and demanded the missing branch), 15 reasoned waivers, overall RED
  carried solely by the standing mentions-table note gap.

The remaining ✎ inputs: the ONE concrete fixture scenario (shared with
Phase 5), the shim_tests.rb bodies/waiver reasons the engine demands,
and nothing else.

For each wall the endpoint hits:
- ✎ Classify the fix: **shim mock** (pure computation) or **target
  mock** (a declared target function) — the naming convention in
  CHECKS.md Part I. Wrong classification is itself a violation.
- Shim mock (`kind: :shim` manifest entry):
  - ✎ author the probe fixture (concrete values exercising the whole
    body — both branches);
  - ▸ mock checker verdict = zero target-function invocations AND 100%
    of the real method's executable lines covered (the two failure
    modes: a hidden target call, or a probe that missed the branch
    hiding one).
- Target mock (`kind: :target_note` manifest entry):
  - ✎ author the ground-truth side (real relation SQL from the clean
    app / a statement_log capture);
  - ▸ mock checker verdict = normalized shape equality between the real
    statement and the mock's note — tables, projection, predicate
    columns (order columns included; literals/binds wildcarded).
  - ✎ T1b: enumerate the mechanism's full statement set (through
    fetches, preload steps) and route every statement through an
    event-emitting probe.
- Pins:
  - ✎ written neutrality argument in the pin ledger, or the
    PC-recording pattern (TypeLinkedString) if the app compares it;
  - ✎ add app-compared columns to the batch's GATE LIST (from code
    reading: grep the endpoint's views/models for compares).
- On any failure: T3 repair loop, closed only per rule P — the new
  check must catch the violation's CLASS with mechanism unspecified.

## Phase 2 — corpus generation

- ▸ rounds script (main + per-STI-type rounds + auth chain; then
  REGENERATE saturation/context seeds from the fresh corpus and run
  those rounds — stale seed files reference dead var names).
- ▸ gate: `run errors: {}` in every round; crash isolation per seed.
- ▸ **THE NAME BOUNDARY — use `concolic_engine.names`, do not hand-roll it.**
  A symbolic variable has two spellings and two forms, and which one you get
  depends on which STAGE wrote it down:
    * LENGTH: the runtime and the dumps write `len(X)`; the checker, the
      enumerator and every summary write `SYM_LEN_X`
      (`coverage_report.fix_len_names` converts at load).
    * ORDINAL vs CANONICAL: `call_interceptor` names a result by WHEN it ran
      (`records_2`); an AliasAssumption renames it by WHAT it did
      (`records_mentions_66022a8b`), via `canonicalize_ordinals` /
      `alias_map_for` / `renamer`. The map is MANY-TO-ONE — seeding one
      backing ordinal contradicts the demand whenever the path takes another,
      so ALL of them must be written.
  A lookup that crosses that boundary and misses is **silent**: `.get()`
  returns `None`, `k in seeds` is False, `LIDX.get(L)` is None — and every
  caller reads that falsy answer as a MEANINGFUL NEGATIVE ("never minted",
  "not seedable", "no compatible base", "never evaluated", "no seed needed",
  "pin unachievable").

  **Documentation alone did not work.** This paragraph has said "convert both
  ways" since 2026-09-11 and the trap was hit FOUR more times in the single
  night of 2026-09-13/14, by four different agents, after it was written down:
  the seeder dropped every `SYM_LEN_*` value (18.5 % of one corpus, 29.8 % of
  another, 31 variables) as "no seed needed"; the confinement gate collapsed
  to a 40x slower single-replay path for ~10 h because the canonicalisation
  hook renamed seeds inside loaded dumps so a probe never matched its own
  launch (`seeds_as_written` fixed it); posts_show class A called 3,746 cubes
  unachievable and gave the OPPOSITE answer once the names were put through
  `canonicalize_ordinals` + `fix_len_names`; posts_show class D read "never
  minted" for a variable the corpus mints in 68 % of runs.

  **So the rule is now mechanical, not advisory:**

  > **A BARE DICT LOOKUP ACROSS THE NAME BOUNDARY IS A DEFECT.**
  > Use `concolic_engine.names.NameSpace`. Reviewers reject the bare lookup.

  ```python
  from concolic_engine.names import NameSpace, to_checker, to_runtime
  ns = NameSpace(seeds, name="concolic_seeds", alias_map=amap)
  ns.get(k)        # raises WrongSpelling IFF the table holds the SAME
                   # variable under another spelling; a genuine absence
                   # returns None, silently, exactly like dict.get
  ns.resolve(k)    # forgiving: answers under whichever spelling is stored
  ns.keys_for(k)   # EVERY backing key — the many-to-one seed resolution
  ns.audit(keys)   # which of these names your table has been answering "no" to
  ```

  The genuine-absence distinction is the whole design: the raise is
  conditioned on a POSITIVE observation — a sibling key that IS present —
  never on the absence itself, so it cannot turn real absences into
  exceptions. Use `get` for a tripwire (a miss on spelling should stop the
  job), `resolve`/`keys_for` when the lookup should simply work.
  `src/test_names.py` pins all of it, including the four failures above as
  named regression tests. Audited call sites and the ones still staged:
  `results3/_staged_20260914/NAME_BOUNDARY_STAGED.md`.
- ▸ demand rounds are CONSTRUCTED, not sampled: each `missing[]` entry
  carries a Z3 counterexample and the checker's foreclosure relation says
  which gates make each member evaluable — ask the solver for the cube's
  outcomes AND `g != o` for every `(g, o)` foreclosing a member (so the model
  carries the path), overlay it on a base run whose profile already walks
  the whole set, then explain the round per key (honoured / contradicted /
  never evaluated). Measured 2026-09-10 on notifications: bulk seeds
  0.0004 closed/run, a counterexample on an arbitrary base 0.014-0.19,
  because 70 % of keys are never reached; seeds are honoured 97 % when
  reached. Batch at the DRIVER level (Bali, 2026-09-10): take every remaining
  cube from the exact enumerator (`_exact_enum.py`, ~100 s) rather than the
  checker's capped witnesses (a pass, hours), build one seed per cube, drive
  the whole batch, re-enumerate; the checker pass runs once, to CERTIFY.
  Build seeds per SET, not per cube: one compatible base per set, every
  cube by overlay; Z3 only for conflicts, in a pool, pipelined into the
  drive (Bali, 2026-09-11). "No run produced this combination" is a
  statement about the corpus, not the program: before calling any
  combination residue, CONSTRUCT it — fix the gate AND member outcomes
  (the enumerator proved SAT; the assignment is the model), seed every
  ordinal backing each canonical, replay, classify per key; only a gate
  that flips back despite its seed is impossibility evidence
  (people_stream 2026-09-11: 768 "residue" cubes, 12/12 reachable,
  driven to 0 with no declaration).
  Stop a method that falls below ~0.05/run for two rounds.
- Ops invariants: systemd caps, flock serialization, extraction later
  in a FRESH unit (page-cache cgroup accounting).

## Phase 3 — corpus & fold audits (all ▸, all ON DUMPS, run as one gate)

```
python3  statement_note_lint.py   <batch>          # F5 — Class S lint
python3  complement_audit.py      <batch>          # F4 — polarity/merge input
python3  pc_visibility_audit.py   <batch> --gate <cols-from-Phase-1>   # T1c/C2-PC
⊕python3 bind_resolution_audit.py <batch> [baseline]  # F1+F3 — predicted
                                  # placeholders + ambiguous producers
⊕python3 skipped_pcs_audit.py     <batch> --patched <fold-patch-dir>   # F2
```
```
python3  identity_symbolicity_audit.py <batch>   # F6 — principal must be symbolic
python3  exception_note_audit.py       <batch>   # F8 — no note may be a
                                  #      captured exception (prose where a
                                  #      statement belongs)
```
EXTRACTION itself is `queries_from_runs.dump` — four stages, one command:

```bash
PYTHONPATH=src python3 -m queries_from_runs --results results3 \
    --out results3/queries_from_runs --endpoint <endpoint> [--no-subsume] \
    [--sample N --sample-seed S] [--suffix S] --verbose
```

`extract_statements` (binds resolved by provenance, qualifying path conditions
rendered as predicates) -> `prune_conditions` (the corpus drops every predicate
it shows the same query running both WITH and WITHOUT) -> `drop_subsumed` ->
`render_policy`. The per-endpoint input is the corpus directory and an optional
`POLICY_HEADER.txt` beside the dumps. The rules are stated in
`src/queries_from_runs/README.md` rule 4.

AFTER EXTRACTION, on the file about to ship (F7, 2026-09-15):
```
python3  policy_loadability_audit.py <batch> <queries_from_runs/<endpoint>.sql>
                                  # F7 — no placeholder in the shipped SQL body
                                  #      may be a value the corpus proves is
                                  #      principal-determined; _MY_UID must be
                                  #      the only spelling of the principal
```
All six must be green (or every red finding dispositioned in the batch
ledger with a repair or a written why-not). Any repair → back to Phase
2. **The engine runs these itself** (`audit_cmds` in the batch's
completion_config.json → `completion.audits` in the final report, RED
blocks `complete`): the metric-only sub-agent experiment (2026-08-26)
showed an agent can reach `complete: true` while never running them,
and the one it needed most — identity symbolicity — did not exist yet.

## Phase 4 — assumption gate (END of generation, final evidence layer).
Verification driver: **THE ASSUMPTION CHECKER** —
`end_to_end_completion_checker/assumption/assumption_checker.py <batch>/assumption_manifest.json`.
One manifest entry per assumption ledger entry; ~15s per probe.

- ✎ per assumption: one manifest entry — name, kind
  (independence/foreclosure), the seeded dimension, expected label.
- ▸ the driver does the rest, per assumption:
  - CORPUS SCAN (tripwire): every run seeding the dimension must show
    PCs consistent with the seed;
  - DIRECTED PROBE (the controlled experiment): auto-picks the richest
    snapshot dump seeding the dimension, replays its ENTIRE seed dict
    with only that dimension flipped (SEEDS_ONLY), diffs the evidence
    (PCs + notes, dimension excluded) against the snapshot —
    independence must diff empty; foreclosure must diverge AND carry
    the expected labeling PC (a silent flip = dead knob = FAIL).
- Line-diff of the probe pair (coverage_probe) only as diagnostic when
  a probe fails.

## Phase 5 — THE CONCRETE CHECKER = AN ADVERSARIAL SUB-AGENT (2026-08-26)

**Not a script.** The scripted checkers (audits, mock checker, assumption
checker) can only examine what the engine chose to look at. Phase 5 is a
SEPARATE sub-agent that has NOT built the batch, reads the endpoint's real
code path (controller → services → models → views/partials/helpers) and
tries to DEFEAT the corpus: produce a REAL run of the endpoint — booted
app, sqlite fixtures, real Devise session, **no mocks, no stubs** — whose
target-function trace contains a call shape that **no dump in the corpus**
contains (statement shape, preload, pluck projection, finder condition,
STI pin, ordering, a call at a depth the engine never reached).

- A novel shape is, by definition, a finding: Class S (the engine
  swallowed / mis-shaped it) or Class B (the engine never explored the
  branch that issues it). It goes back to the batch agent as BLOCKING with
  the scenario attached; `complete: true` is void until the shape is in
  the corpus and the check that catches its class is in place.
- The adversary supplies SCENARIOS, never verdicts. What stays scripted is
  the instrumentation and the judge: `concrete_run_probe.rb` captures the
  frame-tagged target calls of the real run; `mock_note_check.py` /
  decides "in corpus or not" (statement side); the target-call side is the adversary's comparison of `concrete_run.json` `target_calls` against corpus targets.
- Runs AFTER the batch reports `complete: true` (that is what it attacks)
  and again after every repair it causes. Brief: `src/end_to_end_completion_checker/concrete/CONCRETE_CHECKER.md`.
- It never sees a reference policy; the app is the ground truth.

The plumbing below is what the adversary drives.


Run the endpoint (or its paths) CONCRETELY — real code, no concolic
mocks — and compare against the corpus in TARGET-FUNCTION currency, not
SQL: every target function the concrete run invokes must appear as a
corpus event (else a mock swallowed a target — generalized Class S, any
target family), and every app line it executes should be corpus-visible
(Class B).

**The fixture environment EXISTS (gap 1 closed, 2026-08-25):**
`ruby_runtime/completion_checker/concrete_env.rb` — real sqlite DB via
the bundled JDBC adapter (no server), app schema loaded (mysql-isms
stripped as dialect scaffolding), fixture ROWS seeded by raw INSERT
(data, not code-under-test). Target functions run for REAL — no mocks,
no stubs (a stub mode was briefly built and removed: real code with a
faked target boundary is exactly what the concolic engine does — not
ground truth). One env-provisioning knob: the sprockets
precompile-allowlist check is disabled (the JS bundle chain references
never-installed node_modules libs); assets then resolve real
fingerprinted paths.

First genuine run (notifications_index, 2026-08-25): real Devise
resolution → real controller dispatch → real templates → real DB,
status 200, 81 target-function invocations — **checker GREEN vs the
gen10 corpus**. Two would-be misses (`load_target`, `to_a`) were
nested-only: the probe records CALL DEPTH, and a target invoked only
inside another target frame is structurally subsumed (under
interception the outer mock fires first; the inner's evidence lives in
the outer's note). Depth-0 misses stay RED.

- ✎ author concrete scenarios (fixture records + bodies driving the
  endpoint's paths; the corpus's PC set is the checklist of branch
  families to exercise). One scenario per manifest when bodies can
  crash the JVM natively (observed on the mention path) — per-process
  isolation names the crasher.
- ▸ capture: `concrete_run_probe.rb <manifest.rb>` (via the app-booting
  runner; `CONCRETE_COVERAGE=1` adds cumulative line coverage under
  JRuby `--debug`).
- ▸ compare (retired script, now the adversary's judgment — `trash/end_to_end_completion_checker/concrete_checker.py`): every
  concretely-invoked target function present in corpus events
  (exit-gated); coverage side exact with `--corpus-coverage`,
  approximate via corpus event sites without it (⛭ gap 2).
  Capture/compare plumbing is smoke-tested; a GENUINE concrete run
  awaits the fixture environment.

## Phase 6 — extraction & closure

- ▸ extraction with the fold patches installed; complement merge in the
  view-build using Phase 3's F4 output; re-run
  `bind_resolution_audit` baseline comparison. (Both that audit and
  `identity_symbolicity_audit` now read the schema and the principal columns
  from the app config and go RED without one — every `*audits*.sh` in the
  batches exports `QFR_APP_CONFIG`; a new one must too.)
- ▸ optional C3 if a reference policy happens to exist — any residue it
  finds means Phases 3-5 have a gap: fix the CHECK too (rule P).
- ▸ **ALL of `src/queries_from_runs` is app-agnostic and REQUIRES an app
  config** — since 2026-09-11 (E12) that is true of RECONSTRUCTION too, not
  only the subsume/blockaid harness. Export
  `QFR_APP_CONFIG=reports/diaspora/queries_config/app.json`, or pass
  `--app-config`, or run the harness through
  `reports/diaspora/queries_config/check_subsumed.sh`. Every extractor,
  `tools/blockaid_*.py`, `_blockaid_fold.py` and the variant runners set the
  variable themselves, so existing invocations keep working; a NEW driver that
  forgets it gets a ConfigError naming the flag, never a wrong policy.
- ▸ `app.json` now carries values that decide the SQL TEXT of every shipped
  view: the principal/identity tables and columns, the pinned principal
  values, the symbol-name shapes `targets.rb` mints, the inflections. **An
  edit to it is an extractor change** — it needs the same corpus differential
  a `transform.py` change needs, and `principal.binds` is coupled to
  `targets.rb` under Rule T. Run
  `reports/diaspora/queries_config/validate_app_json.py` (checks every
  table/column/FK/regex/path that `schema.rb` can confirm) after any edit, and
  the corpus differential in
  `reports/diaspora/tools/extraction_differential/` (old-vs-new view sets over
  all six corpora; `RUNS DIFFERING` / `VIEWS DIFFERING` must be 0, or the
  statements that moved are a shipped-policy finding for the owner).
- ▸ `diff.py`'s `--reference` has no default and `cli.reference_dir` is null:
  the reference policies stay QUARANTINED unless someone passes the path.

**COMPLETE =** mock checker green (every ledger mock) + Phase 3 fold
diagnostics green + assumption checker green at the final evidence
layer + the real-run check passes (interim: its stand-ins) + every pin
in the ledger with its argument on file.

---

## The LLM task list (everything that is judgment, in one place)

1. Runner + batch mock authorship; shim-vs-target classification.
2. Mock-checker manifest entries: shim probe fixtures + target-mock
   ground-truth sides; the real-run fixture scenario.
3. Multi-statement mechanism enumeration (through fetches, preloads).
4. Pin neutrality arguments; the gate-column list (code reading).
5. Assumption-checker manifest entries (dimension, kind, expected label).
6. Branch-gated confirmations on the complement audit's single-variant
   list (is this predicate genuinely gated?).
7. Repair diagnosis; rule-P check design on every new violation.

Everything else is a script with an exit code.

## Gaps (§ = tracked in FINAL_REPORT open items)

1. ~~Fixture environment~~ CLOSED for diaspora (`concrete_env.rb` +
   per-batch `concrete_manifest.rb`); per-batch work = fixture rows +
   scenarios covering the corpus's branch families.
2. Corpus-side coverage runner flag (concrete checker's exact coverage
   side).
3. Fold patches not yet upstreamed — vanilla src/ FAILS
   `skipped_pcs_audit`; run Phase 3 with `--patched` until then.

### Note on the optional reference diff (C3) — subset sweep candidate set
When sweeping unknowns with the table-subset heuristic, widen the candidate
set to `tables(view) ⊆ tables(query) ∪ {principal-join tables}` (for
diaspora: `users`). The engine binds the principal as `users.id = $$(SYM..)`
and joins out; the reference folds `_MY_UID` into the joined column. Without
the widening the only views carrying the visibility predicate are never
tried, and the sweep reports resource-bound unknowns that are not real
(comments_index 2026-08-26: 9 → 0 unknowns in seconds). Template:
`reports/diaspora/results3/queries_from_runs/run_subset_ci_c2w.py`.

### Assumption checker at corpus scale (2026-08-26, src patch)
`assumption_checker.py` now builds the corpus index once (seeds, scenario,
recorded PC exprs per dump; only the chosen snapshot is loaded in full) and
runs the derived tests in two passes: pass 1 plans every probe, then the
distinct (scenario, seeds) roots are replayed in batches of
`ACHK_PROBE_BATCH` (default 40) per runner launch via EXTRA_SEEDS_JSON (a
list), dumps matched back by their recorded `concolic_seeds`; pass 2 issues
the verdicts. Verdict logic is unchanged (smoke: identical to the
one-launch-per-probe version). Reason: conversations_index's 848-assumption /
10 262-dump corpus made the old O(assumptions × dumps) selection and one JRuby
boot per probe run for hours — the gate is NOT optional; `complete` without
it is not complete.


### The three-phase closing process (2026-08-26, Bali)
1. **Fixed checks — the completion engine** (`coverage_report.py` →
   `concolic_engine/completion.py`): coverage checker, assumption gate
   (mandatory), shim extraction + tests, note check. Missing note check or
   assumption gate is reported BLOCKING.
2a. **Hardening lint — the parent runs `tools/hardening_lint.py`** before
   the adversary (and after every repair): the past wins as a mechanical
   pre-check, so an adversary round is never spent re-finding a known class.
   Every CHECK needs an answer — a repair, or a documented pin with its
   ledger entry.
2b. **Rig-crash census + per-request count check — the parent runs
   `tools/rig_crash_census.py <batch>`** (fails on any terminal raised by the
   rig's own code: `NotImplementedError` etc. — such runs recorded decisions
   without the statements) and reads the batch's count-based multiplicity
   result (per-request shapes must be 0 under / 0 over against the real
   runs). Coverage is a claim about decisions; these two are the claim about
   statements. Added 2026-08-30 after conversations cycle 21.
2. **SQL-consumer audits — run manually by the parent agent**
   (`src/queries_from_runs/audits/`): identity symbolicity, note lint, bind
   resolution, skipped PCs (`--patched`), PC visibility (`--gate`). All must
   exit 0.
3. **The adversary** (every win/near-miss lands in `ADVERSARY_WINS.md`; a
   TARGET-LEVEL win — one whose cause is the shared boundary, the shared
   association/mock toolkit, or a filter every controller runs — goes into
   that file's PROPAGATION MATRIX and is sent to every batch that has not
   applied it, so no endpoint pays for it twice) (`end_to_end_completion_checker/concrete/CONCRETE_CHECKER.md`):
   real runs, no mocks; evidence fidelity per target call is its duty. A
   win reopens the loop at phase 1.

### Parallel probe slots (2026-09-01, Bali)

The machine-wide JRuby mutex is replaced by **N slots**: `tools/slot <cmd>`
takes whichever of `/tmp/concolic-slot-{1..N}.lock` is free (`CONCOLIC_SLOTS`,
default 2) and holds it for the command's life. Every batch's
`assumption_manifest.json` runner and `completion_config.json` test_cmd go
through it.

The assumption gate keeps those slots busy with
`CONCOLIC_PROBE_WORKERS=<n>` (default **1** — unchanged sequential
behaviour): `ProbeCache` runs each chunk (one runner launch plus its single
replays) as an independent unit, safe because `run_probe` namespaces its seed
file and dumps by probe name. Verified behaviour-identical to the sequential
path by property test (same cache, same launch count).

**Memory, not cores, sets the ceiling** — each JRuby peaks ~1.2 GB on a 7.9 GB
box, so 2 workers; raising it risks the OOM kills of 2026-08-27. Set both
knobs together (`CONCOLIC_SLOTS=2 CONCOLIC_PROBE_WORKERS=2`); slots without
workers changes nothing, workers without slots serialises on the lock.

> **2026-09-15 — that ceiling is stale, and the knobs are now visible.**
> The 7.9 GB box is gone: this host has **16 cores and 68 GB**. At ~1.2 GB per
> JRuby the memory argument no longer justifies 2, and the companion finding in
> `_RESTART_HANDOFF_20260911.md` — "`CONCOLIC_PROBE_WORKERS` was useless ONLY
> because of the core count, and that conclusion expires with more cores" —
> expired with the same upgrade. The defaults are deliberately UNCHANGED (a
> default change is a behaviour change, and two campaigns are running); raise
> them on purpose after re-measuring.
>
> Every parallelism/resource knob now also has a CLI flag, under the rule
> **explicit flag > environment variable > default**. Every existing variable
> keeps working exactly as it does today.
>
> * `tools/slot --num-workers N ...`      (`$CONCOLIC_SLOTS`, default 2)
> * `python3 -m queries_from_runs.subsume --help`   (`$SUBSUME_SOLVER_THREADS`,
>   `$SUBSUME_TIMEOUT_MS`) — and `prune_subsumed(..., workers=N)` now exists
> * `python3 -m queries_from_runs.diff --help`      (`--parallel` /
>   `--timeout-ms` still work as aliases)
> * `python3 -m concolic_engine.completion --help`  (`$COMPLETION_AUDIT_TIMEOUT`)
> * `python3 -m resource_knobs --list` — **the whole inventory**, including the
>   env-only knobs of the frozen `assumption_checker.py`.
>
> `--show-knobs` on any of them prints what each knob resolved to and whether
> it came from the flag, the environment or the default — worth putting in a
> long run's log so the tuning is recorded.

### MANDATORY before every extraction (2026-09-01, comments C12)

**Run `skipped_pcs_audit` BOTH ways — vanilla and `--patched
…/_experiment/variant_d` — and install the patch in the extractor if they
differ.** The vanilla `src/` fold silently discards the `(VAR == VAR(_))`
shape: every StringVal equality branch, i.e. `users.language == 'pl'`-style
locale arms and `posts.type == 'Photo'`-style STI arms. Measured on the
cycle-12 corpora:

```
comments_index      parsed 575 447 | DROPPED 73 461  -> RED   (patch REQUIRED)
conversations_index parsed 429 046 | dropped      0  -> pass  (shape absent)
```

Extracting comments without the patch would have dropped 73 461 recorded
constraints from the policy — silently, with a green-looking result. Its
extractor installs `variant_d/assoc_fold` and says so in the emitted header;
the effect is visible in view #1 (`… AND posts.type <> 'Photo' AND
users.language <> 'pl' AND users.language <> 'xx'`).

**conversations_index was CHECKED, not assumed:** its extractor does NOT
install the patch, and its corpus contains none of the shape (0 dropped either
way), so its 58-view policy is unaffected. **Every remaining endpoint must be
measured the same way before its extraction is trusted** — a corpus with a
locale arm or an STI arm will have the shape, and the failure is silent.

This is RUNBOOK gap 3 (patches not upstreamed into `src/`) biting a
deliverable rather than a test. Upstreaming `assoc_fold` into the shared fold
is behaviour-neutral where the shape is absent and correct where it is present;
it is the real fix and remains open as a deliberate task, not a rushed edit.
