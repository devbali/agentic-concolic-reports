# THE RECIPE — executable tests for mocks and assumptions
### (notifications_index rule-regime experiment, night of 2026-08-19 → 20; evidence base: `_experiment/ROUNDS.md` + variants A/B/D RESULT.md + control)

Every test below is a SCRIPT WITH A METRIC — no inspection-only rules. Each
entry: what runs, the metric and threshold, and the one-line experiment
evidence for why it earned its place (or was cut). Ordered as a pipeline:
a new mock or assumption enters at M1/A1 and must clear each gate in order.

---

## Part I — tests for a NEW MOCK (or shim)

**M1. Leaf-probe (SQL/target isolation).** Run the REAL method on concrete
fixtures with every OTHER target still mocked; record interceptor
`TargetCall`s and connection-adapter touches (schema-cache pre-warmed so
Rails' own metadata SQL doesn't false-positive).
*Script:* `_experiment/variant_a/_leaf_probe.rb` (capture pristine
UnboundMethods before install; toggle per-method — 68 mocks probed on ONE
JVM boot). *Metric:* target_calls == 0 AND app-SQL touches == 0.
*Evidence:* the sweep validated the whole gen3 surface mechanically (0
false keeps), surfaced a dead `declare_target` (`Metal#head`), and caught
two harness-level bugs that inspection had missed for three generations
(singleton-class name collisions; inherited-no-override capture).

**M2. Coverage-metered fixture matrix.** M1's fixtures must execute 100% of
the probed method's real body lines (per-line waivers only with recorded
reasons). *Script:* same harness; TracePoint(:line) scoped to
source_location — **JRuby requires `--debug` or line events silently drop**
(A's empirical finding), denominator from a Ripper scan (documented
approximation; no RubyVM on JRuby). *Metric:* coverage_pct == 100 (or
waived). *Evidence:* the only probe failures that were REAL findings
(nested-call chains, rig-limitation branches) were exposed exactly by the
uncovered-lines report, not by the pass/fail bit.

**M3. Machine-readable ledger.** Every probe appends
{method, fixtures, target_calls, connection_touches, body_lines,
covered_lines, coverage_pct, waivers, verdict} to `LEAF_PROBES.json` (+ .md
summary). NOT_PROBED requires a recorded skip_reason. *Metric:* every
`declare_target`/prepend in the batch has a ledger row. *Evidence:* A's
98-row ledger is what made "0 mocks changed" a verifiable result instead of
a claim.

**M4. Design-mock note fidelity (kept from the standing discipline, now
with a metric).** A design mock's note must be real SQL: extraction over a
probe corpus must yield 0 "WHERE unavailable"/render-failed notes and 0
unlabeled degenerate SQL (`1=0` only on labeled `_persisted==False`
branches). *Script:* the validation sweeps in this endpoint's gen2/gen3
logs (corpus-wide grep + taken-flag correlation, pure python). *Metric:*
0 unlabeled occurrences. *Evidence:* these sweeps caught bugs 1/2a/2b and
verified their fixes corpus-wide (472/472 labeled).

**CUT from Part I:** mandatory pre-probe of DORMANT mocks (the ~61-80
not-reached-by-this-endpoint sites). Evidence: zero score effect in either
variant; the ledger's skip_reason row suffices until an endpoint actually
reaches them.

---

## Part II — tests for a NEW ASSUMPTION

**A1. Corpus-wide zero-violation count (necessary, not sufficient).**
*Script:* the foreclosure-matrix scan (pure python over dumps — pattern in
`notifications_index/coverage_assumptions.py`'s Tier-1 derivation; seconds,
no Z3). *Metric:* 0 violations with both populations ≥100 runs.
*Evidence:* this alone was the gen2 standard — and it let a STALE
assumption survive a corpus change (the `first_1` ordinal drift found in
the gen3 re-validation). Hence A2/A3.

