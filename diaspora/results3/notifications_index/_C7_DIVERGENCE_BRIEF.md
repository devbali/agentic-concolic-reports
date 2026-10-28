# C7 DEMAND LOOP DIVERGES — model decision required (2026-09-08)

## Verdict

Three clean demand rounds, each seeded from the FULL missing set
(`MISSING_CAP=6000`, not the default 200 that starved earlier attempts):

| round | dumps | nodes | missing |
|---|---|---|---|
| 1 | 9 895 | 159 | 4 326 |
| 2 | 10 735 (+840) | 164 | **4 476** |
| 3 | 13 816 (+3 081) | 167 | **4 651** |

Both the tree and the demand space grow monotonically. 3 921 new dumps did
not reduce missing by one entry. The loop halted itself at
`demand:diverged`. **More rounds will not close this endpoint.**

## Why — the missing set has ONE shape

4 475 of the 4 651 missing entries are conjunctions over the SAME eight
length variables:

    records_4, records_5, records_7, records_8, records_10, records_11,
    Relation_records_2, Relation_to_ary_1_row_actors_row

This is the joint product space `PAUSED_C7.md` identified in the clique
profile ("ALL 7 680 share the same joint product space"). The C7-A tier
(14 adjudicated cross-family pairs) split what it could; these eight remain
mutually dependent, so the demand is their full product.

## The actual defect: the dimensions are NOT stable facts

Mapping each ordinal to what it resolves to, over the corpus:

| ordinal | no-statement (preloaded) | real SQL |
|---|---|---|
| records_4  | 56% | 43% |
| records_5  | 63% | 36% |
| records_7  | 63% | 36% |
| records_8  | 25% | 74% |
| records_10 | 97% |  2% |
| records_11 |  0% | 100% |

The same ordinal is a **preloaded association read that issues NO SQL** on
some paths and a **real `SELECT`** on others. The checker treats it as one
stable dimension and demands the product across all of them.

This is the batch's own recorded problem, now biting the demand loop:
`PAUSED_C7.md` — "The indices are call ORDINALS (targets.rb cycle-2 fact-cache
note: `records_2 / records_4 / records_6` — one FACT modelled as three)."

Each demand round reaches a new call site, mints a NEW ordinal
(records_9, _10, _12 all appeared during these rounds; nodes 159 -> 167),
that ordinal has no family assignment and no C7-A declaration, so it joins the
joint clique and multiplies the space. That is the divergence mechanism:
**the rounds mint dimensions faster than they cover combinations.**

## Why the obvious fixes are wrong

- **Untrack the preloaded reads.** Would be right if an ordinal were purely
  no-statement, but records_4/5/7/8 are 25-43% REAL SQL. Untracking by ordinal
  discards genuine policy-bearing branches. REJECTED.
- **Declare the eight pairwise independent.** Refuted already by W-E
  (`coverage_assumptions.py`): `(len(X) > 1)` is independent of NOTHING — the
  cardinality determines statement shape (`= $(key)` vs `IN (...)`). 9 of 12
  gate FAILs were this class. Rule D violation. REJECTED.
- **Raise MMC / run more rounds.** Measured above: monotone divergence.
  REJECTED.

## The decision (Rule T3 — proposed, NOT shipped)

**Option A — split the dimension by what it resolves to.** Give the preloaded
no-statement read and the real SELECT distinct symbolic identities, so the
no-statement side can be declared Untracked (it provably cannot emit a
statement, so it carries no policy content) while the SQL side stays tracked.
This is the correct fix and it addresses the root cause the batch already
documented. It is a TARGETS change (shared boundary) => Rule T: it voids every
endpoint and forces regeneration. Expensive, correct.

**Option B — declare the joint space truncated and say so.** Keep the corpus,
report `complete: false` with the eight-variable product declared as a known
unclosed dimension in the policy header, the way people_show's P-7/P-8 were
declared open. Cheap, honest, but notifications_index does NOT meet the
project standard and must not be recorded as closed.

**Option C — bound the ordinal space.** Cap the tracked ordinals to those with
a family assignment in the C7-A census (1-8, 11) and declare 9/10/12+ as
out-of-model, with the argument written down. Middle cost; needs an argument
that the uncovered ordinals are re-reads of already-modelled facts, which the
fact-cache note suggests but does NOT prove.

I did not implement any of these. Option A changes the shared boundary, which
under Rule T restarts every endpoint including the two CLOSED ones — that is
categorically a coordinator decision.

## State on disk

- corpus 13 816 dumps, `coverage_summary.json` = round-3 coverage-only pass
  (nodes 167, missing 4 651, truncated). NOT a completion result.
- `_c7_drive_state`: cov:D1 dse:D1 cov:D2 dse:D2 cov:D3 demand:diverged
- the full-engine pass was STOPPED deliberately: with missing=4 651 it cannot
  return `complete: true`, and the completion gate (shims + assumption
  replays) is expensive. Nothing was lost.
