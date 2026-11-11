# Independence-assumption support for the blind-eval box agent

Context: the blind agentic re-eval (full1) measured ACE with the batch/coverage agent
**never declaring `IndependenceAssumption`** — the lean `brief_app.md` only taught
`UntrackedPathAssumption`, and the box's local gate `coverage_report.py` silently dropped
any independence declaration. On heavy frameworks (phpMyAdmin) the coverage frontier is a
cross-product of independent bootstrap `isset`/`==null` reads that never closes without
independence, so full1 under-measured ACE there. This restores the ability to use it.

## What changed (two files)

1. **`coverage_report.py`** — the agent's local "am I complete?" check.
   - Loader now uses the engine's canonical `declared_assumption_set(...)`, which parses
     **both** accepted kinds, instead of the old hand-rolled loop that only handled
     `UntrackedPathAssumption`. So an independence declaration now actually applies to the
     local `coverage.check`, matching how the gate evaluates it.
   - Adds `decisions_by_file` (each run's branch-decision `expr`s grouped by source file)
     and `assumption_refusals` to the output, so the agent can name decisions when writing
     an `IndependenceAssumption` and see malformed records rejected locally.

2. **`brief_app.md`** — adds step 6 teaching the agent to declare `IndependenceAssumption`,
   adapted from the canonical `sweep/briefs/batch.md` guidance ("a licence not to explore",
   declare specific non-interacting decisions, the gate re-verifies, never self-confirm).

## REMOVED

`make_independence.py` (an auto-generator that blanket-declared every non-`$SCRIPT` file's
branches independent) — unnecessary and off-pattern. The canonical agent writes
`assumptions.json` itself and reasons about which decisions are independent; it does not run
a generator.

## KNOWN DIVERGENCE — the frozen engine is older than current sweep

The canonical brief `sweep/briefs/batch.md` targets a **newer** sweep/concolic than the
frozen eval engine (`agentic_concolic_engine-inj`, 1f03ca4):

| | canonical `batch.md` | frozen `-inj` engine (this eval) |
|---|---|---|
| assumption kinds | 6 (`Independence`, `SymbolicConstraint`, `UntrackedPath`, `OneSideUntrackedPath`, `Alias`, `Foreclosure`) | **2** (`Independence`, `UntrackedPath`) |
| `IndependenceAssumption` schema | `source_a, source_b, expr_a, expr_b` (one pair/record) | **`a`, `b` decision lists** (disjoint within a record) |

So the step-6 guidance above is **adapted to the frozen engine's 2-kind, `a`/`b` schema**,
not a verbatim copy of `batch.md`. Open question for the redo: evaluating the frozen engine
measures an ACE missing 4 of current sweep's 6 assumption kinds. Deciding whether to (a) run
the frozen engine with the 2 kinds it has, or (b) move the eval to a current engine, is a
separate call.
