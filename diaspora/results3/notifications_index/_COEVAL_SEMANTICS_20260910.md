# Co-evaluation combination semantics (2026-09-10)

`src/concolic_engine/coverage.py` — a combination demand now exists **only over
decisions that some run evaluated together**. This file records the design
decisions, the deletions, the tests, the PRE-REGISTERED expectation and the
measurement, and the Rule-T consequences.

## Headline

* The rule is implemented, tested (11 new tests; all 74 pre-existing tests pass
  under BOTH engines) and recorded as a dated decision in `DISCIPLINE.md` §16,
  with its precondition (**tree completeness**, computed and reported) and its
  blind spots (untracking a GATE can now hide a combination, not only a branch).
* **Rule T: no closed endpoint is voided.** old-complete ⇒ new-complete, and the
  two demand universes COINCIDE on an old-complete corpus. Proved, then verified
  read-only on comments_index, conversations_index and people_show — all three
  still `complete`, `tree_complete`, 0 missing.
* **Simplification delivered downstream, not in `coverage.py`.** Four whole
  declaration tiers and their withdrawal/bypass machinery are gone;
  notifications drops **87 864 → 22 679** declarations (55 737 inert),
  posts_show **2 895 → 543**, people_stream **172 → 47**. `coverage.py` itself
  grew (581 → 773 lines, code 359 → 415) — mostly docstring.
* **people_stream: the wall is gone.** 188 416 satisfiable / **0** covered /
  10 of 10 cliques unobservable → 531 / 99 / **0 of 27** unobservable.
* **notifications_index: my pre-registered expectation is REFUTED.** The
  uncovered fraction moved 97.44 % → 97.15 %. The complete-graph default was
  NOT this endpoint's blocker: the 330 never-jointly-evaluated cliques held
  only 10.9 % of the mass and were narrow. What the change buys here is a
  DIAGNOSIS — the whole residual is now over sets some run walked, so it is a
  driving problem — plus 13 named single branches that have never been driven.
* **A cost finding, both ways.** The global clique blow-up (and its silent
  singleton fallback) is gone; but on posts_show, whose 543 declared
  independences fragment 20–42-decision evaluation sets, the group count RISES
  and the pass is expensive — 563 demand sets of width 33–36 against 83 cliques
  with a gap before, 4 481 s of Z3 (§8).

---

## 0. PRE-REGISTRATION (written before any pass under the new semantics was run)

Baseline, from `_ALIAS_REFACTOR_20260909.md` §8 (68 231-dump corpus, shipped
alias, complete-graph semantics, `_exact_enum.py`):

| quantity | baseline |
|---|---|
| nodes (`total_nodes`) | 411 |
| active (after untracking) | 402 |
| maximal cliques | 1 277 |
| satisfiable assignments | 542 784 |
| covered | 13 891 |
| remaining | 528 893 (**97.44 %** uncovered) |
| cliques evaluated whole by NO run | 330 |
| cliques fully covered | 17 |
| `missing` at MMC=1 | 1 260 |

What I expect the co-evaluation pass to show, and why:

* **P1 — zero demand sets evaluated whole by no run** (was 330 of 1 277). This
  is structural, not a hope: every demand set is a subset of an evaluation set
  some run walked, so it always has at least one blocking clause. If any demand
  set turns out to have no covering run, the implementation is wrong.
* **P2 — nodes 411 and active 402, unchanged; untracked 9, unchanged.** The
  universe of distinct PC expressions is not a function of the demand rule.
  A different node count means I broke the load path, not the semantics.
* **P3 — many more, and strictly narrower, demand sets.** A demand set is a
  maximal clique of the dependence graph *restricted to one run's decisions*,
  so every demand set is a subset of some old clique: max width ≤ 20 (the old
  maximum), count in the low thousands (bounded by the number of distinct
  maximal evaluation sets, times the projection factor — 2.1× on a 400-dump
  sample).
* **P4 — the total satisfiable target DROPS, to roughly 150 000–300 000.**
  Narrower sets multiply out to fewer assignments; the 330 zero-coverage
  cliques (the widest ones) are replaced by their observed parts.
* **P5 — the uncovered fraction falls well below 90 %.** This is the
  falsifiable claim about the DESIGN. The 2026-09-09 finding was that the
  uncovered fraction is invariant to the alias keying (96.95 / 97.44 / 97.16 %)
  — i.e. re-keying changed the size of the target, not the reach of the
  driving. If the co-evaluation rule leaves the uncovered fraction at ~97 %
  too, then the complete-graph default was NOT the blocker and I must say so
  rather than dress the number up.
* **P6 — `tree_complete` is probably FALSE, with a SHORT list.** Nothing in the
  campaign ever demanded per-branch completeness on its own, and the 400-dump
  sample already shows 153 satisfiable-but-unobserved sides. On the full corpus
  I expect that list to be much shorter (most of those 153 are sample
  artefacts) but not empty. A non-empty list REFUSES the combination claim —
  that is the precondition doing its job, and `complete` must be false.
* **P7 — reachability improves by more than the target shrinks.** The old
  marginal rate (0.061 newly covered assignments per run, giving ~8.7 M runs /
  ~75 h) was measured against the complete-graph demand, where a run covers a
  cube only in a clique it evaluates WHOLE — which for 330 cliques was never.
  Under co-evaluation every run covers a cube in every demand set it walks
  entirely, so I expect the covered count to jump on the SAME corpus with no
  new driving at all, and the residual to be dominated by genuinely
  unobserved branch combinations rather than by unobservable ones.

Deliberately NOT predicted: the exact demand-set count and the exact
satisfiable total. Those depend on how the corpus's evaluation sets overlap,
which is not derivable from the clique census.

---

*(measurement in §6, deltas in §5 and §7, Rule T in §4)*

## 1. The design decisions

### 1.1 Mutability — the graph is a function of the corpus, and it grows

The demand universe is rebuilt from the corpus on every pass (it always was —
`run_outcomes` in step 1 is derived, never cached). Under the new rule a new run
can **ADD** demand, by showing that two decisions can be evaluated together.

* **Monotone.** Co-evaluation is an existential over runs: once two decisions
  have been seen together they stay together, and no added run can retract a
  demand. Demand only ever grows or gets covered.
* **Subset dedup does not weaken it.** The demand universe keeps only the
  MAXIMAL observed evaluation sets. Dropping `S ⊂ S'` loses nothing: every
  satisfiable assignment over `S` extends to a satisfiable assignment over `S'`
  (each extra expression is a boolean; at least one side keeps the query SAT —
  which is exactly what `_next_untried_combo` does), so covering `S'` implies
  covering `S`. The superset's demand is strictly stronger. This is what makes
  "keep the maximal ones" a theorem rather than an optimisation, and it is why a
  demand set can DISAPPEAR from the reported list without any demand being lost.
