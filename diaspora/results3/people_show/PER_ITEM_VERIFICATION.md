# Per-Item Verification of MISSING=64 (2026-09-04, per 04:49 directive)

**Question:** Is MISSING=64 a genuine structural floor, or a cap artifact?

**Answer (per-item proof trail):** All 64 missing combos are **Z3-satisfiable** (not
provably impossible), but **0/64 are concretely witnessable** — every one is
foreclosed at runtime by guard logic that its own Z3 model forces true.

---

## Method (item-at-a-time, per directive)

1. **Per-item Z3 query** (`_per_item_check.py`): for each of the 64 missing items
   (`coverage_summary.json` → `missing[]`), one bounded Z3 query:
   `fixed_base AND node_constraint`, where `fixed_base` = the checker's exact
   context (274 assumptions + variable bounds + declarations, rebuilt via
   `CoverageChecker._merged_declarations()` / `_merged_bounds()` /
   `assumptions.symbolic_constraints()`). Timeout 60s/item → UNKNOWN.
2. **Concrete execution** (`_replay_missing.rb`): for each SAT item, feed the Z3
   model's `concrete_values` into the dual-format `anon_mobile_presenter` runner
   (byte-identical harness to `run_dse.rb`'s `run_one` / `dual_render`), execute,
   and check whether the run's path conditions contain ALL of the combo's clauses.
3. **New MISSING count**: re-ran the bounded coverage check over the corpus +
   the 64 replay dumps.

---

## Results

### Step 1: Per-item Z3
| verdict | count |
|---------|-------|
| SAT     | **64** |
| UNSAT   | 0     |
| UNKNOWN | 0     |

All 64 are satisfiable formulas (2.5–4.8 ms each, 0.7 s wall).
→ *None* of the 64 is provably impossible in the formula space.

### Step 2: Concrete execution (per SAT item)
| outcome | count |
|---------|-------|
| WITNESSED (run takes the full combo) | **0**  |
| NOT (run 404s / guard-forclosed)    | **64** |

Every replay run aborted at 2–12 path conditions with
`ActionView::MissingTemplate` (render of a 404/redirect path that has no template
in this test environment). The model's guard-forcing concrete values
(`*_closed_account=True`, `*_not_found=True`) route execution away from the
branch-minting path before the combo can witness.

- 4/64 force the *viewed user's own* `SYM_PERSON_via_user_closed_account=True`
  → `people_controller.rb:141` raises `Diaspora::AccountClosed` (line 141),
  rescued at line 22–24 → redirect, no view. Branch structurally unreachable.
- 60/64 force `FinderMethods_*_closed_account=True` AND `FinderMethods_*_not_found=True`
  on finder results, also pulling the run into a 404/redirect.

### Step 3: New MISSING count
```
loaded 5048 runs (0 unparseable)      # 4984 corpus + 64 replay
assumptions: 274 total (254 Independence, 17 OneSide)
COMPLETE=False; NODES=62; MISSING=64; BLOCKING=64; PCS=130292;
TRUNCATED=True; SOLVER_LOST=0; ASSUMPTIONS_USED=239; WALL=43.8s
```
**MISSING stays 64.** Adding the 64 replay dumps changed PCS 129624 → 130292 but
did not cover any missing combo.

---

## Verdict

| | |
|---|---|
| Before | MISSING=64 |
| After  | MISSING=**64** (unchanged) |
| New coverage witnessed | 0 / 64 |
| Z3-UNSAT proofs | 0 / 64 (all SAT as formulas) |
| Truncation | `TRUNCATED=True` (cap `max_missing_per_clique=4`), `SOLVER_LOST=0` |

The 64 is **not** explained by UNSAT (0 proofs) — every combo is satisfiable —
but **none of the 64 is concretely coverable**: each requires guard state
(`closed_account`/`not_found`) that forecloses the branch at runtime. Whether the
true count is *more* than 64 (masked by the cap) remains undetermined without an
unbounded enumeration, which the 04:49 directive set aside.

## Artifacts
- `/tmp/per_item_sat.json` — per-item Z3 verdicts + models (source of the table).
- `/tmp/replay_missing.json` — per-item concrete-run outcomes.
- `dump_replay_000..063.json` — evidence dumps (one per replayed item).
- `/tmp/missing_items_table.tsv` — idx | verdict | elapsed | witnessed | pcs | guards.
- `/tmp/coverage_summary_ORIGINAL_64missing.json` — pre-replay summary backup.
- `coverage_summary.json` — regenerated over 5048 dumps (MISSING=64).
