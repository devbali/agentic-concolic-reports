# Diaspora concolic experiment

Extract, for each Rails endpoint, the **set of SQL queries it can issue** —
its access policy — by running the real app under a concolic (concrete +
symbolic) engine, and prove the set is complete **without any reference
policy**. The app runs for real on JRuby; ActiveRecord query methods are
intercepted at the framework boundary and return symbolic values, so the
app's own branches on query results record path conditions, and each
intercepted call records a NOTE: the statement it stands for, with `$(VAR)`
binds. The corpus of runs (`dump_*.json`) is the evidence; the policy is
folded out of it.

There is no oracle. Completeness is a property we have to establish
ourselves — that is what everything below is for.

---

## Where things are

```
reports/diaspora/
├── README.md              ← this file: what the project is, state, how to run it
├── docs/                  ← the live process documentation
│   ├── RUNBOOK.md         ← THE PROCESS: actors, the loop, every tool, ops
│   ├── DISCIPLINE.md      ← the rules: Class S/B, D1–D3, Rule T (shared boundary)
│   ├── CHECKS.md          ← each check in detail, with examples
│   ├── TARGET_FUNCTIONS.md← what the target functions ARE (the query boundary)
│   ├── ADVERSARY_WINS.md  ← ledger of every gap a real run found + patterns
│   ├── TODO.md            ← DEFERRED work: what is not being done and why
│   ├── ASSUMPTION_KIND_UNIFICATION_20260915.md ← design note: independence
│   │                        and confinement license the same thing (not live)
│   └── history/           ← superseded plans, audits and reports (kept, not live)
├── tools/                 ← project-specific scripts (SQL/extraction level)
│   ├── policy_loadability.py ← written vs loadable per policy, via the
│   │                        project's own SQL loader (subsume/check_subsumed.sh)
│   ├── policy_coverage.py ← tables + table.columns two policies mention,
│   │                        as a "nothing was lost" differential
│   │                        (extraction itself: `python3 -m queries_from_runs`)
│   ├── hardening_lint.py  ← past adversary wins as a mechanical pre-check
│   ├── note_fidelity_audit.py, statement_diff.py, complement_audit.py
│   └── extraction_differential/ ← old-vs-new view sets over all six corpora;
│                            run it for ANY change that can move reconstruction
├── queries_config/        ← THE APP CONFIG: src/queries_from_runs is
│                            app-agnostic and takes this app as input
│                            (`app.json`, `resources/`, `validate_app_json.py`)
├── results3/              ← the live batches, one directory per endpoint
│   ├── <endpoint>/        ← runner, targets, shims, manifests, dumps, reports
│   │                        (+ POLICY_HEADER.txt — the extractor splices it)
│   └── queries_from_runs/ ← extracted policies (`<endpoint>.sql`) and, since
│                            2026-09-15, `<endpoint>_loadable.sql`: the same
│                            corpus re-extracted so that EVERY statement loads
│                            in the project's own SQL loader (see below)
├── results/, results2/    ← earlier generations (historical)
└── trash/                 ← retired scripts and artifacts
```

Engine code lives outside this tree:
`src/concolic_engine/` (coverage + completion), `src/end_to_end_completion_checker/`
(assumption gate, note check, the adversary brief), `src/ruby_runtime/completion_checker/`
(Ruby probes), `src/queries_from_runs/` (the fold, plus its five dump audits).

## How an endpoint is declared done

Three independent checks, on the same corpus — see `docs/RUNBOOK.md` for the
full flow:

1. **the completion engine** — `coverage_summary.json` ends with
   `"complete": true`: every branch combination covered or exempted by a
   declared assumption, every declared assumption tested by replay, every
   shim mock reaching zero targets at 100% line coverage, every target's real
   statements matching a corpus note;
2. **the five SQL-consumer audits** (`src/queries_from_runs/audits/`) — the
   dumps survive what the fold will do with them (binds resolve, PCs parse,
   principal binds are symbolic, notes are well-shaped, compared columns are
   PC-visible);