**A2. Directed probe (both directions).** Seed the guard concretely to each
side (SEEDS_ONLY single runs); assert from the dumps' recorded events that
the foreclosed expr fires on the recording side and cannot fire on the
foreclosing side. *Script:* `_experiment/variant_b/_t2_divergence_run.rb`
(one fresh JVM per side). *Metric:* PC present on recording side, absent on
foreclosing side, in the DUMPS (never inferred from the seed dict).
*Evidence:* B's persisted-gate probe **falsified a wrong mechanism
hypothesis before it shipped** (sibling-`_persisted` guess → real gated
family = the through-association count PCs) — the flagship catch of the
whole experiment.

**A3. Data-flow divergence.** Line-trace both sides; the executed-line sets
must first diverge at the assumption's CITED code site, and the gated
recording lines must be present/absent on the right sides. *Script:* same
harness, Coverage-start-before-boot + per-side line-set diff. *Metric:*
divergence_line == cited guard site AND gated_lines subset/disjoint as
required, recorded in `ASSUMPTION_FLOW.json`. *Evidence:* B's
persisted-gate PASS pinned the mechanism to the exact
`collection_association.rb` null_scope? site — turning an argument into a
measured fact.

**A4. Blocklist on inconclusive probes.** A class whose A2/A3 probe cannot
be built or fails stays UNDECLARED regardless of A1 counts. *Script:*
`_T2_BLOCKED_CLASSES` wiring in B's `coverage_assumptions.py`. *Metric:*
declared tiers at check time exclude blocked classes (B verified live:
tier2=0 after blocking). *Evidence:* count-chain and one-sided classes ran
under this rather than being carried on counts alone.

**A5. Ordinal-stability guard (re-derivation trigger).** Assumptions keyed
on `SYM_RESULT_*_N` ordinals must be re-validated (A1 scan) after ANY mock
or code-path change; a corpus regeneration invalidates all ordinal-keyed
tiers until re-derived. *Metric:* the A1 scan re-run green on the new
corpus. *Evidence:* the gen1 finder-arm tier went stale on gen3 (ordinal
drift) — caught only because the re-scan is cheap and mandatory.

---

## Part III — corpus & pipeline tests (the levers that actually moved the score)

**P1. View-usability metric (extraction gate).** % of final extracted
queries with zero unresolved placeholders. *Threshold:* 100% or each
exception named. *Evidence:* THE decisive lever — folding `assoc_*` binds
(D's `assoc_fold.py`, now candidate for upstreaming into
`src/queries_from_runs/transform.py`) took usable views 13/28 → 30/30 and
reference coverage 15 → 30.

**P2. Named-missing-combination seeding.** Every coverage-checker missing[]
combo whose concrete_values exist must be replayed via SEEDS_ONLY before
being called unreachable; verify the conjunction in the resulting dumps'
PCs, never from the seed dict. *Evidence:* closed the 8-query
mentions/profile-chain family (D); REFUTED cleanly for types 4-7 (the
conjunction structurally cannot mint there) — both outcomes are wins.

**P3. Scenario/type minimum-coverage metric.** Per scenario root and per
STI-type profile: ≥1 bounded exploration round (the LIFO worklist starves
everything behind the first root). *Metric:* dumps-per-scenario/type > 0,
checked by label counts. *Evidence:* gen3's main round produced 0
typed/unread_only dumps and only type-0 exploration until per-type rounds
were added; B independently rediscovered and named the same structural
bias.

**P4. Diff protocol.** Incremental (resumable `_progress.json`), placeholder
queries pre-filtered from views (they crash the checker rc=-9 — B's
finding, D made it moot via P1), SUBSUME_SOLVER_THREADS=1, one systemd-run
cgroup ≥4200M, `--endpoint` scoping, timeout 15s with the QUALIFIER D
proved: 15s ≈ 120s held on the 13-view set (C vs A, verdict-identical) but
NOT on the 30-view set (2 proven rejections degraded to unknown) —
schedule a 120s recheck pass for unknowns, skipping queries with a
demonstrated per-query memory ceiling. *Evidence:* every diff completion
this night used exactly this shape; every failure violated part of it.

**P5. Never enumerate wide (standing rule, Bali 2026-08-19).** Coverage
checker at default cap-4 only; completeness evidence = the pairwise matrix
(pure python) + foreclosure proofs; k-way enumeration is timeout-truncated
sampling, not a total. *Evidence:* the 500-cap run cost 18 solver-minutes
to produce a number that was still a lower bound; the pairwise matrix
closed the same question in seconds.

