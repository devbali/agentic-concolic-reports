# notifications_index rule-regime experiment (Bali directive, 2026-08-19)

## FINAL VERDICT (2026-08-19 night, converged after 3 rounds)

**Winner: the round-2 composite rule-set — codified as
`../MOCK_TEST_RECIPE.md`** (M1-M4 mock tests, A1-A5 assumption tests,
P1-P6 corpus/pipeline tests). Score trajectory on the reference's 71
queries: results2 1 covered → gen2 7/22 → round 1 (A=B=C) 15/16 → round 2
(D) **30 covered / 6 rejected / 30-of-30 usable views**; round 3 refuted
the last corpus lever (types 4-7 conjunction structurally N/A) →
converged. Key attribution findings: T1's probes validated rather than
changed the gen3 mock surface (its value = the mechanical ledger + harness
discoveries); T2's directed probes caught a wrong foreclosure mechanism
before it shipped (the flagship catch); the score movement came from the
extraction fold (usable views 46%→100%) and named-missing-combination
seeding. Full round log: `_experiment/ROUNDS.md`; per-variant evidence:
`_experiment/variant_{a,b,d}/RESULT.md` (+ variant_e for the round-3
refutation).

Question: which verification rule-set produces the extracted notification
queries CLOSEST to the reference policy set
(`ruby_examples/dse-apps/policies/extracted/diaspora/per-endpoint/
notifications_index.sql`, 71 queries)?

Three variants, one result doc each. All start from the same gen3 batch
code (`results3/notifications_index/` at the gen3f state) and run the same
pipeline (regenerate corpus → cap-4 coverage + SEEDS_ONLY seed rounds →
extraction → blockaid diff at `SUBSUME_TIMEOUT_MS=120000`).

| variant | dir | rule-set | run by |
|---|---|---|---|
| A leaf-probed | `_experiment/variant_a/` | DISCIPLINE_TESTS.md T1: build the leaf-probe harness, sweep EVERY mock/shim in the batch, remove or descend every mock that fails its probe, then pipeline | subagent |
| B leaf+assumption-probed | `_experiment/variant_b/` | T1 sweep as in A, plus T2: probe every declared assumption class both directions, drop what fails, then pipeline | subagent |
| C control | main batch dir | gen3 rules as already applied (argument + corpus-wide counts, no executable probes) | coordinator |

Scoring, in order:
1. reference diff: covered ↑ (baseline gen2: 7/71), provably-rejected ↓
   with every rejection tied to a NAMED residue, ours-rejected-by-reference
   explained;
2. extraction hygiene: no unresolved placeholders / flags without notes;
3. corpus honesty: run errors 0 or classified; no unlabeled degenerate SQL.

## Iteration protocol (Bali, night of 2026-08-19: "iterate — I want the
perfect recipe by tomorrow morning")

This is a MULTI-ROUND experiment. After each round's variants land:
1. Score them (criteria below) and attribute every remaining
   reference-diff rejection / hygiene defect to either (a) a rule that a
   variant had and another lacked (evidence the rule earns its cost), (b)
   a defect NO current rule catches — for those, design a NEW executable
   test class (script + metric, never an inspection rule) that would have
   caught it, or (c) an out-of-scope residue (document).
2. Synthesize the next round's rule-set(s) from the best performer plus
   the new test classes; spawn the next variant (D, E, ...) in its own
   `_experiment/variant_<x>/` dir, same pipeline, same scoring.
3. Repeat while the night allows. HARD CUTOFF: by early morning
   2026-08-20, stop iterating and write `results3/MOCK_TEST_RECIPE.md` —
   the final recipe: the ordered, executable test suite for (i) any new
   mock and (ii) any new assumption, each test with its script location,
   metric, threshold, and one line of evidence from this experiment for
   why it earns its place (or a note that it was tried and cut, and why).
   The recipe is the deliverable; the variants are its evidence base.

Operational rules for the variant agents:
- Work ONLY inside your variant dir (a full copy of the batch files).
- Wrap every `scripts/diaspora-concolic` invocation in
  `flock /tmp/concolic-slot.lock` — ONE JRuby at a time on this box.
- Memory: launch long python/JRuby via
  `systemd-run --user -p MemoryMax=2500M --wait` or keep `free -h` ≥ 1.2Gi.
- Never touch `src/`, the app, or the other variants' dirs.
- Deliverable: `RESULT.md` in the variant dir (rules applied, probe
  findings table, mocks changed and why, corpus stats, coverage verdict,
  final query list, diff numbers) — AND restate the full RESULT.md content
  in your final message (transcript-recovery convention).
