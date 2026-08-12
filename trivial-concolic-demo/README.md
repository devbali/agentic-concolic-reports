# Trivial Concolic Demo

## Entrypoint
**Chosen:** A trivial integer comparison function (Option B)

```python
def is_positive(x: int) -> bool:
    return x > 0

def entrypoint(x: int) -> str:
    if is_positive(x):
        return 'positive'
    return 'non-positive'
```

**Why:** This is the simplest possible concolic execution that exercises the full framework pipeline:
1. **SymbolicInt** wrapping of an input variable
2. **Path condition recording** on the `>` comparison
3. **CallInterceptor** with `@target` on the helper function
4. **CoverageChecker** tree building from path conditions
5. **Z3 solver** generating concrete values for the missing branch

Option A (`check_permissions`) was considered, but the `@target` signature accepts a `User` object and a `List[str]` — neither of which cleanly maps to a single SymbolicInt/SymbolicString. The concolic framework currently wraps top-level args (int → SymbolicInt, str → SymbolicString) but has no built-in List wrapper.

## Symbolic Variables
- `x: int` — wrapped as `SymbolicInt(x, name='x')`
- The return value of `is_positive` is automatically wrapped as `SYM_RESULT_is_positive_1` (see `CallInterceptor.target`)

## Input Domain
- `x` is an integer (no explicit bounds were set)
- Two concrete paths exist: `x > 0` (positive) and `x <= 0` (non-positive)

## Run Iterations

### Iteration 1: `x = 5`
| Field | Value |
|-------|-------|
| Input | `x = 5` |
| PC 1 | `(x > 0)` taken=True (in `is_positive()`) |
| PC 2 | `(SYM_RESULT_is_positive_1 != 0)` taken=True (in `entrypoint()`) |
| Result | `'positive'` |
| Coverage | 2 tree nodes, 1 missing branch |
| Z3 suggestion | `{'x': 0}` — satisfies `Not(x > 0)`, the cheapest SAT value |

### Iteration 2: `x = 0`
| Field | Value |
|-------|-------|
| Input | `x = 0` |
| PC 1 | `(x > 0)` taken=False (in `is_positive()`) |
| PC 2 | `(SYM_RESULT_is_positive_1 != 0)` taken=False (in `entrypoint()`) |
| Result | `'non-positive'` |
| Coverage | 3 tree nodes, 0 missing |
| Complete | ✅ **True** — all branches explored |

## Cycle Summary

| Iteration | Input | Path via `is_positive` | Missing After | Coverage Complete |
|-----------|-------|----------------------|---------------|-------------------|
| 1 | 5 | `x > 0` → `True` → `if` taken (`'positive'`) | not_taken branch: `x <= 0` | No |
| 2 | 0 | `x > 0` → `False` → `if` not taken (`'non-positive'`) | — | **Yes** |

The concolic cycle required 2 runs to achieve full coverage.

## Generated Files

| File | Description |
|------|-------------|
| `dump_iter1_x=5.json` | RunDump from iteration 1 (call, symbolic_call, 2 PCs) |
| `dump_iter2_x=0.json` | RunDump from iteration 2 (call, symbolic_call, 2 PCs) |
| `coverage_summary.json` | Final coverage result (complete=true, 3 tree nodes) |
| `run_demo.py` | Script that runs the cycle |
| `README.md` | This file |

## Key Observations

1. **Extra PC from bool context:** The `if is_positive(x):` statement generates TWO path conditions: the `(x > 0)` PC inside `is_positive`, plus `(SYM_RESULT_is_positive_1 != 0)` PC in `entrypoint` from the bool conversion (`__bool__`) of the return value. This is correct behavior — both are legitimate branches.

2. **Solver warning about `Not((SYM_RESULT_... != 0))`:** This warning appears from Z3 because `bool != 0` evaluates to the Python integer `0` or `1` at parse time rather than staying as a Z3 expression. The constraint `SYM_RESULT_is_positive_1 != 0` relies on SymbolicInt.__ne__ which the solver's `eval` doesn't handle natively. The coverage result is still correct because the primary branch `(x > 0)` is what drives path exploration. This is a known limitation when the symbolic function's return value is evaluated in boolean context — a fix would convert `__bool__` PCs to use the symbolic result variable directly (e.g., `SYM_RESULT_is_positive_1 == True`).

3. **Coverage tree:** After 2 iterations, the tree has 3 nodes (root `(x > 0)` with both `taken` and `not_taken` children, plus the `<leaf>` marker). All branches are covered.