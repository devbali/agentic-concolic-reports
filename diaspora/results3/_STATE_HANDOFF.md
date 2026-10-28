# STATE HANDOFF — 2026-09-10 (diaspora concolic, results3)

> **UPDATE, later on 2026-09-10 — the semantics was refined AGAIN.** Combination
> demand is now judged per ASSIGNMENT, not per set: DISCIPLINE **§16b**
> (FORECLOSURE), write-up `notifications_index/_FORECLOSURE_SEMANTICS_20260910.md`.
> Nothing is declared — the relation is inferred from the corpus. Demands are
> nested (§16b ⊆ §16 ⊆ complete-graph), so **Rule T is again NOT triggered** and
> the three closed endpoints were re-verified read-only (comments_index 84/85/0,
> conversations_index 105/83/0, people_show 97/239/0, all `complete`).
> On notifications_index, on a 109 401-dump snapshot: demanded assignments
> **603 032 -> 62 324**, covered **16 781 -> 25 625**, uncovered
> **97.22 % -> 58.88 %**, the four width-20 sets **36 864 -> 488/356/356/356**
> demanded. `tree_missing` is **10** and still refuses the claim.
> **The numbers in the table below are set-level (§16) and on the older 68 231-dump
> corpus — do not compare them with a §16b number.** Open item 1 (the two
> zero-covered sets) was fixed by the campaign; open items 2 and 4–6 stand;
> item 3's 360 000-run estimate is void twice over (campaign §3.4, then §16b).

**The coverage semantics changed today.** `complete` now means "every
satisfiable combination over decisions SOME RUN EVALUATED TOGETHER is observed,
AND every decision has been taken both ways (`tree_complete`)". Decision
record: `docs/DISCIPLINE.md` **§16**. Full write-up with the pre-registration
and what it refuted: `notifications_index/_COEVAL_SEMANTICS_20260910.md`.

**Read that before comparing any number here with an older one.** The demand
universe is different, so `missing`, clique counts and satisfiable totals from
before 2026-09-10 are not comparable. `coverage_summary.json` gained three
keys: `demand_sets`, `tree_complete`, `tree_missing`.

## Endpoints

| endpoint | corpus | nodes | demand sets | missing | tree_complete | status |
|---|---|---|---|---|---|---|
| conversations_index | 18 623 | 105 | 83 | 0 | yes | **CLOSED**; re-verified under the new rule, NOT voided |
| comments_index | 26 528 | 84 | 85 | 0 | yes | **CLOSED**; re-verified, NOT voided |
| people_show | 12 997 | 97 | 239 | 0 | yes | milestone; re-verified |
| notifications_index | 68 231 | 411 | 997 | 980 (MMC=1) | **no — 13 branches** | ACTIVE |
| people_stream | 755 | 29 | 27 | 96 (MMC=4) | **no — 1 branch** | see below |
| posts_show | 96 357 | 101 | 563 | 2 248 (MMC=4) | **no — 11 branches** | re-priced; NO census yet |

The three closed/milestone endpoints were re-checked READ-ONLY
(`scratchpad/ruleT_check.py`, never writes a summary) with their own UNCHANGED
`coverage_assumptions.py`. Their `coverage_summary.json` files were not
touched. **Rule T is not triggered**: old-complete implies new-complete and the
two demand universes COINCIDE on an old-complete corpus (DISCIPLINE §16a — the
proof, and the one exception, which needs a corpus that was NOT old-complete).

## What changed in the code

* `src/concolic_engine/coverage.py` — the rule, the tree-completeness
  precondition (`tree_complete` / `tree_missing`, and a non-empty list REFUSES
  the combination claim), `maximal_sets()`, distinct-outcome-profile collapse,
  deduplicated blocking clauses, profiles indexed by evaluation set. The global
  clique search is gone; `max_cliques` is now the per-evaluation-set projection
  cap.
* `src/test_coevaluation.py` — 11 new tests (never-co-evaluated pair,
  demand-on-co-evaluation, monotonicity, subsumption, the triangle, the
  precondition and its being a named consequence, untracked, one-side pin, the
  projection cap, `maximal_sets`). **All 74 pre-existing tests pass under BOTH
  engines** — the complete-graph default was never covered by a test.
* Batch files: four whole declaration tiers deleted on notifications
  (P1 `_tier_unobservable_pairs` and its withdrawal/bypass machinery,
  `_tier_samerep_never_coeval`, TIER 0a, TIER 0b), four arguments on
  people_stream, TIER 0 on posts_show — every one of them a
  "these can never co-occur" argument the engine now makes for itself. Each
  file gained ONE counted, printed co-evaluation filter so the deletions are
  auditable. **notifications: 87 864 -> 22 679 declarations (55 737 dropped as
  inert). posts_show: 2 895 -> 543. people_stream: 172 -> 47.**

