# Foreclosure — co-evaluation judged per ASSIGNMENT (2026-09-10)

**What changed.** `src/concolic_engine/coverage.py` now judges a combination
demand per ASSIGNMENT, not per SET. The owner's co-evaluation principle ("a
line is drawn only where decisions are seen together") is applied at the
granularity where the tree actually lives. It is **not** a new assumption kind:
nothing is declared, no `AssumptionSet` entry exists, and the relation is
INFERRED from the corpus.

Decision record: `docs/DISCIPLINE.md` **§16b**. Engine docstring: the
"Foreclosure" section of `coverage.py`.

## Headline

**The rule.** Decision `g` with outcome `o` FORECLOSES decision `d` iff some run
evaluated both AND every run in which `g` took `o` left `d` unevaluated. A demand
set's demanded objects are then the LEAVES of the pruned tree over it, not the
flat cross-product. Inferred from the corpus; nothing declared.

**Measured on notifications_index**, 109 401-dump snapshot, both arms in one
process, `--verify 6` 6/6 OK, `bounded_cliques = 0`:

| | set-level (§16) | **foreclosure-aware (§16b)** |
|---|---|---|
| demanded assignments | 603 032 | **62 324  (−89.66 %)** |
| covered | 16 781 | **25 625  (+52.7 %)** |
| remaining | 586 251 | **36 699** |
| uncovered | 97.22 % | **58.88 %** |
| the four width-20 sets | 36 864 demanded each, 14–16 covered | **488/356/356/356 demanded, 122–193 covered** |
| largest single-set gap | 36 850 | **551** |
| coupon-collector bound | 408 904 runs, 6.3 h @18/s | **4 796 runs, 0.07 h** |
| `tree_missing` | 10 | 10 |

3 507 foreclosures applied (12 001 inferred), top gates exactly the two families
the campaign's ground-truth differential proved, plus `stale_language` which
nobody had noticed.

**Reachability: the demand is reachable; the seeder is now the blocker** — and
10 tree-missing branches still refuse the claim outright. §3.4.

**Rule T not triggered**, verified read-only: comments_index 84/85/0,
conversations_index 105/83/0, people_show 97/239/0 — all still `complete`,
`tree_complete`, summaries untouched. §4.

---

## §0. PRE-REGISTRATION (written before the full pass was run)

Snapshot taken first, because a v3.1 tree-completeness drive owned by another
agent is adding dumps to this directory right now:

```
find . -maxdepth 1 -name 'dump_*.json' | sort > _snapshot.txt
109 401 dumps      (the 2026-09-10 morning census ran on 68 231)
```

Every number below is against that snapshot, both arms of the delta on the
IDENTICAL list, same load path, same `coverage_assumptions.py`, nothing
declared or withdrawn for the occasion.

The reference point the brief names is `_COMPLETION_CAMPAIGN_20260910.md` §5.1:
suspending the W-C/W-F class withdrawals moved satisfiable **492 712 -> 51 264**
(-89.6 %) and wide sets (width >= 13) **34 -> 0** on a 572-dump snapshot.

| # | prediction |
|---|---|
| **F1** | Foreclosure cuts the satisfiable total by **>= 85 %** against the set-level census on the same snapshot — at least as good as the W-C/W-F hack's 89.6 %. |
| **F2** | The four width-20 sets fall from 36 864 demanded each to **<= 100 each** (§3.3 computed 32/16/16/16 structurally feasible). |
| **F3** | Wide sets do **NOT** go to 0, unlike §5.1. Foreclosure does not FRAGMENT a set — it prunes assignments inside it — so the width histogram is UNCHANGED and the count of width-  >= 13 sets stays where it is. Their REMAINING MASS falls by >= 95 %. This is a real difference from the independence hack and I expect to have to say so. |
| **F4** | `covered` goes **UP** vs the set-level census on the same corpus, by >= 50 %: a run that stopped early now earns credit for the leaf it walked (invariant 2), which the set-level rule refused it. |
| **F5** | The uncovered fraction drops from ~99 % to somewhere in **60–95 %** — tighter than §5.1's 94.36 %, but I do not expect it near zero: the genuinely free dimensions are still undriven (campaign §4). |
| **F6** | Foreclosures inferred: **1 000 – 10 000** applied (gate,outcome)->decision pairs, with the top gates dominated by the two families §3.2 proved — `*_not_found :: taken` and the `SYM_NOTE_TYPE_PROFILE == i` dispatch compares. |
| **F7** | `tree_missing` on 109 401 dumps: **< 13** (the v3.1 drive is aimed exactly at those thirteen). Foreclosure does not touch this number — a satisfiable never-observed side is still a refusal — and it is reported to show the claim is still conditional. |
| **F8** | Reachability: **yes by driving**, with the widest set's demanded count in the hundreds rather than 32 768, so the coupon-collector bound falls from ~360 000 runs to **< 100 000 runs (< 2 h at the measured ~18 runs/s)** — with the caveat that the corpus must actually vary the dimensions (campaign §4), which is a seeder question, not a demand question. |