* **A declared independence over a pair that later co-evaluates.** It is INERT
  until the corpus produces the pair, and it starts CUTTING the moment a run
  evaluates both — which is the right behaviour on both sides of the ledger:
  tier0a/0b/tier2/C7-A keep doing their job on the pairs that matter, and W-E
  still WITHDRAWS a declared independence on a co-evaluated length pair. It is
  also good for the ASSUMPTION GATE: a never-co-evaluated declaration was a free
  PASS ("mutually exclusive, no probe") — unprobed by construction — whereas a
  declaration that only starts to matter when the pair appears is probed with a
  real flip-both snapshot at exactly that moment. Unsound declarations become
  falsifiable when they start to have an effect, instead of accumulating
  unfalsifiably (P1 alone was ~20 000 of those, 342 of them withdrawn by later
  corpora — i.e. the class was demonstrably wrong at a measurable rate).
* **Append-only corpus assumed.** Monotonicity is a statement about adding
  runs. DELETING dumps (`dedupe_dumps.py`, a sampled pass) can remove a demand,
  and a sampled pass therefore under-states the demand universe. `DUMP_SAMPLE`
  already prints its population; that warning now covers the demand set count
  too.

### 1.2 Pairwise vs sets — the triangle. Decided: SETS.

Pairwise co-evaluation plus Bron–Kerbosch still manufactures sets no run
walked: A–B, B–C and A–C each observed makes {A,B,C} a clique even when no
execution evaluated all three, and such a set can never acquire a blocking
clause. That is the same artefact one level down, so the pairwise design was
rejected. The demand universe is the **maximal observed evaluation sets**.

`test_triangle_pairwise_but_never_together` pins it: 12 runs covering the three
pairs exhaustively are COMPLETE under the new rule and NOT complete under the
old one (8 missing, permanently).

**Declared independence then applies WITHIN a set, by projection**, defined
precisely as: for an evaluation set `S`, build the dependence graph induced on
`S` (complete on `S` minus the declared-independent pairs), and replace `S` by
the MAXIMAL CLIQUES of that induced graph. Then dedup subsets across all sets.
This is the unique definition that (a) is strictly pairwise, as independence
always was, (b) reduces to `S` itself when nothing is declared, and (c)
reproduces the old rule exactly when every clique is contained in an evaluation
set (see Rule T, §7).

**Cost.** The clique search survives only as that projection, so it is bounded
by ONE RUN's decisions rather than by the universe: the global `max_cliques`
blow-up (which silently voided a whole notifications pass on 2026-09-08 by
falling back to singleton cliques) can no longer happen. Measured on
notifications' 68 231-dump corpus: 24 647 distinct outcome profiles → 860
maximal evaluation sets (widths 51–62) → **997 demand sets** (widths 3–20,
median 5). The global adjacency is still computed once over the active universe
(80 601 pairs), exactly as before, so the projection adds only set
intersections.

### 1.3 Tree completeness is the PRECONDITION, and it is reported

`CoverageResult` gained `tree_complete: bool` and `tree_missing: tuple[str]`
(`"<expr> :: taken|not_taken"` for each satisfiable, never-observed side).
A non-empty `tree_missing` forces `complete = False` and `summary()` prints
`COMBINATION CLAIM REFUSED: the tree layer is not complete (...)`.

Thinking it through further than the brief asked: the precondition turns out to
be a **named consequence, not a second gate**. If an outcome is satisfiable
under the shared constraints (`fixed_base` + pins) then it extends to a
satisfiable assignment of any set containing it, so an unobserved satisfiable
side ALWAYS also shows up as a missing combination. `no blocking missing ⇒
tree_complete` is therefore a theorem, and it is asserted over three corpora in
`test_tree_incompleteness_always_shows_up_as_a_missing_combination`. The flag
exists so a refusal is LEGIBLE — so the report says which decision was never
driven both ways rather than leaving a reader to infer it from a combination
constraint.

### 1.4 What "evaluated in a run" means

Step 1's `run_outcomes` (expr → set of taken outcomes, per run) is the
co-evaluation record, unchanged. A run's evaluation set is its keys, intersected
with `active`. Alias renaming happens at LOAD (`canonicalize_ordinals`) and
again inside `CoverageChecker.__init__` (`apply_aliases`), both before step 1,
so aliased decisions co-evaluate under their canonical names — the same map the
gate recomputes.

One change of representation, for cost: runs are collapsed to DISTINCT OUTCOME
PROFILES before anything else. A profile is everything the later steps read, and
68 231 notifications runs carry only 24 647 distinct ones. `total_runs` still
reports the run count.

### 1.5 Untracked and one-side — unchanged, deliberately

* A fully `UntrackedPathAssumption` expression leaves the universe BEFORE the
  sets are formed, so it neither carries a demand nor FUSES two decisions into
  one set (`test_untracked_leaves_the_universe_before_sets_are_formed`).
* A `OneSideUntrackedPathAssumption` stays a Z3 constraint inside every set
  that contains the expression (`test_one_side_pin_applies_inside_the_set`).

Both are now more consequential and that is written into DISCIPLINE §16: under
the old rule untracking hid a BRANCH; under this one it can also hide a
COMBINATION, because a co-evaluation gated only by an untracked decision will
never be demanded. **Untrack a gate only when its arms are interchangeable.**
The same caveat applies to the untracked side of a one-side pin and to
`unevaluable_exprs`. This is the one place where the new rule is genuinely
weaker than the old one, and it is stated rather than papered over.

## 2. Everything deleted

### 2.1 `src/concolic_engine/coverage.py`

| deleted | why |
|---|---|
| the GLOBAL clique search over the whole active universe (`_maximal_cliques(active, adj, cap=self.max_cliques)`) and its singleton-fallback `truncated` path | the demand universe is the observed evaluation sets; the clique search survives only as the per-set projection of a declared independence, where a single run's decisions bound it |
| the "dependence graph starts COMPLETE (every pair dependent)" model and its four docstring paragraphs | replaced by the co-evaluation rule + the tree-completeness precondition + the mutability property |
| `MissingCoverage.origin_run_label` | dead field, no reader anywhere in `src/` or `reports/` |
| the unused `UntrackedPathAssumption` / `OneSideUntrackedPathAssumption` imports | the module goes through `AssumptionSet.is_untracked` / `is_one_side_untracked` |
| duplicate blocking clauses (one per run) | deduped to distinct CUBES; a narrow set over a 68 231-run corpus produced thousands of identical clauses, and every one of them rode along in every Z3 query of that set |

Added: `maximal_sets()` (18 lines, with the postings index that keeps the
subset test near-linear), `tree_complete` / `tree_missing` / `demand_sets` on
`CoverageResult`, the distinct-outcome-profile collapse, and one
`_unobserved_sides()` helper that the tree check and the untracked-transparency
list now SHARE (they were the same computation twice).

**Honest accounting: `coverage.py` did not shrink.** 581 → 773 lines; CODE
lines 359 → 415 (+56), prose 96 → 190 and comments 63 → 89. Almost all of the
growth is the docstring that states the rule, its soundness argument, its
precondition and its three blind spots — which is where a semantics belongs.
The simplification this task delivers is a smaller MODEL and much less
downstream code: four whole declaration tiers and their withdrawal/bypass
machinery gone, and **−56 000 declarations on notifications alone** (§2.2–2.4).
Anyone reading this expecting `coverage.py` itself to be shorter should read
that as the claim not being made.