3. **the adversary** — a sub-agent that reads the real code and tries to make
   a REAL run (sqlite fixtures, no mocks) issue a target call the corpus does
   not have. A round with zero wins closes the endpoint; any win reopens (1).

A defect in a **target declaration** (the shared boundary) voids every
endpoint and forces a from-scratch regeneration — `docs/DISCIPLINE.md` §8,
Rule T.

## Active work in flight (2026-09-19 21:40) — check before starting anything

Several endpoints have background agents actively running right now. **Check
`systemctl --user list-units 'p44*' 'bench*' 'rc1*'` and the log files named
below before launching anything that might duplicate or collide with this
work.** This section is kept current as long-running work progresses; if you
are a new agent reading this, treat it as more current than the per-endpoint
table below for anything it mentions.

- **posts_show**: a real (non-scratch) Z3 completion-gate run is in progress
  in `results3/posts_show/` (log: `_coveragecheck_REAL2.log` or a successor —
  check for the newest `_coveragecheck_REAL*.log`). It has already hit and
  fixed two genuine `src/` bugs this pass (see the posts_show row below) and
  was, as of this writing, verifying whether a RED mock-note-fidelity result
  is real or a scoping artifact before relaunching the full gate. Do not
  relaunch this run yourself; check the log first.
- **people_show**: an agent is building this endpoint's completion-gate
  infrastructure from scratch (`completion_config.json`, `shim_tests.rb`,
  `concrete_run.json`, `assumption_manifest.json` — none existed before
  2026-09-19), then running it. Do not assume `coverage_summary.json`'s
  `coverage_complete: true` is the same claim as a completion-gate
  `OVERALL_COMPLETE` — the gate itself did not exist until this work.
- **comments_index, conversations_index, people_stream, notifications_index**:
  real completion-gate re-runs, orchestrated by a Sonnet agent (switched over
  2026-09-20 after the original Opus orchestrator hit a session rate limit --
  see below). **people_stream and notifications_index have landed real
  verdicts** (both rows above updated) -- neither is a clean pass, both
  findings are genuine. **conversations_index hit a real framework wall**
  (uncaught 6h subprocess timeout) and needs a retry in a quiet window --
  checkpointed, will resume not restart. **comments_index is still running**
  (started 2026-09-20 02:32, ~10.5 probes/min steady, no crash, 4,208
  declared assumptions). Full detail and the operational hazards found along
  the way (orphan dumps from a killed gate silently changing the loaded
  corpus size, `exploration_summary.json` being overwritten by every gate
  run, shared `tools/slot` lock contention between concurrently-running
  agents) are in `results3/_FULL_GATE_RUNS_20260919.md`.
- **Orchestrator model note (2026-09-20)**: the long-running posts_show,
  people_show, and this 4-endpoint gate sweep were all originally launched
  on Opus, before a later instruction to use Sonnet for all subagents.
  `SendMessage`-based "resume" does NOT change an agent's model (no such
  parameter exists on that tool) -- so simply resuming them kept burning
  Opus quota and repeatedly hit its session rate limit. Fixed by launching
  fresh Sonnet orchestrator agents that pick up the same underlying durable
  systemd services/checkpoints (no progress lost, only the orchestrating
  layer changed). If you are a new agent reading this: the old Opus agent
  IDs are dead ends, don't resume them.
- **Open decision, blocking posts_show's own RC-1 fix**: applying the
  RAILS_ENV/lazy_columns fix (below) to posts_show requires moving its
  `concolic_targets.rb` off the `627bac2c1199` commit it has been pinned to
  all session for campaign stability. Not done yet — needs a user decision.
