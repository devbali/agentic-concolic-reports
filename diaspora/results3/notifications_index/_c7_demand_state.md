# C7 Demand-Round Milestone — State (coordinator-driven, 2026-09-04)

## Status: PROBE DONE + TIER DECLARED; DEMAND ROUNDS NEXT

## 1. Probe (D3 flip-both) — DONE, 14/14 PASS
- `_probe14_declared.json` (14 adjudicated pairs, instantiated on corpus ordinals:
  records_2 aspects / records_3 services / records_6 tags / to_ary_1 notifications list /
  Relation_records_1 unread / records_1 aspect_memberships)
- Runner: `_probe14.sh` (gate pattern: heavy lock ONLY, checker self-flocks)
- Result `_probe14_results.json`: 13 PASS w/ no combination-only shapes, 1 mutually-exclusive
  (F3×F8, 0 co-occurrences). 0 FAIL, 0 NOT-TESTABLE.

## 2. Tier in coverage_assumptions.py — DONE (needed 3 fixes)
- `_C7A_LEN_PAIRS` (14 pairs) + `_tier_c7a_crossdim_length()` — direct `aset.add`,
  BYPASSES `_withdrawn_independence` (W-E would withdraw ALL via `_GT1_RE`; verified
  `_withdrawn_independence` returns True on these pairs → bypass is load-bearing).
- Fix 1 (ordering): tier must run BEFORE `_tier2_disjoint_reps` — tier2 adds every
  cross-rep pair to `already` (length pairs included), which silently skipped all 14.
- Fix 2 (form): engine loads runs via `coverage_report.fix_len_names(raw)` →
  `Run.from_dict`, which RENAMES `len(X)` → `SYM_LEN_X`. Constants must be in the
  engine's canonical `(SYM_LEN_SYM_RESULT_..._rows > 1)` form. First version used
  `(len(...) > 1)` → zero matches (debugged via C7A_DEBUG env probe; removed after).
  Use the engine's exact load path when testing tiers standalone: 
  `Run.from_dict(fix_len_names(json.load(open(fp))))`.
- Verified: full-corpus build() → tier0a=180 tier0b=1745 tier0c=1108 tier1=692
  tier2=5151 **C7-A=14** untracked=2 WITHDRAWN(indep)=2280 (was 2294 without C7-A).

## 3. Engine after C7-A (SKIP_COMPLETION=1, MAX_MISSING_PER_CLIQUE=4) — 2026-09-04 20:41 UTC
- `COMPLETE=False;NODES=151;MISSING=2621;BLOCKING=2620;PCS=289652;TRUNCATED=True`
- vs stale-code run (C7-A=0 withdrawn): MISSING=525. **The increase is SOUNDNESS,
  not regression** — clique simulation (full corpus, real AssumptionSet):
  - without C7-A: 132 maximal cliques, 14 C7-A pairs co-residing (wrongly coupled)
  - with C7-A: 660 maximal cliques, 0 pairs co-residing (correctly separated)
  - Each maximal clique demands its own combo; 660 cliques × per-clique combos the
    corpus never witnessed (e.g. records_4>1 ∧ records_5>1 ∧ records_7>1 ∧
    records_8>1 ∧ records_11>1 ∧ Relation_records_2>1 ∧ actors_row>1) = the missing.
  - 525 was an unsound undercount (conflated independent dims); 2621 is the sound
    demand space. Corpus lacks cross-family co-occurrences.
- Missing item shape: dominated (>99%) by "all >1" length conjunctions over
  {records_11, records_4, records_5, records_7, records_8, Relation_records_2,
  actors_row} + one of {records_1, records_2, records_3, records_6}. C7-A pairs
  themselves NEVER co-appear in missing items (declarations respected).

## 4. NEXT: demand rounds (step 2 of campaign order)
- demand_round.py converts checker MISSING combos (coverage_summary.json missing[],
  each with Z3 model) into per-variant seed files → run_dse.rb EXRA_SEEDS_JSON
  (sic — see RUNBOOK) → DSE → re-run engine → iterate until missing collapses ~0.
- Also: paged BASE rounds first (base corpus coverage), per the milestone brief.
- H4 seed: records_4 in scenarios where it ads 0 (per adjudication).
- H3: document CollectionProxy#load_target as declared no-semantics war (wording in
  batch notes) — no code change.
- After demand rounds: full engine (no SKIP_COMPLETION) → audits → sweep → adversary
  → extraction.

## 5. Hard rules honored
- No outer slot flock around checker/gate (self-flocks; verified `_gate_standalone.sh`).
- Tier bypasses W-E ONLY for the 14 adjudicated pairs (hardcoded, scoped).
- No src/ changes; batch file only. Engine + assumptions untouched in src.