`max_missing_per_clique` and `max_cliques` keep their names — every endpoint's
`coverage_report.py` passes them — with `max_cliques` re-documented as the
safety cap on the projection of ONE evaluation set.

### 2.1b `src/concolic_engine/assumptions.py` — one RETIRED rule of the model

No behaviour change, but the model got smaller and the docs had to say so:
`IndependenceAssumption`'s **condition 1** — *"the two PC sources are in
execution paths that are mutually exclusive — if PC #1 is reached, PC #2 is
never evaluated in the same run"* — is **RETIRED**. Mutual exclusion no longer
needs a declaration at all; the checker derives it from the same evidence. The
docstring now says so, and says that such a declaration is INERT (noise in the
report, a free unprobed PASS in the gate) so nobody writes one again. The stale
"the tree builder promotes the two PCs to root-level nodes" text — describing a
tree builder deleted in 2026-08-18 — went with it. `src/README.md`'s
"Combination coverage (decision 2026-08-18)" entry was rewritten to the
co-evaluation rule, and `docs/RUNBOOK.md`'s tool table row for `coverage.py`
now names the tree-completeness precondition.

### 2.2 `notifications_index/coverage_assumptions.py` (1 380 → 1 115 lines)

| deleted | what its whole argument was |
|---|---|
| **`_tier_unobservable_pairs` (P1)** and every piece of its withdrawal/bypass machinery — the `withdrawn` set, `_addi`'s `withdrawn.add(key)`, the `withdrawn` argument, and the "added DIRECTLY, bypasses `_withdrawn_independence`" exemption | "two decisions recorded in DISJOINT run sets have no observable combination". That IS the engine's rule now. ~20 000 declarations, unprobed by construction. |
| the **Rule-D `_nested_pair` exemption inside P1** | under co-evaluation it draws itself: whenever there is a row, `len(X) > 1` and `X_row_*` are on one path, so the edge exists without anyone declaring it |
| **`_tier_samerep_never_coeval`** | the same rule, restricted to same-rep pairs — P1 was its generalisation |
| **`_tier0a_variant`** (variant exclusivity) | "observed only under DISJOINT request variants ⇒ no run records both". Disjoint observed variant sets are disjoint run sets. |
| **`_tier0b_type`** (STI-type exclusivity) | "observed dispatch-value sets are disjoint ⇒ no run records both" — same shape |
| the **corpus-evidence half of `_tier1c_empty_list_foreclosure`** ("closing arm observed, decision observed, never together") and its `runs` parameter | same shape again. Its STRUCTURAL half stays: a length gate and the row decisions it forecloses ARE co-evaluated on the non-empty arm. |
| `_tier2_disjoint_reps`'s `runs_of` parameter, and the 2026-08-27 NOTE that "EVERY cross-rep pair must be declared independent, including never-co-evaluated ones, or 260 blocking combos come back" | those 260 combos were demands over pairs no execution can produce |
| dead code: **`_tier_persisted_textnil`** (withdrawn by the gate 2026-08-27, never called since), **`_formatter_guid_oneside`** (superseded by `_display_untracked`), `_VARIANTS`, `_variant_of` | |

Added: a co-evaluation relation in `_observations` (built with the engine's own
`maximal_sets`, so the two cannot drift) and one filter inside `_addi` that
declines to declare a pair no run co-evaluated, **counted and printed** so the
deletions above are auditable rather than asserted:

```
[assumptions] tier0c(dispatch)=3210 tier1(foreclose)=959 tier2(disjoint-rep)=18494
  C7-A(cross-dim-len)=5 untracked=9 K1=1 WITHDRAWN(indep)=5085
  WITHDRAWN(untracked)=100 INERT(never-co-evaluated, not declared)=55737
  exprs=411 co-evaluated-pairs=28198
```

**55 737 declarations dropped as inert**; 22 678 kept, against 87 864 in the
standing (22:30, statement-keyed) summary. The assumption gate's workload falls
by the same proportion — and what it loses is exactly the population that could
only ever return a free PASS.

### 2.3 `people_stream/coverage_assumptions.py` (now 308 lines)

Deleted: **Argument 3** (id-guid arm vs username arm, 9 pairs), **Argument 4b**
(TRUE-arm tier vs FALSE-arm tier, 28), **Argument 8** (html-only vs json-only,
48), **Argument 9** (anon-json vs auth-json, 10) — 95 declared pairs, every one
of them a MUTUAL-EXCLUSION argument — plus the now-dead `ARM_VS_ARM`,
`SCENARIO_MUTUAL_EXCLUSION` and `FORMAT_MUTUAL_EXCLUSION` note constants.
`build()` gained a `runs` parameter (wired up in `coverage_report.py`) and the
same counted filter, which drops **30 more** of the surviving foreclosure pairs:
declared 47, inert 30.

Proof the deletions are inert, not a change of result: under the new engine the
FULL pre-deletion declaration set and the reduced one give **identical** output
— `nodes=29 missing=384 blocking=384 demand_sets=27 tree_missing=1` either way
(MMC=32). Only `independent_folds` differs (99 vs 44), which is the count of cut
edges, not a demand.

### 2.4 `posts_show/coverage_assumptions.py` (now 642 lines)

Deleted: **`_tier0_scenario_exclusivity`**, its now-dead `_scenario_of` helper
and its 70-line header — "every expr in the corpus is exclusively auth-only, exclusively
anon-only, or genuinely scenario-independent … disjoint sets, so no single run's
path can contain both". Its own header called it *"the dominant clique-size
reducer: without it every `evilq_*` expr is falsely demanded to combine with
every `findpublic_*` expr, which both cannot happen AND blew up maximal-clique
enumeration to 1000+ cliques of size 14–17"*. Under the new rule there is
nothing for it to reduce — the engine derives the same fact from the same
evidence. Same counted filter added.

### 2.5 `notifications_index/_exact_enum.py`

Ported to the new universe (`build_universe` now returns demand sets), profiles
deduped, and the cap message reworded. The census it produces is the same
quantity, over the new demand universe. A generic port of it,
`scratchpad/gcensus.py`, runs the same census for ANY endpoint under EITHER
semantics (`OLDCOV=1` selects an archived copy of the pre-change `coverage.py`)
— that is how the old/new deltas below were measured.

## 3. Tests

### 3.1 New — `src/test_coevaluation.py` (11 tests)

