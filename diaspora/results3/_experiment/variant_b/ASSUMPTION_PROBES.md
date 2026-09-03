# variant_b — T2 assumption-probe results

Harness: `_t2_divergence_run.rb` (re-runnable), driven by `_t2_seeds/*.json`
+ `run_dse.rb`'s existing `EXTRA_SEEDS_JSON`/`SEEDS_ONLY=1` knobs. Each side
is a SEPARATE fresh JRuby process (`Coverage.start(lines: true)` runs
before `config/environment` loads, so gem/app code compiled during boot is
instrumented; a same-process double-`load` of `run_dse.rb` was avoided
because it would double-patch every `declare_target`). Raw per-class
evidence (guard/foreclosed exprs, coverage divergence lines) is in
`ASSUMPTION_FLOW.json`; this file is the human summary.

`coverage_assumptions.py` was edited to add a `_T2_BLOCKED_CLASSES`
frozenset and a `_T2_ONE_SIDED_PROBED_OK` flag: a Tier-1 class or the Tier-2
one-sided class is only auto-declared from the corpus if it is NOT in the
blocklist / the flag is True. Currently: `count-chain` is blocked, Tier-2
one-sided is blocked, `finder-arm` and `persisted-gate` are allowed
(probed and passed below), Tier 0 and `same-var-chain` are unaffected
(sound by construction, per DISCIPLINE_TESTS.md's own carve-out).

## Results

| class | verdict | guard | evidence |
|---|---|---|---|
| finder-arm | **PASS** | `FinderMethods_first_1_not_found` | clean disjoint PC sets (0/24 vs 3/27) |
| persisted-gate | **PASS** | `to_ary_1_row_persisted` | disjoint PC sets + coverage divergence at the exact cited mechanism (targets.rb size-shim, collection_association.rb null_scope?, has_many_association.rb count_records) |
| tier0-type-exclusivity (sanity) | **PASS** | `SYM_NOTE_TYPE_PROFILE` (0 vs 4) | disjoint PC sets, one representative pair as required |
| same-var-chain | sound by construction | n/a | not separately probed (DISCIPLINE_TESTS.md carve-out: "Tier 0 ... is sound by construction"; same-var-chain is definitionally the identical Z3 variable, equally construction-sound) |
| count-chain | **BLOCKED / NOT PROBED** | — | no genuine example found in available time |
| one-sided (Tier 2, `guid != ''`) | **BLOCKED / NOT PROBED** | — | recording site not reached by any seed tried |

### finder-arm — PASS

Guard: `(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)`,
`concolic_targets.rb:527-534` (`finder_mock`'s `if not_found == true ...
else symbolic_instance(...) end`). Two runs:

- **Foreclosing** (`not_found` forced `True`, `dump_plain_t2_nft_dse0001.json`):
  24 total PCs. None of the found-arm's attribute exprs appear.
- **Recording** (`not_found` forced `False`, `dump_plain_t2_nff_dse0001.json`):
  27 total PCs — exactly the foreclosing side's 24 plus 3 new: `first_1_guid
  == ''`, `first_1_id == SYM_PERSON_NI_id`, `first_1_persisted == True`.

Clean disjoint sets: `only_in_foreclosing = {}`, `only_in_recording = {those
3 exprs}`. The branch is a single 2-line if/else, so the mechanism is
unambiguous without a separate coverage-divergence check (the guard
variable's own `if` at concolic_targets.rb:529 IS the divergence point by
construction — there is no other code between the not_found decision and
the branch).

### persisted-gate — PASS (with a correction to the docstring's own
description)

Guard: `(SYM_RESULT_ActiveRecord__Relation_to_ary_1_row_persisted == True)`
— the MAIN notification-list representative's persisted flag
(`concolic_targets.rb:501-511`). Two runs:

- **Foreclosing** (forced `False`, `dump_plain_t2_pf_dse0001.json`): 23 PCs.
- **Recording** (forced `True`, `dump_plain_t2_pt_dse0001.json`): 27 PCs —
  the foreclosing side's 23 plus 4 new: `count_3_count < 4`, `count_3_count
  == 0`, `count_4_count == 0`, `count_4_count == 1`.

I originally hypothesized the foreclosed exprs would be OTHER `_persisted`
companions on the same representative (`assoc_author_persisted`,
`assoc_target_persisted`) — **that hypothesis was wrong**: both appear on
BOTH sides (belongs_to/`SingularAssociation` reads, e.g. `note.author`/
`note.target`, are unaffected — confirms `BUGFIXES_20260819.md`'s bug-1 fix
is `CollectionAssociation`-specific, exactly as documented there). The
REAL foreclosed family is the has_many-*through* `actors`/
`notification_actors` collection's `count_records`-derived PCs (the
`ConcolicIntValue`/i18n-pluralization chain `notifications_helper.rb:70`
depends on for "N others" text).

Coverage-divergence evidence (`_t2_cov/t2_pf.json` vs `_t2_cov/t2_pt.json`,
diffed by `(file, line) -> hit_count`):

- `targets.rb` lines **593/594/596/597** diverge — exactly the §gen2
  `CollectionAssociation#size` coerce shim (`if !find_target? || loaded?
  then super elsif ... count_records else super end`, lines 589-605): the
  foreclosing run takes the `super` branch (line 593, hit 2x, never reaches
  594/596/597); the recording run takes the `count_records` branch (594/
  596/597 hit, 593 never hit).
- `activerecord/associations/collection_association.rb` lines **212/213/
  287-293** diverge — the exact lines `BUGFIXES_20260819.md` bug-1 cites
  (`null_scope?`/`none!` scope build, `collection_association.rb:286-294`).
- `activerecord/associations/has_many_association.rb` lines **63/66/72/74**
  (`count_records`) diverge: **0 hits on the foreclosing side, 2 on the
  recording side** — i.e. the recording site literally never executes when
  unpersisted.

Both mechanical DISCIPLINE_TESTS.md requirements are satisfied: (a) the
sets first diverge inside the guard's own mechanism (the size shim /
`null_scope?` build, both directly downstream of the `persisted?` decision
— no divergence found upstream of that in either file); (b) the foreclosed
expr's recording-site lines (`has_many_association.rb:63-74`) are a subset
of the recording side and disjoint from the foreclosing side.

The classifier's `_same_class` (`if "_persisted" in gv: return
"persisted-gate"`) matches ANY `b` once the guard var name contains
`_persisted`, not just my hand-picked example — the auto-derivation logic
itself is validated by this probe even though my first guess for `B` was
wrong. That correction is exactly why the probe requirement exists.

### tier0-type-exclusivity — PASS (sanity check)

Required even though Tier 0 is "sound by construction": one representative
pair, type 0 (`liked`, target=Post) vs type 4 (`mentioned`,
target=Mention). Disjoint sets confirmed: type 0 uniquely mints
`assoc_author_persisted`/`assoc_target_persisted`/
`assoc_target_text_has_mention`; type 4 uniquely mints
`assoc_mentions_container_persisted`/
`assoc_mentions_container_text_has_mention`.

Aside (not a violation, a documented non-finding): type 0 vs type 1
(`liked` vs `reshared`) produced **identical** PC sets in this scenario —
both route through the same `opts_for_post` helper shape per `targets.rb`'s
own §5f comment ("both route through notifications_helper.rb's
opts_for_post branch"), so that pair is correctly NOT a Tier0 example
(Tier0 only declares pairs whose observed sets are actually disjoint —
liked/reshared aren't, for these particular exprs, and coverage_assumptions
.py's real corpus-driven `build()` would simply not emit that pair either).

### count-chain — BLOCKED, not probed

`_same_class` declares `count-chain` when the GUARD variable's name
contains `_count` (and doesn't already match `_persisted`/`not_found`/
same-var first). I looked for a genuine instance where a `_count`-named
variable forecloses a DIFFERENT expr's recording site in this entrypoint's
default scenarios and did not find one within the available time — the
`count_3`/`count_4` foreclosure I DID find (see persisted-gate above) is
gated by `_persisted`, not by another count var, so it classifies as
persisted-gate, not count-chain. Added to `_T2_BLOCKED_CLASSES` in
`coverage_assumptions.py` so no count-chain pair is auto-declared for
variant_b, whatever the real corpus's counts say once generated. If a
genuine example turns up when the full corpus is built, this is a
straightforward follow-up (unblock + probe it the same way as
persisted-gate).

### one-sided (Tier 2) — BLOCKED, not probed

Tried two seeds: (1) the default scenario, (2) `SYM_NOTE_TYPE_PROFILE=4`
(`mentioned`) with `assoc_mentions_container_text_has_mention` forced
`True` (the seed that should most plausibly reach a comment/mention anchor
route). Neither run recorded the `_guid != StringVal('')` expr form at all
— only the syntactically different `_guid == ''` comparisons appeared.
Recorded as inconclusive (the recording site the assumption targets was
never reached by any probe run), not as a failure of the assumption
itself. Per DISCIPLINE_TESTS.md ("or the probe is inconclusive and the
assumption stays undeclared"), `coverage_assumptions.py`'s
`_T2_ONE_SIDED_PROBED_OK` is set `False`, so this class is never declared
for variant_b regardless of what the eventual corpus's raw counts show.

## Cross-check against the control's independent (argument-only) analysis

The control batch's own `REPORT.md` (an earlier, gen2-era, 4547-dump
snapshot — see `RESULT.md` §4 for why variant_b's corpus is larger)
independently describes, by ARGUMENT alone (no executable probe), the
exact same two mechanisms this probe found mechanically: "count_3==0 → no
count_4 (the two `actors.size` reads...)" and "unpersisted list row → no
actors counts at all (flipped `_persisted` → Rails `null_scope?` → the
size shim's concrete arm — the count mock never fires)." This is a useful
cross-validation in BOTH directions: the control's argument-only claim
was correct (T2's stricter bar did not overturn it, for this class), and
the mechanical probe independently arrived at the identical mechanism
without reading that report first — the persisted-gate section above was
written from the probe's own dual-run evidence, then checked against the
control's prose afterward.

## Net T2 verdict

Two of four Tier-1/Tier-2 classes get a real, mechanically-verified PASS
(finder-arm, persisted-gate) plus the required Tier-0 sanity check; two
(count-chain, one-sided) are honestly reported as not probed within budget
and are blocked from auto-declaration in `coverage_assumptions.py` rather
than carried forward on the old corpus-count-only standard. The
persisted-gate probe additionally caught and corrected a wrong mechanism
hypothesis before it could be documented as fact — exactly the kind of
error the discipline addendum's executable-probe requirement exists to
catch.
