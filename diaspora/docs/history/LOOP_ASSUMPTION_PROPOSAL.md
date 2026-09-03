# Proposal: `RecurrentPathAssumption` — a fourth assumption type, for loops

**Status: prototyped and measured OUTSIDE `src/`. Not implemented. `src/` untouched.**
Probe: `reports/diaspora/loop_assumption_probe.py`.

## The gap

The engine has three assumption types. None models a loop:

| type | says | why it does not fit |
|---|---|---|
| `IndependenceAssumption` | two PCs are independent → parallel roots | loop iterations are the *same* decision, not two |
| `UntrackedPathAssumption` | this PC does not matter | too coarse — excuses ALL occurrences, losing the genuine 0-vs-≥1 loop coverage |
| `OneSideUntrackedPathAssumption` | only one side matters | both sides of a loop guard matter; it is the *depth* that should not be re-demanded |

Under strict-per-node, every occurrence of a recurring predicate is a **separate node**, because its prefix differs. So a predicate re-evaluated per element multiplies the frontier without adding distinct decisions.

## Evidence this is real

Measured across all 27,146 explored paths:

- **23,597 paths (87%)** repeat some expression ≥3× within a single path
- repetition is **bounded**: max 5×, **zero** paths at ≥8× — this is per-element re-evaluation, not runaway looping

## Proposed semantics

> For a `PathSource` declared RECURRENT, require both-sides coverage at its
> **first** occurrence along a path; deeper occurrences inherit that coverage.

This is the standard loop-coverage relaxation (cover 0 iterations and ≥1, do not demand all N).

## The key must be the SOURCE SITE, not the expression string

The first prototype folded by expression and was **wrong**. `services_admin` proved why: `(assoc_profile_image_url == '')` recurs 2.7×/dump, but from **three different call sites** in one request (`no_profile_image?` and `Profile#update_profile_with_omniauth`). Those are genuinely three ordered nodes. A real loop re-executes the *same* `file:line`.

Measured difference between the two keys:

| key | nodes | verdict |
|---|---|---|
| strict per node | 84,334 | baseline |
| fold by `expr` (naive) | 66,911 | **destroys 12 real nodes** |
| fold by `(expr, file, lineno)` | 66,923 | correct |

12 nodes sounds small, but it is concentrated: in `streams_activity` and `streams_commented` the naive key halves the tree (2 → 1 instead of 2), and in `streams_aspects` it cuts 5 → 3 instead of 5.

## Measured effect (source-site key)

| entrypoint | strict | folded | one-sided after |
|---|---|---|---|
| `posts/reshares_create` | 83,799 | 66,503 | 40,800 |
| `photos/photos_index` | 162 | 82 | 35 |
| `people/people_index` | 39 | 29 | 5 |
| `services_admin/services_invite` | 264 | 256 | 0 |
| `users_sessions/users_getting_started` | 24 | 16 | 1 |
| **total (17 affected entrypoints)** | **84,334** | **66,923** | — |

**21% fewer nodes.**

## Honest limits — read before adopting

1. **It does NOT rescue the worst case.** `reshares_create` still has **40,800 one-sided nodes** after folding. Its size is combinatorial *breadth* (independent binary branches), not recurrence. A loop assumption is not the fix for the biggest coverage gap in the experiment.
2. **The effect is dominated by one entrypoint.** Strip `reshares_create` and the remaining 16 entrypoints go 535 → 420 nodes. Real, but modest.
3. **It is a relaxation and CAN cause a false negative** — it will mask a bug that only manifests on the 3rd iteration. It is sound only where the loop body is iteration-independent. The README requires assumptions never cause false negatives, so this one must be **declared per source site with a justification**, never applied by default and never globally.

## What implementing it would require (all in `src/`, hence not done)

1. `assumptions.py`: a `RecurrentPathAssumption(Assumption)` frozen dataclass carrying a `PathSource`, plus an `AssumptionSet.is_recurrent(source)` query — mirroring `is_untracked`.
2. `coverage.py`: `_insert_run` must consult it while building the tree, treating a later occurrence of a recurrent source as the same node rather than a new child. `assumptions_to_dict` needs a case so it serialises with its file/line like the others.

Both are small and additive, but they are engine changes and were **not** made.

## Recommendation

Worth adding, with the source-site key, as a **declared** assumption — but adopt it for its semantic honesty ("every decision covered" rather than "every decision at every depth"), not as a coverage rescue. Nothing in the current results depends on it: all 13 batches reached their reported completeness under **strict per-node with zero assumptions**.