| test | pins |
|---|---|
| `test_never_coevaluated_pair_has_no_demand` | a,b each co-evaluated with c, never with each other → 2 demand sets, 4 missing, nothing naming both |
| `test_a_run_that_coevaluates_them_creates_the_demand` | the same declaration is INERT before and CUTS after; the demand appears with ALL its satisfiable assignments; earlier demands all survive |
| `test_adding_runs_only_covers_or_adds_demand` | monotonicity: 3 → 2 → 1 → 0 missing, each a strict subset of the last |
| `test_a_superset_evaluation_set_subsumes_without_weakening` | subset dedup strengthens the demand ({a,b} covered, then a run walks {a,b,c} → 7 missing, all naming all three) |
| `test_triangle_pairwise_but_never_together` | three pairs exhaustively covered, never jointly → COMPLETE (old rule: 8 missing, forever) |
| `test_incomplete_tree_refuses_the_combination_claim` | `tree_complete=False`, the exact `tree_missing` entry, `COMBINATION CLAIM REFUSED` in `summary()`, and restoration when the outcome is driven |
| `test_tree_incompleteness_always_shows_up_as_a_missing_combination` | `complete ⇒ tree_complete` over three corpora — the precondition is a named consequence, not a second gate |
| `test_untracked_leaves_the_universe_before_sets_are_formed` | an untracked decision neither carries a demand nor FUSES two decisions into one set |
| `test_one_side_pin_applies_inside_the_set` | the pin narrows a set's demand; the set is unchanged |
| `test_projection_cap_is_per_set_and_flags_truncated` | `max_cliques` is the per-evaluation-set projection cap; hitting it sets `truncated` and forbids `complete` |
| `test_maximal_sets_drops_subsets_and_is_deterministic` | the demand-universe helper, including stable ordering across passes |

### 3.2 Existing tests — what changed, consciously

**Nothing.** All 74 pre-existing tests in `test_assumptions.py`,
`test_symbolic.py`, `test_symbolic_func.py`, `test_path_explosion.py` and
`test_interceptor.py` pass under BOTH engines, verified by running them against
an archived copy of the pre-change `coverage.py`
(`scratchpad/run_against_old.py`: `76 passed, 8 failed`, and all 8 failures are
new co-evaluation tests). Two of them looked like candidates and are not:

* `test_coverage_partial_tree` — "run3 merely TERMINATING after a>0=F does not
  cover the (a=F, b=…) combinations". Still 2 missing: run3's evaluation set
  `{a}` is a subset of runs 1–2's `{a,b}`, so it is subsumed and the demand over
  `{a,b}` stands. The fetch-then-404 conservatism is deliberately PRESERVED.
* `test_independence_is_pairwise_not_promotion` — chain p→a→b, one run (T,T,T),
  declare a ⊥ b. Still 6 missing, none naming both a and b: the single
  evaluation set `{p,a,b}` projects to `{p,a}` and `{p,b}`.

That result is itself a finding worth recording: **the complete-graph default
was never covered by a test.** Every pre-existing coverage test drives a single
`py_runtime` target whose runs evaluate every expression, so both rules agree on
all of them; the only way to tell the two apart is a corpus with DISJOINT
evaluation sets, and none existed. The default was assumed, not tested.

One PRE-EXISTING red was fixed and is unrelated to this change:
`test_untracked_by_expression_at_a_shared_source` asserted
`blocking == {expr_a}` where a blocking entry is a missing COMBINATION whose
`node_constraint` is `Not((a == 1))`. It fails identically on the previous
`coverage.py`; the assertion now checks the decision the entry names.

## 4. Rule T — what `complete: true` now means, and who is voided

The decision record is in `docs/DISCIPLINE.md` **§16 (2026-09-10)**, written in
the same form as the 2026-08-18 one it supersedes, including the
tree-completeness precondition and the untracked/one-side blind spots. §16a
carries the argument below.

### 4.1 The argument: old-complete ⇒ new-complete, with EQUAL demand universes

1. Every demand set is a clique of the dependence graph (its adjacency is
   induced from that graph), hence contained in a maximal clique of it.
2. Old-complete means every maximal clique had all its satisfiable assignments
   observed. An assignment is only ever observed by a run that evaluated the
   WHOLE clique (that is exactly the old step-6 blocking clause), so every
   maximal clique with at least one satisfiable assignment is contained in some
   run's evaluation set.
3. A maximal clique of the whole graph that is contained in an evaluation set
   `S` is also maximal in the graph induced on `S` — nothing in `S` is adjacent
   to all of it, because nothing in the whole graph is. So every old maximal
   clique IS a demand set, and every other demand set is a subset of one and is
   dropped by the subset dedup.
4. Same sets, same pins, same blocking clauses, same solver ⇒ same verdict. ∎

**The one exception, and why it cannot touch a closed endpoint.** A
`OneSideUntracked` pin on an expression that some run evaluated APART from a
decision it was cliqued with: the old rule let that pin suppress a branch demand
on a path where the pinned decision was never evaluated at all; the new rule
demands it, because on that path the pin has nothing to say. That divergence
needs step 2 to fail — i.e. a corpus that was NOT old-complete — so it cannot
arise on a closed endpoint. It is a strictly more correct demand, not a
regression. (people_stream, which is not complete and does carry three one-side
pins, is where it shows up: see §6.)

### 4.2 Verified, not just argued

Each closed / milestone endpoint re-checked under the new engine with its own
UNCHANGED `coverage_assumptions.py`, read-only (`scratchpad/ruleT_check.py`
never writes a `coverage_summary.json`):

| endpoint | runs | nodes | demand sets | missing | coverage_complete | tree_complete | assumptions_used |
|---|---|---|---|---|---|---|---|
| comments_index | 26 528 | 84 | 85 | **0** | **True** | **True** | 3 432 |
| conversations_index | 18 623 | 105 | 83 | **0** | **True** | **True** | 5 336 |
| people_show | 12 997 | 97 | 239 | **0** | **True** | **True** | 130 |

`comments_index`'s standing summary records 84 nodes, 0 missing,
`assumptions_used` 3 432 — identical. **No closed endpoint is voided; none needs
re-driving or re-arguing.** Their `coverage_summary.json` files were not
touched.

What DOES change is the meaning of a `complete: true` earned from now on: it is
conditional on `tree_complete`, and it no longer includes combinations of
decisions that no execution can make together.

## 5. people_stream — delta, and the explanation

Measured with `scratchpad/gcensus.py` (a generic port of `_exact_enum.py`), the
same corpus and the same load path under both semantics. `OLDCOV=1` selects an
archived copy of the pre-change `coverage.py`; `PS_OLD_ASSUMPTIONS=1` restores
the 95 pairs §2.3 deleted, so the OLD column is the pre-task configuration
exactly.

| | OLD (complete-graph + full declarations) | NEW (co-evaluation + reduced declarations) |
|---|---|---|
| runs / nodes | 755 / 29 | 755 / 29 |
| demand groups | **10 maximal cliques**, widths 15–17 | **27 demand sets**, widths 2/5/7 |
| satisfiable assignments | **188 416** | **531** |
| covered | **0** | **99** |
| remaining | 188 416 (**100 %**) | 432 (**81 %**) |
| groups no run evaluated whole | **10 of 10** | **0 of 27** |
| groups fully covered | 0 | 3 |