Also pre-registered, as the honest failure mode: **if foreclosure prunes a
demand that a run later shows to be evaluable, the semantics is WRONG and I
have to say so.** The design makes that a refutation rather than a silent
error — a run that walks what a foreclosure forbids REMOVES it and ADDS the
demand back. The one non-monotonicity I already know about is stated in §2.

---

## §1. The formulation, and its invariants

### 1.1 Foreclosure, inferred from the corpus

> Decision `g` with outcome `o` **FORECLOSES** decision `d` iff
> **(a)** some run evaluated `g` and `d` together, and
> **(b)** every run in which `g` took `o` left `d` unevaluated.

(a) is the same existential §16 builds the demand universe from; (b) is a
universal over the corpus. **Nothing is declared.** There is no new assumption
class, no `AssumptionSet` entry, no `coverage_assumptions.py` change on any
endpoint, and no way for a batch to assert a foreclosure that its runs do not
show. It is computed in `infer_foreclosures()` in one pass over the runs'
outcome profiles, with bitmasks:

```
coeval[g]    = OR of the evaluation masks of the runs that evaluated g
union[g, o]  = OR of the evaluation masks of the runs in which g took o
forecl[g, o] = coeval[g] & ~union[g, o]
```

A property worth noticing because it is the rule's own evidence floor:
**(a) + (b) force `g` to have been observed BOTH ways** — the co-evaluating run
of (a) necessarily took the other arm — so a foreclosure is never read off a
decision the corpus has driven one way only.

### 1.2 Demand: the leaves of the pruned tree

For a demand set `S` the demanded objects are the LEAVES of the decision tree
over `S`, walked in an order that puts a gate before what it forecloses: at each
member, if the cube built so far has already foreclosed it, it is **not part of
that cube** and the cube ranges over the rest; otherwise it is assigned both
ways and the walk recurses. A leaf is demanded iff it is Z3-satisfiable.

Equivalently, and this is the form the invariants are written against: a cube is
demanded iff **no member is assigned while foreclosed by another assigned
member, and every unassigned member is foreclosed by an assigned one.**

The demand is strictly nested — this is what makes Rule T easy (§4):

    foreclosure-aware  ⊆  set-level (§16)  ⊆  complete-graph (2026-08-18)

With no foreclosure inferred every leaf assigns all of `S` and the rule IS the
set-level rule, byte for byte.

The blocking-clause loop and the "a run observed both ways omits the expr from
its clause" trick both survive intact — that was the design constraint on the
formulation, and choosing an ORDERED tree (rather than a fixpoint over an
unordered mask) is what keeps them working: the skip decision depends only on
the prefix, so leaves are well defined, pairwise incompatible, and one blocking
clause per leaf terminates the loop.

### 1.3 The invariants (each pinned by a test)

1. **Coverage is still an observation.** A leaf `(T, α)` is covered iff some run
   evaluated every member of `T` with those outcomes. It need NOT have evaluated
   the rest of `S`: by (b) it provably did not.
2. **A blocking clause is emitted only by a run that walked a leaf exactly.** A
   run whose evaluated members `C = S ∩ eval(run)` is a proper subset of `S`
   blocks only if every member of `S \ C` is foreclosed by `C`'s own outcomes (a
   CLOSED prefix). Otherwise it contributes nothing. `C == S` is always closed —
   (b) means an assigned member can never foreclose another member the same run
   evaluated. **An unexplained partial walk blocks NOTHING**, and that is the
   conservative direction: an unproven cover is never counted.
