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

---

## Addendum 2026-09-03 23:10 UTC — cross-format join (the honest floor)

### The 48 "Group A" items are format-exclusive, not same-data

Late probe (`_len_census.py`, `_len_notes.py`, `_bare_ctx.py`) resolved the
identity of the row-count vars definitively:

- **Bare `len(Relation_records_1)` / `len(Relation_records_2)`** — value
  ALWAYS 0, **empty SQL note**, minted ONLY in non-mobile (html/json) runs
  (32 dumps). These are the presenter's `is_blocked?`/`has_contact?` on
  `current_user_person_block`/`current_user_person_contact` = `Block.none`/
  `Contact.none` in anon scenarios — the always-empty block/contact check
  (module docstring REC1/REC2, section-8 OneSide).
- **`len(Relation_records_N_rows)` ×3 + `len(Relation_to_a_1_rows)`** — the
  posts stream, minted ONLY in mobile runs (1749 dumps), all carrying the
  same `SELECT "posts".* FROM "posts" WHERE "posts"."public" = true` note.

The demanded conjunction `records_1==0 ∧ records_2==0 ∧ records_1_rows>0 ∧
to_a_1_rows!=0` joins two var families that live in DIFFERENT request
formats: `people_controller.rb #show` renders the stream ONLY in
`format.mobile`; `format.all`/`format.json` render the presenter only.
The join is structurally unreachable — a genuine gap, but of a different
shape than "same query minted twice".

### 2026-09-03 23:10: the 64→112→64 episode + mechanism change

Per user directive, 4b/6b Independence pairs were added for the
"same-data double-mint" (guards × complement forms, and bare records × rows
forms). Re-run: **MISSING 64 → 112** — WORSE. The Independence
edge-removal re-cliques the dense dependence graph (45 nodes, 17 OneSide
pins), producing more enumerable combos under the per-clique cap (the
same "192" phenomenon as the earlier dot-family episode). All runs are
`TRUNCATED=True`, so both numbers are capped-sample artifacts.

Resolution (this commit): revert 4b/6b; replace the counterproductive
Independence pairs with the framework's **`SymbolicConstraintAssumption`**
for the ONE genuinely same-query double-mint — the four posts-stream row
forms (`records_1_rows == to_a_1_rows == records_2_rows == records_3_rows`).
These are app-true (one Relation, four `.rows`/`to_a`/`records` reads;
identical SELECT notes) and prune fictitious row-corner combos at the SMT
level without touching the clique graph. Re-run: **MISSING = 64** (parity
with the honest baseline; assumptions_used 239 = baseline).

The bare block/contact `records_N` (always 0) are NOT equated with the
posts rows — that would equate block-count with post-count, masking a real
branch (forbidden by discipline). 64 is therefore the honest floor for this
checker/corpus: the only sound declaration for the format-exclusive join
(Independence) mechanically inflates the capped count, and any equality
across the two families would be dishonest.

## Files

- `run_dse.rb` — flip_seed handlers (fixed), campaign driver.
- `coverage_assumptions.py` — 274 assumptions (254 Independence + 17
  OneSide + 3 SymbolicConstraint): reverted 4b/6b, added the 3 same-query
  row equalities (net +37 vs 06d1019).
- `coverage_report.py`, `coverage_summary.json` — coverage evidence.
- `__gap_evidence.py`, `_run_gap_evidence.sh`, `_gap_check.py`,
  `_blank_check.py`, `_branch_check.py` — evidence tooling (scratch).
- `_len_census.py`, `_len_notes.py`, `_bare_ctx.py`, `_cmp_baseline.py`
  — 64→112→64 probe tooling (scratch, untracked).
- `AGENT_RUN.md` — run log + blocker documentation (addendum).

---

## Addendum 2026-09-04 00:40 UTC — multi-variable seed composition tried

Future-work #1 (multi-variable seed composition) was implemented
(`dse_compose.rb` + `run_dse.rb` integration: per-run 2-way and 3-way
composed children on DISTINCT symbolic vars, `COMPOSE_CAP=6` per way,
MRI-unit-tested 7/7) and a bounded campaign run (MAX_RUNS=6000,
TIME_BUDGET=900 — 305.5s, all three scenarios DRAINED, 1682 dumps).

**Verdict: MISSING stays 64 — bit-identical to baseline (0 cleared, 0
new).** The classification of the 64 therefore stands, now with a second
independent mechanism:

