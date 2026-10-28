# notifications_index — TRACE PROJECTION of the 154 decisions onto the statement shapes (2026-09-09, late)

**Status: MEASUREMENT ONLY.** Nothing was driven, no JRuby slot was used,
`src/`, `coverage_assumptions.py`, the app, every dump and every reference
policy are untouched (reference policies were not read). Every number below
is measured on the 68 231-dump corpus in this directory (`find -maxdepth 1
-name 'dump_*.json' | wc -l` = 68 231, 0 unparseable), THROUGH THE ENGINE'S
LOAD PATH (`canonicalize_ordinals -> fix_len_names -> Run.from_dict ->
apply_len_bounds`, `coverage_report.py`), with statement identity taken from
`concolic_engine.assumptions.statement_key` (the same function the alias and
the gate use). Scripts and intermediate artefacts are listed in §9; the
per-decision evidence is in `_TRACE_PROJECTION_20260909_evidence.json` and in
the appendix.

## 0. The answer

**Of the 154 hash-collapsed decisions, 32 are trace-irrelevant, 84 are
trace-relevant, 38 are undecidable for want of runs. 122 survive the
projection.** Removing the 32 (105 of the 427 raw expressions) cuts the exact
satisfiable-assignment demand from **1 212 640 to 344 464** (remaining
unobserved: 1 184 139 -> 336 809) and the blocking cliques from 2 042 to
~800 — a 72% reduction, and **not a closure**. Even the upper bound that
discards every undecidable decision as well (only the 84 provably relevant
ones kept) leaves **49 440** satisfiable assignments (42 855 unobserved) over
589 cliques, 39 of which no run has ever evaluated whole. At the measured
random rate (~1 new assignment per run, falling) none of these is driveable.

So this is the "~100 survive" outcome, not the "~20 survive" one: the
exponential is carried by decisions that DO change the statement set — the
paginated list's cardinality, the actors' cardinality, the 8-way STI
dispatch, the `_not_found` gates on the principal and on every target chain —
and the projection cannot remove them. The direction removes most of the
demand and does not reach a driveable number. That is the plain result.

## 1. Headline figures, re-verified

| figure | brief | measured tonight (load path) | note |
|---|---|---|---|
| dumps | 68 231 | **68 231** (0 bad) | `find`, not `ls` |
| distinct PC expressions (`tree_nodes`) | 435 | **435** | summary and scan agree |
| tracked expressions | 427 | **427** | 435 − 8 `UntrackedPathAssumption` |
| hash-collapsed decisions | 154 | **154** | `_[0-9a-f]{8}` removed; 273 of 427 raw exprs (64%) are variant copies |
| blocking cliques, latest pass | 2 042 | **2 042** | model rebuilt from `coverage_summary.json` (22:30 pass): 2 050 maximal cliques = 2 042 blocking + 8 closed, exact match |
| satisfiable assignments, exact | 1 183 264 (1 826-clique graph) | **1 212 640** on the latest 2 050-clique graph | 28 501 covered, **1 184 139** remaining, **548** cliques never co-evaluated by any run |
| statement TEXTS (binds kept) | 167 | **213** | see below |
| statement SHAPES (binds wildcarded) | 38 | **50** (48 with `IN (…)` arity collapsed) | see below |
| call sites (result names) | 60 | **80** (32 with the ordinal stripped) | see below |
| demand per shape | ~31 000 | 1 212 640 / 50 = **24 253** (/38 = 31 911, the brief's arithmetic) | |
| path conditions | 4 018 735 | 4 018 735 | summary |
| `dump_errors` | 3 597 + 162 | **3 597** `ActionView::Template::Error` + **162** `I18n::InvalidLocale` | 5.5% of runs |

The statement census does not reproduce the brief's 38 / 167 / 60. The
counts are IDENTICAL over the healthy-only subset (64 472 runs), over the
pre-v2 51 362-run subset and over the whole corpus (50 / 213 / 80 in all
three), so the difference is definitional, not corpus growth: mine is every
`symbolic_call` event whose note `is_statement_note`, keyed by
`statement_key(note, keep_binds=False)` after canonicalisation, with
`IN ($$(?), $$(?), $$(?))` and the four-bind form counted as two shapes. I
could not find the brief's counting rule on disk and did not guess at one;
every conclusion below is stated at both the 50-shape and the 48-shape level
and does not change between them.

The two family measurements the brief rests on reproduce exactly through the
load path: the unread root family `(len(Relation_records_notifications) > 1)`
has 10 716 many-arm / 57 353 not-taken runs, **0** shapes and **0** texts
unique to either arm and **0** notes binding its rows (K1's numbers,
verbatim); the paginated list `(len(to_ary_notifications_<v>) > 1)` has
bulk `IN (…)` shapes only on its many arm (and single-key `= $$(?)` shapes
only on its few arm) in every variant; the actors' many arm carries the
four-bind `people`/`profiles IN` shapes; the mentions' many arm carries
`people`/`profiles IN` (visible in the matched-context test, §4, not in the
marginal one because the same shapes are issued by the actors elsewhere).

One state fact for the owner: `coverage_assumptions.py` (22:01) now declares
K1, but the standing `coverage_summary.json` (22:30 pass, started earlier)
does NOT carry it — its 8 untracked expressions are P2's three, the badge
count and the four formatter guids. The baseline above is the summary's
graph, K1 still tracked, so that every number here is against the artefact
on disk.

## 2. Method

**Universe.** The 427 tracked expressions of the latest summary, grouped into
154 decisions by removing the 8-hex statement hash from every canonical name
(the four list variants `c7e6a7ca / cf379872 / 3aa8587a / 10254800`, the
three mentions chains, the six photos reads, the two aspect_memberships
reads collapse; nothing else does). Every verdict is given at both levels.

**Trace-effect (task item 1).** For each decision, the 68 231 runs are
partitioned by outcome: **T** = runs that evaluated the decision (any member)
and recorded only `True`, **F** = only `False`, **both** = recorded both ways
in one run (a loop; excluded from the arms, counted). The trace of a run is
its SET of statement shapes. Report: |T|, |F|, |both|, the shapes present on
T and absent from F, the shapes present on F and absent from T (each with the
number of T- or F-runs carrying it), the same at the text level (binds kept),
and — the W-E bar (task item 2) — every statement whose binds reference the
decision's owner rows (`<X>_row…` for a length `len(X)`, `<chain>_…` for an
attribute decision on `<chain>`).

**Floor (task item 3): 50 single-outcome runs per arm.** A decision with an
arm below 50 is UNDECIDABLE whatever the arms show; it is never counted as
irrelevant. Sensitivity at 20 and 200 is reported (§3.2). 50 was chosen
before the verdicts were read and not tuned afterwards: it is the smallest
arm at which the absence of a 2%-prevalence shape is unlikely by chance
(0.98^50 = 36%, so 50 is still permissive — hence the guard below and the
200-run column).

**Verdicts.**
- **IRRELEVANT**: both arms >= 50, symmetric difference of shapes EMPTY, and
  — for a `(len(X) > 1)` decision — no statement binds `X_row…`.
- **RELEVANT**: both arms >= 50 and some shape is unique to one arm; or a
  `(len(X) > 1)` whose rows key a later read (the W-E bar; 2 decisions rest
  on the bar alone: `aspect_memberships > 1` and `mentions > 1`).
- **UNDECIDABLE**: an arm below 50. All 38 happen to show a shape unique to
  their LARGE arm; that is what a thin arm looks like and is not evidence
  either way.