3. **The "observed both ways" omission still works.** A recurrent expression a
   run took both ways is omitted from its clause, blocking the whole family; for
   a GATE observed both ways the INTERSECTION of its two foreclosure sets is
   used, so the omission is taken only where the family is closed either way. A
   partial run whose clause would be EMPTY is skipped rather than allowed to
   block the space.
4. **Foreclosure never excuses a branch.** `tree_missing` is computed over the
   expressions, untouched: a satisfiable, never-observed outcome is still a
   refusal, whatever forecloses what.
5. **Backward edges are not applied.** If the corpus makes `g=o` foreclose a `d`
   that PRECEDES `g` in the set's order and no acyclic order exists (a
   correlation rather than a gating), the edge is dropped and the product stays
   demanded. Counted in `CoverageResult.foreclosures_ignored`, never silent.

### 1.4 Minimum evidence, and what it is conditional on

**How many runs with `g=o` are needed before "never evaluated" is evidence
rather than absence? ONE — and only because of the tree-completeness
precondition.** Tree completeness already guarantees every satisfiable branch
outcome has been explored, so "no `g=o` run reaches `d`" cannot be explained by
`g=o` being undriven. Off that precondition a single run is not evidence at all.

So foreclosures are reported **exactly as conditional as the combination claim
already is**: `foreclosures_provisional` is True whenever `tree_missing` is
non-empty, `summary()` prints `PROVISIONAL`, and the combination claim is
refused. `complete` is unchanged in its dependence on `tree_complete`.

The honest edge, written into DISCIPLINE §16b as well: tree completeness is a
per-DECISION claim, and the full soundness argument is §16's FIXED POINT (tree
claim AND combination claim together). What is sound is the TRUE verdict — when
the checker says `complete`, the corpus satisfies both claims and the demand
universe it used is the right one. At any intermediate state a foreclosure can
in principle hide a gap that more driving would expose, exactly as §16's "never
seen together" can. **The missing list is a LOWER bound on the remaining work;
only the completeness verdict is a claim.**

### 1.5 Mutability — and the one non-monotonicity

A new run that evaluates `d` under `g=o` **REMOVES** the foreclosure and **ADDS**
demand. (b) is a universal, so it can only ever be refuted by a run that walks
what it forbids — the opposite direction from set growth, which adds demand by
widening the sets. Both push the same way, so demand is monotone in the corpus,
**with one exception, which is real**: if `g` had been driven only as `not o`, a
run that first takes `g=o` can CREATE a foreclosure — (a) already held — and so
RETRACT demand. That can only happen while `g :: o` stood in `tree_missing`,
i.e. while the claim was already refused. At the fixed point the demand only
grows. Test: `test_the_one_non_monotonicity_is_confined_to_an_incomplete_tree`.

### 1.6 What did NOT change

* `IndependenceAssumption` still PROJECTS a set into the maximal cliques of the
  induced graph; the projection runs FIRST and foreclosure applies inside each
  projected set.
* `UntrackedPathAssumption` still removes the expression before the sets are
  formed — so an untracked expression can neither foreclose nor be foreclosed,
  and §16's blind-spot warning gains one more consequence.
* `OneSideUntrackedPathAssumption` still pins a side inside every set.
* The interfaces `coverage_report.py` calls are unchanged. `CoverageResult`
  gained four fields with defaults (`foreclosures`, `foreclosure_gates`,
  `foreclosures_ignored`, `foreclosures_provisional`); nothing was removed or
  renamed.

**One reporting caveat, stated because a number changed meaning.** Under §16b a
foreclosure-truncated leaf (the gate arm alone, say) can be a cube of SEVERAL
demand sets at once, so the same witness is legitimately missing in more than
one set. The engine blocks and counts it in every set but prints it once, so
`len(result.missing)` is **no longer exactly "sets with a gap"** even at MMC=1.
Quote the per-set census, as the standing correction already says. (Before this
was noticed, the cross-set repeat was being counted as `solver_lost` — a false
solver anomaly. Fixed; on the 400-dump probe it was 98 of 395.)

---

