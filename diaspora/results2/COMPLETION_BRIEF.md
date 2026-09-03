# results2 completion brief — combination coverage (read fully before acting)

The coverage engine was rewritten (2026-08-18, by Bali's direction). Read,
in order: `src/README.md` §Combination coverage, the main
`../README.md` §"Semantics (combination coverage…)", and the module
docstring of `src/concolic_engine/coverage.py`. Do NOT modify anything
under `src/` — the checker is frozen by explicit instruction; endpoints get
completed by better runs and better-argued assumptions, never by checker
changes.

## Semantics you are completing against

- `complete` ⟺ every Z3-satisfiable COMBINATION of branch outcomes over
  each maximal clique of the dependence graph was observed in a single
  run's executed path. The graph starts complete (every pair of distinct PC
  expressions is an edge = a standing combination demand). Only explicit
  assumptions relax it: `IndependenceAssumption(expr_a=…, expr_b=…)`
  removes exactly that one edge (the freed expr keeps all other edges);
  `UntrackedPathAssumption(expr=…)` removes an expression entirely (last
  resort); `SymbolicConstraintAssumption` prunes infeasible combos.
- Run termination does NOT cover combinations. A 404/guard path truncating
  before an inner PC leaves those cross-combos missing FOREVER unless you
  declare the independence — with an argument.
- `truncated=true` or `solver_lost>0` forces incomplete. `unevaluable_exprs`
  (unparseable PC expressions, e.g. over undeclared vars) are excluded from
  the universe and listed — an endpoint whose completeness rests on
  exclusions is NOT done; fix the dumps so the expression becomes checkable.

## The completion loop (per endpoint)

1. Extend the endpoint's `coverage_report.py` (batch-local, write freely):
   - load an `AssumptionSet` from a new batch-local `coverage_assumptions.py`
     in the endpoint dir (empty to start);
   - construct `CoverageChecker(runs, assumptions=…,
     max_missing_per_clique=256)` so completion is proven, not cap-sampled;
   - serialize `result.assumptions_to_dict()` and the new fields
     (`truncated`, `unevaluable_exprs`) into `coverage_summary.json`.
2. Run it. For EACH blocking missing combo decide, by reading the app code
   that hosts the decisions:
   - **Close by execution** (preferred): the combo's `concrete_values` are
     seeds — drive a DSE run with them (`ConcolicTargets.seed_overrides` /
     your runner's seed mechanism), producing a real dump whose path
     manifests the combo. Re-check.
   - **Close by assumption** (only when execution provably cannot manifest
     the combo): cite the file:line of the guard that makes it unobservable
     (e.g. `post_service.rb` raising RecordNotFound before the inner check
     can run) and apply the safety test in
     `src/concolic_engine/assumptions.py`'s IndependenceAssumption
     docstring — "can any combination of the two outcomes produce a call
     sequence/access pattern the individual outcomes don't?" Only if the
     answer is provably no, declare `IndependenceAssumption(expr_a=…,
     expr_b=…, description=…, agent_notes=<the argument, with code
     citations>)`. Expr-keyed (mock-boundary PCs share sources). Mind the
     per-run ordinal caveat: verify the expression names the same decision
     in every run before keying on it.
3. Iterate until `coverage_complete: true` with `truncated: false`,
   `solver_lost: 0`, and every remaining assumption argued in
   `coverage_assumptions.py` comments + your report.
4. If an endpoint honestly cannot reach complete (combos neither runnable
   nor honestly assumable), STOP and report that state exactly — a false
   complete is worse than an incomplete.

## Ground rules

- `src/`, the diaspora app source, and `../concolic_targets.rb` (shared)
  are read-only. Your endpoint dir (incl. its private `concolic_targets.rb`
  and `targets.rb`) is write-freely.
- New runs: launch ONLY via `/home/dev/.claude/jobs/302ac302/tmp/concolic-slot`,
  `JRUBY_OPTS=-J-Xmx1000m`, check `free -h` first (wait below 1.2Gi
  available), kill only your own PIDs.
- Blanket-untracking to force complete is forbidden. Prefer: execution >
  independence (argued) > SymbolicConstraint (argued) > untracked (rare,
  argued).
- The harness refuses REPORT.md writes — return the full report as text:
  combos closed by new runs (count + example), every assumption with its
  argument, final summary JSON, and anything you could not close.