**Explanation.** The STATE_HANDOFF line "40/40 combinations UNOBSERVABLE
(exhaustive, through the load path)" is now quantified exactly, and it was worse
than 40: the old rule demanded **188 416** assignments over ten cliques of width
15–17, and **not one of them was coverable by any run at any corpus size** —
every clique spanned decisions from mutually exclusive request formats and
controller arms, so no execution could evaluate a whole one. `missing = 40` was
`10 cliques × MMC 4`, a clique count, never a gap (STATE_HANDOFF correction 5).

Under co-evaluation the corpus has 9 distinct maximal evaluation sets, which
project to 27 demand sets, and the target is **531** assignments of which 99 are
already covered. Every one of the 432 remaining is over a set some run actually
walked, so every one is a candidate for driving — which is the difference
between "needs a decision from the owner" and "needs more runs".

Two secondary numbers move and both are artefacts of the cap, not of the gap:
`missing` at MMC=4 goes 40 → 96 (24 demand sets with a gap × 4, against 10
cliques × 4) and at MMC=32 it is 384. Quote the census, not `missing`.

`tree_missing = 1` — so people_stream is NOT tree-complete and the combination
claim is refused independently of the 432. The entry names it:

```
(SYM_RESULT_ActsAsApi__Collection_as_api_response_1_row_guid != StringVal('')) :: taken
```

which is the SAME framework short-circuit the endpoint already declares
`OneSideUntracked(tracked_side="not_taken")` for on three other expressions
(Argument 5, `GUID_TRUE_UNREACHABLE`: actionpack reaches `segment != ''` only on
the blank-guid path, where it is always False). This one — the json-render
instance of it — was never declared, and under the old rule nothing pointed at
it, because it was buried inside a 100 %-unobservable clique. The precondition
found it on its first pass. It is either a fourth instance of that declaration
or a branch to drive; either way it is now a NAMED next action instead of an
unexplained residual.

The new fields are in the regenerated `people_stream/coverage_summary.json`:
`demand_sets: 27`, `tree_complete: false`, `tree_missing: [...]`.

**The deletions are inert, proven:** under the new engine the FULL pre-deletion
declaration set and the reduced one give identical output
(`nodes=29 missing=384 blocking=384 demand_sets=27 tree_missing=1`); only
`independent_folds` differs (99 vs 44), and that counts cut edges, not demands.

## 6. notifications_index — the re-pricing

All passes: `systemd-run --user --slice=concolic-cov.slice --scope -p
MemoryMax=10G`, `JAVA_TOOL_OPTIONS` unset. **The cap was verified in the
cgroup, not just in `systemctl show`** (§10 of the alias report: the earlier
OOM-kills came from `app.slice`'s own 5 GB `MemoryMax` when `--slice` was
omitted):

```
/sys/.../concolic.slice/memory.max                      -> max
/sys/.../concolic.slice/concolic-cov.slice/memory.max   -> max
/sys/.../concolic-cov.slice/ndxcovD.scope/memory.max    -> 10737418240
```

Peak RSS of the pass: **2 451 MB** — nowhere near the cap, and the parent
slices impose none.

### 6.1 The coverage pass (`coverage_report.py`, `SKIP_COMPLETION=1`, MMC=1)

```
[assumptions] tier0c(dispatch)=3210 tier1(foreclose)=959 tier2(disjoint-rep)=18494
  C7-A(cross-dim-len)=5 untracked=9 K1=1 WITHDRAWN(indep)=5085
  WITHDRAWN(untracked)=100 INERT(never-co-evaluated, not declared)=55737
  exprs=411 co-evaluated-pairs=28198

COMPLETE=False; NODES=411; MISSING=984; BLOCKING=980; PCS=4018735
GENUINE=True; TRUNCATED=True; SOLVER_LOST=0; UNEVALUABLE=[]
coverage phase: 566 s   declared assumptions: 22 679   assumptions_used: 21 712
```

`MISSING = 984` at MMC=1 is **980 demand sets with at least one uncovered
satisfiable assignment**, plus 4 untracked transparency entries — against 997
demand sets in total, i.e. **17 demand sets are fully covered**. `TRUNCATED` is
the MMC=1 witness cap, as always. The 997 agrees exactly with the independent
universe probe, which is the cross-check that the pass and the census are
measuring the same universe.

The completion gate (shim tests, note check, assumption gate) was NOT run: the
brief forbids JRuby slots this session, so `SKIP_COMPLETION=1` and the summary
correctly carries `complete: false` with
`"completion gate did not run (coverage-only pass / SKIP_COMPLETION)"`.

### 6.2 The exact census (`_exact_enum.py`, ported to demand sets)

Same corpus, same load path, same assumptions, `bounded_cliques=0` (every
figure exact, not a lower bound), `--verify 6` cross-check **6/6 OK** against
direct all-SAT.

| | OLD — complete-graph (2026-09-09, shipped alias) | NEW — co-evaluation |
|---|---|---|
| nodes / active / untracked | 411 / 402 / 9 | **411 / 402 / 9** |
| demand groups | 1 277 maximal cliques | **997 demand sets** |
| widths | 3–20 | **3–20** (4 sets of width 20, unchanged) |
| satisfiable assignments | 542 784 | **491 264** (−9.5 %) |
| covered | 13 891 | **13 990** (+99) |
| remaining | 528 893 | **477 274** |
| **uncovered** | **97.44 %** | **97.15 %** |
| groups no run evaluated whole | **330** | **2** (and neither is a coverage gap — §6.4) |
| groups fully covered | 17 | 17 |

Cross-checks: the coverage pass's `MISSING = 980` blocking entries at MMC=1 is
997 demand sets − 17 fully covered, exactly; and the independent universe probe
and the census agree on 860 evaluation sets → 997 demand sets.

### 6.3 Pre-registration vs measurement — TWO OF FIVE PREDICTIONS SURVIVE

| | prediction | measured | verdict |
|---|---|---|---|
| P1 | zero demand sets evaluated whole by no run | 330 → **2**, and both are a MODELLING inconsistency, not a demand no run can reach | **CONFIRMED** in substance |
| P2 | nodes 411, active 402, untracked 9 | 411 / 402 / 9 | **CONFIRMED** |
| P3 | many MORE, strictly NARROWER demand sets | **FEWER** (1 277 → 997), widths unchanged (3–20) | **REFUTED** |
| P4 | satisfiable falls to 150 000–300 000 | **491 264** (−9.5 %) | **REFUTED** |
| P5 | uncovered fraction well below 90 % | **97.15 %** (was 97.44 %) | **REFUTED** |
| P7 | driving reach improves | covered +99 on the same corpus | **REFUTED** |

**So: the complete-graph default was NOT the blocker on notifications_index,
and I have to say so rather than dress the 0.29-point move up as a win.**

Why P3/P4/P5 were wrong, and it is the same mistake three times. I assumed the
corpus's evaluation sets would FRAGMENT the cliques. They do not: an evaluation
set on this endpoint is 51–62 decisions wide, so it CONTAINS whole cliques.
The only cliques it fragments are the narrow spurious ones, and those were
cheap. The evidence the brief cited — "330 of 1 277 cliques are evaluated whole
by NO run" — is true, and I re-derived it, but the 330 held only **59 152 of
542 784 satisfiable assignments (10.9 %)**, and they were overwhelmingly
NARROW: 191 of width 5, 92 of width 6, 16 of width 4. Removing an artefact that
holds a tenth of the mass cannot move a 97 % figure.