## §2. Tests

`src/test_coevaluation.py` gains **8** tests (11 -> 19). All of them build runs
directly from the engine dataclasses so a test can say exactly which decisions a
path evaluated — the thing the rule is about.

| test | what it pins |
|---|---|
| `test_foreclosure_drops_the_gate_x_gated_product` | the headline: `{g,d}` with a gate whose `taken` arm ends the run demands **3** leaves — `(g=T)`, `(g=F,d=T)`, `(g=F,d=F)` — not 4; dropping any one run makes it incomplete; a dropped gated leaf comes back as a 2-cube |
| `test_set_level_rule_would_have_demanded_four` | the nesting claim, checked rather than asserted |
| `test_a_new_run_removes_the_foreclosure_and_adds_demand` | MUTABILITY: one run evaluating `d` under `g=True` takes `foreclosures` 1 -> 0, `complete` True -> False, and the 4th cube is demanded |
| `test_transitive_foreclosure` | `g` forecloses `d`, `d` forecloses `e` (nested early return): **4** leaves, not 8 |
| `test_transitive_gate_that_does_not_foreclose_the_grandchild` | transitivity is INFERRED per pair, never DERIVED: if `g=True` runs do reach `e`, `e` stays in the cube where `d` is dropped (5 leaves) |
| `test_foreclosure_is_conditional_on_tree_completeness` | with `tree_missing` non-empty the combination claim is refused as before AND `summary()` names the foreclosures `PROVISIONAL` |
| `test_the_one_non_monotonicity_is_confined_to_an_incomplete_tree` | the honest case of §1.5, with its boundary |
| `test_partial_run_blocks_only_a_closed_prefix` | invariant 2 — a partial walk nothing forecloses blocks nothing |

Declared independence still projects, untracked still leaves the universe before
the sets are formed, the one-side pin still narrows inside the set, the
projection cap still flags `truncated`: those four pre-existing tests are
unchanged and pass.

### 2.1 Suites

```
test_symbolic.py 36   test_interceptor.py 7   test_path_explosion.py 5
test_assumptions.py 15   test_symbolic_func.py 11        = the 74 pre-existing
test_query_ops.py 27     test_coevaluation.py 19 (11 + 8)
```

All pass.

### 2.2 Existing tests whose EXPECTED SEMANTICS changed — 4, all consciously

Each is annotated in place with a `SEMANTICS CHANGED 2026-09-10 (§16b)` comment
saying what the old rule demanded and why the new answer is the right one.

1. **`test_symbolic.py::test_coverage_partial_tree`** — `not complete`, 2 missing
   -> **complete, 0 missing**. This test IS the fetch-then-404 corner: run3
   terminates after `a>0` false. Under §16 the two `(a=F, b=…)` combinations
   were demanded and an `IndependenceAssumption` was the only resolution; under
   §16b the corpus itself shows `(a, False)` forecloses `b` and nothing is
   declared. The test now also checks that a run walking `b` under `a=False`
   REFUTES the foreclosure and brings the demand back, and that the old
   independence declaration still resolves that corpus.
2. **`test_path_explosion.py::test_range_chain_6_levels`** — 6 missing -> **4**.
   Six monotone thresholds on one variable admit exactly 7 satisfiable combos.
   The old rule gave the early-stopping runs (`x=5`, `x=25`) NO credit because
   they had not evaluated all six expressions. The chain IS a chain — every run
   with `x>10` false stops there — so those two runs now cover the leaf they
   walked, and 3 of the 7 are covered. The test additionally asserts the witness
   WIDTHS `[2, 4, 6, 6]`: two of the four missing leaves are short cubes, which
   is also a better seed for the DSE than a padded 6-wide one.
3. **`test_coevaluation.py::test_a_run_that_coevaluates_them_creates_the_demand`**
   — the `{a,b}` set demands 3 -> **1**. In that corpus the only `a=False` run
   does not evaluate `b`, so `(a,False)` forecloses `b`.
4. **`test_coevaluation.py::test_a_superset_evaluation_set_subsumes_without_weakening`**
   — 7 missing -> **1**. Every `a=False` and every `b=False` run leaves `c`
   unevaluated. Note the conservative half of invariant 2 shows up here: the run
   that walked `a=T,b=T` WITHOUT `c` is not a closed prefix (nothing forecloses
   `c` there) and blocks nothing, so `(a=T,b=T,c=F)` is still demanded.