- **RESOLVED 2026-09-19**: `notifications_index` IS genuinely affected by
  RC-1 (confirmed at the mechanism level, not just outcome) — see its row
  below and `_RAILS_ENV_MOD_FIX_20260919.md` §8. Fix not yet built (needs a
  new gated wide/narrow decision, more invasive than the other three
  endpoints' fix) — open follow-up, not urgent, not attempted same-day.

### RC-1 / RC-2 / RC-3 / RC-4 — the 2026-09-19 precision-vs-benchmark findings

Referenced by name throughout this table. Full detail and worked examples in
`results3/queries_from_runs/_PRECISION_VS_BENCH_20260919.md`. Found while
tracing why the six endpoints' policies score <100% disclosure_precision
against `/home/dev/project/policy-extraction-bench/`'s external reference
answer keys — **none of the four turned out to be a fabrication in our
extraction** (0 of 29 traced extra `(table,column)` pairs were bucket-(a)
genuine over-disclosure):

- **RC-1 — RAILS_ENV/lazy_columns mismatch (fixable, being fixed).** Under
  `RAILS_ENV=concolic`, `Profile`'s `lazy_load :bio,:gender,:birthday,:location`
  (`app/models/profile.rb:8`, gated on `Rails.env.include?("mod") ||
  Rails.env == "test"`) never activates, so every `profiles.*` read always
  includes those 4 columns; the reference environment excludes them by
  default. Fix has two parts, BOTH required (the env alone is inert — every
  endpoint's `profiles` projection is a hand-built string in its own
  batch-local mock layer, never read live from ActiveRecord): (1) a new
  `ruby_examples/dse-apps/apps/diaspora/config/environments/concolic_mod.rb`
  (committed; settings identical to `concolic.rb`, only satisfies the "mod"
  substring check) plus mandatory `concolic_mod:` sections in
  `config/{database,defaults,diaspora}.yml`; (2) a `default_projection(klass)`
  helper applied at each endpoint's own profiles-synthesis mock sites (one
  site per endpoint — the real Rails `#reload`/`unscoped` call — is
  deliberately left full-width, matching the real app's own escape hatch).
  Applied to comments_index, conversations_index, people_stream (all three
  verified via a branching-identical seed replay, so no fresh completion-gate
  proof was needed for the change itself). **NOT applied** to
  notifications_index (mechanism unverified — see its row above) or
  people_show (verified NOT applicable — would cost recall, the "reload"
  escape hatch structurally cannot fire there). posts_show confirmed affected,
  blocked on unpinning `concolic_targets.rb` (user decision).
- **RC-2 — the external reference is incomplete, not us (not fixable on our
  side, deliberately left alone).** `reports`, `tag_followings`, and `tags`
  (via `tag_followings`) appear in **zero** of the 13 reference answer-key
  files, but our corpus records them thousands of times — exclusively from
  `dump_mobile_*` runs (the mobile layout's drawer partial,
  `_drawer.mobile.haml`). The reference simply never drove that scenario.
  Explicit user decision 2026-09-19: do not edit the external reference to
  add these; document the gap, don't chase the number.
- **RC-3 — a parser bug in the benchmark itself, fixed 2026-09-19.**
  `policy-extraction-bench/bench/sqlnorm.py` mis-parsed a literal `SELECT 1`
  as a real column named "1" whenever the query had a FROM list (i.e. almost
  always) — generalized to a proper literal-constant check (`_LITERAL_RE`:
  any numeric/string/boolean literal, not just `"1"`), verified against both
  single- and multi-table cases plus real-column controls.
- **RC-4 — "aggregate-as-rows" in `src/queries_from_runs/transform.py:692-717`
  (not a bug, explicit user decision to leave as-is).** When a recorded
  statement's SELECT list is a bare aggregate (`COUNT(*)`/`SUM(t.c)`), the
  extractor substitutes the table's primary key (needed because the project's
  own downstream loader/Blockaid's determinacy model cannot represent a bare
  aggregate over an aliased self-join at all). This does disclose more than
  the literal aggregate value would on its own — flagged and discussed, but
  understood to be Blockaid's own established convention for representing
  aggregates as views, not a local invention — kept as-is.

## State (2026-09-19 21:40)