Where the mass actually is, and this is the finding that matters:

* **41 demand sets of width ≥ 13 hold 380 432 of the 477 274 remaining —
  79.7 %.** Four sets of width 20 alone hold 131 016 (27.5 %).
* Every one of them **IS co-evaluated** — the corpus walks them. They were
  never the artefact.
* They are barely DRIVEN: across all 997 sets the corpus's 68 231 runs produce
  a **median of 14 distinct cubes per set, max 55** (14 171 in total). The four
  width-20 sets, 32 768 satisfiable assignments each, got **16, 15, 13 and 12
  covered** — one per distinct cube, i.e. the corpus produced twelve to sixteen
  DISTINCT outcome combinations over twenty co-evaluated decisions, in 68 231
  runs.

That is a qualitatively different diagnosis from the one this endpoint has been
carrying, and it is what the new semantics BUYS even though it did not move the
number: under the old rule you could not tell "unobservable" from "undriven",
so 97 % of the residual had no actionable reading. Under the new rule
**the entire residual is over sets some run actually walked**, so all of it is
a driving problem and none of it is a modelling problem. The question stops
being "is this reachable at all?" and becomes "how many varied runs?" — §7.

Two caveats on that sentence, both stated in the engine docstring and neither
hidden here: (a) co-evaluation is a fact about the SET, not a promise that
every assignment OVER the set is reachable — the fetch-then-404 corner inside a
walked set is still demanded and still needs an explicit independence, so the
477 274 is an UPPER bound on what driving must produce; (b) 2 of the 997 sets
are the §6.4 defect and their 128 assignments are not a driving target at all.

### 6.4 A defect the precondition surfaced: 2 sets whose OWN observed outcomes are UNSAT

Two width-7 demand sets (64 satisfiable assignments each) report `covered = 0`
while having 2 and 1 distinct observed cubes respectively. By construction that
should be impossible: a cube comes from a run that walked the whole set, so it
must be satisfiable. `covered = 0` means every observed cube is inconsistent
with EVERY model of the set's variable components — i.e. **the corpus recorded
an outcome combination that the batch's declared Z3 model says cannot happen.**

That is a modelling inconsistency in this batch's declarations (the candidates
are `coverage_report.apply_len_bounds`'s `SYM_LEN_*` domains — `{0,1}`,
`{0..3}`, `{0..4}` by name suffix — and the `SYM_NOTE_TYPE_PROFILE` /
`SYM_POST_STI` bounds), not a coverage gap and not an engine bug: the same
two sets were among the old 330, where they were invisible because 330 sets
looked the same. **Not yet localised to the offending expressions** — the job
that dumps the two sets' members and their observed cubes
(`scratchpad/curve.py`, `zero_covered_detail`) was written and is queued but
did not get a memory window this session; it needs one 68 231-dump load
(~2.5 GB, ~15 min) and no driving. **It is a Class-B
finding for this batch: a declared domain that excludes something the runtime
produced makes every demand computed under it suspect.**

## 7. Is notifications_index reachable by driving now?

### 7.1 What the census says, arithmetically

477 274 satisfiable assignments remain, and — for the first time — **every one
of them is over a set some run actually walked**, so the question is now about
volume rather than possibility. The binding constraint is the widest set, and
the shape of the problem is extremely lopsided:

| | sets | coupon-collector demand `n·H(n)` |
|---|---|---|
| widest (width 20, 32 768 satisfiable each) | 4 | **359 609 runs** |
| next (width 19, 16 384 each) | 4 | 168 448 runs |
| the MEDIAN set with a gap | — | **129 runs** |

Because ONE run assigns every decision at once, a varied run covers one
assignment in EVERY set it walks simultaneously — the owner's 2026-09-09
insight, unchanged and now applicable to sets that can actually be walked. So
the whole corpus converges at the rate of its widest set:

* **~360 000 varied runs**, ≈ **3.1 hours** at the measured ~32 runs/s
  (~6.2 h at 16 runs/s, ~1.6 h at 64 runs/s).

That is against the old figure of **~8.7 M runs / ~75 h as a LOWER bound, over
a target 330 of whose 1 277 cliques were unreachable at any volume**. The
change in the answer comes almost entirely from the demand being reachable at
all, not from it being smaller.

### 7.2 What the corpus says, empirically — and this is the caveat

The arithmetic above assumes each run draws a FRESH assignment in each set.
The corpus does not do that: 68 231 runs produced a **median of 14 distinct
cubes per demand set (max 55, 14 171 in total)**. The four width-20 sets got
**16, 15, 13 and 12** distinct cubes — and therefore that many covered
assignments — out of 32 768 each. The driving is not varying the dimensions
those sets span; it is re-walking a handful of shapes tens of thousands of
times.

That is consistent with the STATE_HANDOFF diagnosis and with the tool that was
built for it and never run: `_diverse_seeds.py` randomises the seedable
variables over `{0, 1, 2, 4}` (the domain the PCs actually test), and
`_diverseR.json` holds 6 000 such seeds.

The marginal rate itself needs no new job to be read off what is already
measured: the covered count moved **13 891 → 13 990** across the semantics
change on the SAME 68 231 runs, and the previous pass measured 0.061 newly
covered assignments per run over 34 000 → 68 231 runs. Neither number is a
property of the demand rule; both are properties of the DRIVING, and the
driving did not change. A `covered_at(k)` curve (`scratchpad/curve.py`, one
load, no driving) would put points on that line and is the obvious next
measurement, but it would not change the reading.

### 7.3 The precondition's verdict on notifications, and what it hands the driver

`tree_complete = **false**`, with **13** named satisfiable branch outcomes the
68 231-run corpus never drove:

```
Core__ClassMethods_find_by_1_not_found == True            :: taken
Core__ClassMethods_find_by_1_persisted == True            :: not_taken
Core__ClassMethods_find_by_1_profile_not_found == True    :: taken
FinderMethods_find_by_4_not_found == True                 :: taken
FinderMethods_devise_user_first_1_username == ''          :: taken
Relation_size_2_size > 0                                  :: not_taken
CollectionProxy_records_photos_312a5782_row_text_dlink_is_post == True   :: not_taken
to_ary_notifications_10254800_row_target_text_dlink_is_post == True      :: not_taken
to_ary_notifications_{c7e6a7ca,cf379872}_row_target_statusmessage_text_dlink_is_post == True :: not_taken
to_ary_notifications_10254800_row_target_mentions_container_commentable_author_profile_disp_dlink_is_post == True :: not_taken
to_ary_notifications_{c7e6a7ca,cf379872}_row_target_statusmessage_mention_inline_name == True :: not_taken
```