No test's expectation was weakened to make the new engine pass; in every case
the new number is the one the corpus supports, and in cases 1 and 2 it is
strictly more informative than the old one.

---

## §3. Priced on notifications_index

### 3.0 How it was run

```
snapshot   _snapshot.txt, 109 401 dumps  (find -maxdepth 1 -name 'dump_*.json' | sort)
unit       systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=10G
env        JAVA_TOOL_OPTIONS unset
tool       _exact_enum.py (the batch's exact enumerator, ported to leaves)
loader     DUMP_LIST support added — a v3.1 drive owned by another agent is
           adding dumps to this directory, so the glob is NOT reproducible
assumptions  the batch's own coverage_assumptions.py, UNCHANGED, nothing
           declared or withdrawn for this measurement
both arms  FORECLOSURE=1,0 in ONE process — one load, one universe, two
           censuses, so the delta is exact and not a comparison of two runs
cross-check  --verify 6, 6/6 OK in BOTH arms: each verified set's leaves are
           re-derived by brute force over its 2^w total assignments, deduped,
           and all-SAT'd directly against the factorised count
bounded_cliques = 0 in both arms — every figure exact, not a lower bound
```

Universe build 427 s (the load dominates), census 83 s with foreclosure and
29 s without. `[assumptions] ... exprs=411 co-evaluated-pairs=28462`.

### 3.1 The delta — identical snapshot, identical assumptions

| | set-level (§16) | **foreclosure-aware (§16b)** |
|---|---|---|
| nodes / active / untracked | 411 / 402 / 9 | **411 / 402 / 9** |
| demand sets | 1 010 | **1 010** |
| width histogram | 5x366, 6x276, 4x129, 7x104 … | **unchanged** |
| **demanded assignments** | **603 032** | **62 324  (−89.66 %)** |
| **covered** | **16 781** | **25 625  (+52.7 %)** |
| remaining | 586 251 | **36 699  (−93.7 %)** |
| **uncovered** | **97.22 %** | **58.88 %** |
| sets with a gap / fully covered | 982 / 28 | **894 / 116** |
| wide sets (width >= 13) | 43 | **43** |
| wide sets' demand / remaining | 477 696 / 477 086 | **16 832 / 11 675  (−97.6 %)** |
| foreclosures applied | 0 | **3 507** pairs, 4 524 leaf groups |
| `tree_missing` | 10 | **10** |
| census wall | 29 s | 83 s |

The four width-20 sets, which are the whole story of this endpoint:

| set | set-level demanded | **§16b demanded** | covered | leaf groups | foreclosures |
|---|---|---|---|---|---|
| #0 | 36 864 | **488** | **122** | 63 | 75 |
| #1 | 36 864 | **356** | **138** | 62 | 84 |
| #2 | 36 864 | **356** | **188** | 62 | 84 |
| #3 | 36 864 | **356** | **193** | 62 | 84 |
| four | 147 456 | **1 556** | **641 (41 %)** | | |

Under the set-level rule those four sets had 14–16 of 36 864 covered each. They
now have 122–193 of 356–488 — the same corpus, the same runs, the same
assumptions; only the question changed.

### 3.2 Pre-registered vs measured

