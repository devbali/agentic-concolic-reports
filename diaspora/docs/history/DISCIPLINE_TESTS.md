# results3 discipline addendum — empirical verification tests (Bali directive, 2026-08-19)

Two new REQUIRED test classes extend `../README.md` §THE DISCIPLINE. Rules
are no longer satisfied by argument alone — each mock and each assumption
must pass its executable test in the live concolic environment.

## T1 — the mock leaf-probe (required for EVERY mock/shim)

> Whenever a mock is instituted, run the REAL function with concrete
> values and verify that no SQL query is issued and no declared target
> function is called.

Mechanics (in the batch's JRuby rig, `RAILS_ENV=concolic`):

1. Boot the environment with all targets declared EXCEPT the method under
   test (probe mode: skip its `declare_target` / don't prepend its shim).
2. Build concrete fixtures for the receiver and arguments (plain Ruby
   values / `allocate`d models with concrete attrs — no symbolic types).
3. Invoke the real method. During the call, record:
   - every `TargetCall` the interceptor logs (`@all_calls` delta) — any
     entry = the real body CALLS A DECLARED TARGET → mock forbidden;
   - any touch of the connection adapter (hook `execute`/`exec_query` to
     raise a `ConcolicLeafProbeViolation`) — any hit = the real body
     ISSUES SQL → mock forbidden.
4. A mock is admissible only if the probe completes with zero target
   calls and zero connection touches, across at least the fixture matrix
   {nil-ish, typical, boundary} for each argument.
5. **Coverage rule (Bali, 2026-08-19): the probe fixture matrix must
   achieve FULL line coverage of the probed method's body**, measured by
   Ruby's `Coverage` stdlib (or a TracePoint line collector) scoped to the
   method's `source_location` range. The probe suite MAY mock declared
   sub-functions (that is what the interceptor already does), but the
   metric is over the real body's executable lines: any line the matrix
   never executes is a branch the probe never checked — and a branch that
   could hide SQL. Verdict is PASS only at 100% (lines proven unreachable
   get an explicit per-line waiver in the ledger, with the reason).
6. Record every probe MACHINE-READABLY in the batch's `LEAF_PROBES.json`
   ({method, fixtures, target_calls, connection_touches, body_lines,
   covered_lines, coverage_pct, waivers, verdict}) plus a human summary in
   `LEAF_PROBES.md`. A mock without a recorded PASS is a discipline
   violation regardless of how obvious the leaf looks. These are scripts
   and metrics — a probe whose verdict is produced by inspection rather
   than by the harness does not count.

Existing mocks are grandfathered ONLY until their first probe run; the
probe sweep over a batch's full mock surface is part of bringing that
batch to gen3 standard.

## T2 — the assumption probe (required for foreclosure/exclusivity claims)

For each declared assumption whose argument is "on side S of guard G the
code recording expr B never runs":

1. Construct the guard state CONCRETELY in the live rig (seed the guard's
   variable to the foreclosing side with everything else at defaults).
2. Execute the entrypoint body once.
3. Assert from the interceptor's recorded events that B's recording site
   did not fire (no PC with B's expr, no mint of B's variable).
4. Repeat on the recording side and assert B DOES fire — both directions,
   or the probe is inconclusive and the assumption stays undeclared.

Corpus-wide 0-violation counts (the gen2/gen3 standard) remain necessary
but are no longer sufficient: they show the explored runs never violated;
the probe shows a DIRECTED attempt to violate cannot.

**Data-flow divergence test (Bali, 2026-08-19) — required per foreclosure
class:** run the entrypoint under a line tracer (Coverage stdlib /
TracePoint) twice — once per guard side, concrete seeds, everything else
identical — and compute the two executed-line sets. The assumption PASSES
only if, mechanically:
1. the sets first diverge at the guard's cited code site (the branch line
   the assumption's argument names) — divergence anywhere else means the
   claimed mechanism is not the real mechanism;
2. the foreclosed expr's recording site lines are a subset of the
   recording-side set and DISJOINT from the foreclosing-side set.
Output per assumption class into `ASSUMPTION_FLOW.json`
({class, guard, guard_site, divergence_line, gated_lines,
present_on_recording_side, absent_on_foreclosing_side, verdict}) plus an
`ASSUMPTION_PROBES.md` summary. A class without a mechanical PASS is not
declared, whatever the corpus counts say.

## T1b — note/statement-set equivalence (Bali, 2026-08-21)

M4 sharpened into an executable check: run the T1 probe on the real body
and record the FULL SET of SQL statements the connection hook observes;
the mock's note(s) must correspond one-to-one to that set. A mock whose
note renders one folded statement where the real body issues two (e.g.
the through-association intermediate `notification_actors` fetch folded
into the people join) is a note-fidelity violation even though each
rendered statement is individually real. Found via the reference diff's
single proven-rejected query.

## T1c — pin branch-neutrality (Bali, 2026-08-21)

A concretization pin (identity shim) is admissible ONLY with proof that
no reachable branch depends on the pinned value's variation — mechanical
form: line-coverage of the pinned value's consumer sites must be
achievable across the pin's value domain, or a SEEDED DECISION must
exist per branch-relevant dimension (nil-ness, emptiness, pattern
presence — each one, not just the first found). The §5g `text` pin
carried a `_text_has_mention` seed but no `_text_nil` seed; the
foreclosed `message.present? == false` side hid the ENTIRE photos query
family (10 reference queries) across 8,000+ runs with zero recorded PCs.
Return symbolic (or per-dimension-seeded) values from mocks; a bare
concrete pin is the same failure class as the truthiness gap, silent by
construction.

## T3 — the repair loop (Bali, 2026-08-20)

A T1/T2 FAIL is not a terminal verdict — it is an input. Every failure's
machine-readable witness (violating call site, uncovered lines,
counterexample run, divergence line) must drive a synthesized replacement
(descended mock, added fixtures, re-derived assumption), which re-enters
the same test. Terminal states: PASS, or PROVEN-IMPOSSIBLE with the final
witness recorded. Bounded (default 3 repair turns), ledgered as a
`repair_chain`, and "FAIL kept with a note" is a scriptable discipline
violation. Full repair-move table: `MOCK_TEST_RECIPE.md` Part IV.

## Scope

These tests bind every future mock/assumption in results3 and the probe
sweep is retroactive per batch. `notifications_index` is the pilot (see
`MOCK_RULE_EXPERIMENT.md` for the variant comparison that selected the
final rule-set).