Under the old rule these thirteen were invisible: they were dissolved into
2 046 combination entries and nothing in the report said "this single decision
has never been taken the other way". They are the cheapest thirteen things to
drive on this endpoint and they gate the combination claim outright — no amount
of combination coverage can make `complete` true while any of them stands.

### 7.4 The answer

**Not yet — but it is now a driving question with a number attached, which it
was not before.**

* Under the old semantics the honest answer was NO on principle: 330 of 1 277
  cliques could not be covered by any run at any volume.
* Under the new semantics nothing is unreachable on principle. The work is:
  **13 branch outcomes** (tree completeness — mandatory, and cheap), then
  **477 274 combination assignments**, converging at the rate of the widest set
  — **~360 000 varied runs, ≈3 hours** at ~32 runs/s, IF the driving varies the
  seeded dimensions.
* **That "if" is currently false and is the whole problem.** 68 231 runs
  produced 12–16 distinct outcome combinations on each of the four width-20
  sets. The corpus is re-walking a handful of shapes, not exploring the space.
  Running the already-built `_diverseR.json` (6 000 seeds over `{0,1,2,4}`) and
  re-measuring the covered count is the one experiment that decides this: if
  6 000 diverse runs move `covered` by roughly 6 000 × (sets they walk) rather
  than by ~6, the 3-hour figure holds; if they do not, the seeded dimensions
  are not free and the residual needs modelling, not driving.
* The two §6.4 defect sets must be fixed first regardless — a declared domain
  that excludes something the runtime produced makes every demand computed
  under it suspect.

## 8. posts_show — delta, and an honest COST finding

Full 96 357-run corpus, `pxcov3.scope` (`--slice=concolic-cov.slice`,
`MemoryMax=9G` verified in the cgroup, peak RSS 6.7 GB, `JAVA_TOOL_OPTIONS`
unset). Load 11 min, coverage phase **4 481 s**.

| | OLD (complete-graph, 2 895 declarations) | NEW (co-evaluation, 543) |
|---|---|---|
| nodes | 101 | **101** |
| declared assumptions | 2 895 | **543** (411 of the survivors dropped as inert) |
| `assumptions_used` | 2 595 | **543** |
| demand groups | 83 cliques WITH a gap (332 missing / MMC 4) | **563 demand sets**, 561 with a gap |
| `missing_branches` (MMC=4) | 332 | **2 248** |
| `truncated` / `solver_lost` | true / 0 | true / 0 |
| `tree_complete` | not computed | **false — 11 named branches** |

### 8.1 Explaining every part of the delta

* **nodes 101 -> 101.** The universe of distinct PC expressions does not depend
  on the demand rule. This is the check that the load path is intact, and it
  passes.
* **declarations 2 895 -> 543 (-81 %).** `_tier0_scenario_exclusivity` deleted
  outright (§2.4) — "these exprs' observed scenario sets are DISJOINT, so no
  single run's path can contain both" is the claim the engine now makes for
  itself — plus **411** of the survivors dropped by the counted filter for the
  same reason. Its own header called TIER 0 *"the dominant clique-size
  reducer"*; under the new rule there is nothing for it to reduce. The
  assumption gate's workload falls with it, and what it loses is exactly the
  population that could only ever return a free "mutually exclusive" PASS.
* **`missing` 332 -> 2 248, and it is NOT a regression.** Both numbers are
  `groups with a gap x MMC`, never a gap: 83 x 4 and 561 x 4. The DEMAND got
  weaker (every demand set is a subset of an old clique); the number of
  enumeration GROUPS got larger. Quote a census, not `missing` — this is
  STATE_HANDOFF correction 5 in its sharpest form yet, on an endpoint where the
  two move in opposite directions.
* **563 demand sets where there were 83 cliques with gaps — the cost finding.**
  posts_show declares 543 independences over 101 decisions, and its evaluation
  sets are very wide (20–42 decisions). Cutting 543 edges INSIDE a 40-decision
  set breaks it into many maximal cliques, and different evaluation sets yield
  cliques that do not subsume one another. The demand sets are correspondingly
  wide — every missing entry in the report names **33–36** decisions at once —
  and each costs `2 x width` solver calls per witness.

  **So the co-evaluation rule is not uniformly cheaper, and this is the case
  that shows it.** It removed the GLOBAL clique-count blow-up (and the silent
  singleton fallback that voided a notifications pass on 2026-09-08): the
  projection can no longer be exceeded by the size of the universe, only by one
  run's decisions. But the number of enumeration groups is now bounded by
  `evaluation sets x cliques per set`, and on this endpoint that is bigger than
  the old global clique count. Three engine-side mitigations went in during this
  session and are already in the 4 481 s above — profiles deduplicated to
  distinct outcome profiles, blocking clauses deduplicated to distinct cubes,
  and step 6 indexing profiles by evaluation set rather than scanning all of
  them per group (that loop alone made the first attempt on this corpus run
  past 50 minutes without finishing). Batching the per-witness solver calls is
  the next one if this endpoint stays expensive.
* **`tree_complete: false`, 11 named branches** — a verdict this endpoint has
  never had. Four are the `as_api_response_N_row_guid != StringVal('')` family
  (the SAME framework short-circuit people_stream declares `OneSideUntracked`
  for, and posts_show does not — see §5, this is now the second endpoint
  showing it), four are `SYM_LEN_..._rows != 0` / `!= 0` arms, and three are
  `evilq_act_public_1_{not_found,text_has_mention}` and a mention flag. Cheap,
  named work that gates the combination claim outright.

### 8.2 What was NOT measured

No exact census for posts_show. `scratchpad/gcensus.py` runs the same
satisfiable/covered/remaining census for it under either semantics (one load,
no driving) and is the right next measurement — `missing` on this endpoint is
now demonstrably a group count moving OPPOSITE to the demand, so nothing about
its residual should be quoted until the census exists.

## 9. How it was run, and what was NOT run

* Every heavy job: `systemd-run --user --slice=concolic-cov.slice --scope -p
  MemoryMax=<N>G`, `JAVA_TOOL_OPTIONS` unset. **The cap was verified in the
  cgroup, not just in `systemctl show`** — the parent slices report
  `memory.max = max`, so no `app.slice` 5 GB ceiling applies:
  `concolic.slice/memory.max = max`,
  `concolic.slice/concolic-cov.slice/memory.max = max`,
  `.../ndxcovD.scope/memory.max = 10737418240`. Peak RSS: notifications 2.5 GB,
  posts_show 6.7 GB. Nothing was OOM-killed; one posts_show attempt was killed
  by ME when the box reached 14 GB of 15 GB with two loads resident.
* **No driving.** No `run_dse.rb`, no JRuby, no gate probes, no slots. The
  completion gate did not run on any endpoint, so no summary written today
  claims completeness: notifications carries `complete: false` with
  `"completion gate did not run (coverage-only pass / SKIP_COMPLETION)"`, and
  people_stream / posts_show carry `coverage_complete: false` (those two
  endpoints have no `completion_config.json`, so their reports never emit a
  `complete` key at all). A coverage-only pass must never leave a completeness
  claim behind.
