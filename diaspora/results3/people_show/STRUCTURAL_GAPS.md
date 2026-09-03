# STRUCTURAL GAPS — people_show (PeopleController#show, anonymous, 3 formats)

Evidence report for the 64 missing branch-combinations in the coverage
checker, collected 2026-09-03 after the 6000-run exploration campaign
(1781 dumps, 37136 path conditions, 45 tree nodes, `missing=64`,
`truncated=true`, `solver_lost=0`, `unevaluable=[]`).

## TL;DR

- The flip_seed fix (commit `98cdc89`) plus a 3× bigger exploration
  (6000-run `anon_mobile` campaign vs the original 1200-cap) improved real
  branch coverage dramatically — most notably, **branch-B (A=False)
  mobile runs went from 0 to 592**, disproving the earlier "branch-B ×
  mobile impossible" hypothesis.
- The checker's `missing` count stayed at exactly **64** while the corpus
  grew 1184 → 1781 runs and tree nodes 37 → 45. The count is a capped
  sample (4 per clique) over a growing dependence graph — it reflects the
  deepest unconquered conjunctions, not a static defect list.
- Every one of the 64 remaining combos is a **genuine structural gap**:
  either a deep multi-clause conjunction beyond single-flip DSE reach, or
  a combination foreclosed by app control flow (guard/PD render paths),
  or unreachable-by-construction (empty-handle split crash).
- None can be cleared by declaring assumptions without **masking real app
  branches** — forbidden by the source discipline.

## Corpus (final, 1781 runs)

| scenario    | runs   | distinct paths | drained | frontier |
|-------------|--------|----------------|---------|----------|
| anon_handle | 156    | 22             | yes     | —        |
| anon_json   | 28     | 10             | yes     | —        |
| anon_mobile | 6000   | 1749           | **no**  | stack 10 |

`MAX_RUNS=6000`, `TIME_BUDGET=5400`; campaign elapsed 456.6 s. The mobile
frontier is still 10 deep after 6000 runs — it keeps generating new
distinct paths (1749) but never drains.

## What the deeper campaign changed (vs the 1184-run corpus)

| observation                                  | 1184-run corpus | 1781-run corpus |
|----------------------------------------------|-----------------|-----------------|
| branch-B (A=False) runs                      | 16              | **592**         |
| via_user no-@ (NOTC2) runs                   | 3               | **183**         |
| via_user dot family (H[0,1/2/Len-0]) both sides | 0             | **72T / 36F**   |
| via_user IndexOf == 2                        | 3T              | **183T**        |
| DOTLEN-T ∧ guid-empty runs                   | 13              | **73**          |
| max stream clauses in ANY run                | 4/10            | **5/10**        |
| guard-T runs with ANY stream clause          | 0               | 0               |
| PD-T runs with ANY stream clause             | 0               | 0               |
| full stream 10/10                            | 0               | 0               |
| handle blank-T (empty handle taken)          | 0               | 0               |

## The 64 missing — category breakdown