## notifications_index — the re-pricing, and the refutation

`_exact_enum.py` (ported to demand sets), 68 231 dumps, `bounded_cliques=0`,
`--verify 6` 6/6 OK:

| | OLD (complete-graph) | NEW (co-evaluation) |
|---|---|---|
| demand groups | 1 277 cliques | 997 sets |
| satisfiable | 542 784 | 491 264 |
| covered | 13 891 | 13 990 |
| **uncovered** | **97.44 %** | **97.15 %** |
| groups no run evaluated whole | 330 | 2 (both a DEFECT, see below) |

**The complete-graph default was NOT this endpoint's blocker.** The 330
never-jointly-evaluated cliques were real but held only **10.9 %** of the
satisfiable mass and were overwhelmingly NARROW (191 of width 5). The mass is
in **41 demand sets of width >= 13 that hold 79.7 % of the remaining** and that
the corpus DOES walk — they are simply not driven: the four width-20 sets
(32 768 satisfiable each) received **16, 15, 13 and 12** distinct outcome
combinations from 68 231 runs.

What the change DID buy: the whole residual is now over sets some run walked,
so it is a DRIVING problem, not a possibly-unreachable one; and the
precondition named **13 single branch outcomes** that have never been driven
(`tree_missing` in `coverage_summary.json`) — the cheapest work on the
endpoint, previously invisible inside 2 046 combination entries.

## Open, in priority order

1. **notifications, DEFECT (Class B):** two width-7 demand sets have
   `covered = 0` while having observed cubes — the corpus recorded an outcome
   combination the batch's declared Z3 model says is impossible. Suspects:
   `coverage_report.apply_len_bounds`'s `SYM_LEN_*` domains and the
   `SYM_NOTE_TYPE_PROFILE` / `SYM_POST_STI` bounds. **A declared domain that
   excludes something the runtime produced makes every demand computed under it
   suspect.** `scratchpad/curve.py` dumps the two sets' members and cubes
   (`zero_covered_detail`); one 68 231-dump load, no driving.
2. **notifications, tree completeness:** drive the 13 named branch outcomes.
   No combination coverage can make `complete` true while any of them stands.
3. **notifications, the decisive driving experiment:** run the already-built
   `_diverseR.json` (6 000 seeds over `{0,1,2,4}`) and re-measure `covered`. If
   it moves by thousands, the ~360 000-run / ~3 h coupon-collector estimate for
   the whole residual holds; if it moves by ~6, the seeded dimensions are not
   free and the residual needs modelling, not driving.
4. **posts_show:** no exact census yet, and `missing` moved 332 -> 2 248 in the
   OPPOSITE direction to the demand (both are `groups with a gap x MMC`: 83 x 4
   then 561 x 4, over sets that are each a SUBSET of an old clique). Nothing
   about its residual should be quoted until `scratchpad/gcensus.py` has run on
   it — one load, no driving. Its 563 demand sets are WIDE (33–36 decisions)
   because 543 declared independences fragment its 20–42-decision evaluation
   sets, so the pass cost 4 481 s of Z3: **the new rule is not uniformly
   cheaper**. Batching the per-witness solver calls is the next engine-side
   mitigation. Its `tree_missing` (11) includes four
   `as_api_response_N_row_guid != StringVal('')` — the same framework
   short-circuit people_stream declares `OneSideUntracked` for and this
   endpoint does not.
5. **people_stream:** `tree_missing` names
   `ActsAsApi__Collection_as_api_response_1_row_guid != StringVal('') :: taken`
   — the json-render instance of the same framework short-circuit the endpoint
   already declares `OneSideUntracked` for on three other expressions
   (Argument 5). Either a fourth instance of that declaration or a branch to
   drive. Its census: 531 satisfiable, 99 covered, 432 remaining over 27 demand
   sets — against **188 416 satisfiable / 0 covered / 10 of 10 cliques
   unobservable** under the old rule. That endpoint's wall is gone.
6. **DecisionAlias upstream?** Unchanged from 2026-09-09: root cause is
   `call_interceptor.rb:142-144` naming a result by WHEN it was called. Fixing
   it there is a Rule T event that voids the closed endpoints. Per-batch ports
   work and are installed.

## Standing corrections carried forward (2026-09-09, still true)

