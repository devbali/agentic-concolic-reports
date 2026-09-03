# Rule-regime experiment — running round log

## Round 1 — SCORED (control diff pending, expected to confirm)

| variant | covered | rejected | unknown | usable views | coverage check |
|---|---|---|---|---|---|
| A (T1) | **15**/71 | 16 (all attributed) | 40 | 13/28 | finished: 164 missing, truncated, 73 min |
| B (T1+T2) | **15**/71 | 7 (subset of A's 16) | 49 | 13/28 | never finished (2 attempts) |
| C (control) | **15**/71 | 16 (matches A exactly) | 40 | 13/28 (pre-filtered) | loop unfinished |

Verdict so far: T1 changed ZERO mocks in both variants (gen3f surface
already compliant) — its round-1 value is the mechanically-produced
ledger + two harness findings, not score movement. T2's value is the
mechanism-catch + blocked under-verified classes. The A-vs-B rejection
gap (16 vs 7) is a DIFF TIMEOUT-SCHEDULE artifact (A ran full 120s
throughout; B fell back to 15s under memory pressure; B's 7 ⊂ A's 16 —
both agents' attributions agree). Score movement levers, all evidenced:
1. `_assoc_*` bind folding in transform.py (15/28 queries unusable as
   views) — biggest closeness lever;
2. one named missing joint combination (type×mention×persisted) behind
   8 of A's rejections — seedable;
3. standardized diff protocol (incremental, threads=1, big cap,
   --endpoint scoping) — A's run proves it completes without shortcuts.
   REFINEMENT from control's result: C at 15s timeout matched A's 120s
   verdicts EXACTLY (15/16/40) — the timeout was not the differentiator;
   B's lower rejection count traces to its kill-interrupted resume churn.
   Recipe implication: 15s per query suffices IF the run is uninterrupted
   and incremental; spend headroom on stability, not timeout.

## Round 2 — variant D SCORED (levers 1+2+3 on A's corpus)

| | A | B | C | **D** |
|---|---|---|---|---|
| covered | 15 | 15 | 15 | **30** |
| rejected | 16 | 7 | 16 | **6** (all = the documented before_action/layout scope residue) |
| unknown | 40 | 49 | 40 | 35 |
| usable views | 13/28 | 13/13 | 13/28 | **30/30** |

Lever separation (from D's evidence): Lever 1 (assoc-fold) alone converts
the 15 unusable shapes to real joins; Lever 2 (joint seeds) alone proves
the type×mention×persisted family satisfiable; only together do they close
the 8-query family (now solver-proved covered). New findings for the
recipe: (i) 15s-vs-120s verdict equivalence is VIEW-SET-SIZE DEPENDENT —
2 formerly-proven rejections became unknowns at 15s on the 30-view set;
(ii) one reference query has a per-query solver memory ceiling on this box
(120s recheck OOMs at any cap tried); (iii) D's disciplined deviation
(variant-local fold vs src commit, per the experiment's own no-src rule)
plus its evidence-checked pushback on a wrong coordinator diagnosis are
both operational-recipe material.

## Round 3 — thin, coordinator-run (variant_e): CONVERGED (lever refuted)

Types 4-7 joint seeds ran clean (11 runs, 0 errors, drained) and REFUTED
the lever: 0/7 dumps co-record the mention×persisted conjunction because
those types' targets are Mention/Person rows — `assoc_target_text_has_
mention` structurally cannot mint there. The joint gap was inherently a
types-0-3 phenomenon, fully closed in round 2. Remaining residues are all
refuted, out-of-scope (runner-scope plumbing), or pipeline-bounded (solver
capacity) — no score-moving lever remains. EXPERIMENT CONVERGED at round
2's numbers: **30/71 covered, 6 rejected (all documented scope residue),
30/30 usable views.** Final deliverable: ../MOCK_TEST_RECIPE.md.


## Round 1 (variants A, B vs control C) — in progress

Reference baseline: 71 notifications queries. Prior scores for context:
results2 = 1 covered; main-line gen2 = 7 covered / 22 rejected / 42
unknown (7 extracted queries).

| variant | rule-set | extracted | covered | rejected | unknown | status |
|---|---|---|---|---|---|---|
| B (T1+T2, probes+flow) | leaf-probe w/ coverage metric + assumption flow tests | 13 | **15** | **7** | 49 | diff complete (after capped re-run; first attempt watchdog-killed at 08:35). RESULT.md needs its diff section refreshed with these numbers — agent active. |
| A (T1 only) | leaf-probe w/ coverage metric | — | — | — | — | coverage checker finished (~70 min solver run); seed rounds → extraction → diff pending. |
| C (control, no probes) | gen3 argument+counts rules | — | — | — | — | pipeline queued for quiet window. |

**Attribution correction (from B's final report — supersedes the earlier
preliminary note):** B's T1 sweep changed ZERO mocks (18 probed: every
FAIL resolved to a safe nested chain or a confirmed-minimal SQL boundary;
concolic_targets.rb/targets.rb byte-identical to control). So B's better
diff numbers are NOT a mock-rule effect. They decompose into:
- corpus fullness (all-8-STI-type gen3 corpus vs the stale gen2 4,547-dump
  snapshot behind the "7 covered" baseline),
- diff METHODOLOGY: pre-filtering placeholder-bearing queries from the
  views (they crash the checker, rc=-9), --incremental resumable checking,
  and the 15s-timeout finding (120s adds wall time, not verdicts).
What the probe rules DID buy, evidenced:
- T2 caught a WRONG mechanism hypothesis on the persisted-gate class
  before it shipped (sibling-_persisted guess falsified; real foreclosed
  family = the through-association count PCs) — the flagship catch.
- T2 blocked under-verified classes (count-chain, one-sided) from
  auto-declaration.
- T1 surfaced a dead declare_target (Metal#head) and two harness-relevant
  infra bugs (watchdog cross-tenant kills; diff.py placeholder crash).
New gaps B named, candidates for round-2 test classes (all executable):
scenario-dominance test (LIFO starves typed/unread_only scenarios —
control corpus: 6+6 of 7,825 dumps; needs per-scenario rounds like the
type rounds + a minimum-dumps-per-scenario metric); note-completeness for
association-load intermediates (the bare notification_actors row fetch —
B's one genuine rejected-query gap); coverage-check time-budget protocol
(two attempts 45/31 min unfinished on the full-STI corpus; pairwise matrix
must be the primary metric with k-way as budgeted best-effort).

Operational notes: two uncapped blockaid JVMs watchdog-killed (08:35,
09:02) — both re-run capped; no kernel OOM events; box stable throughout.