**Two guards against confounding, added after the first table was read.**
(a) *Chance-absence guard*: a shape unique to arm A is only accepted as
evidence when its absence from arm B is unlikely under independence — expected
count |B| x (prevalence on A) >= 5. This never turns an IRRELEVANT into a
RELEVANT; it marks 13 of the 84 RELEVANT decisions as resting on a shape whose
absence from the small arm is explainable by chance (§3.1, "chance-absence
only"). The classic case is `SELECT COUNT(*) FROM "reports" WHERE reviewed =
false` — issued only in the mobile scenarios (1 521 runs) — which appears
"unique to the large arm" of any decision whose small arm never sampled a
mobile run; 43 of the 68 raw-level RELEVANT verdicts inside IRRELEVANT groups
are that artefact, which is why the raw table is reported but the collapsed
table is the primary one. (b) *Matched-context differential* (§4): the
corpus analogue of the gate's single-flip probe.

**Pricing (task item 4).** The proposal's exact enumerator, ported onto this
scan: dependence graph = complete minus the summary's 87 855 declared
independences, minus the 8 untracked, minus the candidate set; maximal
cliques by Bron–Kerbosch with pivot (as `coverage.py`); per clique the EXACT
satisfiable outcome count (Z3 per variable-connected component under the
engine's merged declarations and `apply_len_bounds` bounds, blocking-clause
loop, no cap, product across components); covered = `coverage.py` step-6
semantics over all 68 231 run families. The baseline reproduces the summary's
2 042 blocking cliques exactly (2 050 − 8 closed).

## 3. Results

### 3.1 The 154 decisions (floor 50, shapes = `statement_key` with binds wildcarded)

| verdict | decisions | raw exprs | of which |
|---|---|---|---|
| **IRRELEVANT** | **32** | 105 | 18 also have an empty TEXT-level difference (bind identity, DISCIPLINE §14) — 59 raw exprs; 14 differ at text level (see §5) |
| **RELEVANT** | **84** | 220 | 71 robust; 13 rest only on a chance-explainable unique shape; 2 by the W-E bar alone |
| **UNDECIDABLE** | **38** | 102 | 7 have an arm never observed at all (0 runs); smallest arms 0,0,0,0,0,0,0,1,4,5,6,6,7,7,8,11,… |
| **survive** (relevant + undecidable) | **122** | 322 | |

The 32 trace-irrelevant decisions (evidence in the appendix, rows marked
IRRELEVANT):

- root-family cardinalities: unread notifications `== 0` and `> 1`
  (5 557 / 62 512 and 10 716 / 57 353 runs), aspects `== 0` (1 553 / 32 346),
  services `== 0` (1 472 / 32 427), mentions `== 0` (1 634 / 29 719; but 12
  texts unique to the few arm — §5);
- the photos family: `!= 0`, `== 0`, `> 1` (2 300–27 514 per arm, 0 rows
  keyed), the target-photos `!= 0`, and the photo-row text decisions
  `_text_nil / _text_has_dlink / _text_has_mention / _text_dlink_is_post`;
- profile display attributes that select a string, not a statement:
  `first_name / last_name / disp_has_dlink` on the mentions-container
  author, the commentable author, the actor rows, the contact person, plus
  the contact person's `birthday_year` and `public_details`;
- two identity compares on the contact finder (`find_by_1_person_id ==
  devise_user…person_id`, the self-compare), the moderator-role `exists__2`,
  the mentions-container `_text_has_dlink / _text_has_mention`, the mention
  person's `diaspora_handle` compare and the mention person `_not_found`
  (326 / 29 393; 18 texts unique to the found arm — §5).

What survives, and why: the 8 `SYM_NOTE_TYPE_PROFILE == k` and 2
`SYM_POST_STI` compares (each selects which target chain is read: `posts`
vs `comments` vs `mentions` vs `photos` shapes), `SYM_PARAM_show`, the
paginated list `== 0` / `> 1` (27 and 4+4 unique shapes), the actors `> 1`
/ `> 3` (four-bind `IN`), mentions `> 1`, aspect_memberships `== 0` / `> 1`,
every `_not_found` gate on the principal and on the target chains (each
removes the whole chain's reads: 10–47 shapes unique to the found arm),
`_persisted`, `_guid == ''`, `_target_is_photo`, `_text_nil` on the target
and container, the role `exists__1/3/4/5/6` probes, the badge/size counts.
Every one of these is a decision that adds or removes a statement shape.

### 3.2 Sensitivity

| floor per arm | RELEVANT | IRRELEVANT | UNDECIDABLE |
|---|---|---|---|
| 20 | 98 | 32 | 24 |
| **50 (reported)** | **84** | **32** | **38** |
| 200 | 59 | 31 | 64 |
| 50, shapes with `IN` arity collapsed (48 shapes) | 81 | 35 | 38 |
| 50, healthy runs only (errors excluded) | 78 | 34 | 42 (n/a) |
| 50, after the chance-absence guard | 71 (+13 chance-only) | 32 | 38 |

The irrelevant count is 31–35 under every reading; the floor only moves
decisions between RELEVANT and UNDECIDABLE, both of which survive. The
raw-427 table: 207 / 68 / 152 at floor 50 (186 / 21 chance-only / 68 / 152
guarded); it is inflated on the RELEVANT side by the mobile-only shapes
described in §2 and is reported in the evidence JSON, not used for the
headline.

### 3.3 Pricing — exact demand after removal

| removal set | raw exprs removed | active | maximal cliques | satisfiable (exact) | covered | **remaining** | closed | never co-evaluated |
|---|---|---|---|---|---|---|---|---|
| none (latest summary graph) | 0 | 427 | 2 050 | 1 212 640 | 28 501 | **1 184 139** | 8 | 548 |
| **A. the 32 trace-irrelevant decisions** | 105 | 322 | 810 | **344 464** | 7 655 | **336 809** | 18 | 74 |
| B. only raw exprs individually irrelevant | 68 | 359 | 1 505 | 524 512 | 13 750 | 510 762 | 13 | 272 |
| C. the 35 irrelevant at the `IN`-collapsed level | 117 | 310 | 794 | 171 912 | 4 580 | 167 332 | 52 | 74 |
| E. A + the 13 chance-absence-only decisions | 139 | 288 | 729 | 340 512 | 6 999 | 333 513 | 16 | 67 |
| S. strict: the 18 with empty TEXT-level difference too | 59 | 368 | 1 055 | 432 704 | 9 979 | 422 725 | 39 | 134 |
| D. UPPER BOUND: remove irrelevant AND undecidable (84 relevant kept) | 207 | 220 | 589 | 49 440 | 6 585 | 42 855 | 19 | 39 |

After A, 91.6% of the remaining demand sits in the 72 cliques of width >= 10;
every one of the 72 contains the paginated list `> 1`, the actors `> 1`, the
principal's `person_not_found` and `person_profile_not_found`, and
`row_target_not_found`; 28 contain the 8-way dispatch. The widest surviving
clique (w = 20, 32 768 assignments) is {both aspect_memberships `> 1`, actors
`> 1`, list `> 1`, the 8 dispatch compares, 8 `_not_found` gates}. None of
these 20 is trace-irrelevant, and none is undecidable-for-want-of-runs in a
way more runs would fix cheaply: the demand is 8 x 2^12 because the
checker models the dispatch as eight dependent Bools and the not-founds as
pairwise dependent (W-F), exactly as the proposal's §2 said.

**Reachability.** 336 809 unobserved assignments at the measured v2 random
rate (17 327 new in 16 869 runs, ~1.03/run and falling) is > 3 x 10^5 runs
before diminishing returns, i.e. not reachable; 74 of the 810 cliques have
never been co-evaluated by any run and cannot be reached by seeding at all.
The upper bound D, 42 855, is ~4 x 10^4 runs at the initial rate — and D is
not a defensible set, it is what you would get by declaring 38 decisions
irrelevant on no evidence. **The endpoint does not become reachable under
this criterion.**

## 4. Matched-context differential (the corpus flip test)

The marginal split can be confounded by other decisions that co-vary with
the one under test (the mobile-only `reports` COUNT is the worked example in
§2). The stronger test groups runs by their outcome family over EVERY OTHER
tracked expression and compares the T- and F-arm statement sets inside each
group, so no other tracked decision can explain a difference.

- Exact contexts (all 427 other exprs identical): 18 of the 32 IRRELEVANT
  decisions have matched contexts (5 561 contexts, 674–7 244 T-runs each);
  **0** of them show a shape difference and **0** a text difference. 43 of
  the 84 RELEVANT decisions have contexts; 8 show shape differences there
  (the paginated list `> 1`: 1 861 of 1 861 contexts; mentions `> 1`: 629 /
  629 — the `people`/`profiles IN` shapes appear only on the many arm inside
  matched contexts; `target_is_photo`; dispatch 4–7; aspect_memberships
  `== 0`). The remaining 14 IRRELEVANT decisions have no exact context
  (the photos family and the mentions family: their arms live in runs that
  differ elsewhere).
- Variant-merged contexts (other decisions keyed at the hash-collapsed
  level) turned out to be invalid as a differential: merging the list
  variants puts html_plain and html_typed runs in one context and the
  typed COUNT shapes show up as "differences". Not used.
- Scenario-stratified, variant-merged contexts (other decisions keyed at the
  hash-collapsed level, the run's scenario part of the key): the same 18
  IRRELEVANT decisions have contexts (5 605), again **0** shape and **0**
  text differences; 47 RELEVANT decisions have contexts and 12 show
  differences; 1 of 22 UNDECIDABLE does. No IRRELEVANT verdict is
  contradicted by any matched context under either keying. The 14
  IRRELEVANT decisions without a matched context (the photos family, the
  mentions family, the container-text decisions) rest on the marginal split
  alone.

## 5. Where the criterion is weakest — bind identity

The task defines the deliverable as a set of statement SHAPES (binds
wildcarded). DISCIPLINE §14 and the alias's own key say bind identity is
part of the statement. 14 of the 32 trace-irrelevant decisions have an
empty shape difference but a NON-empty text difference; for most of them the
matched-context test (§4) shows the text difference is confounding
(aspects `== 0`: 3 texts, services `== 0`: 4, `exists__2`: 5, actors
`last_name`: 5, the mention `diaspora_handle` compare: 8 — all 0/0 inside
matched contexts). Two are not confounding, they are the mechanism:

- `(len(mentions_<chain>) == 0)`: the 12 texts unique to the few arm are
  `people.id = $$(mentions_<chain>_row_person_id)` and the matching
  `profiles` read — the per-mention person reads, which an empty mentions
  list removes. The SHAPE `people.id = $$(?)` survives because the actors
  and authors issue it too;
- `(mentions_<chain>_row_person_not_found == True)`: 18 texts unique to the
  found arm, same reads.

Under the shape criterion both are trace-irrelevant (variant A); under bind
identity they are not (variant S, 422 725 remaining). The owner should know
that variant A's number rests on the shape reading in exactly these two
places, and that the P2 argument ("no note binds its rows") would NOT admit
`mentions == 0` — its rows are bound.

## 6. Error-path caveat

- Corpus error share: 3 759 of 68 231 runs (5.5%): 3 597
  `ActionView::Template::Error`, 162 `I18n::InvalidLocale`. Attribution by
  dump group: 2 988 + 117 in the base/D-round dumps, 577 + 44 in the v2
  diverse (`_DV`) dumps, 32 + 1 in the pilot. The growth is not mainly the
  diverse seeds.
- **None of the 32 trace-irrelevant decisions is concentrated on error
  paths.** The highest error share on any of their arms is 9.5%
  (`mentions_row_person_not_found` True arm, 31 of 326); the rest are
  0–6.5%, i.e. the corpus rate. All 32 verdicts hold when the error runs
  are removed entirely (`verdict_healthy_only` = IRRELEVANT for all 32).
- **0** statement shapes and **0** tracked expressions exist only on error
  runs; the shape set of the healthy subset is the full 50.
- The error concentration is on the CLOSING arms that survive: 12 decisions
  have an arm that is >= 50% error runs, all `_not_found == True` gates or
  `stale_language` (`person_profile_not_found` 196/196,
  `target_author_profile_not_found` 284/284, `commentable_not_found` 60/60,
  `stale_language` 162/162 = the I18n runs, `person_not_found` 2 366/3 290).
  These are RELEVANT or UNDECIDABLE and are untouched by the projection.
  Their demand is what the proposal's D4 (closing-arm foreclosure) prices.

So the finding is of the healthy-path kind: the 32 are decisions that select
a string or a count on a rendered page, not decisions that exist only when
the render fails.

## 7. What adopting this criterion would change — for the owner

If trace-irrelevance becomes an untracking tier, `complete: true` stops
asserting "every satisfiable combination of recorded decisions was observed
in one run" and starts asserting "every satisfiable combination of the
decisions that can observably change the statement-shape set was observed".
Three consequences the owner should weigh, none of which this measurement
can settle:

1. The projection is MARGINAL and OBSERVED. A shape that requires two
   decisions jointly (d ∧ e) and was never issued in the corpus is invisible
   to it by construction — which is precisely the hidden combination the
   2026-08-18 combination semantics were adopted to demand. P2/K1 make the
   same wager but pair it with an app-code argument and a gate flip test per
   family; the bulk criterion has only the corpus.
2. It is a different assertion from the one the CLOSED endpoints were closed
   under. comments_index (84 nodes), conversations_index (105) and
   people_show (97) hold `complete: true` under full combination semantics;
   adopting the weaker assertion project-wide re-grades them (their policies
   would not change, the strength of the claim behind them would). Adopting
   it for notifications_index only makes the four endpoints' `complete`
   mean two different things.
3. The shape-vs-bind-identity reading (§5) must be chosen explicitly; the
   engine's own alias key says bind identity, the deliverable-as-shape-set
   argument says shape. The two readings differ by 86 000 assignments here
   and by two decisions whose mechanism is real.

It is his call. The measurement says: even with the most generous reading
(A, or E), the endpoint stays ~3 x 10^5 assignments from `missing == 0`,
so the decision is not forced by this endpoint's economics — the criterion
does not buy closure.

## 8. Not done / caveats

- No assumption was installed or proposed as installable; nothing here is a
  declaration. The removal sets are what-if edits to a copy of the graph.
- Statement census reconciliation (38/167/60 vs 50/213/80) is open; I could
  not locate the brief's counting rule and did not invent one.
- The "both" column is small (0 for all but three decisions) so excluding
  both-outcome runs from the arms costs nothing here.
- Owner-row keying was computed by variable-name prefix on canonical names
  (`<X>_row`, `<chain>_`) — the same prefix rule the audits use, with the
  same known caveat (a nested list's `_row_actors_row` extends `_row`; it is
  attributed to the outer list too, which only makes the W-E bar stricter).

## 9. Artefacts

Batch dir: this report; `_TRACE_PROJECTION_20260909_evidence.json` (all 154
decisions with arms, shapes/texts unique per arm, owner-row binds, scenario
and error split, matched-context results; all 427 raw rows; every pricing
variant with per-width tables).

Scratchpad (`/tmp/claude-1000/-home-dev-project/94ab9891-…/scratchpad/tp/`):
`scan.py` (one load-path pass, 66 s, 4 workers) -> `full.json.gz` (per run:
outcome mask per expr, statement result-name + text, scenario, error);
`graph_new.json` (latest summary's declarations, cliques, universe);
`effect2.py` -> `effect2_f{20,50,200}.json`; `matched.py` / `matched3.py`
-> `matched.json` / `matched3.json`; `price.py` / `price2.py` ->
`price.json`; logs alongside.

## Appendix — the 154 decisions (floor 50, shapes = engine `statement_key`, binds wildcarded)

Columns: runs on each single-outcome arm and seen-both-ways; shapes unique to each arm with the number of
arm runs carrying them; count of TEXTS (binds kept) unique to each arm; number of distinct statements whose
binds reference the decision's owner rows; error-run share of each arm; matched contexts (exact / scenario-
stratified) with how many showed a shape/text difference. Prefixes: `TOARY` = the paginated notifications list
(4 variants), `REL.` = Relation reads, `CP.` = CollectionProxy reads, `FM.` = finders, `CORE.` = Person.find_by,
`LEN.` = list length, `SV(` = StringVal(.

| # | verdict | members | runs T | runs F | both | shapes only on T (runs) | shapes only on F (runs) | texts only T/F | rows keyed | err% T/F | matched ctx exact (sh/tx diff) | matched ctx scen-strat (sh/tx) | decision |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | RELEVANT | 2 | 55 | 2269 | 80 | — | SELECT "aspects".* FROM "aspects" WHERE "aspects"."id" = $… x2269 | 0/2 | 2 | 0/4 | 17 (17/17) | 17 (17/17) | `(LEN.CP.aspect_memberships_rows == 0)` |
| 1 | RELEVANT (W-E bar) | 2 | 145 | 2162 | 97 | — | — | 0/0 | 2 | 3/4 | 15 (0/0) | 15 (0/0) | `(LEN.CP.aspect_memberships_rows > 1)` |
| 2 | IRRELEVANT | 1 | 1553 | 32346 | 0 | — | — | 0/3 | 0 | 0/1 | 430 (0/0) | 430 (0/0) | `(LEN.CP.aspects_rows == 0)` |
| 3 | IRRELEVANT | 6 | 27514 | 2300 | 0 | — | — | 16/0 | 0 | 2/1 | 0 (0/0) | 0 (0/0) | `(LEN.CP.photos_rows != 0)` |
| 4 | IRRELEVANT | 6 | 2300 | 27514 | 0 | — | — | 0/16 | 0 | 1/2 | 0 (0/0) | 0 (0/0) | `(LEN.CP.photos_rows == 0)` |
| 5 | IRRELEVANT | 6 | 2874 | 26940 | 0 | — | — | 0/0 | 0 | 2/2 | 446 (0/0) | 447 (0/0) | `(LEN.CP.photos_rows > 1)` |
| 6 | IRRELEVANT | 1 | 1472 | 32427 | 0 | — | — | 0/4 | 0 | 0/1 | 370 (0/0) | 370 (0/0) | `(LEN.CP.services_rows == 0)` |
| 7 | RELEVANT (chance-absence only) | 1 | 133 | 13068 | 0 | — | SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('?'… x442; SELECT "photos".* FROM "photos" WHERE "photos"."id" = $$(?… x379 (+2 more) | 0/80 | 0 | 0/3 | 0 (0/0) | 0 (0/0) | `(LEN.CP.tags_rows == 0)` |
| 8 | RELEVANT (chance-absence only) | 1 | 13068 | 133 | 0 | SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('?'… x442; SELECT "photos".* FROM "photos" WHERE "photos"."id" = $$(?… x379 (+2 more) | — | 80/0 | 0 | 3/0 | 0 (0/0) | 0 (0/0) | `(LEN.FM.devise_user_first_1_followed_tags_row_rows > 0)` |
| 9 | IRRELEVANT | 3 | 1634 | 29719 | 0 | — | — | 0/12 | 12 | 1/2 | 0 (0/0) | 0 (0/0) | `(LEN.REL.mentions_rows == 0)` |
| 10 | RELEVANT (W-E bar) | 3 | 3385 | 27968 | 0 | — | — | 6/6 | 12 | 1/2 | 629 (629/629) | 630 (630/630) | `(LEN.REL.mentions_rows > 1)` |
| 11 | IRRELEVANT | 1 | 5557 | 62512 | 0 | — | — | 0/0 | 0 | 4/5 | 1050 (0/0) | 1062 (0/0) | `(LEN.REL.notifications_rows == 0)` |
| 12 | IRRELEVANT | 1 | 10716 | 57353 | 0 | — | — | 0/0 | 0 | 4/6 | 1592 (0/0) | 1621 (0/0) | `(LEN.REL.notifications_rows > 1)` |
| 13 | RELEVANT | 4 | 4518 | 58437 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."id" IN ($$… x8648; SELECT "profiles".* FROM "profiles" WHERE "profiles"."pers… x8648 | 0/25 | 0 | 4/6 | 0 (0/0) | 0 (0/0) | `(LEN.TOARY_row_actors_row_rows == 0)` |
| 14 | RELEVANT | 4 | 8648 | 54307 | 0 | SELECT "people".* FROM "people" WHERE "people"."id" IN ($$… x8648; SELECT "profiles".* FROM "profiles" WHERE "profiles"."pers… x8648 | — | 8/17 | 0 | 4/6 | 0 (0/0) | 0 (0/0) | `(LEN.TOARY_row_actors_row_rows > 1)` |
| 15 | RELEVANT | 4 | 8648 | 54307 | 0 | SELECT "people".* FROM "people" WHERE "people"."id" IN ($$… x8648; SELECT "profiles".* FROM "profiles" WHERE "profiles"."pers… x8648 | — | 8/17 | 0 | 4/6 | 0 (0/0) | 0 (0/0) | `(LEN.TOARY_row_actors_row_rows > 3)` |
| 16 | RELEVANT | 4 | 1531 | 671 | 0 | SELECT "people".* FROM "people" WHERE "people"."id" = $$(?… x1531 | — | 8/0 | 0 | 3/1 | 0 (0/0) | 0 (0/0) | `(LEN.TOARY_row_target_mentions_container_commentable_photos_row_rows != 0)` |
| 17 | RELEVANT | 4 | 1140 | 356 | 0 | SELECT "people".* FROM "people" WHERE "people"."id" = $$(?… x1140 | — | 8/0 | 0 | 1/1 | 0 (0/0) | 0 (0/0) | `(LEN.TOARY_row_target_mentions_container_photos_row_rows != 0)` |
| 18 | IRRELEVANT | 4 | 1803 | 398 | 0 | — | — | 0/0 | 0 | 1/0 | 0 (0/0) | 0 (0/0) | `(LEN.TOARY_row_target_photos_row_rows != 0)` |
| 19 | RELEVANT | 4 | 5114 | 62955 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."id" = $$(?… x47241; SELECT "profiles".* FROM "profiles" WHERE "profiles"."pers… x46218 (+27 more) | 0/192 | 156 | 3/5 | 0 (0/0) | 0 (0/0) | `(LEN.TOARY_rows == 0)` |
| 20 | RELEVANT | 4 | 17670 | 50399 | 0 | SELECT "notification_actors".* FROM "notification_actors" … x17670; SELECT "posts".* FROM "posts" WHERE "posts"."id" IN ($$(?)… x8370 (+2 more) | SELECT "notification_actors".* FROM "notification_actors" … x45285; SELECT "posts".* FROM "posts" WHERE "posts"."id" = $$(?) x20089 (+2 more) | 28/28 | 156 | 5/5 | 1861 (1861/1861) | 1890 (1890/1890) | `(LEN.TOARY_rows > 1)` |
| 21 | RELEVANT | 1 | 23054 | 44021 | 0 | — | SELECT "posts".* FROM "posts" WHERE "posts"."id" = $$(?) L… x22138; SELECT "mentions".* FROM "mentions" WHERE "mentions"."id" … x19071 (+11 more) | 0/122 | 0 | 5/6 | 21 (0/0) | 21 (0/0) | `(SYM_NOTE_TYPE_PROFILE == 0)` |
| 22 | RELEVANT | 1 | 2364 | 64711 | 0 | — | SELECT "posts".* FROM "posts" WHERE "posts"."id" = $$(?) L… x22138; SELECT "mentions".* FROM "mentions" WHERE "mentions"."id" … x19071 (+12 more) | 0/124 | 0 | 4/5 | 19 (0/0) | 19 (0/0) | `(SYM_NOTE_TYPE_PROFILE == 1)` |
| 23 | RELEVANT | 1 | 5293 | 61782 | 0 | — | SELECT "posts".* FROM "posts" WHERE "posts"."id" = $$(?) L… x22138; SELECT "mentions".* FROM "mentions" WHERE "mentions"."id" … x19071 (+9 more) | 0/104 | 0 | 6/5 | 0 (0/0) | 0 (0/0) | `(SYM_NOTE_TYPE_PROFILE == 2)` |
| 24 | RELEVANT | 1 | 2637 | 64438 | 0 | — | SELECT "posts".* FROM "posts" WHERE "posts"."id" = $$(?) L… x22138; SELECT "mentions".* FROM "mentions" WHERE "mentions"."id" … x19071 (+9 more) | 0/104 | 0 | 4/5 | 0 (0/0) | 0 (0/0) | `(SYM_NOTE_TYPE_PROFILE == 3)` |
| 25 | RELEVANT | 1 | 12028 | 55047 | 0 | — | SELECT "posts".* FROM "posts" WHERE "posts"."id" = $$(?) x20089; SELECT "comments".* FROM "comments" WHERE "comments"."id" … x12046 (+10 more) | 32/118 | 0 | 5/5 | 4 (3/3) | 4 (3/3) | `(SYM_NOTE_TYPE_PROFILE == 4)` |
| 26 | RELEVANT | 1 | 14233 | 52842 | 0 | SELECT "comments".* FROM "comments" WHERE "comments"."id" … x12046 | SELECT "posts".* FROM "posts" WHERE "posts"."id" = $$(?) x20089; SELECT "posts".* FROM "posts" WHERE "posts"."id" IN ($$(?)… x8370 (+9 more) | 36/114 | 0 | 6/5 | 4 (3/3) | 4 (3/3) | `(SYM_NOTE_TYPE_PROFILE == 5)` |
| 27 | RELEVANT | 1 | 5522 | 61553 | 0 | SELECT "users".* FROM "users" WHERE "users"."id" = $$(?) L… x2425; SELECT "contacts".* FROM "contacts" WHERE "contacts"."user… x2411 (+4 more) | SELECT "mentions".* FROM "mentions" WHERE "mentions"."ment… x31353; SELECT "posts".* FROM "posts" WHERE "posts"."id" = $$(?) L… x22138 (+11 more) | 18/134 | 0 | 8/5 | 4 (3/3) | 4 (3/3) | `(SYM_NOTE_TYPE_PROFILE == 6)` |
| 28 | RELEVANT | 1 | 1883 | 65192 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."id" = $$(?… x43139; SELECT "mentions".* FROM "mentions" WHERE "mentions"."ment… x31353 (+19 more) | 0/152 | 0 | 5/5 | 4 (3/3) | 4 (3/3) | `(SYM_NOTE_TYPE_PROFILE == 7)` |
| 29 | RELEVANT | 1 | 29301 | 38768 | 0 | SELECT "notifications".* FROM "notifications" WHERE "notif… x19516; SELECT COUNT(*) FROM "notifications" WHERE "notifications"… x9785 (+1 more) | SELECT COUNT(*) FROM "notifications" WHERE "notifications"… x25427; SELECT "notifications".* FROM "notifications" WHERE "notif… x25427 (+2 more) | 87/88 | 0 | 6/5 | 0 (0/0) | 3408 (3408/3408) | `(SYM_PARAM_show == SV('unread'))` |
| 30 | RELEVANT | 1 | 47439 | 938 | 0 | SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x19204; SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x10610 (+2 more) | — | 56/0 | 0 | 3/2 | 19 (0/0) | 19 (0/0) | `(SYM_POST_STI == 0)` |
| 31 | RELEVANT | 1 | 903 | 47474 | 0 | — | SELECT "mentions".* FROM "mentions" WHERE "mentions"."ment… x31353; SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x19204 (+3 more) | 0/62 | 0 | 2/3 | 7 (0/0) | 7 (0/0) | `(SYM_POST_STI == 1)` |
| 32 | UNDECIDABLE (thin arm) | 6 | 2114 | 26 | 0 | SELECT COUNT(*) FROM "notifications" WHERE "notifications"… x259; SELECT "notifications".* FROM "notifications" WHERE "notif… x259 (+2 more) | — | 70/0 | 0 | 1/0 | 16 (0/0) | 16 (0/0) | `(CP.photos_row_mention_inline_name == True)` |
| 33 | IRRELEVANT | 6 | 2011 | 87 | 0 | — | — | 66/0 | 0 | 0/5 | 27 (0/0) | 27 (0/0) | `(CP.photos_row_text_dlink_is_post == True)` |
| 34 | IRRELEVANT | 6 | 2098 | 23771 | 0 | — | — | 0/0 | 0 | 0/2 | 0 (0/0) | 0 (0/0) | `(CP.photos_row_text_has_dlink == True)` |
| 35 | IRRELEVANT | 6 | 2140 | 23729 | 0 | — | — | 0/0 | 0 | 1/2 | 0 (0/0) | 0 (0/0) | `(CP.photos_row_text_has_mention == True)` |
| 36 | IRRELEVANT | 6 | 1645 | 25869 | 0 | — | — | 0/0 | 0 | 1/2 | 0 (0/0) | 0 (0/0) | `(CP.photos_row_text_nil == True)` |
| 37 | RELEVANT | 1 | 379 | 12822 | 0 | — | SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('?'… x442; SELECT "photos".* FROM "photos" WHERE "photos"."id" = $$(?… x379 (+2 more) | 0/48 | 0 | 0/3 | 132 (0/0) | 132 (0/0) | `(AR.Calculations_sum_2_sum > 0)` |
| 38 | RELEVANT | 1 | 163 | 182 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."id" IN ($$… x8; SELECT "profiles".* FROM "profiles" WHERE "profiles"."pers… x8 (+1 more) | 4/24 | 1 | 0/0 | 24 (0/0) | 24 (0/0) | `(CORE.find_by_1_diaspora_handle == SV('concolic_mention@example.org'))` |
| 39 | UNDECIDABLE (thin arm) | 1 | 0 | 345 | 0 | — | SELECT "users".* FROM "users" WHERE "users"."id" = $$(?) O… x345; SELECT COUNT(*) FROM "notifications" WHERE "notifications"… x345 (+35 more) | 0/86 | 1 | 0/0 | 0 (0/0) | 0 (0/0) | `(CORE.find_by_1_not_found == True)` |
| 40 | UNDECIDABLE (thin arm) | 1 | 345 | 0 | 0 | SELECT "users".* FROM "users" WHERE "users"."id" = $$(?) O… x345; SELECT COUNT(*) FROM "notifications" WHERE "notifications"… x345 (+35 more) | — | 86/0 | 1 | 0/0 | 0 (0/0) | 0 (0/0) | `(CORE.find_by_1_persisted == True)` |
| 41 | UNDECIDABLE (thin arm) | 1 | 270 | 1 | 0 | SELECT COUNT(*) FROM "notifications" WHERE "notifications"… x87; SELECT "notifications".* FROM "notifications" WHERE "notif… x87 (+15 more) | — | 47/0 | 0 | 0/0 | 1 (0/0) | 1 (0/0) | `(CORE.find_by_1_profile_disp_dlink_is_post == True)` |
| 42 | RELEVANT | 1 | 271 | 74 | 0 | — | SELECT "comments".* FROM "comments" WHERE "comments"."id" … x7 | 8/18 | 0 | 0/0 | 0 (0/0) | 0 (0/0) | `(CORE.find_by_1_profile_disp_has_dlink == True)` |
| 43 | UNDECIDABLE (thin arm) | 1 | 0 | 345 | 0 | — | SELECT "users".* FROM "users" WHERE "users"."id" = $$(?) O… x345; SELECT COUNT(*) FROM "notifications" WHERE "notifications"… x345 (+35 more) | 0/86 | 0 | 0/0 | 0 (0/0) | 0 (0/0) | `(CORE.find_by_1_profile_not_found == True)` |
| 44 | RELEVANT | 1 | 3290 | 50238 | 0 | — | SELECT SUM("conversation_visibilities"."unread") FROM "con… x33899; SELECT ? AS one FROM "roles" WHERE "roles"."person_id" = $… x33899 (+8 more) | 0/16 | 4 | 72/2 | 0 (0/0) | 0 (0/0) | `(FM.devise_user_first_1_person_not_found == True)` |
| 45 | RELEVANT (chance-absence only) | 1 | 33923 | 172 | 0 | SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('?'… x967; SELECT "photos".* FROM "photos" WHERE "photos"."id" = $$(?… x770 (+2 more) | — | 78/0 | 4 | 2/1 | 145 (0/0) | 145 (0/0) | `(FM.devise_user_first_1_person_persisted == True)` |
| 46 | RELEVANT | 1 | 2044 | 68 | 0 | SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x454; SELECT ? AS one FROM "posts" WHERE "posts"."guid" = $$(?) … x206 (+1 more) | — | 85/0 | 0 | 0/0 | 20 (0/0) | 20 (0/0) | `(FM.devise_user_first_1_person_profile_disp_dlink_is_post == True)` |
| 47 | RELEVANT | 1 | 2112 | 31787 | 0 | — | SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('?'… x967; SELECT "photos".* FROM "photos" WHERE "photos"."id" = $$(?… x770 (+2 more) | 0/30 | 0 | 0/1 | 0 (0/0) | 0 (0/0) | `(FM.devise_user_first_1_person_profile_disp_has_dlink == True)` |
| 48 | RELEVANT | 1 | 923 | 32976 | 0 | — | SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('?'… x967; SELECT "photos".* FROM "photos" WHERE "photos"."id" = $$(?… x770 (+2 more) | 0/31 | 0 | 0/1 | 155 (0/0) | 155 (0/0) | `(FM.devise_user_first_1_person_profile_first_name == SV(''))` |
| 49 | RELEVANT | 1 | 922 | 32977 | 0 | — | SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('?'… x967; SELECT "photos".* FROM "photos" WHERE "photos"."id" = $$(?… x770 (+2 more) | 0/31 | 0 | 0/1 | 159 (0/0) | 159 (0/0) | `(FM.devise_user_first_1_person_profile_last_name == SV(''))` |
| 50 | RELEVANT | 1 | 196 | 33899 | 0 | — | SELECT SUM("conversation_visibilities"."unread") FROM "con… x33899; SELECT ? AS one FROM "roles" WHERE "roles"."person_id" = $… x33899 (+11 more) | 0/85 | 0 | 100/1 | 0 (0/0) | 0 (0/0) | `(FM.devise_user_first_1_person_profile_not_found == True)` |
| 51 | RELEVANT | 1 | 162 | 68069 | 0 | — | SELECT COUNT(*) FROM "notifications" WHERE "notifications"… x68069; SELECT "notifications".* FROM "notifications" WHERE "notif… x68069 (+47 more) | 0/212 | 21 | 100/5 | 0 (0/0) | 0 (0/0) | `(FM.devise_user_first_1_stale_language == True)` |
| 52 | UNDECIDABLE (thin arm) | 1 | 0 | 12804 | 0 | — | SELECT "users".* FROM "users" WHERE "users"."id" = $$(?) O… x12804; SELECT COUNT(*) FROM "notifications" WHERE "notifications"… x12804 (+42 more) | 0/193 | 19 | 0/0 | 0 (0/0) | 0 (0/0) | `(FM.devise_user_first_1_username == '')` |
| 53 | RELEVANT | 1 | 916 | 33714 | 0 | — | SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('?'… x967; SELECT "photos".* FROM "photos" WHERE "photos"."id" = $$(?… x770 (+2 more) | 0/26 | 0 | 0/1 | 325 (0/0) | 325 (0/0) | `(FM.exists__1_exists == True)` |
| 54 | IRRELEVANT | 1 | 7956 | 26190 | 0 | — | — | 0/5 | 0 | 1/1 | 778 (0/0) | 778 (0/0) | `(FM.exists__2_exists == True)` |
| 55 | RELEVANT | 1 | 709 | 13894 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x115; SELECT "photos".* FROM "photos" WHERE "photos"."id" IN ($$… x63 | 0/32 | 0 | 0/0 | 23 (0/0) | 23 (0/0) | `(FM.exists__3_exists == True)` |
| 56 | RELEVANT | 1 | 632 | 12759 | 0 | — | SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('?'… x436; SELECT "photos".* FROM "photos" WHERE "photos"."id" = $$(?… x373 (+2 more) | 0/35 | 0 | 0/0 | 13 (0/0) | 13 (0/0) | `(FM.exists__4_exists == True)` |
| 57 | RELEVANT | 1 | 203 | 722 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."id" IN ($$… x34; SELECT "profiles".* FROM "profiles" WHERE "profiles"."pers… x34 (+1 more) | 0/28 | 0 | 0/1 | 10 (0/0) | 10 (0/0) | `(FM.exists__5_exists == True)` |
| 58 | RELEVANT (chance-absence only) | 1 | 112 | 157 | 0 | — | SELECT "notifications".* FROM "notifications" WHERE "notif… x2; SELECT COUNT(*) FROM "notifications" WHERE "notifications"… x2 (+1 more) | 4/19 | 0 | 0/3 | 6 (0/0) | 6 (0/0) | `(FM.exists__6_exists == True)` |
| 59 | UNDECIDABLE (thin arm) | 1 | 159 | 35 | 0 | SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" … x72 | SELECT "notifications".* FROM "notifications" WHERE "notif… x2; SELECT COUNT(*) FROM "notifications" WHERE "notifications"… x2 (+1 more) | 5/19 | 0 | 0/0 | 8 (0/0) | 8 (0/0) | `(FM.exists__7_exists == True)` |
| 60 | UNDECIDABLE (thin arm) | 1 | 31 | 75 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."id" IN ($$… x4; SELECT "profiles".* FROM "profiles" WHERE "profiles"."pers… x4 (+3 more) | 0/23 | 0 | 0/0 | 7 (0/0) | 7 (0/0) | `(FM.exists__8_exists == True)` |
| 61 | UNDECIDABLE (thin arm) | 1 | 7 | 2404 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."id" = $$(?… x2404; SELECT "aspect_memberships".* FROM "aspect_memberships" WH… x2404 (+6 more) | 0/30 | 6 | 29/4 | 0 (0/0) | 0 (0/0) | `(FM.find_by_1_not_found == True)` |
| 62 | UNDECIDABLE (thin arm) | 1 | 2391 | 13 | 0 | SELECT "people".* FROM "people" WHERE "people"."id" IN ($$… x191; SELECT "profiles".* FROM "profiles" WHERE "profiles"."pers… x191 | — | 16/0 | 6 | 4/0 | 11 (0/0) | 11 (0/0) | `(FM.find_by_1_persisted == True)` |
| 63 | IRRELEVANT | 1 | 1104 | 1212 | 0 | — | — | 0/2 | 5 | 1/0 | 0 (0/0) | 0 (0/0) | `(FM.find_by_1_person_id == FM.devise_user_first_1_person_id)` |
| 64 | IRRELEVANT | 1 | 526 | 321 | 0 | — | — | 0/0 | 5 | 2/6 | 9 (0/0) | 9 (0/0) | `(FM.find_by_1_person_id == FM.find_by_1_person_id)` |
| 65 | UNDECIDABLE (thin arm) | 1 | 2393 | 11 | 0 | SELECT "people".* FROM "people" WHERE "people"."id" IN ($$… x191; SELECT "profiles".* FROM "profiles" WHERE "profiles"."pers… x191 | — | 16/0 | 5 | 4/0 | 11 (0/0) | 11 (0/0) | `(FM.find_by_1_person_persisted == True)` |
| 66 | IRRELEVANT | 1 | 1010 | 897 | 0 | — | — | 0/0 | 1 | 3/4 | 10 (0/0) | 10 (0/0) | `(FM.find_by_1_person_profile_birthday_year <= 1004)` |
| 67 | RELEVANT | 1 | 1426 | 78 | 0 | SELECT ? AS one FROM "posts" WHERE "posts"."guid" = $$(?) … x1074 | — | 9/0 | 1 | 4/5 | 1 (0/0) | 1 (0/0) | `(FM.find_by_1_person_profile_disp_dlink_is_post == True)` |
| 68 | RELEVANT | 1 | 1504 | 894 | 0 | SELECT ? AS one FROM "posts" WHERE "posts"."guid" = $$(?) … x1074 | — | 1/0 | 1 | 4/4 | 0 (0/0) | 0 (0/0) | `(FM.find_by_1_person_profile_disp_has_dlink == True)` |
| 69 | IRRELEVANT | 1 | 1016 | 1382 | 0 | — | — | 0/0 | 1 | 3/5 | 11 (0/0) | 11 (0/0) | `(FM.find_by_1_person_profile_first_name == SV(''))` |
| 70 | IRRELEVANT | 1 | 1013 | 1385 | 0 | — | — | 0/0 | 1 | 3/5 | 14 (0/0) | 14 (0/0) | `(FM.find_by_1_person_profile_last_name == SV(''))` |
| 71 | UNDECIDABLE (thin arm) | 1 | 6 | 2398 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."owner_id" … x2398; SELECT "blocks".* FROM "blocks" WHERE "blocks"."user_id" =… x2398 (+10 more) | 0/34 | 1 | 100/4 | 0 (0/0) | 0 (0/0) | `(FM.find_by_1_person_profile_not_found == True)` |
| 72 | UNDECIDABLE (thin arm) | 1 | 2374 | 24 | 0 | SELECT "tags"."name" FROM "tags" INNER JOIN "taggings" ON … x2374; SELECT COUNT(*) FROM "notifications" WHERE "notifications"… x418 (+1 more) | — | 21/0 | 1 | 4/0 | 13 (13/13) | 13 (13/13) | `(FM.find_by_1_person_profile_persisted == True)` |
| 73 | IRRELEVANT | 1 | 1005 | 1393 | 0 | — | — | 0/0 | 1 | 3/5 | 11 (0/0) | 11 (0/0) | `(FM.find_by_1_person_profile_public_details == True)` |
| 74 | UNDECIDABLE (thin arm) | 1 | 11 | 2387 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."id" IN ($$… x191; SELECT "profiles".* FROM "profiles" WHERE "profiles"."pers… x191 | 0/18 | 1 | 0/4 | 10 (0/0) | 10 (0/0) | `(FM.find_by_2_not_found == True)` |
| 75 | UNDECIDABLE (thin arm) | 1 | 1286 | 7 | 0 | SELECT "notifications".* FROM "notifications" WHERE "notif… x314; SELECT "people".* FROM "people" WHERE "people"."id" IN ($$… x86 (+1 more) | — | 23/0 | 1 | 6/0 | 3 (0/0) | 3 (0/0) | `(FM.find_by_2_persisted == True)` |
| 76 | RELEVANT | 1 | 254 | 490 | 0 | SELECT ? AS one FROM "posts" WHERE "posts"."guid" = $$(?) … x219 | — | 3/0 | 1 | 13/5 | 0 (0/0) | 0 (0/0) | `(FM.find_by_2_sharing == True)` |
| 77 | UNDECIDABLE (thin arm) | 1 | 11 | 2386 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."id" IN ($$… x191; SELECT "profiles".* FROM "profiles" WHERE "profiles"."pers… x191 | 0/16 | 0 | 0/4 | 11 (0/0) | 11 (0/0) | `(FM.find_by_3_not_found == True)` |
| 78 | UNDECIDABLE (thin arm) | 1 | 0 | 1 | 0 | — | SELECT "users".* FROM "users" WHERE "users"."id" = $$(?) O… x1; SELECT "notification_actors".* FROM "notification_actors" … x1 (+21 more) | 0/26 | 0 | 0/0 | 0 (0/0) | 0 (0/0) | `(FM.find_by_4_not_found == True)` |
| 79 | IRRELEVANT | 3 | 941 | 1033 | 0 | — | — | 0/8 | 12 | 1/2 | 97 (0/0) | 97 (0/0) | `(REL.mentions_row_person_diaspora_handle == SV('concolic_mention@example.org'))` |
| 80 | IRRELEVANT | 3 | 326 | 29393 | 0 | — | — | 0/18 | 12 | 10/2 | 0 (0/0) | 0 (0/0) | `(REL.mentions_row_person_not_found == True)` |
| 81 | UNDECIDABLE (thin arm) | 3 | 2051 | 46 | 0 | SELECT "people".* FROM "people" WHERE "people"."id" IN ($$… x136; SELECT "profiles".* FROM "profiles" WHERE "profiles"."pers… x136 (+1 more) | — | 62/0 | 0 | 1/2 | 32 (0/0) | 32 (0/0) | `(REL.mentions_row_person_profile_row_disp_dlink_is_post == True)` |
| 82 | IRRELEVANT | 3 | 2097 | 27296 | 0 | — | — | 0/5 | 0 | 1/2 | 0 (0/0) | 0 (0/0) | `(REL.mentions_row_person_profile_row_disp_has_dlink == True)` |
| 83 | RELEVANT (chance-absence only) | 1 | 274 | 78 | 0 | — | SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" … x1 | 2/1 | 0 | 0/10 | 27 (0/0) | 27 (0/0) | `(REL.mentions_row_person_profile_row_first_name == SV(''))` |
| 84 | RELEVANT (chance-absence only) | 1 | 275 | 77 | 0 | SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" … x1 | — | 4/0 | 0 | 1/8 | 35 (0/0) | 35 (0/0) | `(REL.mentions_row_person_profile_row_last_name == SV(''))` |
| 85 | RELEVANT | 1 | 1731 | 5632 | 0 | — | SELECT ? AS one FROM "posts" WHERE "posts"."guid" = $$(?) … x40 | 0/4 | 0 | 7/5 | 217 (0/0) | 226 (0/0) | `(REL.notifications_row_target_is_photo == True)` |
| 86 | RELEVANT | 1 | 13005 | 196 | 0 | SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('?'… x442; SELECT "photos".* FROM "photos" WHERE "photos"."id" = $$(?… x379 (+2 more) | — | 80/0 | 0 | 3/1 | 78 (0/0) | 78 (0/0) | `(AR.Relation_size_1_size > 0)` |
| 87 | UNDECIDABLE (thin arm) | 1 | 87 | 0 | 0 | SELECT "users".* FROM "users" WHERE "users"."id" = $$(?) O… x87; SELECT "people".* FROM "people" WHERE "people"."id" = $$(?… x87 (+30 more) | — | 68/0 | 0 | 0/0 | 0 (0/0) | 0 (0/0) | `(AR.Relation_size_2_size > 0)` |
| 88 | RELEVANT | 1 | 1325 | 109 | 0 | SELECT "mentions".* FROM "mentions" WHERE "mentions"."id" … x627; SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x350 (+3 more) | — | 93/0 | 0 | 0/0 | 97 (0/0) | 97 (0/0) | `(AR.Relation_size_3_size > 0)` |
| 89 | RELEVANT | 4 | 2364 | 47921 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x331 | 0/8 | 24 | 3/7 | 727 (0/0) | 729 (0/0) | `(TOARY_row_actors_row_guid == '')` |
| 90 | RELEVANT | 4 | 43566 | 3673 | 0 | SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x331 | — | 9/0 | 24 | 2/2 | 945 (0/0) | 949 (0/0) | `(TOARY_row_actors_row_id == FM.devise_user_first_1_person_id)` |
| 91 | RELEVANT | 4 | 9980 | 814 | 0 | SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" … x107; SELECT "photos".* FROM "photos" WHERE "photos"."id" IN ($$… x27 | — | 45/0 | 0 | 4/3 | 247 (0/0) | 246 (0/0) | `(TOARY_row_actors_row_profile_row_disp_dlink_is_post == True)` |
| 92 | RELEVANT | 4 | 10794 | 47643 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x331 | 0/7 | 0 | 4/6 | 0 (0/0) | 0 (0/0) | `(TOARY_row_actors_row_profile_row_disp_has_dlink == True)` |
| 93 | RELEVANT | 4 | 5579 | 44706 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x331 | 0/7 | 0 | 5/7 | 514 (0/0) | 511 (0/0) | `(TOARY_row_actors_row_profile_row_first_name == SV(''))` |
| 94 | IRRELEVANT | 4 | 5567 | 44718 | 0 | — | — | 0/5 | 0 | 5/7 | 513 (0/0) | 515 (0/0) | `(TOARY_row_actors_row_profile_row_last_name == SV(''))` |
| 95 | UNDECIDABLE (thin arm) | 4 | 14 | 2411 | 0 | — | SELECT "contacts".* FROM "contacts" WHERE "contacts"."user… x2411; SELECT "profiles".* FROM "profiles" WHERE "profiles"."pers… x2409 (+13 more) | 0/30 | 8 | 100/4 | 0 (0/0) | 0 (0/0) | `(TOARY_row_recipient_not_found == True)` |
| 96 | UNDECIDABLE (thin arm) | 4 | 16 | 2093 | 0 | — | SELECT "profiles".* FROM "profiles" WHERE "profiles"."pers… x2093; SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('?'… x2080 (+11 more) | 0/42 | 8 | 100/2 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_author_not_found == True)` |
| 97 | RELEVANT (chance-absence only) | 4 | 23468 | 334 | 0 | SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x231 | — | 5/0 | 8 | 3/1 | 232 (0/0) | 234 (0/0) | `(TOARY_row_target_author_persisted == True)` |
| 98 | UNDECIDABLE (thin arm) | 4 | 3244 | 46 | 0 | SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('?'… x110; SELECT "photos".* FROM "photos" WHERE "photos"."id" = $$(?… x77 (+3 more) | — | 30/0 | 0 | 1/0 | 25 (0/0) | 25 (0/0) | `(TOARY_row_target_author_profile_disp_dlink_is_post == True)` |
| 99 | RELEVANT | 4 | 3290 | 20228 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x231 | 0/5 | 0 | 1/2 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_author_profile_disp_has_dlink == True)` |
| 100 | RELEVANT | 4 | 1387 | 22131 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x231 | 0/5 | 0 | 2/2 | 250 (0/0) | 252 (0/0) | `(TOARY_row_target_author_profile_first_name == SV(''))` |
| 101 | RELEVANT | 4 | 1423 | 22095 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x231 | 0/6 | 0 | 2/2 | 260 (0/0) | 262 (0/0) | `(TOARY_row_target_author_profile_last_name == SV(''))` |
| 102 | RELEVANT | 4 | 284 | 23518 | 0 | — | SELECT "mentions".* FROM "mentions" WHERE "mentions"."ment… x17070; SELECT SUM("conversation_visibilities"."unread") FROM "con… x14859 (+13 more) | 0/47 | 0 | 100/2 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_author_profile_not_found == True)` |
| 103 | RELEVANT | 4 | 3373 | 72 | 0 | SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x3373; SELECT "people".* FROM "people" WHERE "people"."id" IN ($$… x348 (+1 more) | SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x72 | 20/4 | 24 | 1/0 | 0 (0/0) | 25 (25/25) | `(TOARY_row_target_guid == '')` |
| 104 | RELEVANT | 4 | 2622 | 4682 | 0 | SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('?'… x2080; SELECT "photos".* FROM "photos" WHERE "photos"."id" = $$(?… x1780 (+1 more) | SELECT "posts".* FROM "posts" WHERE "posts"."id" = $$(?) x3273; SELECT "mentions".* FROM "mentions" WHERE "mentions"."ment… x2537 (+4 more) | 20/28 | 80 | 9/4 | 35 (35/35) | 39 (39/39) | `(TOARY_row_target_is_photo == True)` |
| 105 | RELEVANT (chance-absence only) | 4 | 1410 | 536 | 0 | SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('?'… x8; SELECT "photos".* FROM "photos" WHERE "photos"."id" = $$(?… x4 | — | 18/0 | 37 | 3/2 | 58 (0/0) | 58 (0/0) | `(TOARY_row_target_mention_inline_name == True)` |
| 106 | UNDECIDABLE (thin arm) | 4 | 7871 | 47 | 0 | SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" … x268 | — | 7/0 | 8 | 2/0 | 38 (0/0) | 38 (0/0) | `(TOARY_row_target_mentions_container_author_persisted == True)` |
| 107 | UNDECIDABLE (thin arm) | 4 | 4925 | 34 | 0 | SELECT "people".* FROM "people" WHERE "people"."id" IN ($$… x358; SELECT "profiles".* FROM "profiles" WHERE "profiles"."pers… x358 (+1 more) | — | 15/0 | 0 | 1/0 | 28 (0/0) | 28 (0/0) | `(TOARY_row_target_mentions_container_author_profile_disp_dlink_is_post == True)` |
| 108 | IRRELEVANT | 4 | 4959 | 2929 | 0 | — | — | 0/0 | 0 | 1/2 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_mentions_container_author_profile_disp_has_dlink == True)` |
| 109 | IRRELEVANT | 4 | 1552 | 6336 | 0 | — | — | 0/0 | 0 | 2/1 | 48 (0/0) | 48 (0/0) | `(TOARY_row_target_mentions_container_author_profile_first_name == SV(''))` |
| 110 | IRRELEVANT | 4 | 1545 | 6343 | 0 | — | — | 0/0 | 0 | 2/1 | 47 (0/0) | 47 (0/0) | `(TOARY_row_target_mentions_container_author_profile_last_name == SV(''))` |
| 111 | UNDECIDABLE (thin arm) | 4 | 30 | 7888 | 0 | — | SELECT SUM("conversation_visibilities"."unread") FROM "con… x5150; SELECT ? AS one FROM "roles" WHERE "roles"."person_id" = $… x5150 (+9 more) | 0/22 | 0 | 100/1 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_mentions_container_author_profile_not_found == True)` |
| 112 | RELEVANT (chance-absence only) | 4 | 8944 | 55 | 0 | SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" … x296 | — | 7/0 | 8 | 4/0 | 42 (0/0) | 42 (0/0) | `(TOARY_row_target_mentions_container_commentable_author_persisted == True)` |
| 113 | UNDECIDABLE (thin arm) | 4 | 2424 | 23 | 0 | SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x283; SELECT COUNT(*) FROM "notifications" WHERE "notifications"… x127 (+4 more) | — | 35/0 | 0 | 1/0 | 17 (0/0) | 17 (0/0) | `(TOARY_row_target_mentions_container_commentable_author_profile_disp_dlink_is_post == True)` |
| 114 | IRRELEVANT | 4 | 2447 | 6514 | 0 | — | — | 0/0 | 0 | 1/4 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_mentions_container_commentable_author_profile_disp_has_dlink == True)` |
| 115 | IRRELEVANT | 4 | 5432 | 3529 | 0 | — | — | 0/0 | 0 | 4/2 | 58 (0/0) | 58 (0/0) | `(TOARY_row_target_mentions_container_commentable_author_profile_first_name == SV(''))` |
| 116 | IRRELEVANT | 4 | 5431 | 3530 | 0 | — | — | 0/0 | 0 | 4/1 | 50 (0/0) | 50 (0/0) | `(TOARY_row_target_mentions_container_commentable_author_profile_last_name == SV(''))` |
| 117 | UNDECIDABLE (thin arm) | 4 | 38 | 8961 | 0 | — | SELECT SUM("conversation_visibilities"."unread") FROM "con… x5646; SELECT ? AS one FROM "roles" WHERE "roles"."person_id" = $… x5646 (+9 more) | 0/20 | 0 | 100/3 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_mentions_container_commentable_author_profile_not_found == True)` |
| 118 | RELEVANT | 4 | 3692 | 88 | 0 | SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x3692; SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" … x116 | SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x88 | 11/4 | 20 | 5/1 | 0 (0/0) | 34 (34/34) | `(TOARY_row_target_mentions_container_commentable_guid == '')` |
| 119 | UNDECIDABLE (thin arm) | 4 | 465 | 8 | 0 | SELECT "tag_followings".* FROM "tag_followings" WHERE "tag… x123; SELECT "tags".* FROM "tags" INNER JOIN "tag_followings" ON… x123 (+4 more) | — | 36/0 | 12 | 1/0 | 6 (0/0) | 6 (0/0) | `(TOARY_row_target_mentions_container_commentable_mention_inline_name == True)` |
| 120 | RELEVANT | 4 | 60 | 11919 | 0 | — | SELECT "profiles".* FROM "profiles" WHERE "profiles"."pers… x10747; SELECT "people".* FROM "people" WHERE "people"."id" = $$(?… x8999 (+14 more) | 0/46 | 24 | 100/3 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_mentions_container_commentable_not_found == True)` |
| 121 | RELEVANT | 4 | 7999 | 3843 | 0 | SELECT "mentions".* FROM "mentions" WHERE "mentions"."ment… x7999 | SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x3692; SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x7 | 10/6 | 24 | 2/5 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_mentions_container_commentable_persisted == True)` |
| 122 | UNDECIDABLE (thin arm) | 4 | 491 | 6 | 0 | SELECT ? AS one FROM "posts" WHERE "posts"."guid" = $$(?) … x483; SELECT "tag_followings".* FROM "tag_followings" WHERE "tag… x189 (+6 more) | — | 37/0 | 12 | 0/0 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_mentions_container_commentable_text_dlink_is_post == True)` |
| 123 | RELEVANT | 4 | 497 | 1246 | 0 | SELECT ? AS one FROM "posts" WHERE "posts"."guid" = $$(?) … x483 | — | 4/6 | 16 | 0/2 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_mentions_container_commentable_text_has_dlink == True)` |
| 124 | RELEVANT | 4 | 473 | 1270 | 0 | SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x7 | — | 2/4 | 16 | 1/2 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_mentions_container_commentable_text_has_mention == True)` |
| 125 | RELEVANT | 4 | 10176 | 1743 | 0 | SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x6431; SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x3692 | SELECT ? AS one FROM "posts" WHERE "posts"."guid" = $$(?) … x483; SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x7 | 8/6 | 24 | 3/2 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_mentions_container_commentable_text_nil == True)` |
| 126 | RELEVANT | 4 | 3545 | 57 | 0 | SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x3545; SELECT "people".* FROM "people" WHERE "people"."id" IN ($$… x292 (+2 more) | SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x57 | 13/4 | 20 | 2/0 | 0 (0/0) | 31 (31/31) | `(TOARY_row_target_mentions_container_guid == '')` |
| 127 | UNDECIDABLE (thin arm) | 4 | 1444 | 21 | 0 | SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x144; SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" … x65 | — | 36/0 | 40 | 3/0 | 12 (0/0) | 12 (0/0) | `(TOARY_row_target_mentions_container_mention_inline_name == True)` |
| 128 | RELEVANT | 4 | 109 | 22096 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."id" = $$(?… x16917; SELECT "mentions".* FROM "mentions" WHERE "mentions"."ment… x14283 (+5 more) | 0/67 | 52 | 5/3 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_mentions_container_not_found == True)` |
| 129 | RELEVANT | 4 | 6284 | 3782 | 0 | SELECT "mentions".* FROM "mentions" WHERE "mentions"."ment… x6284 | SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x3545; SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x107 | 9/6 | 24 | 2/2 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_mentions_container_persisted == True)` |
| 130 | UNDECIDABLE (thin arm) | 4 | 3431 | 37 | 0 | SELECT ? AS one FROM "posts" WHERE "posts"."guid" = $$(?) … x508; SELECT "people".* FROM "people" WHERE "people"."id" IN ($$… x239 (+3 more) | — | 27/0 | 40 | 2/0 | 19 (0/0) | 19 (0/0) | `(TOARY_row_target_mentions_container_text_dlink_is_post == True)` |
| 131 | IRRELEVANT | 4 | 3468 | 9142 | 0 | — | — | 4/6 | 44 | 2/4 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_mentions_container_text_has_dlink == True)` |
| 132 | IRRELEVANT | 4 | 1465 | 11145 | 0 | — | — | 0/6 | 44 | 3/3 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_mentions_container_text_has_mention == True)` |
| 133 | RELEVANT | 4 | 9486 | 12610 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x114 | 8/8 | 52 | 2/3 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_mentions_container_text_nil == True)` |
| 134 | RELEVANT | 4 | 4944 | 58011 | 0 | — | SELECT "people".* FROM "people" WHERE "people"."id" = $$(?… x43139; SELECT "mentions".* FROM "mentions" WHERE "mentions"."ment… x31353 (+13 more) | 0/128 | 120 | 38/3 | 244 (0/0) | 242 (0/0) | `(TOARY_row_target_not_found == True)` |
| 135 | RELEVANT | 4 | 17070 | 3972 | 0 | SELECT "mentions".* FROM "mentions" WHERE "mentions"."ment… x17070 | SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x3373; SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x231 | 9/6 | 28 | 2/1 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_persisted == True)` |
| 136 | UNDECIDABLE (thin arm) | 4 | 0 | 584 | 0 | — | SELECT "users".* FROM "users" WHERE "users"."id" = $$(?) O… x584; SELECT COUNT(*) FROM "notifications" WHERE "notifications"… x584 (+26 more) | 0/64 | 24 | 0/0 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_status_message_guid != TOARY_row_target_status_message_guid)` |
| 137 | UNDECIDABLE (thin arm) | 4 | 2047 | 16 | 0 | SELECT SUM("conversation_visibilities"."unread") FROM "con… x967; SELECT ? AS one FROM "roles" WHERE "roles"."person_id" = $… x967 (+7 more) | — | 26/0 | 8 | 1/0 | 11 (0/0) | 11 (0/0) | `(TOARY_row_target_statusmessage_author_persisted == True)` |
| 138 | RELEVANT | 4 | 914 | 67 | 0 | SELECT "tags".* FROM "tags" INNER JOIN "tag_followings" ON… x202; SELECT "tag_followings".* FROM "tag_followings" WHERE "tag… x202 | — | 6/0 | 0 | 0/0 | 59 (0/0) | 59 (0/0) | `(TOARY_row_target_statusmessage_author_profile_disp_dlink_is_post == True)` |
| 139 | RELEVANT | 4 | 981 | 1068 | 0 | — | SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" … x6 | 0/1 | 0 | 0/0 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_statusmessage_author_profile_disp_has_dlink == True)` |
| 140 | RELEVANT (chance-absence only) | 4 | 475 | 1574 | 0 | — | SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" … x6 | 0/3 | 0 | 0/0 | 16 (0/0) | 16 (0/0) | `(TOARY_row_target_statusmessage_author_profile_first_name == SV(''))` |
| 141 | RELEVANT (chance-absence only) | 4 | 473 | 1576 | 0 | — | SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" … x6 | 0/3 | 0 | 0/0 | 16 (0/0) | 16 (0/0) | `(TOARY_row_target_statusmessage_author_profile_last_name == SV(''))` |
| 142 | UNDECIDABLE (thin arm) | 4 | 14 | 2049 | 0 | — | SELECT SUM("conversation_visibilities"."unread") FROM "con… x967; SELECT ? AS one FROM "roles" WHERE "roles"."person_id" = $… x967 (+7 more) | 0/26 | 0 | 100/0 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_statusmessage_author_profile_not_found == True)` |
| 143 | UNDECIDABLE (thin arm) | 4 | 136 | 5 | 0 | SELECT "photos".* FROM "photos" WHERE "photos"."id" IN ($$… x43; SELECT "notification_actors".* FROM "notification_actors" … x43 (+8 more) | — | 40/0 | 8 | 1/0 | 1 (0/0) | 1 (0/0) | `(TOARY_row_target_statusmessage_mention_inline_name == True)` |
| 144 | UNDECIDABLE (thin arm) | 4 | 17 | 2063 | 0 | — | SELECT SUM("conversation_visibilities"."unread") FROM "con… x967; SELECT ? AS one FROM "roles" WHERE "roles"."person_id" = $… x967 (+7 more) | 0/30 | 8 | 100/1 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_statusmessage_not_found == True)` |
| 145 | UNDECIDABLE (thin arm) | 4 | 467 | 4 | 0 | SELECT "tag_followings".* FROM "tag_followings" WHERE "tag… x111; SELECT "tags".* FROM "tags" INNER JOIN "tag_followings" ON… x111 (+10 more) | — | 48/0 | 8 | 1/0 | 3 (0/0) | 3 (0/0) | `(TOARY_row_target_statusmessage_text_dlink_is_post == True)` |
| 146 | RELEVANT (chance-absence only) | 4 | 471 | 1420 | 0 | — | SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" … x6 | 0/1 | 8 | 1/1 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_statusmessage_text_has_dlink == True)` |
| 147 | RELEVANT | 4 | 141 | 1750 | 0 | — | SELECT "tags".* FROM "tags" INNER JOIN "tag_followings" ON… x390; SELECT "tag_followings".* FROM "tag_followings" WHERE "tag… x390 (+1 more) | 0/11 | 8 | 1/1 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_statusmessage_text_has_mention == True)` |
| 148 | RELEVANT (chance-absence only) | 4 | 172 | 1891 | 0 | — | SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" … x6 | 0/5 | 8 | 0/1 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_statusmessage_text_nil == True)` |
| 149 | UNDECIDABLE (thin arm) | 4 | 1316 | 46 | 0 | SELECT ? AS one FROM "posts" WHERE "posts"."guid" = $$(?) … x887; SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" … x120 (+5 more) | — | 43/0 | 37 | 2/0 | 9 (0/0) | 9 (0/0) | `(TOARY_row_target_text_dlink_is_post == True)` |
| 150 | RELEVANT | 4 | 1362 | 13398 | 0 | SELECT ? AS one FROM "posts" WHERE "posts"."guid" = $$(?) … x887 | SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x231 | 4/5 | 40 | 2/4 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_text_has_dlink == True)` |
| 151 | RELEVANT | 4 | 1946 | 12814 | 0 | SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x231 | — | 2/3 | 40 | 3/4 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_text_has_mention == True)` |
| 152 | RELEVANT | 4 | 13873 | 14760 | 0 | SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x7973; SELECT "photos".* FROM "photos" WHERE "photos"."status_mes… x3373 | SELECT ? AS one FROM "posts" WHERE "posts"."guid" = $$(?) … x887; SELECT "people".* FROM "people" WHERE "people"."diaspora_h… x231 | 8/6 | 48 | 2/4 | 0 (0/0) | 0 (0/0) | `(TOARY_row_target_text_nil == True)` |
| 153 | RELEVANT | 4 | 3472 | 35771 | 0 | SELECT "users".* FROM "users" WHERE "users"."id" = $$(?) L… x2425; SELECT "contacts".* FROM "contacts" WHERE "contacts"."user… x2411 (+4 more) | SELECT "mentions".* FROM "mentions" WHERE "mentions"."ment… x22755; SELECT "posts".* FROM "posts" WHERE "posts"."id" = $$(?) L… x15126 (+11 more) | 18/134 | 156 | 10/5 | 0 (0/0) | 0 (0/0) | `(TOARY_row_type == SV('Notifications::StartedSharing'))` |