| # | prediction | measured | verdict |
|---|---|---|---|
| F1 | satisfiable cut by >= 85 % | **−89.66 %** (603 032 -> 62 324) | **CONFIRMED** — and it lands within 0.1 pt of the 89.6 % the W-C/W-F suspension bought, without narrowing a gate-refuted class |
| F2 | the four width-20 sets fall to <= 100 each | **488 / 356 / 356 / 356** | **REFUTED.** §3.3 of the campaign estimated 32/16/16/16 "structurally feasible" by treating every PIN in those sets as a foreclosure. Foreclosure only prunes what the corpus PROVES; the free dimensions inside those sets survive, and they are 3–5 bits wide. The estimate was a floor, not the answer, and I predicted the floor. |
| F3 | wide sets do NOT go to 0; their mass falls >= 95 % | **43 -> 43**, mass **−97.6 %** | **CONFIRMED**, and it is the structural difference from §5.1: independence FRAGMENTS a set (34 -> 0 wide sets), foreclosure PRUNES ASSIGNMENTS inside it. The width histogram is byte-identical between the two arms. |
| F4 | covered goes UP by >= 50 % | **+52.7 %** (16 781 -> 25 625) | **CONFIRMED**, and it is invariant 1 paying. Note the two counts are over different objects — §16 counts full assignments over the set, §16b counts leaves — so the honest reading is not "8 844 newly covered assignments" but: even though the objects are strictly fewer and each one smaller, MORE of them are covered, because a run that stopped early is now credited with the leaf it walked instead of being refused for not having evaluated the whole set. |
| F5 | uncovered lands in 60–95 % | **58.88 %** | **REFUTED**, narrowly and in the good direction. |
| F6 | 1 000–10 000 applied foreclosure pairs, top gates the two proven families | **3 507 applied** (12 001 inferred over the whole active universe, over 380 gates) | **CONFIRMED** |
| F7 | `tree_missing` < 13 | **10** | **CONFIRMED** — and this is the v3.1 drive's doing, not foreclosure's: three of the thirteen have been driven since the morning census. |
| F8 | reachable; binding coupon-collector < 100 000 runs / < 2 h | binding set **676 demanded -> 4 796 runs, 0.07 h** at 18 runs/s | **CONFIRMED on the arithmetic**, with a caveat that is now the whole story — §3.4 |

### 3.3 The foreclosures, and the top gates

**3 507 (gate, outcome) -> decision pairs applied inside the demand sets**;
12 001 inferred over the whole active universe, across 380 distinct gates. The
top gates are exactly the two families the campaign's ground-truth differential
proved, plus one the differential had not looked at:

```
  384  devise_user_first_1_stale_language == True            :: taken
  149  SYM_NOTE_TYPE_PROFILE == 7                            :: taken
  142  to_ary_notifications_10254800_row_target_not_found    :: taken
  135  devise_user_first_1_person_not_found                  :: taken
  125  SYM_NOTE_TYPE_PROFILE == 1                            :: taken
  125  to_ary_notifications_c7e6a7ca_row_target_not_found    :: taken
  120  devise_user_first_1_person_profile_not_found          :: taken
  113  SYM_NOTE_TYPE_PROFILE == 3                            :: taken
  112  to_ary_notifications_3aa8587a_row_target_not_found    :: taken
  111  to_ary_notifications_cf379872_row_target_not_found    :: taken
```

* the `*_not_found :: taken` family — the campaign measured
  `row_target_not_found == true` in 5 687 runs with a mean of **0.00** gated
  decisions per run, against 8.18 when false. The engine re-derives that from a
  corpus 60 % larger without being told, on all four alias-keyed instances of
  the gate at once.
* the `SYM_NOTE_TYPE_PROFILE == i :: taken` dispatch family — each set holds
  type-specific downstream decisions, so only one type value can walk it.
* `devise_user_first_1_stale_language :: taken` is the biggest single gate at
  384 and was NOT in the campaign's list: taking it short-circuits a whole
  language-dependent chain. It is exactly the kind of thing this rule is for —
  nobody had to notice it.

`foreclosures_ignored` (backward/cyclic edges NOT applied — invariant 5) is
reported by the engine on every pass; on the 400-dump engine probe it was 514
against 2 807 applied. Those products stay demanded.

### 3.4 Is notifications_index now reachable by driving?

**The demand is: yes, comfortably. The driving is: still not, and for a reason
that has nothing to do with the demand.**

The arithmetic, on the measured census:

| | set-level (§16) | **§16b** |
|---|---|---|
| total remaining | 586 251 | **36 699** |
| largest single-set gap | 36 850 | **551** |
| binding set (max `n·H(n)`) | width 20, 36 864 demanded | **width 17, 676 demanded** |
| coupon-collector bound | **408 904 runs = 6.3 h** @ 18 runs/s | **4 796 runs = 0.07 h** @ 18 runs/s |

