# Concolic Testing — Sub-Agent Workflow

Use this workflow to run concolic coverage analysis on any entrypoint in any language.

## Overview

The concolic framework has four phases:

1. **EXPLORE** — Run the entrypoint with seed values (no assumptions). See what branches fire and where the tree might explode.
2. **ASSUME** — Add minimal assumptions (independence, untracked conditions) to keep the run count feasible.
3. **EXECUTE** — Generate standalone run scripts and execute them to produce dump JSONs.
4. **VERIFY** — Run the CoverageChecker with assumptions to confirm completeness.

## Step 0: Find your report directory

Reports live under `/home/dev/project/reports/`. Create a new directory for each
entrypoint you analyze, e.g. `/home/dev/project/reports/my-entrypoint/`.

Copy the runner template from an existing report for reference:
- `/home/dev/project/reports/trivial-concolic-demo/` (minimal example)
- `/home/dev/project/reports/chattermate-get-chat-detail/` (full example with assumptions)

## Step 1: Understand the entrypoint

Read the source file for your entrypoint. Identify:

- **Symbolic variables**: Which inputs control branching? (auth type, permissions, DB result found/not-found, etc.)
- **Branch points**: Each `if`/`elif`/`else` on a symbolic value creates a path condition.
- **Target functions**: Functions that call external systems (DB queries, JWT decode, API calls). These must be declared as targets in your runtime.

## Step 2: Define targets

Every external boundary call must be a declared target. Two forms exist in
both the Python and Ruby runtimes:

| Mode | Description |
|---|---|
| **Body executes** | The real function body runs; the return value is automatically wrapped as a symbolic variable. Use for real implementations. |
| **Body skipped** (declarative) | The function body is never executed. A lambda/proc provides the concrete return value (or a `(value, sort)` pair). Use for modeling external boundaries. |

The lambda receives `(call_args, result_name)` and returns:
- A single concrete value (e.g. `0`, `1`, `"hello"`)
- Or a `(value, sort)` tuple for explicit Z3 sort (e.g. `(0, "Int")`, `("hello", "String")`)

Symbolic types available in the runtime:
- **SymbolicInt** — int, tracks all comparison operators
- **SymbolicString** — string, tracks `==`/`!=`
- **SymbolicList** — list, tracks `len()` via truthiness checks
- **SymbolicDict** — dict, tracks `len()` via truthiness checks

## Step 3: Define the entrypoint model

Build a simplified model of your entrypoint that uses only symbolic variables
and calls your target functions. The model's control flow (if/else on symbolic
values) is what the CoverageChecker analyses.

The model should be a function that:
1. Takes symbolic arguments as keyword parameters
2. Calls target functions (which return symbolic values)
3. Branches on those symbolic return values (`if not result:`, `if x > 10:`, etc.)
4. Returns a status string indicating which code path was taken

## Step 4: Define the runs

List every combination of concrete values you want to try. Start small (1-2 runs)
and expand until coverage is complete. Each run is `(label, kwargs_dict, expected_return)`.

The rule of thumb:
- Start with 1-2 seed runs (one "happy path", one "not found").
- Check coverage — Z3 will tell you which branches are missing and suggest concrete values.
- Add runs for the suggested values.
- If the tree explodes (2^N paths), add assumptions to collapse it.

## Step 5: Build the runner

Your runner script should implement these phases:

### Phase 1 — EXPLORE
Run the entrypoint with seed values and no assumptions. Print each run's PC count
and call events. Run the CoverageChecker to see the initial tree.

### Phase 2 — ASSUME
Define an `AssumptionSet` with:
- **`IndependenceAssumption`**: Two branch points that are mutually exclusive
  (different if/elif/else, one returns early). Declaring independence collapses
  the tree from multiplicative (2^N) to additive (2N).
- **`UntrackedPathAssumption`**: A branch that's not relevant to access control.
  Missing that side does not block completeness.
- **`OneSideUntrackedPathAssumption`**: Only one side of a branch matters; the
  other side is irrelevant.

### Phase 3 — EXECUTE
Generate standalone run scripts (one per label) that can be executed independently.
Each script should:
- Import and initialize the runtime
- Declare all target functions
- Define the entrypoint model
- Call `interceptor.run()` with the concrete values
- Save the dump JSON

Every dump JSON should embed its own generating script in the `"script"` field
for reproducibility.

### Phase 4 — VERIFY
Collect all dump JSONs, build a CoverageChecker with your assumptions, and
call `check_coverage()`. Save the result to `coverage_summary.json`.

## Step 6: Add assumptions (when needed)

If the coverage tree is too large, add assumptions to collapse it. See existing
reports for examples of well-justified assumptions.

**WARNING**: Assumptions must never cause false negatives (miss real bugs).
Only false positives are acceptable (reporting something as covered when it
technically isn't).

## Step 7: Run and verify

```bash
# Full workflow
python3 /path/to/run_concolic.py

# Verify existing dumps without re-executing
python3 /path/to/run_concolic.py --verify-only
```

Verify:
- `coverage_summary.json` has `"complete": true`
- All dump JSONs have a `"script"` field
- Standalone scripts in `runs/` are independently executable

## Reference

- **Concolic engine**: `/home/dev/project/src/concolic_engine/` — coverage.py, run.py, solver.py, assumptions.py
- **Python runtime**: `/home/dev/project/src/py_runtime/` — call_interceptor.py, int_.py, string_.py, list_.py, dict_.py
- **Ruby runtime**: `/home/dev/project/src/ruby_runtime/` — call_interceptor.rb, int.rb, string.rb, list.rb, dict.rb
- **Example reports**: `/home/dev/project/reports/trivial-concolic-demo/`, `/home/dev/project/reports/chattermate-get-chat-detail/`