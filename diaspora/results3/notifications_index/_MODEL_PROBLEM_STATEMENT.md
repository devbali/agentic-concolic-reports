# PROBLEM STATEMENT — notifications_index demand loop will not converge

## The observation

Demand rounds, each seeded from the FULL missing set (MISSING_CAP=6000):

| round | dumps | nodes | missing |
|---|---|---|---|
| 1 | 9 895 | 159 | 4 326 |
| 2 | 10 735 (+840) | 164 | 4 476 |
| 3 | 13 816 (+3 081) | 167 | 4 651 |

3 921 new dumps reduced missing by ZERO. Root yield is falling (6.6% -> 3.4%).

## The structure of the missing set

4 475 of 4 651 missing entries are conjunctions over the SAME eight length
variables:

    records_4, records_5, records_7, records_8, records_10, records_11,
    Relation_records_2, Relation_to_ary_1_row_actors_row

## The suspected root cause

`src/ruby_runtime/call_interceptor.rb:142-144`:

    func_name   = "#{klass_name}.#{method}"
    idx         = SymbolicFunc.next_call_idx(func_name)   # PER-RUN COUNTER
    result_name = "SYM_RESULT_#{func_name}_#{idx}"

A symbolic result is identified by WHEN it was called, not WHAT it is.
`records_4` = "the 4th CollectionProxy#records call in this run". Which
association that is depends on the path. Measured over the corpus:

| ordinal | preloaded (NO statement) | real SQL |
|---|---|---|
| records_4  | 56% | 43% |
| records_5  | 63% | 36% |
| records_7  | 63% | 36% |
| records_8  | 25% | 74% |
| records_10 | 97% |  2% |
| records_11 |  0% | 100% |

The checker treats each distinct expr as one stable dimension
(`coverage.py` step 5 builds the dependence graph over `active` exprs) and
demands the product. New call sites mint NEW ordinals (records_9/_10/_12
appeared during these rounds; nodes 159 -> 167), which have no family
assignment and no independence declaration, so they join the joint clique.
Rounds mint dimensions faster than they cover combinations.

The batch already recorded this in another form — `PAUSED_C7.md`: "The indices
are call ORDINALS (targets.rb cycle-2 fact-cache note: records_2 / records_4 /
records_6 — one FACT modelled as three)."

## What has been RULED OUT with evidence

1. **Untrack the preloaded reads BY ORDINAL.** Wrong: records_4/5/7/8 are
   25-43% REAL SQL. Untracking by ordinal discards policy-bearing branches.
2. **Discriminate by source location.** Measured: the length PCs for
   records_4/5/7 record at `targets.rb:1194` and `:1195` for BOTH readings.
   Source does not separate them.
3. **Declare the eight pairwise independent.** Refuted by W-E in
   `coverage_assumptions.py`: `(len(X) > 1)` is independent of NOTHING —
   cardinality determines statement shape (`= $(key)` vs `IN (...)`). 9 of 12
   gate FAILs were this class. Rule D violation.
4. **More rounds / bigger MMC.** Measured monotone divergence above.
5. **Rename the symbolic result by what it resolves to.** Correct in
   principle, but `src/ruby_runtime/` is "minimal changes, ask first"
   (CLAUDE.md) and it changes EVERY symbolic variable name in EVERY dump —
   under DISCIPLINE §8 Rule T that voids all corpora including the two CLOSED
   endpoints (conversations_index, comments_index). From-scratch regeneration
   of the whole project.

## THE QUESTION

**Can this be expressed within the existing assumption model instead?**

`src/concolic_engine/assumptions.py` offers exactly four kinds — Independence,
SymbolicConstraint, UntrackedPath, OneSideUntrackedPath — and an assumption
names its path condition by `expr` (a decision), by `source` (a site), or
both. Its stated design goal: "Assumptions should never cause false negatives
(miss a real bug), only false positives."

Give a concrete proposal that:
  (a) is sound under that design goal — no real policy-bearing branch may be
      hidden. The deliverable of this project is the SET OF SQL STATEMENTS the
      endpoint can issue; anything that provably cannot change that set is
      legitimately untrackable, anything that can is not;
  (b) does NOT require renaming symbolic results (no Rule T regeneration);
  (c) does NOT re-open the W-E class (length x read-gating-DECISION pairs);
  (d) says exactly which assumption objects to construct, keyed on what;
  (e) states how to VERIFY it — this project's standard is the D3 flip-both
      probe (`assumption_checker.py`, IndependenceAssumption branch): richest
      seed co-recording both exprs -> flip A, flip B, flip BOTH ->
      novel = trace(flip-both) - (base U trace(A) U trace(B)) -> PASS iff novel
      is empty;
  (f) if it CANNOT be done soundly within the assumption model, say so
      plainly and say what the minimum change outside it is.

## Required reading (authoritative, in this repo)

- `src/concolic_engine/assumptions.py` — module docstring + the four classes
- `src/concolic_engine/coverage.py` — `check_coverage` docstring + steps 5-6
  (dependence graph, per-clique demand enumeration)
- `reports/diaspora/docs/DISCIPLINE.md` — Class S/B, D1-D3, §8 Rule T, §15
- `reports/diaspora/docs/CHECKS.md` — what each check proves
- `reports/diaspora/docs/TARGET_FUNCTIONS.md` — what the query boundary IS
- `reports/diaspora/results3/notifications_index/PAUSED_C7.md` — the C7-A model
  proposal, the coordinator's adjudication, the family census, and the
  "STAY DEPENDENT — never declare" list
- `reports/diaspora/results3/notifications_index/coverage_assumptions.py` —
  the existing tiers, especially W-E
- corpus: `reports/diaspora/results3/notifications_index/dump_*.json` (14k)