One run assigns every decision it evaluates at once, so a varied run covers an
assignment in every set it walks simultaneously and the corpus converges at the
rate of its worst set. That worst set now demands **676** assignments, not
32 768. At the measured aggregate rate of ~18 runs/s (campaign §3.5, 3 JRuby
slots, 15 220 dumps in ~14 min) the coupon-collector bound is **under five
thousand runs, minutes rather than hours**.

**The caveats, in the order they bind.**

1. **`tree_complete` is FALSE — 10 branch outcomes.** No combination coverage
   makes `complete` true while any of them stands, and while they stand the
   3 507 foreclosures are PROVISIONAL, so the 62 324 is itself provisional. This
   is the cheapest and the most binding work on the endpoint, it is unchanged by
   this semantics, and the v3.1 drive is aimed at it (13 -> 10 already).
2. **The coupon-collector model assumes each run draws a fresh assignment in
   each set, and the seeder does not.** Campaign §4: 24 of 146 seed dimensions
   are varied, and every one of the 86 boolean dispatch dimensions stays at its
   default. The demand is no longer the binding constraint — **the seeder is**.
   That is a different, cheaper, already-diagnosed problem with a tool already
   written (`_diverse_seeds3.py`).
3. The residual is genuinely a driving backlog now: 894 of 1 010 sets have a
   gap, but the median gap is **15 assignments** and the largest is 551.

**So the campaign's §5.2 verdict is superseded.** It said `complete: true` on
this endpoint was "blocked on a modelling decision, not on driving", because
89.6 % of the target did not exist. That 89.6 % is now gone from the target,
measured on a corpus 60 % larger, **without narrowing a gate-refuted class and
without a new assumption kind** — option 1 of the three the campaign put to the
owner, in the form that requires no declaration at all. What is left is a
driving problem of a size the rig can actually reach.

---

## §4. Rule T — what `complete: true` means now, and the closed endpoints

### 4.1 The argument

Demands are strictly nested:

    foreclosure-aware (§16b)  ⊆  set-level (§16)  ⊆  complete-graph (2026-08-18)

so **old-complete implies new-complete**, twice over. §16a proved that on an
old-complete corpus the 2026-08-18 and §16 demand universes COINCIDE; §16b then
only ever REMOVES assignments from a set's demand, and removing assignments from
a set every one of whose satisfiable assignments was observed leaves a set every
one of whose satisfiable assignments was observed. The blocking side needs one
more line and it is invariant 2: the extra clauses §16b admits come from runs
that walked a CLOSED prefix, which on an old-complete corpus can only re-block
what a whole-set run already blocked. **Rule T is NOT triggered.**

### 4.2 Verified, not just argued — read-only

Each endpoint re-checked with its **own, unchanged** `coverage_report.py` load
path and `coverage_assumptions.py`, under the new engine. The checker script
writes nothing: no `coverage_summary.json` was touched, no file in any endpoint
directory was created or modified.

| endpoint | nodes | demand sets | missing | `complete` | `tree_complete` | foreclosures applied / ignored |
|---|---|---|---|---|---|---|
| **comments_index** | 84 | 85 | 0 | **True** | True | 0 / 0 |
| **conversations_index** | 105 | 83 | 0 | **True** | True | 0 / 0 |
| **people_show** | 97 | 239 | 0 | **True** | True | **16 172 / 3 628** |

Every row is identical to the §16a re-check of this morning (84/85/0,
105/83/0, 97/239/0). `solver_lost = 0`, `truncated = False` in all three.

**people_show is the interesting row and it is the argument made empirically.**
It carries 16 172 applied foreclosures — the rule bites hard there — and it is
still `complete`, because pruning assignments out of a fully covered set leaves
it fully covered. comments_index and conversations_index infer ZERO
foreclosures: on those corpora every run in a demand set evaluates the whole
set, which is what a corpus driven to completeness looks like.

### 4.3 What `complete: true` asserts from now on

> Every Z3-satisfiable outcome assignment over every maximal observed
> evaluation set, projected by declared independence, **in which no decision is
> assigned while the corpus shows that assignment removes it from the path**,
> has been observed in some single run's executed path — AND every tracked
> decision has been observed with every satisfiable outcome (`tree_complete`).