- 48 cross-format (bare block/contact `records_1/2` × posts-stream rows):
  format-exclusive by controller/template (stream only in
  `format.mobile`), provably unwitnessable by ANY seed set — composition
  included.
- 16 guard-foreclosed (`first_1/find_by/via_user not_found/closed_account
  == True` × stream attrs): control-flow foreclosure, not seed-reachability.

Composition DID improve pair co-reach density ~50% (e.g. `rows_gt0 ×
via_user_dot` 216→324 of 1682 dumps; `via_user_dot × via_user_guid_empty`
144→216) and drained the exploration, but the residual gaps need depth 8-10
conjunctions with cross-format or guard-foreclosed parts — out of reach for
any seed-composition strategy. The remaining documented lever is future-work
#3 (harness decoupling of format from branch — PERMISSION REQUIRED).

Evidence probes (scratch, untracked): `_co_reach.py`, `_co_cmp.py`,
`_depth_cmp.py`, `_cmp_compose.py`, `_classify64.py`, `_missing_fams.py`,
`_peek_exprs.py`, `_test_compose.rb`, `_compose_campaign.log`.


---

## Addendum 2026-09-04 01:20 UTC — the 64 is now anchored to a DRAINED corpus

The "64 = genuine structural gaps" claim above was collected on the 1781-dump
CAPPED corpus. Future-work #2 (commit `69fe5bb`) re-ran the anon_mobile
exploration at MAX_RUNS=10000: the frontier **exhausted** at 9950 runs /
2346 mobile paths (+34% over the capped 1749), two deterministic re-runs, and
the bounded checker on the fully-drained 2378-dump corpus reported
**NODES=45 (unchanged), MISSING=64 (unchanged), PCS 37136→50314** — every
one of the 64 remains: 48 cross-format joins (format-exclusive per
controller/template; unwitnessable by any seed set) + 16 guard-foreclosed
(not_found/closed_account → stream never renders). This is the strongest
possible corpus evidence: no seed combination is left unexplored, yet the
same 64 stand.

Only future-work #3 (decouple format from branch in the harness) could clear
the 48 cross-format items — **PERMISSION REQUIRED** (source discipline:
harness change, ask first). Not done.


---

## Addendum 2026-09-04 03:10 UTC — RESOLUTION: the 48 cross-format items are
## a call-ordinal NAMING collision, not an app reachability gap (FUTURE-WORK
## #3, dual-format scenario)

Earlier addenda classified the 64 into 48 "cross-format" + 16
"guard-foreclosed". FUTURE-WORK #3 (PERMISSION GRANTED, dual-format scenario
`anon_mobile_presenter` in run_dse.rb) directly tested the cross-format
claim. Result: **the app genuinely renders the html presenter AND the mobile
stream in one request** (1696/1701 dual dumps co-mint bare `records_1==0`
with `records_3/4/5_rows>0`), yet MISSING stays 64.

The resolution, proven by `_fw3_ordinal2.py` over all 4079 dumps:
**ZERO dumps co-mint a bare `records_N` with same-ordinal `records_N_rows`.**
The checker's 48 items demand `Not(records_1 != 0) ∧ records_1_rows > 0` in
one run — impossible because the interceptor's per-run call-ordinal counter
gives the html leg `records_1/2` and a co-run's mobile leg `records_3/4/5_rows`
by construction. A single format cannot mint both names either. So the 48 are
**unsatisfiable purely from the naming scheme** — they are not evidence of
any app-side unreachability. The app reaches both families; the checker
cannot pair them under one ordinal.

Downrevised honest reading of the 64:
- **~14 guard-foreclosed** (closed_account/not_found == True forecloses the
  stream render so `to_a_1_row_comments_count==1` cannot be witnessed) — true
  control-flow gaps, app-side real.
- **~50 ordinal-naming-unsat combinations** (bare `records_1/2 == 0` ∧ rows
  family ∧ profile/handle/guid conjuncts requiring same-ordinal bare+rows) —
  app-reachable but checker-structurally unpairable in one run; clearing
  them requires a runtime/engine call-ordinal change (SOURCE.md: OUT OF SCOPE).

The 64 therefore remains the honest bounded-count floor, and is now the
strongest possible claim: MISSING is unchanged at 64 across (a) deeper drain
(69fe5bb), (b) multi-var composition (a67ae0e), and (c) dual-format
co-rendering (this addendum) — three independent strategies, same 64.

Frozen endpoints + shared concolic_targets.rb untouched. `run_dse.rb` + docs
committed; probe scripts `_fw3_*.py` untracked scratch.