`MISSING` is a group count x MMC, never a gap — quote a census.
`ls $B/dump_*.json | wc -l` returns 0 past ARG_MAX; use `find`.
Runner logs can report healthy `paths=` while the corpus does not grow.
Dump labels must be unique per INVOCATION.
Check the artefact, not the number describing it — and route every check
through the same load path the engine uses.

## Reports

* `notifications_index/_COEVAL_SEMANTICS_20260910.md` — today's work
* `notifications_index/_ALIAS_REFACTOR_20260909.md` — the alias refactor
  (its §10 note about a JVM-abort signature on `ndxcovB` is WRONG; the
  coordinator killed that pass deliberately)
* `_NIGHT_REPORT_20260909.md` — the previous night, incl. §3c RETRACTION
* `queries_from_runs/_REFERENCE_COMPARISON_20260908.md`
* `people_stream/_NEXT_BLOCKER.md`, `_WALLS.md`

## Re-verification required (X10) — the assumption gate's independence probe was broken on canonicalizing batches

Found 2026-09-11 by the posts_show drive, while running the gate on a new
disjoint-rep tier. Authorized and FIXED in `src/` the same day.

**The defect.** `assumption_checker.py`'s `IndependenceAssumption` probe writes
each flip at the RUNTIME (ordinal) seed key —
`flipped_seeds()`: `rdim = _runtime_key(sd, dim); out[rdim] = v` — and then read
the combined flip back at the CANONICAL key:

```python
fab = dict(fa); fab[db] = fb[db]          # db is CANONICAL, the write was RUNTIME
```

`_runtime_key` is documented as "identity when nothing is aliased". So the
probe worked on a batch whose seed dimensions are not ordinal-aliased and raised
`KeyError` on **every pair** of a batch that canonicalizes ordinals — and
`run_declared` had no per-probe isolation, so the first such pair ended the
whole suite and no results file was written at all.

**Consequence.** On a canonicalizing batch, no `IndependenceAssumption` has ever
been flip-both probed. Any declaration there whose evidence line says
"licensed by the engine's flip-both probe" was licensed by a probe that could
not execute. This is a Rule-T3 question, not a cosmetic one.

**The fix** (`src/end_to_end_completion_checker/assumption/assumption_checker.py`,
minimal): read the combined flip at `_runtime_key(sd, db)`, and handle the
flip-by-DELETION case (a dimension controlled by a seed's ABSENCE); per-probe
isolation in `run_declared` so one exception is that probe's `ERROR` verdict;
the `--json-out` file written under `finally`; `ERROR` counted as a failure.
Tests: `src/test_assumption_checker.py` (4). They are a ground-truth
differential — **4/4 FAIL against the pre-fix code with exactly
`KeyError: 'VAR_B'`, 4/4 PASS after.** Full `src/` suite green.

### Which batches must be re-probed, and how many declarations are at stake

| batch | gate `canonicalize` | coverage_report canonicalizes | "flip-both" cites in `coverage_assumptions.py` | IndependenceAssumption sites citing it |
|---|---|---|---|---|
| **notifications_index** | `coverage_report:canonicalize_ordinals` | yes | **17** | **7** |
| **people_stream** | `gate_canon:canonicalize_for_gate` | yes | 0 | 0 |
| **posts_show** | `gate_canon:canonicalize_for_gate` | yes | 0 (tier 2, added 2026-09-11, is the first) | 0 |
| comments_index | — | no | 3 | 1 | 
| conversations_index | — | no | 2 | 1 |
| people_show | — | no | 0 | 0 |

**AFFECTED: `notifications_index`, `people_stream`, `posts_show`** — the three
that canonicalize. `comments_index` and `conversations_index` do NOT
canonicalize in their gate manifests, so their probes ran on identity keys and
their existing flip-both verdicts STAND.

**notifications_index is the one with declarations at stake: 7 declaration
sites, 17 evidence citations.** Those must be re-probed with the fixed gate
before any `complete: true` is claimed on that batch. `people_stream` and
`posts_show` have no pre-existing flip-both-licensed declaration, so nothing
there is retroactively in doubt — but every probe they run from now on is
running for the first time on a working harness.

**How it gets done: the final full-engine gate run on each endpoint does this
naturally** — the engine runs the assumption checker over the batch's declared
set as part of the completion gate, so a certification run on the fixed `src/`
re-probes everything by construction. No separate campaign is needed, and no
batch should be certified on a gate result predating 2026-09-11. The
notifications drive will hit this in its certification run; this drive did not
re-probe other endpoints.