Narrower than §16, which was narrower than 2026-08-18. Each narrowing removed an
artefact of a representation rather than a fact about the program: pairs that
never share a path, then sets that no run walks, now assignments that no run can
make. **Do not quote any of the three as a coverage improvement** — the target
moved, the driving did not.

---

## §5. Soundness — the cases I found, stated rather than buried

1. **The non-monotonicity (§1.5).** Real, confined to a corpus whose tree layer
   is incomplete, tested, and the reason `foreclosures_provisional` exists.
2. **The fixed point (§1.4).** Tree completeness is a per-DECISION claim. The
   full soundness argument is §16's fixed point — tree claim AND combination
   claim together — so what is sound is the TRUE verdict. **At any intermediate
   state the missing list is a LOWER bound on the remaining work**, and a
   foreclosure can hide a gap that more driving would expose, exactly as §16's
   "never seen together" can. This is inherited from §16, not introduced here,
   but §16b makes it worth writing down because it is now the mechanism that
   turns an unreachable target into a reachable one.
3. **Backward and cyclic edges are NOT applied** (invariant 5), so a corpus
   CORRELATION that is not a gating leaves its product demanded. Conservative,
   counted in `foreclosures_ignored`, never silent.
4. **An unexplained partial walk blocks nothing** (invariant 2). A run that
   walked part of a set for a reason foreclosure does not explain is not counted
   as cover. Conservative; it is why
   `test_a_superset_evaluation_set_subsumes_without_weakening` still reports one
   missing assignment.
5. **Subset dedup** (`maximal_sets`) stays sound: a leaf of a dropped subset
   `S'` is covered by a leaf of its superset `S`, because a member foreclosed
   inside `S` by a gate outside `S'` is assigned on the gate's other arm, which
   exists by (a). The corner where an outcome is satisfiable ONLY jointly with
   the arm that forecloses it is caught by the tree layer — that outcome is then
   never observed and `tree_missing` names it.
6. **Untracked gates.** An `UntrackedPathAssumption` removes a decision from the
   universe, so it can neither foreclose nor be foreclosed. §16 already warned
   that untracking a GATE can hide a combination; under §16b it can also leave
   an infeasible product demanded (the mirror image, and the harmless
   direction). Unchanged advice: untrack a gate only when its arms are genuinely
   interchangeable.

I did **not** find a case where the rule drops a demand a run can satisfy while
the tree layer is complete. The design makes that a refutation rather than a
silent error: a run that walks what a foreclosure forbids removes it and adds
the demand back, on the next pass, with no declaration to withdraw.

---

## §6. Artefacts

| path | what |
|---|---|
| `src/concolic_engine/coverage.py` | the rule: `infer_foreclosures()`, `restrict_foreclosures()`, `_foreclosure_order()`, the closed-prefix blocking test, the pruned-tree walk in `_next_untried_combo`, 4 new `CoverageResult` fields, the docstring's §16b section and its invariants |
| `src/test_coevaluation.py` | 8 new tests (11 -> 19) |
| `src/test_symbolic.py`, `src/test_path_explosion.py` | 2 tests whose expected semantics changed, annotated in place |
| `reports/diaspora/docs/DISCIPLINE.md` §16b | the decision record |
| `notifications_index/_exact_enum.py` | ported to leaves: `leaves()`, per-leaf-group covered counting, `DUMP_LIST`, `FORECLOSURE=1,0` for the delta in one load, foreclosure-aware `--verify`, `tree_missing` computed in the same pass |
| `notifications_index/_snapshot.txt` | the 109 401-dump snapshot every number here is against |
| `notifications_index/_foreclosure_census_20260910.{json,log}` | both arms' per-set census and the pass log |
| `_STATE_HANDOFF.md` | updated with the §16b note and a warning not to compare its §16 table with a §16b number |

Reproduce:

```
cd reports/diaspora/results3/notifications_index
unset JAVA_TOOL_OPTIONS
DUMP_LIST=$PWD/_snapshot.txt FORECLOSURE=1,0 \
  systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=10G \
  python3 _exact_enum.py --verify 6 --json-out /tmp/fcens.json
```

Nothing was declared, withdrawn, or edited in any endpoint's
`coverage_assumptions.py`. No `coverage_summary.json` was written. No driving,
no JRuby; the drive owned by another agent was left alone.
