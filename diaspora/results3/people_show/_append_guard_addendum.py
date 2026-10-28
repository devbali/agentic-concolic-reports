#!/usr/bin/env python3
"""Append a dated addendum to AGENT_RUN.md documenting the guard-True
foreclosure evidence and this re-run's verdict (2026-09-04)."""
import datetime

path = "/home/dev/project/reports/diaspora/results3/people_show/AGENT_RUN.md"

block = """
---

## 2026-09-04 — guard-True foreclosure encoded as SymbolicConstraintExclusions

**Directive (Bali 05:53):** encode the proven guard foreclosure as
`SymbolicConstraintAssumption` exclusions (`<guard_var> == False`) for the
guard branch vars in `coverage_assumptions.py`, re-run the bounded check,
and report the solver's own verdict. This turn verified the mechanism end-to-end.

### Evidence that guard-True forecloses `show` (no co-minting)

For EVERY guard branch var (`first_*_not_found` / `*_closed_account` /
`find_by_*_not_found`), a corpus-wide scan of the 5048 dumps
(`_guard_corpus_foreclose.py`) found:

| guard var taken True | runs | co-mints rows/to_a | co-mints handle/split |
|---|---|---|---|
| first_2_not_found   | 64 (all dump_replay_*) | 0 | 0 (only 1 PC each) |
| first_2_closed_account | 2 | 0 | 0 |
| first_1_not_found   | 4 | 0 | 0 |
| first_1_closed_account | 7 | 0 | 0 |
| via_user_closed_account | 4 | 0 | 0 |

`_guard_64enum.py` shows the 64 `first_2_not_found == True` runs are ALL
`dump_replay_*` and each contains only the guard PC plus the negated
upstream guards (RecordNotFound -> 404 render / AccountClosed ->
redirect_back aborts the run before the presenter/layout/data mints).

### The pinned exclusions (section 6c)

Added `_GUARD_EXCLUDE_TRUE` with `(X == False)` for all 7 guard branch vars
(both `_1`/`_2` ordinals + via_user) as `SymbolicConstraintAssumption`. The
solver's own `check_satisfiability(["(X == True)", "(X == False)"])` -> UNSAT
for every one (`_probe_solver_pin.py`), so any missing combo demanding
guard==True is pruned as UNSAT. 0 bare-positive guard conjuncts remain in
the post-run `missing[]` (verified `_classify_current.py`).

### Verdict (solver's own numbers)

```
COMPLETE=False; NODES=62; MISSING=64; BLOCKING=64;
PCS=130300; TRUNCATED=True; ASSUMPTIONS_USED=239; WALL=46.7s
```

The guard-True (foreclosed) combos are cleared from `missing[]` (0 bare-
positive guards remain). MISSING still reports the bounded sample of 64
because `max_missing_per_clique=4` caps the per-clique enumeration and the
remaining healthy-path cross-format combos (the 48 clean items + revealed
variants) fill the sample — `TRUNCATED=True`. This bounded ceiling is a
checking artifact, not residual guard demand; the genuinely-clean cross-
format items still need the FUTURE_WORK3 co-mint harness.

Commit scope (people_show-only): `coverage_assumptions.py`,
`coverage_summary.json`, `AGENT_RUN.md`.
"""

with open(path, "a") as fh:
    fh.write(block)
print("appended", len(block), "chars")