Sequential, one endpoint at a time. Standard for "done": engine
`complete: true` (0 FAIL / 0 NOT-TESTABLE) + the coordinator's audit sweep +
an adversary round with zero wins + the multiset matrix green — all on ONE
corpus. Scope is DISCIPLINE §15: post-auth entrypoint, symbolic principal;
the auth stages are the shared `results3/_auth_boundary/BOUNDARY_POLICY.md`,
unioned into every endpoint's policy.

| endpoint | standing | next |
|---|---|---|
| **conversations_index** | **CLOSED 2026-09-01**, precision-repaired 2026-09-19. Original close: engine complete (105 nodes, 0 missing, 18,623 dumps, 5,877 assumption probes PASS, shims 15/23/0); adversary R7 zero wins; multiset matrix 7/7 (one check, `cardinality_consistency`, judged 0-events-here, not retracted — see REPORT.md). **2026-09-19 (RC-1):** the RAILS_ENV/lazy_columns mismatch (below) fixed via a `default_projection` helper at 6 mock-synthesis sites + `RAILS_ENV=concolic_mod`, applied via seed-exact replay (not fresh exploration). Branching verified byte-for-byte identical (0/18,623 per-seed PC mismatches, seed multiset match) — this alone does not need a fresh completion-gate proof. `bench.grade` disclosure_precision **0.9286 → 0.9630**; remaining 4 extra `(table,column)` pairs are RC-2 (below), not a defect here. A full real completion-gate re-run was attempted 2026-09-20 and **did not reach a verdict — hit a real framework wall**, not a data problem: the assumption gate ran for the engine's own hardcoded 21,600s (6h) subprocess timeout and was killed by an *uncaught* `TimeoutExpired` in `concolic_engine/completion.py` (the audits path has a timeout guard at the same call shape; the assumption-gate path doesn't — a real, reportable `src/` bug, not yet fixed). No misleading result shipped: the crash fires before `json.dump`, so `coverage_summary.json` is still the untouched 2026-09-01 file. Root cause of the slowness also diagnosed: this corpus's legitimate duplicate seeds make the batched-probe path degenerate to serial single-JRuby-boot replay (6,236 assumptions declared, only ~5,209 probes completed in the full 6h window). The run is checkpointed (`ACHK_CHECKPOINT`) so a re-attempt resumes from those 5,209 banked probes rather than restarting — just needs one clean 21,600s window without box contention. Full detail: `_FULL_GATE_RUNS_20260919.md` §4. Policy: `queries_from_runs/conversations_index.sql` (stale, pre-fix — current output is `queries_from_runs/conversations_index_pcfold3_fix.sql`, not yet promoted to canonical) | retry the gate in a quiet window (checkpoint intact); consider mirroring the audits' timeout guard in completion.py; promote `_pcfold3_fix.sql` |
| **comments_index** | **CLOSED 2026-09-01**, precision-repaired 2026-09-17/19. Original close: engine complete (84 nodes, 0 missing, 26,528 dumps); adversary R10 zero wins. **2026-09-17/18:** found and fixed a real alias-collision bug in `src/queries_from_runs/transform.py` (naive first-free-slot alias counter was making distinct real producer identities render identically, fooling the pruning rule into dropping real predicates) — fixed via `zlib.crc32`-derived aliases. Re-verified 100% precision per this project's own definition across 4 defect classes (alias collision, reliable-pruning-witnesses inapplicability, mock-fabrication sweep, skipped_pcs semantics) — see `results3/queries_from_runs/_COMMENTS_PRECISION_FIX_20260917.md`. **2026-09-19 (RC-1):** same lazy_columns fix as conversations_index, applied and verified — `bench.grade` disclosure_precision **0.9604 → 1.0000**, exact column-set match with the reference, 0 branching drift across all 26,528 dumps. **2026-09-20: CORRECTION — the completion-gate re-run did NOT land, an orchestrator monitoring mistake reported a false positive.** A `coverage_summary.json` tail was captured right as the systemd unit exited and looked like a real `complete: true` verdict, but that file was stale (unchanged since Sep 13) — the run actually crashed on the same uncaught `subprocess.TimeoutExpired` at `completion.py:334`'s 21,600s hardcoded timeout that hit conversations_index (see conversations_index's row and `_FULL_GATE_RUNS_20260919.md` §4.1/§7) — the same real, still-unfixed `src/` framework bug, not a data problem. `_assumption_results.json` is empty; nothing was actually re-certified. Round 3 is now running (resumed from 8,798 banked checkpointed probes, not restarted). Policy: `queries_from_runs/comments_index.sql` (stale, pre-fix — current output `comments_index_pcfold3_fix.sql`, not yet promoted) | wait for round 3's real verdict; fix the uncaught-timeout framework bug; promote `_pcfold3_fix.sql` |
| **notifications_index** | **CLOSED + SHIPPED 2026-09-15** — `COMPLETE=True; NODES=441; MISSING=4; BLOCKING=0; PCS=8,883,622` on 138,912 runs; assumptions 27,231 declared / 2,004 tested; §17/X12 gate zero refutations. `MISSING=4` is four untracked transparency entries. **2026-09-19: mechanism-level investigation resolved the open RC-1 question — it IS genuinely affected, not correctly exempt.** The reference has 18 distinct `profiles` statement shapes: 16 narrow (14-col) and exactly 2 wide (18-col, gated on `Notifications::StartedSharing` + `public_details`/`contacts.sharing`, traced through `PersonPresenter#full_hash_with_profile` → `ProfilePresenter#private_hash`, HTML-only — JSON suppresses this branch via `no_aspect_dropdown: true`). Our mock emits wide unconditionally for every `profiles` note (`class_finder_sql`/`find_target`/`emit_includes_preloads`, no `default_projection` gate) — this is a real, uncaught RC-1-class over-disclosure. The earlier "0 extra disclosure pairs" finding was **coincidental**: both policies' column *unions* saturate to all 18 columns the instant even one wide shape is present, so getting the other 16 shapes wrong never surfaced in the aggregate diff. **Not yet fixed** — unlike the other three endpoints, there's no existing decision gate at note-synthesis time to distinguish the 2 wide shapes from the 16 narrow ones; a blanket `default_projection` narrowing (the other three endpoints' fix) would incorrectly narrow the 2 real wide cases too, turning today's accidental correctness into a real recall regression. The correct fix needs new logic gated on the already-traced `show_profile_info` decision (`targets.rb:1627-1655`) plus its own from-scratch branching-safety proof — deliberately scoped as a follow-up, not attempted same-day, given box contention (~load 49) and this endpoint's size (313,977 dumps, largest of the six). Full detail: `_RAILS_ENV_MOD_FIX_20260919.md` §8. Loadability audit: **142/142 pass (100%)** as of 2026-09-19 (this doesn't catch the RC-1 issue — loadability ≠ precision). **2026-09-20: real completion-gate re-run landed via the reuse wrapper — important correction to the CLOSED claim.** The gate itself is green and got STRONGER than the 2026-09-15 certification (`COMPLETION=True`, 0 blocking, 0 FAIL vs. the prior 65 NOT-TESTABLE) — but on the **full 313,977-dump corpus**, the coverage layer is genuinely **not complete**: 96 missing branches (92 blocking), all `combination`-type, `truncated=True` (an enumeration cap, not a solver failure, so 96 is a floor not a ceiling). The 2026-09-15 "CLOSED + SHIPPED" certification was run with `DUMP_LIST=_snapshot_c30_R5.txt`, a **pruned 138,912-dump snapshot** — that claim is real *for that snapshot*, but does not hold for the endpoint's full corpus. An apples-to-apples re-run against the same snapshot would resolve whether this is new drift or was always true; not yet done. Full detail: `_FULL_GATE_RUNS_20260919.md` §5. Policy `notifications_index.sql` (stale — current output `notifications_index_pcfold3_fix.sql`, not yet promoted, and doesn't yet include the RC-1 fix either since it isn't built) | build the gated wide/narrow profiles fix; re-run the gate against the certified snapshot to check for drift vs. genuine full-corpus incompleteness |
| **people_show** | **REOPENED 2026-09-19** (was SET ASIDE 2026-09-07). The RED that blocked closure — `identity_symbolicity_audit`, every `auth_*` scenario driving a CONCRETE principal (34 literal binds in the shipped policy) — is **fixed**: root cause was 4 shadowing pins in `targets.rb#signed_in_user` overriding an already-correct symbolic mint (fix was deleting pins, not adding machinery). Also fixed: **B-1** (class-level finder dropping its WHERE — 10→0 unloadable placeholder statements; a control extraction on the *old* corpus with the *new* `src` alone only reached 22, proving the redrive itself was necessary, not just the code fix). Redriven corpus (24,151 runs / 10,656 paths, 6/9 scenarios reproduce the original baseline exactly — proof only binds changed) reverified: `coverage_complete=True, NODES=97, MISSING=0, BLOCKING=0` — same node count as the original campaign, 18% fewer paths. **Honest shortfall**: 3 mobile scenarios time-capped on throughput (2.2 vs 9.4 runs/s), not yet fully drained. Loadability: **42.37% → 98.48%** (one remaining non-defect statement, `_SYM_POSTS_GUID`, TODO.md item 7). **RC-1 implemented but deliberately NOT activated** — would be a pure recall loss here: 798/800 dumps read all 4 lazy columns, and the "real `reload` fires" escape hatch that makes narrowing correct elsewhere cannot fire for people_show (`symbolic_instance`'s singleton readers shadow the lazy accessors entirely). **The completion gate itself never existed for this endpoint** (no `completion_config.json`/`shim_tests.rb`/`concrete_run.json`/`assumption_manifest.json` ever built) — being built from scratch as of 2026-09-19, see "Active work" above. Policy: `queries_from_runs/people_show.sql`, 66 views, re-extracted 2026-09-19 (prior kept as `.pre_f6repair_20260919`) | drain the 3 capped mobile scenarios; finish building + run the completion gate |
| **people_stream** | **CLOSED 2026-09-11** — `OVERALL_COMPLETE=True`, MISSING=0/TREE_MISSING=0, gate 30/30. **2026-09-18:** redriven for B-3 (`ActsAsApi::Collection#as_api_response` note carry-through) — extraction self-reported 7→0 unresolved binds. **2026-09-19: that self-report was wrong.** The real policy-loadability audit (which opens the shipped `.sql` and runs it through the actual loader, unlike any dump-side check) found **23 of 169 statements genuinely unloadable** — `SYM_PERSON_via_user_id` (X1, TODO.md item 5), a **resolver defect** (a producing SELECT *was* recorded but never inlined), not the "named principal leaf" the self-report used to wave it through — the project's own `app.json` classifies that exact name under `non_principal_identity_name`, the opposite of the dismissal. **X1 is still open, needs a Rule-T naming ruling**, not attempted. Separately, **RC-1 fixed and verified 2026-09-19**: `default_projection` at 2 mock sites + `concolic_mod` env, seed-exact replay, 0/13,677 branching mismatches, `bench.grade` disclosure_precision **0.9753 → 1.0000**, exact 158=158 column match. **2026-09-20: real completion-gate re-run landed — `OVERALL_COMPLETE=False`, 5 real BLOCKING items**, all genuine, none framework noise: (1) a latent 4-day-old regression — a 2026-09-15 code change added a `rescue Exception` shim-renderer path that the batch's own shim tests (last touched 2026-09-11) never exercise, silently broken since; (2)-(5) 4 newly-**inferred** ConfinementAssumptions all FAIL under the stricter X10 flip-both probe — the same class of genuine dependence already found and fixed in people_show, not yet addressed here. Coverage layer itself unchanged and verified byte-identical to the 2026-09-11 certification (39 nodes, 0 missing) — the delta is entirely in the gate, not exploration. Full detail: `_FULL_GATE_RUNS_20260919.md` §3. Policy: `queries_from_runs/people_stream.sql` (stale — current output `people_stream_pcfold3_fix.sql`, not yet promoted) | resolve X1 (Rule-T decision needed); fix the shim-test gap + the 4 confinement FAILs; promote `_pcfold3_fix.sql` |
| **posts_show** | **NOT CLOSED.** Header still opens "THIS ENDPOINT IS NOT COMPLETE" as of the last shipped snapshot (2026-09-15, `MISSING=706`). **2026-09-17-19: the prior session's diagnosis for the Class-B backlog (0/4111 walked, previously attributed to "base-selection steering" and, before that, §16f REFUTED as a genuine reachability barrier) has been superseded.** Real root cause, found by diffing base vs. driven dumps: `_p31_construct.py`'s seed-writer treats a canonical length pin (e.g. `records_photos == 0`) as universal, zeroing *every* raw ordinal backing it — when the pin is actually existential (both `_p23_index.py`'s collapse and `_p15_explain.py`'s `pol in t` test agree), so the constructor was destroying the exact reachability it was trying to construct. Fix: new `EMPTY_EXISTENTIAL`/`REACH_TIER` env knobs in `_p31_construct.py` (batch-local, `src/` untouched, verified byte-identical no-op when off). **Walk rate: 0/4111 → 3014/4111 (73.3%)**, size gate honored 0%→85.0%, strict dominance checked (0 regressions, 513 new). A real (non-scratch) completion-gate run is in progress — the first one ever to reach this endpoint's completion phase for real (earlier runs were accidentally scratch-mode). It has hit and fixed two genuine `src/` bugs along the way: `shim_extractor.rb` missing the `"key"` field `completion.py` requires (commit `c4e1446`, project-wide fix, affects every endpoint), and `mock_note_check.py`/`completion.py`'s `note_check()` lacking the directory-scoping + timeout handling every other audit already had (also now fixed, batch-local config change). Currently verifying whether a RED mock-note-fidelity result is real or a scoping artifact before relaunching the full gate — see "Active work" above. **RC-1 confirmed needed** (500/500 sampled dumps touch profile data) but blocked on a user decision: applying it requires moving `concolic_targets.rb` off its `627bac2c1199` campaign pin. Policy `posts_show.sql`, 119 views (stale relative to the REACH_TIER fix, not yet re-extracted) | finish the gate run; user decision on unpinning for RC-1; re-extract once settled |

Shared assets every later endpoint inherits: the auth-boundary policy (§8 of
that file says what is verified and what is NOT claimed), the post-auth scope,
`tools/slot` 2-slot parallelism, the rig-crash census, the DML-aware judges,
the repaired hand-seeder, and the multiset matrix protocol.

Extracted policies to date: `conversations_index.sql` (58 views, CLOSED),
`comments_index.sql` (79 views, CLOSED), `people_show.sql` (58 views — from a
milestone corpus, read its header first) and `notifications_index.sql` (83
views, STALE: a pre-engine cycle-2 corpus, superseded by the C7 run in
progress). Extraction is normally the last step of a closed endpoint; the
people_show file is the documented exception (extract-and-set-aside).

The reference policies that once lived in `ruby_examples/dse-apps/policies/`
are deliberately quarantined and unreadable; no agent may look for them.

## Loadability (2026-09-15)

**Per-endpoint numbers below are stale** — see the State table above and
`results3/_BENCHMARK_RUNS_20260919.md` for current figures:
comments_index/conversations_index/notifications_index now pass 100%,
people_stream is RED at 86.4% (the X1 defect), people_show improved
42.37%→98.48%, posts_show not yet re-measured since the REACH_TIER fix.

A shipped policy is read by SQL consumers through
`src/queries_from_runs/subsume/check_subsumed.sh`, and `subsume.py`'s own
contract is that a query the loader cannot take **"participates in no pair and
always survives"** — it stays in the file, is counted as a view, and silently
means nothing. Measured over the six shipped policies, **355 of 558 statements
(63.6%) loaded**; conversations_index was 11 of 58.

Two causes, both now fixed in `src/queries_from_runs` (nothing diaspora-
specific was added there):

1. **unresolved binds** — `$$(SYM_RESULT_<call>_<n>_<col>)` is "column of a row
   that call returned", i.e. a JOIN. The resolver only knew producers recorded
   as `symbolic_call` events; an association read chained off an earlier result
   is recorded on the VALUE (`symbolic_vars` note) instead, so every bind
   naming such a row shipped as a bare `_SYM_RESULT_…` token — unloadable, and
   over-permissive (a free token constrains nothing where the run proves the
   value is what that query returned). `RunTransformer.bind_producers` now
   registers those too, and the bind resolves by inlining that query and
   recursing on its binds, terminating at `_MY_UID` / `_NOW` / request params.
2. **shapes the loader cannot represent** — FROM-list subqueries, aggregates
   over an aliased FROM, outer joins. Rewritten by
   `RunTransformer._emission_conventions` into the readings the consumers
   already define (README rule 7).

`<endpoint>_loadable.sql` is each corpus re-extracted with both. The canonical
`<endpoint>.sql` files are UNCHANGED. What remains unresolvable is booked in
`docs/BOUNDARY_NOTE_GAPS_20260915.md`: every surviving placeholder is a value
whose producing query the RUN NEVER RECORDED (a description, a
`render_relation_sql` crash, or nothing) — Rule T, not an extraction defect.

```bash
PYTHONPATH=src python3 -m queries_from_runs --results results3 \
    --out results3/queries_from_runs --endpoint <endpoint> [--no-subsume] \
    [--sample N --sample-seed S] [--suffix S]
python3 tools/policy_loadability.py results3/queries_from_runs/*.sql
PYTHONPATH=src python3 src/queries_from_runs/audits/policy_loadability_audit.py \
    results3/<endpoint> results3/queries_from_runs/<endpoint>.sql
```

## Running things

```bash
# one JRuby at a time, machine-wide; always unset JAVA_TOOL_OPTIONS
flock /tmp/concolic-slot.lock scripts/diaspora-concolic /abs/path/runner.rb

# the engine report for a batch (needs ~5.5-6.3 GB at 20k dumps; run it alone)
systemd-run --user --pipe --wait -p MemoryMax=6300M -p MemorySwapMax=0 \
  --working-directory=/home/dev/project bash -c \
  'unset JAVA_TOOL_OPTIONS; PYTHONPATH=src \
   python3 reports/diaspora/results3/<endpoint>/coverage_report.py'
# (MAX_MISSING_PER_CLIQUE is no longer needed — one Z3 query per demand set
#  and one witness by default since 2026-09-12; DISCIPLINE §16d)

# the five SQL audits (coordinator)
PYTHONPATH=src venvs/queries_from_runs/bin/python \
  src/queries_from_runs/audits/<audit>.py reports/diaspora/results3/<endpoint> [...]

# the hardening lint, before any adversary round
PYTHONPATH=src python3 reports/diaspora/tools/hardening_lint.py \
  reports/diaspora/results3/<endpoint> --sample 400
```

Cost model: a concolic run is ~30 ms, but a JRuby launch is ~60–90 s, so
wall-clock is dominated by the number of launches (rounds, probes, concrete
scenarios) and by the assumption gate's replays — not by the runs themselves.

## Infrastructure

Java 21 + JRuby 9.3 (`/home/dev/tools/`), Rails 5.2.4.3 with a minimal
Gemfile, the app at `ruby_examples/dse-apps/apps/diaspora/`, Z3 via the
`venvs/queries_from_runs` virtualenv, sqlite (bundled JDBC adapter) for the
real fixture runs. Source-code discipline: `src/**` and the app are
coordinator-only; batch directories are write-freely.