**P6. Memory containment (swapless shared box).** Every heavy job in its
own systemd-run cgroup; flock-serialize JRuby; system watchdog killing
expendable >500MB processes under a 700MB floor; app.slice collective cap.
*Evidence:* zero kernel OOMs across a night that included five
cgroup/watchdog kills — versus two session-killing kernel OOMs the day
before.

---

## Part IV — THE REPAIR LOOP (Bali, 2026-08-20: "when they catch
wrongness they should make the agent come up with different mocks and
assumptions")

Tests are generators, not just gates. Every FAIL carries a
machine-readable WITNESS, and the agent is REQUIRED to synthesize a
replacement from that witness and re-run the test. The loop's only
terminal states are PASS or PROVEN-IMPOSSIBLE (with the witness attached).
"FAIL, kept anyway with a judgment note" is no longer a legal state —
round 1's variant A did exactly that twice (`head`, the Devise mock) and
this rule exists to outlaw it.

**R1 — the witness is the generator.** Each test's failure output must
name the repair site:
- M1 FAIL → the recorded target_call/SQL-touch site (file:line of the
  first violating call). Repair move: DESCEND — the violating line
  partitions the body; the smallest enclosing SQL-free callee below it is
  the new mock candidate. Re-run M1 on the candidate. (This is the
  function-boundary-split pattern the project already used by hand in
  Gate 1b — now driven by the probe trace instead of by reading.)
- M2 FAIL → the uncovered line numbers. Repair move: derive the branch
  conditions guarding those lines and ADD FIXTURES that take them; if a
  line is genuinely unreachable, a per-line waiver with the reason.
- A2/A3 FAIL → the counterexample run (foreclosed expr fired on the
  "foreclosing" side) or the observed divergence line. Repair move:
  RE-DERIVE the assumption FROM the witness — the actual divergence line
  names the true guard site; the counterexample's PC set names the truly
  gated family. Re-run A2/A3 on the revised claim. (Evidence this works:
  variant B's persisted-gate — wrong sibling-`_persisted` hypothesis
  falsified, corrected to the through-association count family BY the
  probe's own output, re-probed, PASSED.)
- P2 seed that fails to reproduce its combination → the seeded dumps' PC
  sets. Repair move: either a context-preserving reseed (base = a real
  run's full seed dict, overlay the flip — the round-1 fix) or, if the
  conjunction structurally cannot mint, CONVERT the finding into the
  matching independence/N-A declaration and verify it via A1-A3 (round
  3's types-4-7 refutation is the worked example).

**R2 — bounded iteration.** Each mock/assumption gets a repair budget
(default 3 loop turns). Exhausting it without PASS forces the
proven-impossible path: the claim is withdrawn (mock removed / assumption
undeclared) and the final witness recorded in the ledger. Never ship the
original despite the FAIL.

**R3 — ledger closure.** LEAF_PROBES.json / ASSUMPTION_FLOW.json entries
gain a `repair_chain` field: the sequence of (witness → revision →
re-test verdict) triples. An entry whose final verdict is FAIL with no
repair_chain is a discipline violation detectable by script (the ledger
check in M3).

## Out-of-scope residues (documented, not test-fixable)

- The 6 before_action/layout queries (auth chain, admin roles, services,
  own profile/person/user rows): a deliberate, load-bearing runner-scope
  decision (`ctrl.send(:index)` + `layout false`); closing them means
  driving `process_action` — a separate wall-family project.
- The bare `notification_actors` join-table row: extraction-granularity gap
  (no producer event distinguishes it from the folded people-join);
  candidate for a future transform improvement, one query.
- ~35 reference unknowns: blockaid per-query solver capacity on 5-9-table
  joins; one query has a memory ceiling this box cannot clear at any cap.

## Scoreboard that validates the recipe

| stage | reference covered / rejected (of 71) |
|---|---|
| results2 (pre-discipline) | 1 / — |
| gen2 (bugs 1+2 fixed) | 7 / 22 |
| round 1 (probed rules, old extraction) | 15 / 16 |
| **round 2 = this recipe** | **30 / 6 (all 6 = the documented scope residue)** |