* Reference policies untouched and quarantined. Closed endpoints' summaries
  untouched (verified by mtime: 2026-09-01 / 2026-09-05).
* `src/` has its own git with many pre-existing uncommitted changes. **Nothing
  was committed or reverted**; today's work sits on top.
* One PRE-EXISTING red was fixed and disclosed (§3.2).

### Artefacts

In the batch: `_COEVAL_SEMANTICS_20260910.md` (this file), the regenerated
`coverage_summary.json` (with `demand_sets` / `tree_complete` / `tree_missing`),
`_exact_enum.py` (ported).
In `src/`: `concolic_engine/coverage.py`, `concolic_engine/assumptions.py`
(docs), `README.md`, `test_coevaluation.py`, one fixed assertion in
`test_assumptions.py`.
In `docs/`: `DISCIPLINE.md` §16 + §16a, `RUNBOOK.md` §3 tool table.
In the scratchpad (`/tmp/claude-1000/-home-dev-project/94ab9891-.../scratchpad/`):
`pxprobe.json` (posts_show sampled sizing probe),
`exact_coeval.json` (the new census), `exact_shipped.json` /
`exact_statement.json` (the old ones, from 2026-09-09), `cens_ps_new.json` /
`cens_ps_old.json` (people_stream both ways), `gcensus.py` (generic census,
either semantics via `OLDCOV=1`), `ruleT_check.py` (read-only closed-endpoint
re-check), `universe_probe2.py` (sampled sizing probe), `curve.py` (queued:
covered-vs-corpus-size + `zero_covered_detail`), `oldcov/` (archived
pre-change `coverage.py`), `run_against_old.py` (runs the src tests against it),
`ndxcovD.log` / `ndxcovF.log` / `px_new3.log` / `cm_ruleT.log` / `cv_ruleT.log`.

---

# APPENDIX A (2026-09-11) — §2.4 revisited: the TIER 0 deletion was RIGHT, and that is not what went wrong on posts_show

Written by the posts_show drive, on the coordinator's instruction to correct the
semantics record. It is an APPENDIX: nothing above is rewritten, and §2.4's
reasoning is not withdrawn — it is confirmed, and then completed.

## A.1 What §2.4 claimed, and what the measurement says

§2.4 deleted posts_show's `_tier0_scenario_exclusivity` on the ground that

> "Under the new rule there is nothing for it to reduce — the engine derives the
> same fact from the same evidence."

**That is CORRECT, and it is now measured rather than reasoned.**
`posts_show/_tier_recover.py` recovered the tier verbatim from `reports@f75f9c2`
and ran it against the p5 corpus (31 054 distinct outcome profiles), testing its
pairs against the SAME co-evaluation relation `build()`'s own filter uses:

```
pairs TIER 0 would declare   : 3487
of those CO-EVALUATED on p5  :    0
of those NEVER co-evaluated  : 3487
=> SUBSUMED BY §16           : True
```

**Zero of 3 487.** Tier 0's criterion is "these two exprs' observed SCENARIO
SETS are disjoint"; the filter's is "no run evaluates both". On one corpus those
are the same predicate, so restoring tier 0 would add 3 487 declarations and
relax nothing. The 2 895 → 543 collapse in posts_show's `declared` count was an
ACCOUNTING change, not a demand change.

## A.2 What the record missed — an inference, not a deletion

The deletion was sound. The unexamined step was what posts_show was left with
AFTERWARDS.

* `notifications_index` kept **`_tier2_disjoint_reps`** — a tier over pairs that
  ARE co-evaluated, declared independent because they are taken on DIFFERENT
  symbolic reps. Co-evaluation semantics does not touch that tier, which is why
  notifications did not explode.
* `conversations_index` and `_auth_boundary` keep the same tier.
* **posts_show has never had one** — not in results3, not in results2. Its
  `_tier2_attempt_chain_pairs` is a different claim (the evilq/findpublic
  attempt chain). A `def _tier*` census across every `coverage_assumptions.py`
  in results2 and results3 confirms it.

So posts_show was the one endpoint where deleting tier 0 left **no rep-level
independence of any kind**, and it had nothing to fall back on. §6-§7's
observation that posts_show went 83 → 563 demand groups with Z3 cost UP was the
symptom of exactly that, and it was recorded and not acted on.

## A.3 What it cost, measured

On the p5 corpus, with the surviving tiers only:

```
demand sets 1805   satisfiable 48 548 318 047 288   covered 482 516
remaining   48 548 317 564 772        (bounded_cliques=0 — exact, not a bound)
```

and the cause is not the solver: of the 8 206 pairs the dependence graph joins,
**8 201 (99.9 %) share no Z3 variable**, no variable-connected component
anywhere exceeds 2, and the widest demand set has 45 members in 45 components.
For comparison, notifications on a corpus three times larger reports
`remaining = 24 185`.

## A.4 The contrast that settles which tier matters

| | pairs | CO-EVALUATED | verdict |
|---|---|---|---|
| TIER 0 (scenario exclusivity, deleted) | 3 487 | **0 (0 %)** | genuinely subsumed by §16 — correctly deleted |
| TIER 2 (disjoint reps, never existed here) | 4 566 | **2 645 (58 %)** | NOT subsumed — these carry real demand |

That is the operational test the record should carry going forward: **a tier
whose pairs are 0 % co-evaluated is subsumed; a tier whose pairs are
co-evaluated is not, whatever its geometric justification.** Disjointness of
SCENARIOS implies never-co-evaluated. Disjointness of REPS does not.

## A.5 What was done

The disjoint-rep tier was PORTED to posts_show under notifications'
original criteria, with the already-adjudicated refutations inherited rather
than re-litigated — W-E (lengths/cardinality), W-C (the request-routing
dispatch), W-F (`not_found x not_found`, which withdrew 507 of 1 787 net-new
candidates here) — and the remainder submitted to the assumption gate, one
representative per rep-pair class, PASS-only shipping. Rule T3: nothing shipped
ungated. Full record: `posts_show/_COMPLETION_20260910.md` §60-§64.

## A.6 A defect the exercise exposed in the gate itself (X10)

Running the gate on a canonicalizing endpoint for the first time revealed that
`assumption_checker.py`'s IndependenceAssumption probe wrote each flip at the
RUNTIME (ordinal) seed key and read the combined flip back at the CANONICAL key
— identity only when nothing is aliased, `KeyError` otherwise — and that
`run_declared` had no per-probe isolation, so the first such pair ended the
whole suite with no results file. **No IndependenceAssumption had ever been
flip-both probed on a canonicalizing batch.** Fixed in `src/` under coordinator
authorization, with a ground-truth differential test (4/4 FAIL pre-fix with the
production `KeyError`, 4/4 PASS after) and the full `src/` suite green. The
re-verification list — which batches canonicalize, and how many of their
declarations cite the flip-both probe — is in `../_STATE_HANDOFF.md`,
"Re-verification required (X10)". **notifications_index is the batch with
declarations at stake: 7 declaration sites, 17 evidence citations**, to be
re-probed by its certification run on the fixed gate.