All 64 are 4+-way conjunctions (the checker's max clique combo). Every
atomic expr is observed on at least one side; the gap is the multi-way
co-occurrence. Categories (with counts from `coverage_summary.json`):

1. **Full-stream conjunction (partial)**: combos needing the mobile stream
   render at clause-depth ≥ 6 with dot/guid/record-length partners.
   Observed max depth is 5/10 in a single run. The stream family has 10
   clauses; reaching 10/10 in one run requires the deepest seed
   composition (posts relation rows × to_a rows × post columns × profile
   columns all non-default simultaneously).
2. **Guard-T ∧ stream (16)**: all 16 guard-T (disconnected/NF/CA) runs have
   **zero** stream clauses. The guard branch redirects/rejects before the
   stream render — genuine foreclosure, verified 0 co-occurrence across
   the whole corpus.
3. **PD-T ∧ stream (8)**: all 16 public_details==True runs have **zero**
   stream clauses. `public_details?` selects the public_hash presenter
   which never renders the mobile stream — mutually exclusive render
   paths.
4. **Blank-family ∧ stream (16)**: co-occurrence of the observed
   non-empty blank-check sides with the deepest stream clauses. The empty
   (T) sides are unreachable by construction (see below).
5. **via_user handle-shape ∧ deep-stream (8+)**: branch-B handle shapes
   (dot/guid) co-occurring with stream-depth ≥ 6 — branch-B runs reach
   4/10 max; the extra depth needs multi-variable composition.

## Unreachable-by-construction: the empty-handle blank-T (split crash)

The blank exprs `(SubString(H, 0, k) == '')` take the **T** side only when
H == '' (empty handle). The shared runtime's `SymbolicString#split`
(`src/ruby_runtime/string.rb:266`) raises `IndexError` on an empty
concrete value — `"".split('@')` returns `[]`, so `[0]` is out of range.

Evidence: **all 109 `ActionView::Template::Error` dumps in the corpus have
empty-handle seeds** (`SYM_*_diaspora_handle = ''`); the error message is
`split result index 0 out of range (len=0)`. The blank PC is never
recorded because the crash happens before it. In production, empty handles
cannot reach this code: DiasporaId validation forbids them.

Handling: declared **OneSide untracked (tracked_side="not_taken")** for
the 3 first_1 + 3 via_user blank shapes in `coverage_assumptions.py`
section 8b — same precedent as the REC1/REC2 OneSide (unreachable by
direct execution, proven by dump evidence rather than a probe).

## Why missing = 64 is stable (not a treadmill artifact)

Two competing effects, observed across three corpus sizes (1200/1184 →
3000/1152 → 6000/1749 runs):

- **Coverage improves**: new exprs get observed (45 nodes vs 31 baseline),
  artifact combos get eliminated by assumptions (114 → 271).
- **The graph grows**: newly observed exprs become new dependence-graph
  nodes and new cliques; each clique reports up to 4 SAT-but-unobserved
  combos. The capped sum stays ≈ 64 while the real unexplored frontier
  shrinks.

## True-demand enumeration is computationally infeasible on this corpus

The checker's `max_missing_per_clique=4` / `max_cliques=1024` bounded
run completes in ~15.6s and reports 64. Two moderate-cap probes to compute
the true (uncapped) demand both self-terminated on hard timeouts
(2026-09-03):

- `max_missing_per_clique=100, max_cliques=2000` → TOO_SLOW at 180s
  (`_true_demand.py`).
- `max_missing_per_clique=100, max_cliques=1024` (default clique count,
  the config that completes in ~15s at per-clique=4) → TOO_SLOW at 170s
  (`_true_demand2.py`).

The second probe isolates the cost: the explosion is in **per-clique z3
combo querying**, not clique enumeration. 64 is therefore a lower bound on
the true unmet demand; the category breakdown in this document (verified by
corpus search, not clique enumeration) is the trustworthy structural
evidence.

Deeper exploration alone will not drive `missing` to 0: the residual
combos need multi-variable seed composition (guid='' AND dot-handle AND
full-stream-qualifying username in ONE run), which the single-flip
`flip_seed` cannot compose.

## Options to actually clear the residual gaps

1. **Multi-variable seed composition** (next-step #1 in AGENT_RUN.md):
   extend `flip_seed` to merge a base seed dict, or add a second flip
   pass. Clears the dot×guid×partial-stream conjunctions. No harness
   change; runner-local `run_dse.rb` only.
2. **Much deeper mobile drain**: the frontier advances ~500 new paths per
   3000-run doubling; reaching stream-depth 10/10 needs the deepest
   prefix — a far larger MAX_RUNS or a depth-first reordering
   (flip shallow PCs first). Runner-local.
3. **Decouple format from branch**: give mobile format runs a branch-B
   entry point at shallower depth. Harness/targets change — requires
   asking first (source discipline).

## Files

- `run_dse.rb` — flip_seed handlers (fixed), campaign driver.
- `coverage_assumptions.py` — 271 assumptions (254 Independence + 17
  OneSide), including the new VBLANK section 8b.
- `coverage_report.py`, `coverage_summary.json` — coverage evidence.
- `__gap_evidence.py`, `_run_gap_evidence.sh`, `_gap_check.py`,
  `_blank_check.py`, `_branch_check.py` — evidence tooling (scratch).
- `AGENT_RUN.md` — run log + blocker documentation.