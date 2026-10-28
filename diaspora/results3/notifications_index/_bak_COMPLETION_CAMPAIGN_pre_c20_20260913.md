# notifications_index — completion campaign under co-evaluation semantics
**2026-09-10.** Goal: `complete: true` under DISCIPLINE §16. Owner approved a
large run count. Updated as the campaign runs, so it survives a context loss.

Semantics: `_COEVAL_SEMANTICS_20260910.md`. Handoff: `../_STATE_HANDOFF.md`.

---

## §1. STEP 0 — the two Class-B defects. CAUSE FOUND, FIXED.

The 2026-09-10 census reported **2 width-7 demand sets with `covered == 0`
despite having observed cubes** — the corpus recorded an outcome combination
the batch's declared Z3 model calls impossible. Two independent declaration
bugs were found. Both are fixed in `coverage_report.py`; neither touches
`src/`, the app, `targets.rb` or any dump.

### §1.1 The cause of the two zero-covered sets: a SELF-COMPARE that is not a tautology

**Not** `apply_len_bounds`'s `SYM_LEN_*` domains — the brief's first suspect.
That hypothesis was tested first and **refuted**: a scan of every `len(...)`
symbolic var over a 1 845-dump stride sample found **0 values outside the
declared `{0..1}` / `{0..3}` / `{0..4}` domains**. The runtime clamps
(`targets.rb`: `len_i = 3 if len_i > 1`, `an = 4 if an > 1`), so the diverse
seeds' `{0,1,2,4}` never escapes the bound. The bound is not stale.

The actual cause, localised to the exact expression:

```
(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_id
 == SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_id)
```

An exhaustive raw-text scan of **all 68 231 dumps** finds this recorded
**1 052 times taken and 963 times NOT taken**. Every Z3 model makes `V == V`
true, so all 963 not-taken observations are UNSAT under the declared model,
and any demand set whose *only* observed cubes pin it False reports
`covered = 0`. In a 400-dump smoke sample **13 of 13** zero-covered sets
contained exactly this expression; after the fix, **0**.

Ground truth (`app/helpers/gon_helper.rb:6`, function `block in
gon_load_contact`, which is where the PC is stamped):

```ruby
if Gon.preloads[:contacts].none? {|stored_contact| stored_contact[:person][:id] == contact.person_id }
```

It compares a **previously stored** contact's person id against the **current**
contact's. Two different rows of the same `Contact.find_by` family — and
`call_interceptor.rb:142-144` names a result by *when* it was called relative
to its prefix, so both operands are minted with the one name `find_by_1_person_id`.
This is the known `DecisionAlias` root cause (STATE_HANDOFF item 6) showing up
as a *modelling* defect rather than a naming one. The dump has already lost the
distinction, so it cannot be recovered by keying on the statement the way the
P0 alias canonicalization does for list reads.

**Fix** (`coverage_report.split_self_compare`, called from
`canonicalize_ordinals`, so every tool that loads through `coverage_report`
— the pass, `_exact_enum.py`, `_decisive.py` — sees one universe): rewrite
`(V == V)` to `(V == V__prior)` and declare `V__prior` as a free SymbolicVar of
the same sort. The expression then models what the app actually decides
("is this contact already stored?") and both observed outcomes are satisfiable.
The **right** operand is renamed deliberately: `coverage_assumptions._leftvar`
and `_rep_key` key on the LEFT variable, and `_is_principal` still sees
`person_id` in the renamed right operand, so every declared tier keys exactly
as before — verified by the identical tier counts in the pass.

`(V != V)` also occurs (1 168 times, on
`to_ary_..._row_target_status_message_guid`) but is recorded **not_taken every
single time** — precisely what the tautology model predicts. There is no
contradiction to repair there, and repairing it would invent an unobserved
True side and a tree-completeness demand the corpus has never contradicted.
It is left alone and named here as a watched item: a single
`(V != V) :: taken` observation makes it the same defect.

### §1.2 A second, independent Class-B defect: STI dispatch domains

Found while testing the `SYM_LEN_*` hypothesis. `apply_len_bounds` declared

```python
BOUNDS = {"SYM_NOTE_TYPE_PROFILE": (0, 7), "SYM_POST_STI": (0, 1)}
```

on the explicit claim (in its own comment) that an out-of-range index "would
make the all-compares-False combination *spuriously* satisfiable". **That claim
is false.** Both mints carry an explicit out-of-range default in `targets.rb`
(`profile = NOTE_TYPE_PROFILES.first  # defensive default (idx out of range)`,
line ~876; `pchosen = 0`, line ~1477), the *runtime* puts no bound on the seed,
and the DSE solver — negating `idx == 7` / `pidx == 1` — duly produced 8 and 2
and the runner executed them. Full-corpus counts:

| var | declared | observed values (68 231 dumps) |
|---|---|---|
| `SYM_NOTE_TYPE_PROFILE` | `0..7` | 0..7 **and 8 in 61 dumps** |
| `SYM_POST_STI` | `0..1` | 0,1 **and 2 in 35 dumps** |

Verified on the dumps themselves: a `SYM_NOTE_TYPE_PROFILE == 8` run records
all eight `== i` compares **not taken**, and a `SYM_POST_STI == 2` run records
both **not taken** — cubes that are UNSAT under the old bounds.

**Fix:** `BOUNDS = {"SYM_NOTE_TYPE_PROFILE": (0, 8), "SYM_POST_STI": (0, 2)}`.
The new high bound is **one representative of the out-of-range class**: every
value above it (and every negative) drives the same defensive default and
records the identical all-False cube, so `{0..8}` / `{0..2}` is a complete set
of representatives for the observable outcome space and `low = 0` excludes no
outcome. This defect is real but was **not** what produced the two
zero-covered sets (those sets' observed cubes are UNSAT for the §1.1 reason);
it is reported because a declared domain that excludes something the runtime
produced makes every demand computed under it suspect.

### §1.3 Confirmation status

* 400-dump smoke, before fixes: **13 zero-covered sets**, all 13 containing the
  self-compare. After fixes: **0**.
* Full-corpus confirmation: the Step-1 pass below reports `zero_covered`; the
  campaign does not claim completeness until it reads 0 on 68 231+ dumps.

---

## §2. STEP 1 — PRE-REGISTRATION (written 2026-09-10, before the pass ran)

### §2.1 A correction to the brief's experiment, made before running it

The brief names `_diverseR.json` (6 000 seeds over `{0,1,2,4}`) as the decisive
experiment. Two measured facts change what should actually be run:

1. **`_diverseR.json` is the DEFECTIVE v1 file.** Measured: of its 6 000 seeds,
   **3 394 carry ZERO length keys** and the rest carry 1–4 — v1 randomised only
   the `len(...)` keys already present in a template dump. `_diverse_seeds2.py`'s
   own docstring documents this and supersedes it; `_diverseR2.json` assigns
   **all 22 length keys in every one of its 6 000 seeds**. Running v1 could
   only produce a null result that fails to distinguish "the dimensions are
   pinned" from "the seeds never touched them", which would waste the decision.
2. **The v2 experiment has ALREADY BEEN RUN, and its runs are in the corpus.**
   `_diverse_drive_DV2028.log` (2026-09-09) drove `_diverseR2.json`; the corpus
   went 51 662 → 68 231 dumps. Counted by label suffix, **16 569 of the 68 231
   dumps are diverse-v2 (`_DV2028*`) and a further 4 000 are diverse-v1
   (`_DIV1`) — 20 569 diverse runs, 30 % of the corpus.** So the 16/15/13/12
   distinct-cube figures on the four width-20 sets were measured on a corpus
   that *already contains* a full diverse drive.

Therefore the decisive experiment is run as a **differential on the existing
corpus** (`_decisive.py`, one load, no driving), splitting every demand set's
observed cubes and covered count into the **DIV** arm (20 569 diverse runs) and
the **PLAIN** arm (47 662 others), *plus* a fresh `_diverseR2.json` drive run in
parallel so a second, independent point exists either way. This is strictly
more informative than the brief's version and answers the same question.

### §2.2 The pre-registered criterion

Baseline (`_COEVAL_SEMANTICS` §6.2/§7.2, 68 231 dumps, pre-fix declarations):
997 demand sets, 491 264 satisfiable, 13 990 covered (**97.15 % uncovered**);
14 171 distinct cubes in total, median 14/set; the four width-20 sets got
**16, 15, 13, 12**.

**PASS — the seeded dimensions are FREE, proceed to Step 2.** Both must hold on
the four width-20 sets:
* `cubes_div >= 3 x cubes_plain` (the DIV arm has 0.43x the runs of the PLAIN
  arm, so this is a per-run yield of >= 7x), and
* `cubes_div >= 40` on each of the four.

**FAIL — the app's control flow PINS those sets; STOP and report.** Either:
* `cubes_div <= cubes_plain` on the width-20 sets (20 569 diverse runs did not
  beat 47 662 ordinary runs at producing distinct cubes), or
* `cubes_div < 20` on each of the four.

On FAIL the report must NAME the pins: `_decisive.py` prints, per wide set, the
member decisions never observed both ways inside that set (`pinned_all` /
`pinned_div`). No campaign is scaled against a target that cannot move.

**MIDDLE (neither) —** report the numbers, take the fresh drive's measured
delta as the marginal rate, project, and decide with the numbers stated.

**Secondary, on the fresh drive** (independent of the differential): after
>= 40 000 new diverse runs, total `covered` rises by **>= 20 000** assignments
= PASS; **< 500** = FAIL.

### §2.3 Throughput — to be measured, not assumed

The semantics report's "~32 runs/s" is unsourced. `_diverse_drive_DV2028.log`
measures **6 000 runs in 10 m 34 s on one slot = 9.5 runs/s/slot**, consistent
with the earlier ~620 dumps/min figure. Re-measured on the fresh drive below.

---

## §3. Milestones

*(appended as the campaign runs)*

---

## §3. STEP 1 — THE DECISIVE RESULT. Criterion FAILED. Campaign NOT scaled.

`_decisive.py`, 68 231 dumps, full load through the engine's own path,
`ndxdec1.scope` (`--slice=concolic-cov.slice`, `MemoryMax=10G` verified),
load 289 s, universe 403 s, census 497 s.

### §3.0 Cross-checks first, then the numbers

| | baseline (§6.2) | this pass | |
|---|---|---|---|
| nodes / active / untracked | 411 / 402 / 9 | **411 / 402 / 9** | universe intact |
| evaluation sets -> demand sets | 860 -> 997 | **860 -> 997** | same universe |
| `tree_missing` | 13 | **13** | same |
| **`zero_covered`** | **2** | **0** | **STEP 0 CONFIRMED on the full corpus** |
| satisfiable | 491 264 | **580 096** | +88 832: the §1 fixes ADD real states |
| covered | 13 990 | **14 171** | |
| uncovered | 97.15 % | **97.56 %** | |

The declaration fixes did not perturb the universe — same nodes, same sets,
same tree residue — and they removed both zero-covered sets. `zero_covered = 0`
on 68 231 dumps is Step 0's confirmation.

### §3.1 The pre-registered rows

```
  w      sat     cov cubesALL cubesDIV cubesPLAIN  covDIV covPLAIN  free_all
 20    36864      16       16       15          6      15        6    5 of 20
 20    36864      15       15       15          4      15        4    4 of 20
 20    36864      13       13       13          5      13        5    4 of 20
 20    36864      12       12       12          2      12        2    4 of 20
```
DIV arm 20 569 runs, PLAIN arm 47 662 runs.

**Verdict against §2.2: FAIL.** The FAIL clause `cubes_div < 20 on each of the
four` holds (15, 15, 13, 12). The PASS clause `cubes_div >= 40` fails on all
four. Per the pre-registration the campaign is **not scaled**, and this section
names what pins the sets.

Worth recording because it is real but did not meet the bar: diverse seeding
IS more productive per run — **covered_DIVonly = 11 644 from 20 569 runs
(0.566/run) against covered_PLAINonly = 7 040 from 47 662 (0.148/run), a
3.8x per-run yield** — and `cubes_div > cubes_plain` on every one of the four.
It is simply nowhere near enough, and §3.2 says why.

### §3.2 What pins them — measured, not theorised

The tool prints, per wide set, the member decisions never observed both ways
inside that set. **In all four width-20 sets, EVERY pinned decision belongs to
one of exactly two families**, and there is nothing else in the list:

* **the 8 `SYM_NOTE_TYPE_PROFILE == i` dispatch compares** (all 8 pinned in all
  four sets), and
* **7-8 `*_not_found` gates** (`devise_user_first_1_person`,
  `..._person_profile`, `find_by_1/2/3`, `..._row_recipient`, `..._row_target`).

Neither family is undrivable. **17 of the corpus's 20 `*_not_found` decisions
have been observed BOTH ways corpus-wide** (e.g. `row_target_not_found`
5 627 true / 66 309 false), and `SYM_NOTE_TYPE_PROFILE` takes all nine of its
values across thousands of runs each. They are pinned *inside these sets*, and
the reason is **structural foreclosure**, verified as a ground-truth
differential over all 68 231 dumps:

```
gate row_target_not_found == true :  5 687 runs; mean gated decisions/run = 0.00;
                                     runs with >=1 gated decision = 0 (0.0 %)
gate row_target_not_found == false: 67 045 runs; mean gated decisions/run = 8.18;
                                     runs with >=1 gated decision = 58 713 (87.6 %)
```

When the gate fires, **every decision it gates disappears from the path** — in
0 of 5 687 runs did a single target-chain decision survive. So a run that flips
the gate no longer walks the set; it walks a different, smaller evaluation set.
The same holds for the type dispatch: the sets contain type-specific downstream
decisions, so only one note type can walk each of them, and with 68 231 runs
spread over nine type values the "merely undriven" reading is not credible.

**This is the §6.3(a) caveat of the semantics report, now measured and load
bearing: co-evaluation is a fact about the SET, not a promise that every
assignment OVER the set is reachable.** The rule demands the cross-product of a
gate's outcomes with the decisions that gate enables, and that product does not
exist in the program.

### §3.3 How big the artefact is

For each width-20 set the pins are fully explained by the two proven families,
so the structurally reachable count is exact rather than a bound:
`9 -> 1` type outcome, and `2^k -> 1` per pinned gate.

| set | demanded | structurally feasible | covered | covered / feasible |
|---|---|---|---|---|
| #0 (w20) | 36 864 | **32** | 16 | **50 %** |
| #1 (w20) | 36 864 | **16** | 15 | **94 %** |
| #2 (w20) | 36 864 | **16** | 13 | **81 %** |
| #3 (w20) | 36 864 | **16** | 12 | **75 %** |
| **four sets** | **147 456** | **80** | **56** | **70 %** |

Extending the same estimate (`2^free_all`) to all 41 sets of width >= 13 —
which hold **459 264 of the 580 096 demanded assignments, 79.2 %** — gives
**~4 225 structurally feasible, 0.92 % of what is demanded there**, of which
**519 (12.3 %) are already covered**. For the wide sets other than the four this
is a LOWER bound on feasibility (`free_all` conflates proven foreclosure with
merely-undriven), but for the four width-20 sets, where every pin is accounted
for by the two verified families, it is exact.

### §3.4 What this means for the plan — the 360 000-run estimate is void

The `~360 000 varied runs / ~3 hours` figure prices covering 32 768 assignments
per width-20 set. **About 32 of them exist.** The residual is not a driving
backlog; it is ~99 % a modelling artefact of demanding gate x gated-decision
products. Driving it is not slow, it is impossible, and no seeding strategy
changes that — which is exactly what the pre-registration was for.

The work that actually remains is therefore, in order:

1. **A foreclosure tier for the gate families.** `IndependenceAssumption`
   between a gate and the decisions it gates projects the evaluation set and
   deletes the impossible product. This batch already has that mechanism and
   uses it (`tier1(foreclose) = 959`, `_tier_guid_foreclosed_by_persisted`,
   `_tier1c_empty_list_foreclosure`); it needs extending to `*_not_found` and to
   `SYM_NOTE_TYPE_PROFILE`. Note that TIER 0a (variant) and TIER 0b (type) were
   **deleted on 2026-09-10** as inert on the argument that the engine now makes
   the "never co-occur" case for itself. It does — for sets no run walks. It
   does **not** for impossible assignments inside a set some run does walk, and
   that deletion is why the type dispatch now shows up here.
2. **Drive the genuinely free dimensions**, which the seeder has never touched
   (§4).
3. Then the full engine run and `_c7_audits.sh`.

### §3.5 Throughput, measured

3 JRuby slots, `_diverseR2.json`, tag `DV100530`: **15 220 dumps in ~14 min =
~18 runs/s aggregate**, and the one variant that ran to completion did
6 000 runs in 7 min = **14.3 runs/s/slot**. JIT warm-up costs the first ~2 min.
The report's "~32 runs/s" is the right order for more slots; the "~10/s" figure
was a cold measurement. Disk: the corpus is on `hpool/home`, **176 GB free**,
83 625 dumps = 4.2 GB (~56 KB/dump), so 500 k dumps is ~28 GB. Not a constraint.

---

## §4. The seeder varies 24 of 146 dimensions — and that is why the free decisions are not free either

Census of `concolic_seeds` over this corpus: **146 distinct seed keys — 86
bool, 33 int (22 of them `len(...)`), 25 str.** `_diverse_seeds2.py` assigns the
22 lengths (and re-rolls two STI ints). **Every one of the 86 boolean dispatch
dimensions stays at its default in every "diverse" run** — `_not_found`,
`_persisted`, `_text_has_dlink`, `_text_dlink_is_post`, `_mention_inline_name`,
`_disp_has_dlink`, `_text_nil`, `_target_is_photo`.

That is also exactly where the **13 `tree_missing` branch outcomes** live — all
thirteen are seedable booleans or strings the seeder never sets
(5 x `_text_dlink_is_post :: not_taken`, 2 x `_mention_inline_name ::
not_taken`, 4 x `_not_found`/`_persisted`, `devise_user_first_1_username == ''`,
`Relation_size_2_size > 0 :: not_taken`). Tree completeness is a hard
precondition: `complete` cannot be true while any of them stands.

`_diverse_seeds3.py` (written 2026-09-10) varies the whole universe: booleans
{True,False}; `len(...)` {0,1,2,4}; `SYM_NOTE_TYPE_PROFILE` 0..8 and
`SYM_POST_STI` 0..2 (the out-of-range representative from §1.2); other ints and
strings sampled from the values the corpus has produced, with `''` added at
p = 1/4 for `_first_name` / `_last_name` / `_username` because `== StringVal('')`
is a branch the corpus has never taken. Domains are cached in
`_seed_domains.json` (`--rebuild` to refresh).

### §4.1 PRE-REGISTERED — the v3 experiment (written before it ran)

Budget: 6 000 v3 seeds x 7 variants, ~42 000 runs, ~40 min at the measured rate.

* **PASS** — the boolean dimensions are free: `tree_missing` falls from **13 to
  <= 6**, AND at least two of the four width-20 sets rise above their current
  16 / 15 / 13 / 12 covered.
* **FAIL** — `tree_missing` stays at 13 and no width-20 set moves. Then the
  boolean seeds are not reaching the mint sites and the seeding path itself is
  the defect, not the domain.

This experiment is run regardless of §3's verdict: driving the 13 tree-missing
branches is mandatory for `complete` under DISCIPLINE §16 and is independent of
the combination artefact.

---

## §5. Why the two families are glued — and what the artefact costs, priced

§3.4 said "extend the foreclosure tier". That was wrong, and the reason matters.

**Both declarations already exist, and both are thrown away on purpose.**

* `_tier0c_dispatch_independence` (3 210 declarations) already declares the
  dispatch compares independent of every non-dispatch decision.
* The finder foreclosure tiers already cover `*_not_found`.

`_withdrawn_independence` then discards them for exactly these two classes,
because the **assumption gate refuted them on flip-both evidence**:

* **W-C** (`dispatch x *_not_found`) — 4 FAILs on `SYM_POST_STI == 0/1` x
  `..._mentions_container[_commentable]_author_profile_not_found`: flipping both
  produced `find_target`, `reload` and a `load_intermediate SELECT "people".*
  ... LIMIT 1` — shapes absent from the base and from both singles.
* **W-F** (`*_not_found x *_not_found`) — 3 FAILs; the §7 finder memo makes the
  contact/block finders one fact.

Verified directly: `_withdrawn_independence` returns True for
`(SYM_NOTE_TYPE_PROFILE == 3)` x each of the width-20 sets' `_not_found`
members, and for `row_target_not_found x row_target_statusmessage_not_found`.
**So the width-20 sets are exactly the withdrawn classes' glue**, and that glue
is evidence-backed, not an oversight. `_INDEPENDENCE_PROPOSAL_20260909.md`
already considered narrowing W-C by prefix and **rejected it** ("the principal
finders are not on a dispatched chain, so the refuting mechanism cannot apply —
but that is a narrowing by prefix, which the rule forbids").

### §5.1 The price, measured on an IDENTICAL corpus snapshot

Both runs over the same fixed 572-dump list (`DUMP_LIST`, so the two are
comparable to the dump), same load path, same everything but the two clauses.
`_counterfactual.py` declares nothing and writes no summary — it is a PRICE,
not a proposal.

| | SHIPPED (classes withdrawn) | W-C/W-F narrowed |
|---|---|---|
| nodes / active / untracked | 389 / 380 / 9 | **389 / 380 / 9** |
| evaluation sets | 172 | **172** |
| `tree_missing` | 151 | **151** |
| demand sets | 847 | 985 |
| **satisfiable** | **492 712** | **51 264** |
| covered | 2 428 | 2 890 |
| uncovered | **99.51 %** | **94.36 %** |
| sets of width >= 13 | **34**, holding 395 520 (80.3 %) | **0** |

**Those two class-wide withdrawals account for 89.6 % of the entire combination
demand on this endpoint, and for every single wide set.** Nothing else on the
endpoint is remotely this large.

### §5.2 The real blocker, stated plainly

The gate asks **"does flipping both produce a query shape absent from the
singles?"** The coverage rule uses the answer to decide **"must this
combination be observed?"** Those are different questions, and the width-20
sets are where they come apart: the pair is genuinely dependent *where both
outcomes are reachable*, and the co-evaluation rule then also demands the
assignments where they are **not** reachable — the ones §3.2 proved cannot
exist (0 of 5 687 runs). The framework currently has no way to say *"dependent,
but this particular product is infeasible"*: `IndependenceAssumption` deletes
the demand everywhere, `UntrackedPath` deletes the decision, and neither is
what is true here.

**So `complete: true` on notifications_index is blocked on a modelling decision,
not on driving,** and it is one this agent should not take unilaterally: it
either narrows a gate-refuted class (which the standing proposal forbids) or it
adds a new kind of assumption to `src/` (Rule T territory — it would change what
`complete` asserts for every endpoint). Options, for the owner:

1. **A feasibility-scoped assumption** — "expressions A and B stay dependent,
   but assignments in which A takes the arm that forecloses B are not demanded".
   This is the honest statement of the ground truth and it is `src/` work.
2. **Narrow W-C/W-F to the refuted mechanism** (the mentions-container chain and
   the finder memo), restoring independence for the principal finders that no
   dispatched chain touches. Rejected once on 2026-09-09 as narrowing by prefix;
   it would need the gate re-run over the restored pairs.
3. **Accept the demand and declare the endpoint incompletable under §16**, with
   this measurement as the reason.

Whichever is chosen, the driving campaign the brief authorised is not the
instrument: 89.6 % of the target does not exist, and no number of runs
reaches it.

---

## §6. The v3 experiment — early read (1 200 of ~42 000 runs)

Raw-PC scan of the first 1 200 `DV3a100600` dumps, against the whole
68 231-dump corpus for contrast:

| decision family | v3 (1 200 runs) taken / not-taken | old corpus |
|---|---|---|
| `*_not_found` | **480 / 433** | e.g. `find_by_1_not_found` 7 / 2 696 |
| `*_text_dlink_is_post` | **12 / 14** | not-taken side **never observed** |
| `*_mention_inline_name` | **37 / 28** | not-taken side **never observed** |
| `*_persisted` | 98 / 76 | heavily one-sided |

Three of the 13 `tree_missing` branch outcomes are already hit by name in the
first 1 200 runs (`to_ary_1_row_target_text_dlink_is_post` not-taken x14,
`to_ary_1_row_target_mention_inline_name` not-taken x22,
`records_2_row_mention_inline_name` not-taken x6).

**So the boolean dimensions are free; they had simply never been seeded.** The
seeder, not the app, was the constraint on tree completeness. Final verdict
against §4.1 goes here once the drive and its measurement pass complete.

### §6.1 v3.0 was withdrawn — two seeder defects, both measured and fixed

The first v3 drive (`DV3a100600`, 6 000 seeds x 7 variants) exposed two
defects in the seeder, not in the app:

1. **JVM abort at run 119 in six of seven variants** (`free(): invalid pointer`,
   `hs_err_pid*.log` in the app dir). Seed #119 is the first with
   `SYM_PARAM_show: ""` — v3.0 built each key's domain from `concolic_seeds`,
   which only a minority of dumps carry, so `SYM_PARAM_show`'s domain came out
   as `['', 'unread']` and it seeded the REQUEST VARIANT, which `VARIANTS`
   owns. (The abort class is pre-existing — `hs_err` files from Aug 25/27/30
   sit in the same directory — but v3.0 is what triggered it here.)
   Result: those six variants produced 118 dumps each instead of 6 000.
2. **`I18n::InvalidLocale` on 2 967 of 6 000 runs** in the one variant that
   survived. Two causes, separated by a differential over the 800 probe dumps:
   * v3.0 also seeded `..._row_type`, which is DERIVED from
     `SYM_NOTE_TYPE_PROFILE` — pinning it to one STI class while the profile
     says another is an inconsistent state.
   * the boolean `devise_user_first_1_stale_language`: with it True,
     **422 of 422** probe runs raised `I18n::InvalidLocale`; with it False,
     **0 of 378**. It sets an invalid locale and the request dies at i18n
     before anything else is decided, so at p=1/2 it burned half the campaign.

**v3.1** takes its universe from `symbolic_vars` (present in EVERY dump, so no
thin-sample degeneracy) — **202 bool, 22 len, 37 count, 20 emptyable-string** —
behind an explicit allow-list, with an explicit deny-list for `SYM_PARAM_*`,
`*_type`, `*_guid`, `*_diaspora_handle`, `*_id`, `*_person_id`,
`*_birthday_year`, and it strips those keys from inherited templates too so a
stale override cannot be smuggled back in. `_stale_language` stays in the
domain at p=0.02 rather than being removed — it is a real decision.

Re-probe, 400 seeds x 2 variants: **800 of 800 dumps, 0 JVM aborts.**
Drive `DV31a100610` (8 000 v3.1 seeds x 7 variants) is running.

---

## §7. The completion drive under §16b (2026-09-10, later)

Appended as the work proceeds. Earlier sections are history and are not
rewritten.

### §7.1 Baseline

Snapshot `_snapshot_20260910_063649.txt`, **109 401 dumps** — verified
byte-identical to `_snapshot.txt`, the list the foreclosure census was priced
on, so the census IS the baseline and was not re-run:

| | value |
|---|---|
| demand sets | 1 010 |
| **demanded assignments (§16b)** | **62 324** |
| covered | 25 625 |
| remaining | 36 699 |
| **uncovered** | **58.88 %** |
| largest single-set gap | 551 |
| `tree_missing` | **10** |
| foreclosures applied / inferred | 3 507 / 12 001 |

The ten `tree_missing` branch outcomes, by name:

| # | expression | side wanted |
|---|---|---|
| T1 | `SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found == True` | taken |
| T2 | `SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_profile_not_found == True` | taken |
| T3 | `..._CollectionProxy_records_photos_312a5782_row_text_dlink_is_post == True` | not_taken |
| T4 | `..._Relation_to_ary_notifications_c7e6a7ca_row_target_statusmessage_text_dlink_is_post == True` | not_taken |
| T5 | `SYM_RESULT_ActiveRecord__FinderMethods_find_by_4_not_found == True` | taken |
| T6 | `..._to_ary_notifications_c7e6a7ca_row_target_statusmessage_mention_inline_name == True` | not_taken |
| T7 | `..._to_ary_notifications_10254800_row_target_mentions_container_commentable_author_profile_disp_dlink_is_post == True` | not_taken |
| T8 | `..._to_ary_notifications_cf379872_row_target_statusmessage_text_dlink_is_post == True` | not_taken |
| T9 | `..._to_ary_notifications_cf379872_row_target_statusmessage_mention_inline_name == True` | not_taken |
| T10 | `SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_username == ''` | taken |

### §7.2 Why v3.1 only moved 13 -> 10: SIX OF SEVEN VARIANTS GOT 277 RUNS

`_diverse_drive.sh` hands the whole 8 000-seed list to ONE JRuby per variant.
Measured on the shipped `DV31a100610` drive:

```
html_plain 277   html_typed 277   json_plain 277   json_typed 277
mobile_plain 277 mobile_typed 277 xml_plain 8000
```

Every non-xml variant died at path **#277** — `munmap_chunk(): invalid
pointer` / `SIGSEGV` in `libcurl.so.4`, a native abort inside the JVM. The
predecessor drive `DV3a100600` died the same way at **#119** in exactly the
same six variants. **v3.1 did not fix the abort class; it moved it.** So the
"8 000 x 7" drive actually delivered 8 000 x 1 + 277 x 6 = 9 662 runs, and the
one variant that got the full budget is the ONE variant that cannot reach any
of the ten branches: a corpus-wide scan of the 109 401-dump snapshot shows
`xml_plain` records **none** of the ten target expressions.

Corpus scan of the ten targets (`_tree_scan.py`, canonical names, the engine's
own load path): every one of them IS evaluated by the corpus — on the other
side — so none is a never-minted variable. Populations and the variants that
reach them:

| # | other-side runs | variants that reach it |
|---|---|---|
| T1 | 427 | html/json/mobile, both typings |
| T2 | 427 | html/json/mobile, both typings |
| T3 | 709 | html/json/mobile, both typings |
| T4 | 143 | html_plain, json_plain, mobile_plain |
| T5 | **3** | html_plain, html_typed |
| T6 | 22 | html_plain, json_plain, mobile_plain |
| T7 | 172 | html_typed, json_typed, mobile_typed |
| T8 | 110 | html_typed, json_typed, mobile_typed |
| T9 | 18 | html_typed, json_typed |
| T10 | 18 321 | mobile_plain, mobile_typed |

### §7.3 Two seeder repairs, both measured

**(a) The abort is SEED-DETERMINISTIC, so a drive can resume across it.**
Independent 200- and 300-seed chunks of the same list abort on the same
ABSOLUTE seed indices (#277, #496). `_chunk_drive.sh` (new) therefore splits
the list into chunks, gives each chunk its own JVM, and on an abort drops
exactly the seed that killed the VM and restarts on the remainder. Probe,
600 seeds, one variant: **594 of 600 consumed, 6 toxic seeds named and
dropped**, against 277 of 600 for the shipped driver.

**(b) The v3.1 seed universe was built at stride 120 (825 dumps) and MISSED
target T5's variable.** `SYM_RESULT_ActiveRecord__FinderMethods_find_by_4_not_found`
is minted in 3 dumps of 109 401; a stride-120 sample never saw it, so the
seeder could not vary it and T5 was unreachable by bulk driving BY
CONSTRUCTION. Rebuilt at stride 6 (18 395 dumps): **205 bool / 22 len /
39 count / 20 emptyable-string**, and all ten targets' seed keys are now in
the universe. Seed list `_diverseR32.json` (8 000 seeds).

### §7.4 The JVM abort has a CAUSE, and it is the discovery arm

The "seed-deterministic native abort" of §7.3(a) is not random flakiness. A
control-vs-flip differential on ONE seed (`_tw/probe/`, json_plain, same base
dump both ways):

| seed | rc | paths |
|---|---|---|
| base dump's own seeds, verbatim | **0** | 1 |
| the same seeds, deny-list applied | **0** | 1 |
| the same seeds + `Core__ClassMethods_find_by_1_not_found = True` | **134** | **0** |

`hs_err_pid*.log` native frames: `curl_easy_setopt` -> `__libc_free` ->
SIGSEGV, reached through `com.kenai.jffi.Foreign.invokeArrayReturnInt`. And
the population differential over the 37 toxic seeds the C32A bulk drive named:

| `(find_by_1_not_found, find_by_1_profile_not_found)` | toxic seeds | share of the 8 000-seed list |
|---|---|---|
| (True, False) | 17 | 24.8 % |
| (False, True) | 14 | 25.1 % |
| (True, True) | 6 | 24.5 % |
| **(False, False)** | **0** | **25.6 %** |

**37 of 37 toxic seeds set at least one of the two; none of the 0-abort
quarter does.**

The app code says why. `Person.find_or_fetch_by_identifier`
(`app/models/person.rb:318-329`), reached from
`lib/diaspora/mentionable.rb:89` when a notification's text carries a mention:

```ruby
person = by_account_identifier(diaspora_id)          # -> find_by_1
return person if person.present? && person.profile.present?
DiasporaFederation::Discovery::Discovery.new(diaspora_id).fetch_and_save
```

`find_by_1_not_found` is `!person.present?` and `find_by_1_profile_not_found`
is `!person.profile.present?`. **Either one true takes the request into
`Discovery#fetch_and_save`** — the very method whose SUCCESS arm
`POLICY_HEADER.txt` (M-17) already declares UNMODELLED because it needs two
live HTTP fetches and, measured by this batch on a PARSEABLE host, **aborts
the JVM with exit 134** while a URI-hostile handle exits 0. The batch's
mention fixture handle is `concolic_mention@example.org` (`targets.rb:1717`) —
a legal URI host, i.e. exactly the aborting case.

**Consequences, both of them useful:**

1. **T1 and T2 are the two entry conditions of the M-17 arm.** They are not
   undriven; they are unobservable in this environment. The dump is written at
   the END of a run, so a SIGSEGV takes the path condition with it — there is
   no seed, no context and no amount of driving that records them. See §7.6.
2. **Pinning both off makes bulk driving ~4x cheaper.** With
   `find_by_1_not_found = find_by_1_profile_not_found = False` in every seed,
   the rooted drives ran **0 aborts in 157 runs** against ~1 abort per 100 runs
   before. Bulk list `_diverseR33.json` carries the pin.

### §7.5 A second seeder defect: `SYM_PARAM_show` is a REAL dimension

v3.1's deny-list excludes `SYM_PARAM_*` wholesale, blamed on the v3.0 abort at
seed #119. §7.4 reattributes that abort to the discovery arm, and the
exclusion turns out to cost a whole dimension: `run_dse.rb:95-101` makes
`show` a genuine symbolic request parameter, seeded from `""` and flipped to
`"unread"` by DSE. Measured over a 3 000-dump random sample, the four
`to_ary_notifications_*` statement aliases are **exactly** that dimension
crossed with `type`:

| alias | variant | `show == 'unread'` |
|---|---|---|
| `notifications_10254800` | typed | **true** |
| `notifications_3aa8587a` | plain | **true** |
| `notifications_c7e6a7ca` | plain | false |
| `notifications_cf379872` | typed | false |

The first rooted attempt at T7 (`notifications_10254800`, typed x unread)
stripped `SYM_PARAM_show` from its base dumps and so drove **19 runs against
`cf379872`** — the right branch on the wrong statement. Keeping the parameter
closed it on the next attempt, 19/19. `_diverseR33.json` varies it 50/50.

### §7.6 tree_missing 10 -> 3: what closed each branch

Rooted seeds (`_tree_root.py`: a REAL dump's own seeds, one dimension flipped,
canonical->ordinal through the base dump's own alias map, all ordinals backing
a canonical seeded). 157 runs, 0 aborts. Verified with `_tree_check.py`
through the engine's load path (`canonicalize_ordinals`), then by a coverage
pass.

| # | outcome | evidence |
|---|---|---|
| T3 | **CLOSED** 36 hits | `dump_html_typed_dse0002_TR3t03htmtr0.json` |
| T4 | **CLOSED** 21 hits | `dump_json_plain_dse0004_TR3t04jsopr0.json` |
| T5 | **CLOSED** 2 hits | `dump_html_plain_dse0001_TR3t05htmpr0.json` — the branch the stride-120 seed universe could not see (3 dumps of 109 401) |
| T6 | **CLOSED** 5 hits | `dump_json_plain_dse0003_TR3t06jsopr0.json` |
| T7 | **CLOSED** 19 hits | `dump_html_typed_dse0007_TR4t07htmtr0.json` — after §7.5 |
| T8 | **CLOSED** 12 hits | `dump_html_typed_dse0002_TR3t08htmtr0.json` |
| T9 | **CLOSED** 4 hits | `dump_html_typed_dse0001_TR3t09htmtr0.json` |
| T1 | **UNREACHABLE** in this environment | §7.4 — the M-17 discovery arm; SIGSEGV before the dump is written |
| T2 | **UNREACHABLE** in this environment | §7.4 — same arm, the other entry condition |
| T10 | **UNREACHABLE** — see §7.7 | 38 of 38 rooted runs raise `No route matches {…:username=>""}` |

### §7.7 T10 — `username == ''` is foreclosed by a route constraint UPSTREAM in the same partial

The site is `String#blank?` (`activesupport .../object/blank.rb:126`), reached
only in the two mobile variants (18 321 not-taken observations; zero in
html/json/xml). Its position in the event stream is pinned: it fires between
`_drawer.mobile.haml:28` (`current_user.followed_tags.length > 0`) and the
`roles` existence probe of `current_user.admin?` (`:40`). Line **33** of that
same partial is

```haml
= link_to user_profile_path(current_user.username) do
```

and `config/routes.rb:189` is
`get '/u/:username' => 'people#show', as: 'user_profile', constraints: {username: /[^\/]+/}`.
The helper's argument is evaluated **before** `link_to` is called, so every run
that reaches the compare has already generated that path.

Measured, 38 rooted runs (TR3 + TR4, seed honoured — `symbolic_vars` shows
`value: ''`): **38 of 38** reach 86–90 path conditions and then raise

```
ActionView::Template::Error: No route matches
  {:action=>"show", :controller=>"people", :username=>""},
  possible unmatched constraints: [:username]
```

at `journey/formatter.rb:57`, and the compare is **never reached**. The same
thing happened to the 78 v3.1 bulk runs that drew `''` for this key.

So the taken side is not undriven, it is **structurally foreclosed by a gate
earlier in the same template**: `''` is the only value that satisfies the
compare and the only value that cannot survive the route helper above it.

The application agrees: `app/models/user.rb:37-38` validates
`username` `presence: true` and `format: /\A[A-Za-z0-9_]+\z/`, so no persisted
`users` row can hold `''`.

**One thing the probe found that is worth recording** (and whose dumps were
then removed from the corpus, deliberately — see below). Seeding a WHITESPACE
username (`' '`, `'  '`) does survive the route helper and completes cleanly,
and it shows the runtime's model of `blank?`: `empty?` records
`(username == '')`, and the whitespace path then records a SECOND expression
`(username != StringVal(''))` that no run in the corpus has ever produced. Its
`not_taken` side needs `username == ''` — the same impossible value — so
keeping those 9 probe dumps would have ADDED a permanently unclosable
`tree_missing` entry to the endpoint. They were deleted immediately
(`_tw/probe/t10ws.log` keeps the evidence). Note also that this makes the
recorded decision a NARROWING of the real `blank?`: real `blank?` is true for
whitespace too, and that arm is entered with no matching path condition. That
is a pre-existing property of the string model, not something this campaign
introduced, and it is not what `tree_missing` names.

### §7.8 What `missing == 0` can and cannot mean while T1/T2/T10 stand

A demand set that contains one of the three unreachable expressions demands
cubes on BOTH of its sides — nothing is declared, so the engine has no way to
know one side is unobtainable. Those cubes are permanently missing. **So
`missing == 0` on the SHIPPED assumption set is unattainable on this endpoint
until the owner rules on the three proposals**, and `tree_missing` would refuse
the combination claim anyway.

The campaign is therefore run against two numbers, and both are reported:

* **AS SHIPPED** — `coverage_report.py` with this batch's unchanged
  `coverage_assumptions.py`. This is the file the endpoint ships
  (`coverage_summary.json`). Its residual is driven down until every remaining
  entry is a cube that assigns an unreachable outcome, and that is stated with
  the count.
* **COUNTERFACTUAL** — the same pass with `PIN_UNREACHABLE=1 SUMMARY_OUT=…`,
  which applies the three proposed `OneSideUntracked` pins IN MEMORY and writes
  to a different file. `coverage_assumptions.py` is not touched and
  `coverage_summary.json` is not overwritten (the knob refuses to run without
  `SUMMARY_OUT`). This prices "what the endpoint would be if the three
  proposals were accepted" — the same instrument `_counterfactual.py` used for
  W-C/W-F in §5.1.

`_demand_root.py` gained the matching filter: a witness that assigns an
unreachable outcome is SKIPPED and COUNTED rather than turned into a seed that
kills the runner, and every seed it does build pins the two discovery booleans
off.

### §7.9 The drives, as run

| tag | what | variants | seeds/variant | outcome |
|---|---|---|---|---|
| TR3 | rooted tree seeds, targets T3–T10 | 6 | 1–10 per (target, variant) | 119 runs, **0 aborts**, closed T3 T4 T5 T6 T8 T9 |
| TR4 | rooted tree seeds, T7 and T10, `SYM_PARAM_show` kept | 5 | as above | 38 runs, 0 aborts, closed **T7** |
| C32A | bulk v3.2 (`_diverseR32.json`, stride-6 universe), no discovery pin | html_plain (8 000) + html_typed (partial) | 1 000/chunk | **37 toxic seeds** — the differential that found §7.4 |
| C33A | bulk v3.3 = v3.2 + discovery pin + `SYM_PARAM_show` | html_plain 8 000, html_typed 6 000 | 1 000/chunk | **0 toxic seeds** in 14 000 runs |
| C33B/C | bulk v3.3, the other five variants | json/mobile/xml | 4 000–8 000 | 0 toxic |

Corpus **109 401 -> 153 252** dumps.

The abort-resume chunk driver is what makes this reproducible: the shipped
`_diverse_drive.sh` delivered 277 runs per non-xml variant, `_chunk_drive.sh`
delivers the whole list and names any seed it has to drop.

---

## §8. The pins are INSTALLED — and the gate can test only one of them

**Owner instruction, 2026-09-10 ~08:00** ("continue working till all endpoints
are complete"), relayed by the coordinator with the direction to install the
three unreachable-side pins rather than leave them as proposals. Done:
`coverage_assumptions.py` gains `_overnight_unreachable_pins`, a separate tier
counted and printed on its own (`OVERNIGHT_PINS=` in the `[assumptions]` line),
with the evidence, the falsifier and the precedent in its docstring. Backup of
the previous file: `_bak_coverage_assumptions_pre_overnight_pins.py`. Reversal
is one edit (`_OVERNIGHT_PINS = ()`), and every number is reported twice —
shipped (with pins) and `NO_PINS=1 SUMMARY_OUT=…` (without).

### §8.1 The gate's verdict on the three pins — MEASURED, not predicted

`assumption_checker.py` over `_assum_pins.json` alone
(`_assum_pins_results.json`, `_assum_pins.log`):

```
  FAIL  OneSideUntrackedPathAssumption  (…Core__ClassMethods_find_by_1_not_found == True)
      flip probe produced no dump in the snapshot's scenario
  FAIL  OneSideUntrackedPathAssumption  (…Core__ClassMethods_find_by_1_profile_not_found == True)
      flip probe produced no dump in the snapshot's scenario
  PASS  OneSideUntrackedPathAssumption  (…devise_user_first_1_username == '')
      flipping the variable leaves the PC unevaluated — the other side is unreachable by construction

RESULT: 3 distinct tested — PASS 1, FAIL 2, NOT-TESTABLE 0, NOT-COMPARABLE 0
```

**T10 passes cleanly and for the right reason** — the gate flipped the seed,
the run completed, and the compare was never evaluated. That is precisely the
§7.7 argument, re-derived by the gate from its own probe.

**T1 and T2 FAIL, and the FAIL is not a refutation.** The gate tests a pin by
FLIPPING the branch and replaying. Flipping these two is exactly the action
that SIGSEGVs the JVM, so the probe produces no dump and the checker's
`r is None` branch reports `FAIL: flip probe produced no dump`. The gate is
not saying "the untracked side adds access shapes"; it is saying it could not
run the experiment. **The pin's evidence and the gate's failure mode are the
same event.**

So the pins do NOT by themselves make this endpoint complete:

| layer | with the pins |
|---|---|
| `coverage_complete` / `tree_missing` | the three outcomes leave `tree_missing`; the coverage claim can be earned |
| `completion` (assumption gate) | **2 FAILs**, therefore `completion.complete = False` and `complete = False` |

### §8.2 What actually closes it, and why this agent may not do it

Two ways, both outside a batch agent's authority:

1. **The boundary change already filed in `AGENT_RUN.md`** — declare
   `DiasporaFederation::Discovery::Discovery#fetch_and_save` a target that
   publishes its WALL note and then RAISES `DiscoveryError`, the exact form
   `comments_index/targets.rb` §8e ships and that endpoint closed with. Then
   the arm no longer aborts, the two branches become OBSERVABLE, the pins are
   deleted rather than argued, and the gate has a probe it can run. **Rule T3:
   only the coordinator edits a wall.** This batch withdrew its own
   `fetch_and_save` wall on 2026-09-01 under a coordinator condition
   (`targets.rb:1732-1815`) — because the OLD wall returned `nil` and modelled
   a success the app has no path to. The comments_index form does not have
   that defect: it raises, and `mentionable.rb:88-91` rescues the raise to
   nil, which is what the application does.
2. **A crash-isolated gate probe** (`src/end_to_end_completion_checker/…`),
   so "the probe aborted" is a distinguishable verdict from "the probe ran and
   the claim failed". That is a `src/` change and is reported, not made.
   The pattern exists: `results/users_sessions/drive_registrations.py`.

Not doing: changing the mention fixture handle to a URI-hostile domain. It is
per-batch material (Rule T1), and it WOULD make the arm raise in pure Ruby —
but `targets.rb:1741-1752` considered exactly that and rejected it (DSE flips
string values freely, so a flip back to a parseable handle re-arms the abort),
and it would change the literal inside every `people` note in the corpus.

---

## §9. The wall came back, in its RAISING form — and T1/T2 fell in six minutes

**Coordinator ruling, 2026-09-10: §8.2 option 1 AUTHORISED.**
`targets.rb` §5h-bis now declares
`DiasporaFederation::Discovery::Discovery#fetch_and_save` a target that
publishes its WALL note and then raises `DiscoveryError` — verbatim the shape
`results3/comments_index/targets.rb` §8e ships on a CLOSED endpoint. Per-batch
material (Rule T1); `concolic_targets.rb` untouched; no closed endpoint voided.
Backup of the previous file: `_bak_targets_pre_c8_discovery_wall.rb`.

The in-file note sits next to the 2026-09-01 withdrawal note and says why both
are right: the WITHDRAWN wall returned `nil`, modelling a success the app has
no path to (1 916 dumps ending in a clean 200 where the app always raises);
the RAISING form models what the app does, and
`Mentionable.find_or_fetch_person_by_identifier` (mentionable.rb:88-91)
RESCUES `DiscoveryError` to nil, so the mention renders as its raw text, the
request does not 500 and no statement is invented.

### §9.1 Smoke — the abort is gone

`dump_json_plain_dse0001_C8WALLSMOKE.json`, the SAME seed that produced
`rc=134 / 0 paths` before the wall:

```
rc=0     new paths=1     "fatal error" occurrences=0     hs_err_pid*: none
error: None      path conditions: 58
(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found == True) :: TAKEN
call event: DiasporaFederation::Discovery::Discovery.fetch_and_save  @ person.rb:325
```

The wall records as a `call` event at the application's own line — the same
shape comments_index's corpus carries for its `fetch_and_save` wall.

### §9.2 T1 and T2 driven both ways

`_tree_drive2.sh TR5 t01 t02` — 70 runs, **0 aborts**, 12 of 12 (target,
variant) jobs consumed on the first try:

| # | outcome |
|---|---|
| T1 `find_by_1_not_found == True :: taken` | **CLOSED**, 35 hits (35 on the other side in the same 70 runs) — `dump_json_plain_dse0001_TR5t01jsopr0.json` |
| T2 `find_by_1_profile_not_found == True :: taken` | **CLOSED**, 35 hits — `dump_json_plain_dse0005_TR5t02jsopr0.json` |

So the pins for T1/T2 are **DELETED** from `_overnight_unreachable_pins`
(a branch that can be driven is never argued); the tier now holds T10 alone,
which PASSED the gate on its own merits. `OVERNIGHT_PINS=1`.

### §9.3 tree_missing: 10 -> 3 -> 0

| stage | `tree_missing` |
|---|---|
| baseline, 109 401 dumps | **10** |
| after the rooted drives TR3/TR4 + bulk v3.3, 153 252 dumps (engine pass, no pins) | **3** — T1, T2, T10, exactly the three with a grounded argument |
| after the wall + TR5, with T10 pinned | **0** (to be confirmed by the next pass's own `tree_missing` line) |

The seven that fell to driving fell because of §7.3's two seeder repairs and
§7.5's `SYM_PARAM_show` restoration; the two that needed the boundary fell in
six minutes once the wall was there; the one that remains is pinned and
gate-verified.

### §9.4 The pass-1 census (no pins, wall not yet installed)

`_c8_cov1.log`, snapshot `_snapshot_20260910_080559.txt` (153 252 dumps),
`SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=8 MISSING_CAP=8000`, own scope,
MemoryMax=12G, coverage phase **4 926 s**, peak RSS 4 791 MB:

```
COMPLETE=False;NODES=411;MISSING=5875;BLOCKING=5871;PCS=7437398
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
demand_sets=1022   tree_complete=False   tree_missing=3   assumptions_used=22459
dump_errors={'ActionView::Template::Error': 33631, 'I18n::InvalidLocale': 5069}
```

`TRUNCATED=True` here is the MMC cap being reached with combinations still
being found (`coverage.py:988`), not a projection-cap or solver event —
`solver_lost=0`, `unevaluable=[]`. It is the normal state of a demand round
and clears when `missing` reaches 0. Saved as
`_cov_nopins_20260910_0939.json` (the NO-PINS counterfactual for §7.8's
two-number rule).

### §9.5 Demand round DR1

`_demand_root.py` over the pass-1 witnesses, on the SAME snapshot the pass
measured (`DUMP_LIST`, new knob — a root must be built from a dump the witness
actually saw). Two repairs to that tool, both forced by scale:

* **memory** — it kept every dump's `concolic_seeds` in RAM. v3 seed dicts
  carry ~270 keys, so at 153 252 dumps that is several GB and the round OOMs.
  It now keeps the PATH and loads the chosen bases' seeds lazily (memoised).
* **time** — the base search is O(missing x dumps) = 5 871 x 153 252 = 900 M
  iterations. It now stops at the best obtainable score (every expr of the
  combination recorded on the OPPOSITE polarity, in a variant the combination
  is recorded in). Root building fell from "still running after 20 minutes"
  to about 5 minutes.

```
missing (blocking): 5871
indexed 153252 dumps, 411 distinct exprs, 421 wanted
html_plain 2201  html_typed 2250  json_plain 1106  json_typed 1201
mobile_plain 1793  mobile_typed 1871  xml_plain 0        = 10 422 rooted seeds
combinations with no corpus base: 0
combinations SKIPPED as environmentally unreachable: 74   (all T10 — T1/T2 came
                                                          off that list when the
                                                          wall landed)
```

Drive: `_demand_drive.sh DR1`, 6 jobs, **10 422 of 10 422 seeds consumed,
0 aborts, every job on its first try**. Corpus **163 323 -> 173 745**.

### §9.6 Pass 2, and the FOUR NEW branches the wall opened

`_c8_cov2.log`, snapshot `_snapshot_20260910_102206.txt` (173 745 dumps), pins
in (`OVERNIGHT_PINS=1`), wall in, coverage phase **4 214 s**, peak RSS 5 588 MB:

```
COMPLETE=False;NODES=417;MISSING=5388;BLOCKING=5384;PCS=8513554
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
demand_sets=1037   tree_missing=4   assumptions_used=23122
```

The three of pass 1 are gone — T1/T2 driven, T10 pinned — and **four new ones
appeared**, all on the mentions chain the wall opened (`tree_nodes` 411 -> 417):

```
(…Relation_records_mentions_d25799cb_row_person_profile_row_first_name == StringVal('')) :: taken
(…Relation_records_mentions_d25799cb_row_person_profile_row_last_name  == StringVal('')) :: taken
(…Relation_records_mentions_fbb27183_row_person_profile_row_first_name == StringVal('')) :: taken
(…Relation_records_mentions_fbb27183_row_person_profile_row_last_name  == StringVal('')) :: taken
```

This is exactly the mutability §16 describes: a corpus that walks new ground
ADDS decisions, and `tree_missing` names them the moment they exist. It is
not a regression — the four are the blank-name arm of
`Person.name_from_attrs` (`concolic_targets.rb:1698-1699`) on the mention's
own profile, a region no run could reach while the arm aborted.

### §9.7 A THIRD rooted-seed defect: the deny-list is wrong for a ROOTED seed

The first attempt (TR6, 102 runs) hit the branch **0 times and did not even
EVALUATE the expression**. Diff of a rooted seed against its own base dump —
3 keys differ where only 1 should:

```
find_by_1_profile_not_found          True -> False   (the §7.4 discovery pin)
..._row_person_diaspora_handle       'concolic_mention@example.org' -> ABSENT
..._row_person_profile_row_first_name  ABSENT -> ''  (the intended flip)
```

`_tree_root.py` was applying `_diverse_seeds3.py`'s DENY-LIST to the base
dump's seeds. That list exists for a BULK seeder, which invents values; a
ROOTED seed reproduces a real run and flips one dimension, so the deny-list is
simply wrong there — and it dropped
`..._row_person_diaspora_handle`, which `lib/diaspora/mentionable.rb:35`
compares to decide whether the mention resolves to that person at all
(`diaspora_handle` is a Rule G GATE column). With the handle gone the mention
never resolved, `Person.name_from_attrs` was never called on that chain, and
the compare had no site.

Fix: rooted seeds are now **verbatim** base seeds plus the single flip, and the
discovery pin is gone from both `_tree_root.py` and `_demand_root.py` (the
wall retired it). Re-drive **TR7**, same 102 runs:

| # | outcome |
|---|---|
| `…mentions_d25799cb_…_first_name == '' :: taken` | **CLOSED**, 15 hits |
| `…mentions_d25799cb_…_last_name == '' :: taken` | **CLOSED**, 15 hits |
| `…mentions_fbb27183_…_first_name == '' :: taken` | **CLOSED**, 36 hits |
| `…mentions_fbb27183_…_last_name == '' :: taken` | **CLOSED**, 36 hits |

**The same defect was in DR1's seeds** (the discovery pin forced
`find_by_1_profile_not_found` off in all 10 422 of them), which is the most
likely reason that round moved `missing` only 5 871 -> 5 384. DR2 runs without
it.

### §9.8 Demand round DR2 (clean seeds)

`_demand_root.py` over pass 2's 5 384 blocking witnesses, same snapshot, no
discovery pin, verbatim base seeds:

```
html_plain 2097  html_typed 2201  json_plain 994  json_typed 1072
mobile_plain 1644  mobile_typed 1851  xml_plain 0        = 9 859 rooted seeds
combinations with no corpus base: 0
combinations SKIPPED as environmentally unreachable: 0
```

Drive `_demand_drive.sh DR2`: **9 859 of 9 859 consumed, 0 aborts, every job
first try**. Corpus **173 949 -> 183 808**.

Pass 3 is run at `MAX_MISSING_PER_CLIQUE=16` (was 8) so each round harvests
twice as many witnesses per demand set; the pass cost is dominated by the
per-set blocking-clause construction, not by the cap.

---

## §10. tree_missing is ZERO — and the state of the combination demand

### §10.1 Pass 3 — the tree layer is complete

`_c8_cov3.log`, snapshot `_snapshot_20260910_122659.txt` (183 808 dumps),
`MAX_MISSING_PER_CLIQUE=16`, coverage phase **7 837 s**, peak RSS 6 036 MB:

```
COMPLETE=False;NODES=417;MISSING=8811;BLOCKING=8807;PCS=9250565
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
demand_sets=1037   tree_complete=TRUE   tree_missing=0   OVERNIGHT_PINS=1
```

**`tree_missing = 0`.** Every tracked decision on this endpoint has now been
observed with every satisfiable outcome, or is the ONE pinned side that the
gate itself verified is unreachable by construction. The combination claim is
no longer refused by the precondition, and the 3 592 applied foreclosures stop
being PROVISIONAL the moment the combination claim is earned.

`MISSING` rose 5 388 -> 8 811 only because the cap rose 8 -> 16; the
comparable quantity is sets-with-a-gap, and that fell (see §10.3).
`TRUNCATED=True` is that cap, not a projection or solver event.

### §10.2 The corpus prune — SOUND, VERIFIED, and it saves the LOAD only

Priced at the coordinator's request. Under §16b the checker reads exactly one
thing off a run: its outcome profile `expr -> {outcomes taken}` over the
canonical expressions. Everything — the demand sets (`maximal_sets` over
profiles), the inferred foreclosures, the covering cubes, the blocking clauses
(closed-prefix partial walks included, since a partial walk has its own
profile) and `tree_missing` — is a function of the SET of profiles. So the
minimal covering subset is **one dump per distinct outcome profile**, and that
is exact, not a greedy approximation. `_prune_corpus.py` computes it; it
writes a SNAPSHOT LIST and deletes nothing.

```
corpus 183 808 dumps -> 76 990 distinct outcome profiles (0 unparseable)
```

**Equivalence, verified on the identical snapshot** — `_exact_enum.py` over the
full list and over the pruned list, both through the batch's own load path and
unchanged `coverage_assumptions.py`:

| | full 183 808 | pruned 76 990 |
|---|---|---|
| evaluation sets -> demand sets | 1384 -> 1037 | **1384 -> 1037** |
| foreclosures inferred / gates | 9334 / 371 | **9334 / 371** |
| `tree_missing` | 0 | **0** |
| nodes (active) | 408 | **408** |
| satisfiable / covered / remaining | 64 748 / 37 261 / 27 487 | **identical** |
| `bounded_cliques` | 0 | **0** |
| foreclosures applied / leaf groups | 3592 / 3561 | **identical** |
| wide sets (>=13) / their remaining mass | 48 / 8 835 | **identical** |
| census wall | 68 s | 67 s |
| whole-tool wall | ~19 min | **~7 min** |

**Byte-identical on every number.** But note WHAT it buys, honestly: the census
wall is 68 s vs 67 s — the engine ALREADY collapses runs to distinct outcome
profiles, so the SOLVER phase does not move at all. The saving is the LOAD
phase (2.4x fewer JSON parses) and the memory (6.0 GB -> ~2.5 GB). It does not
turn a 2 h pass into a 20 min pass; it takes perhaps 20 minutes off it. The
binding cost is Z3 over 1 037 demand sets x the missing cap, and that is a
function of the DEMAND, not of the corpus size.

### §10.3 Where the combination demand actually stands

Exact census (`bounded_cliques=0`, so every figure is exact, not a bound):

| | baseline 109 401 dumps | **now, 183 808 dumps** |
|---|---|---|
| demand sets | 1 010 | **1 037** |
| demanded assignments | 62 324 | **64 748** |
| covered | 25 625 | **37 261  (+45 %)** |
| remaining | 36 699 | **27 487  (−25 %)** |
| uncovered | 58.88 % | **42.45 %** |
| sets fully covered | 116 | **171** |
| sets with a gap | 894 | **866** |
| median gap / mean gap | 15 / — | **12 / 31.7** |
| largest single-set gap | 551 | **484** |
| wide sets (>=13) and their remaining mass | 43 / 11 675 | **48 / 8 835** |
| `tree_missing` | 10 | **0** |

The demand GREW (more decisions, more sets — the wall opened a region), and
coverage grew faster.

### §10.4 DR3 and DR4 — the rooted-demand method's conversion rate, measured

| round | seeds | runs | `remaining` before -> after | assignments closed per run |
|---|---|---|---|---|
| DR3 (1 base per witness) | 15 630 | 15 630, 0 aborts | 27 487 -> **24 590** | 0.185 |
| DR4 (3 bases per witness, same witness set) | 28 535 | 28 535, 0 aborts | 24 590 -> **24 194** | **0.014** |

**DR4 is a negative result and it is worth stating plainly.** Giving each
witness three different bases instead of one closed 396 more assignments out of
28 535 runs. So the witnesses that DR3 failed to realise are not failing for
want of a better base — the method itself cannot reach them.

### §10.5 WHY — the residual splits in two, and only one half is a driving problem

Classification of the 8 807 blocking witnesses of pass 3 by the KIND of
variable their cube constrains (`SYM_LEN_x` mapped back to `len(x)`, alias
hashes normalised, checked against `_seed_universe3.json`):

| the cube constrains | witnesses | share |
|---|---|---|
| only variables the BULK seeder already varies (bools, `len(...)`, counts, emptyable strings, the two STI ints, `SYM_PARAM_show`) | **5 568** | 63 % |
| ALSO an IDENTITY variable — `*_person_id`, `*_row_id`, `*_guid`, `*_diaspora_handle`, `*__prior` | **3 235** | 37 % |
| a derived `*_row_type` | 4 | — |

* The **63 %** are an ordinary driving backlog. They should respond to BULK
  diversity (a v3.3-style run draws a fresh assignment in every dimension at
  once and so covers a cube in every set it walks simultaneously) far better
  than to another demand round, which re-aims at the same cubes.
* The **37 %** are not a driving problem at all. Those are the var-vs-var
  identity compares — `people_helper.rb:81-86` `current_user.person == person`,
  the `gon_helper.rb:6` self-compare that `split_self_compare` renames to
  `..._person_id__prior`, and the hovercard `guid.blank?` family. Their values
  are DERIVED by the mocks, not read from a seed: `_demand_root.py` writes the
  Z3 model's value into the seed dict and nothing consumes it, so the cube
  cannot be forced no matter how many bases it is given. That is exactly the
  DR4 result. Closing them needs either the identity columns made seedable in
  this batch's `targets.rb` (per-batch material, Rule T1) or a declaration —
  and either is a decision, not a drive.

**So `missing == 0` is not reachable by more demand rounds as the tooling
stands.** The honest next steps, in order of cost:

1. **Bulk, not demand, for the 63 %.** `_diverseR33.json` x 7 variants at the
   full 8 000 (this campaign only got html_plain to 8 000; the rest got
   1 000-6 000 before the box needed the memory) — about 40 000 runs, ~1 h at
   the measured rate, and the drive is abort-free now.
2. **Make the identity columns seedable** for the 37 %: the mocks derive
   `person_id` / `row_id` / `guid`; letting a seed pin them (as the other
   columns already are) turns 3 235 witnesses from unreachable into ordinary
   demand roots. `targets.rb` is per-batch, so this is inside a batch agent's
   authority — but it changes what every run's identity looks like, so it
   should be a deliberate, reviewed change, not something done at the end of a
   long session.
3. Only if 1 and 2 leave a residue: consider what it is evidence OF.

---

## §11. State at hand-off (2026-09-10 16:45 UTC)

**Machine is QUIESCENT** — 0 JRuby, 0 coverage passes, 0 censuses running;
11 GB RAM available, 174 GB disk free. The slots and the memory are free.

| | |
|---|---|
| corpus | **227 973** dumps (baseline 109 401; **+118 572** this campaign) |
| pruned equivalent (verified byte-identical verdict) | 92 102 — `_snapshot_pruned_20260910_163232.txt` |
| `tree_missing` | **0** (`tree_complete: true`) |
| demanded / covered / remaining (exact, `bounded_cliques=0`) | 65 140 / 40 946 / **24 194** |
| uncovered | **37.1 %** (baseline 58.88 %) |
| demand sets | 1 042 (171+ fully covered) |
| shipped `coverage_summary.json` | pass 3, 183 808-dump snapshot, `MISSING=8811` at MMC=16, `tree_missing=0`, `OVERNIGHT_PINS=1` |
| latest census | `_c8_census_dr4.json` / `.log` (92 102-dump pruned list, 227 973-dump corpus) |

### What changed in the batch (all per-batch, `src/` and `concolic_targets.rb` untouched)

| file | change |
|---|---|
| `targets.rb` | §5h-bis — `Discovery#fetch_and_save` RAISING wall (coordinator-authorised). Backup `_bak_targets_pre_c8_discovery_wall.rb` |
| `coverage_assumptions.py` | `_overnight_unreachable_pins` tier, now **one** pin (T10), counted as `OVERNIGHT_PINS=`. Backup `_bak_coverage_assumptions_pre_overnight_pins.py` |
| `coverage_report.py` | `DUMP_LIST`, `SUMMARY_OUT`, `NO_PINS=1` (counterfactual; refuses to run without `SUMMARY_OUT`) |
| `_exact_enum.py` | `NO_PINS=1` |
| `_demand_root.py` | `DUMP_LIST`; lazy base seeds (memory); early-exit base search (time); `DEMAND_BASES` (default 3); discovery guard removed |
| `_tree_root.py` (new) | rooted seeds for `tree_missing`, VERBATIM base seeds + one flip |
| `_tree_scan.py`, `_tree_check.py`, `_tree_drive2.sh` (new) | per-target scan / check / drive |
| `_chunk_drive.sh`, `_demand_drive.sh` (new) | abort-resuming chunked drivers |
| `_prune_corpus.py` (new) | the verified minimal-corpus snapshot |
| `queries_from_runs/_extract_notifications_index_streaming.py` (new) | ported from comments_index, with E1 + the E11 RED check + `DUMP_LIST`. **NOT YET RUN** — its blockaid/subsumption step is Java and must not run beside a pass |

### Not done, and why

* **`missing == 0`** — see §10.4/§10.5: the rooted-demand method is at its
  limit (DR4 closed 396 of 24 590 in 28 535 runs). 63 % of the residual wants
  BULK diversity, 37 % wants seedable identity columns. Neither is another
  demand round.
* **The full engine run and `_c7_audits.sh`** — not started; they should run on
  a corpus that is at or near `missing == 0`, and the gate must be given its
  own slice.
* **The extraction** — the script exists and is ready; not run.

### Filed, not implemented (as instructed)

**A crash-isolated assumption-gate probe** (`src/end_to_end_completion_checker/
assumption/assumption_checker.py`). Today the gate spells "the probe aborted
the JVM" and "the probe ran and the claim failed" the same way —
`FAIL: flip probe produced no dump in the snapshot's scenario` — and that cost
this endpoint a whole diagnostic cycle (§8.1). The fix is the
`results/users_sessions/drive_registrations.py` pattern: write the in-flight
seed to disk, fsync, supervise from outside, and report `ABORTED` as its own
verdict. It would also let a pin whose falsifier is "the probe cannot run" be
stated honestly instead of failing.

---

## §12. Phase 2 — the full bulk v3.3 drive (2026-09-10, overnight)

Owner instruction relayed 2026-09-10: "continue working till all endpoints are
complete." This section is appended as the work proceeds; §1-§11 are history and
are not rewritten.

### §12.1 Baseline — REUSED, not re-derived

Snapshot `_snapshot_20260910_164828.txt`, **227 973 dumps** — the same corpus
§11 handed off, byte-count verified. The §10.3/§11 census is therefore the
baseline and was NOT re-run:

| | value |
|---|---|
| corpus | 227 973 dumps (pruned equivalent 92 102) |
| demanded assignments (§16b, exact, `bounded_cliques=0`) | **65 140** |
| covered | **40 946** |
| remaining | **24 194** |
| uncovered | **37.1 %** |
| demand sets | 1 042 |
| `tree_missing` | **0** (`tree_complete: true`) |
| wide sets (>=13) / their remaining mass | 48 / 8 354 |

### §12.2 What of the bulk v3.3 budget was actually consumed

`_diverseR33.json` is 8 000 seeds; the intended budget is 8 000 x 7 variants =
**56 000 runs**. The union of the `done_` markers across tags C33A/C33B/C33C
(chunk size 1 000, so 8 chunks per variant) says what §7.9's "1 000-6 000
before the box needed the memory" means, chunk by chunk:

| variant | chunks consumed | runs |
|---|---|---|
| html_plain | 0-7 | 8 000 |
| html_typed | 0-5 | 6 000 |
| json_plain | 0-3 | 4 000 |
| json_typed | 0-3 | 4 000 |
| mobile_plain | 0-3 | 4 000 |
| mobile_typed | 0-3 | 4 000 |
| xml_plain | 0-3 | 4 000 |
| **total** | | **34 000 of 56 000** |

(C33C re-ran json_plain/json_typed chunks 0-3, already consumed under C33B —
duplicated seeds, no new budget.)

So the drive that completes the brief's "8 000 x 7 in full" is the **22 000
unconsumed runs**: html_typed c6-c7, and c4-c7 of json_plain, json_typed,
mobile_plain, mobile_typed, xml_plain. Tag **C33D**, chunk 1 000, unique
`LABEL_SUFFIX` per (tag, variant, chunk, retry) as the standing correction
requires. The already-consumed (variant, chunk) pairs are pre-marked `done_`
under the C33D chunk dir so no seed is driven twice; the log records which.

`_chunk_drive.sh` gains one knob, `DRIVE_PAR` (default: `CONCOLIC_SLOTS`, i.e.
previous behaviour) so this drive can run FEWER workers than there are
machine-wide JRuby locks — another agent is driving people_stream on the same
box through the same `tools/slot`, and taking every lock would starve it.
C33D runs `DRIVE_PAR=2` against `CONCOLIC_SLOTS=3`.

### §12.3 PRE-REGISTRATION — written before C33D ran

The claim under test is §10.5's split: that the **63 %** of residual witnesses
whose cube constrains only bulk-seeded variables is "an ordinary driving
backlog" that "should respond to BULK diversity far better than to another
demand round", while the **37 %** that also constrain an identity variable
cannot be forced by driving at all.

Measured rates to beat, from §10.4: DR3 (rooted demand, 1 base/witness) closed
**0.185** assignments per run; DR4 (3 bases/witness) closed **0.014**.

The brief asks what "mostly close" means. Stated before the run, over the
22 000 runs of C33D, measured by ONE exact census on the post-drive corpus:

| | criterion | reading |
|---|---|---|
| **P1 PASS** | `remaining` <= **12 000** (>= 0.55 assignments closed per run, 3x DR3) | the 63 % is a driving backlog and bulk is the right instrument; "mostly closes" is earned |
| **P1 PARTIAL** | `remaining` in **12 000 - 20 000** (0.19-0.55/run) | bulk beats or matches the rooted round but does not clear the backlog; the residual needs a third instrument |
| **P1 FAIL** | `remaining` > **20 000** (< 0.19/run, worse than DR3) | the "63 % is an ordinary driving backlog" reading is REFUTED; the seeded dimensions are not free either, and §4's finding generalises to the whole residual |

Two secondary, independently falsifiable predictions:

* **P2** — if bulk preferentially closes the non-identity half, the
  IDENTITY-constrained share of the residual witnesses must RISE from 37 %
  to **> 55 %**. If it stays near 37 %, bulk is closing both kinds in
  proportion (or neither), and the §10.5 split does not describe what is
  actually limiting coverage. Measured with ONE classifier run against BOTH
  pass 3's witnesses (the 37 % baseline, re-derived, not quoted) and the new
  pass's, so the instrument is identical on both sides.
* **P3** — `demand_sets` and `tree_missing`. The wall opened new ground once
  already (§9.6: 411 -> 417 nodes, four new branches). 22 000 fresh bulk runs
  may do it again. Pre-registered: if `tree_missing > 0` after this pass, that
  is NOT a regression, it is §16's mutability, and those branches are driven
  with `_tree_root.py` before any completion claim is made.

Also pre-registered, so it cannot be read as a post-hoc excuse: `missing` and
`remaining` are different quantities. `MISSING` is a capped witness count
(sets-with-a-gap x `max_missing_per_clique`, held at **16**); `remaining` is
the exact assignment gap from `_exact_enum.py` with `bounded_cliques=0`. P1 is
judged on `remaining`. `MISSING` is reported but is not the criterion.

### §12.4 The identity residue — §10.5's diagnosis is REFUTED

§10.5 classified 37 % of the 8 807 blocking witnesses as "not a driving problem
at all", on the ground that identity values are "DERIVED by the mocks, not read
from a seed: `_demand_root.py` writes the Z3 model's value into the seed dict
and nothing consumes it". **That is wrong for four of the five families, and it
is wrong in a way that is cheap to measure.**

The instrument (`_classify_residual.py`, new — one classifier, used on both
sides so a baseline and a post-drive number are never two different codes)
first reproduces §10.5's split on the SHIPPED `coverage_summary.json`:

```
missing=8811  combination=8807  demand_sets=1037  tree_missing=0
seeded-only        5632   63.9 %
ALSO identity      3171   36.0 %
derived row_type      4    0.0 %
identity families: _person_id=3353 _row_id=2339 _guid=506 __prior=425 _diaspora_handle=41
```

**Are those values seedable?** `concolic_targets.rb:568-580` (`symbolic_instance`)
mints EVERY column of a symbolic row through
`seed_for("<base>_<col>", default_int(col))` — `id`, `guid`, `person_id` and
`diaspora_handle` included. So a seed key exists by construction. Whether it is
CONSUMED is a measurement, and `_ident_seed_scan.py` (new) makes it: over an
800-dump sample, for every variable whose name ends in an identity suffix,
compare the value the runtime MINTED against the value the run was SEEDED with.

| family | minted | of those, seeded | seed honoured | distinct values seen |
|---|---|---|---|---|
| `_row_id` | 3 933 | 241 | **241 (100 %)** | 3 |
| `_guid` | 3 648 | 114 | **114 (100 %)** | 23 |
| `_person_id` | 2 857 | 256 | **256 (100 %)** | 3 |
| `_diaspora_handle` | 3 600 | 9 | **9 (100 %)** | 20 |
| `_rowN_row_id` (N>=2) | 970 | **0** | — | 3 (`2007`/`3007`/`4007`) |
| `_rowN_person_id` | 204 | **0** | — | 2 |

And the same check run against **the DR4 round's own 28 535 dumps**, which is
the round §10.4 called a negative result:

| family | seed keys written | var also minted | seed honoured | var NEVER minted |
|---|---|---|---|---|
| `_person_id` | 1 654 | 1 091 | **1 091 (100 %)** | 563 |
| `_row_id` | 942 | 911 | **911 (100 %)** | 31 |
| `_guid` | 355 | 275 | **275 (100 %)** | 80 |
| `_diaspora_handle` | 55 | 41 | **41 (100 %)** | 14 |
| `__prior` | 59 | **0** | — | **59** |

So DR4's identity seeds were honoured every single time the run reached the
variable. What failed is not seedability: it is that **34 % of the `_person_id`
seeds landed in runs that never minted the variable at all** — the base put the
run somewhere the cube cannot live. That is a base-selection problem, i.e. an
ordinary driving problem, and it is the same failure the `_guid` (23 %) and
`_diaspora_handle` (25 %) columns show.

Two families really are not seeded, and only one of them is in the residual:

* **`_rowN_` (N>=2)** — `targets.rb:1169`
  `symint("#{name}_row#{j}_#{pk2}", (1_000 * j) + 7, note: sql)`, a hardcoded
  `2007`/`3007`/`4007` with no `seed_for`. These exist only to render the
  preloader's `WHERE id IN (...)` note; they are **not in the residual at all**
  (0 of the 31 distinct identity names the residual constrains carries a
  `_rowN_`), so nothing turns on them.
* **`__prior`** — the load-time synthetic of `coverage_report.split_self_compare`.
  It has no runtime variable, so a seed for it is inert: 0 of 59 minted in DR4.
  That family is §12.5.

### §12.5 `__prior` is not free either — but it IS controllable, by the seed key's PRESENCE

The only expression in the whole residual that carries `__prior` is
`gon_helper.rb:6`'s

```
(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_id ==
 SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_id__prior)
```

— 425 witnesses, demanded 210 taken / 215 not_taken, `Gon.preloads[:contacts]`
compared against the CURRENT contact, i.e. a value produced by a PRIOR LOOP
ITERATION. By the brief's test this is case (b): no seed names it.

But "no seed names it" is not the same as "no input controls it". **Measured**,
over a 20 000-dump sample of the 227 973-dump corpus, on the runs that evaluate
the compare at all:

| `find_by_1_person_id` in `concolic_seeds` | outcome | runs |
|---|---|---|
| **absent** | `not_taken` | **187** |
| **present** (values 0, 1 and 2 all appear) | `taken` | **358** |

Zero exceptions either way; 0 runs record both sides in one walk. The seed
VALUE does not matter — 0, 1 and 2 all give `taken`.

**Ground-truth differential** (DISCIPLINE: a check is a differential, not an
instance test). One base, `dump_html_plain_dse0107_D13htm`, its 14 seeds
verbatim vs the same 14 with that ONE key deleted, same variant, both `rc=0`:

| | key seeded | self-compare outcomes | path conditions |
|---|---|---|---|
| control `dump_html_plain_dse0001_PRIORDIFFctl` | yes | **taken, taken** | 92 |
| flip `dump_html_plain_dse0001_PRIORDIFFflip` | no | **not_taken x3** | 112 |

So the honest reading of the `__prior` family is neither "free decision" nor
"unforceable": the right operand is **ALIASED to the left** by
`call_interceptor.rb:142-144` (a result is named by WHEN it was called), and the
decision is a function of ONE seed key's PRESENCE. `_demand_root.py` could never
realise these cubes because it only ever ADDS keys to a base's seed dict — it
has no way to express "this key must be absent".

**No `targets.rb` change is proposed or made.** The boundary stays where it is:
the identity columns are already seedable, and nothing here makes a derived
value seedable that was not.

What is changed is the per-batch demand tool. `_demand_root.py` gains the
SELF-COMPARE rule (`UNSEED_SELFCMP=1`, default on; backup
`_bak_demand_root_pre_unseed.py`):

1. a cube demanding the compare TAKEN puts `V` in the seed dict;
2. a cube demanding it NOT TAKEN **deletes** `V` from the base's seeds, and the
   base search gains a HARD first-rank preference for a base that does not seed
   `V` (the child is the base verbatim plus the demand, so a base carrying `V`
   hands the child the taken side whatever we write);
3. because `V` is then not ours to set, every companion conjunct
   `(V == X)` — 363 of the 425 witnesses also constrain
   `find_by_1_person_id == devise_user_first_1_person_id`, the
   `people_helper.rb:81-86` "is this me?" compare — is satisfied by moving `X`
   to the value `V` actually takes unseeded, read off that base's own
   `symbolic_vars`.

**The falsifier**, so this is not an unfalsifiable repair: after a demand round
run with the rule, the 425 self-compare witnesses must convert at a rate
comparable to the seeded-only witnesses. If they still convert at DR4's
0.014/run, the presence-control reading is wrong and the family goes back to
being a declaration question.

### §12.6 The (a)/(b) split, with counts

Re-classified with the refined instrument (`__prior` separated from the seedable
identity columns, `_rowN_` counted separately), over the same 8 807 blocking
witnesses of pass 3:

| class | witnesses | share | reading |
|---|---|---|---|
| no identity variable at all | **5 632** | 63.9 % | the bulk backlog (§12.3's P1) |
| **(a)** seedable identity only — `_person_id`, `_row_id`, `_guid`, `_diaspora_handle` | **2 746** | 31.2 % | DERIVED FROM A SEEDED INPUT, seed honoured 100 % of the time the run reaches it. An ordinary demand round; the failures are base/context, not seedability |
| **(b)** also the `__prior` self-compare | **425** | 4.8 % | no seed key names it — but the decision is controlled by the LEFT operand's seed key PRESENCE (§12.5), so it is ALIASED, not foreclosed, and it is drivable with the new rule |
| `_rowN_` (hardcoded `1000j+7`, genuinely unseeded) | **0** | — | not in the residual |
| derived `_row_type` | 4 | 0.0 % | — |

So of the 3 171 "identity" witnesses §10.5 called undrivable, **2 746 (86.6 %)
are case (a) and drivable today**, 425 are case (b) by the letter of the brief's
test and drivable with a driver change that touches no boundary, and **0 are
unforceable by construction**. There is no §16b refinement to propose and no
declaration to file: the demand over these variables is not an artefact.

### §12.7 Two instrument defects found on the way to the census — both fixed, one is a `src/` case

The first census attempt died three times before producing a number, and the
way it died is worth recording because it looked like a stall.

**(a) The launcher hid a SIGKILL, and the log's tail was stale.**
`_c9_census.sh` as first written did not check the exit code and did not run
`python3 -u`. The process was killed by its own cgroup (`rc=137`,
`MemoryMax=8G`) and, because stdout was block-buffered, the log ended in the
middle of a phase with no traceback — indistinguishable from "still running".
A wait loop polling `pgrep -f _exact_enum.py` then waited forever, because that
pattern **matches the waiting shell's own `bash -c` command line**. Both are
fixed: the script runs `python3 -u`, prints and CHECKS `rc` (naming 137 as a
cgroup kill), and prints the PID; waiters poll the launcher PID with
`kill -0`, never a `pgrep -f` of the script's own name.

**(b) The engine's outcome-profile key costs ~2 objects per expression per
profile, and it is RETAINED.** With `-u` the kill localised to one loop:

```
[mem] entering build_universe: RSS 2.55 GB runs=96148
[mem] CoverageChecker built:   RSS 2.55 GB
<killed, 11G>
```

`src/concolic_engine/coverage.py:717` (and the census's port of it) keys the
profile table with
`frozenset((e, frozenset(o)) for e, o in outcomes.items())`. That key is a
tuple plus a 1-2 element frozenset PER EXPRESSION, kept alive for every
DISTINCT profile purely to be a dict key. At 76 990 distinct profiles (pass 3)
it fits; at **96 148** it does not — three kills, at 8G and twice at 11G.

The census is batch-local, so it now keys on a 16-byte blake2b digest of the
canonical serialisation of the same items — the same equivalence relation
(collision probability over 10^5 profiles ~1e-29), with the profile VALUES
untouched, so every later step reads exactly what it read before.

**Verified, not asserted** — the digest build re-run on the IDENTICAL old
pruned list (92 102) that produced `_c8_census_dr4`:

| | DR4 (frozenset key) | now (digest key) |
|---|---|---|
| evaluation sets -> demand sets | 1428 -> 1042 | **1428 -> 1042** |
| foreclosures inferred / gates | 9268 / 367 | **9268 / 367** |
| `tree_missing` | 0 | **0** |
| nodes(active) / untracked / pinned | 408 / 9 / 1 | **408 / 9 / 1** |
| satisfiable / covered / remaining | 65 140 / 40 946 / 24 194 | **identical** |
| `bounded_cliques` | 0 | **0** |
| foreclosures applied / leaf groups | 3644 / 3585 | **3644 / 3585** |
| wide sets / their remaining mass | 48 / 8 354 | **48 / 8 354** |
| memory at "profiles built" | (OOM at 11G on the new list) | **3.35 GB** |

**Byte-identical on every number.** The peak fell from ">11 GB" to 3.46 GB.

**`src/` case, REPORTED not made** (source-code discipline): the same key is in
`src/concolic_engine/coverage.py:717`, so the coverage PASS carries the same
cost on the same corpus. The fix is the same three lines. It is a pure
memory change with no verdict content — the equivalence is verified above on a
real corpus — but it is `src/`, and this batch does not edit `src/`.

### §12.8 THE BULK RESULT — pre-registration P1 FAILED, and not narrowly

Census on `_snapshot_pruned_20260910_171301.txt` (96 148 profiles, corpus
249 975), `bounded_cliques=0` so every figure is exact:

```
evaluation sets=1462 -> demand sets=1042
foreclosures inferred: 9235 (gate,outcome)->decision pairs over 369 gates
tree_missing=0  tree_complete=True
nodes(active)=408 untracked=9 pinned=1 cliques=1042
EXACT: nodes=408 cliques=1042 satisfiable=65140 covered=40955 remaining=24185 bounded_cliques=0 wall=104s
FORECLOSURE: applied=3644 pairs; leaf groups=3585
wide sets (width>=13): 48 holding 8354 of the remaining
```

| | before C33D (227 973) | after C33D (249 975) | delta |
|---|---|---|---|
| demanded assignments | 65 140 | **65 140** | 0 |
| covered | 40 946 | **40 955** | **+9** |
| remaining | 24 194 | **24 185** | **-9** |
| uncovered | 37.14 % | **37.13 %** | -0.01 pp |
| demand sets | 1 042 | **1 042** | 0 |
| evaluation sets | 1 428 | 1 462 | +34 |
| `tree_missing` | 0 | **0** | 0 |
| nodes (active) | 408 | **408** | 0 |
| wide sets / mass | 48 / 8 354 | 48 / 8 354 | 0 |

**22 000 runs closed NINE assignments: 0.0004 per run.**

Against the pre-registration of §12.3:

| criterion | threshold | result |
|---|---|---|
| P1 PASS | remaining <= 12 000 | **no** |
| P1 PARTIAL | 12 000 - 20 000 | **no** |
| **P1 FAIL** | **remaining > 20 000 (< 0.19/run)** | **YES — 24 185, at 0.0004/run** |

It is not a near miss. Bulk diversity is **35x worse than DR4** (0.014/run,
already published as a negative result) and **460x worse than DR3**
(0.185/run). The pre-registered reading of a FAIL therefore stands as written:
**the "63 % is an ordinary driving backlog" claim of §10.5 is REFUTED, and §4's
finding — that the seeded dimensions are not free — generalises to the whole
residual, not just to the identity half.**

**P3 held**: `tree_missing` stayed 0, `nodes` stayed 408, `demand_sets` stayed
1 042. The 22 000 runs opened no new decisions and no new demand; the 34 new
evaluation sets all projected into demand sets that already existed. The
prune tells the same story from the other side: the 22 000 runs produced only
**4 046 new distinct outcome profiles** (96 148 - 92 102), i.e. 82 % of them
re-walked a profile the corpus already had.

So the whole "8 000 x 7 in full" budget — the one thing §10.5 named as the
cheapest remaining lever, and the reason the previous agent's shipped-driver
defect looked expensive — is worth **nine assignments**. That question is now
settled and does not need asking again.

### §12.9 The coverage PASS cannot run on this corpus — a `src/` memory case, priced

The pass was launched exactly as the brief specifies (own slice,
`MemoryMax=10G`, `unset JAVA_TOOL_OPTIONS`, `DUMP_LIST` = the pruned snapshot,
`MAX_MISSING_PER_CLIQUE=16`) and was **SIGKILLed by its cgroup**:

```
[2026-09-10T18:39:39] pass c9 list=_snapshot_pruned_20260910_171301.txt cap=10G free=8GB
loaded 96148 runs (0 unparseable); peak RSS 2471 MB
[assumptions] ... exprs=417 co-evaluated-pairs=29888
[2026-09-10T18:49:14] pass c9 EXIT rc=137
```

It died at the same place the census did, and for the same reason:
`CoverageChecker._analyze_coevaluation`'s first loop,
`src/concolic_engine/coverage.py:717`. `coverage_summary.json` was NOT touched
(it is still pass 3's, mtime 14:46).

**Priced, on this corpus, with the runs already loaded** (`_mem_probe.py`, new
— loads through the batch's own load path, runs the loop with each key, builds
no universe and writes nothing):

| profile key | distinct profiles | memory ON TOP of the loaded runs |
|---|---|---|
| `frozenset((e, frozenset(o)) …)` — the engine's | 96 148 | **> 10.6 GB (OOM-killed at MemoryMax=13G, runs resident 2.40 GB)** |
| blake2b-16 digest of the same items | 96 148 | **0.91 GB** (census: RSS 2.55 -> 3.46 GB) |

So the pass needs >13 GB on a 15 GB box shared with another endpoint's agent,
and the fix costs 0.91 GB. The verdict equivalence of the digest key is
**verified**, not argued — §12.7's table is byte-identical on all fourteen
numbers of a real census.

**This is reported, not made.** `coverage_report.py`, `_exact_enum.py` and
`_mem_probe.py` are batch-local and carry the fix; `src/concolic_engine/
coverage.py:717` does not, and this batch does not edit `src/`. The change is
three lines, has no verdict content, and is what unblocks the pass on this
endpoint (and on `posts_show`, whose corpus is larger still).

Note the shape of the growth, because it matters for whoever takes the case:
the profile TABLE barely grew — 4.0 M -> 4.1 M (expr, profile) pairs, +3 %,
mean 43.1 -> 42.9 distinct exprs per profile — while the memory went from
"fits in 6 GB at pass 3" to ">13 GB". The cost is not the retained table; it is
the per-run CHURN of ~43 tuples and ~43 one-element frozensets built for EVERY
run (96 148 of them) merely to be a dict key, and the arena fragmentation that
leaves behind. A digest builds one bytes object per run instead.

### §12.10 WHY driving stopped working — 70 % of every rooted seed is never evaluated

The pre-registered FAIL of §12.8 says the seeded dimensions are not free. Here
is the mechanism, measured on **DR4's own 28 535 dumps** (2 500 sampled,
125 438 seed keys), by comparing every seed key a run was given against the
value that run actually minted:

| | seed keys | share |
|---|---|---|
| honoured (variable minted, value equals the seed) | 36 346 | **29.0 %** |
| contradicted (variable minted, value differs) | 1 089 | **0.9 %** |
| **never evaluated** (the run never minted the variable at all) | **88 003** | **70.2 %** |

Per run, the median share of its own seeds that are never evaluated is
**0.66**, p90 **0.80**.

So the seeds are not being overridden by the app — when a seeded variable is
reached it takes the seeded value 97 % of the time (36 346 of 37 435). The
failure is that **the run never gets to the variable**. A demanded cube is a
conjunction: every one of its conjuncts must be evaluated in the same walk, and
a rooted seed that reaches 30 % of its own keys realises the whole cube only by
luck.

That is a statement about the ENDPOINT, not about the seeder: which statements
a notifications render issues is decided by gates upstream of them (the note
type, the target's STI type, whether the collection is empty, whether the text
carries a mention), and those gates FORECLOSE most of the variables the cube
names. §16b's inferred foreclosure already removes 3 644 (gate, outcome) pairs
from the demand; what this measurement says is that the same structure is
present at a finer grain than the foreclosure inference can see from the
corpus, and it is what makes the remaining 24 185 assignments so expensive.

**This also explains the DR3 > DR4 > bulk ordering** that looked paradoxical:

| method | runs | assignments closed | per run |
|---|---|---|---|
| DR3 — rooted, 1 base per witness | 15 630 | 2 897 | 0.185 |
| DR4 — rooted, 3 bases per witness | 28 535 | 396 | 0.014 |
| **C33D — bulk v3.3, 22 000 fresh seeds** | **22 000** | **9** | **0.0004** |

A ROOTED seed inherits a real run's whole context and so reaches ~30 % of its
own keys; a BULK seed invents all 270 keys at once and reaches almost none of
the ones that matter, because the context it invents is not one the app
produces. The more a method departs from a real observed walk, the worse it
does. That is the opposite of §10.5's expectation, and it is why the "63 %
ordinary driving backlog" reading fails.

---

## §13. Phase-2 close-out (2026-09-10, coordinator-directed)

Coordinator ruling after §12.8/§12.10: **stop driving.** 22 000 bulk runs bought
9 assignments and 70 % of every rooted seed is never evaluated, so more runs will
not close the 24 122. What follows is analysis on the corpus already in hand,
plus the `src/` proposal, and then this agent stops.

### §13.1 DR5 — the SELF-COMPARE rule passed its pre-registered falsifier

Run before the stop ruling, and reported here because it is the falsifier §12.5
registered. `_demand_root.py` with `ONLY_SELFCMP=1 UNSEED_SELFCMP=1` over the
425 self-compare witnesses of pass 3: **402 rooted seeds** (html_plain 201,
html_typed 201 — the compare occurs in no other variant), **215 cubes needing an
UNSEEDED operand, 0 of them without a clean base**. Drive: **402 of 402
consumed, 0 aborts, both jobs first try.**

The branch was realised **402 of 402 times**, in exactly the pattern §12.5
predicted:

| left operand in `concolic_seeds` | self-compare outcome | runs |
|---|---|---|
| absent (the rule DELETED it) | `not_taken` | **197 / 197** |
| present | `taken` | **205 / 205** |

and the companion `find_by_1_person_id == devise_user_first_1_person_id` compare
was driven both ways in the same runs (1 003 taken / 805 not_taken), so the
value-repair of rule (3) works too.

Census after (pruned 96 299, corpus 250 377):

| | after C33D | after DR5 | delta |
|---|---|---|---|
| demanded | 65 140 | 65 156 | +16 |
| covered | 40 955 | **41 034** | **+79** |
| remaining | 24 185 | **24 122** | **-63** |

**63 assignments in 402 runs = 0.157 per run.** The registered falsifier was
"if these still convert at DR4's 0.014/run the presence-control reading is
wrong". They convert at **11x DR4** and **390x the bulk rate**, in line with
DR3's best-ever 0.185. So the reading holds: the `__prior` family was never
foreclosed and never a declaration question — it was a driver that could only
ADD seed keys, against a decision controlled by a key's ABSENCE.

For the record, the full method table now reads:

| method | runs | assignments closed | per run |
|---|---|---|---|
| DR3 rooted, 1 base/witness | 15 630 | 2 897 | 0.185 |
| **DR5 rooted + SELF-COMPARE rule (425 witnesses)** | **402** | **63** | **0.157** |
| DR4 rooted, 3 bases/witness | 28 535 | 396 | 0.014 |
| C33D bulk v3.3, the full remaining budget | 22 000 | 9 | **0.0004** |

### §13.2 PROPOSAL for `src/` — the outcome-profile key (do not merge without owner sign-off)

**File / line.** `src/concolic_engine/coverage.py:716`, inside
`CoverageChecker._analyze_coevaluation`, step 1:

```python
            if outcomes:
                key = frozenset((e, frozenset(o)) for e, o in outcomes.items())
                profiles.setdefault(key, outcomes)
```

**Proposed:**

```python
            if outcomes:
                # The key only has to be a stable identifier for the profile;
                # the frozenset-of-pairs form builds one tuple and one 1-2
                # element frozenset PER EXPRESSION for EVERY run, and that
                # churn (not the retained table) is what costs the memory.
                key = hashlib.blake2b(
                    ";".join(f"{e}:{'1' if True in outcomes[e] else ''}"
                             f"{'0' if False in outcomes[e] else ''}"
                             for e in sorted(outcomes)).encode(),
                    digest_size=16).digest()
                profiles.setdefault(key, outcomes)
```

(plus `import hashlib`). Nothing else changes: the dict VALUES — the `outcomes`
maps every later step reads — are untouched, and `run_outcomes` is still
`list(profiles.values())`.

**Why it is needed.** Measured on notifications_index's 96 148-profile pruned
corpus, with the runs already loaded (2.40 GB resident):

| key | memory ON TOP of the loaded runs |
|---|---|
| current `frozenset(...)` | **> 10.6 GB** — OOM-killed at `MemoryMax=13G` |
| proposed digest | **0.91 GB** |

The coverage PASS is consequently un-runnable on this endpoint: it was
SIGKILLed (`rc=137`) at `MemoryMax=10G` immediately after its `[assumptions]`
line, which is this loop. posts_show's corpus is larger still.

**Why it is safe.** The change replaces one equivalence-class representative
with another for the same equivalence class: two profiles get the same key iff
they have the same set of (expr, outcome-set) pairs, before and after. The only
new failure mode is a 128-bit digest collision, whose probability at 10^5
profiles is ~1e-29 — smaller than the probability of a bit flip in the table
it replaces.

**Verified, not argued.** The identical change is already carried by this
batch's `_exact_enum.py`, and the census was re-run with it on the IDENTICAL
92 102-dump pruned list that produced `_c8_census_dr4`:

| | frozenset key (DR4) | digest key |
|---|---|---|
| evaluation sets -> demand sets | 1428 -> 1042 | **1428 -> 1042** |
| foreclosures inferred / gates | 9268 / 367 | **9268 / 367** |
| `tree_missing` / `tree_complete` | 0 / True | **0 / True** |
| nodes(active) / untracked / pinned | 408 / 9 / 1 | **408 / 9 / 1** |
| satisfiable / covered / remaining | 65 140 / 40 946 / 24 194 | **identical** |
| `bounded_cliques` | 0 | **0** |
| foreclosures applied / leaf groups | 3644 / 3585 | **3644 / 3585** |
| wide sets / remaining mass | 48 / 8 354 | **48 / 8 354** |

Fourteen numbers, byte-identical.

**Falsifier / acceptance test.** Run any closed endpoint's pass twice, once with
each key, on the same `DUMP_LIST`, and diff `coverage_summary.json` with the
`total_runs`/timing fields masked. They must be identical. If any number moves,
reject the change — the digest is not doing what this proposal claims.

**Rule T.** This is `src/`, so it is a Rule T event by policy and the
coordinator/owner decides. The argument that it does NOT void a closed endpoint
is the equivalence above (the demand universe, the foreclosure inference, the
covering cubes and `tree_missing` are all functions of `run_outcomes`, which is
unchanged), but that argument is offered for review, not acted on. **Not
implemented by this batch.**

### §13.3 Is the residue REACHABLE? — the multi-gate-foreclosure hypothesis, tested and REFUTED

**The question.** §16b infers foreclosure PAIRWISE: `(g,o)` forecloses `d` only
if no run with `g=o` evaluates `d`. That is blind to DISJUNCTIVE reachability —
if `d` is evaluated when `g1=a` OR `g2=b`, then runs with `g1!=a` still evaluate
`d` (via `g2=b`), so no pairwise foreclosure is inferred, and the cube
`{g1!=a, g2!=b, d=x}` stays DEMANDED even though no run can ever be in a
position to walk it. The hypothesis under test is that this is the residue.

**The instrument.** The leaf-group formulation already carries the test, so no
new semantics were invented. A leaf group is a pair `(pre, surv)`: a gate
prefix and the decisions that survive it. The census already computes, per
group, the set of observed profiles whose evaluated members of that demand set
are EXACTLY `surv` and which agree with `pre` — that is exactly "some run
co-evaluated these decisions under a compatible gate assignment". So:

* `cubes >= 1` -> **REACHABLE**: a run has walked this context; the group's
  uncovered assignments are an honest driving backlog.
* `cubes == 0` -> **MULTI-GATE-FORECLOSED**: no run ever has; every one of the
  group's `sat` assignments is demanded by the declared model and unreachable in
  the corpus.

`_exact_enum.py` gains `REACH_SPLIT=1` (batch-local, off by default; the census
numbers are untouched — it only accumulates what the loop already computes) and
writes `_reach_split.json`. Run on `_snapshot_pruned_20260910_192233.txt`
(96 299 profiles, corpus 250 377).

**The answer.**

```
=== REACHABILITY SPLIT of the remaining assignments ===
  leaf groups: 3398 with an observed compatible walk, 185 with NONE
  demanded 65156  covered 41034  remaining 24122
  REACHABLE remaining        22562   93.5 %
  MULTI-GATE-FORECLOSED       1560    6.5 %
```

**The hypothesis is REFUTED.** Multi-gate foreclosure is real and it is
measurable, but it is **6.5 %** of the residue, in **185 of 3 583** leaf
groups. 93.5 % of the 24 122 remaining assignments are over decisions that
runs in this corpus HAVE walked together, under the very gate assignment the
cube demands. They are not unreachable. They are undriven.

**MULTI-GATE-FORECLOSED — the structure, gates named.** All 185 groups are in
WIDE sets (width 12-20: 17x75, 19x32, 18x24, 14x20, 16x12, 20x12, 13x8, 12x2)
and every one of them fixes `devise_user_first_1_person_not_found`. The
recurring shape is a conjunction of a note-type ordinal with two finders'
outcomes. The four largest (sat=32 each, sets #32-35, width 14, 13 survivors)
are the same cube on the four `to_ary_notifications_*` statement aliases:

```
  Relation_to_ary_notifications_cf379872_rows > 1              = TAKEN
  FinderMethods_devise_user_first_1_person_not_found == True   = not_taken
  FinderMethods_find_by_1_not_found == True                    = not_taken
  FinderMethods_find_by_1_person_profile_not_found == True     = not_taken
  (find_by_1_person_id == devise_user_first_1_person_id)       = not_taken
  FinderMethods_find_by_2_not_found == True                    = TAKEN
  ..._row_recipient_not_found == True                          = not_taken
  ..._row_target_not_found == True                             = not_taken
```

i.e. *"a multi-row notification list whose recipient and target both resolve,
whose `find_by_1` hits AND whose profile is present, but whose `find_by_2`
MISSES"*. Across all 185 groups, two gates never vary:
`find_by_2_not_found = TAKEN` together with
`find_by_1_person_profile_not_found = not_taken` in 24 groups, and
`SYM_NOTE_TYPE_PROFILE == 7` / `== 0` pinned `not_taken` in 155 / 135 groups.
The two finders are not independent in the app — the second lookup is issued on
a row the first one already resolved — but §16b's pairwise inference cannot see
that, because there ARE runs where `find_by_2` misses (with a different note
type) and there ARE runs where `find_by_1` hits.

**REACHABLE — where the mass is.** 22 562 assignments over 3 398 leaf groups.
The largest per-set remainders are `set#92-95` (width 9, 473/469/474/465) and
`set#16-19` (width 17, 394/391/377/366) — the four-way alias families again.
The census's own accounting puts 8 328 of the remaining in the 48 wide sets
(>=13), so about 15 800 of the reachable mass is in NARROW sets. (Member names
were not extracted for these; that needs another universe build and the
coordinator's ruling was to stop.)

**Which fix does this decide? All three, in these proportions:**

1. **Seeding — 93.5 % (22 562).** Reachable, so no semantics change can remove
   it and no declaration would be honest. But "reachable" is not "cheap":
   at DR5's best-ever rooted rate (0.157/run, §13.1) that is **~144 000 runs**;
   at DR4's 0.014 it is 1.6 M; at the bulk rate it is never. And §12.10 says
   why — 70 % of every rooted seed is never evaluated. **The lever that would
   change the price is not more runs but a seeder that can reproduce a
   CONTEXT**, i.e. root a seed on a real walk and flip only what the cube names
   (which is what `_tree_root.py` and the SELF-COMPARE rule do, and they are the
   only two things this campaign found that convert at >0.15/run).
2. **`src/` semantics — 6.5 % (1 560).** A genuine §16b refinement, and the
   test above IS the refinement: **demand only cubes that some observed
   evaluation profile is compatible with** (equivalently: infer foreclosure over
   gate CONJUNCTIONS, not just pairs). It is exactly the leaf-group check the
   census already performs, so the engine has the information and does not use
   it. This is worth filing, but note it does not change the verdict tonight:
   applying it would leave 22 562 remaining and `complete` still False.
3. **A declared residue — 0.** Nothing here needs a declaration. Every one of
   the 185 unreachable groups is a consequence the engine could infer for
   itself under (2); declaring them by hand would be the kind of "these can
   never co-occur" argument §16 already deleted 55 737 of.

### §13.4 State at hand-off (2026-09-10 ~20:00 UTC)

| | |
|---|---|
| corpus | **250 377** dumps (phase-2 start 227 973; +22 402) |
| pruned equivalent | 96 299 — `_snapshot_pruned_20260910_192233.txt` |
| `tree_missing` | **0** (`tree_complete: true`) |
| demanded / covered / remaining (exact, `bounded_cliques=0`) | **65 156 / 41 034 / 24 122** |
| uncovered | **37.0 %** (phase-2 start 37.1 %) |
| of the remaining: REACHABLE / MULTI-GATE-FORECLOSED | **22 562 (93.5 %) / 1 560 (6.5 %)** |
| demand sets | 1 042 (unchanged all phase) |
| `complete` | **False**, and not claimable tonight |
| shipped `coverage_summary.json` | STILL pass 3 (183 808-dump snapshot, mtime 14:46) — the phase-2 pass could not run, §12.9 |

**Blockers, in the order they bite:**

1. **The coverage PASS cannot run on this corpus** — `src/coverage.py:716`,
   >10.6 GB vs 0.91 GB. Proposal in §13.2, verified equivalent, not
   implemented. Until it lands there is no fresh `coverage_summary.json`, no
   `COMPLETE=` line and no fresh witness set for this endpoint (or for
   posts_show).
2. **22 562 reachable assignments at ~0.157/run best case.** Not a declaration
   problem and not a semantics problem; a cost problem, and the campaign has
   now measured all four methods that were available (§13.1's table).
3. **1 560 assignments the engine demands and no run can walk** — the §16b
   conjunction refinement of §13.3(2).

**Not done, and why:** the extraction
(`_extract_notifications_index_streaming.py`, ready, never run), the full
engine run with the gate, and `_c7_audits.sh`. All three are gated on
`missing == 0`, which is 24 122 away, and the coordinator's ruling was to stop
at the honest number rather than spend the night on runs that close 0.0004
assignments each.

**Files added this phase** (all batch-local; `src/` and `concolic_targets.rb`
untouched): `_classify_residual.py`, `_ident_seed_scan.py`, `_mem_probe.py`,
`_prune_incremental.sh`, `_c9_census.sh`, `_c9_pass.sh`, `_reach_split.json`.
**Changed:** `_chunk_drive.sh` (`DRIVE_PAR`), `_demand_root.py` (SELF-COMPARE
rule + `ONLY_SELFCMP`; backup `_bak_demand_root_pre_unseed.py`),
`_exact_enum.py` (digest profile key, progress/RSS prints, `REACH_SPLIT`;
backup `_bak_exact_enum_pre_reach.py`).

---

## §14. The `src/` memory fix is IN, and the pass runs again (2026-09-10, later)

Coordinator authorisation: implement §13.2 as proposed (performance only, no
semantic change), prove the equivalence the way the proposal did, and then
resume driving with a new seeding method (§15).

### §14.1 What was changed in `src/`

`src/concolic_engine/coverage.py`, three hunks, no other `src/` file:

1. `import hashlib` next to `import dataclasses`.
2. A new module-level `profile_key(outcomes) -> bytes` beside the other
   step-helper functions (`_outcome_constraint`, `_combo_constraint`,
   `maximal_sets`), carrying the docstring that names this as the 2026-09-10
   memory fix with the measured numbers (>10.6 GB -> 0.91 GB, OOM at
   `MemoryMax=13G`, ~43 exprs x 96 148 runs, collision ~1e-29).
3. Step 1's key line:

```python
             if outcomes:
-                key = frozenset((e, frozenset(o)) for e, o in outcomes.items())
-                profiles.setdefault(key, outcomes)
+                # KEY only — the dict VALUE is the profile itself, and that is
+                # what every later step reads (`run_outcomes` below).
+                profiles.setdefault(profile_key(outcomes), outcomes)
```

**Requirement (a) — the digest is only a KEY.** `profiles` is still
`digest -> one representative profile`, `run_outcomes = list(profiles.values())`
is unchanged, and `grep -n 'profiles\|run_outcomes'` over the file confirms the
key is never read back: every later step (evaluation sets, `infer_foreclosures`,
the covering-cube loop, `_unobserved_sides`) reads the VALUES. The one
deviation from §13.2's literal text is that the expression was lifted into a
named function instead of being inlined — because requirement (c) needs the
key to be testable, and because `_exact_enum.py` now imports it rather than
carrying a copy.

### §14.2 Requirement (b) — verdict equivalence, re-measured

`_exact_enum.py`'s own `_profile_key` was DELETED and replaced by
`from concolic_engine.coverage import profile_key as _profile_key`, so the
re-run is a test of the shipped code and not of a copy of it. The census was
then re-run on the IDENTICAL pruned list, `_snapshot_pruned_20260910_171301.txt`
(96 148 profiles), that produced the §12.8 census (`_c9_census_c9pruned.log`),
under `concolic-cov.slice`, `MemoryMax=5500M`, `python3 -u`, exit code checked:
`_c10_census_c10eq.log`, **rc=0**.

| | §12.8 census (`c9pruned`) | §14 census, src digest key (`c10eq`) |
|---|---|---|
| evaluation sets -> demand sets | 1462 -> 1042 | **1462 -> 1042** |
| foreclosures inferred / gates | 9235 / 369 | **9235 / 369** |
| `tree_missing` / `tree_complete` | 0 / True | **0 / True** |
| nodes(active) / untracked / pinned | 408 / 9 / 1 | **408 / 9 / 1** |
| cliques (demand sets) | 1042 | **1042** |
| satisfiable / covered / remaining | 65 140 / 40 955 / 24 185 | **identical** |
| `bounded_cliques` | 0 | **0** |
| foreclosures applied / leaf groups | 3644 / 3585 | **3644 / 3585** |
| wide sets / remaining mass | 48 / 8 354 | **48 / 8 354** |

Fourteen numbers, byte-identical — the masked verdict lines of the two logs
have the same md5 (`a91d82e0…`). And the proof is stronger than the fourteen:
the two censuses' `--json-out` files were diffed field by field and the ONLY
difference in the whole document is `wall_s` (104 -> 115, a timing). The
1042-entry `per_clique` array, the 25-entry `top_gates` list and the `widths`
histogram are all equal, which is §13.2's own acceptance test ("diff the
summary with the timing fields masked; if any number moves, reject").

### §14.3 Requirement (c) — the unit test

`src/test_coevaluation.py` gains section 8,
`test_distinct_profiles_get_distinct_keys_identical_ones_collapse`:

* two profiles differing only in ONE outcome must get different keys;
* two differing only in the EXPRESSION SET must get different keys;
* a both-sides expression is not the same profile as a one-side one;
* two IDENTICAL profiles built in different dict-insertion order must collapse
  to one key (a profile is a MAP, not a sequence);
* an exhaustive cross-check that `profile_key(x) == profile_key(y)` **iff**
  `frozenset((e, frozenset(v))…)` agrees — the equivalence relation itself,
  not a sample of it;
* end to end, that duplicating a run five times moves no verdict number
  (`demand_sets`, the missing set, `complete`).

### §14.4 Requirement (d) — the full `src/` suite

| suite | result |
|---|---|
| `test_symbolic.py` | rc=0, "All tests passed" |
| `test_interceptor.py` | rc=0, "All tests passed" |
| `test_path_explosion.py` | rc=0 |
| `test_assumptions.py` | rc=0 |
| `test_symbolic_func.py` | rc=0, "All tests passed" |
| `test_coevaluation.py` | rc=0, "All co-evaluation tests passed" (incl. the new one) |
| `test_query_ops.py` | rc=0 |
| `queries_from_runs/test_queries_from_runs.py` | **47 passed** (venv `queries_from_runs`, needs `sqlglot`) |
| `test_ruby_runtime.rb` | **65 passed, 0 failed** |
| `py_runtime/test_list_rep.py`, `ruby_runtime/test_list_rep.rb` | both OK |

Green. The work sits on top of the pre-existing uncommitted `src/` changes;
nothing was reverted and nothing was committed.

### §14.5 The PASS runs — the blocker of §13.4(1) is gone

`_c10_pass.sh` on `_snapshot_pruned_20260910_192233.txt` (96 299 profiles),
`concolic-cov.slice`, `MemoryMax=8G`, `MemorySwapMax=0`, `python3 -u`,
PID-based waiting, exit code checked:

```
[2026-09-10T20:10:27] pass c10p1 list=_snapshot_pruned_20260910_192233.txt cap=8G avail=6408MB
[2026-09-10T23:23:28] pass c10p1 EXIT rc=1
loaded 96299 runs (0 unparseable); peak RSS 2517 MB
OVERALL_COMPLETE=False;COMPLETION=False
COMPLETE=False;NODES=417;MISSING=8319;BLOCKING=8315;PCS=5750800
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
wrote .../coverage_summary.json in 11098.6s; peak RSS 3835 MB
  Elapsed (wall clock) time: 3:13:00
  Maximum resident set size (kbytes): 3927588
```

`rc=1` is `coverage_report.py`'s documented "not complete" exit, not a failure.

| | §12.9 (frozenset key) | §14 (digest key) |
|---|---|---|
| runs loaded / load peak | 96 148 / 2 471 MB | 96 299 / **2 517 MB** |
| what happened next | **SIGKILL, `rc=137`**, inside `_analyze_coevaluation`'s first loop at `MemoryMax=10G` | ran to completion |
| **peak RSS** | **>13 GB (killed)** | **3 927 588 kB = 3.75 GB** |
| coverage phase | never finished | 3 h 13 m, `solver_lost=0` |

The coevaluation loop cost **1.32 GB on top of the loaded runs** (3.84 GB peak
self-report minus the 2.52 GB load peak) where it previously cost >10.6 GB —
in line with §13.2's predicted 0.91 GB for the profile table itself, the rest
being the demand structures the loop feeds. `coverage_summary.json` is now
FRESH for the first time since pass 3: 96 299 runs, `demand_sets` 1042,
`tree_complete` true, 8 315 blocking witnesses (previous file: 183 808 runs,
mtime 14:46, kept as `_bak_coverage_summary_pass3_20260910_1446.json`).

---

## §15. Seeds built from the FORECLOSURE GRAPH — the method (2026-09-10, owner direction)

Two owner directions arrived during §14 and are adopted together. The first
replaced the seeding method:

> Use the counterexamples AND the graph structure. Per witness cube C over set
> S: for every member `d` of C and every inferred `(g, o)` that forecloses `d`,
> add `g != o` to the solver query, transitively for the gates of those gates —
> the model then carries the WALKABLE path, not just the leaf. Choose the base
> by COMPATIBILITY (§13.1's test), not richness. Audit the round's seed keys
> the way §12.10 did.

The second moved the batching to the driver and the targets to the enumerator:

> The batching should happen at the driver level; no solver-call batching in
> `src/`. Targets come from the exact enumerator, not the checker's witnesses:
> extend `_exact_enum.py` to EMIT every remaining cube. Build one graph-guided
> seed per remaining cube — all of them — in one batch. Re-enumerate (~100 s),
> not re-pass. `coverage_report.py` runs ONCE at the end, to certify.

### §15.1 The instrument

Four new batch-local tools. `src/` is not touched again — §14's memory fix is
the only `src/` change this agent makes.

* **`_forecl_dump.py`** — the inferred foreclosure relation, the declaration
  set and the assumption base for a snapshot, WITHOUT the 581-second
  maximal-clique projection. It runs steps 1, 3 and 4 of
  `CoverageChecker.check_coverage` and then §16b's own `infer_foreclosures`,
  imported from the engine. **Cross-checked**: on
  `_snapshot_pruned_20260910_192233.txt` it reports
  `active=408 untracked=9 pinned=1` and **9224 (gate,outcome)->decision pairs
  over 369 gates** — the census's numbers for that snapshot
  (`_c9_census_c9reach.log`) to the digit, in 552 s and 3.48 GB instead of
  ~680 s.
* **`_exact_enum.py` + `EMIT_REMAINING`** — the census already enumerates each
  leaf group's satisfiable assignments as a PRODUCT of per-component model
  lists and counts the covered ones; emitting them is one extra pass over the
  same product. Off by default, so the census numbers are untouched.
* **`_enable_root.py`** — the seeder: enabling closure, one Z3 solve,
  one compatible base, one seed, per remaining cube.
* **`_seed_audit.py`** — §12.10's per-key measurement plus a per-CUBE one.
* **`_xcheck_targets.py`** — the two implementations, checked against each
  other (§15.3).

### §15.2 Two things the method could have got wrong, and what was measured

**Foreclosure conflicts are not contradictions.** `(g, o)` forecloses `d` means
"no run with `g = o` evaluated `d`". It says NOTHING about a run that never
evaluates `g`. So when two members of one cube are foreclosed by OPPOSITE
outcomes of the same gate, the honest reading is "`g` must not be evaluated in
this walk" — not expressible as a Z3 constraint over `g`. The first
implementation called that a contradiction and classified 60 of 60 smoke cubes
as self-foreclosing. Such gates are now left FREE and counted. Measured:
**0 conflicts at depth 1**; they appear only in the transitive layers, where
the inferred relation is at its most over-approximated. The solve also backs
off the depth (3 -> 2 -> 1 -> 0) until it is SAT, and RECORDS the depth used.

**The overlay is still narrow.** §12.10's lesson stands: the Z3 model assigns
EVERY declared variable and its defaults are 0, so overlaying the whole model
seeds `len(...rows) = 0` and forecloses the very decisions the cube is about.
Only the variables named by the cube's members and by the ENABLING GATES are
overlaid — more than `_demand_root.py` overlaid (that is the point), far less
than the model. `V__prior` keys are dropped: they have no runtime variable
(§12.5), and measured on DR5's own 402 dumps they are that round's single
most-often "never evaluated" seed key (200 of 200 runs).

### §15.3 The enumerator and the checker AGREE — both directions

The owner asked for any disagreement between the enumerator's remaining set and
the checker's `missing[]` to be reported as a bug. There is none, and the check
was run two ways on the SAME snapshot.

**Inside the enumerator.** `EMIT_REMAINING` asserts, per leaf group, that the
number of assignments it EMITS equals `sat - covered` as counted by the
sum-of-disjoint-products accounting — two independent computations of the same
number (a product-and-filter enumeration vs a cube-subtraction count):

```
EMIT_REMAINING: wrote 24122 remaining assignments (counted remaining = 24122)
EMIT_REMAINING: emitted count == counted remaining, on every leaf group
                — the two computations agree exactly.
```

and the enumeration reproduces §13.1's census exactly:
`satisfiable=65156 covered=41034 remaining=24122 bounded_cliques=0`,
`REACHABLE 22562 (93.5 %) / MULTI-GATE-FORECLOSED 1560 (6.5 %)`.

**Enumerator vs engine.** `_xcheck_targets.py` takes every one of the 8 315
blocking `node_constraint` cubes the §14.5 pass reported and asks whether some
emitted remaining assignment AGREES with it on every expression it fixes:

```
enumerator remaining: 24122 (REACHABLE 22562, MULTI-GATE-FORECLOSED 1560)
checker missing (blocking): 8315 (truncated=True, demand_sets=1042)
checker cubes witnessed by an enumerator remaining assignment: 8315 / 8315
AGREE
```

8 315 of 8 315. The checker's list is a CAP (`MAX_MISSING_PER_CLIQUE=16`,
`truncated: true`) on the same set the enumerator names in full — which is
exactly why the targets now come from the enumerator: **24 122 named in 101 s
against 8 315 named in 3 h 13 m.**

---

## §16. The 1 560 — four owner directions, all four measured (2026-09-11)

The owner ruled that the 1 560 MULTI-GATE-FORECLOSED cubes be handled with
`OneSideUntrackedPathAssumption`, then refined the ruling twice: first to
measure the over-relaxation per pin before installing, then to test whether a
single pin at the ROOT would do, then to test whether the two "impossible"
finder outcomes are really one symbolic value with two names. All three tests
were run. **No pin is installed**, and the reason is measured, not argued.

### §16.1 Per-pin over-relaxation — nonzero for EVERY pin

The refinement's instruction: "For each (expression, side) you would pin, count
the remaining cubes that CONTAIN that side but are NOT among the 1 560... If
the legitimate count is 0 for every pin: install. If it is nonzero for any pin:
do NOT install that pin unconditionally."

No single `(expr, side)` separates the two populations at all: **0 of the pairs
appearing in the 1 560 are absent from the 22 562 reachable ones.** The
least-collateral greedy cover needs **16 pins** to account for all 1 560, and
every one of them removes legitimate reachable demand:

| impossible covered | LEGITIMATE also lost | side | expression |
|---|---|---|---|
| 128 | 16 | taken | `...to_ary_notifications_c7e6a7ca_row_target_not_found` |
| 128 | 24 | taken | `...to_ary_notifications_cf379872_row_target_not_found` |
| 128 | 24 | taken | `...to_ary_notifications_10254800_row_target_not_found` |
| 128 | 40 | taken | `...to_ary_notifications_3aa8587a_row_target_not_found` |
| 36 | 12 | taken | `...c7e6a7ca_row_target_mentions_contains...` |
| 36 | 15 | taken | `...cf379872_row_target_mentions_contains...` |
| 36 | 18 | taken | `...10254800_row_target_mentions_contains...` |
| 36 | 18 | taken | `...3aa8587a_row_target_mentions_contains...` |
| 208 | **443** | taken | `Core__ClassMethods_find_by_1_not_found` |
| 208 | **520** | not_taken | `FinderMethods_find_by_3_not_found` |
| 32 | 112 | taken | `FinderMethods_find_by_1_not_found` |
| 208 | **977** | taken | `FinderMethods_find_by_3_not_found` |
| 72 | **418** | not_taken | `Core__ClassMethods_find_by_1_profile_not_found` |
| 72 | **599** | taken | `Core__ClassMethods_find_by_1_profile_not_found` |
| 8 | 67 | taken | `SYM_POST_STI == 1` |
| 96 | **3 498** | not_taken | `SYM_NOTE_TYPE_PROFILE == 5` |

**Distinct legitimate reachable remaining cubes the 16 unconditional pins would
also delete: 5 582 of 22 562 — 24.7 %.** The three pins the ruling named fare
worse still:

| pin | impossible covered | LEGITIMATE also lost |
|---|---|---|
| `find_by_2_not_found :: taken` | 416 | **1 063** |
| `find_by_1_person_profile_not_found :: not_taken` | 416 | **2 249** |
| `devise_user_first_1_person_not_found :: not_taken` | 1 136 | **8 118** |

An example of a legitimate reachable cube that `find_by_3_not_found :: taken`
(977 such) would delete is in `_onesided_pin_analysis.txt`: demand set #0,
width 20, 19 survivors, note type 6, `devise_user_first_1_person_not_found`
TAKEN, `find_by_1`/`find_by_2` both hit, `find_by_3` misses — an ordinary
third-lookup miss, in a context the corpus reaches.

Per the refinement's own rule, **no unconditional pin is installed.**

### §16.2 The single-ROOT hypothesis — facts 1-3, verbatim

**FACT 1 — which side of the root do the 1 560 fix?** Both. The premise fails:

```
root: (SYM_RESULT_..._devise_user_first_1_person_not_found == True)
  1136  not_taken  (person FOUND)
   424  TAKEN      (person NOT found — the fictional side)
```

Only **424 of 1 560** fix the not-found side. A single root pin cannot account
for the 1 560; **1 136 of them fix the FOUND side** and are a different shape.

**FACT 2 — can a signed-in User exist without a Person?** No.
`ruby_examples/dse-apps/apps/diaspora/app/models/user.rb`:

```
 47    validates :person, presence: true
 48    validates_associated :person
 54    has_one :person, inverse_of: :owner, foreign_key: :owner_id
 55    has_one :profile, through: :person
```

and the only construction path, `User.build` -> `setup` (l. 407-427), ends in
`self.set_person(Person.new(...))` (l. 424, 429-432) after `self.valid?`. A
persisted, valid `User` therefore always has a `Person`: the not-found side of
the root IS a state the real app does not reach, and the mock produces it.

**FACT 3 — is there a downstream query unique to the pinned side?** No.
From the inferred foreclosure relation (`_forecl.json`, the same
`infer_foreclosures` the engine uses):

```
decisions evaluated ONLY under the NOT-FOUND (taken) side:  0
decisions evaluated ONLY under the FOUND (not_taken) side: 22
```

**0 statements unique to the pinned side** — exactly the evidence the owner
asked for ("or are we getting another query downstream?"). The 22 the other way
are the ordinary person/profile reads that only happen once a person exists.

**So (2) and (3) line up and (1) does not.** A root pin on the not-found side
would be sound on its own evidence and would remove 424 + 3 047 = **3 471**
remaining assignments (the 3 047 "reachable" ones are reachable only because
the mock produced a fictional root, so removing them is correct, not
collateral) — but it would leave **1 136 of the 1 560 standing**. It is
therefore a separate, defensible pin, not the instrument for this residue.
Per the ruling's step 4 ("if (1)-(3) do not line up, fall back to that
measurement and report"), §16.1 is the report and nothing is installed.

### §16.3 The memo-identity hypothesis — REFUTED, and it moves 1 560 cubes into the backlog

The owner's last test: are `find_by_1_not_found` and `find_by_2_not_found`
really one symbolic value with two names (a memo hit that issues no SQL, so
`_alias_core` has no `statement_key` to alias on)? Measured over a 15 000-dump
random sample of the 96 299 pruned profiles:

**Q1b — one key or two? TWO, both independently honoured:**

```
seeded in 6522 runs   minted {False: 787, True: 29}   find_by_1_not_found
seeded in 6520 runs   minted {False: 733, True: 38}   find_by_2_not_found
seeded in 6512 runs   minted {False: 697, True: 50}   find_by_3_not_found
runs seeding BOTH find_by_1 and find_by_2: 6518; exactly one: 6
```

**Q1a/Q1c — do their outcomes ever differ in a real run? YES, and in exactly
the direction the 1 560 need:**

```
(find_by_1_not_found, find_by_2_not_found) over co-evaluating runs:
   733   both HIT
    38   find_by_1 HIT, find_by_2 MISS   <-- the shape the 1,560 fix
```

with named witnesses: `dump_html_plain_dse0794_DR4htmpr0.json`,
`dump_html_plain_dse0036_DR3htmpr0.json`,
`dump_html_typed_dse0748_DR3htmtr0.json`.

**This is the owner's branch (4).** The two finders are NOT one value with two
names; they are two independent seed keys, both honoured, and the corpus
already contains 38 runs in which the "impossible" finder combination happens.
So there is no identity to declare, no alias extension to propose, and no pin
to install for it: **the finder pair is producible, and the cubes that fix it
belong in the driving backlog.**

What §13.3 measured remains true and is now sharper: the 1 560 are unreachable
as WHOLE LEAF GROUPS — a conjunction of a note-type ordinal with several
finders' outcomes — not because any pair in them is impossible. That is why no
one-sided pin isolates them (§16.1) and why the single-root reading fails
(§16.2). The instrument that fits is still §13.3(2)'s conjunction refinement of
§16b, and the honest interim treatment is the declared residue: **1 560
counted, named, skipped, and reported with every batch.**

---

## §17. Batch S1 — the per-leaf-group OVERLAY seeder

### §17.1 Why the per-cube solver was abandoned (measured, not assumed)

`_enable_root.py` (§15) solved one Z3 model per cube with the transitive
enabling closure. It ran to the end of its solve stage on all 22 562 targets
before the owner's batching ruling arrived, and what it produced is the
argument for the ruling:

```
solved 22562 of 22562: unsat 0   (2756 s)
enabling depth used: 1:1403, 3:21159
enabling gates per solved cube: mean 221.0
cubes with a FREED gate: 22562, 1222687 gate-instances
```

**Mean 221 constrained gates per cube, out of 408 active decisions.** The
transitive closure at depth 3 pins more than half the graph, so the "rooted"
seed it produces is most of a BULK seed — and §12.8 measured what bulk seeds
convert at (0.0004/run). 2 756 s of solving to arrive at that shape is the
wrong instrument, and the run was stopped rather than driven.

### §17.2 What replaced it

Everything that needs deciding is per LEAF GROUP, not per cube:

* satisfiability is already established — the enumerator listed these cubes as
  satisfiable, so there is nothing to re-prove;
* within-set foreclosure consistency is already encoded in the cube: a cube IS
  a leaf of the pruned tree, so its members are exactly the decisions not
  foreclosed under its own gate outcomes (measured: `pre` is a SUBSET of
  `asg`'s keys in every one of the 24 122 rows, total `pre \ asg` = 0);
* the outside-set enabling gates are a property of the group, and a base run
  that walked ALL of the group's members already satisfies them.

So: pick the base once per group by §13.1's compatibility test, then OVERLAY
each cube's member outcomes onto that base's seeds, taking values from the
base's own minted values wherever the base already walks the demanded side and
otherwise from the expression's syntax. Every active expression on this
endpoint is one of `(V == True)` (249), `(V == StringVal(''))` (52),
`(V == k)` (30), `(V > k)` (25), `(V == '')` (17), `(V != k)` (15),
`(V == V2)` (10), `(V <= k)` (1) — **358 of the 368 member expressions invert
directly**, and the 10 that do not are cross-variable compares handled by the
value-repair rule.

**Two defects found and fixed on the way, both by their own printed verdict:**

1. The first run emitted **0 seeds** — "no compatible base" for all 1 394
   groups. Cause: `WANTED` carried the CHECKER-side spelling `SYM_LEN_X` while
   the dumps spell it `len(X)`, so every length decision — most of the gating
   on this endpoint — was never indexed. (731 polarity masks after the fix,
   631 before.)
2. The second emitted **1 412** seeds with "20 554 cubes need a solver". Cause:
   the inversion was applied to the DUMP-side name, which matches none of the
   patterns. Inverting the checker-side name fixed it.

### §17.3 The batch, built

```
TARGETS _remaining_e1.jsonl: 22562 REACHABLE cubes in 1394 leaf groups;
   1560 MULTI-GATE-FORECLOSED skipped (declared residue, §13.3)
indexed 96299 dumps, 731 polarity masks (310s)
emitted 13564 seeds from 22562 cubes in 9.4s = 1441 seeds/s (index excluded)
leaf groups with a compatible base: 1394 of 1394  (no base: 0)
cubes needing a SOLVER (not syntactically invertible): 3429
duplicate seeds: 5569
members the base had to be FLIPPED on, per cube:
   1:1711  2:5350  3:7337  4:5183  5:2212  6:631  7:126  8:12
peak RSS 179 MB, wall 5:20 (of which 310 s is the dump index)
```

html_plain 6 243, html_typed 6 462, mobile_plain 354, mobile_typed 505.

The flip histogram is the point: the **median cube needs 3 of its members
flipped** off a real observed walk, and none needs more than 8. That is a
rooted seed in DR3/DR5's sense — the opposite of the 221-gate models §17.1
rejected.

### §17.4 PRE-REGISTRATION — written before the S1 drive ran

Baseline (enumerated, `bounded_cliques=0`): `remaining = 24 122` =
**22 562 REACHABLE + 1 560 declared residue**. Seeds: **13 564**, one run each
(`SEEDS_ONLY=1`), so runs == seeds.

| method | per run |
|---|---|
| DR3 rooted, 1 base/witness | 0.185 |
| DR5 rooted + SELF-COMPARE rule | 0.157 |
| DR4 rooted, 3 bases/witness | 0.014 |
| C33D bulk v3.3 | 0.0004 |

The owner's expectation is "an order of magnitude above 0.16", on the ground
that a seeded variable that is REACHED is honoured 97 % of the time (§12.10).

| | threshold | expected closed on 13 564 runs |
|---|---|---|
| **PASS** | **>= 0.50 closed/run** | **>= 6 782** |
| PARTIAL | 0.157 - 0.50 | 2 130 - 6 782 |
| **FAIL** | **<= 0.157/run** | <= 2 130 |

SECONDARY (`_seed_audit.py` on the batch's own dumps; DR5's baseline measured
the same way on its 402 dumps, DR4's is §12.10's):

| | DR4 | DR5 | S1 pre-registered |
|---|---|---|---|
| seed keys never evaluated | 70.2 % | 59.9 % | **< 40 %** |
| honoured | 29.0 % | 34.0 % | > 50 % |
| cubes with every member evaluated by some run | — | — | **>= 60 %** |

FALSIFIER (owner's): if the rate is not well above 0.16, the enabling
constraints are incomplete, and the deliverable is the diagnostic — which
members stayed unevaluated and under which gate settings.

STOP RULE: two consecutive batches below 0.05/run ends the driving.

### §17.5 The S1 drive, as run

```
=== SET DRIVE S1 seeds=13564 jobs=93 chunk=150 slots=3 par=2 ===
corpus before: 250377      corpus after: 263941  (+13564)
93 of 93 chunks DONE, 13564 of 13564 seeds consumed, 0 toxic seeds, 0 JVM aborts
```

One run per seed, so **runs == 13 564**. Mid-drive the whole drive was stopped
and relaunched inside the caged slice (§17.7); the chunk `done_` markers made
that cost nothing but the two chunks in flight.

### §17.6 The seed audit — the pre-registered SECONDARY criteria

`_seed_audit.py` over a 3 000-dump sample of the batch's 13 564, and a
2 000-cube sample of the 22 562 targets:

| | DR4 (§12.10) | DR5 | **S1** | pre-registered |
|---|---|---|---|---|
| honoured | 29.0 % | 34.0 % | **35.3 %** | > 50 % — **miss** |
| contradicted | 0.9 % | 6.1 % | **6.9 %** | (none) |
| never evaluated | 70.2 % | 59.9 % | **57.8 %** | < 40 % — **miss** |
| per-run never-evaluated, **median** | 0.66 | 0.47 | **0.17** | (none) — **3.9x better than DR4** |
| per-run, p90 | 0.80 | 0.68 | 0.71 | |
| **cubes with EVERY member evaluated** | — | — | **99.6 %** (1 992/2 000) | >= 60 % — **PASS** |
| cubes REALISED (all members, demanded outcomes, one run) | — | — | **23.9 %** (479/2 000) | |

The two "misses" and the two passes say the same thing, and it is the useful
finding. The AGGREGATE never-evaluated share barely moved (59.9 -> 57.8 %)
because a seed dict inherits ~270 keys from its base and most of them are
irrelevant to the cube; but the **median per-run share fell from 0.47 to 0.17**,
and the criterion that actually matters — *does a run reach the members of the
cube it was built for?* — went from unmeasured to **99.6 %**. §12.10's
diagnosis ("the run never gets to the variable") is fixed: the compatibility
base selection puts every member of the cube on the walk. What remains is that
reaching a member is not the same as reaching it with the DEMANDED outcome:
only 23.9 % of cubes came out fully realised.

**Pre-registered expectation for the batch's own contribution:** 23.9 % of
22 562 targets ~ **5 392 cubes closed**, i.e. **~0.40 closed/run** on 13 564
runs — a PARTIAL by §17.4's table (0.157-0.50), 2.5x DR5 and 1 000x the bulk
rate, short of the 0.50 PASS bar.

### §17.7 Ops — what now runs concurrently, and the caps

Per the owner's ops directive (and its correction: `-p OOMScoreAdjust=` is
rejected for a `--scope`, because a scope adopts an already-started process —
`choom -n 1000 --` inside the scope instead):

Every job — the pass, the enumerator, the foreclosure dump, the seed builders,
the prune AND the JRuby drives — now launches as

```
systemd-run --user --slice=concolic-cov.slice --scope \
    -p MemoryMax=<cap> -p MemorySwapMax=0 --quiet choom -n 1000 -- <cmd>
```

Verified on the live drive: all three JRuby PIDs report `oom_score_adj=1000`
and sit in `run-*.scope` units whose accounting matches the slice's
`MemoryCurrent` (1.56 GB for ~1.47 GB of JRuby), i.e. they are INSIDE the cage,
not beside it.

| job | cap | run concurrently with |
|---|---|---|
| JRuby drive worker (x2) | **2 G each** (~0.8-1.2 G actual) | the interim audit |
| seed audit | **1.5 G** | the drive, and the prune |
| snapshot + incremental prune | **2.5 G** | the audit |
| enumerator / census | **5 G** (3.7 G actual) | nothing else of mine |
| coverage pass | **8 G** (3.75 G actual) | a drive, not another census |

Share held at <= 4 GB while the owner's cage is 9 G/8 G across three agents.
Pipelined, not serialized: the interim audit ran on 5 250 dumps while the drive
was still producing, and caught a defect (§17.8) 40 minutes before the batch
ended; the prune and the full audit then ran side by side.

### §17.8 A third defect, caught by the interim audit

The first interim audit reported **0 % of cubes with every member evaluated**
and named only `SYM_LEN_...` members as unevaluated. That was the same
length-spelling bug as §17.2(1), this time in the AUDIT: the dumps spell a
length `len(X)` and the enumerator's cubes spell it `SYM_LEN_X`. Fixed by
indexing both spellings; the number went 0 % -> 43.5 % on the same dumps, and
99.6 % on the full batch. Worth recording because it is the third appearance of
one root cause: **the checker-side and dump-side spellings of a length differ,
and every tool that joins the two must convert.**

### §17.9 PRE-REGISTRATION — separating the BATCH from CONFINEMENT

A new inferred property, CONFINEMENT (DISCIPLINE §16c), landed in the live
`src/concolic_engine/coverage.py` (mtime 2026-09-11 02:21) while S1 was
driving, so the re-enumeration after the batch measures BOTH effects at once.
(The §14 memory fix survives the merge intact — `profile_key` at l. 579, used
at l. 1056, and `test_coevaluation.py` is still green.)

To keep them separable, the enumeration is run TWICE, pre-registered here
before either runs:

1. **PRE-batch snapshot** `_snapshot_pruned_20260910_192233.txt` (96 299
   profiles) with the NEW engine -> `remaining_pre_conf`.
   **CONFINEMENT's effect = 24 122 - remaining_pre_conf** (24 122 is the same
   snapshot's number under the old engine, §16.3/§13.1).
2. **POST-batch snapshot** `_snapshot_pruned_20260911_024443.txt` (108 061
   profiles, corpus 263 941) -> `remaining_post`.
   **S1's effect = remaining_pre_conf - remaining_post.**

Batch rate = S1's effect / 13 564 runs, judged against §17.4's table. The
pre-registered expectation is ~5 392 closed (~0.40/run, PARTIAL); anything
attributable to confinement is NOT credited to the batch.

**Correction to §17.9, before either run (and it simplifies the split).**
`_exact_enum.py` builds its OWN universe (`build_universe`) and never calls
`CoverageChecker.check_coverage`; it uses the checker only for alias
application, the merged declarations and the bounds. CONFINEMENT lives in
step 5d of `check_coverage`, so **the enumeration is not affected by it at
all** — the census's semantics are identical to the ones that produced
24 122. The batch's effect is therefore measurable directly, with no
confinement-isolation run needed:

> **S1's effect = 24 122 - remaining_post**, both on the same semantics.

CONFINEMENT's effect belongs to `coverage_report.py`'s pass and is reported at
the certification (§18), not here. One weak-definition enumeration was started
at 02:53 and DISCARDED unrun when the owner's STRICT refinement landed at
02:58; and at 03:02 `src/test_confinement.py` is RED (`AssertionError: (15, 0)`
in the strict counterexample search) while the property is still being landed
by the posts_show agent — so no confinement-aware pass or gate is run here
until it is green.

### §17.10 THE S1 RESULT — pre-registration PASSED, by 2.3x its own bar

Re-enumeration on `_snapshot_pruned_20260911_024443.txt` (108 061 profiles,
corpus 263 941), `bounded_cliques=0` so every figure is exact, and the
emitted-vs-counted self-check agrees on every leaf group (8 381 == 8 381):

| | before S1 | after S1 | delta |
|---|---|---|---|
| satisfiable (demanded) | 65 156 | **65 217** | +61 |
| covered | 41 034 | **56 836** | **+15 802** |
| **remaining** | **24 122** | **8 381** | **-15 741** |
| of which REACHABLE | 22 562 | **6 949** | **-15 613** |
| of which MULTI-GATE-FORECLOSED | 1 560 | **1 432** | -128 |
| uncovered | 37.0 % | **12.9 %** | -24.1 pp |
| demand sets | 1 042 | 1 042 | 0 |
| `tree_missing` / `tree_complete` | 0 / True | 0 / True | 0 |
| nodes (active) | 408 | 408 | 0 |
| wide sets (>=13) / their mass | 48 / 8 328 | 48 / **3 742** | -4 586 |
| foreclosures inferred / gates | 9 224 / 369 | 9 137 / 360 | -87 / -9 |

**15 741 assignments closed by 13 564 runs = 1.16 closed per run.**

| criterion (§17.4) | threshold | result |
|---|---|---|
| **PASS** | **>= 0.50/run** | **YES — 1.16/run** |
| PARTIAL | 0.157 - 0.50 | — |
| FAIL | <= 0.157/run | — |

Against every method the campaign has measured:

| method | runs | closed | per run |
|---|---|---|---|
| **S1 — per-leaf-group OVERLAY, graph-chosen base** | **13 564** | **15 741** | **1.16** |
| DR3 rooted, 1 base/witness | 15 630 | 2 897 | 0.185 |
| DR5 rooted + SELF-COMPARE rule | 402 | 63 | 0.157 |
| DR4 rooted, 3 bases/witness | 28 535 | 396 | 0.014 |
| C33D bulk v3.3 | 22 000 | 9 | 0.0004 |

**6.3x DR3, 7.4x DR5, 83x DR4, 2 900x bulk.** It also beat my own
pre-registered expectation of ~5 392 closed (~0.40/run) by 2.9x, and it beat
the "natural ceiling" of one assignment per run — because a run covers a CUBE,
free on every expression it recorded both ways, so a single realised walk can
close several neighbouring assignments. The 23.9 % cube-realisation rate
measured in §17.6 therefore UNDER-states the yield by about 3x.

Two secondary observations worth recording:

* **The declared residue is corpus-relative, as §13.3 said it was.** The
  MULTI-GATE-FORECLOSED count fell 1 560 -> 1 432: 128 assignments that no run
  had ever walked under their gate assignment now have one. Nothing was
  declared away to achieve that — the classification simply re-ran on a corpus
  that had grown. This is the strongest practical argument yet against pinning
  the 1 560 by hand (§16): a chunk of them dissolves under driving.
* **The demand did not inflate.** `demand_sets` 1 042, `nodes` 408,
  `tree_missing` 0, all unchanged across 13 564 new runs — the batch closed
  demand without opening any.

### §17.11 PRE-REGISTRATION — batch S2

Targets: the **6 949 REACHABLE** assignments of `_remaining_s1post.jsonl`
(1 432 MULTI-GATE-FORECLOSED skipped and counted, as before). Same instrument,
no changes.

The residue left after a batch is by construction the part its seeds did NOT
realise, so the rate must fall. Pre-registered bands for S2, on whatever seed
count `_set_root.py` emits:

| | threshold | reading |
|---|---|---|
| PASS | >= 0.50/run | the method is still working at full strength |
| PARTIAL | 0.157 - 0.50 | still better than any earlier rooted method |
| POOR | 0.05 - 0.157 | first of the two strikes in the stop rule |
| **STOP** | **< 0.05/run twice in a row** | report the number, stop driving |

Expected, from S1's 69.2 % closure of the reachable set applied to a harder
residue: **0.4-0.9 closed/run**, i.e. roughly 1 700-3 800 of the 6 949.

### §17.12 Batch S2 / S2b — driven, and a fourth defect fixed between them

**S2.** 6 949 REACHABLE targets in 464 leaf groups -> **3 474 seeds**
(1 129 seeds/s). Driven: 3 474 of 3 474 consumed, 26/26 chunks, **0 toxic
seeds**, corpus 263 941 -> 267 415.

The seeder reported **3 175 of 6 949 cubes "needing a SOLVER"** — 46 %, against
S1's 15 %. The residue after S1 is enriched in exactly the cubes the syntactic
inversion could not do: identity compares `(V == V2)` / `(V != V2)` whose base
run minted NEITHER operand, so there was no observed value to anchor on.

**The fix needs no solver either.** An identity compare only requires its two
operands to AGREE (or to differ); with no anchor, seed BOTH with a common
literal (1/1 for `==`, 1/2 for `!=`). Re-running the seeder on the SAME targets
with that rule:

| | S2 | **S2b (fixed)** |
|---|---|---|
| cubes needing a solver | 3 175 | **0** |
| seeds emitted | 3 474 | **5 989** of 6 949 cubes |
| seeds/s | 1 129 | **2 092** |

So the owner's "Z3 only for exceptions, and in parallel" turned out to need no
Z3 at all: the exception class was a missing inversion rule, not a constraint
problem. **S2b** drove the 2 761 seeds S2 had not already run (deduped against
S2's own list by digest), 20/20 chunks, 0 toxic, corpus -> **270 176**.

Combined S2+S2b: **6 235 runs** against the 6 949 reachable targets.

**S2's seed audit** (2 500-dump sample, 1 500-cube sample), against S1's:

| | S1 | S2 |
|---|---|---|
| honoured | 35.3 % | 32.7 % |
| contradicted | 6.9 % | 6.0 % |
| never evaluated | 57.8 % | 61.3 % |
| per-run never-evaluated, median | 0.17 | 0.28 |
| cubes with EVERY member evaluated | 99.6 % | **82.8 %** |
| cubes REALISED | 23.9 % | **7.1 %** |

Both of the cube-level numbers fall, which is what a harder residue looks like:
the cubes left after S1 are the ones its seeds did not realise, so the same
instrument converts them less often. That is the expected shape, and it is why
§17.11 pre-registered a lower band for S2.

### §17.13 The S2 measurement is BLOCKED on a budget, and here is the number

The post-S2b enumeration was launched on the PRUNED snapshot
`_snapshot_pruned_20260911_042810.txt` — **110 912 profiles**, one dump per
distinct outcome profile of the 270 176-dump corpus (`_prune_corpus.py`, exact
for the verdict per §10.2). It was killed (`rc=143`, SIGTERM by the
coordinator) at 25 min wall / 10 min CPU: memory-throttled at the slice's
high-water mark beside posts_show's 2.9 GB pass, cputime frozen.

Per the coordinator's instruction ("if the pruned enumeration still needs
> 3 G, report the RSS and stop — I want the number rather than a retry at a
bigger cap"), the number is:

| pruned snapshot | profiles | corpus | enumerator peak RSS |
|---|---|---|---|
| `..._20260910_171301` | 96 148 | 249 975 | **3.56 GB** |
| `..._20260911_024443` | 108 061 | 263 941 | **4.15 GB** |
| `..._20260911_042810` | 110 912 | 270 176 | **3.06 GB at LOAD**, killed before `build_universe` finished |

**The pruned enumeration needs ~4 GB, not ~3 GB, and the trend is +0.6 GB per
+12 000 profiles.** The floor is the loaded runs themselves: 3.06 GB before
`build_universe` does anything at all. This is the same shape as §12.9 — the
corpus outgrows the budget as driving succeeds — except it is now the
ENUMERATOR, not the pass, and it is one memory fix later.

**It is NOT confinement.** `_exact_enum.py` contains **0 references to
confinement and 0 calls to `check_coverage`**: it builds its own universe and
uses `CoverageChecker` only for alias application, the merged declarations and
the bounds. CONFINEMENT lives in step 5d of `check_coverage`, so it cannot
reach these numbers. For the record, the run imported
`src/concolic_engine/coverage.py` **md5 `d9a11b08e9e73b2a80e4adc3b227bf55`**
(mtime 05:40:02; the run started 05:45:21), i.e. the gate-aware version.

A corollary worth stating: because the enumerator does not see confinement,
every `remaining` number in §16-§17 — 24 122 and 8 381 alike — is on
FORECLOSURE-ONLY semantics and the two are directly comparable. Confinement's
effect on this endpoint is still unmeasured and belongs to the certification
pass.

**State at this point.** S2 + S2b are DRIVEN (6 235 runs against the 6 949
reachable targets, 0 aborts, corpus 270 176) but NOT yet measured; the closed
count and the S2 rate are the one open number. Everything else stands.

---

## §18. The rulings of 2026-09-11, executed — and the root pin withdrawn by its own condition

### §18.1 The root pin was installed, then WITHDRAWN before it shipped a number

Ruling 1(b) directed installing `OneSideUntracked` on
`devise_user_first_1_person_not_found`'s NOT-FOUND side. It was installed as
its own counted tier (`_OWNER_ROOT_PIN`, printed separately in the
`[assumptions]` line, one-line reversible), with the owner's ruling, the app
facts and the falsifier.

The later ruling added the condition: *"keep it only if its side is still never
realised by construction; if the construction realises 'signed-in user with no
person' the app facts were wrong and the pin comes out."*

**It is realised constantly, and no construction was needed to show it.** Over
a 20 000-dump random sample of the 111 130-profile pruned corpus:

```
compare evaluated TAKEN     (person NOT found):  3 466   (17.3 %)
compare evaluated not_taken (person found):     14 887
variable minted: {'False': 14887, 'True': 3466}
witnesses: dump_html_plain_dse0849.json  (an ORIGINAL corpus dump, not a
           demand seed), dump_html_plain_dse0227_C32Ahtmp0000r0.json,
           dump_json_typed_dse0292_DR2jsotr0.json
```

**So the pin is withdrawn** (`_OWNER_ROOT_PIN = ()`, the evidence kept in
place as the record).

Why the evidence looked sufficient and was not, stated plainly because it is
the reusable lesson: `user.rb:47-48,54` is a fact about the real Rails app, and
"0 decisions and 0 target-call statements are evaluated ONLY under that side"
is a fact about what lies DOWNSTREAM of the branch. Neither is a statement
about whether THIS harness can walk the branch — and the branch is a seeded
boolean the harness sets freely. *"The application cannot reach this state"*
and *"this endpoint's decision cannot take this outcome"* are different claims,
and only the second licenses a pin. That is the same error §16.1 rejected for
the 16-pin cover, reached from the other direction. A branch that can be driven
is never argued (the rule that retired T1/T2). These ~3 471 assignments are
DRIVING BACKLOG.

### §18.2 Ruling 1(c) — the 1 432 "multi-gate" cubes, seeded and driven

`_set_root.py` gained `INCLUDE_MULTIGATE=1`: the leaf-group test says "no
observed profile walked exactly these members under exactly this gate prefix",
which is a statement about the CORPUS, not about the program — and 128 of them
had already dissolved under S1 alone. Carved out as `_remaining_mg.jsonl`
(1 432 assignments, 96 gate combinations, never seeded in S1/S2/S2b), seeded
(708 seeds, 111 of 111 leaf groups based, 0 needing a solver) and driven:
708/708 consumed, 0 toxic, corpus 270 176 -> **270 884**.

### §18.3 DIRECT CONSTRUCTION of every remaining gate combination — the table

Method imported from people_stream's `_x7_construct12.py` (the coordinator's
relay) and adapted here as `_construct_all.py`: fix the gate outcomes AND every
member outcome (the enumerator already proved the cube SAT, so the assignment
IS the model), invert to seeds written at EVERY ordinal backing each canonical,
UNSEED for `__prior`, and take the base for CONTEXT ONLY by maximum overlap —
never by compatibility.

Three adaptations this endpoint needed, all of which the people_stream script
would have got wrong here:

1. **`(V > k)` and `(V <= k)`** — 26 of its 408 active decisions — have no case
   in that script's `plan_for`. Added, with `NOT (> k) -> k, never 0` (§12.10).
2. **The `len` spelling** (RUNBOOK Phase 2): a canonical `SYM_LEN_X` must be
   resolved to every backing ordinal and re-wrapped as `len(<ordinal>)`.
3. **The SELF-COMPARE direction is the opposite one here.** people_stream's
   script realises the self-compare's TAKEN side by UNSEEDING and returns
   `None` for not-taken; §12.5 MEASURED the reverse on this endpoint (V
   present -> taken 205/205, V absent -> not taken 197/197). Unfixed, it left
   14 of 355 combinations NOT-CONSTRUCTIBLE; fixed, **0**.

**A fourth defect, found by the replay itself and worth the most.** The first
replay classified **76 of 355** combinations as CONTRADICTED — decisions that
flipped back despite their seed, i.e. the only shape that counts as
impossibility evidence. They were dominated by `SYM_NOTE_TYPE_PROFILE == k`.
Cause: a family like that contributes EIGHT members on ONE variable — seven
`== k` demanded False (each writing a sentinel `k + 424242`) and one demanded
True (writing the real `k`) — and in dict order a sentinel can be written LAST
and clobber the real value. **Write order, not impossibility.** Negatives
first, positives last (a demanded equality pins its variable exactly and must
win), and the number collapses:

| verdict | first replay | **after the write-order fix** |
|---|---|---|
| **REALISED** (some run walked every demanded decision with its demanded outcome) | 143 (40.3 %) | **154 (43.4 %)** |
| **UNEVALUATED** (a demanded decision was never reached — NOT impossibility) | 136 (38.3 %) | **185 (52.1 %)** |
| **CONTRADICTED** (flipped back despite its seed — the only impossibility evidence) | **76 (21.4 %)** | **16 (4.5 %)** |

355 combinations, 1 275 constructed seeds, 2 550 runs per replay, 0 crashes.

**The 16 that still contradict, named** (the only impossibility evidence this
endpoint has produced):

```
 5  (find_by_1_person_id == find_by_<n>_person_id)          identity compare
 4  (..._row_actors_row_rows > 3)      on all four notifications aliases
 2  (..._records_aspect_memberships_237d94fd_rows > 1)
 2  (..._records_mentions_fbb27183_rows > 1)
 1  (..._to_ary_notifications_cf379872_rows > 1)
 1  (..._to_ary_notifications_cf379872_row_actors_row_rows > 1)
 1  (..._records_aspects_0ce2f4d4_rows == 0)
 1  (..._records_services_0e45635b_rows == 0)
```

The `> 3` family on all four aliases is the suggestive one — it looks like a
harness cap on the actors list rather than an application fact, and it should
be checked against the mock before anything is declared about it.

**The headline: the "declared residue" framing does not survive contact with
direct construction.** 43.4 % of the combinations realise immediately, 52.1 %
are merely unreached, and only 4.5 % show a decision that refuses its seed.
Nothing here licenses a declaration; all of it is driving backlog, which is
exactly what people_stream found.

### §18.4 The `> 3` actors family — it IS the mock's domain, and the mechanism is named

The ruling asked that the `> 3` family be checked against the mock's list cap
before anything is declared. It is a cap — not a maximum, a THREE-POINT DOMAIN.
`targets.rb:744-756`:

```ruby
# Domain {0, 1, 4}: empty / one / the `number_of_actors < 4` arm
# (notifications_helper.rb:63), with `> 1` recorded so the
# cardinality-consistency check can read the decision back.
an_seed = ct.seed_for(aln, 1)
an = (...).to_i
an = 0 if an.negative?
an = 4 if an > 1          # <-- any seed above 1 snaps to 4
anv = symint(aln, an, note: psql)
anv == 0 ; anv > 1 ; anv > 3
```

and the decision itself is a REAL application branch —
`notifications_helper.rb:61 if number_of_actors < 4`, with l. 70 interpolating
`number_of_actors - 3` into the "and N others" text.

**All four contradicted `> 3` combinations demand `(> 1) = True` AND
`(> 3) = False`** — an actors list of length 2 or 3. The domain {0, 1, 4} has
no such value: every seed above 1 becomes 4. So those cubes are:

* **reachable in the application** (2 or 3 actors is an ordinary notification), and
* **unreachable in this harness**, by a deliberate, documented 3-point domain.

That is a MOCK-FIDELITY limit, not an application fact, and it is not a
declaration candidate: the honest fix is to widen the domain (e.g. {0,1,2,4}),
which is an `application code` change under the tightly-controlled rule, so it
is FILED, not made. Until then these four are named, with their cause.

**A fifth instrument defect, from the same reading.** The constructor wrote `k`
for `NOT (> k)`, so `NOT (> 3)` wrote 3 — which the snap turns into 4 and the
decision comes back TRUE. Domain-aware now: `NOT (> k)` writes **1** (satisfies
it for every k>=1, and is never 0, §12.10).

### §18.5 Batches S4 / CT4, and the rate trajectory

| batch | runs | remaining after | closed | per run |
|---|---|---|---|---|
| baseline | — | 24 122 | — | — |
| **S1** overlay | 13 564 | **8 381** | 15 741 | **1.16** |
| S2 + S2b + S3mg + CT2 | 9 493 | **5 364** | 3 017 | **0.318** |
| S4 + CT4 | 7 800 | **4 695** | 669 | **0.086** |
| **cumulative** | **30 857** | **4 695** | **19 427** | **0.63** |

0.086/run is above the brief's 0.05 stop threshold, so no strike — but the
trajectory is unambiguous and the residue is hardening exactly as a
successively-filtered residue must.

Final enumeration (`_snapshot_pruned_20260911_094226.txt`, 112 896 profiles,
corpus 283 784), `bounded_cliques=0`, emitted == counted on every leaf group:

```
EXACT: nodes=408 cliques=1042 satisfiable=65217 covered=60522 remaining=4695
REACHABLE 3351 (71.4 %)   MULTI-GATE-FORECLOSED 1344 (28.6 %)
tree_missing=0  tree_complete=True   wide sets (>=13): 48 holding 2733
```

uncovered **7.2 %** (from 37.0 % at the §13.4 hand-off).

**CT4's per-combination table** (270 combinations, 1 769 constructed seeds,
3 538 runs, 0 crashes):

| verdict | CT3 (355 combos) | CT4 (270 combos) |
|---|---|---|
| REALISED | 154 (43.4 %) | 76 (28.1 %) |
| UNEVALUATED | 185 (52.1 %) | 176 (65.2 %) |
| CONTRADICTED | 16 (4.5 %) | **18 (6.7 %)** |

The contradicted set is STABLE across both replays and is the same short list:
the four `_row_actors_row_rows > 3` (the domain gap above), the
`find_by_1_person_id == …__prior` self-compare, two `aspect_memberships…> 1`,
two `mentions_fbb27183…> 1`, and the `aspects`/`services` `== 0` pair. Eleven
distinct decisions in all, over ~250 000 runs — that is the whole of this
endpoint's impossibility evidence, and none of it is an application argument.

---

## §19. The UNEVALUATED class, sized — it is NOT mostly a semantics gap

Coordinator question (2026-09-11): the UNEVALUATED combinations now dominate
(176 of 270 in CT4, 65 %). A constructed seed fixed every gate and every member,
the gates were honoured, and a member was still never reached. Is that the
§16b CONJUNCTION-foreclosure case?

`_conj_forecl.py` (new, batch-local, 2 GB companion — the certification pass was
not touched) answers it with §16b's own test, lifted from pairs to conjunctions:

> a (member `d`, gate conjunction `P`) is a CONJUNCTION FORECLOSURE iff some run
> MATCHES `P` — evaluated every gate of `P` with `P`'s outcome, the same
> convention the leaf-group covering test uses — and NO run that matches `P`
> evaluates `d`.

### §19.1 The measurement

```
UNEVALUATED combinations to explain: 176 of 270
distinct (unevaluated member, gate conjunction) pairs: 267
combinations whose gates were ALL honoured in some run: 88 of 175
distinct unevaluated MEMBERS: 37
corpus indexed for 69 expressions over 112 896 profiles (162 s)

=== §16b's 'never' test, applied to the CONJUNCTION ===
  CONJUNCTION FORECLOSURE (runs match the gates, none evaluates the member):  52
  REACHABLE               (some matching run DOES evaluate it)              : 154
  NO RUN MATCHES the conjunction at all (undecidable by this test)          :  61

=== COVERAGE OF THE CURRENT RESIDUE ===
  remaining cubes now: 4695
  explained by a corpus-consistent CONJUNCTION FORECLOSURE: 960  (20.4 %)
```

**The answer is not "most of the remaining".** The conjunction case is real,
corpus-consistent and measurable — 52 pairs, **960 of 4 695 = 20.4 %** — but the
majority of the class, **154 of 267 pairs, is REACHABLE**, and not marginally:

```
 matching runs / of which evaluate the member
  14524 / 14524   (..._to_ary_notifications_3aa8587a_rows > 1)
  14524 / 14524   (..._to_ary_notifications_3aa8587a_row_actors_row_rows > 1)
  12259 / 12259   (..._to_ary_notifications_10254800_rows > 1)
  12259 / 12259   (..._to_ary_notifications_10254800_row_actors_row_rows > 1)
   3880 /  9049   (..._records_photos_175abc8b_rows > 1)
```

**Every single run that matches the gate conjunction evaluates the member** —
14 524 of 14 524 — and the constructed seed still did not reach it. Nothing
about the semantics is missing there; the SEED is wrong. The shape is the alias
family: a run walks ONE of the four `to_ary_notifications_*` statement aliases
depending on its context, and a cube whose members name a DIFFERENT alias from
the one the chosen base walks cannot be reached from that base no matter what is
seeded. `_construct_all.py` picks its base by maximum overlap and never checks
that the base MATCHES the gate conjunction — which is exactly the base-selection
criterion §13.1 established and the constructor dropped.

So the class splits three ways, and only the first is a `src/` question:

| | pairs | reading |
|---|---|---|
| CONJUNCTION FORECLOSURE | **52** | genuine §16b gap; 960 remaining cubes (20.4 %) |
| REACHABLE | **154** | a base-selection defect in the constructor — back to the drive with a base from a matching run |
| NO RUN MATCHES the conjunction | 61 | undecidable by this test; the gate combination itself is undriven |

### §19.2 PROPOSAL for `src/` — foreclosure over gate CONJUNCTIONS (not implemented)

**File.** `src/concolic_engine/coverage.py`, `infer_foreclosures` (§16b) and its
use in the demand-set split.

**Now.** `(g, o)` forecloses `d` iff some run evaluated both and every run with
`g = o` left `d` unevaluated. Strictly PAIRWISE, so a decision that is only
foreclosed by TWO gates acting together is never inferred, and its cubes stay
demanded forever.

**Proposed.** Infer the same relation over gate CONJUNCTIONS *that the demand
already contains*: for each demand set, for each leaf group's gate prefix `P`
and each surviving member `d`, if some profile matches `P` and none of the
matching profiles evaluates `d`, then `d` is foreclosed under `P` and the
group's assignments over `d` are not demanded. Nothing new is inferred from
outside the demand — `P` is a prefix the pruned tree already built, and the
"matches `P`" mask is the one the covering test already computes, so the cost is
one extra mask intersection per (group, member).

**Evidence.** 52 corpus-consistent (member, conjunction) foreclosures on this
endpoint, accounting for **960 of 4 695 remaining assignments (20.4 %)**, every
one of them verified by the same "never" test §16b uses pairwise, over 112 896
distinct outcome profiles.

**Falsifier.** Any run that matches one of those 52 conjunctions and evaluates
its member. That is precisely the test above, so it re-derives itself on every
corpus; 154 of the 267 candidate pairs FAILED it and were classified REACHABLE
rather than foreclosed, which is the discrimination working.

**What it does NOT do.** It does not close this endpoint: 3 735 of the 4 695
remaining would survive it. It is worth having because it is inferred, not
declared — it needs no owner argument and no pin — but the honest headline is
that **80 % of what is left is still driving backlog.**

**Not implemented.** `src/` is untouched beyond §14's memory fix.

### §19.3 The 154 REACHABLE pairs go back to the drive

Per the ruling's own branch, these are re-driven with a base from a matching
run. The constructor's base rule changes from "maximum overlap" to "matches the
gate conjunction, then maximum overlap" — the §13.1 criterion it had dropped.

### §19.4 The gate-matching base rule — installed, driven, honestly flat so far

`_construct_all.py`'s base selection changed from "maximum overlap" to
"**match the gate conjunction first** (greedily, never emptying the candidate
set), then maximise member overlap inside the matching set", with the index
rebuilt as bitmasks so the choice is a mask intersection rather than a scan of
112 896 dumps per cube.

CT5 on the current residue (`_remaining_s4post.jsonl`, 4 695 assignments in 224
gate combinations), 8 seeds per combination:

```
wrote 1547 constructed seeds over 224 combinations
bases MATCHING THE FULL gate conjunction: 1307 of 1547   (the old rule never checked)
replay: 3094 runs, 0 crashes
REALISED      64 of 224  (28.6 %)
UNEVALUATED  144 of 224  (64.3 %)
CONTRADICTED  16 of 224  ( 7.1 %)
```

**Flat against CT4's 28.1 % / 65.2 % / 6.7 %** — and that is the honest reading
to record now, not a win. Two qualifications, both measurable rather than
argued: CT5 aimed at a residue CT4 had already thinned (4 695 vs 5 364), so
holding the rate on a harder set is not nothing; and the per-COMBINATION verdict
is the coarse measure — the per-ASSIGNMENT delta is what the campaign is scored
on, and that needs an enumeration, which is exclusive with the certification
pass now running. **CT5's closed count is the one number still outstanding.**

What this does settle: the 154 REACHABLE pairs of §19.1 were NOT closed by
simply fixing the base rule. Every run matching their gates evaluates their
member, and a gate-matched base still does not reach it in 64 % of
combinations — so the obstacle is downstream of the gate prefix, inside the
walk, and the next thing to measure is which of the cube's OWN members the
gate-matched base fails to carry. That is a sharper question than "is it
foreclosure", and it is where the next batch should start.

### §19.5 Running total

| | |
|---|---|
| corpus | 250 377 -> **286 878** (+36 501 this session, 0 JVM aborts) |
| runs driven | **33 951** (S1 13 564, S2 3 474, S2b 2 761, S3mg 708, CT2 2 550, CT3 2 550, S4 4 262, CT4 3 538, CT5 3 094 — CT2/CT3 and CT5 not yet enumerated) |
| remaining (last enumerated) | 24 122 -> **4 695** |
| uncovered | 37.0 % -> **7.2 %** |
| of the residue | REACHABLE 3 351 / MULTI-GATE 1 344 |
| of the residue, explained by conjunction foreclosure | **960 (20.4 %)**, 52 pairs, corpus-consistent |
| impossibility evidence, whole endpoint | **11 decisions**, stable across two replays |

## §19.6 The alias hypothesis — REFUTED (5.1 %), and what the misses really are

The coordinator's reading was that the four `to_ary_notifications_*` aliases are
selected upstream of the gate prefix, so a gate-matched base walking a different
alias cannot carry the cube's members. Tested on CT5's own data, no new runs
(`_alias_miss.py`, 2 GB companion; the certification pass untouched):

```
UNEVALUATED combinations whose missed members name an aliased statement: 78
  base walked a DIFFERENT alias than the cube needs:  4   ( 5.1 %)
  base walked the RIGHT alias, member still missed : 74   (94.9 %)
```

**The hypothesis does not hold at 5.1 %** — but the CONTROL says why it looked
right, and vindicates the fix that was already made. Running the identical test
on CT4, whose bases were chosen by maximum overlap alone:

| | alias MISMATCH among the unevaluated |
|---|---|
| CT4 — base by max overlap | **24 of 96 (25.0 %)** |
| CT5 — base matches the gate conjunction | **4 of 78 (5.1 %)** |

So the alias effect was real at 25 %, and **gate-matching already absorbed four
fifths of it** as a side effect (the gate prefix and the alias are correlated —
matching one largely matches the other). That is also why CT5's per-combination
rate was flat: the fix removed a blocker that was never the dominant one. An
explicit alias rule would now buy the residual 5 %.

**The dominant class, characterised.** 138 combinations have the right alias AND
the right gates and still miss a member; **112 of 138 (81 %) miss exactly ONE**.
The missed members are a tight family:

```
 36x  devise_user_first_1_person_profile_not_found
 28x  find_by_3_not_found
 10x  ..._row_target_author_not_found            (x4 aliases)
  8x  ..._row_target_mentions_container_not_found (x4 aliases)
  6x  ..._row_target_statusmessage_not_found      (x4 aliases)
```

and a corpus scan shows each is gated by the NOTE TYPE: `row_target_author` is
evaluated only at note types 2-3, `row_target_mentions_container` only at 4-5,
`find_by_3_not_found` only at 6.

## §19.7 The cause is MINE — the sixth instrument defect, and it is the big one

The scan turned up out-of-domain values in the corpus — `SYM_NOTE_TYPE_PROFILE`
= 424245/424249, `SYM_POST_STI` = 424242/424243 — i.e. `k + PIN`, the
constructor's own negation sentinel. Applying the lesson that retired the root
pin (§18.1) — *does anything but my own seeds produce this?*:

```
sample 25 000 pruned profiles, of which 24 613 are NOT from my CT replays
SYM_NOTE_TYPE_PROFILE  out-of-domain: {424245: 10, 424249: 70}
                       ... in NON-CT dumps only: {}          <- ZERO
SYM_POST_STI           out-of-domain: {424242: 30, 424243: 140}
                       ... in NON-CT dumps only: {}          <- ZERO
```

**Every out-of-domain value in the corpus came from my constructor.** And the
decisive fact:

```
note-type ordinals TRACKED as decisions: [0,1,2,3,4,5,6,7]   (8 compares)
note-type values OBSERVED in the corpus: [0,1,2,3,4,5,6,7,8] (9 values)
```

**A cube demanding all eight `== k` FALSE is satisfied by note type 8 — a real
arm the corpus walks.** It is not out-of-domain demand at all. My constructor
wrote 424245 instead of 8, and an out-of-domain note type forecloses *every*
note-type-specific downstream decision — which is exactly the `row_target_*`
family that dominates the misses. **854 of the 4 695 remaining cubes (18.2 %)
demand all eight FALSE**, so this one defect plausibly accounts for a large part
of the UNEVALUATED class on its own.

This is the same error as the `> 3` actors domain (§18.4) in a new place, and it
is worth stating as a rule: **a negation must be realised by a value the
variable ACTUALLY TAKES.** An invented sentinel satisfies the solver and
forecloses the walk.

**Fixed** (`_construct_all.py`): the indexer now records each variable's
OBSERVED domain from `symbolic_vars`, and a cube's negations on a variable with
no positive equality are resolved to the most-often-observed value that
satisfies them all — the sentinel only survives where the corpus offers nothing.

**The next batch rule is therefore NOT "match the alias"** (5 %) but
**"realise negations from the observed domain"** (potentially 18 %+), with the
gate-matched base kept and an alias tie-break available for the residual 5 %.

**Not launched.** Per the sequencing instruction the batch waits for the
certification pass to land and be read; the constructor is ready.

---

## §20. The CERTIFICATION PASS landed — and CONFINEMENT priced

### §20.1 The pass, verbatim

`_c10_pass.sh` on `_snapshot_pruned_20260911_094226.txt` (112 896 profiles,
corpus 283 784), own slice, `MemoryMax=8G`, `MemorySwapMax=0`, `choom -n 1000`,
`python3 -u`, PID-waited, exit code checked. `src/concolic_engine/coverage.py`
md5 **`d9a11b08e9e73b2a80e4adc3b227bf55`** (gate-aware confinement, mtime
05:40:02; the run started 10:01:25).

```
[2026-09-11T10:01:25+00:00] pass cert1 list=_snapshot_pruned_20260911_094226.txt cap=8G avail=11171MB
[2026-09-11T11:28:17+00:00] pass cert1 EXIT rc=1
loaded 112896 runs (0 unparseable); peak RSS 3059 MB
OVERALL_COMPLETE=False;COMPLETION=False
COMPLETE=False;NODES=417;MISSING=731;BLOCKING=727;PCS=7110483
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
dump_errors={'ActionView::Template::Error': 35362, 'I18n::InvalidLocale': 1}
wrote .../coverage_summary.json in 4833.7s; peak RSS 4531 MB
  Elapsed (wall clock) time (h:mm:ss or m:ss): 1:26:52
  Maximum resident set size (kbytes): 4640348
```

`rc=1` is the documented "not complete" exit. `COMPLETION=False` because this
pass ran `SKIP_COMPLETION=1` — the gate is the next step, not a failure.

| | §14.5 pass (pre-campaign) | §20.1 pass |
|---|---|---|
| runs / unparseable | 96 299 / 0 | **112 896 / 0** |
| `demand_sets` | 1 042 | **1 539** (confinement splits) |
| `tree_complete` | true | **true** |
| `MISSING` / `BLOCKING` | 8 319 / 8 315 | **731 / 727** |
| `solver_lost` / `unevaluable` | 0 / [] | **0 / []** |
| wall / peak RSS | 3:13:00 / 3.75 GB | **1:26:52 / 4.43 GB** |

The summary carries **no confinement line** — the fixed schema has no such key;
`demand_sets` 1042 -> 1539 is the visible effect, and §20.2 prices it exactly.

### §20.2 CONFINEMENT, priced on an identical snapshot

`reports/diaspora/tools/confinement_census.py` runs this batch's own exact
enumerator TWICE on the identical universe — once over the §16b demand sets,
once over those sets projected by confinement:

```
DELTA (identical snapshot, identical assumptions, foreclosure ON in both):
  16b: sets=1042 satisfiable=65217 covered=60522 remaining=4695 bounded=0
  16c: sets=1539 satisfiable=34948 covered=32928 remaining=2020 bounded=0
DONE in 811s
```

| | §16b only | **+ CONFINEMENT (§16c)** | effect |
|---|---|---|---|
| demand sets | 1 042 | 1 539 | +497 (splits) |
| demanded (satisfiable) | 65 217 | **34 948** | **-30 269 (-46.4 %)** |
| covered | 60 522 | 32 928 | -27 594 |
| **remaining** | **4 695** | **2 020** | **-2 675 (-57.0 %)** |
| uncovered | 7.2 % | **5.8 %** | -1.4 pp |
| bounded cliques | 0 | 0 | exact both ways |
| wide sets (>=13) / mass | 48 / 2 733 | 84 / 1 756 | |

**Confinement removes 2 675 of the 4 695 remaining assignments** on this
endpoint — more than half — and it is inferred, not declared: nothing was
argued, pinned or withdrawn to get it. It also nearly halves the DEMAND itself
(65 217 -> 34 948), which is why the pass that took 3 h 13 m at 1 042 sets took
1 h 27 m at 1 539.

### §20.3 Where the endpoint stands

| | at §13.4 hand-off | now |
|---|---|---|
| corpus | 250 377 | **286 878** |
| pruned profiles | 96 299 | 112 896 |
| demanded / covered / remaining (§16b) | 65 156 / 41 034 / **24 122** | 65 217 / 60 522 / **4 695** |
| demanded / covered / remaining (§16c, shipped semantics) | — | 34 948 / 32 928 / **2 020** |
| uncovered | 37.0 % | **5.8 %** |
| `tree_missing` / `tree_complete` | 0 / true | 0 / true |
| `complete` | false | false |

**19 427 assignments closed by driving** (24 122 -> 4 695 under §16b, the
comparable semantics) in **33 951 runs with zero JVM aborts**, and a further
2 675 removed by the engine's own new inference.

The next batch targets the **confinement-aware** residue — 2 020, not 4 695 —
because that is the demand the shipped semantics actually carries; the
enumerator is being re-run with `EMIT_REMAINING` over the 16c sets to produce
that target list.

### §20.4 The domain-resolved batch (CT6 / S5) — built, driven, measurement pending

Targets: the **confinement-aware** residue, `_remaining_conf.jsonl` — 2 020
assignments in 149 gate combinations (532 REACHABLE, 1 488 MULTI-GATE by the
leaf-group test, all driven per ruling 1c). Emitted by the 16c census with the
enumerator's own self-check green (`emitted count == counted remaining, on
every leaf group`).

**The domain fix is confirmed in the seeds themselves** — the point of §19.7:

```
SYM_NOTE_TYPE_PROFILE seeded values: {8: 496, 5: 170, 4: 155, 6: 66, 3: 62, 7: 5, 1: 4}
SYM_POST_STI          seeded values: {2: 283, 0: 244, 1: 153}
```

Zero sentinels. Note type 8 — the legitimate "none of the eight tracked
ordinals" arm — is now written 496 times where the constructor previously wrote
424245, an out-of-domain value that foreclosed every note-type-specific
downstream decision.

Driven: **CT6** 976 constructed seeds x 2 variants = 1 952 runs, 0 crashes;
**S5** 807 overlay seeds (286 of 286 leaf groups based, 0 needing a solver),
0 crashes. Corpus 286 878 -> **289 637**.

CT6's per-combination verdict, on the hardest residue yet:

```
REALISED      32 of 149  (21.5 %)
UNEVALUATED  108 of 149  (72.5 %)
CONTRADICTED   9 of 149  ( 6.0 %)
```

**The assignment-level effect is NOT yet measured.** The 16c census that would
measure it was killed twice by budget collisions — once by the cage at 5.2 GB
of 8, once by the coordinator at 12:50 to protect people_stream's blockaid
subsumption (6 G cap) with the box at 2 GB free. Neither is a defect in the
job: both exited before their verdict line, which by the standing rule is
"killed, not done".

**A budget fact for whoever schedules it.** The instruction was to rerun it at
`<= 3.5 G`. That is not achievable on this corpus and the number is measured:
the loaded runs alone are **3.06 GB** before `build_universe` does anything,
and the census peaked at **4.49 GB** on 112 896 profiles (it is now 114 586).
The retry is therefore armed at 4 600 M, gated on `_box_clear.sh` reporting no
coverage pass, no enumeration, no confinement census AND no blockaid/subsume
JVM, plus >= 5.2 GB of cage headroom and >= 7 GB free. This is the same shape as
§12.9 and §17.13: the corpus outgrows the budget as the driving succeeds.

### §20.5 `dump_errors` — constructed runs error at 70 %, and the errors cluster on the seeded dimensions

`ActionView::Template::Error` rose 3 597 (2026-09-09) -> **35 362** in this
corpus. Measured over a 30 000-dump random sample of the 114 586-profile pruned
snapshot, split by provenance:

| provenance | runs | errored |
|---|---|---|
| ORIGINAL (no seed tag) | 8 908 | **7.2 %** |
| other seeded (DR*, C3*, S*) | 20 114 | **41.5 %** |
| **CONSTRUCTED (`_CT*`)** | 978 | **70.0 %** |

and they cluster on exactly the dimensions the seeder sets:

| `SYM_NOTE_TYPE_PROFILE` | runs | errored | | `SYM_POST_STI` | runs | errored |
|---|---|---|---|---|---|---|
| 0 | 6 226 | 19.0 % | | 0 | 15 072 | 16.8 % |
| 1 | 1 907 | 45.9 % | | 1 | 1 413 | 56.7 % |
| 2 | 2 504 | 44.0 % | | 2 | 1 900 | 61.5 % |
| 3 | 2 077 | 46.2 % | | (unset) | 11 262 | 43.5 % |
| 4 | 4 963 | 27.9 % | | **424243 (sentinel)** | 313 | **82.1 %** |
| 5 | 5 476 | 28.3 % | | | | |
| 6 | 3 886 | 30.0 % | | | | |
| 7 | 1 168 | 40.0 % | | | | |
| **8** | 1 394 | **59.9 %** | | | | |
| **424249 (sentinel)** | 162 | **70.4 %** | | | | |

**This is a seeder domain fact, of the same kind as the note-type sentinel.**
Three readings, all from the table:

1. The out-of-domain SENTINELS error hardest (70.4 % / 82.1 %) — more evidence
   for §19.7's fix, which removed them.
2. Note type **8** — the legitimate "none of the eight tracked ordinals" arm
   that the fix now seeds 496 times — still errors **59.9 %**, well above types
   0/4/5/6 (19-30 %). So the fix traded a 70 % failure mode for a 60 % one: the
   arm is real and drivable, but it is an expensive place to aim, and that
   alone explains a large part of CT6's 72.5 % UNEVALUATED.
3. The rarely-walked ends of every dimension error most (STI 1/2 at 57-62 % vs
   STI 0 at 17 %), which is what a residue-directed seeder must aim at by
   construction — the error rate rises as the targets get rarer.

**Soundness is unaffected and that is not an argument, it is §16b:** an error
run blocks only its own CLOSED PREFIX, so an errored run contributes the
decisions it did evaluate and demands nothing beyond them. The cost is
throughput, not correctness — roughly 70 % of constructed runs buy less than a
full walk, which is a direct multiplier on the closed/run rates of §17.10 and
§18.5.

### §20.6 Ops — the unified memory invariant is now the binding rule

Two collisions in this phase were mine: the 4.6 G census retry fired beside the
GATE because `_box_clear.sh`'s name list did not contain `assumption_checker`
or the gate's JRuby replays (which `tools/slot` launches OUTSIDE the cage, so
they do not show in `MemoryCurrent` either).

Fixed, and the fix is not another pattern:

* `_wait_mem.sh` — **the invariant**: before any launch >= 1 GB, require BOTH
  `free -g` available **>= 4** AND `(8 GiB - slice MemoryCurrent) >= the job's
  cap`; poll every 30 s; LOG both numbers at launch. Installed in all fifteen
  launchers (pass 8 G, enum 5 G, gate 8 G, census 4.6 G, drives 4 G, ...).
* `_box_clear.sh` — widened to `assumption_checker.py` and `java.*run_dse|jruby`
  as well as passes, enumerations, censuses and blockaid/subsume. It is now
  explicitly only an optimisation on top of the invariant.
* The gate counts as a PASS for slot purposes; nothing else heavy of mine runs
  beside it, and the census retry is disarmed until the gate exits.

---

## §21. THE GATE — first real probe under X10

### §21.1 Smoke (9 declarations), verbatim

```
[canonicalize] coverage_report:canonicalize_ordinals with 2 alias(es): ... by loop (k=1); ... by statement (k=1)
== derived assumption tests: 9 declared ==
RESULT: 23 distinct tested — PASS 19, FAIL 3, ERROR 0, NOT-TESTABLE 0, NOT-COMPARABLE 1
```

Nine declarations expand to twenty-three derived tests, in **41 minutes**.

Two things this already settles:

* **X10 works here.** `IndependenceAssumption` probes RUN and return verdicts
  (three sampled, all PASS, e.g. "no combination-only access shapes (snapshot
  `dump_html_typed_dse0779_C33Ahtmt0001r0.json`)"). Before the fix they
  `KeyError`ed on every pair of a canonicalizing endpoint, and notifications
  canonicalizes — so this is the first time any of these ~24 000 declarations
  has been probed at all.
* **The FAILs are all CONFINEMENT**, the new property, under its active probe:
  > `FAIL ConfinementAssumption ... (i) flip-A changed 9 shape(s) OUTSIDE
  > footprint(A): ActiveRecord::Associations::CollectionProxy.records |
  > preloaded association #aspect_memberships ...`

  plus one `NOT-COMPARABLE` where the flip changed what an aliased ordinal
  RESOLVED TO ("flip-B: 2 read as photos/175abc8b in the snapshot,
  aspects/0ce2f4d4 in the probe") — the 2026-09-08 rule that a probe about a
  different reading is never a PASS.

### §21.2 A full gate is not runnable, and the number says so

The shipped summary declares **25 467** assumptions: 24 302 Independence,
1 153 Confinement, 9 UntrackedPath, 2 Alias, 1 OneSideUntracked. At the smoke's
measured rate (23 tests / 9 declarations / 41 min) a full gate is
**~1 950 hours**. It is not a question of budget discipline; it cannot be run.

So the gate is run STRATIFIED and reported as a sample with its size stated:
**212 declarations** = 2 alias (carried so canonicalization matches the pass)
+ 9 untracked + 1 one-side + **100 of 24 302** independence + **100 of 1 153**
confinement. `assumption_checker.py` writes its results file even if the run
dies (X10), so a kill leaves evidence rather than nothing.

Launched under the new invariant, with both numbers logged as required:

```
[2026-09-11T13:40:06+00:00] gate g1 declared=_gate_declared_g1.json cap=5G avail=8110MB
[2026-09-11T13:40:06+00:00] _c10_gate.sh LAUNCH: free=7G cage_headroom=5215MB cap=5120MB
== derived assumption tests: 212 declared ==
```

The cap was corrected from 8 G to **5 G** first: the invariant demands
`(8 G - MemoryCurrent) >= cap`, and an 8 G cap requires an empty cage, which
this box never has. 5 G is the measured footprint (checker ~2.7 GB + two JRuby
replays ~1.6 GB), so the cap now states the job's need instead of a ceiling.

## §21.3 The gate by CLASS — the counts, and the hours

Classes computed from the declarations themselves (tier2 carries its class key
in its own description, `disjoint reps: [rep_a] || [rep_b]`; confinement by the
`(footprint-family_a, footprint-family_b)` pair):

| tier | declarations | CLASSES | one rep each |
|---|---|---|---|
| **tier2 disjoint-rep** | 20 056 | **8 252** | **633 h** |
| dispatch-independence | 3 230 | **304** | 23 h |
| confinement (footprint-family pair) | 1 153 | **140** | 11 h |
| not_found forecloses same-rep | 532 | 13 | |
| empty-list forecloses row decision | 318 | 3 | |
| cross-dispatch | 16 | 16 | |
| text_nil / disp_dlink / has_dlink / _persisted / _text_nil / C7-A | 150 | 16 | |
| UntrackedPath / Alias / OneSideUntracked | 12 | 11 | |
| **TOTAL** | **25 467** | **8 755** | **671 h** |

**Saying the hours rather than sampling silently, as instructed: a complete
class-level gate is 671 hours.** tier2 is 94 % of that. A coarser but still
principled key for tier2 — the rep FAMILY pair rather than the rep pair —
gives **1 368 classes (105 h)** instead of 8 252 (633 h); that is a ruling for
the coordinator, not a choice this agent should make, because it decides what
"a class" means for the standard.

**What IS running: tranche 1, complete at class level** — EVERY class of every
tier except tier2 and dispatch-independence: **198 classes covering 2 179
declarations**, plus the 2 alias declarations carried so canonicalization
matches the pass. ~15 h. The random-100 sample of §21.2 was stopped and
superseded.

```
[2026-09-11T13:43:45+00:00] gate t1 declared=_gate_classes_t1.json cap=5G avail=10973MB
[2026-09-11T13:43:45+00:00] _c10_gate.sh LAUNCH: free=10G cage_headroom=8092MB cap=5120MB
== derived assumption tests: 200 declared ==
```

**Correction to §21.1.** The smoke's three FAILs were **2 Alias + 1
Confinement**, not 3 confinement. Exact breakdown of the 23 tests:
Alias 14 PASS / **2 FAIL**; Independence 3 PASS; UntrackedPath 2 PASS;
Confinement **1 FAIL** / 1 NOT-COMPARABLE. The two Alias FAILs matter most —
they say the LOOP-keyed alias merges two statements that behave differently:
> "(i) 2 statements merged as variants of one loop: SELECT "photos".* ... |
> SELECT "photos".* ...; (ii) INTERVENTION EFFECTS DIFFER across members"

which is a defect in canonicalization itself, upstream of every number.

---

## §22. The render errors are NOT a mock gap — 92 % are declared or faithful

Ruling 2 asked for the top `ActionView::Template::Error` signatures on note
type 8 and on constructed runs, on the reading that "the harness [is] failing
to render an arm the app renders". Measured over 4 000 constructed dumps
(73.9 % errored):

| n | signature | first traceback frame |
|---|---|---|
| 1 210 | `undefined method 'first_name' for nil:NilClass` | `app/models/person.rb:251 in 'name'` |
| 1 035 | `undefined method 'as_api_response' for nil:NilClass` | `app/presenters/user_presenter.rb:12 in 'to_json'` |
| 476 | `undefined method 'mentions_container' for nil:NilClass` | `app/models/notifications/mentioned.rb:8 in 'linked_object'` |
| 171 | `undefined method '[]' for nil:NilClass` | `app/helpers/gon_helper.rb:6` |
| 63 | (photo/post delegation on nil author) | shareable.rb:21, posts_helper.rb:14, photo.rb:45 |

**The premise does not hold, and this batch's own POLICY_HEADER.txt already
says so — it names the top two signatures verbatim** (l. 85-106):

> TERMINAL SUBSTITUTION, STATED RATHER THAN GLOSSED. The corpus reaches this
> arm by declaring `Person#fix_profile` a target, which skips `Discovery.new`,
> `fetch_and_save` and `reload` together; the render then raises `NoMethodError`
> on the nil profile where the application raises `DiscoveryError`. The
> STATEMENT SETS are identical and the request 500s either way...
> There are TWO such nil-profile consumers ... both appear in the corpus as
> `ActionView::Template::Error`:
>   `undefined method 'first_name' for nil:NilClass`  (person.rb:250)
>   `undefined method 'as_api_response' for nil:NilClass` (presenter path)

So **2 245 of 2 955 (76 %)** are the DECLARED-UNMODELLED federation-discovery
boundary. "Fixing" it in `targets.rb` means modelling two live HTTP fetches
(`webfinger` and `hcard`) — which is exactly what the policy declares
unmodelled, and the app's own `fix_profile` raises `DiscoveryError` there. It
must not be repaired batch-locally.

A further **476 (16 %)** are FAITHFUL: `notifications_helper.rb:11` defends
against `linked_object` being nil, but `linked_object` is `target.mentions_
container`, so a nil TARGET raises one step earlier — in the application too.
The seeder drives `row_target_not_found` deliberately; the app raises there.

**92 % accounted for. The one genuine candidate is `gon_helper.rb:6`
(171, 5.8 %)** — `stored_contact[:person][:id]` on a presenter hash whose
`[:person]` is nil. That is a presenter/mock gap worth a differential, and it
is FILED rather than fixed here, because it is 6 % of the errors and the
session's remaining capacity is better spent on the gate.

**The consequence for the residue is the real finding.** The 70 % error rate on
constructed runs is not repairable by a mock change: it is what driving
deliberately into not-found arms costs, on an endpoint whose discovery-success
arm is declared unmodelled. An errored run still contributes its closed prefix
(§16b, sound), but it buys less than a full walk — so a large part of CT6's
72.5 % UNEVALUATED is **structural**, not a seeder defect, and no amount of
seeding removes it. That belongs in the composition of the residue, which is
where §19 already put 20.4 % as conjunction foreclosure.

---

## §23. The ALIAS FAIL acted on — P3's loop widening WITHDRAWN

### §23.1 What the gate refuted

```
FAIL AliasAssumption
  (i) 2 statements merged as variants of one loop:
      SELECT "photos".* FROM "photos" WHERE "photos"."status_message_guid" = $$(...)
    | SELECT "photos".* FROM "photos" WHERE "photos"."status_message_guid" = $$(...)
  (ii) INTERVENTION EFFECTS DIFFER across members: ordinals ['2'];
       e.g. at length 0 one variant removes an
       `ActiveRecord::Associations::SingularAssociation.find_target` /
       `SELECT "people".* ...` read the other does not.
```

This is the SAME refutation the widening already took for `to_ary` notifications
in `_ALIAS_REFACTOR_20260909.md` §4: an empty-scope `AND (1=0)` variant of a
photos read is not the same loop BODY as the real read, because at length 0 the
two do not lead to the same downstream statements. The 2026-09-09 census that
licensed the widening tested the five CollectionProxy families and passed them;
on the corpus as it now stands (114 586 profiles vs 68 231 then) **photos no
longer passes**, and the declaration's own text says in terms: *"A FAIL
withdraws."*

### §23.2 The narrowing is not available, so the KEY changed, not the pattern

The ruling offered "narrow the pattern or split the declaration". Narrowing is
not available here and the declaration already says why, about a different
family: the pattern matches ORDINAL names (`..._records_7`), which do not carry
the table, so **no pattern over them selects photos out** — the same reason
`Relation_records_notifications` could not be loop-keyed alone.

So the KEY was changed instead: `_ALIAS_LOOP_PATTERN` goes from `key="loop"`
back to `key="statement"` — P0 identity, where these reads were before P3
widened them. The cost is contained and the original note states it:
*"aspects / services / tags / aspect_memberships are one loop name each either
way"*, so **the only family renamed is photos: 3 loop names -> 6 statement
names**, and those six are exactly the three owner chains x {real,
`AND (1=0)`} that the gate just refuted merging.

### §23.3 What un-merging re-opened — measured

The pass was re-run on `_snapshot_pruned_20260911_122751.txt` (114 586
profiles, corpus 289 637) with the corrected alias. Its `[assumptions]` line
against the loop-keyed one, same corpus family:

| | loop-keyed (§20.1) | **statement-keyed (corrected)** | delta |
|---|---|---|---|
| tracked expressions | 417 | **441** | **+24** |
| co-evaluated pairs | 29 947 | **33 470** | +3 523 |
| tier2 disjoint-rep declarations | 20 056 | **22 574** | +2 518 |
| tier0c dispatch | 3 270 | 3 480 | +210 |
| tier1 foreclose | 971 | 1 001 | +30 |
| WITHDRAWN(indep) | 5 193 | 5 874 | +681 |
| INERT (never co-evaluated) | 56 473 | 63 054 | +6 581 |

**Un-merging photos re-opened 24 decisions**, and that is the correct cost of a
refuted identity, reported rather than avoided: the six photos statements are
six nodes again, the demand over them is real, and the 3-name version of the
graph was buying its smaller numbers with an identity the gate has now refuted.
`nodes / demand sets / remaining` after the pass follow when it lands.

### §23.4 Sequencing correction — tranche 1 was stopped, and why

Tranche 1 (198 classes) had been running since 13:43, i.e. **before** the alias
withdrawal. Its classes were keyed on the loop-merged canonical names, so every
one of its probes was about an identity that no longer holds — the exact reason
the ruling gives for starting the tier2/dispatch gate only after the correction.
It was stopped rather than allowed to produce verdicts about a withdrawn model.
It had written no results file yet, so nothing was lost but the time.

The corrected order is therefore: **alias withdrawal -> pass (regenerates the
assumption set on corrected names) -> rebuild the classes -> gate**. The class
counts of §21.3 are superseded: tier2 is now 22 574 declarations, so its
family-pair class count must be recomputed after this pass.

### §23.5 The pass after the withdrawal — and the real cost was TREE COMPLETENESS

```
[2026-09-11T13:49:13+00:00] _c10_pass.sh LAUNCH: free=10G cage_headroom=8082MB cap=6144MB
[2026-09-11T14:22:09+00:00] pass cert2 EXIT rc=1
loaded 114586 runs (0 unparseable); peak RSS 3107 MB
OVERALL_COMPLETE=False;COMPLETION=False
COMPLETE=False;NODES=441;MISSING=783;BLOCKING=779;PCS=7232901
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
  Elapsed (wall clock) time: 32:56.59
  Maximum resident set size (kbytes): 4729824
```

| | loop-keyed (§20.1) | **statement-keyed** | delta |
|---|---|---|---|
| `tree_nodes` | 417 | **441** | +24 |
| `demand_sets` | 1 539 | **1 245** | -294 |
| `MISSING` / `BLOCKING` | 731 / 727 | **783 / 779** | +52 |
| declared: Independence / Confinement | 24 302 / 1 153 | **27 060 / 2 350** | +2 758 / +1 197 |
| **`tree_complete`** | **true** | **FALSE** | — |
| wall / peak RSS | 1:26:52 / 4.43 GB | 32:57 / 4.51 GB | |

**The headline cost is not the +24 nodes or the +52 witnesses — it is
`tree_complete: false`.** The combination claim is CONDITIONAL on the tree
layer (DISCIPLINE §16), and §16b's foreclosure inference becomes PROVISIONAL
with it, so a refuted identity did not just add demand: it suspended the
precondition of every combination number until the new branches are observed.
That is exactly the cost the ruling asked to see reported rather than avoided.

`demand_sets` FELL (1 539 -> 1 245) at the same time, which is not a
contradiction: confinement splits sets, and un-merging changed which decisions
are confined; the demand is re-partitioned, not simply larger.

### §23.6 Tree completeness RESTORED in 24 runs

`tree_missing` was **2 branches**, both on the newly-separated statement:

```
(..._CollectionProxy_records_photos_36b2a9ca_row_text_dlink_is_post == True) :: not_taken
(..._CollectionProxy_records_photos_36b2a9ca_row_mention_inline_name == True) :: not_taken
```

Under the loop key these were merged with a sibling photos statement that had
both sides; un-merged, this one had only `taken`.

A first attempt (`_construct_all.py`, 2 seeds x 7 variants) recorded **neither**
— the base was chosen by overlap over a single expression, so with no gate
prefix to constrain it the chosen dumps **never walked photos at all**. The
targeted repair: scan the pruned snapshot for dumps that DO evaluate
`photos_36b2a9ca`, take their seeds, and flip the decision at the RUNTIME
ordinal key (`..._CollectionProxy_records_2_row_*`) rather than the canonical
name — 12 seeds x 2 variants = **24 runs, 0 crashes**:

```
text_dlink_is_post   not_taken observed: 12  -> CLOSED
mention_inline_name  not_taken observed: 12  -> CLOSED
```

Both branches are now observed, so `tree_complete` should return to true on the
next pass — 24 runs to restore the precondition the withdrawal suspended. The
lesson is the one §19.1 already gave in another form: **a base must be chosen
to walk the statement the target names**, and for a single-decision target that
means selecting on the statement, not on overlap.

### §23.7 CONFIRMED — tree completeness restored, and the withdrawal's full price

```
[2026-09-11T15:36:04+00:00] pass cert3 EXIT rc=1
loaded 114610 runs (0 unparseable); peak RSS 3107 MB
COMPLETE=False;NODES=441;MISSING=720;BLOCKING=716;PCS=7234929
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
  tree_complete: True   tree_missing: 0
  Elapsed 52:43.23; Maximum RSS 4 730 280 kB
```

**The complete before -> after for withdrawing P3's loop widening:**

| | loop-keyed (refuted) | statement-keyed, tree repaired |
|---|---|---|
| tracked expressions / `tree_nodes` | 417 | **441** (+24) |
| `demand_sets` | 1 539 | **1 240** (-299) |
| `MISSING` / `BLOCKING` | 731 / 727 | **720 / 716** |
| `tree_complete` | true | **true** (false in between, repaired by 24 runs) |
| declared Independence / Confinement | 24 302 / 1 153 | **27 060 / 2 350** |
| `solver_lost` / `unevaluable` | 0 / [] | **0 / []** |

So the refuted identity cost **+24 decisions and +1 197 confinement
declarations**, briefly suspended `tree_complete`, and — the part that is easy
to miss — REDUCED `demand_sets` by 299 and `BLOCKING` by 11. Un-merging does not
simply add demand: the six photos statements are separately confined where the
merged three were not, so confinement reclaims more than the un-merge opened.
**The corrected model is both more honest AND smaller here**, which is the
answer to "if un-merging re-opens demand, report it": on this endpoint it
re-opened 24 decisions and closed 299 demand sets.

---

## §24. THE GATE'S VERDICTS APPLIED — 253 refuted licences withdrawn

The class-level gate of §23.7's corrected model ran 16:44-18:36 over **2 023
class representatives covering all 29 430 declarations** (`_gate_ALL.log`,
`_gate_ALL_results.json`, `CONCOLIC_SLOTS=3 ACHK_PROBE_BATCH=40`, 6 725 s):

```
RESULT: 2040 distinct tested — PASS 1753, FAIL 253, ERROR 0, NOT-TESTABLE 0, NOT-COMPARABLE 34
  AliasAssumption         PASS 19
  ConfinementAssumption   FAIL 245, PASS 44, NOT-COMPARABLE 2
  IndependenceAssumption  PASS 1680, FAIL 8, NOT-COMPARABLE 32
  OneSideUntrackedPath    PASS 1
  UntrackedPath           PASS 9
```

### §24.1 The class key was REPRODUCED before anything was withdrawn

A verdict on a representative is only a verdict on a CLASS if the class is
known exactly, so the key was re-derived from the declarations themselves and
checked against the gate's own class file, both the key STRING and the cover
count (`_c11_classes.py`):

```
[verify] class key reproduced on tested reps: ok=1659 bad=0
[verify] cover counts match: 1659 classes, mismatched 0     (tier2 + confinement)
```

tier2's key is the rep-FAMILY pair (§21.3's coarse key: 1 368 classes over
22 574 declarations); confinement's is the footprint-family pair where a side
has a footprint and the read's table/expr otherwise (291 classes over 2 360
pairs). Every tested representative's class key and cover count came back
identical, so the expansion below is the gate's own partition, not a guess.

### §24.2 (a) The 8 IndependenceAssumption FAILs — eight tier2 CLASSES, withdrawn WHOLE

Every one of the 8 is a **tier2 disjoint-rep** class (none is dispatch), and
every verdict is the flip-both probe's own sentence — *"combination (flip both)
produced N target-call shape(s) absent from base/flip-A/flip-B"*. Withdrawn
whole per the HARD RULE (never narrowed to the probed rep): **60 declarations**.

| class (rep-family pair) | decls | the shape(s) the combination produced |
|---|---|---|
| `True` x `to_ary_notifications` | 24 | 8 shapes: `CollectionProxy.records SELECT "aspects".*`, `SELECT "services".*`, `preloaded association #services`, … |
| `to_ary_notifications_row_actors_row` x `to_ary_notifications_row_recipient` | 16 | 1: `FinderMethods.first loaded relation: #first answers from the in-memory target` |
| `True` x `find_by_1_person_profile_disp_has_dlink` | 6 | 2: `FinderMethods.exists? SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ?` + `Anonymous.load_intermediate` on the same |
| `exists__1_exists` x `to_ary_notifications_row_target_text_dlink_is_po` | 4 | 1: `Anonymous.load_intermediate SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ?` |
| `exists__2_exists` x `to_ary_notifications_row_target_text_dlink_is_po` | 4 | 1: `Anonymous.load_intermediate SELECT 1 AS one FROM "roles" WHERE "roles"."person_id" = ?` |
| `to_ary_notifications_row_target_is_photo` x `to_ary_notifications_row_target_text_has_dlink` | 4 | 2: `exists?` + `load_intermediate` on `SELECT 1 AS one FROM "posts"` |
| `exists__1_exists` x `find_by_1_person_profile_disp_dlink_is_post` | 1 | 1: `Anonymous.load_intermediate SELECT 1 AS one FROM "posts"` |
| `exists__2_exists` x `find_by_1_person_profile_disp_dlink_is_post` | 1 | 1: `Anonymous.load_intermediate SELECT 1 AS one FROM "posts"` |

**The mechanism is one mechanism, and it is the diaspora-link probe.** Six of
the eight pair a `Post.exists?`/`load_intermediate` guid probe with the
decision that decides whether a `diaspora://` link is rendered at all: with
both flipped the renderer reaches the probe that neither single flip reaches.
The seventh (`actors_row` x `recipient`) is the in-memory `#first` of a
preloaded relation, and the eighth (`True` x `to_ary_notifications`) is the
layout's own reads appearing when the principal is found AND the list is
non-empty. This is W-D's family (already withdrawn in cycle 6 for the
`_sharing` partner) reaching two partners cycle 6 did not have.

Installed in `coverage_assumptions.py` as **W-G**, keyed on the rep-FAMILY pair
read off each declaration's own `disjoint reps:` description — the same key the
gate classed by — with `NO_GATE_WITHDRAW=1` as the A/B knob. Checked against
the declaration set before any pass ran:

```
[W-G] tier2 declarations 22574; withdrawn by the gate-class predicate 60 (must be 60)
```

### §24.3 (b) The 245 ConfinementAssumption FAILs — INFERRED pairs, fed back as `withdrawn_pairs=`

A confinement pair is never declared in `coverage_assumptions.py`: the engine
INFERS it from the corpus (§16c), so it is withdrawn through the engine's own
mechanism. `_CONFINEMENT_20260911.md` names two optional one-liners for the
cross-pass loop, and **neither had ever been added to this batch's
`coverage_report.py`** — every pass re-inferred from scratch and a gate FAIL
lived only as long as the corpus disagreed. Both are now wired:

```python
CoverageChecker(..., withdrawn_pairs=_wd, prior_footprints=_pf)
#   _wd — _confinement_withdrawn.json, 1 806 pairs (class-whole)
#   _pf — _prior_footprints.json, 193 expressions (the corpus tripwire)
```

The 245 FAIL + 2 NOT-COMPARABLE representatives are **247 classes covering
1 806 inferred pairs**, and all 1 806 are withdrawn — a NOT-COMPARABLE inferred
pair withdraws exactly like a FAIL (DISCIPLINE §16c: *"an inferred pair the gate
could not VERIFY is withdrawn and blocks too"*).

**Which criterion refused them** (the first criterion each verdict cites):

| criterion | classes | pairs | what it says |
|---|---|---|---|
| (i) flip-A changed shapes OUTSIDE footprint(A) | 103 | 1 112 | the footprint is not the decision's real reach |
| (ii) flip-B changed shapes OUTSIDE footprint(B) | 62 | 447 | same, the other side |
| (iv) a flip leaves the partner UNEVALUATED | 80 | 243 | removal-shaped dependence (foreclosure, X11) — not a confined pair at all |
| NOT-COMPARABLE (aliased ordinal read differently) | 2 | 4 | not a test of the claim |

**The top failing shapes** — what actually crossed a footprint boundary:

```
  39  Anonymous.load_intermediate | SELECT "people".* FROM "people" WHERE "people"."id" = ?
  20  CollectionProxy.records | preloaded association #aspect_memberships
  16  FinderMethods.first | SELECT "people".* FROM "people" WHERE "people"."id" = ?
  11  CollectionProxy.records | SELECT "aspects".* FROM "aspects" WHERE ...
   9  CollectionProxy.records | SELECT "photos".* FROM "photos" WHERE ...
```

The person-by-id read dominates, and that is the honest reading of §16c on this
endpoint: almost every decision's flip perturbs the SAME `people` read, because
almost every branch here ends in rendering a person. Confinement's strictness
is what catches it — and 245 of 291 tested classes is not a marginal failure
rate, it is the property mostly not holding on this endpoint.

### §24.4 (c) The 34 NOT-COMPARABLE — one cause, and they are NOT passes

All 34 are the same 2026-09-08 rule: the probe's replay resolved an ALIASED
ORDINAL to a different statement than the snapshot did, so the probe is about a
different reading of the claim and can never be a PASS.

| | classes | declarations | disposition |
|---|---|---|---|
| IndependenceAssumption, tier2 | 24 | **540** | DECLARED-BUT-UNVERIFIED |
| IndependenceAssumption, dispatch | 8 | **70** | DECLARED-BUT-UNVERIFIED |
| ConfinementAssumption (inferred) | 2 | 4 | WITHDRAWN (an inferred pair must PASS) |

**610 independence declarations therefore stand DECLARED BUT UNVERIFIED**, e.g.
`flip-A: 2 read as memberships/6f13edc1 in the snapshot, photos/2a9cc6c3 in the
probe`. They are not withdrawn — the gate did not refute them, it failed to
address them — and they are not counted as passed anywhere. That statement
belongs in the header of any completeness claim this endpoint makes, and it is
in `POLICY_HEADER.txt`.

### §24.5 The exact census, before -> after, on ONE identical corpus

Both runs are `_exact_enum.py` on the SAME pruned snapshot
(`_snapshot_pruned_20260911_143539.txt`, 114 610 profiles, corpus 289 675 dumps at 14:35:39),
the same 441-expression statement-keyed model, `MemoryMax=4600M`, PID-waited,
each judged by its own printed line. The only difference is the A/B knob
`NO_GATE_WITHDRAW=1` (W-G off) versus the shipped code (W-G on):

```
BEFORE  [assumptions] tier2=22574 ... WITHDRAWN(indep)=5874 WITHDRAWN(gate-class W-G)=0
        EXACT: nodes=432 cliques=1608 satisfiable=82537 covered=72169 remaining=10368 bounded_cliques=0 wall=95s
        FORECLOSURE: applied=4872 pairs; leaf groups=5139          peak RSS 4.43 GB

AFTER   [assumptions] tier2=22514 ... WITHDRAWN(indep)=5934 WITHDRAWN(gate-class W-G)=92
        EXACT: nodes=432 cliques=1596 satisfiable=87233 covered=75446 remaining=11787 bounded_cliques=0 wall=97s
        FORECLOSURE: applied=5352 pairs; leaf groups=5283          peak RSS 4.42 GB
        EMIT_REMAINING: wrote 11787 remaining assignments (counted remaining = 11787; the two
        computations agree exactly, on every leaf group)
```

| | before (W-G off) | after (W-G on) | delta |
|---|---|---|---|
| tier2 declarations | 22 574 | **22 514** | **-60** (exactly the eight classes) |
| WITHDRAWN(indep) | 5 874 | **5 934** | **+60** |
| demand sets (§16b) | 1 608 | 1 596 | -12 |
| demanded (satisfiable) | 82 537 | **87 233** | **+4 696** |
| covered | 72 169 | 75 446 | +3 277 |
| **remaining** | **10 368** | **11 787** | **+1 419 (+13.7 %)** |
| uncovered | 12.6 % | **13.5 %** | +0.9 pp |
| foreclosure pairs inferred | 4 872 | 5 352 | +480 |

**`remaining` ROSE by 1 419, and that is the honest price of the refutation.**
Sixty declarations said "these two decisions do not interact"; the gate's
flip-both replay produced a target-call shape that only their combination
produces; so their cross product is demanded again, and 1 419 assignments of it
have never been walked. Nothing was traded to keep the number down.

**The W-G counter says 92 while the withdrawal moves 60, and both are right:**
the predicate runs FIRST, so it also catches the 32 pairs of those classes that
cycle 6's W-E/W-F had already withdrawn for a different reason. Only the 60 that
were still DECLARED change the model, which is exactly what `WITHDRAWN(indep)`
+60 and `tier2` -60 report.

**A number this campaign had not yet measured.** §23.7 reported the alias
withdrawal's cost at the PASS layer only (`NODES 417 -> 441`,
`demand_sets 1 539 -> 1 240`, `MISSING 731 -> 720`); the census that prices it
per ASSIGNMENT was killed twice by budget collisions (§20.4) and never re-run.
It is now run: against §20.2's last enumerated §16b figure of **4 695** on the
loop-keyed 417-node model, the corrected statement-keyed model demands
**10 368** — the un-merged photos statements re-opened rather more of the §16b
demand than the pass-layer numbers suggested, and 11 787 is where the gate's
verdicts leave it.

### §24.6 THE RESIDUAL, CHARACTERISED — and it contains no "walkable but unwalked" cube

`_c11_residual.py` (batch-local, **peak RSS 60 MB**, its own 400 M slice)
classifies every one of the **11 787** remaining assignments the corrected
enumerator emitted (`_remaining_after.jsonl`, emitted count == counted
remaining on every leaf group), over the whole 114 610-profile snapshot, on the
CORRECTED canonical names. The test is §16b's own "never" test lifted to the
gate conjunction, exactly as §19 did it, plus the run's terminal error.

**At the PAIR level — directly comparable with §19.1:**

```
distinct (member, gate conjunction) pairs in the residue: 4448
  CONJUNCTION FORECLOSURE (runs match P, none evaluates the member):  960
  REACHABLE               (some matching run DOES evaluate it)      : 2191
  NO RUN MATCHES P        (undecidable by this test)                : 1297
```

**At the CUBE level — which is the unit of demand, and the answer to §22(b):**

| class | cubes | share | what `COMPLETE=True` would need |
|---|---|---|---|
| CONJUNCTION-FORECLOSURE, matching runs mostly COMPLETE | **6 131** | 52.0 % | a `src/` inference (§19.2) — nothing to drive |
| CONJUNCTION-FORECLOSURE, matching runs 50-90 % errored | 805 | 6.8 % | same, plus a cleaner corpus on those arms |
| CONJUNCTION-FORECLOSURE, >=90 % DECLARED-UNMODELLED error | **928** | 7.9 % | a MODEL DECISION on the federation-discovery boundary |
| CONJUNCTION-FORECLOSURE, >=90 % FAITHFUL app error | **704** | 6.0 % | nothing — the application 500s there too |
| CONJUNCTION-FORECLOSURE, >=90 % mixed-signature error | 64 | 0.5 % | triage of the `other` signatures |
| NO RUN MATCHES THE GATE CONJUNCTION | **3 155** | 26.8 % | DRIVING (or a proof the combination is unwalkable) |
| **genuinely REACHABLE-BUT-UNDRIVEN** | **0** | **0.0 %** | — |

**The headline is the last row.** Every remaining assignment either has a
member that NO run matching its gate conjunction ever evaluates (8 632, 73.2 %),
or a gate conjunction no run walks at all (3 155, 26.8 %). **Not one of the
11 787 is a combination the corpus shows to be walkable and simply not walked.**
More seeding of the same kind closes none of the first class and only the
second.

**The error census behind the two error rows** (the same dumps, counted by
terminal signature — `''` means the run completed):

```
dump error census: {'': 78073, 'declared': 29988, 'faithful': 2727, 'other': 3822}
```

26 % of the corpus ends at the DECLARED-UNMODELLED discovery boundary and 2.4 %
at the faithful `mentions_container`-on-nil-target error — §22's split
(76 % / 16 % of the ERRORS) re-derived on the whole corpus rather than on
4 000 constructed dumps, and it is what puts 1 632 cubes (13.8 %) below a
boundary this endpoint has DECLARED it does not model.

### §24.7 What `COMPLETE=True` would take, priced

1. **A `src/` conjunction-foreclosure inference (§19.2), now much bigger than
   when it was proposed.** §19 measured it at 960 of 4 695 (20.4 %) on the
   loop-keyed residue. On the corrected model it is **960 pairs again — but
   they carry 8 632 of 11 787 cubes (73.2 %)**, because the corrected names
   split the photos family and the same foreclosures now gate more cubes. The
   proposal is unchanged (infer the relation over gate conjunctions the demand
   ALREADY contains; the mask is the one the covering test already computes)
   and it remains NOT IMPLEMENTED — `src/` is untouched by this batch.
2. **A model decision on the federation-discovery boundary** — 928 cubes
   (7.9 %) sit under the arm `POLICY_HEADER.txt` declares unmodelled, where
   `Person#fix_profile` skips two live HTTP fetches and the render 500s. It
   cannot be repaired batch-locally (Rule T: the boundary is shared), and
   "fixing" it means modelling `webfinger` + `hcard`.
3. **704 cubes (6.0 %) need nothing**: the application raises there too. They
   are demand over assignments a correct app cannot complete, and the honest
   move is a `UntrackedPath`-style ruling from the owner or an engine-side
   "terminal error" class — not a driving round.
4. **3 155 cubes (26.8 %) are driving work** — their gate conjunction has never
   been walked. That is where a next batch's seeds belong, and §19.7's
   observed-domain fix plus §19.4's gate-matched base is exactly the instrument
   for it; at CT6's measured per-combination rate this is many thousands of
   runs, and it is the only class where more runs is the right answer.

### §24.8 The 3 155 undriven cubes name ONE missing gate each

`_c11_nomatch.py` (same 400 M slice, 60 MB peak) asks, for every cube whose gate
conjunction no run walks, how many of its gates cannot be added to a
jointly-walked prefix:

```
cubes whose gate conjunction is NOT walked: 3155
how many of their gates cannot be added to a walked prefix: {1: 3153, 2: 2}

the blocking gate-sets, most common first:
   250  ..._to_ary_notifications_3aa8587a_rows == 0)  :: not_taken
   246  ..._to_ary_notifications_c7e6a7ca_rows == 0)  :: not_taken
   239  ..._to_ary_notifications_3aa8587a_row_actors_row_rows == 0) :: not_taken
   235  ..._to_ary_notifications_10254800_row_actors_row_rows == 0) :: not_taken
   232  ..._to_ary_notifications_10254800_rows == 0)  :: not_taken
   228  ..._to_ary_notifications_c7e6a7ca_row_actors_row_rows == 0) :: not_taken
   226  ..._to_ary_notifications_cf379872_rows == 0)  :: not_taken
   222  ..._to_ary_notifications_cf379872_row_actors_row_rows == 0) :: not_taken
   146  (SYM_LEN_..._to_ary_notifications_10254800_rows > 1) :: taken
   128  (SYM_LEN_..._to_ary_notifications_c7e6a7ca_rows > 1) :: taken
   118  (SYM_LEN_..._to_ary_notifications_3aa8587a_rows > 1) :: taken
   116  (SYM_LEN_..._to_ary_notifications_cf379872_rows > 1) :: taken
```

**3 153 of 3 155 are blocked by exactly ONE gate**, and every one of the top
blockers is the notification LIST cardinality on one of the four
`to_ary_notifications` aliases: a NON-EMPTY list (`rows == 0 :: not_taken`), a
non-empty actor list, or a MANY-row list (`rows > 1 :: taken`) — each in
combination with a prefix the corpus already walks separately.

That is a seeding target a next batch can aim at by name rather than "the
residue": hold the walked prefix, force the list cardinality on the alias the
base walks. It is also consistent with §19.7's lesson — the cardinality gates
are seeded dimensions, and the corpus's cardinality distribution is where the
driving has been thinnest.

### §24.9 Ops — the cage was lowered TWICE mid-session, and what that blocked

An editor language server OUTSIDE the cage grew from 3.4 GB to over 6 GB during
this session. The coordinator lowered the cage twice in response, and the
invariant was re-based each time (`_wait_mem.sh`, one place, all launchers):

| time | cage | invariant | what it permits |
|---|---|---|---|
| before | `MemoryMax=8G` | free >= 4 AND (8G - current) >= cap | pass at 8 G |
| 19:10 | `6G / high 5G` | free >= 4 AND (6G - current) >= cap | pass at 5 G, enumerator at 4.6 G |
| 19:46 | **`4G / high 3G`** | **free >= 2 AND (4G - current) >= cap** | **nothing over ~3 G** |

What that cost, stated rather than glossed:

* The FULL engine pass (coverage + completion) was **launched at 19:41 and
  killed at 19:46** by me, not by the kernel: its measured need is 4.5-4.7 GB
  and a 5 G scope inside a 4 G slice is killed at 4 G whatever `free` says. It
  exited without a verdict line, so by the standing rule it was **killed, not
  done**, and no number from it is quoted anywhere.
* Both censuses had already landed (19:17-19:29 and 19:29-19:41), so the
  before -> after of §24.5 is complete and unaffected.
* Everything under 3 G was done instead: the withdrawals, the wiring, the
  residual classification (60 MB), the unwalked-gate analysis (60 MB), the
  report and the POLICY_HEADER stanza.

**One more ops finding, and it is a real one.** A small job put into
`concolic-cov.slice` while another batch's 3 GB job is in it does not run
slowly — it does not run at all: `/proc/<pid>/wchan` reads
`mem_cgroup_handle_over_high` and the process accumulates 1 s of CPU in 3
minutes. Small analysis jobs therefore run CAGED IN THEIR OWN SLICE
(`_c11_smallrun.sh`, `concolic-small.slice`, `MemoryMax=400M`), which both
bounds them and keeps them off the contended slice. `_box_clear.sh` was also
rewritten from its name list to a SIZE rule (any python/java/ruby over 400 MB,
whoever owns it) — the name list did not match the other batch's
`_part_decomp.py` or its streaming extractor, which is exactly the collision
the lowering was about.

**Queued, not abandoned.** `_c11_queue.sh` is armed and fires the remaining
stages automatically when the box returns: it waits for `free -g >= 6` AND an
empty box (the size rule) AND `concolic-cov.slice MemoryMax >= 5.5 G` — the
third condition because the first two can be true while the cage still makes
the pass impossible.

### §24.10 Extraction WITHDRAWN — a policy is extracted at CLOSURE only

The brief asked for the extraction and the policy install. The owner's rule
(relayed 2026-09-11 21:16) is that **a policy is extracted only after
`complete: true`** — comments_index, conversations_index and people_stream were
all extracted after closure — and notifications_index is not complete. So:

* the extraction that was running (SKIP_SUBSUME=1, caged, 10 000 of 114 610
  dumps) was **killed and is not to be relaunched**;
* **nothing was written** to `queries_from_runs/notifications_index.sql` — it
  still carries its 2026-08-21 mtime and its 83 views, untouched by this
  session (the extractor writes only at the end, and it never got there);
* the extraction stage was **removed from `_c11_queue.sh`**, which now chains
  the final pass -> `_c7_audits.sh` and nothing else;
* the verification stanza this session had added to `POLICY_HEADER.txt` was
  **reverted** (the file is byte-identical to its 2026-09-01 state) and the
  text is parked in `_c11_POLICY_HEADER_stanza_NOT_INSTALLED.txt` for whoever
  closes this endpoint. It says what the class gate PASSed, what was withdrawn,
  and that **610 declarations stand declared-but-unverified**; that sentence
  belongs in the header of any completeness claim, but the header itself is
  written at closure.

One knob survives as a batch-local improvement, and it is worth keeping:
`_extract_notifications_index_streaming.py` now honours **`SKIP_SUBSUME=1`**,
which runs the FREE syntactic stage in-process and records
`subsume_ran: false`, so the solver stage is never conflated with it and no
blockaid JVM is forked while the box is short of memory.

---

## §25. C13 — THE CONSTRUCTED ROUNDS OFF THE C12 WITNESSES (2026-09-12)

### §25.1 What C12 actually says, and at what cap

`_cov_FINAL_C12_20260912.json`, coverage layer only (`SKIP_COMPLETION=1`),
written by `_c12_rerun_after_restart.sh` stage 1 on the §16d engine:

```
COMPLETE=False;NODES=441;MISSING=781;BLOCKING=777;PCS=7234929
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
  snapshot   _snapshot_pruned_20260911_143539.txt   114 610 runs
  checkpoint _cov_c12.ckpt.jsonl                    1 665 records (1 per demand set)
  wall 977 s   peak RSS 4 697 MB
  demand_sets 1665   tree_complete TRUE   tree_missing []
  dump_errors {'ActionView::Template::Error': 36536, 'I18n::InvalidLocale': 1}
```

**`tree_missing` is EMPTY and `tree_complete` is TRUE**, so §16b's precondition
holds on this corpus: every decision has been taken both ways and the
foreclosure relation the combination claim rests on is **not** conditional.
`foreclosures_provisional` does not appear in the file — this batch's
`coverage_report.py` writes a FIXED key set (the coordinator's cross-endpoint
schema) that omits it — but `coverage.py:2060` defines it as
`bool(tree_missing)`, so on this pass it is **False**. Stated as a derivation,
not read off the file. `foreclosures` / `foreclosure_gates` are omitted by the
same schema; the enabling gates were therefore taken from the CHECKPOINT's own
leaf assignments instead (see §25.2), which is the same information and needs
no solver.

**The cap the pass ran at was 4, not 1.** The brief said "no
`MAX_MISSING_PER_CLIQUE`", on the strength of the engine's new §16d default of
1. That default does not reach this batch: `coverage_report.py:519` reads
`int(os.environ.get("MAX_MISSING_PER_CLIQUE", "4"))`, so an UNSET variable means
FOUR here. The heartbeat line in `_c12_cov.log` confirms it
(`max_missing_per_clique=4`), and so does the checkpoint:

```
demand sets in the checkpoint          1 665
sets WITH A GAP                          298   <- the number to drive to zero
   of them stopped AT the cap of 4       171   (so 781 is a LOWER bound)
witness leaves recorded                  885   distinct cubes: 777
                                              (= BLOCKING; the other 4 of the
                                               781 are `untracked`)
distinct expressions over those cubes    162
width 2..17, mode 5
```

`_c13_pass.sh` therefore sets `MAX_MISSING_PER_CLIQUE=1` explicitly.

### §25.2 The gates come from the checkpoint, not from a second solve

`combos[i]` in `_cov_c12.ckpt.jsonl` is the leaf assignment — every
`(expr, outcome)` pair the leaf pins, GATES INCLUDED, because §16b builds the
leaf gates-first out of the set's own foreclosure order. `models[i]` is Z3's
counterexample for it. So "the counterexample PLUS the enabling gates" is one
object already in the file, and **no Z3 call is made anywhere in C13's
construction**. `_c13_witness.py` extracts it: 777 distinct cubes over the 298
sets with a gap.

### §25.3 The seeder defect check — a GROUND-TRUTH DIFFERENTIAL, and the answer is NO

posts_show §77.4 found THREE defects in `_construct_by_gate.py`, the constructor
it had used since 2026-09-11, all of the same shape (a checker-side name looked
up in a dump-side namespace, failing silently as "no compatible base"). The
brief's instruction was to check this batch's seeders for them before trusting
any earlier "never evaluated" classification. `_c13_defect_audit.py` does it as
a differential over REAL data rather than as an instance test: 250 random base
dumps from the C12 snapshot x the 142 variables the 777 witness cubes actually
constrain = 35 500 (variable, base) pairs, each resolved to runtime seed keys
BOTH ways and scored against that base's OWN `concolic_seeds` key set.

```
                                             keys emitted   base consumes
  OLD  (_construct_all.ordinals/_ordinals_raw)     35 500      4 799 (13.5 %)
  NEW  (derived round-trip, _c13_construct)        35 500      4 799 (13.5 %)
  variables where OLD and NEW disagree on seedability:  0 of 142
```

**Neither of the two big defects is present here.**

1. *"Every `SYM_LEN_*` value silently dropped"* — NOT present.
   `_construct_all.ordinals()` has always converted `SYM_LEN_X` -> `len(X)`
   before resolving ordinals (its own docstring cites the RUNBOOK `len` rule),
   and every analysis script in this batch that joins the two namespaces
   (`_seed_audit.py`, `_construct_report.py`, `_alias_miss.py`) carries the
   `_UNLEN` substitution in the other direction. `_exact_enum.py` loads through
   `CR.fix_len_names`, so its emitted assignments are checker-spelled and the
   constructor converts them back. 33 of the 142 constrained variables are
   `SYM_LEN_*` and all 33 resolve identically under both paths.
2. *"Suffixed names never resolved, 60 % of values unwritable"* — NOT present.
   posts_show's `inv.get(k)` demanded an EXACT alias-map canonical;
   `_construct_all._ordinals_raw` has always used a PREFIX match
   (`canon.startswith(c)` -> `o + canon[len(c):]`), which is exactly what a
   `<canonical>_row_target_not_found` name needs.
3. *"Out-of-domain resolution only for `==`/`!=`"* — **PARTIALLY present, and it
   is the one real finding.** `_construct_all`'s domain resolution (§19.7) fires
   only for INTEGER equality with no positive pin (`_EQI` in `eqpos`/`eqneg`).
   A `!= k`, a `> k`, a string `== 'x'`/`!= 'x'` and a two-variable compare all
   still write the invented sentinel (`k + 424242`, `x + "_ctother"`), tempered
   only by the hand-written `> k` snap-domain hack of §18.4.
   `_c13_construct.resolve()` replaces all of it with one rule: a value is
   accepted only if it SATISFIES EVERY literal the cube puts on that variable,
   preferring (a) the model's own value when the corpus produces it, then
   (b) the most-observed corpus value that satisfies, then (c) a synthesized
   sentinel, counted. Corpus values >= 424242 are EXCLUDED from (b): §19.7
   measured zero such values in non-constructed dumps, so they are the previous
   constructor's own sentinels replayed back into the corpus, not app behaviour.

**What that means for the earlier classifications.** §24.6-24.8's "conjunction
foreclosure" (73.2 %) and "no run matches the gate conjunction" (26.8 %) were
computed by `_c11_residual.py` / `_c11_nomatch.py`, which are CORPUS SCANS over
`canonicalize_ordinals`-normalised dumps — they never call the constructor, so
posts_show's defects cannot have produced them. What the constructor's
sentinel-writing CAN have produced is the UNEVALUATED share of the CT4/CT5/CT6
replays (§19), and §19.7 already caught and named that on this batch's own
evidence (the note-type-8 case, 18.2 % of the then-residue). The C13 rounds
below re-test §24.6-24.8 the only way it can honestly be re-tested: by
constructing every one of the checker's own 777 leaves with the repaired
resolver and driving them.

### §25.4 ROUND 1 — the batch, built

`_c13_index.py` (114 610 dumps, 1 376 s, 19.1 MB pickle, peak RSS ~100 MB) then
`_c13_construct.py` (55 s):

```
gaps (distinct witness leaves)      777        K = 2 bases per gap
distinct base profiles              51 438     (114 610 dumps collapse to this
                                                many distinct (variant, eval
                                                mask, true mask, canonical mask)
                                                signatures; base choice scores
                                                the profiles, not the dumps)
distinct base runs used                778
seeds built                          1 554
values SUBSTITUTED                   2 536   model value not one the corpus
                                             produces -> most-observed value
                                             that SATISFIES the cube
values kept out-of-domain              304   NO observed value satisfies the
                                             cube on that variable  <- §25.6
values NOT seedable                      0
variables with no satisfying value       0
seeds with an INERT alias               55   base cannot spell a canonical the
                                             cube's names use
keys written the base was not seeded on 1 538 (upper bound on inert keys)
  set A  html_plain 139  html_typed 196  json_plain  45  json_typed 23
         mobile_plain 195  mobile_typed 179  xml_plain 0
  set B  html_plain  78  html_typed 139  json_plain 150  json_typed 83
         mobile_plain 144  mobile_typed 181  xml_plain 2
```

**Gaps that could not be constructed: 0.** Bases are chosen by alias-canonical
coverage FIRST, then cube-match-minus-conflict over the whole leaf (gates and
members together — §19.4's gate-match rule, generalised), then seed count.

### §25.5 ROUND 1 — driven, and explained PER KEY

```
_c13_drive.sh C13A 100   09:34:05 -> 09:49:19   15 min 14 s   +777 dumps
_c13_drive.sh C13B 100   09:52:xx -> 10:18:27   26 min        +777 dumps
   verdict lines: C13-DRIVE-DONE C13A / C13B, 0 seeds left, every leg with its
   own `=== CHUNK DRIVE ... END ===`; 0 toxic seeds, 0 crashed chunks
   one dump per seed exactly (SEEDS_ONLY replay): 777 and 777
```

`_c13_classify.py` over both sets (1 554 replay runs against the 777 cubes,
5 326 demanded keys):

```
=== PER KEY ===                        set A only        A + B
  HONOURED                          4 364 (81.9 %)   4 494 (84.4 %)
  CONTRADICTED                        170 ( 3.2 %)     182 ( 3.4 %)
  NEVER-EVALUATED                     792 (14.9 %)     650 (12.2 %)
=== PER GAP (777) ===
  REALISED  (one run took the WHOLE cube)  117 (15.1 %)   185 (23.8 %)
  UNEVALUATED                              490 (63.1 %)   410 (52.8 %)
  CONTRADICTED                             170 (21.9 %)   182 (23.4 %)
replay dump errors  {'': 739, declared: 580, other: 115, faithful: 88, gon: 32}
```

**This is the number that matters against §19/§24.** Round OD0911-era
constructions on this endpoint ran at ~68 % UNEVALUATED PER KEY; with the
observed-domain resolver applied to EVERY literal kind and a base chosen by
alias coverage, the per-key honour rate is **84.4 %** and **185 of the checker's
own 777 uncovered leaves were taken WHOLE by a single constructed run each**.

### §25.6 THE CONTRADICTED CLASS — 116 of 182 are the MOCK's snap domain, named

A decision that flips back despite its seed is the only shape that is
impossibility evidence, so the 182 were taken apart rather than counted.

**116 of 182 demand a list length the mock cannot produce.** `targets.rb`'s
actors-list mock snaps a collection length to the domain **{0, 1, 4}**
(`an = 0 if an.negative?; an = 4 if an > 1` — §18.4). Both `> 1` and `> 3` are
TRACKED decisions on that same snapped variable, so the checker legitimately
demands the combination `(len > 1) = true AND (len > 3) = false`, which needs a
length in {2, 3} — a value the mock CANNOT return. The constructor detected this
before the drive (those are 304 of its "kept out-of-domain" values: no observed
value satisfies the cube on that variable) and the drive confirmed it: the
seeded 2/3 is snapped to 4 and `> 3` comes back TRUE.

```
gaps whose cube demands a list length outside {0,1,4}      152 of 777 (19.6 %)
  ... of which driven and CONTRADICTED                     116
variables involved                                           4
  ..._to_ary_notifications_{10254800,3aa8587a,c7e6a7ca,cf379872}_row_actors_row_rows
```

**This is a MOCK-DOMAIN fact, not an app fact, and it needs an owner ruling —
not more driving.** The honest options are (a) declare the pair
`(len > 1, len > 3)` on these four variables as a mock-domain constraint
(a `SymbolicConstraint`-shaped assumption: the mock's own codomain makes
`len > 1 -> len > 3` valid), or (b) widen the mock's snap domain, which is a
target-boundary change (Rule T) and reopens every endpoint. (a) is the
proportionate move and it is the same ruling §18.4 asked for and never got.

**The other 66** are nested-list lengths and one identity compare that the seed
does not control:

```
  10  (find_by_1_person_id == devise_user_first_1_person_id)     identity compare
  24  ..._row_target_photos_row_rows != 0                        (x4 aliases)
  16  ..._row_target_mentions_container_commentable_photos_...   (x4 aliases)
  15  ..._row_target_mentions_container_photos_row_rows          (x4 aliases)
   1  ..._records_tags_5fc4a296_rows == 0
```

These are the DEEPLY NESTED row lists — a photo list hanging off a mention's
container's commentable. `_c13_defect_audit.py` already flagged the family:
9 of the 142 constrained variables (the `records_photos_*_row_text_*` /
`_mention_inline_name` names) could not be seeded by ANY of 250 sampled bases.
They are candidates for a round-2 construction with a base that mints them, not
residue.

### §25.7 ROUND 1 — CERTIFIED by a fresh pass

`_c13_pass.sh _snapshot_c13_R1.txt R1` (116 164 runs = the C12 snapshot + this
round's 1 554 constructed dumps), coverage layer only, `MAX_MISSING_PER_CLIQUE=1`,
checkpointed to `_cov_c13_R1.ckpt.jsonl`:

```
COMPLETE=False;NODES=441;MISSING=207;BLOCKING=203;PCS=7331670
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
  coverage phase 599 s   total wall 33 min 42 s   peak RSS 4 877 MB
  demand_sets 1638   tree_complete TRUE   tree_missing []
  dump_errors {'ActionView::Template::Error': 37351, 'I18n::InvalidLocale': 1}
  file _cov_C13_R1.json
```

**The comparable metric is SETS WITH A GAP, not `missing_branches`** — C12 ran at
cap 4 (885 witnesses over 298 sets), R1 at cap 1 (227 witnesses over 227 sets).

```
                          C12 (cap 4)      R1 (cap 1)
  demand sets                 1 665           1 638
  SETS WITH A GAP               298             227      -71
  witness leaves (distinct)   777              203
  runs added this round                       1 554
  RATE                                        71 / 1554 = 0.046 closed/run
  wall (construct+drive+pass)                 ~2 h 40
```

Set-key bookkeeping, because the keys themselves move when the corpus grows:
of C12's 298 gap-sets, **33** are still demand sets and now CLEAN, **118** are no
longer demand sets at all (their member set changed as new co-evaluations
appeared — `co-evaluated-pairs` went 33 470 -> 33 486, tier2 22 514 -> 22 530),
and **80** sets that were clean in C12 have a gap in R1. Net −71. The churn is a
property of §16's co-evaluation universe, not of the drive, and it is why the
aggregate is the honest number.

**0.046 closed/run is just BELOW the RUNBOOK's ~0.05 stop rule, on ONE round.**
The rule is two consecutive rounds, so round 2 runs.

### §25.8 ROUND 2 — built, driven, explained

The 203 distinct witness leaves of R1 (227 sets with a gap, cap 1 so one witness
per set; 24 leaves shared between sets). Fresh corpus index over the 116 164-run
R1 snapshot (1 177 s), then `_c13_construct.py` (33 s):

```
seeds built 406 (203 x K=2)   substituted 696   kept out-of-domain 88
not seedable 0   inert-alias seeds 15   keys novel to the base 159
  set C  html_plain 34  html_typed 31  mobile_plain 71  mobile_typed 67
  set D  html_plain 19  html_typed 48  json_plain 56  json_typed 28
         mobile_plain 26  mobile_typed 26
_c13_drive.sh C13C 60   11:18 -> 11:24:47   +203 dumps   C13-DRIVE-DONE
_c13_drive.sh C13D 60   11:29 -> 11:36:30   +203 dumps   C13-DRIVE-DONE
```

```
=== PER KEY (1 278) ===          set C only          C + D
  HONOURED                     1 006 (78.7 %)     (see _c13_classify_R2.json)
  CONTRADICTED                    63 ( 4.9 %)
  NEVER-EVALUATED                209 (16.4 %)
=== PER GAP (203) ===
  REALISED                         4 ( 2.0 %)         7 ( 3.4 %)
  UNEVALUATED                    136 (67.0 %)       137 (67.5 %)
  CONTRADICTED                    63 (31.0 %)        62 (30.5 %)
replay dump errors (C+D) {'': 187, declared: 149, other: 38, faithful: 24, gon: 8}
```

**The realisation rate collapses from 23.8 % to 3.4 %** — which is what it
should do: round 1 took every leaf that a constructed run could take, and what
is left is dominated by the two classes round 1 named. 44 of the 203 (21.7 %)
demand a length outside the mock's {0,1,4} snap domain and 62 of them
CONTRADICTED on exactly that; the rest are the deep nested-row lists the seed
does not control and the `exists_/person_profile_not_found` arms that the walk
never reaches from any base.

### §25.9 ROUND 2 — CERTIFIED, and it closed NOTHING

`_c13_pass.sh _snapshot_c13_R2.txt R2` (116 570 runs = C12 snapshot + all 1 960
C13 dumps), coverage layer only, cap 1, checkpointed:

```
COMPLETE=False;NODES=441;MISSING=207;BLOCKING=203;PCS=7356295
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
  coverage phase 904 s   total wall 35 min 26 s   peak RSS 4 888 MB
  demand_sets 1638   tree_complete TRUE   tree_missing []
  file _cov_C13_R2.json   checkpoint _cov_c13_R2.ckpt.jsonl
```

```
  SETS WITH A GAP           R1 227  ->  R2 227
  R1 gap-sets closed in R2                      0
  R1 gap-sets no longer demand sets             0
  new gap-sets in R2                            0
  witness leaves (distinct)  R1 203  ->  R2 203   (identical set, identical
                                                  width histogram)
```

**Round 2 changed nothing.** 406 constructed runs on the checker's own 203
remaining leaves, driven on two different bases each, moved neither the demand
structure nor a single set.

### §25.10 THE RATE RULE FIRES — the loop stops here

```
 round | runs  | sets-with-a-gap | closed | closed/run | wall
   C12 |   —   |  298 (cap 4)    |   —    |     —      | (the input)
    R1 | 1 554 |  227            |   71   |   0.046    | ~2 h 40 (index 23 min,
       |       |                 |        |            |  construct 1, drive 41,
       |       |                 |        |            |  pass 34)
    R2 |   406 |  227            |    0   |   0.000    | ~1 h 15 (index 20 min,
       |       |                 |        |            |  construct 1, drive 14,
       |       |                 |        |            |  pass 35)
```

RUNBOOK Phase 2: *"Stop a method that falls below ~0.05/run for two rounds."*
0.046 then 0.000. **The loop stops**, and it stops with the residue EXPLAINED by
construction, not asserted.

### §25.11 THE RESIDUE — 203 leaves over 227 sets, every one CONSTRUCTED AND DRIVEN

Nothing below is called residue on the strength of "no run produced it". Each of
the 203 was built into a seed on two independently chosen bases and replayed;
`_c13_classify_R2.json` carries the per-key verdict.

```
 per KEY (1 278 demanded keys over the 203 leaves, 406 replay runs)
   HONOURED           1 029  (80.5 %)
   NEVER-EVALUATED      187  (14.6 %)
   CONTRADICTED          62  ( 4.9 %)
 per LEAF (203)
   CONTRADICTED  by the MOCK's snap domain            43   <- OWNER RULING
   CONTRADICTED  by a nested row length / identity    19   <- see below
   UNEVALUATED   (the walk never reaches a key)      137
   "REALISED" by the per-run test but still missing     4   <- see the caveat
```

**(a) 43 leaves (+ 1 more that went unevaluated) — the MOCK DOMAIN. Needs an
owner ruling; more driving cannot touch it.** `targets.rb`'s actors-list mock
snaps a length to **{0, 1, 4}** (`an = 0 if an.negative?; an = 4 if an > 1`,
§18.4). Both `> 1` and `> 3` are tracked decisions on that snapped variable, so
the checker legitimately demands `(len > 1) = true AND (len > 3) = false` — a
length in {2, 3}, which the mock cannot return. Measured, not argued: the
constructor found NO observed value satisfying the cube on those four variables
(88 "kept out-of-domain" values in round 2 alone), and the drive then showed
`> 3` coming back TRUE with the seed in place. Four variables:
`..._to_ary_notifications_{10254800,3aa8587a,c7e6a7ca,cf379872}_row_actors_row_rows`.
The proportionate fix is a declared mock-domain constraint
(`len > 1 -> len > 3` is VALID in the mock's codomain, a
`SymbolicConstraint`-shaped assumption); widening the snap domain is a
target-boundary change (Rule T) that reopens every endpoint. **This is the same
ruling §18.4 asked for on 2026-09-11 and did not get; it is now the single
largest identified block on this endpoint's `COMPLETE=True`.**

**(b) 19 leaves — deeply nested row lengths and one identity compare, not under
seed control.**

```
  ..._row_target_photos_row_rows != 0                            (x4 aliases)
  ..._row_target_mentions_container_commentable_photos_row_rows  (x4 aliases)
  ..._row_target_mentions_container_photos_row_rows              (x4 aliases)
  (find_by_1_person_id == devise_user_first_1_person_id)         identity
  ..._records_tags_5fc4a296_rows == 0
```

`_c13_defect_audit.py` had already flagged the family: 9 of the 142 constrained
variables (`records_photos_*_row_text_*`, `_mention_inline_name`) are seedable
by NONE of 250 sampled bases. A photo list hanging off a mention's container's
commentable is derived inside the mock chain rather than seeded at its head.
This is a CONSTRUCTOR reach problem, not an impossibility — but it needs a mock
that exposes the nested length as a seedable dimension, which is target-boundary
work (Rule T), so it goes to the owner with (a).

**(c) 137 leaves — UNEVALUATED, the walk never reaches a demanded key.** The
head of the never-reached list is stable across both rounds:

```
   14  devise_user_first_1_person_profile_not_found == True
   12  exists__5_exists == True
   12  exists__4_exists == True
    9/8/7  ..._row_actors_row_rows > 1   (three aliases)
    8  Relation_size_3_size > 0
   16  ..._row_target_mentions_container_not_found == True (x4 aliases)
```

These are the arms §24.6 called CONJUNCTION FORECLOSURE, and two rounds of
construction on gate-matched, alias-covering bases did not reach them. That is
now evidence FOR §19.2's proposal (infer foreclosure over the gate CONJUNCTIONS
the demand already contains) rather than a driving backlog — but the proposal
is a `src/` change and `src/` is untouched by this batch.

**(d) The caveat on "REALISED".** `_c13_classify.py` scores a key HONOURED when
the run took that decision the demanded way AT LEAST ONCE. A per-ROW decision is
evaluated many times in one run and can legitimately come back both ways, so
this test is WEAKER than the checker's leaf-covering test (which needs the run's
outcome over the set to BE the leaf). The 4 "realised" leaves that the checker
still reports are exactly that gap, and it is why the honest closure number is
the CHECKER's (298 -> 227), never the classifier's.

### §25.12 What C13 retracts, and what it confirms, in §24.6-24.8

- **RETRACTED: "genuinely REACHABLE-BUT-UNDRIVEN: 0 (0.0 %)".** On the checker's
  own witnesses, **71 demand sets closed on 1 554 constructed runs** in one
  round. §24.6's zero was computed over the EXACT ENUMERATOR's 11 787
  assignments with a corpus-scan test, not by constructing the checker's leaves;
  a combination no run had walked was not the same as a combination no
  constructed run COULD walk.
- **CONFIRMED: the class structure.** §24.8 said 3 153 of 3 155 undriven cubes
  were blocked by exactly ONE gate and that every top blocker was a
  `to_ary_notifications_*` list cardinality. Those same four aliases' row-list
  cardinalities are exactly what remains, in both the contradicted (a) and the
  unevaluated (c) classes.
- **CONFIRMED and SHARPENED: 73 % "conjunction foreclosure".** The unevaluated
  class survives two rounds of construction on matched bases (137 of 203
  leaves, 67 %), which is what a real foreclosure looks like from the driver's
  side. It is still not a driving problem.
- **NOT RE-TESTED HERE: the 7.9 % declared-unmodelled and 6.0 % faithful-error
  classes.** They are error-rate classifications over the residue's matching
  runs; the C13 replays reproduce the split (declared 149, faithful 24, gon 8,
  other 38 of 406 in round 2) but this campaign did not recompute §24.6's
  per-cube thresholding.

### §25.13 Ops record

Everything ran detached in `concolic-cov.slice`, waited on by polling
`systemctl --user is-active`, never from the agent's process tree:
`notif-c13-index-1/-2` (4G), `notif-c13-construct-1/-2` (4G),
`notif-c13-driveA/B/C/D-1` (6G, DRIVE_PAR=2, JRUBY_CAP=2G),
`notif-c13-passR1/R2` (9G scope, the pass itself capped 8G). Every launch >= 1 GB
went through `_wait_mem.sh`. Peak slice occupancy stayed under 15 GB of the
19-20 G cage while posts_show's P14/P15 campaign and this endpoint's own
`notif-c12-full-20260912` engine section were running.

**One interaction to note for whoever redoes the records.** The C13A/C13B drive
(09:34-10:18) wrote 1 554 new dumps into the batch DIRECTORY while
`notif-c12-full-20260912`'s gate audits were scanning that same directory
(289 733 dumps at their start). `run_dse.rb` writes each dump with a
non-atomic `File.write`, so a partial read was possible; no audit error was
observed, but that stage's audit rows are on a corpus that grew under them and
are due to be redone at closure anyway (they were already flagged for that).
Nothing of either running service was touched.

### §25.14 Artefacts

```
_c13_witness.py      checkpoint -> distinct witness leaves + the round's counts
_c13_index.py        corpus index: expr masks, alias-canonical masks, observed
                     domain, DERIVED reverse seed-key map   (~20 min / 116k dumps)
_c13_construct.py    the constructor (§25.3's four rules)
_c13_defect_audit.py the OLD-vs-NEW differential of §25.3
_c13_drive.sh        caged, resumable BY SEED ID, verdict C13-DRIVE-DONE
_c13_classify.py     per-key honoured / contradicted / never-evaluated
_c13_pass.sh         the coverage layer, checkpointed, verdict ^COMPLETE=
_c13_snapshot.sh     next round's dump list = base + this round's dumps
_c13_gaps.json / _c13_gaps_R2.json / _c13_gaps_R3.json   777 / 203 / 203 leaves
_cov_C13_R1.json  _cov_c13_R1.ckpt.jsonl    227 sets with a gap
_cov_C13_R2.json  _cov_c13_R2.ckpt.jsonl    227 sets with a gap  <- current
_c13_classify_C13.json (round 1)  _c13_classify_R2.json (round 2)
```

**To continue** (a round 3 is NOT indicated by the rate rule; this is the exact
command if the owner rules on (a)/(b) and wants the loop restarted):

```
cd /home/dev/project/reports/diaspora/results3/notifications_index
systemd-run --user --slice=concolic-cov.slice --unit=notif-c13-index-3 \
  -p MemoryMax=4G -p MemorySwapMax=0 --quiet \
  --working-directory=$PWD --setenv=PYTHONPATH=/home/dev/project/src \
  --setenv=C13_GAPS=$PWD/_c13_gaps_R3.json --setenv=C13_INDEX=$PWD/_c13_index_R3.pkl \
  --setenv=DUMP_LIST=$PWD/_snapshot_c13_R2.txt \
  bash -c 'python3 -u _c13_index.py > _c13_index_R3.log 2>&1'
# then, with C13_GAPS/_c13_index_R3.pkl and C13_PREF_A=_c13_seedsE_ /
# C13_PREF_B=_c13_seedsF_ / C13_MANIFEST=_c13_manifest_R3.json:
#   _c13_construct.py  ->  _c13_drive.sh C13E 60 / C13F 60  ->
#   _c13_snapshot.sh R3 'dump_*_C13[A-F]*.json'  ->  _c13_pass.sh ..._R3.txt R3
```

## §26. RESIDUE (a) RULED ON — the mock's codomain is DECLARED, not widened (2026-09-12)

§25.11(a) sent the owner one question: 44 of the 227 gap-sets demand an
actors-list length in {2, 3}, which `targets.rb`'s mock cannot mint, and the
two honest options were (a) declare the codomain or (b) widen the snap domain.
**(b) is a Rule T change to the shared target boundary and was NOT made.** This
section is (a), carried through: declared, gated, and re-measured on the same
snapshot.

### §26.1 The declaration — eight constraints, and why eight

`coverage_assumptions._msnap_actors_domain` (tier `M-SNAP`, its own counter on
the `[assumptions]` line, kill switch `NO_MSNAP=1`). One
`SymbolicConstraintAssumption` per (variable x hole), emitted only for a
variable on which the corpus actually records the `> 3` decision:

```
SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_ary_notifications_10254800_row_actors_row_rows != 2
SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_ary_notifications_10254800_row_actors_row_rows != 3
SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_ary_notifications_3aa8587a_row_actors_row_rows != 2
SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_ary_notifications_3aa8587a_row_actors_row_rows != 3
SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_ary_notifications_c7e6a7ca_row_actors_row_rows != 2
SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_ary_notifications_c7e6a7ca_row_actors_row_rows != 3
SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_ary_notifications_cf379872_row_actors_row_rows != 2
SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_ary_notifications_cf379872_row_actors_row_rows != 3
```

**Why the holes and not the implication.** The claim is `len > 1 -> len > 3`,
i.e. `len NOT IN {2,3}`. Written as `Or(Not(VAR > 1), VAR > 3)` the gate cannot
test it: `assumption_checker.test_declared` derives a SymbolicConstraint's
falsifying probe only for a constraint of the form `VAR op INT`, and returns
NOT-TESTABLE for anything else — and a NOT-TESTABLE is not a licence (§24.4).
Split into the two holes, each declaration is `VAR != k`, the gate derives the
violating value k, and the conjunction is exactly the implication:
`(>1)=True AND (>3)=False` needs a length in {2,3} and is now UNSAT
(verified directly against Z3 with the batch's own bounds low=0/high=4; every
other cube on the variable — `==0`, `(>1)=False`, `(>1)=True AND (>3)=True` —
stays SAT).

**Why a constraint and not a bound.** The 2026-08-26 coordinator directive is
that a list length's domain is declared as SymbolicVar BOUNDS
(`coverage_report.apply_len_bounds`), never as a constraint. That directive is
already followed for this variable: it carries `low = 0, high = 4` there. A
bound is an INTERVAL; this domain is {0,1,4} = [0,4] with two holes punched in
it, and the holes are the one part of the same domain fact a bound cannot
state. Nothing else is claimed: 0, 1, 4 and the interval itself are untouched.

### §26.2 The evidence — ground truth, twice, before the gate

**(i) The whole corpus.** Over the 116 570-run R2 snapshot the actors-length
SymbolicVar is minted **111 590** times:

```
   value 0  ->  13 774        value 1  ->  49 947        value 4  ->  47 869
   value 2  ->       0        value 3  ->       0
```

Not one run has ever recorded a value in {2, 3}. (~90 s over the dump list;
re-derivable at any time.)

**(ii) The falsifier, run directly** (`_m1_gtprobe.sh`, 6 SEEDS_ONLY replays of
one rich `html_plain` snapshot, 8.8 s). Seed the LIVE (ordinal) key
`len(SYM_RESULT_ActiveRecord__Relation_to_ary_1_row_actors_row_rows)` to 0..5
and read back what the mock MINTED, with the three decisions it records:

```
  seed  minted   (== 0)   (> 1)   (> 3)
     0       0    True    False   False
     1       1    False   False   False
     2       4    False   True    True     <- the demanded (>3)=False is NOT reachable
     3       4    False   True    True     <- ditto
     4       4    False   True    True
     5       4    False   True    True
```

That IS the falsifier the declaration names ("any run in which the mock returns
a length in {2,3}"), and it does not refute: the codomain is exactly {0, 1, 4}
and `> 3` comes back TRUE for every seed above 1, as §25.6 said. Dumps kept in
`_m1_probe_dumps/`.

### §26.3 The gate — 8/8 PASS, and the PASS is VACUOUS

`_m1_gate.sh`: `assumption_checker.py assumption_manifest.json --declared
_msnap_declared.json --keep`, caged (7 G scope in an 8 G service),
`ACHK_CHECKPOINT=_m1_probe_checkpoint.jsonl`, `CONCOLIC_SLOTS=2`,
`CONCOLIC_PROBE_WORKERS=1`. Corpus index over the batch directory's 291 693
dumps took ~20 min; 8 distinct probes in 2 JRuby launches; 21 min 57 s wall,
peak RSS 3 075 MB.

```
== derived assumption tests: 8 declared ==
RESULT: 8 distinct tested — PASS 8, FAIL 0, ERROR 0, NOT-TESTABLE 0, NOT-COMPARABLE 0
  PASS  SymbolicConstraintAssumption
     excluded region (len(..._10254800_row_actors_row_rows)=2) adds no access shapes
     (snapshot dump_html_plain_dse0016_C13Bhtmp0000r0.json)                    ... x8
```

**All eight PASSes were audited against the probe dumps they were earned on,
and none of them put the violating value on the LIVE dimension. They are
vacuous, and the reason is a NEW instance of the X10 key class.** Mechanism,
measured:

* `canonicalize_ordinals` deliberately leaves `concolic_seeds` ORDINAL-named
  ("they are what the RUNTIME consumes"). The C13 constructor, however, also
  writes CANONICAL-named seed keys into the seed dicts it builds — dead knobs
  the runtime never reads.
* `pick_snapshot(batch, dim)` therefore DOES find a snapshot for the canonical
  `dim`: it matches one of those dead knobs.
* On that snapshot the live ordinal `..._to_ary_1` resolves to a DIFFERENT
  canonical name than the declaration's (e.g. `dump_html_plain_dse0016...`
  aliases `to_ary_1 -> ..._3aa8587a`, while the declaration under test names
  `..._10254800`), so `_runtime_key(sd, dim)` finds nothing to map and returns
  the canonical key unchanged.
* The gate then writes `2` / `3` at the dead canonical key. Read back from the
  probe dumps: the live `len(..._to_ary_1_row_actors_row_rows)` was **1 (minted
  1)** in the four `html_typed` probes and **2 (minted 4)** in the four
  `html_plain` ones — in the snapshot's own seeds, never from the gate.

So the gate certified "excluding 2 and 3 hides no access shape" on runs whose
live actors length was 1 or 4. It is a PASS, it is not a FAIL, and it is not
evidence. `pick_snapshot` and `_runtime_key` are `src/`; this is filed, not
patched.

**What the gate CAN test for a domain constraint, even when it works.** Its
probe seeds the violating value and compares TARGET-CALL SHAPES: it can only
say whether the excluded region hides behaviour. It can never test the codomain
claim itself, because under a SNAPPING mock the seed 2 is not the value 2 — the
run it measures is a length-4 run. That the holes exist is established by the
source (`targets.rb:744-755`), by §26.2(i) and by §26.2(ii), not by the probe.
X11 applies as everywhere: the probes detect ADDITIVE effects only.

### §26.4 A differential on 800 runs, before spending the pass

`NO_MSNAP=1` vs. default over the first 800 runs of the R2 snapshot, same
`MAX_MISSING_PER_CLIQUE=1`:

```
                         M-SNAP off     M-SNAP on
  demand sets                   783           783
  MISSING                       705           707
  witnesses of the FORBIDDEN cube 8             0
  tree_missing                   46            46
  assumptions_used           11 387        11 387
```

Two things this settles before the full pass. The constraint parses (a
constraint Z3 cannot parse makes `check_satisfiability` return UNSAT for EVERY
query — `solver.py:186` — and that failure mode looks exactly like
completeness; it did not happen). And **removing an impossible witness does not
by itself close a set**: at cap 1 the solver simply returns the next uncovered
cube, so `MISSING` can go UP. What the declaration buys is that the witness the
constructor is handed is now a REACHABLE one.

### §26.5 THE PASS — 43 of the 44 sets CLOSED

`_c13_pass.sh _snapshot_c13_R2.txt M1` — the SAME 116 570-run snapshot, the
same engine (`coverage.py` md5 270be964bc7de60bfb9390108938411f), the same
`MAX_MISSING_PER_CLIQUE=1`, `SKIP_COMPLETION=1`, checkpointed to
`_cov_c13_M1.ckpt.jsonl`. Only the assumption set differs, by these eight
declarations (`[assumptions] ... M-SNAP(mock-codomain-holes)=8`, every other
tier's count byte-identical to R2).

```
                          R2 (before)                       M1 (after)
  verdict   COMPLETE=False;NODES=441;          COMPLETE=False;NODES=441;
            MISSING=207;BLOCKING=203;          MISSING=165;BLOCKING=161;
            PCS=7356295                        PCS=7356295
            GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]   (both)
  demand sets                 1 638                            1 638
  tree_complete / tree_missing TRUE / 0                        TRUE / 0
  SETS WITH A GAP               227                              184     -43
  witness leaves (distinct)     203                              161     -42
  leaves demanding {2,3}         44                                0     -44
  coverage phase                904 s                            813 s
  wall / peak RSS         35 min 26 s / 4 887 MB          32 min 31 s / 4 888 MB
```

Set-key bookkeeping on the identical demand universe (no churn to explain away
this time — the corpus did not move, so the set keys are the same objects):

```
  gap-sets before                    227
  gap-sets after                     184
  closed                              43     <- ALL of them contradiction-carrying
  newly gapped                         0
  of the 44 contradiction-carrying sets: 43 CLOSED, 1 still has a gap
```

**The one survivor** (`16b3d8de…`) is the point of the exercise: its witness
was `(actors > 1)=True AND (actors > 3)=False`, which nothing could ever drive;
it is now

```
  (…_10254800_rows > 1)=False   (…_10254800_row_actors_row_rows == 0)=False
  (…_row_actors_row_rows > 1)=True   (…_row_actors_row_rows > 3)=True
  (…_row_recipient_not_found == True)=False
  (…records_aspect_memberships_ae3fcf22_rows > 1)=True
  (…records_aspect_memberships_6f13edc1_rows > 1)=True
  (…_row_actors_row_id == …devise_user_first_1_person_id)=False
```

an actors list of 4 with two many-arm aspect_membership loops — a REACHABLE
cube and an ordinary driving target. That is the whole value of the
declaration beyond the 43: where a set still has a gap, the witness the
constructor is handed is now one a run can actually walk.

**Do not read the leaf diff as "42 impossible leaves removed".** At cap 1 the
witness of a set is whichever uncovered cube Z3 returns first, and that choice
moves when the constraint moves: leaf-wise the diff is 70 gone / 28 new /
133 kept, and 44 of the 70 are the forbidden cube. The stable, comparable
numbers are SETS WITH A GAP (227 -> 184) and the forbidden-cube count
(44 -> 0). All 28 new leaves are reachable-shaped; the family they cluster in
is §25.11(b)'s nested `…_target_photos_row_rows` / `…_mentions_container_…`
lengths, which is now the largest identified block on this endpoint.

### §26.6 Where the endpoint stands, and what residue (a) leaves behind

```
  C12 (cap 4)  298 sets with a gap
  C13 R1       227   (-71, 1 554 constructed runs)
  C13 R2       227   ( -0,   406 constructed runs)  <- rate rule fired, §25.10
  M-SNAP       184   (-43,       0 runs)            <- a declaration, not a drive
```

Residue (a) is CLOSED: 0 of the 184 remaining gap-sets demand a length the mock
cannot mint. §25.11's classes (b) 19 nested-row-length leaves, (c) 137
unevaluated and (d) 4 "realised" are untouched by this section and are still
the standing account of what is left; (b) and (c) both need target-boundary
work or the §19.2 `src/` foreclosure inference, neither of which is this
batch's to make.

**What this section did NOT do.** It did not widen the mock (Rule T). It did
not run a C13 round 3 (the rate rule stands). It did not re-run the engine
section, the audits or the shims — this is the coverage layer only
(`SKIP_COMPLETION=1`), so `COMPLETE=False` here is the coverage verdict and
nothing is claimed about completion. No policy was extracted.

### §26.7 Ops

Everything detached in `concolic-cov.slice`, polled by
`systemctl --user is-active`, never from the agent's process tree; the unified
memory rule (`_wait_mem.sh`) ran before every launch >= 1 GB and both numbers
are in `_m1.log` / `_c13.log`.

```
  notif-m1-gate-20260912     8 G service / 7 G scope   21 min 57 s   peak 3 075 MB
      LAUNCH: free=49G cage_headroom=13911MB cap=7168MB
  notif-m1-gtprobe-20260912  4 G service / 3 G scope        8.8 s    one JRuby
  notif-m1-pass-20260912     9 G service / 8 G scope   32 min 31 s   peak 4 888 MB
      LAUNCH: free=45G cage_headroom=14755MB cap=8192MB
```

Cage peak stayed under 10 GB of the 19 GiB `MemoryMax` while posts_show's
P14 campaign ran; `notif-c12-s23-queued-20260912` (the C12 stage-2 restart,
still waiting on posts_show's engine section) was NOT touched and never
overlapped a pass of this section.

The 14 probe dumps the two probe stages wrote into the batch directory
(8 `dump_*_achkmsnap_*` from the gate's `--keep`, 6 `dump_*_msnapgt`) were
MOVED OUT to `_m1_probe_dumps/` as soon as both finished, so the batch
directory the audits scan is back to its 291 693 dumps and no dump list
changed. They are kept, not deleted: they are §26.2(ii)'s and §26.3's evidence.

### §26.8 Artefacts

```
coverage_assumptions.py     _msnap_actors_domain + the M-SNAP block (NO_MSNAP=1
                            disables); backup of the previous file in
                            _bak_coverage_assumptions_pre_msnap_20260912.py
_msnap_declared.json        the 8 declarations, as the gate consumed them
_m1_gate.sh / _m1_gate.log / _m1_gate_results.json / _m1_rows.jsonl
_m1_probe_checkpoint.jsonl  ACHK_CHECKPOINT (8/8 probes recorded)
_m1_gtprobe.sh / _m1_gtprobe.log / _msnap_gt_seeds.json / _msnap_gt_meta.json
_m1_probe_dumps/            14 probe dumps (gate x8, ground truth x6)
_m1_compare.py              the before/after census on two coverage checkpoints
_m1_contradicted_setkeys.json  the 44 set keys, recorded BEFORE the pass
_cov_C13_M1.json / _cov_c13_M1.ckpt.jsonl / _c13_cov_M1.log   the M1 pass
```

**To reverse this section in one line:** `NO_MSNAP=1` on the pass. **To
withdraw it for cause:** any dump whose `len(…_row_actors_row_rows)` carries 2
or 3 refutes it, and a Rule T widening of the snap domain refutes it by
construction.

## §27. C14 — EVERY REMAINING CUBE, NOT ONE WITNESS PER SET (2026-09-12)

### §27.1 Why the round exists

§25's C13 rounds built ONE seed per demand set, because the checker at
`MAX_MISSING_PER_CLIQUE=1` prints one witness per set (§16d). A round built
that way can close AT MOST ONE LEAF PER SET however many runs it drives — the
same ceiling posts_show hit (§80). The RUNBOOK's driver-level batching rule
says the opposite: take EVERY remaining cube from the EXACT ENUMERATOR (which
is not capped), construct all of them by per-set overlay, drive them as one
batch, and run the expensive checker pass ONCE, to certify. C14 is that round.
No `src/`, no `targets.rb`, no new declaration.

### §27.2 The enumeration — 10 319 remaining cubes

`_exact_enum.py` with `EMIT_REMAINING`, on the SAME corpus the M1 verdict was
measured on (`_snapshot_c13_R2.txt`, 116 570 runs) and the SAME assumption set
(M-SNAP included — the enumerator loads `coverage_assumptions` like the pass
does). Caged 5 G service, streamed to `_c14_enum.log`.

```
nodes(active)=432 untracked=9 pinned=1 cliques=1596     (universe built 1 428 s)
EXACT: satisfiable=86535 covered=76216 remaining=10319 bounded_cliques=0
       census wall 167 s   total wall 26 min 40 s   peak RSS 4 701 MB
EMIT_REMAINING: emitted count == counted remaining, on every leaf group
                — the two computations agree exactly.
REACHABILITY SPLIT: leaf groups 5 069 with an observed compatible walk, 208 with none
       REACHABLE remaining 8 591 (83.3 %)   UNREACHABLE 1 728
```

The 10 319 cubes distribute over **599 demand sets** and **1 006 LEAF GROUPS**
(set x gate prefix):

```
  cubes per set    1:49 2:49 3:28 4:46 5:22 6:34 7:23 8:21 9:10 10:18 ...
                   largest 132, 132, 114, 110, 106, 100, 99, 96
  cubes per group  1:66 2:78 3:52 4:143 5:32 6:56 7:40 8:172 ...
  width            4:798 5:2224 6:257 7:1607 8:840 9:626 10:417 11:409
                   12:463 13:1199 14:460 15:402 16:269 17:284 18:64
  distinct expressions over all cubes: 277
```

**Against C13, this is 10 319 cubes where the checker printed 161.** The
ceiling is what the round is aimed at.

### §27.3 The two instruments do not agree on WHAT is left — so the batch is the UNION

The M1 checkpoint's 184 gap-sets carry **159 distinct witness leaves**. Of
those, **81 appear among the enumerator's 10 319 and 78 do not**. The
enumerator's covered test (a run's evaluated members must be EXACTLY the leaf's
survivors) and the checker's blocking clauses (a run blocks a CLOSED PREFIX)
are not the same test, so their residues are not the same object — and the
verdict line `COMPLETE/MISSING` is the CHECKER's. Driving only the enumerator's
list would leave 78 of the checker's own witnesses untouched, so
`_c14_add_witnesses.py` appends them:

```
  enumerated remaining cubes                10 319   (1 006 leaf groups)
  checker witnesses appended                    78   (78 one-cube groups)
  BATCH                                     10 397   (1 084 groups)
```

A checker witness has no separate gate prefix to hand (§25.2: the combo is one
gates-first object), so its `pre` is the whole cube and the base rule falls
back to C13's whole-cube match for exactly those 78.

### §27.4 The construction — per-LEAF-GROUP overlay, one base per group

`_c14_construct.py`. It reuses `_c13_construct`'s value rules verbatim (§25.3's
four repairs, UNSEED, both `len` spellings, the DERIVED reverse seed-key map),
and changes two things.

**Base choice is per LEAF GROUP, not per cube.** A leaf group is
(demand set x gate prefix), which is the granularity at which "gate-matched"
is even well defined: two leaf groups of ONE set pin different gates, so one
base per SET cannot be gate-matched for both. Every cube of the group is then
overlaid on that one base.

**The choice is done with inverted bitsets, and it is §19.4's installed rule.**
At 440 expressions almost every dump is its own profile (115 233 of 116 570),
so C13's score-every-profile loop would be 1.3e8 iterations. Instead one big
int per (expr, polarity) and per alias canonical over the profiles, then
intersect GREEDILY, never emptying the candidate set, in the order

```
   alias canonicals  ->  gate prefix literals  ->  the group's member decisions
```

and take the seed-richest survivor. 21 s for all 1 084 groups.

```
cubes 10 397   leaf groups 1 084   distinct base runs used 359   K=1
  set A html_plain 2918  html_typed 2766  json_plain 975  json_typed 297
        mobile_plain 1336  mobile_typed 2105  xml_plain 0
seeds built                              10 397
values SUBSTITUTED                       70 116
values kept OUT-OF-DOMAIN                     0   <- M-SNAP; C13 R2 had 88
values NOT SEEDABLE                           0
variables with no satisfying value            0
seeds with an INERT alias                     0   (alias coverage 10 397/10 397)
seeds on a base NOT walking the whole gate prefix  654
keys novel to the base                    6 593
  wall 25 s   peak RSS 345 MB
per-seed base quality:  gate-perfect 9 743/10 397   alias-perfect 10 397/10 397
                        member-walk-perfect 9 245/10 397
```

**`values kept out-of-domain` is 0, and that is the M-SNAP declaration paying
off in the constructor rather than in the pass.** C13 R2 had 88 of them (the
{2,3} actors lengths no run can mint); with §26's holes declared, the
enumerator no longer emits a single cube that demands one.

### §27.5 The §19.2 FALSIFIER, computed — and it agrees with the enumerator exactly

`_c14_falsifier.py` runs §19.2's own test on the whole 116 570-run corpus, per
leaf group: A = runs agreeing with every literal of the gate prefix `P`;
B(d) = those of A that also EVALUATE member `d`. **B > 0 is the falsifier**
(the conjunction does not foreclose `d`, so the demand is driving backlog);
B = 0 with A > 0 is the evidence FOR the inference. Inverted bitsets over runs,
3 s.

```
  leaf groups                                   1 084   cubes 10 397
  FULLY FALSIFIED (A>0, every member reached)     798   cubes  8 591
  some member with B=0                            208   cubes  1 728
     ... of which A=0 (no run matches P at all)   166   cubes    654
     ... of which A>0  -> §19.2 WOULD FIRE        120*  cubes  1 152
  (* 208 - 88 groups whose members are all B=0 under A=0; the other 78 A=0
     groups are the appended checker witnesses, which have no member split)
```

**Two independent computations agree to the unit.** The enumerator's own
reachability split calls 8 591 of the 10 319 REACHABLE and 1 728 UNREACHABLE;
the falsifier, computed from run bitmasks with no solver, puts exactly 8 591
cubes in FULLY-FALSIFIED and exactly 1 728 in "some member never evaluated
under its own gate conjunction". The enumerator's UNREACHABLE class and
§19.2's inference-candidate class are the same object.

**What the owner gets from this, either way.** §19.2 as specified requires
"some profile matches `P`". So implementing it would remove **1 152 of 10 397
cubes (11.1 %)** from the demand, over 120 leaf groups — and it would NOT
touch the 576 cubes / 88 groups where NO run matches the gate prefix at all
(that is §13.3's multi-gate-unreachable class, a different question), nor the
8 591 that the corpus itself falsifies. **83 % of this batch is driving
backlog by §19.2's own test**, which is why it was driven rather than
classified.

Head of the B=0 list (groups with B=0 / groups demanding the member):

```
   140/284   devise_user_first_1_person_profile_not_found == True
    24/34    find_by_3_not_found == True
    22/250   ..._10254800_row_actors_row_rows > 1     (and 5 siblings at 22/220-259)
     8/8     find_by_1_profile_not_found == True
```

Mask semantics, stated because they bound the claim: the index records `em`
(evaluated at least once) and `tm` (taken TRUE at least once), so "agrees with
`P`" is read per-literal as "took it that way at least once". A per-ROW
decision can go both ways in one run, so this test can only OVERSTATE A and B
— a B = 0 verdict is conservative in the direction that matters.

### §27.6 The drive

```
_c13_drive.sh C14A 200   (SEEDSET=A, C13_PREF_A=_c14_seeds_,
                          C13_MANIFEST=_c14_manifest.json)
   detached: notif-c14-driveA-1 (8 G service), DRIVE_PAR=2, CONCOLIC_SLOTS=3,
   JRUBY_CAP=2G, every JRuby in its own scope inside concolic-cov.slice with
   `wait_mem 4096` before each launch; resumable BY SEED ID.
```

```
   corpus before 291 693 dumps -> after 302 089  (+10 396)
   6 legs, every one with its own `=== CHUNK DRIVE C14A END ===`; 55 chunks
   all `DONE consumed=N/N tries=1 toxic=0`; xml_plain 0 seeds (stated)
   VERDICT  C13-DRIVE-DONE C14A  +10 396 dumps  0 seeds left
   17:46:34 -> 19:37:17   1 h 50 min   ~1.6 runs/s at DRIVE_PAR=2
```

One seed of 10 397 produced no dump (10 396 dumps for 10 397 seeds) and the
classifier reports it as the single NOT-DRIVEN gap; it is counted, not hidden.

### §27.7 The round explained PER KEY — 96.6 % honoured, 73.7 % of cubes REALISED

`_c13_classify.py` over the 10 396 replays (`TAG=C14A`,
`C13_GAPS=_c14_gaps.json`), the SAME classifier and the same definition of
HONOURED that scored C13:

```
=== PER KEY (92 449 demanded keys) ===        C13 R2 (for comparison)
  HONOURED         89 351  (96.6 %)             1 029  (80.5 %)
  CONTRADICTED        257  ( 0.3 %)                62  ( 4.9 %)
  NEVER-EVALUATED   2 832  ( 3.1 %)               187  (14.6 %)
  NOT-DRIVEN            9  ( 0.0 %)
=== PER CUBE (10 397) ===
  REALISED (one run took the WHOLE cube)  7 660  (73.7 %)   C13 R2: 3.4 %
  UNEVALUATED                             2 479  (23.8 %)   C13 R2: 67.5 %
  CONTRADICTED                              257  ( 2.5 %)   C13 R2: 30.5 %
  NOT-DRIVEN                                  1
replay dump errors {'': 4864, declared: 3980, other: 716, faithful: 708, gon: 128}
```

**7 660 of the enumerator's own uncovered assignments were taken WHOLE by one
constructed run each.** That is the ceiling coming off: C13's rounds could not
have realised more than one leaf per set however many runs they drove.

The 257 contradicted keys are dominated by ONE identity compare
(169: `find_by_1_person_id == devise_user_first_1_person_id`) and by §25.11(b)'s
deeply nested row lengths (`_row_target_photos_row_rows`,
`_row_target_mentions_container_{commentable_,}photos_row_rows`, 6 each x 4
aliases) — the same family, unchanged, and still not under seed control.

### §27.8 ROUND 1 — CERTIFIED. 184 gap-sets -> 105

`_c14_pass.sh _snapshot_c14_R1.txt C14R1` (126 966 runs = the R2 snapshot + all
10 396 C14A dumps), coverage layer only (`SKIP_COMPLETION=1`), the SAME engine
(`coverage.py` md5 270be964bc7de60bfb9390108938411f), `MAX_MISSING_PER_CLIQUE=1`,
checkpointed.

```
                        M1 (before)                    C14 R1 (after)
  verdict  COMPLETE=False;NODES=441;      COMPLETE=False;NODES=441;
           MISSING=165;BLOCKING=161;      MISSING=85;BLOCKING=81;
           PCS=7356295                    PCS=8087584
           GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]  (both)
  demand sets           1 638                          1 630
  tree_complete/missing TRUE / 0                       TRUE / 0
  SETS WITH A GAP         184                            105      -79
  witness leaves (dist.)  161                             81      -80
  coverage phase          813 s                        1 411 s
  wall / peak RSS   32 min 31 s / 4 888 MB     48 min 45 s / 5 279 MB
  file              _cov_C13_M1.json           _cov_C14_C14R1.json
  checkpoint        _cov_c13_M1.ckpt.jsonl     _cov_c14_C14R1.ckpt.jsonl
```

Set-key bookkeeping (`_m1_compare.py` on the two checkpoints):

```
  gap-sets before 184   after 105
  still gapped     81      closed 103      newly gapped 24
```

**79 net, 103 gross.** For comparison, every earlier round on this endpoint:

```
  round       | runs   | sets with a gap | closed | closed/run | wall
  C12 (cap 4) |   —    | 298             |   —    |     —      | (input)
  C13 R1      |  1 554 | 227             |   71   |   0.046    | ~2 h 40
  C13 R2      |    406 | 227             |    0   |   0.000    | ~1 h 15
  M-SNAP      |      0 | 184             |   43   |     —      | a declaration
  C14 R1      | 10 396 | 105             |   79   |   0.0076   | ~4 h 00
```

### §27.9 ROUND 2 — the residue re-enumerated, constructed and driven

`_exact_enum.py` again, on the R1 corpus (`_snapshot_c14_R1.txt`, 126 966 runs):

```
EXACT: nodes=432 cliques=1598 satisfiable=86575 covered=84032 remaining=2543
       bounded_cliques=0   census 237 s   wall 31 min 29 s   peak RSS 5 108 MB
EMIT_REMAINING: emitted == counted, on every leaf group
REACHABILITY SPLIT   REACHABLE remaining 815 (32.0 %)   UNREACHABLE 1 728
   remaining 10 319 -> 2 543   over 142 demand sets, 354 leaf groups
   + 12 checker witnesses not already in it (79 distinct over 105 gap-sets,
     67 already present)  ->  BATCH 2 555 cubes in 366 groups
```

**The UNREACHABLE count did not move: 1 728 before the drive, 1 728 after.**
The whole of round 1's 79-set closure came out of the REACHABLE class, which
fell 8 591 -> 815 (90.5 % of it closed by 10 396 runs).

```
_c14_construct.py (6 s)  2 555 seeds, 170 distinct bases,
   substituted 18 380   kept out-of-domain 0   not seedable 0   inert alias 0
   seeds on a base not walking the whole gate prefix 588   keys novel 295
_c13_drive.sh C14B 200   21:12:35 -> 21:33:22   20 min 47 s   +2 555 dumps
   VERDICT C13-DRIVE-DONE C14B, 0 seeds left, every leg with its END line,
   all chunks `consumed=N/N tries=1 toxic=0`
_c13_classify.py TAG=C14B
   PER KEY (30 255)  HONOURED 27 606 (91.2 %)  CONTRADICTED 178 (0.6 %)
                     NEVER-EVALUATED 2 471 (8.2 %)
   PER CUBE (2 555)  REALISED 202 (7.9 %)  UNEVALUATED 2 175 (85.1 %)
                     CONTRADICTED 178 (7.0 %)
```

### §27.10 THE §19.2 FALSIFIER AFTER 10 396 CONSTRUCTED RUNS — it did not move

`_c14_falsifier.py` re-run on the 126 966-run corpus against the 2 555-cube
residue:

```
                                   R1 batch (116 570 runs)   R2 residue (126 966)
  leaf groups                             1 084                     366
  cubes                                  10 397                   2 555
  FULLY FALSIFIED (A>0, all members hit)  798 / 8 591 cubes    146 /   815 cubes
  some member B=0                         208 / 1 728 cubes    208 / 1 728 cubes
     ... A=0 (no run matches P)            88 /   576 cubes     88 /   576 cubes
     ... A>0  -> §19.2 WOULD FIRE          120 / 1 152 cubes    120 / 1 152 cubes
```

**Identical, to the group and to the cube.** 10 396 constructed runs, honoured
at 96.6 % per key on gate-matched and alias-matched bases, did not cause ONE
member of ONE B=0 group to be evaluated under its own gate conjunction. That
is the strongest form the §19.2 evidence can take from the driver's side: the
class is not a driving backlog, and the drive that emptied 90 % of the
falsifiable class left this one untouched.

For the owner's decision, sized on the residue:

```
  §19.2 as specified ("some profile matches P, none evaluates d")
     would remove  1 152 of the 2 543 remaining cubes (45.3 %) over 120 groups
  it would NOT touch    576 cubes / 88 groups where NO run matches P at all
                        (§13.3's multi-gate-unreachable class — a different
                         question, and NOT what §19.2 proposes to infer)
```

Head of the B=0 list on the residue (B=0 groups / groups demanding the member):

```
   140/182  devise_user_first_1_person_profile_not_found == True
    24/28   find_by_3_not_found == True
    22/72..89  the four `to_ary_notifications_*` rows / row_actors_row_rows > 1
     8/8    find_by_1_profile_not_found == True
```

### §27.11 ROUND 2 — CERTIFIED. 105 -> 103, and the RATE RULE FIRES

`_c14_pass.sh _snapshot_c14_R2.txt C14R2` (129 521 runs = the C13 R2 snapshot +
all 12 951 C14 dumps), same engine, cap 1, checkpointed.

```
  COMPLETE=False;NODES=441;MISSING=83;BLOCKING=79;PCS=8248527
  GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
  demand sets 1 630   tree_complete TRUE   tree_missing 0
  coverage phase 1 621 s   wall 54 min 31 s   peak RSS 5 228 MB
  file _cov_C14_C14R2.json   checkpoint _cov_c14_C14R2.ckpt.jsonl
  SETS WITH A GAP  105 -> 103   closed 2   newly gapped 0
```

```
  round       | runs   | sets with a gap | closed | closed/run | wall
  C12 (cap 4) |   —    | 298             |   —    |     —      | (input)
  C13 R1      |  1 554 | 227             |   71   |   0.046    | ~2 h 40
  C13 R2      |    406 | 227             |    0   |   0.000    | ~1 h 15
  M-SNAP      |      0 | 184             |   43   |     —      | a declaration
  C14 R1      | 10 396 | 105             |   79   |   0.0076   | ~4 h 00
  C14 R2      |  2 555 | 103             |    2   |   0.00078  | ~2 h 00
```

RUNBOOK Phase 2: *"Stop a method that falls below ~0.05/run for two rounds."*
0.0076 then 0.00078. **The loop stops** — and it stops having taken the
endpoint from 184 gap-sets to 103 with the residue explained by construction,
not asserted.

### §27.12 THE RESIDUE — 103 gap-sets, 77 witness leaves, EVERY ONE CONSTRUCTED AND DRIVEN

`_c14_residue.py` joins each of the 77 distinct witness leaves of
`_cov_c14_C14R2.ckpt.jsonl` to (a) whether a C14 seed was built for that exact
cube and driven, (b) the classifier's per-key verdict on those replays, and
(c) the §19.2 falsifier for each of its members.

```
  leaves NOT IN ANY C14 BATCH                 0    <- nothing is residue by default
  leaves REALISED by the classifier           0
  leaves CONTRADICTED (a decision flipped
     back despite its seed)                  26  leaves / 26 gap-sets
  leaves UNEVALUATED                         51  leaves / 77 gap-sets
  leaves with >= 1 member that is B=0 under
     its own gate conjunction              77 of 77   <- ALL of them
```

Split by §19.2's own premise ("some profile matches `P`"):

```
                                        leaves   gap-sets
  A > 0  — §19.2 WOULD FIRE                57        71
     ... of them CONTRADICTED              26        26
     ... of them UNEVALUATED               31        45
  A = 0  — no run matches the gate
           conjunction at all              20        32
```

**Every remaining leaf on this endpoint carries a member that no run has ever
evaluated under the leaf's own gate conjunction.** After 12 951 constructed
runs at 96.6 % / 91.2 % per-key honour on gate-matched, alias-matched bases,
there is no leaf left whose obstacle is the driver.

### §27.13 The classification, per key, with what each one needs

**(1) DRIVER-FIXABLE — 0.** Two rounds, 12 951 constructed runs, the rate rule
fired, and the classifier realises none of the 77. Nothing here is fixed by a
better base, a better resolver or more runs; §19.4's gate rule, §19's alias
rule and §25.3's resolver are all in force and measured
(alias coverage 12 952/12 952 seeds, gate-perfect 9 743 + 1 967).

**(2) `src/` INFERENCE — §19.2, 71 of the 103 gap-sets. REPORTED, NOT MADE.**
`coverage.py::infer_foreclosures` is strictly PAIRWISE, so a decision
foreclosed by two gates ACTING TOGETHER is never inferred and its cubes stay
demanded forever. §19.2 proposes inferring the same relation over the gate
CONJUNCTIONS the demand already contains. The falsifier is its own test and it
is now run twice, on two corpora 12 951 runs apart:

```
                       before the C14 drive     after it
  B=0 groups / cubes     208 / 1 728            208 / 1 728    IDENTICAL
  of them A>0            120 / 1 152            120 / 1 152    IDENTICAL
  FULLY FALSIFIED        798 / 8 591            146 /   815    -90.5 %
```

The drive emptied 90 % of the class §19.2 does NOT claim and did not move ONE
group of the class it does. On the residue, §19.2 would remove **1 152 of the
2 543 remaining cubes (45.3 %)** and would clear **71 of the 103 gap-sets**.
It is an INFERENCE, not a declaration: it needs no owner argument and no pin,
and it re-derives itself on every corpus. `src/` is untouched by this batch.

**(3) MULTI-GATE-UNREACHABLE (§13.3) — 32 of the 103 gap-sets. REPORTED.**
20 leaves for which NO run of 129 521 matches the gate conjunction at all.
§19.2's premise ("some profile matches `P`") FAILS on them, so the proposed
inference does not cover them either; they need a separate ruling and the
honest statement today is that the corpus has never walked their enabling
prefix.

**(4) RULE T — the 26 CONTRADICTED leaves, unchanged from §25.11(b).**
Every one flipped back despite its seed, and the decisions are the same family
the C13 rounds named:

```
  x4 aliases  ..._row_target_photos_row_rows != 0
  x4 aliases  ..._row_target_mentions_container_photos_row_rows
  x4 aliases  ..._row_target_mentions_container_commentable_photos_row_rows
       1      (find_by_1_person_id == devise_user_first_1_person_id)  (identity)
```

A photo list hanging off a mention's container's commentable is derived INSIDE
the mock chain rather than seeded at its head, so no seed at the head controls
it. Exposing the nested length as a seedable dimension is a change to the
shared target boundary (Rule T) and reopens every endpoint. **Reported to the
owner, not patched, and no declaration is made:** the falsifier for a
declaration here would be "a run in which the seeded nested length is
honoured", and this campaign has not established that no such run can exist —
only that this constructor cannot build one.

**(5) NO NEW DECLARATION WAS MADE.** §26's M-SNAP is the only declaration in
force and this round confirms it from a new direction: the constructor kept
ZERO values out of domain across 12 952 seeds (C13 R2 kept 88), and the
enumerator emitted no cube demanding an actors length in {2, 3}.

### §27.14 Ops

Everything detached in `concolic-cov.slice` (19 GiB MemoryMax, shared with
posts_show's P22/P23 campaign), polled by `systemctl --user is-active`, never
from the agent's process tree; `_wait_mem.sh` plus a `free -g >= 4` gate before
every launch >= 1 GB, and both numbers logged.

```
  notif-c14-enum-1       5 G   26 min 40 s   peak 4 701 MB
  notif-c14-index-1      5 G   14 min 54 s   peak   133 MB
  notif-c14-construct-1  9 G        25 s     peak   345 MB
  notif-c14-fals-1       5 G         3 s
  notif-c14-driveA-1     8 G    1 h 50 min   DRIVE_PAR=2, JRUBY_CAP=2G
  notif-c14-passR1       9 G   48 min 45 s   peak 5 279 MB
  notif-c14-enum-2       6 G   31 min 29 s   peak 5 108 MB
  notif-c14-index-2      5 G   17 min        peak   133 MB
  notif-c14-construct-2  9 G         6 s
  notif-c14-driveB-1     8 G   20 min 47 s
  notif-c14-passR2       9 G   54 min 31 s   peak 5 228 MB
```

Cage occupancy stayed under 6 GB of 19 GiB throughout; one pass at a time for
this endpoint; no `src/`, no `targets.rb`, no shared-boundary edit, no new
declaration, nothing under `posts_show/`, no policy extracted, no git.

### §27.15 Artefacts

```
_c14_enum.sh / _c14_enum.log / _c14_enum_R2.log      the EMIT_REMAINING runs
_c14_remaining.jsonl (10 319) / _c14_remaining_R2.jsonl (2 543)
_c14_universe_gaps.json      the 440-expression index universe (sampled 4 858
                             dumps; 440 exprs against the pass's NODES=441)
_c14_index_run.sh / _c14_index.pkl / _c14_index_R2.pkl
_c14_gaps.py / _c14_gaps.json (10 397) / _c14_gaps_R2.json (2 555)
_c14_add_witnesses.py        appends the checker's own remaining witnesses
_c14_construct.py            per-LEAF-GROUP overlay, inverted-bitset base rule
_c14_seeds_*.json  _c14_manifest.json      round 1 (10 397 seeds)
_c14_seedsC_*.json _c14_manifest_R2.json   round 2 ( 2 555 seeds)
_c14_falsifier.py / _c14_falsifier.json / _c14_falsifier_R2.json   §19.2
_c14_classify_C14A.json / _c14_classify_C14B.json
_c14_snapshot.sh / _snapshot_c14_R1.txt (126 966) / _snapshot_c14_R2.txt (129 521)
_c14_pass.sh
_cov_C14_C14R1.json / _cov_c14_C14R1.ckpt.jsonl     105 gap-sets
_cov_C14_C14R2.json / _cov_c14_C14R2.ckpt.jsonl     103 gap-sets  <- CURRENT
_c14_residue.py / _c14_residue.json                 the classification above
```

**Where the endpoint stands.**

```
  C12 (cap 4)  298 sets with a gap
  C13 R1       227   (-71,  1 554 runs)
  C13 R2       227   ( -0,    406 runs)     rate rule fired
  M-SNAP       184   (-43,      0 runs)     a declaration (§26)
  C14 R1       105   (-79, 10 396 runs)     every remaining cube, constructed
  C14 R2       103   ( -2,  2 555 runs)     rate rule fires again
  CURRENT   COMPLETE=False; NODES=441; MISSING=83; BLOCKING=79;
            DEMAND_SETS=1630; tree_missing 0   (_cov_C14_C14R2.json)
```

The single largest identified block is now the §19.2 `src/` inference
(71 of 103 gap-sets), followed by the multi-gate-unreachable class (32) and
the Rule T nested-row-length family (26, overlapping the first).

## §28. C15 — §19.2 IMPLEMENTED IN `src/` AS §16e, AND MEASURED (2026-09-13)

Owner ruling: *"Why are the assumptions not enough to prune the space such
that you can get a complete drive."* §19.2 is now the engine's behaviour,
opt-in, with the same discipline as §16b — DISCIPLINE §16e.

### §28.1 What was built

`src/concolic_engine/coverage.py`, `CoverageChecker(foreclosure_conjunctions=
True)` (**default False**):

```
profile_literal_masks(active, run_outcomes) -> (takes, evals, universe)
      inverted bitsets over the PROFILE table: takes[(e,o)] = profiles that
      took e that way at least once (§16b's per-literal reading, so A and B
      can only be OVERSTATED and B=0 is the conservative verdict)
prefix_match_mask(prefix, takes, universe)      -> A's mask
conjunction_foreclosed(prefix, members, ...)    -> (foreclosed, A);  A == 0
      returns NOTHING — a conjunction no run walks is absence, not evidence
render_prefix(prefix)                           -> the human form
```

Applied in step 6 on BOTH sides, which is the whole of the fix:

* **emission** — after `_next_untried_combo` returns the §16b cube, `P` is the
  model's assignment over the set's surviving gates, and every non-gate member
  no profile matching `P` evaluates is dropped from the cube. Gates are never
  conjunction-foreclosed: they DEFINE `P` (the falsifier's own member list is
  `surv − P`).
* **blocking** — the closed-prefix test drops the same members, so a PARTIAL
  run that walks the coarsened leaf can block it. Without this half the leaf
  is pruned out of the demand and then reported missing for ever, which is
  the defect being fixed, not a fix.

Reported: `conjunction_foreclosures` / `conjunction_foreclosure_groups` /
`conjunction_foreclosure_list` / `conjunction_foreclosures_provisional`
(follows `tree_complete`, exactly as §16b's), and — separately and NOT as an
inference — `unmatched_gate_conjunctions` /
`unmatched_gate_conjunction_prefixes`, the `A = 0` class whose demand STANDS.
The foreclosures also reach the assumption gate through
`assumptions_to_dict()` as `ConjunctionForeclosureAssumption`
(`inferred: true`). The flag is folded into the step-6 checkpoint key.

### §28.2 The pass — 103 gap-sets -> 84

`_c15_pass.sh _snapshot_c14_R2.txt C15R2` — the SAME 129 521-run corpus, the
same assumptions, cap 1, checkpointed, `FORECLOSURE_CONJUNCTIONS=1`.

```
                       C14 R2 (§16b)              C15 R2 (§16e)
  COMPLETE                False                     False
  NODES                     441                       441
  MISSING                    83                        68
  BLOCKING                   79                        64
  DEMAND_SETS              1630                      1630
  tree_complete            True (0 missing)          True (0 missing)
  SETS WITH A GAP           103                        84      -19, +0
  coverage phase           1621 s                    1069 s
  peak RSS                 5228 MB                   5247 MB
  wall                     54 m 31 s                 43 m 42 s
```

`_c15_gapcensus.py` over the two checkpoints: **the demand-set key sets are
IDENTICAL** (1 630 / 1 630 digests shared — the demand universe did not move),
every one of C14's 103 gap-sets is present, **19 closed, 0 newly gapped**. The
pass is also 34 % FASTER: a coarser leaf is a shorter cube and a shorter
blocking clause.

```
  conjunction foreclosures      89   over 89 leaf groups   (PROVISIONAL: no)
  unmatched gate conjunctions   12   (A = 0 — demand stands)
  §16b foreclosures           5278   (unchanged), ignored 1
```

The 89 are over exactly TWO members — the two the §27.5 head list named:

```
   62 prefixes   ..._devise_user_first_1_person_profile_not_found == True
   27 prefixes   ..._find_by_3_not_found == True
   prefix widths 4..14 (mode 7-8); the gates are
     devise_user_first_1_person_not_found (61), SYM_NOTE_TYPE_PROFILE == 4..7
     (59 each), == 0/1 (43), find_by_1_not_found (35)
```

The 12 `A = 0` prefixes are all width 10-12 and all of one shape: the eight
`SYM_NOTE_TYPE_PROFILE == k` literals NOT taken, plus
`devise_user_first_1_person_not_found` and a
`to_ary_notifications_*_row_target_not_found` /
`..._row_target_mentions_container_not_found` pair. That is §13.3's
multi-gate-unreachable class, named per-prefix for the first time, and the
inference deliberately does NOT touch it.

### §28.3 The falsifier cross-check — AGREE, to the unit

`_c15_falsifier_check.py` recomputes A and B for every reported pair straight
from the dump index's inverted bitsets (`_c14_index_R2.pkl`, 126 966 dumps —
2 555 runs behind the pass's corpus; §27.10 measured the class as immobile
across 12 951 constructed runs, so the lag is immaterial and is stated rather
than hidden):

```
  conjunction foreclosures checked  89     A>0 and B=0 (AGREE)  89   DISAGREE 0
  unmatched (A=0) prefixes checked  12     A=0        (AGREE)  12   DISAGREE 0
  VERDICT=AGREE
```

The engine's inference IS the §19.2 falsifier, implemented.

### §28.4 §27.13's "would clear 71 of 103" was an OVER-COUNT — and why

The measured clearance is **19**, not 71. Two independent reasons, both
reportable as findings rather than as a shortfall of the implementation.

**(a) `_c14_residue.py` flattened the falsifier to a per-EXPRESSION set.**
Lines 47-51 build `B0` as *every expression that is B = 0 in ANY leaf group
anywhere* and then ask `e in B0` of each member of a checker witness leaf.
That is "B = 0 under SOME gate conjunction", not "under ITS OWN". §27.12's
"leaves with >= 1 member that is B=0 under its own gate conjunction: 77 of 77"
and §27.13's "clears 71 of the 103" both rest on that flattening. Measured
per (leaf group, member), as §19.2 specifies and as the engine now does, only
**28 of the 103 witness leaves are touched at all** (19 closed, 9 replaced by
a different leaf); the other **75 come back byte-identical** — their own gate
conjunction forecloses none of their members.

**(b) Removing a cube from the demand is not the same as closing a set.**
Even where the inference fires, the leaf it coarsens must then be COVERED by
a run that matches `P` and evaluates every surviving member together. §19.2's
sizing counted cubes removed from the demand; a set closes only when the
coarsened leaf acquires a blocking clause. (This is also why the blocking
side had to move with the emission side — see §28.1.)

Every one of the 84 remaining witness leaves is still a leaf **no run of the
129 521 matches whole** (`_c15_residue.py`, A = 0 over the full cube, 84 of
84 — as was true of all 103 before). §16e removed the part of that residue
the corpus can PROVE unreachable under its own gates; the rest is unchanged
and unexplained by this inference.

### §28.5 Nesting, and the closed endpoints

`src/test_conjunction_foreclosure.py::test_demand_is_nested_16e_16b_16` — 60
random corpora, three settings, per demand set: leaves summed over every set
**§16 9 184 -> §16b 4 735 -> §16e 4 500**, every §16e leaf a sub-cube of a
§16b leaf and every §16b leaf a sub-cube of a §16 assignment; 125 sets shrank
pairwise, 52 shrank further on a conjunction.
`::test_missing_is_nested_on_random_corpora` — the same through the checker:
§16b-complete implies §16e-complete on all 60, and where nothing fires the
two reports are identical.

Closed endpoints, coverage layer re-run OFF then ON on the same corpus:

```
  people_stream   13 677 dumps   OFF COMPLETE=True NODES=39 MISSING=0
                                 ON  COMPLETE=True NODES=39 MISSING=0
  comments_index  25 408 runs    OFF COMPLETE=True NODES=84 MISSING=0
                                 ON  COMPLETE=True NODES=84 MISSING=0
```

people_stream's two summaries are identical in every key except
`assumptions`, where the ON pass appends **3** inferred
`ConjunctionForeclosureAssumption` entries. Nothing about `complete`,
`demand_sets`, `tree_missing` or `missing` moves. The flag-OFF summary also
reproduces the endpoint's COMMITTED closed summary key for key, with the one
exception of 4 `ConfinementAssumption` entries that the §16c engine of
2026-09-11/12 adds and that predate this work.

### §28.6 An OPERATIONAL DEFECT of this session, and its repair

The differential harness ran each endpoint's own `coverage_report.py` with
`SKIP_COMPLETION=1 SUMMARY_OUT=<scratch>`. **`comments_index/coverage_report.py`
ignores `SUMMARY_OUT`** (line 235: `out = os.path.join(HERE,
"coverage_summary.json")`) — unlike people_stream's, which honours it — so the
two probe passes OVERWROTE that closed endpoint's `coverage_summary.json`,
reproducing its coverage numbers exactly (`COMPLETE=True; NODES=84;
MISSING=0`) but replacing its completion section with the SKIP_COMPLETION
stub. There was no backup of the closed file in that directory
(`_bak_coverage_summary_cycle9.json` is a 16 496-run corpus, not the closed
26 528-run one). **Rule for the next agent: never point a differential at a
batch report without first checking that it honours `SUMMARY_OUT`;
people_stream's does and comments_index's does not.**

Repaired the same hour by re-running the FULL pass with engine defaults —
§16e OFF, no `SKIP_COMPLETION` — 02:00-03:14, cap 7G, gate checkpointed. It
reproduces the coverage layer EXACTLY:

```
  COMPLETE=True;NODES=84;MISSING=0;BLOCKING=0;PCS=928746     (25 408 runs)
```

**and it does NOT reproduce `complete: true` overall.** The regenerated
completion section is blocked by

```
  shim NO-TEST  ActiveRecord::Associations::SingularAssociation.find_target
  shim NO-TEST  ::Gon.singleton_class.preloads
  15 x assumption FAIL (ConfinementAssumption)
     assumptions: declared 4228, distinct_tested 3694, PASS 3679 / FAIL 15,
     confinement_tested 46; the FAILs are the `Length(SYM_PARAM_post_id) < 16`
     family (7), three `ci_*_first_1_type == 'Photo'` and five
     `Relation_to_a_1_row*_author_*` pairs
```

**None of this is §16e**: the restoring pass ran the flag OFF and the summary
carries no `ConjunctionForeclosureAssumption`. Every FAIL is a
`ConfinementAssumption` — the pairs §16c INFERS and feeds to the gate. §16c
landed 2026-09-11; comments_index closed 2026-09-01, and §16a's 2026-09-10
re-verification was explicitly coverage-only ("their `coverage_summary.json`
files were not touched"). This is therefore very likely the FIRST run of the
current engine's confinement gate on this endpoint, and the 15 FAILs are a
genuine previously-unseen verdict, surfaced by accident rather than caused by
it. notifications_index and posts_show feed such FAILs back as
`withdrawn_pairs=`; comments_index has no such loop wired, so nothing has been
withdrawn and nothing re-licensed here. **Whether a closed endpoint must answer
§16c's inferred-pair gate is a Rule T question for the owner.** Written up in
`comments_index/_RESTORED_20260913.md`; the pre-2026-09-13 file is gone and
this one is NOT presented as a reconstruction of it.

### §28.7 The gate — the derived test for a conjunction foreclosure

`assumption_checker.py::_test_conjunction_foreclosure`, dispatched on the
inferred type. Base = the richest snapshot that recorded the member TOGETHER
WITH every gate of `P` (a run in which the member IS evaluated, which is
"seeded to force its evaluation"); probe = that snapshot's seeds with every
gate whose recorded outcome differs from `P`'s flipped at the runtime ordinal
key. Member evaluated under a realised `P` => **FAIL** (refuted, withdrawn);
not evaluated => PASS; `P` not realised, or no dump, or no such snapshot =>
NOT-TESTABLE; aliased reading changed => NOT-COMPARABLE. The test can never be
vacuous: the base records the member, so if it already matched `P` the
inference would not have been made.

`_c15_gate_classes.py` — a class is a foreclosed MEMBER, the representative is
its NARROWEST prefix (foreclosure under a prefix implies it under every
extension, so the narrowest is the strongest claim of the family and the most
likely to be REALISED). **89 pairs collapse to 2 classes**, both at prefix
width 4.

`_c15_gate.sh C15` — detached in `concolic-cov.slice`, cap 7G (the cage was
sharing 11.3G with posts_show, so 8G would not have passed `_wait_mem`;
measured peak 3 341 MB), `CONCOLIC_SLOTS=1`, ACHK index/derive/probe
checkpoints + `ACHK_HEARTBEAT_S=120`.

```
  wall 41 m 23 s   peak RSS 3 341 MB
     corpus-index   304 586 dumps at ~135/s   ~40 min   (the whole cost)
     derive-probes  2/2, 0 s
     probes         1 batch, 2 roots, scenario 'html_typed', 2 dumps matched

  RESULT: 2 distinct tested — PASS 2, FAIL 0, ERROR 0, NOT-TESTABLE 0,
                              NOT-COMPARABLE 0
```

Both passes are ACTIVE, not vacuous — the detail names the base and the flips:

```
  PASS  ..._devise_user_first_1_person_profile_not_found == True
        a run realising the conjunction (2 gates flipped from
        dump_html_typed_dse0057_C14Bhtmt0004r0.json, which DOES record the
        member) leaves the member unevaluated
  PASS  ..._find_by_3_not_found == True
        a run realising the conjunction (1 gate flipped from
        dump_html_typed_dse0023_C14Bhtmt0004r0.json, which DOES record the
        member) leaves the member unevaluated
```

The base is chosen as a run that RECORDS the member, so a PASS is always a
replay in which the member could have been evaluated and was not; and if the
base had already matched `P` the corpus would have falsified the inference and
the engine would never have made it. `NOT-TESTABLE` would have been the
verdict had the probe failed to realise `P` (the realised-value rule) — it did
not fire.

### §28.8 What remains, per key (updating §27.13)

```
  (1) DRIVER-FIXABLE                     0   unchanged; C15 drove nothing
  (2) §19.2 / §16e src INFERENCE      DONE   103 -> 84 gap-sets (-19),
                                             89 (prefix, member) pairs over
                                             2 members, gate 2/2 PASS
  (3) MULTI-GATE-UNREACHABLE (§13.3)    12   gate CONJUNCTIONS no run of
                                             129 521 matches, now NAMED
                                             per-prefix (`unmatched_gate_
                                             conjunctions`); demand STANDS
  (4) RULE T nested-row-length          26   unchanged (§27.13(4)); the
                                             photos/mentions-container family
                                             a seed at the head cannot control
  (5) NEW: leaves no run matches whole  84   every remaining witness leaf has
                                             A = 0 over its FULL cube. §16e
                                             cannot speak to them: their gate
                                             conjunction IS walked (only 12 of
                                             them are A=0 at the gate level),
                                             it is the full assignment that is
                                             not
```

The single largest identified block is no longer a `src/` inference. It is
(5): 84 leaves whose full assignment no run has ever produced, of which the
corpus can prove only 12 unreachable at the gate-conjunction level. The
honest reading is that §19.2 was worth implementing — it is inferred, it needs
no owner argument, it re-derives itself, it PASSED its derived gate, and it
took 19 sets off the board for free — but §27.13's "71 of 103" was an
artefact of a flattened falsifier, and the endpoint's remaining distance is
not an assumption problem.

### §28.9 Ops and artefacts

```
  e16e-identity-20260913   4G/7G   people_stream + comments_index, off then on
  restore-comments-20260913 7G     1 h 15 m   the §28.6 repair
  notif-c15-r2-20260913     7G     43 m 42 s  peak 5 373 MB   the pass
  notif-c15-gate-20260913   7G     41 m 23 s  peak 3 341 MB   the gate
```

Every launch gated on `free -g >= 4` AND `(19G − slice MemoryCurrent) >= cap`,
both logged; one pass at a time; the cage never exceeded ~16.3G of 19G while
posts_show's P26 drive and gate were also in it. No `targets.rb`, no shared
boundary, nothing under `posts_show/`, no extraction, no git.

```
src/concolic_engine/coverage.py            §16e: the four helpers, the flag,
                                           step 5c', both sides of step 6,
                                           conjunction_foreclosures_to_dict
src/end_to_end_completion_checker/assumption/assumption_checker.py
                                           _test_conjunction_foreclosure + the
                                           `prefix` dedup key
src/test_conjunction_foreclosure.py        13 tests (283 -> 296 green)
reports/diaspora/docs/DISCIPLINE.md §16e   the decision record
reports/diaspora/docs/RUNBOOK.md §4        the flag

notifications_index/
  coverage_report.py            FORECLOSURE_CONJUNCTIONS knob (default 1 HERE)
                                + the §16b/§16e summary keys + CONJ_ line
  _bak_coverage_report_pre_16e_20260913.py
  _c15_pass.sh / _c15.log / _c15_cov_C15R2.log / _c15_cov_C15R2.time
  _cov_C15_C15R2.json / _cov_c15_C15R2.ckpt.jsonl        the pass
  _c15_gapcensus.py                                      103 -> 84
  _c15_falsifier_check.py / _c15_falsifier_check.json    VERDICT=AGREE
  _c15_residue.py                                        A=0 over the full cube
  _c15_gate_classes.py / _c15_gate_classes.json          2 classes
  _c15_gate.sh / _c15_gate_C15.log / _c15_gate_C15.json / _c15_achk_rows.jsonl
  _c15_achk_index.ckpt.jsonl (537 MB) / _c15_achk_probes.jsonl
comments_index/_RESTORED_20260913.md                     the §28.6 repair
```

## §29. C16 — EVERY REMAINING CUBE **UNDER §16e**, CONSTRUCTED AND DRIVEN (2026-09-13)

§28 implemented §16e and measured what it buys the CHECKER (103 -> 84
gap-sets). C16 asks the other half of the RUNBOOK Phase 2 question: with the
demand coarsened by the same inference, what does the EXACT ENUMERATOR still
have left, and does driving all of it close anything? One round. It does not.

### §29.1 The enumerator under §16e — `_c16_enum.py`

`_exact_enum.py` predates §16e, so it was copied to `_c16_enum.py` and the
relation added **with the engine's own functions** — `profile_literal_masks`,
`prefix_match_mask`, `conjunction_foreclosed`, `render_prefix` imported from
`concolic_engine.coverage`, nothing re-derived. Per leaf group `(P, surv)`:
`P` is the ordered surviving-gate assignment the §16b pruned walk already
produces, the member list is `surv − P` (gates DEFINE `P` and are never
conjunction-foreclosed), and the members `conjunction_foreclosed` returns are
dropped from the leaf — from the SAT count, from the covered test's profile
mask and from the emitted cube alike, which is the same both-sides move
`coverage.py` step 6 makes. `A == 0` infers NOTHING: the group keeps its
demand in full and is counted, emitted and driven as its own class. Each
emitted cube now also carries `sdig` — the checker's own per-set checkpoint
key, `checkpoint.digest(group)` after `restrict_foreclosures` — so the census
joins to a coverage checkpoint by SET without guessing.

Two differentials before it was believed:

```
  FORECLOSURE_CONJUNCTIONS=0, 1 440-dump sample, against `_exact_enum.py`
     EXACT satisfiable=95450 covered=19777 remaining=75673   BOTH
     and the 75 673 emitted assignments are IDENTICAL line for line.
  FORECLOSURE_CONJUNCTIONS=1, same sample
     satisfiable 95450 -> 93946  (-1504, == the reported `conj_cubes_removed`)
     covered     19777 -> 20245  (+468 — coarsened leaves acquiring coverage,
                                  i.e. the BLOCKING side moving with the
                                  emission side, §28.1)
     remaining   75673 -> 73701     wall 253 s -> 128 s
```

### §29.2 The enumeration — 1 184 remaining cubes, in TWO classes

`_c16_enum.sh` on `_snapshot_c14_R2.txt` (129 521 runs — the SAME corpus the
C15 R2 §16e verdict of 84 gap-sets was measured on), same assumptions,
streamed, caged 6 G.

```
loaded 129521 runs   profiles=122305 active=432 untracked=9 pinned=1
demand sets=1598   tree_missing=0 tree_complete=True   universe built 1649 s
EXACT: satisfiable=85999 covered=84815 remaining=1184 bounded_cliques=0
       census 168 s   wall 30 min 21 s   peak RSS 5 187 MB
EMIT_REMAINING: emitted == counted, on every leaf group
§16e: 58 leaf groups foreclosed, 58 (prefix, member) pairs over 2 members
      (devise_user_first_1_person_profile_not_found x34, find_by_3_not_found x24)
      satisfiable assignments the coarsening REMOVED from the demand: 576
      UNMATCHED (A = 0, demand STANDS): 32 prefixes over 88 leaf groups
REACHABILITY SPLIT   REACHABLE 608 (51.4 %)   MULTI-GATE-FORECLOSED 576
```

**The A = 0 class and the enumerator's "no observed compatible walk" class are
the same object, to the group and to the cube: 88 leaf groups, 576 cubes** —
the same 88/576 §27.5 and §27.9 measured with the independent falsifier, and
it has still not moved.

```
  remaining cubes                     1 184   over 102 demand sets, 207 leaf groups
    A > 0, nothing foreclosed           608   (the enumerator's reachable remainder)
    A = 0, UNMATCHED gate conjunction   576   32 prefixes / 88 groups / 20 sets
                                              (widths 11 and 12)
  + checker witnesses not already in it     8
  BATCH                               1 192   in 215 leaf groups
```

**56 of the checker's 64 witness leaves were ALREADY in the enumerator's
list.** C14 R1 had 16 of 159 and C14 R2 67 of 79; §16e has brought the two
instruments into near-agreement about what is left.

### §29.3 The two instruments AGREE, on everything they share

`_c16_setcheck.py`, joined on `sdig`:

```
  ENUMERATOR 1 598 demand sets, 102 with remaining > 0
  PASS       1 630 demand sets,  84 gap-sets
  universe overlap: shared 299   enum-only 1 299   pass-only 1 331
  the pass's 84 gap-sets:  52 are in the census's universe — ALL 52 have
                           remaining > 0;  0 have remaining == 0
  the census's 102:        52 are in the pass's universe — ALL 52 are GAPPED;
                           0 are called covered
```

**On the shared universe the two instruments name the SAME set of gapped
sets, 52 = 52, with zero disagreements in either direction.** The 1 299 /
1 331 difference is structural and known (§27.3): the pass applies §16c
confinement and the census does not, so most set digests simply do not exist
on the other side (441 nodes / 1 630 sets vs 432 / 1 598). It is not a
disagreement about coverage, and it is stated rather than assumed away.

`_c16_falsifier_check.py` (= `_c15_falsifier_check.py` pointed at the
census's `_c16_conj.json`) recomputes A and B from the dump index's inverted
bitsets — **on the identical 129 521-dump corpus this time, no lag**:

```
  conjunction foreclosures checked  58   A>0 and B=0 (AGREE)  58   DISAGREE 0
  unmatched (A=0) prefixes checked  32   A=0        (AGREE)  32   DISAGREE 0
  VERDICT=AGREE
```

All 58 of the census's pairs are among the pass's 89 (the pass names more
because it walks the confinement-projected universe); 8 of the pass's 12
`A = 0` prefixes are also named by the census, which names 24 more the pass's
capped witness search never reached.

### §29.4 The construction — 1 192 seeds, and what the A = 0 class costs

`_c14_construct.py` verbatim (per-leaf-group overlay, inverted-bitset base
rule, `_c13_construct` value rules, UNSEED `__prior`, both `len` spellings),
on a FRESH index over the same 129 521-run corpus (`_c16_index.pkl`, 19 m 30 s).
The full prefix `P` is pinned in every cube, because `_c16_gaps.py` builds the
cube as `pre ∪ asg` — which is exactly the new information §16e hands the
constructor: a SHORTER member list under a gate prefix now known to be the
whole of what the leaf demands beyond it.

```
cubes 1192   leaf groups 215   distinct base runs used 124   K=1   wall 5 s
  seeds built 1192   substituted 8061   kept OUT-OF-DOMAIN 0
  NOT SEEDABLE 0     unsatisfiable 0    inert alias 0    keys novel 81
  alias-perfect       1192/1192
  member-walk-perfect 1192/1192
  gate-perfect         608/1192
```

**The 584 gate-imperfect seeds are exactly the 576 A = 0 cubes plus the 8
checker witnesses, and that is a definition, not a defect: no run of the
corpus matches an A = 0 gate conjunction, so no base can be gate-matched for
one.** The 608 A > 0 cubes are gate-perfect to the cube.

### §29.5 The drive

```
_c13_drive.sh C16A 200  (SEEDSET=A, C13_PREF_A=_c16_seeds_,
                         C13_MANIFEST=_c16_manifest.json)
  detached notif-c16-driveA-1, 6 G service, DRIVE_PAR=2, CONCOLIC_SLOTS=2,
  JRUBY_CAP=2G, every JRuby its own scope in concolic-cov.slice
  corpus 304 586 -> 305 778 dumps  (+1 192, one dump per seed, no loss)
  6 legs each with `=== CHUNK DRIVE C16A END ===`; 10 chunks all
  `DONE consumed=N/N tries=1 toxic=0`; xml_plain 0 seeds (stated)
  VERDICT  C13-DRIVE-DONE C16A  +1 192 dumps  0 seeds left
  04:41:18 -> 04:53:48   12 min 30 s
```

### §29.6 The round PER KEY — 89.4 % honoured, and **0 cubes REALISED**

`_c13_classify.py` (TAG=C16A), the same classifier and the same definition of
HONOURED that scored C13, C14A and C14B:

```
=== PER KEY (14 052 demanded keys) ===        C14A          C14B
  HONOURED         12 567  (89.4 %)           96.6 %        91.2 %
  CONTRADICTED        109  ( 0.8 %)            0.3 %         0.6 %
  NEVER-EVALUATED   1 376  ( 9.8 %)            3.1 %         8.2 %
  NOT-DRIVEN            0
=== PER CUBE (1 192) ===
  REALISED               0  ( 0.0 %)          73.7 %         7.9 %
  UNEVALUATED        1 083  (90.9 %)
  CONTRADICTED         109  ( 9.1 %)
replay errors {declared: 636, '': 360, other: 100, gon: 96}
```

Per §16e class, and the split is TOTAL:

```
  A = 0 unmatched     576   UNEVALUATED 576   CONTRADICTED   0   REALISED 0
  A > 0 enumerated    608   UNEVALUATED 499   CONTRADICTED 109   REALISED 0
  checker witness       8   UNEVALUATED   8   CONTRADICTED   0   REALISED 0
```

**Every one of the 109 contradicted cubes carries a Rule T family decision,
and no cube outside that family was contradicted.** The 576 A = 0 cubes were
all constructed and all driven, and not one of them was evaluated — which is
the construction evidence §13.3's class has never had: *"no run has walked
this gate conjunction"* is now *"a seed built to force it, on the richest
alias-matched base the corpus offers, did not walk it either."*

### §29.7 THE PASS — 84 -> 84, and the RATE RULE FIRES ON THE FIRST ROUND

`_c16_pass.sh _snapshot_c16_R1.txt C16R1`, 130 713 runs (= the C15 R2 corpus +
all 1 192 C16A dumps), same engine (`coverage.py` md5
e083101a87bf4b80d5ae2611339346fc), `FORECLOSURE_CONJUNCTIONS=1`, cap 1,
checkpointed, cap 8 G.

```
                       C15 R2 (§16e)             C16 R1 (§16e)
  COMPLETE                False                     False
  NODES                     441                       441
  MISSING                    68                        68
  BLOCKING                   64                        64
  DEMAND_SETS              1630                      1630
  tree_complete            True (0 missing)          True (0 missing)
  conj foreclosures    89 / 89 groups            89 / 89 groups
  unmatched (A=0)            12                        12
  total_runs            129 521                   130 713
  dump_errors            45 044                    45 876   (+832)
  SETS WITH A GAP            84                        84      -0, +0
  wall / peak RSS   43 m 42 s / 5 373 MB      43 m 22 s / 5 405 MB
  file              _cov_C15_C15R2.json       _cov_C16_C16R1.json
  checkpoint        _cov_c15_C15R2.ckpt.jsonl _cov_c16_C16R1.ckpt.jsonl
```

The verdict line (recovered by the §29.9 replay, from the report's own output):

```
COMPLETE=False;NODES=441;MISSING=68;BLOCKING=64;PCS=8326630
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
CONJ_FORECLOSURES=89;CONJ_GROUPS=89;CONJ_PROVISIONAL=False;UNMATCHED_CONJ=12;FORECLOSURES=5278
VERDICT C16-C16R1: OK (line present)      C16-PASS-DONE C16R1
```

`_c16_gapdelta.py` on the two checkpoints:

```
  demand universe: shared 1630, only-before 0, only-after 0
  CLOSED 0   NEWLY GAPPED 0   STILL GAPPED 84
  of the still-gapped, witness leaf UNCHANGED 84, replaced by a different leaf 0
  distinct witness leaves: 64 before, 64 after, 64 shared
```

**Not one leaf moved.** Every witness comes back byte-identical.

```
  round       | runs   | sets with a gap | closed | closed/run | wall
  C12 (cap 4) |   —    | 298             |   —    |     —      | (input)
  C13 R1      |  1 554 | 227             |   71   |   0.046    | ~2 h 40
  C13 R2      |    406 | 227             |    0   |   0.000    | ~1 h 15
  M-SNAP      |      0 | 184             |   43   |     —      | a declaration
  C14 R1      | 10 396 | 105             |   79   |   0.0076   | ~4 h 00
  C14 R2      |  2 555 | 103             |    2   |   0.00078  | ~2 h 00
  C15 R2      |      0 |  84             |   19   |     —      | §16e in src/
  C16 R1      |  1 192 |  84             |    0   |   0.000    | ~1 h 40
```

RUNBOOK Phase 2: *"Stop a method that falls below ~0.05/run for two rounds."*
C14 R2 was 0.00078 and C16 R1 is 0.000. **The loop stops, and this time it
stops with every remaining cube of the §16e demand constructed, driven and
explained per key.**

### §29.8 The residue — 84 gap-sets in FOUR classes, all four with construction evidence

`_c16_residue.py`. §28.4(a)'s flattening defect is not repeated: A and B are
measured per (leaf, member) from the leaf's OWN literals, never as "B = 0
under SOME gate conjunction anywhere".

```
  witness leaves 84 rows / 64 distinct cubes over 84 gap-sets
  leaves NOT IN THE C16 BATCH                      0   <- nothing is residue by default
  leaves REALISED by the classifier                0
  leaves with A = 0 over the FULL cube        84 / 84  (no run of 130 713
                                                        matches the leaf whole)
```

| # gap-sets | class | verdict of its constructed run | what it needs |
|---|---|---|---|
| **12** | its witness leaf IS an `A = 0` cube of the enumerator — the 12 `unmatched_gate_conjunctions` prefixes the pass names, widths 14/16 | UNEVALUATED | a RULING on §13.3, not a driver |
| **16** | checker-witness-only leaf, also under an A = 0 gate conjunction | UNEVALUATED | same class, reached by the checker not the census |
| **25** | A > 0, and every one carries a **Rule T** nested-row-length / identity decision | **CONTRADICTED** — the decision flipped back despite its seed | a Rule T change to the shared target boundary |
| **31** | A > 0, no Rule T member, gate conjunction IS walked | UNEVALUATED | see below — the honest open class |

**(1) DRIVER-FIXABLE — 0.** Three rounds, 14 143 constructed runs, the rate
rule fired twice, and the classifier realises none of the 64 leaves. Alias
coverage 1 192/1 192, member-walk 1 192/1 192, 0 out-of-domain, 0 not
seedable.

**(2) §16e / `src/` INFERENCE — DONE and CONFIRMED, no further yield.** 89
pairs over 2 members, gate 2/2 PASS (§28.7), falsifier AGREE 58/58 and 32/32
on the census's identical corpus with no lag. It took 19 sets off the board in
§28 and 0 more here. It is not the remaining obstacle.

**(3) MULTI-GATE-UNREACHABLE (§13.3) — 28 of the 84 gap-sets (12 + 16),
now with CONSTRUCTION evidence.** 576 cubes over 32 gate conjunctions no run
of 129 521 matches were built and driven; all 576 came back UNEVALUATED, none
contradicted. The class is unchanged in size across 14 143 constructed runs
(88 groups / 576 cubes at C14 R1, C14 R2 and C16). **What it needs is a
ruling, and the question is precise: the eight `SYM_NOTE_TYPE_PROFILE == k`
literals NOT taken together with `devise_user_first_1_person_not_found` and a
`_row_target_not_found` / `_row_target_mentions_container_not_found` pair. No
inference licenses dropping it (A = 0 is absence, not evidence, §16e) and the
driver has now been shown, by construction, not to reach it.**

**(4) RULE T — 25 of the 84 gap-sets (was 26; §16e closed 2 of them).** The
same family §27.13(4) named, re-measured by this round's own drive rather than
inherited:

```
  x4 aliases  ..._row_target_photos_row_rows != 0
  x4 aliases  ..._row_target_mentions_container_photos_row_rows
  x4 aliases  ..._row_target_mentions_container_commentable_photos_row_rows
      37      (find_by_1_person_id == devise_user_first_1_person_id)  (identity)
```

Exposing the nested length as a seedable dimension is a change to the shared
target boundary (Rule T) and reopens every endpoint. **Reported, not patched;
no declaration is made.**

**(5) THE OPEN CLASS — 31 gap-sets.** A > 0 at the gate conjunction (their
gates ARE walked), A = 0 over the full cube, no Rule T member, constructed on
a gate-perfect alias-perfect base, driven, 89.4 % of their keys honoured — and
still not one run took the whole cube. §16e cannot speak to them: it is not
the gate conjunction that is unwalked, it is the full assignment. This is
§28.8(5) narrowed from 84 to 31 by giving the other 53 a name.

**(6) NO NEW DECLARATION WAS MADE.** §26's M-SNAP remains the only one, and
this round confirms it again from the constructor: 0 values kept out of
domain across 1 192 seeds.

### §29.9 An OPERATIONAL DEFECT of this round, and its repair

The coordinator's new rule (one endpoint's `coverage_report.py` on the box at
a time while the posts_show confinement gate runs) arrived WHILE the C16 R1
pass was running, and it was installed by editing `_c16_pass.sh` in place.
**bash reads a script by byte offset as it executes it**, so the edit shifted
the offsets under the running shell: when `coverage_report.py` returned, the
parent resumed mid-token, re-executed the `> "$LOG"` redirect — TRUNCATING
`_c16_cov_C16R1.log` to a single error line — and died with
`line 45: -p: command not found`, rc 127. `_c16_pass.sh` then printed its own
`*** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***`, which is exactly the
right verdict for what it could see.

The WORK was not lost and was not trusted on that basis: `/usr/bin/time`
wrote `_c16_cov_C16R1.time` (43 m 21.98 s, peak 5 405 416 kB) which it only
does when the child exits, the summary is a full 196 MB artefact with
`total_runs 130713` and its own `dump_errors`, and the checkpoint holds
1 630/1 630 records. The repair is to **replay** it: the same
`_c16_pass.sh` invocation with the same `COVERAGE_CHECKPOINT` re-folds every
recorded set with no Z3 work and re-emits the verdict line from the report's
OWN output. Both artefacts were backed up first
(`_cov_c16_C16R1.ckpt.jsonl.bak`, `_bak_cov_C16_C16R1_prelog.json`) so the
replay can be compared against them rather than believed.

**Rule for the next agent: never edit a shell script while a copy of it is
running — copy it to a new name and launch that.** The gate itself is right
where it belongs (inside the unit, before `wait_mem`, so a launcher that dies
cannot skip it); only the timing of the edit was wrong.

**A SECOND defect in the same gate, found by the replay it was blocking.**
The first spelling was `while pgrep -f "posts_show/coverage_report.py"`.
`pgrep -f` matches any process whose COMMAND LINE CONTAINS the string, and the
coordinator's own posts_show monitor shell contains it — inside a
`grep -v "posts_show/coverage_report.py"`, of all places. So the gate blocked
for four minutes on a monitor, with no posts_show pass running at all
(`pgrep -a python3 | grep -i posts` showed only the assumption checker and
`_p26_emit_or.py`). A path-shaped `pgrep -f` pattern is a liveness hazard
wherever any monitor or log line mentions the path. Fixed to

```
while pgrep -a python3 2>/dev/null | grep -q "posts_show/coverage_report[.]py"; do
```

which lists only python3 processes, so a shell that merely mentions the path
cannot match. The unit was STOPPED before this edit (it had done no work — it
was still in the wait loop) and relaunched, which is the rule above applied.

**The repair worked and was CHECKED, not assumed.** The replay resumed from
the checkpoint (`[checkpoint] resuming ...: 1630 completed unit(s) will be
skipped`), spent 502 s instead of 1 069 s, and reproduces the pre-replay
artefacts exactly:

```
  checkpoint md5   c2671b2fae524afff58847a2b30e4a2c   IDENTICAL to the .bak
  summary          complete / demand_sets / missing_branches / tree_complete /
                   total_runs / conj 89 / groups 89 / unmatched 12 /
                   solver_lost / truncated / dump_errors   ALL IDENTICAL
  missing[]        68 entries, IDENTICAL element for element
```

### §29.10 Ops

Every launch gated on `free -g >= 4` AND `(cage MemoryMax − MemoryCurrent) >=
cap`, both logged; one pass at a time for this endpoint, and — from the
coordinator's 2026-09-13 rule, after the cage hit 19.6 G and was raised to
24 G — one endpoint's `coverage_report.py` on the box at a time while the
posts_show confinement gate runs, checked INSIDE the unit.

```
  notif-c16-smoke-a/b/c   4G    ~4 min each   the flag-off / flag-on differentials
  notif-c16-index-1       3G    19 min 30 s   peak   133 MB   _c16_index.pkl
  notif-c16-enum-1        6G    30 min 21 s   peak 5 187 MB   the §16e enumeration
  notif-c16-construct-1   4G          5 s     peak   249 MB   1 192 seeds
  notif-c16-fals-1        2G          7 s                     falsifier AGREE
  notif-c16-driveA-1      6G    12 min 30 s   DRIVE_PAR=2, CONCOLIC_SLOTS=2, JRUBY_CAP=2G
  notif-c16-passR1        9G    43 min 22 s   peak 5 405 MB   the pass
  notif-c16-residue-1     3G         10 s
  notif-c16-passR1-replay2 9G                  the §29.9 verdict-line replay
```

No `src/` edit, no `targets.rb`, no shared-boundary edit, no new declaration,
no extraction, no git, nothing under `posts_show/` or `comments_index/`.

### §29.11 Artefacts

```
_c16_enum.py          the §16e census (engine functions, not re-derived)
_c16_enum.sh / _c16_enum.log / _c16_enum.json
_c16_remaining.jsonl (1 184)          _c16_conj.json (58 pairs, 32 A=0 prefixes)
_c16_gaps.py / _c16_gaps.json (1 192 after witnesses)
_c16_add_witnesses.py                 8 appended of 64 checker witnesses
_c16_setcheck.py / _c16_setcheck.json 52 = 52 on the shared universe
_c16_falsifier_check_enum.json/.log   VERDICT=AGREE, no corpus lag
_c16_index_run.sh / _c16_index.pkl    129 521 dumps, 440 exprs
_c16_seeds_*.json / _c16_manifest.json          1 192 seeds
_c13_drive.sh C16A -> _c16_driveA_outer.log / _chunk_drive_C16A.log
_c16_classify_C16A.json                         89.4 % honoured, 0 realised
_c16_snapshot.sh / _snapshot_c16_R1.txt (130 713)
_c16_pass.sh / _c16.log / _c16_cov_C16R1.log / _c16_cov_C16R1.time
_cov_C16_C16R1.json / _cov_c16_C16R1.ckpt.jsonl        84 gap-sets  <- CURRENT
_cov_c16_C16R1.ckpt.jsonl.bak / _bak_cov_C16_C16R1_prelog.json
                                       the pre-replay artefacts (§29.9)
_c16_gapdelta.py                       84 -> 84, 0 closed, 0 newly gapped
_c16_residue.py / _c16_residue.json    the four-class residue
_c16_ruleT_leaves.json / _c16_c15state.json    the C15 R2 inputs
```

**Where the endpoint stands.**

```
  C12 (cap 4)  298 sets with a gap
  C13 R1       227   (-71,  1 554 runs)
  C13 R2       227   ( -0,    406 runs)     rate rule fired
  M-SNAP       184   (-43,      0 runs)     a declaration (§26)
  C14 R1       105   (-79, 10 396 runs)
  C14 R2       103   ( -2,  2 555 runs)     rate rule fired
  C15 R2        84   (-19,      0 runs)     §16e in src/ (§28)
  C16 R1        84   ( -0,  1 192 runs)     rate rule fires; every §16e cube
                                            constructed, driven, explained
  CURRENT   COMPLETE=False; NODES=441; MISSING=68; BLOCKING=64;
            DEMAND_SETS=1630; tree_missing 0   (_cov_C16_C16R1.json)
            84 gap-sets = 28 multi-gate-unreachable (§13.3)
                        + 25 Rule T
                        + 31 A>0-at-the-gates, full assignment never produced
```

The endpoint's remaining distance is not an assumption problem and not a
driver problem. It is two owner questions (§13.3's ruling, Rule T's boundary
change) covering 53 of the 84, and one honestly open class of 31.


## §30. C17 — THE RE-MINTED-LENGTH SEED KEY. THE FIX WORKS; THE 24 LEAVES ARE **NOT** RULE T, AND **NOT** A DRIVING BACKLOG EITHER (2026-09-13)

Coordinator, mid-round: `notifications_index/_c17_seedkey_fix.py`
(self-test `C17-SEEDKEY-FIX-SELFTEST-OK`). `targets.rb`'s loaded-target early
return RE-MINTS an already-decided list length under an owner-derived name
(`..._<assoc>_row_rows`) without consulting a seed, so a demand written at
that name is INERT; the runtime reads the UPSTREAM materialize-mock key
(`len(SYM_RESULT_..._CollectionProxy_records_N_rows)`), which
`remint_map(dump)` resolves from the base dump alone. *"24 of the 25
CONTRADICTED leaves constrain a re-mint — they are driveable, NOT Rule T."*

The fix is real, and the first half of that is confirmed to the key. The
second half is not, and C17 is the controlled experiment that shows why.

### §30.1 What was built

`_c17_construct.py` = `_c14_construct.py` + `remint_map`, one map per BASE
(it is a property of the base's `symbolic_vars`), applied after ordinal
resolution to the runtime seed keys `seedkeys()` produces — which is the only
place it CAN be applied: the checker-side canonical name
(`..._to_ary_notifications_10254800_row_target_photos_row_rows`) and the
runtime key (`len(SYM_RESULT_..._to_ary_1_row_target_photos_row_rows)`) are
different strings, and an offline probe that compares them directly finds
nothing (it found 0/25 before the mistake was caught).

Two knobs, because the first build immediately hit something:

```
  C17_SEEDKEY_FIX=1   apply remint_map at all                       (default 1)
  C17_MOVE_WINS       what to do when the cube ALSO demands the
                      upstream key directly, with a DIFFERENT value (default 0)
```

### §30.2 The finding that forced the second knob: **72 CLASHES, 0 clean moves**

On the C16 batch of 1 192 cubes, the conservative build reports:

```
  demands MOVED to the upstream key   :  0 in 0 of 1192 seeds
  re-mints the base could NOT resolve :  0
  the cube demands BOTH names         : 72
     x24  len(..._to_ary_1_row_target_photos_row_rows)
     x24  len(..._to_ary_1_row_target_mentions_container_commentable_photos_row_rows)
     x24  len(..._to_ary_1_row_target_mentions_container_photos_row_rows)
```

**Every single re-mint this endpoint's residue constrains is one the SAME CUBE
also constrains under its upstream name, to an incompatible value.** Worked
through on `c001134` (base `dump_mobile_typed_dse0002_C14Amobt0004r0.json`):

```
  cube demands   (SYM_LEN_..._CollectionProxy_records_photos_aa895602_rows > 1) TRUE
                 (SYM_LEN_..._to_ary_notifications_10254800_row_target_photos_row_rows != 0) FALSE
  remint_map     len(..._to_ary_1_row_target_photos_row_rows)  minted 1
                    -> upstream len(..._CollectionProxy_records_2_rows) = 1
  and `seedkeys()` maps the cube's FIRST literal to that SAME runtime key.
```

So the cube asks one runtime dimension to be `> 1` and `== 0` at once.

### §30.3 The controlled A/B — 109 cubes, same bases, the move ON and OFF

`_c17_gaps.json` = exactly the 109 cubes C16 classified CONTRADICTED
(36 leaf groups, 35 sets), constructed twice from the same bases, driven as
`C17A` with `C17_MOVE_WINS=1` (72 of 109 seeds took a move), and scored
against the C16A replays of the identical cubes.

```
_c13_drive.sh C17A 200   06:10 -> 06:19:18   +109 dumps for 109 seeds
   6 legs each with its END line; 6 chunks all DONE consumed=N/N tries=1 toxic=0
   VERDICT C13-DRIVE-DONE C17A  +109 dumps  0 seeds left
```

```
  the re-mint / upstream PAIR, same 109 cubes, same bases
    name class   C16 (no move)  ->  C17 (move wins)   keys
    RE-MINT           CON       ->       HON            72
    UPSTREAM          HON       ->       CON            72
```

**Exactly 72 keys flip each way, and not one cube realises in either
direction.** That is the whole result:

* **the fix WORKS, 72/72.** Every previously-inert demand on a re-minted
  nested length is honoured once it is written at the upstream key. The
  decisions §27.13(4) and §29.8(4) called "not under seed control" ARE under
  seed control — at the other name;
* **and it buys these leaves nothing**, because the same cube pins the same
  runtime dimension the other way under its other name.

```
=== C17A PER KEY (634) ===          === PER CUBE (109) ===
  HONOURED        504  (79.5 %)       REALISED         0  ( 0.0 %)
  CONTRADICTED    109  (17.2 %)       CONTRADICTED   109  (100 %)
  NEVER-EVALUATED  21  ( 3.3 %)
  (the 109: 72 upstream photo lengths + 37 identity compares)
```

### §30.4 The 25 CONTRADICTED witness leaves, as asked

All 25 are in the C17 batch and all 25 were driven.

```
                       C16A                    C17A
  per CUBE verdict     CONTRADICTED 25         CONTRADICTED 25
  per KEY (121 keys)   HONOURED     96 (79.3 %)  HONOURED     96 (79.3 %)
                       CONTRADICTED 25 (20.7 %)  CONTRADICTED 25 (20.7 %)
```

**The honour RATE is identical to the tenth of a percent; only the IDENTITY of
the contradicted key changes** — from the re-mint in C16 to its upstream in
C17, one key per leaf, in 24 of the 25. The 25th is the identity compare
`find_by_1_person_id == devise_user_first_1_person_id`, which involves no
re-mint and is unchanged by the fix (37 cubes carry it).

### §30.5 What this reclassifies, and what it opens

**DROP the Rule T marking on these 24 — the coordinator is right about that,
and for a stronger reason than the one proposed.** No change to the shared
target boundary would help: the dimension is already seedable, at the upstream
name, measured. Rule T is not what stands between this endpoint and those 24
sets, so the boundary does not need to be reopened for them. What remains of
Rule T is **1** gap-set: the identity compare.

**But they are not a driving backlog either, and the batch is not "reported"
in place of being driven — it WAS driven, twice, both ways.** They are an
**ALIASING gap in the checker's canonical universe**: `canonicalize_ordinals`
keeps `..._CollectionProxy_records_photos_<hash>_rows` and
`..._row_target_photos_row_rows` as two decisions, while the loaded-target
early return makes them two READINGS OF ONE VALUE at runtime. The demand asks
them to differ; no run can produce that, and the corpus agrees — `A = 0` over
the full cube on all 84 residual leaves (§29.8), and 72/72 of these keys swap
rather than co-satisfy under a direct controlled test.

That is an §19 / alias question (does an `AliasAssumption` — or the §16c
footprint layer — unify a loaded-target re-mint with its materialize mock?),
NOT Rule T and NOT §13.3. **It is REPORTED, with the A/B as its evidence; no
declaration is made and no `src/` change is proposed here.** The falsifier for
such a declaration is stated so the next round can run it: *a run in which the
upstream materialize length and the re-minted association length are recorded
with DIFFERENT values.* `_c17_seedkey_fix.py`'s own 600-base probe already
measured 607/607 with the upstream value EQUAL to the re-mint's, which is
evidence for the unification and against the demand — but it is a sample, not
a proof, and it is quoted as such.

### §30.6 The revised residue — 84 gap-sets

```
  28   §13.3 multi-gate-unreachable (A = 0 at the gate conjunction)
       — constructed, driven, 576 cubes all UNEVALUATED. Needs a RULING.
  24   re-mint / upstream ALIASING (was "Rule T"): the cube constrains one
       runtime dimension under two canonical names, to incompatible values.
       Driven both ways; 72 keys swap, 0 realise. Needs an ALIAS ruling.
   1   Rule T proper: the identity compare
       find_by_1_person_id == devise_user_first_1_person_id
  31   A > 0 at the gates, full assignment never produced, no re-mint, no
       Rule T member — the honestly open class.
```

### §30.7 THE PASS — 84 -> 84 again, and the rate rule fires a third time

`_c16_pass.sh _snapshot_c16_R2.txt C17R2`, 130 822 runs (= C16 R1 + all 109
C17A dumps), same engine, `FORECLOSURE_CONJUNCTIONS=1`, cap 1, checkpointed.
It was worth running rather than assuming: the C17A runs are the FIRST in the
corpus that honour a re-minted nested length, so they are genuinely new
profiles and could have blocked something.

```
COMPLETE=False;NODES=441;MISSING=68;BLOCKING=64;PCS=8335525
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
CONJ_FORECLOSURES=89;CONJ_GROUPS=89;CONJ_PROVISIONAL=False;UNMATCHED_CONJ=12;FORECLOSURES=5278
dump_errors={'ActionView::Template::Error': 45917, 'I18n::InvalidLocale': 1}
coverage phase 1 101 s   wall 41 m 52 s   peak RSS 5 410 MB
VERDICT C16-C17R2: OK (line present)      C16-PASS-DONE C17R2
```

```
  _c16_gapdelta.py  _cov_c16_C16R1.ckpt.jsonl -> _cov_c16_C17R2.ckpt.jsonl
     demand universe: shared 1630, only-before 0, only-after 0
     CLOSED 0   NEWLY GAPPED 0   STILL GAPPED 84
     witness leaf UNCHANGED 84 of 84;  distinct leaves 64 -> 64, 64 shared
```

```
  round       | runs   | sets with a gap | closed | closed/run | wall
  C14 R1      | 10 396 | 105             |   79   |   0.0076   | ~4 h 00
  C14 R2      |  2 555 | 103             |    2   |   0.00078  | ~2 h 00
  C15 R2      |      0 |  84             |   19   |     —      | §16e in src/
  C16 R1      |  1 192 |  84             |    0   |   0.000    | ~1 h 40
  C17 R2      |    109 |  84             |    0   |   0.000    | ~55 min
```

### §30.8 Ops and artefacts

```
  notif-c17-construct-1/2  4G     8 s / 4 s     the clash finding, then MOVE_WINS
  notif-c17-driveA-1       6G     8 min 31 s    109 seeds, DRIVE_PAR=2
  notif-c17-passR2         9G    41 min 52 s    peak 5 410 MB
     (queued 15 min behind posts_show's pass by the coordinator's new rule,
      which the gate enforced from inside the unit — see §29.9)
```

```
_c17_seedkey_fix.py        the coordinator's fix (remint_map / fix_seeds)
_c17_construct.py          _c14_construct.py + remint_map, C17_SEEDKEY_FIX /
                           C17_MOVE_WINS knobs, per-seed remint counters
_c17_gaps.json             the 109 C16-CONTRADICTED cubes (36 groups, 35 sets)
_c17_seeds_*.json / _c17_manifest.json     109 seeds, 72 with a move
_c17_construct.log         the CONSERVATIVE build over all 1 192: 0 moves, 72 clashes
_c17_construct2.log        the MOVE_WINS build over the 109: 72 moves
_c17_driveA_outer.log / _chunk_drive_C17A.log
_c17_classify_C17A.json    79.5 % per key, 0 realised, 109 contradicted
_snapshot_c16_R2.txt (130 822)
_cov_C16_C17R2.json / _cov_c16_C17R2.ckpt.jsonl     84 gap-sets  <- CURRENT
```

**Where the endpoint stands after C17.**

```
  CURRENT   COMPLETE=False; NODES=441; MISSING=68; BLOCKING=64;
            DEMAND_SETS=1630; tree_missing 0   (_cov_C16_C17R2.json)
  84 gap-sets = 28  §13.3 multi-gate-unreachable   -> needs a RULING
              + 24  re-mint / upstream ALIASING     -> needs an ALIAS ruling
              +  1  Rule T (the identity compare)   -> needs the boundary
              + 31  full assignment never produced  -> open
```



## §31. C18 — THE TWO RULINGS MADE, WITH FALSIFIERS: RE-MINT IDENTITY AND THE OUT-OF-RANGE DISPATCH (2026-09-13)

Owner direction (Bali, 2026-09-13): *"make the fair assumptions that the
evidence supports, with a falsifier, and carry the endpoint through. Do not
park anything as 'owner ruling' that a declaration with a stated falsifier can
honestly cover."*

§30 left 84 gap-sets in four classes and two of them parked on an owner:
28 §13.3 multi-gate-unreachable, 24 re-mint/upstream aliasing, 1 identity
compare, 31 open. This round rules on the first two, refuses the third on the
evidence, and re-measures the fourth.

### §31.1 What was measured before anything was declared

Three whole-corpus instruments, all read-only, all re-derivable:

```
_c18_identity_census.py   130 822 dumps, canonicalised with THIS batch's
                          ALIASES (so the names counted are the CHECKER's
                          spellings), 4 workers, 2 m 52 s, peak 96 MB
_c18_profile_diff.py      the same corpus, split by whether all eight
                          SYM_NOTE_TYPE_PROFILE literals came back not_taken
_c18_a0_table.py          the 32 A = 0 gate prefixes x their 576 driven C16A
                          cubes, per gate literal
```

### §31.2 RULING 1 — RE-MINT-IDENTITY. The 24 aliasing gap-sets, CLOSED.

**The mechanism, from the harness source.** `targets.rb:1071-1090`, the
`records`/`load_target` mock's loaded-target early return:

```ruby
tgt = a0.target
next(IterableSymbolicList.new(tgt.length, name: "#{abase0}_rows",
       note: "preloaded association ##{a0.reflection.name}: answered from the
              loaded target, no statement ..."))
```

`tgt` IS the list the upstream `CollectionProxy#records` materialise mock
produced. The two canonical names the checker keeps apart are two readings of
one value.

**The census — the whole corpus, not a sample.**

```
  29 canonical (re-mint, upstream) pairs
  139 585 paired observations       EQUAL 139 585      DIFFERENT 0
  re-mints minted with NO upstream in the run                    0
  runs pairing ONE re-mint with TWO upstream names               0
```

The last line is load-bearing: photos keeps SIX statement names (three owner
chains x {the real read, its empty-scope `AND (1=0)` variant}), so a re-mint
has two possible partners — but never both in one run, so declaring both
equalities never equates the two upstream names with each other.

**The active falsification (§79 / RENDER_IDENTITY model), because a census is
a passive observation.** `_c18_fals_construct.py` picked 64 bases across six
request variants that mint both names, with a per-association-family quota so
photos and aspect_memberships are exercised as hard as services, and replayed
each base with EVERY upstream length key it feeds a re-mint overwritten to v,
v over the mock's whole domain {0,1,2,3,4}. `_c13_drive.sh C18F 60`, 320 runs,
DRIVE_PAR=2, 10 m 47 s.

```
  replays 320   errors 0   runs with no pair minted 0
  the upstream length WAS realised, at three distinct values per family:
      seed 0 -> upstream 0 (167)   seed 1 -> 1 (167)   seed 2/3/4 -> 3 (501)
  paired observations 835   EQUAL 835   DIFFERENT 0
  19 of the 25 declared pairs exercised (the photos statement names the
  chosen bases did not all mint are the shortfall, stated not hidden)
  VERDICT  C18-FALSIFICATION PASS
```

**The declaration.** `coverage_assumptions.py`, tier `RE-MINT-IDENTITY`, 25
`SymbolicConstraintAssumption`s `SYM_LEN_<remint> == SYM_LEN_<upstream>` —
every alias/ordinal the corpus names BOTH of whose sides occur in a tracked
expression. The other four pairs (aspects / services / aspect_memberships x2
off the principal, 92 398 observations, 0 different) are equally true and
deliberately NOT emitted: their re-mint side is never a recorded decision
here, so no demand can name them, and an extra constraint over a variable the
declarations might not carry makes `solver.py` return unsat for EVERY query —
M-SNAP's stated failure mode, which looks exactly like completeness.

**Not an `AliasAssumption`, for RENDER_IDENTITY's reason.**
`_alias_core` keys on a STATEMENT note and the re-mint's note is the prose
"preloaded association #<assoc>: answered from the loaded target, no
statement" — by construction not a statement, since the whole point of the
early return is that no query is issued. The alias map comes back empty.

**Falsifier.** Any run recording a re-minted association length and its
upstream materialize length with different values. `_c18_identity_census.py`
IS that test over any dump list (~3 min); the C18F drive is its constructed
form. A Rule T change making the loaded-target return independently seedable
refutes the tier and withdraws it. `NO_REMINT_IDENTITY=1` withdraws it
without an edit.

**Gate.** As the brief predicted, the shipped derived test is NOT-TESTABLE on
this shape: `assumption_checker.test_declared` derives the single violating
value for a `VAR op INT` constraint, and `VAR == VAR` is not that form. The
active falsification above is run in its place and recorded, exactly as §79
did for RENDER_IDENTITY.

### §31.3 RULING 2 — GATE-CONJ-INFEASIBLE. The 28 A = 0 witness leaves,
### killed (the SETS survive on their sibling leaf — see §31.6a)

**The table the brief asked for, and it is uniform.** All 32 A = 0 gate
prefixes of the C16 enumerator, their 576 constructed cubes and 576 driven
C16A runs (`_c18_a0_table.py`, `_c18_a0_table.json`):

```
  prefixes                                              32
  driven cubes / driven runs                       576 / 576
  prefixes REALISED by any driven run                    0
  prefixes whose ONLY unsatisfied gate literal is
      ..._row_target_mentions_container_not_found    32 / 32
  that literal's verdict over its runs        NEVER-EVALUATED, 576 / 576
  consistency                                        100 %
  every OTHER gate literal of every prefix              HONOURED
```

It is not the same *pair* every time in the sense the brief anticipated (a
`g1=o1 forces g2!=o2`): it is the same *coupling* every time, between an
8-literal dispatch conjunction and one member.

**The mechanism, identified in the harness source.**
`build_notification_representative` (`targets.rb:872-901`) mints
`SYM_NOTE_TYPE_PROFILE` from a seed and compares it against every index of the
EIGHT-entry `NOTE_TYPE_PROFILES` table (`:209-241`), recording all eight
decisions unconditionally; an index outside 0..7 records all eight as
not_taken and leaves `profile = NOTE_TYPE_PROFILES.first  # defensive default
(idx out of range)`, so the run renders a `Notifications::Liked` with
`target_type: "Post"`. The `mentions_container` chain exists only on a
`Mention` target — indices 4 and 5 — and its container pin (`:1517-1529`) is
guarded by `if klass.name == "Mention"` and derives itself from
`@active_note_profile`. An out-of-range index therefore renders a Post-target
notification and never reads `target.mentions_container`.

**The ground-truth differential** (`_c18_profile_diff.py`, whole corpus):

```
                                OUT-OF-RANGE      IN-RANGE
   runs                                9 270       120 641
   mentions_container decided              0        41 042
   target_not_found   decided          9 014       116 828
   person_not_found   decided          8 282       112 456
   Core.find_by_1_not_found decided     1 349         2 452
```

The out-of-range state is reachable and is NOT declared away — 9 270 runs of
this corpus are in it (dispatch values 8, 424245, 424249, reached deliberately
by the C14/C16 constructors) and they decide every OTHER gate of these
prefixes. Exactly one member never co-occurs with it, in 9 270 of 9 270 runs,
for the reason the source gives.

**The declaration.** Tier `GATE-CONJ-INFEASIBLE`, four constraints — one per
`to_ary notifications` statement variant:

```
  Or(SYM_NOTE_TYPE_PROFILE == 0, ..., == 7,
     <variant>_row_target_mentions_container_not_found == True)
```

i.e. `Not( out-of-range AND the mention container was FOUND )`.

**The asymmetry, stated rather than hidden.** Only the FOUND direction is
declared. The full truth is "out of range implies the decision is never
MINTED", and over a free Z3 Bool excluding BOTH outcomes collapses to
`Not(out-of-range)` — which is FALSE, refuted by 9 270 runs. A free Bool
cannot express "this decision does not exist in that run", so the constraint
is written for the direction the residue demands and the other side is left
free and reported here.

**Falsifier.** Any run in which all eight dispatch literals are not_taken and
`..._row_target_mentions_container_not_found` is recorded not_taken.
`_c18_profile_diff.py` is that test. A Rule T widening of `NOTE_TYPE_PROFILES`
or any change that reads `mentions_container` off a non-Mention target
refutes it. `NO_GATE_CONJ=1` withdraws it without an edit.

**Active falsification, not only a census.** The 9 270 out-of-range runs are
not an accident of the corpus: 576 of them were CONSTRUCTED for exactly this
prefix by `_c14_construct.py`/`_c16_construct` (the seed writes
`SYM_NOTE_TYPE_PROFILE: 8`) and driven as C16A. The deliberate attempt to
realise the conjunction was made 576 times, the out-of-range dispatch WAS
realised every time (all eight literals recorded not_taken), and the container
decision appeared in none of them. That is the same shape of evidence §79
asks for, already spent.

**Gate.** `Or(...)` is not `VAR op INT` either, so
`assumption_checker.test_declared` returns NOT-TESTABLE here as well, and a
NOT-TESTABLE is not a licence (§24.4). The 576 constructed runs above are what
carries the claim; the full gate was not re-run because its `corpus_index`
leg (~40 min over 300 k dumps) would contend with the posts_show gate the cage
is holding, and it could only repeat the NOT-TESTABLE.

### §31.4 NOT RULED — `find_by_1_person_id == devise_user_first_1_person_id`

The brief asked: if the finder is called with the signed-in user's person id,
declare the identity. **It is not, and the corpus says so plainly.**

```
  runs minting BOTH person ids                     11 569
     values EQUAL                                   5 012
     values DIFFERENT                               6 557
  runs minting only one of the two                 87 837
  the COMPARE itself, over 129 521 indexed runs
     taken 2 577      not_taken 8 881
```

The decision is `PersonPresenter#own_profile?` /
`current_user.person == person` — "is this contact's person the signed-in
user's own person?" — a genuine free application state with both outcomes
observed thousands of times. An identity declaration would be refuted by 6 557
runs and is NOT made.

**What the leaf actually needs is a seed, and the constructor did not write
one.** The single gap-set (`37e4460e...`, width 13) demands the compare TRUE
with twelve other literals; 19 corpus runs match those twelve and all 19 record
the compare FALSE, and the C16A replay contradicted it. The C16 seed
(`_c16_seeds_html_typed.json#324`) writes
`devise_user_first_1_person_id = 0` and **no** `find_by_1_person_id` — a
var-var equality literal needs BOTH sides seeded to the same value and
`_c13_construct.synth` seeds only one. The dimension IS seedable: corpus dumps
carry `SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_id` in their
`concolic_seeds`. So this is a CONSTRUCTOR gap, not Rule T — the last Rule T
marking on this endpoint is dropped.

### §31.5 The 31 OPEN leaves, re-measured per key — and why §16e cannot reach them

**Per-key drive analysis** (`_c18_leafdrive.py`, class `open`, over the C16A +
C17A replays):

```
  31 leaves, 47 replays, 31 of 31 UNEVALUATED, 0 keys CONTRADICTED
  every leaf has EXACTLY ONE never-evaluated member (four have three):

    x16  (devise_user_first_1_person_profile_not_found == True)  = False
    x 7  (FinderMethods_exists__5_exists == True)                = False
    x 3  (FinderMethods_exists__5_exists == True)                = True
    x 1  (FinderMethods_exists__8_exists == True)                = False
    x 4  the three ..._row_target_statusmessage / _target_author
         members of one to_ary variant each
```

Nothing is contradicted. Each of the 31 is one decision short of its cube.

**A SECOND round was constructed and driven** rather than reported —
`_c18_gaps.json` (the 32 constructible cubes), `_c14_construct.py` with
`BASES_PER_GROUP=4`, plus 12 hand-overlaid seeds for the identity cube taken
from bases that RECORD the compare taken. `_c13_drive.sh C18R 30`, 44 runs,
6 min 18 s.

```
  C18R  per gap (32):  REALISED 0   UNEVALUATED 31   CONTRADICTED 1
        44 replays; dump errors {'-': 27, gon: 16, other: 1}
        the identity cube's demanded compare moved CONTRADICTED -> HONOURED
        (the overlay works); it now contradicts on the SPLIT SELF-COMPARE
        (find_by_1_person_id == ..._person_id__prior) demanded False, which
        seeding both ids equal necessarily makes True — the two are coupled
        through gon_helper.rb:6's "is this contact already stored?"
        the other 31 keep exactly the same single never-evaluated member
```

**WHY they are stuck, measured** (`_c18_minimal_cond.py`). For every open leaf
and its never-evaluated member, the MINIMAL subset of the leaf's own literals
under which the member is foreclosed (A > 0, B = 0) was searched to width 3:

```
  members with a foreclosing subset of width <= 3        39
     of them conditioned ONLY on GATE literals            0
     conditioned on at least one NON-GATE member         39
  members with no such subset (A > 0 all the way)       192
```

**Not one of them conditions on gates alone.** §16e forecloses under GATE
conjunctions by design (gates define the leaf; the falsifier's member list is
`surv - P`), so it structurally cannot reach any of these. Example, the
16-leaf family, A = 108-128 and B = 0 in each:

```
  member   (devise_user_first_1_person_profile_not_found == True) = False
  minimal conditioning
     True   (SYM_LEN_..._to_ary_notifications_<v>_rows > 1)
     True   (SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found == True)
```

i.e. with more than one notification row AND the contact finder returning
nothing, the principal's profile decision is never minted — plausibly because
`gon_load_contact(note.contact)` never presents a contact, so
`ContactPresenter#full_hash_with_person` never reads it. **This is REPORTED,
not declared.** Declaring it would be doing by hand what §16e deliberately
restricts to gate prefixes, and the mechanism above is inferred from the call
graph rather than read end to end. It is a §16f question — *should foreclosure
condition on non-gate members?* — with its evidence attached
(`_c18_minimal_cond.json`), and it is the whole of what stands between this
endpoint and its remaining 31 sets.

**The `exists__5` / `exists__8` family (11 leaves) has a second, separate
cause.** Those names are `ActiveRecord::FinderMethods#exists?` call ORDINALS
(`Post.exists?(guid:)` from a `diaspora://` link in a rendered text or bio,
`targets.rb:1280-1347`), and the endpoint's `AliasAssumption`s cover only
`Relation_records` / `Relation_to_ary` / `CollectionProxy_records` — not this
family. The ordinal moves with the path prefix, so "the same decision" is
several canonical names. That is a P0/P1-shaped alias question for a family
whose gate test (which probes by intervening on `len(<ordinal>_rows)`) has no
length dimension to probe, so it is reported, not declared.

### §31.6 THE PASS — 84 -> 60, and every closed set is the RE-MINT class

`_c18_pass.sh _snapshot_c16_R2.txt C18R1` — the SAME 130 822-run corpus the
C17R2 verdict was measured on, so the only thing that moved is the two
declarations. (`_c16_pass.sh` was copied to `_c18_pass.sh` first; §29.9's
rule. The C18F/C18R runs are deliberately NOT in this corpus — they are folded
in by the R2 pass below, where their effect can be told apart from the
declarations'.)

```
COMPLETE=False;NODES=441;MISSING=40;BLOCKING=36;PCS=8335525
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
CONJ_FORECLOSURES=89;CONJ_GROUPS=89;CONJ_PROVISIONAL=False;UNMATCHED_CONJ=8;FORECLOSURES=5278
dump_errors={'ActionView::Template::Error': 45917, 'I18n::InvalidLocale': 1}
coverage phase 1 129 s   wall 39 m 03 s   peak RSS 5 409 MB
VERDICT C18-C18R1: OK (line present)      C18-PASS-DONE C18R1
[assumptions] ... M-SNAP=8 RE-MINT-IDENTITY=25 GATE-CONJ-INFEASIBLE=4 ...
```

```
                        C17R2        C18R1
  MISSING                  68           40
  BLOCKING                 64           36
  UNMATCHED_CONJ           12            8
  distinct witness leaves  64           36
```

`_c16_gapdelta.py _cov_c16_C17R2.ckpt.jsonl -> _cov_c18_C18R1.ckpt.jsonl`

```
  demand universe: shared 1630, only-before 0, only-after 0
  CLOSED 24   NEWLY GAPPED 0   STILL GAPPED 60
  of the still-gapped: witness leaf UNCHANGED 32, REPLACED 28
```

**Per class:**

| class at C17R2 | sets | after C18R1 | why |
|---|---|---|---|
| re-mint / upstream aliasing | 24 | **0 — CLOSED** | `RE-MINT-IDENTITY` makes `upstream > 1 AND re-mint == 0` UNSAT |
| §13.3 A = 0 multi-gate | 28 | 28, **new witness leaf** | `GATE-CONJ-INFEASIBLE` killed the FOUND-side leaf; the sibling leaf pins the same gate NOT-FOUND |
| Rule T identity compare | 1 | 1 | not an identity; a constructor gap (§31.4) |
| open (A > 0, assignment never produced) | 31 | 31 | §31.5 |

Nothing was newly gapped and no observed profile lost its demand — checked
before the pass with the engine's own solver (`_c18_solver_check.py`: the 28
A = 0 and 24 re-mint leaves go SAT -> unsat, the 31 open and the 1 identity
leaf stay SAT, all 37 constraints (8 M-SNAP + 25 re-mint + 4
gate-conj) parse and are jointly satisfiable, and 0 of 400 sampled OBSERVED
run cubes are made unsat).

### §31.6a The 28 SETS did not close, and the reason is the asymmetry the declaration ITSELF wrote down

`GATE-CONJ-INFEASIBLE` declares only `Not( out-of-range AND container FOUND )`.
The pass shows exactly the predicted consequence: all 28 sets kept their gap
with a NEW witness leaf that is the same cube with the container gate flipped,

```
  all eight (SYM_NOTE_TYPE_PROFILE == k) not_taken
  AND  ..._row_target_mentions_container_not_found  == True   (NOT FOUND)
```

and the pass's own `unmatched_gate_conjunction_prefixes` went 12 -> 8, all
eight of them that shape. Both outcomes are genuinely unreachable under an
out-of-range dispatch — the decision is never MINTED — but as Z3 constraints
the two directions together are `Not(out-of-range)`, and 9 270 runs of this
corpus refute that, so declaring the second one is not available. Declaring it
anyway would also be the `split_self_compare` bug from the other side: a
demand set whose only observed cubes are out-of-range would report
`covered == 0`.

**What actually stands in the way is one line of §16e**, and the question is
now precise enough to answer in one:

> §16e says *"Gates are never conjunction-foreclosed. They DEFINE `P`."*
> `..._row_target_mentions_container_not_found` is a GATE of these leaf
> groups, so it can never be foreclosed — even though it IS foreclosed under
> a SUB-conjunction of its own gate prefix: over the eight dispatch literals
> alone, **A = 9 270 and B = 0**, measured on this corpus, with the mechanism
> in `targets.rb:872-901` / `:1517-1529`.

That is a §16f question — *may a gate be conjunction-foreclosed under a proper
sub-prefix of its own leaf-group conjunction?* — and it is the whole of the
28. It is an `src/` change and is NOT made here.

### §31.7 Ops

Cage 24 G shared with the posts_show confinement gate (never stopped; it held
11.0-11.7 G throughout). Every launch gated on `free -g >= 4` AND
`(24 G - slice MemoryCurrent) >= cap`, both logged; the pass additionally
gated INSIDE the unit on `pgrep -a python3 | grep -q
"posts_show/coverage_report[.]py"` being empty, per the 2026-09-13 rule.
`_c16_pass.sh` was NOT edited — it was COPIED to `_c18_pass.sh` first (§29.9's
rule), and nothing was edited while running.

```
  CAGED (systemd-run --user --scope --slice=concolic-cov.slice)
    _c18_census.sh          4G   2 m 52 s   peak    96 MB   130 822 dumps
    _c18_pass.sh C18R1      8G  39 m 03 s   peak 5 409 MB   130 822 runs
    _c18_pass.sh C18R2      8G   queued behind a posts_show pass by the gate
    _c13_drive.sh C18F  JRUBY_CAP=2G DRIVE_PAR=2  07:32:29 -> 07:43:16  +320
    _c13_drive.sh C18R  JRUBY_CAP=2G DRIVE_PAR=2  07:50:29 -> 07:56:47  +44
  UNCAGED, small and short-lived (read-only analysis, RSS well under 1 GB —
  stated rather than dressed up as a service):
    _c18_profile_diff.py    4 workers, ~3 min over 130 822 dumps
    _c18_fals_construct.py  ~20 s (20 000 dumps scanned)
    _c18_solver_check.py    3 000 runs + the engine's Z3, a few minutes
    _c18_a0_table.py / _c18_leafdrive.py / _c18_minimal_cond.py / classifiers
```

No `src/` edit, no `targets.rb` edit, no shared-boundary edit, no extraction,
no git, nothing under `posts_show/` or `comments_index/`. The only
PRE-EXISTING project files modified are
`notifications_index/coverage_assumptions.py` (backup
`_bak_coverage_assumptions_pre_c18_20260913.py`) and this campaign document
(backup `_bak_COMPLETION_CAMPAIGN_pre_c18_20260913.md`); everything else
this round wrote is a new `_c18*` artefact.

### §31.8 Artefacts

```
_c18_identity_census.py / .json / _c18_census.log / _c18_census.sh
                                       29 pairs, 139 585 obs, 0 different
_c18_profile_diff.py / _c18_profile_diff_pre.json
                                       OOR 9 270 runs, 0 mentions_container
_c18_a0_table.py / _c18_a0_table.json  32 prefixes x 576 runs, 100 % uniform
_c18_fals_construct.py / _c18f_construct.log / _c18f_seeds_*.json /
_c18f_manifest.json                    320 seeds, 64 bases, 6 variants
_c13_drive.sh C18F -> _c18f_drive_outer.log / _c13_drive_C18F.log
_c18_fals_classify.py / _c18f_classify.json      PASS, 835 equal, 0 different
_c18_solver_check.py                   all 37 constraints parse (8 M-SNAP +
                                       25 re-mint + 4 gate-conj), jointly SAT;
                                       28 A0 + 24 re-mint
                                       leaves SAT -> unsat; 31 open + 1 identity
                                       still SAT; 0 of 400 observed run cubes killed
_c18_leafdrive.py / _c18_leafdrive_open.json     per-key drive of the open class
_c18_residue.py -> _c18_residue.json   the C18R1 residue in three classes
   (computed with _c16_index.pkl, 129 521 of the 130 822 corpus dumps —
    the same index _c16_residue.json used, stated not assumed)
_c18_minimal_cond.py / _c18_minimal_cond.json    39/39 foreclosures need a
                                                 NON-GATE member
_c18_gaps.json / _c18r_seeds_*.json / _c18r_manifest.json / _c13_drive_C18R.log
_c18r_classify_C18R.json
_c18_pass.sh (copy of _c16_pass.sh)    _c18_cov_C18R1.log / _c18_cov_C18R1.time
_cov_C18_C18R1.json / _cov_c18_C18R1.ckpt.jsonl
_c18_snapshot.sh / _snapshot_c18_R2.txt (131 186)
_c18_cov_C18R2.log / _c18_cov_C18R2.time / _cov_C18_C18R2.json /
_cov_c18_C18R2.ckpt.jsonl        60 gap-sets  <- CURRENT
_bak_coverage_assumptions_pre_c18_20260913.py
```


### §31.9 WHERE THE ENDPOINT STANDS AFTER C18

```
  C12 (cap 4)  298 sets with a gap
  C13 R1       227   (-71,  1 554 runs)
  C13 R2       227   ( -0,    406 runs)     rate rule fired
  M-SNAP       184   (-43,      0 runs)     a declaration (§26)
  C14 R1       105   (-79, 10 396 runs)
  C14 R2       103   ( -2,  2 555 runs)     rate rule fired
  C15 R2        84   (-19,      0 runs)     §16e in src/ (§28)
  C16 R1        84   ( -0,  1 192 runs)
  C17 R2        84   ( -0,    109 runs)
  C18 R1        60   (-24,      0 runs)     TWO declarations (§31.2, §31.3)
  C18 R2        60   ( -0,    364 runs)     the round's own runs folded in

  CURRENT   COMPLETE=False; NODES=441; MISSING=40; BLOCKING=36;
            DEMAND_SETS=1630; tree_missing 0   (_cov_C18_C18R2.json,
            131 186 runs — the corpus every later round should start from)

  60 gap-sets = 28  A = 0 gate conjunction, out-of-range dispatch x the
                    mentions-container GATE  -> §16f, one line of §16e
              + 31  A > 0, one member never evaluated under the leaf's own
                    other literals; 39/39 of the foreclosures that explain
                    them need a NON-GATE member -> §16f, same line
              +  1  the identity compare: a CONSTRUCTOR gap (a var-var
                    equality needs both sides seeded), no longer Rule T
```

**Rule T is now empty on this endpoint.** §30 dropped the 24 aliasing leaves'
Rule T marking; §31.4 drops the last one. No change to the shared target
boundary is required by anything in this residue.

**All three remaining classes are ONE question**: may a decision be
foreclosed under a conjunction that is not exactly its leaf group's gate
prefix — a proper sub-prefix (the 28), or a conjunction containing non-gate
members (the 31)? Both are measured on the corpus, with A and B per (leaf,
member), in `_c18_a0_table.json`, `_c18_profile_diff.json` and
`_c18_minimal_cond.json`. The remaining 1 needs a constructor that seeds both
sides of a var-var equality.

### §31.10 R2 — the round's own runs folded in, and they move nothing

`_c18_pass.sh _snapshot_c18_R2.txt C18R2` — 131 186 runs = C18R1's corpus + the
320 C18F falsification runs + the 44 C18R construction runs. Launched 08:28:45,
held by the coordinator's one-pass-at-a-time gate from inside the unit
(`C18 PASS C18R2 WAIT: posts_show/coverage_report.py is running`, 16 minutes)
and started on its own at 08:44:45 when that pass exited. The gate worked
exactly as intended and nothing had to be babysat.

```
COMPLETE=False;NODES=441;MISSING=40;BLOCKING=36;PCS=8366500
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
CONJ_FORECLOSURES=89;CONJ_GROUPS=89;CONJ_PROVISIONAL=False;UNMATCHED_CONJ=8;FORECLOSURES=5278
dump_errors={'ActionView::Template::Error': 45934, 'I18n::InvalidLocale': 1}
coverage phase 1 253 s   wall 40 m 35 s   peak RSS 5 426 MB
VERDICT C18-C18R2: OK (line present)      C18-PASS-DONE C18R2
[assumptions] ... M-SNAP=8 RE-MINT-IDENTITY=25 GATE-CONJ-INFEASIBLE=4 ... exprs=441
```

`exit=1` on both C18R1 and C18R2 is `coverage_report.py:717`'s own
`return 0 if summary['complete'] else 1` — the not-complete return code, not a
failure. The verdict is the `^COMPLETE=` line, which is present in both, with
`/usr/bin/time` recording a normal child exit and a 196 MB summary written.

```
  _c16_gapdelta.py  C18R1 -> C18R2
     demand universe: shared 1630, only-before 0, only-after 0
     CLOSED 0   NEWLY GAPPED 0   STILL GAPPED 60
     witness leaf UNCHANGED 60 of 60; distinct leaves 36 -> 36, 36 shared

  _c16_gapdelta.py  C17R2 -> C18R2   (the whole round, end to end)
     CLOSED 24   NEWLY GAPPED 0   STILL GAPPED 60
```

**Both halves of the added corpus are accounted for.** The 44 C18R
construction runs realised 0 of their 32 cubes, as their classifier already
said. The 320 C18F runs are genuinely new profiles — they are the only runs in
the corpus that hold a preloaded association at a length its owner did not
choose — and they falsified NOTHING: `CONJ_FORECLOSURES`, `CONJ_GROUPS`,
`FORECLOSURES` and `UNMATCHED_CONJ` are identical to C18R1 (89 / 89 / 5 278 /
8), and no set was newly gapped. So the §16e layer is stable under this
round's own evidence, and the round's whole effect is the two declarations.

```
  round       | runs    | sets with a gap | closed | closed/run | wall
  C16 R1      |  1 192  | 84              |   0    |   0.000    | ~1 h 40
  C17 R2      |    109  | 84              |   0    |   0.000    | ~55 min
  C18 R1      |      0  | 60              |  24    |     —      | 39 m (2 declarations)
  C18 R2      |    364  | 60              |   0    |   0.000    | 41 m
```

## §32. C19 — §16f IMPLEMENTED IN `src/`: FORECLOSURE OVER A **SUB**-CONJUNCTION. 60 -> 11 GAP-SETS, THE A = 0 CLASS EMPTIED (2026-09-13)

§31.9 left the endpoint's whole residue as ONE question, in two halves, each of
them a line of §16e:

> may a decision be foreclosed under a conjunction that is not exactly its leaf
> group's gate prefix — a proper SUB-prefix (the 28), or a conjunction
> containing NON-GATE members (the 31)?

Owner ruling: *"an inference of an already-accepted kind, derived from the
corpus, self-falsifying, nested-subset-provable and gate-testable, is
implemented under that discipline — not parked."* It is now **DISCIPLINE
§16f**, in the engine, opt-in and OFF by default.

### §32.1 The rule, and the one design decision that was not free

> For a demand set `S` and one of its leaves, walk the leaf's members in the
> set's own order (§16b's gate-first topological order, unchanged). With `acc`
> the literals FIXED SO FAR, a member `d` is FORECLOSED under `C` iff
> `C ⊆ acc`, `|C| <= W`, `A(C) > 0` and `B(C, d) = 0`; `C` is the
> MINIMUM-cardinality such set. A foreclosed member — GATE or not — is not part
> of the leaf and contributes NO literal downstream.

`W = foreclosure_conjunction_width`, default 3. Two things §16e forbids and
this allows, and they are exactly the two halves of the residue: `C` may
contain NON-GATE literals, and `d` may itself be a GATE.

**The walk order is the definition, not a tie-break.** `C` is drawn from the
literals fixed EARLIER, never from the whole cube. Widening it to the whole
cube would let two members foreclose each other in a cycle; restricting it to a
prefix makes each drop a function of the prefix alone, which is what keeps the
leaves a decision tree. It is also the one place the engine is deliberately
WEAKER than `_c18_minimal_cond.py`, which searched the leaf's literals
order-free — §32.5 MEASURES that difference instead of assuming it away.

**Both sides move**, as §16e's did: the emission cube AND the closed-prefix
test. On the blocking side only UNEVALUATED members are tested, and that is a
theorem rather than a shortcut: every literal of `acc` is one the profile
itself matches, so the profile is in `A(C)` for any `C` drawn from it and a
member it evaluates has `B >= 1`. Two further consequences with the flag on: a
demand set with NO §16b gate is no longer skipped outright on the blocking side
(a §16f conditioning set need not contain a gate), and the blocking-side memo
is keyed on every evaluated member, not only the gates.

**Cost is a bounded SET COVER, not `C(n, k)`.** With `R` the profiles that
evaluate `d`, `A(C) ∩ R = ∅ ∧ A(C) ≠ ∅` says the complements of the chosen
literals must COVER `R`. Iterative deepening over that cover — take one profile
still evaluating `d`, branch only on the literals it does NOT match — is exact
and minimum-cardinality. `foreclosure_conjunction_budget` (20 000 nodes) caps
it and exhaustion is a NON-inference.

### §32.2 Nesting — by construction, and measured

The drop set is §16e's UNION the walk's (`F(P)` first, on the unchanged §16b
cube, its members leaving before the walk starts), so

    §16f ⊆ §16e ⊆ §16b ⊆ §16 ⊆ complete-graph

holds BY CONSTRUCTION. 60 random corpora, leaves summed over every demand set:
**§16 4 288 -> §16b 2 293 -> §16e 2 246 -> §16f 1 903**, `⊆` checked on every
leaf, 75 sets shrinking on a sub-conjunction; through the checker 54 of 60
corpora fire and the other 6 report identically to the §16e pass. Rule T is NOT
triggered.

**The price, stated.** §16e could promise its leaves were pairwise
INCOMPATIBLE because it never drops a GATE. §16f drops gates — that IS the 28 —
so a leaf can now be a strict SUB-CUBE of a sibling: **27 of 13 914 leaf pairs
(0.19 %)** over 40 random corpora, always containment, never a crossing. It
cannot reach a verdict: the blocking side never emits a coarsened clause (a
run's clause is its EXACT evaluated assignment over the set's members; the leaf
structure only decides whether a PARTIAL run qualifies), and `complete` is
decided by a set's FIRST query, whose clauses are all run-derived. Ground
truth: over 35 corpora where the §16f checker returns `complete`, all 489
leaves of every demand set were walked by a run of that corpus.

### §32.3 Closed endpoints — byte-identity, and what ON changes

Each endpoint's UNMODIFIED `coverage_report.py`, coverage layer only, through
a harness that never edits the batch file (`run_report16f.py`,
`_16f_identity.sh`), OFF / §16e / §16f:

```
  people_stream    off  complete=True  nodes=39  missing=0  sets=21   1:26 -> 2:34
  people_stream    e    complete=True  nodes=39  missing=0  sets=21
  people_stream    f    complete=True  nodes=39  missing=0  sets=21
     OFF run BYTE-IDENTICAL to the pre-§16f engine's OFF run
     §16e-only BYTE-IDENTICAL to the pre-§16f engine's ON run
     §16f vs §16e: the ONLY key that differs is `assumptions` — 19 new
       SubconjunctionForeclosureAssumption entries (|C| = 2, A = 1 248-1 263).
       complete / nodes / missing / demand_sets / tree_missing all unchanged.

  comments_index   off  complete=True  nodes=84  missing=0  sets=79
  comments_index   e    complete=True  nodes=84  missing=0  sets=79
  comments_index   f    complete=True  nodes=84  missing=0  sets=79
     all three summaries BYTE-IDENTICAL to each other (nothing fires)
```

`complete` did not move on either. That is the property the opt-in exists for.

### §32.4 THE PASS — **60 -> 11**, and the A = 0 class EMPTIED

`_c19_pass.sh _snapshot_c18_R2.txt C19R1` — the SAME 131 186-run corpus C18R2's
verdict was measured on, so the only thing that moved is the engine.
(`_c18_pass.sh` was COPIED to `_c19_pass.sh` first; §29.9's rule. Nothing was
edited while running.)

```
COMPLETE=False;NODES=441;MISSING=15;BLOCKING=11;PCS=8366500
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
SUBCONJ_FORECLOSURES=24;SUBCONJ_CONDS=10;SUBCONJ_WIDTH=3;SUBCONJ_PROVISIONAL=False
CONJ_FORECLOSURES=89;CONJ_GROUPS=89;CONJ_PROVISIONAL=False;UNMATCHED_CONJ=0;FORECLOSURES=5278
coverage phase 1 938 s   wall 51 m 02 s   peak RSS 5 427 MB
VERDICT C19-C19R1: OK (line present)      C19-PASS-DONE C19R1
```

|                        | C18R2 (§16e) | C19R1 (§16f, W=3) |
|---|---|---|
| MISSING                |  40 |  **15** |
| BLOCKING               |  36 |  **11** |
| gap-sets               |  60 |  **11** |
| UNMATCHED_CONJ (A = 0) |   8 |   **0** |
| §16b foreclosures      | 5 278 | 5 278 |
| §16e conj foreclosures | 89 / 89 groups | 89 / 89 groups |
| §16f sub-conj classes  |  — | 24 over 10 conditioning sets |
| coverage phase         | 1 253 s | 1 938 s (+55 %) |
| peak RSS               | 5 426 MB | 5 427 MB |

`_c16_gapdelta.py _cov_c18_C18R2.ckpt.jsonl -> _cov_c19_C19R1.ckpt.jsonl`

```
  demand universe: shared 1630, only-before 0, only-after 0
  CLOSED 49   NEWLY GAPPED 0   STILL GAPPED 11
  of the still-gapped: witness leaf UNCHANGED 10, REPLACED 1
```

**Per class:**

| class at C18R2 | sets | after C19R1 | why |
|---|---|---|---|
| §13.3 A = 0 multi-gate (out-of-range dispatch x the mentions-container GATE) | 28 | **0 — CLOSED** | the GATE is foreclosed under the width-2 sub-prefix `(SYM_NOTE_TYPE_PROFILE == 4) :: not_taken AND (== 5) :: not_taken`, A = 78 192 profiles, B = 0. §31.3 measured this coupling over all EIGHT dispatch literals; the minimum-cardinality search finds the two that carry it — indices 4 and 5 are the only `Mention` targets, which is the mechanism `targets.rb:1517-1529` gives. `unmatched_gate_conjunctions` 8 -> 0 with it. |
| open (A > 0, one member never evaluated under the leaf's own other literals) | 31 | **21 CLOSED, 10 left** | 16 of the 31 are the `devise_user_first_1_person_profile_not_found` family, foreclosed under `(notifications_<v>_rows > 1) AND (find_by_1_not_found == True)`, A = 38-59 profiles; the rest are `row_target_author` / `row_target_statusmessage` under two dispatch literals, A = 103 538. The 10 left are the `exists__5` / `exists__8` ALIAS family (§31.5's second, separate cause). |
| Rule T identity compare | 1 | 1 | a CONSTRUCTOR gap (§31.4), fixed in the seeder this round (§32.7) but needing a drive to close |

Nothing was newly gapped and the demand universe did not move — 1 630/1 630
set digests shared, which is the same check §31.6 ran.

### §32.5 The cross-check against `_c18_minimal_cond.json` — and the honest gap

`_c19_crosscheck.py`. The artefact was computed OUTSIDE the engine, over
per-DUMP bitsets and over the leaf's literals ORDER-FREE; the engine counts A
over PROFILES and draws `C` from the literals fixed EARLIER IN THE WALK. So the
agreement to check is on the (member, C) CLASSES, and every disagreement must
be explained by one of those two differences.

```
  engine §16f (C, d) classes                 24   over 10 conditioning sets, W=3
  artefact rows / distinct classes        39 / 27  over 29 sets

  AGREE (same member, SAME minimal C)          16 / 27
      every A pair agrees up to the profile collapse and nothing else, e.g.
        engine 38 profiles   / artefact 108 dumps   (devise ... profile_not_found)
        engine 103 538       / artefact 110 167     (row_target_statusmessage)
  ARTEFACT ONLY                                11   all `exists__5`/`exists__8`
                                                    and the mentions-LENGTH
                                                    members; their minimal C
                                                    needs a literal the walk
                                                    fixes AFTER them
  ENGINE ONLY                                   8   the 4 mentions_container
                                                    GATES (the artefact's script
                                                    searched only the OPEN class,
                                                    so it structurally could not
                                                    find them) + 4 more exists__5
  members reached by BOTH                      14 / 17
  members the artefact found and the engine did not    3
```

So: **the two instruments agree to the unit on every class both can express**,
and the 11 artefact-only classes are exactly the price of the ordering rule,
named rather than absorbed. Widening `C` to the whole cube would reach them and
would cost the well-definedness of the leaf; that is a §16g question, not a
defect in this one.

### §32.6 The gate — **PASS 12, FAIL 0**, and 12 honest NOT-TESTABLEs

`_c19_gate.sh C19` (copy of `_c15_gate.sh`; fixed `assumption_checker.py`,
`ACHK_*` checkpoints + `ACHK_RESULTS_JSONL` + heartbeat, cap 8 G,
`CONCOLIC_SLOTS=1`, detached), on **one representative per (C, d) CLASS** — all
24, not one per member. The derived test is §16e's probe with `C` in place of
`P`: base = the richest snapshot that records `d` together with every literal of
`C`, probe = that snapshot's seeds with every literal whose recorded outcome
differs from `C`'s flipped, at the runtime (ordinal) key (X10).

```
RESULT: 24 distinct tested — PASS 12, FAIL 0, ERROR 0, NOT-TESTABLE 12, NOT-COMPARABLE 0
  38 m 02 s, peak 3 367 MB; 20 distinct probes for 24 classes (the ProbeCache
  dedupes identical seed dicts); ~29 min of it is `corpus_index` over 306 251
  dumps at 165-171 dumps/s, the probes are the remaining ~9 min.
```

**Nothing was refuted.** The 12 PASSes are on probes that REALISED the
conjunction after flipping 1-3 literals from a base that DOES record the
member, and they cover every class that matters:

* all 4 `devise_user_first_1_person_profile_not_found` classes — the 16-leaf
  family, the largest half of the old "31 open";
* 3 of the 4 `..._row_target_mentions_container_not_found` **GATE** classes —
  the inference the 28 A = 0 sets rest on, and the one line of §16e this
  section changes;
* 1 `row_target_author` and all 4 `exists__5` classes.

**The 12 NOT-TESTABLE are the realised-value rule, not a shortfall.** Every one
is `the probe did not REALISE the gate conjunction (1 of 2 literal(s) unmet)`,
and the unmet literal is always a dispatch one — `(SYM_NOTE_TYPE_PROFILE == 3)
:: not_taken` 11 times and `(== 5) :: not_taken` once. That is exactly the
shape the rule exists for: the base was chosen BECAUSE it records the member,
which on this endpoint means the dispatch IS 3 (or 5), and the flip the harness
can infer does not move it off that index. Seeding is not realising, so it
cannot vouch — and a NOT-TESTABLE is not a licence (§24.4). What carries those
12 is the corpus evidence that produced them (A = 78 192-103 538 profiles,
B = 0) plus the 576 CONSTRUCTED out-of-range runs of §31.3, which are the
active-falsification half already spent on this same coupling.

### §32.7 The constructor gap of §31.4, CLOSED

`_c13_construct.parse_cube` reads `(x == x__prior)` as an UNSEED (presence of
the key IS the decision) and `(a == b)` as a var-var PIN. Cube `c000824` has
both, on the SAME variable:

```
  True   (find_by_1_person_id == devise_user_first_1_person_id)
  False  (find_by_1_person_id == find_by_1_person_id__prior)
```

The pair loop pinned BOTH sides correctly — and the UNSEED loop, which runs
LAST, then did `seeds.pop(seedkey(find_by_1_person_id))`. So only the devise
side survived into `_c16_seeds_html_typed.json#324`. That is precisely §31.4's
"a var-var equality literal needs BOTH sides seeded and the seeder writes one";
it was not a `seedkeys` failure and not a domain failure, it was two demands on
one key resolved silently in the wrong direction.

The two are not JOINTLY seedable — one value per key cannot also differ from
itself across calls — so the **PIN now wins and the clash is COUNTED**, never
silent. Six lines in `_c13_construct.py` and the same in `_c14_construct.py`
(which imports the value rules but has its own loop). Verified by re-running
the constructor on that one cube against `_c16_index.pkl`:

```
  var-var PIN beat an UNSEED : 1 over 1 name(s) — the equality is seeded, the
                               self-compare it clashes with is NOT (§32)
        1  SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_id
  the seed now carries BOTH sides:
        ..._devise_user_first_1_person_id = 0
        ..._find_by_1_person_id           = 0
```

which is exactly what C18R's 12 HAND-overlaid seeds did (§31.5) — the
constructor now produces it. The consequence is the one C18R already measured
and is NOT hidden: the equality moves to HONOURED and the run then contradicts
the SPLIT SELF-COMPARE, a different and harder question about per-call seeding.

### §32.8 Ops

Cage 24 G shared with the posts_show confinement gate (never stopped; 9.4-11.3 G
throughout) and a posts_show `_p29_round7` coverage pass. Every launch gated on
`free -g >= 4` AND `(24 G - slice MemoryCurrent) >= cap`, both logged; the pass
additionally gated INSIDE the unit on `pgrep -a python3 | grep -q
"posts_show/coverage_report[.]py"` being empty — **the gate fired and held C19R1
for 19 minutes** behind `_p29_cov_P29A2`, which is the rule working.

```
  CAGED (systemd-run --user --scope --slice=concolic-cov.slice)
    _c19_pass.sh C19R1        8G  51 m 02 s  peak 5 427 MB   131 186 runs
    _c14_construct.py probe   3G   4 s                       1 cube (§32.7)
    _16f_identity.sh people_stream 4G / comments_index 7G    3 modes each
    _c19_gate.sh C19          8G  38 m 03 s  peak 3 367 MB   24 classes
  UNCAGED, small and short-lived (read-only analysis, RSS well under 1 GB):
    _c19_crosscheck.py, the offline minimal-width measurement over
    `_c16_index.pkl`, `_c16_gapdelta.py`
```

The gate ran only while no notifications drive or pass was running (the C19R1
pass had written its verdict line 49 s earlier). Measured rate for the record:
`corpus_index` 165-171 dumps/s over 306 251 dumps, and 20 probes in ~9 min at
`CONCOLIC_SLOTS=1` alongside the posts_show gate.

Two false starts, both stopped inside the first minutes of step 6 and both
relaunched from scratch (no checkpoint reused, `_c19_pass.sh` never edited
while running): the first because the blocking side recorded its (C, d)
classes under §16e's `not both` guard, which would have hidden exactly the
classes that CLOSE a set (a closed set never reaches the emission side); the
second because the per-set §16f cut record was not deduplicated and the
checkpoint was writing ~1 MB per demand set. Both are engine fixes, both are
covered by the test file, and the checkpoint is now ~30 bytes/set.

No `targets.rb` edit, no shared-boundary edit, no extraction, no git, nothing
under `posts_show/` or `comments_index/`. `src/` WAS edited — that is the
round. The PRE-EXISTING project files modified are
`notifications_index/coverage_report.py` (env knob; backup
`_bak_coverage_report_pre_c19_20260913.py`), `_c13_construct.py` /
`_c14_construct.py` (backups `_bak_c13_construct_pre_c19_20260913.py`,
`_bak_c14_construct_pre_c19_20260913.py`) and this document (backup
`_bak_COMPLETION_CAMPAIGN_pre_c19_20260913.md`); everything else is a new
`_c19*` artefact.

### §32.9 Artefacts

```
src/concolic_engine/coverage.py        §16f: minimal_subconjunction,
                                       _SubconjBudget, _MISS, step 5c'',
                                       the walk on both sides, the `subconj`
                                       checkpoint record,
                                       subconjunction_foreclosures_to_dict
src/.../assumption/assumption_checker.py  _test_subconjunction_foreclosure
src/test_subconjunction_foreclosure.py    18 tests (suite 296 -> 314 green)
reports/diaspora/docs/DISCIPLINE.md    §16f decision record
reports/diaspora/docs/RUNBOOK.md       §4 FORECLOSURE_SUBCONJUNCTIONS
_c19_pass.sh (copy of _c18_pass.sh)    _c19_cov_C19R1.log / .time / _c19.log
_cov_C19_C19R1.json / _cov_c19_C19R1.ckpt.jsonl
_c19_crosscheck.py                     16/27 agree, 11 artefact-only, 8 new
_c19_gate_classes.py / _c19_gate_classes.json   24 (C, d) classes
_c19_gate.sh (copy of _c15_gate.sh)    _c19_gate_C19.json / .log / .time
                                       _c19_achk_*.jsonl (checkpoints + rows)
                                       PASS 12, FAIL 0, NOT-TESTABLE 12
_bak_coverage_report_pre_c19_20260913.py / _bak_c13_construct_pre_c19_20260913.py
_bak_c14_construct_pre_c19_20260913.py / _bak_COMPLETION_CAMPAIGN_pre_c19_20260913.md
scratchpad/run_report16f.py, _16f_identity.sh   the closed-endpoint harness
```

### §32.10 WHERE THE ENDPOINT STANDS AFTER C19

```
  C12 (cap 4)  298 sets with a gap
  C13 R1       227   (-71,  1 554 runs)
  C13 R2       227   ( -0,    406 runs)     rate rule fired
  M-SNAP       184   (-43,      0 runs)     a declaration (§26)
  C14 R1       105   (-79, 10 396 runs)
  C14 R2       103   ( -2,  2 555 runs)     rate rule fired
  C15 R2        84   (-19,      0 runs)     §16e in src/ (§28)
  C16 R1        84   ( -0,  1 192 runs)
  C17 R2        84   ( -0,    109 runs)
  C18 R1        60   (-24,      0 runs)     TWO declarations (§31.2, §31.3)
  C18 R2        60   ( -0,    364 runs)
  C19 R1        11   (-49,      0 runs)     §16f in src/ (this section)

  CURRENT   COMPLETE=False; NODES=441; MISSING=15; BLOCKING=11;
            DEMAND_SETS=1630; tree_missing 0; UNMATCHED_CONJ=0
            (_cov_C19_C19R1.json)

  11 gap-sets = 10  the `exists__5` / `exists__8` ALIAS family (§31.5's second
                    cause): `ActiveRecord::FinderMethods#exists?` call ORDINALS
                    from a `diaspora://` link, which the endpoint's
                    AliasAssumptions do not cover, so "the same decision" is
                    several canonical names. A P0/P1 alias question, and the
                    one class §16f reaches only partially — 11 of its
                    conditioning sets need a literal the walk fixes after the
                    member (§32.5).
              +  1  the identity compare: a CONSTRUCTOR gap, the seeder fixed
                    this round (§32.7); it needs ONE drive round, and its
                    split-self-compare coupling is the next thing to measure.
```

The gate found **no refutation**: 24 classes tested, PASS 12, FAIL 0,
NOT-TESTABLE 12 (all the realised-value rule), NOT-COMPARABLE 0.

**Rule T is still empty on this endpoint.** Nothing in this residue asks for a
change to the shared target boundary. The two remaining questions are an ALIAS
declaration and a DRIVE — neither is an inference question, which is what the
whole of §28-§32 was.
