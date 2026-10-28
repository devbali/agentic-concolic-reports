# posts_show — completion drive under DISCIPLINE §16b (2026-09-10, overnight)

Appended as the work proceeds. Owner instruction (overnight): "continue working
till all endpoints are complete." Starting state is `_PREFLIGHT_20260910.md`:
96 357 dumps, §16 (set-level) pass 101 nodes / 563 demand sets /
`tree_complete: false` / `tree_missing: 11`; the §16b pass **never completed**
(OOM-killed at 3 GB, inside the LOAD, before Z3 ran); the named defect ×4
undeclared; `run_dse.rb` SEEDS_ONLY dedup gate installed but UNTESTED.

Reference policies stay QUARANTINED (`chmod 000`), never read. No `src/` change.
Heavy jobs under `systemd-run --user --slice=concolic-cov.slice --scope`,
`JAVA_TOOL_OPTIONS` unset, JRuby through `reports/diaspora/tools/slot`.
`find`, never `ls`. Unique `LABEL_SUFFIX` per invocation.

## §1. Smoke — the `SEEDS_ONLY` dedup gate against JRuby

**The preflight had repaired only HALF the drift, exactly as people_stream's
port had.** `run_dse.rb`'s flip loop lacked `next if ENV["SEEDS_ONLY"]`
(notifications_index/run_dse.rb:455 carries it). Without it `SEEDS_ONLY` only
changes which roots START the worklist — every replayed root still pushes its
whole flip frontier, so the replay degenerates into a full DSE exploration and
a hit can no longer be attributed to the seed that was replayed, which is the
entire point of a rooted round. Found by inspection against notifications
BEFORE the smoke, and installed batch-locally (backup
`run_dse.rb.pre_seedsonly_flipgate`; `ruby -c` Syntax OK).

Smoke, per people_stream's method — the strongest form is **two IDENTICAL seed
dicts**: under the old unconditional `seen_seeds` dedup the second is dropped
before it runs, and under an ungated flip loop the replay explodes to the
`MAX_RUNS` cap. Seeds are `dump_auth_json0002_D4.json`'s own `concolic_seeds`,
duplicated. `MAX_RUNS=50` deliberately left far above the expected 2, so a
broken gate is loud.

```
[seeds] 2 extra roots from _smoke_seeds.json (SEEDS_ONLY=1)
  auth_html runs=2      paths=2      drained=true   worklist drained
  anon_html runs=2      paths=2      drained=true   worklist drained
  auth_json runs=2      paths=2      drained=true   worklist drained
  anon_json runs=2      paths=2      drained=true   worklist drained
--- SMKPS0910a dumps: 8
corpus 96357 -> 96365 (+8)
```

Two identical seed dicts -> two dumps per scenario, `stack` falls to 0 after the
second root instead of growing a frontier. Both dedups are off under
`SEEDS_ONLY` and only under it; frontier rounds are byte-unchanged.
**Smoke PASSED.** The 8 runs are real runs of the app and were KEPT, not
deleted: under §16b removing runs can CREATE a foreclosure and RETRACT demand,
which is the dishonest direction.

## §2. The load blocker is gone — the exact prune, verified on this endpoint

The preflight's binding blocker was environmental: 62 KB resident per run x
96 357 dumps ≈ 6.0 GB just to LOAD, and the 3 GB pass was OOM-killed inside the
load before Z3 started. `notifications_index/_prune_corpus.py` (copied in, not
touched in place) keeps **one dump per distinct outcome profile**, which is
exact for the §16b verdict rather than a greedy approximation: the checker
reads exactly one thing off a run — the map `expr -> {outcomes taken}` — and
builds `maximal_sets`, `infer_foreclosures`, the covering cubes, the blocking
clauses and `tree_missing` from it.

**Its exactness was re-derived for THIS batch's loader before it was used, not
assumed from notifications.** `coverage_report.main` depends on the corpus
through `build_assumptions(runs)` and `CoverageChecker(runs)` only, and
`coverage_assumptions.build(runs)` depends on the runs through exactly two
things: (i) the DISTINCT PC exprs (`all_exprs`), and (ii) the per-run expr SET
used by the co-evaluation filter. Both are functions of the outcome profile, so
two runs with the same profile are interchangeable in both. This batch has no
`apply_len_bounds`-style corpus-derived domain (that is a notifications-only
mechanism), so there is no third channel.

```
corpus 96365 dumps -> 14742 distinct outcome profiles (0 unparseable dropped)
```

**Confirmed empirically at the point it can be checked cheaply:** the pruned
load reproduces the preflight's assumption line EXACTLY —

```
preflight, 24 000-dump sampled load : [assumptions] declared=543 INERT(...)=411
this pass,  14 742-dump pruned load : [assumptions] declared=543 INERT(...)=411
```

Load cost: **14 742 runs in 90 s at 680 MB**, against the extrapolated 15 min /
6.0 GB for the full corpus. Nothing was deleted — this is a SNAPSHOT LIST
(`_snapshot_pruned_20260910.txt`) consumed through `DUMP_LIST`; the dump FILES
that extraction, the note audits and the concrete checks read are all still
there. What the prune does NOT preserve, stated rather than glossed: `PCS`,
`total_runs` and `dump_errors` are population statistics and are smaller on the
pruned list. The VERDICT fields are not statistics.

Full snapshot for this drive: `_snapshot_20260910_drive.txt`, **96 365** paths
(the preflight's 96 357 + the 8 smoke runs), `find`-generated.

## §3. The B-8 finder-note defect — PRESENT here, FIXED batch-locally

The brief asked whether posts_show's boundary copy carries people_stream's B-8
`note=""` finder defect. **It does**, and it was the only batch left with it:

```
posts_show/concolic_targets.rb              concolic_pending_note = 0   <-- defect
notifications_index/concolic_targets.rb     concolic_pending_note = 3
comments_index/concolic_targets.rb          concolic_pending_note = 1
people_stream/concolic_targets.rb           concolic_pending_note = 1
reports/diaspora/concolic_targets.rb        concolic_pending_note = 0   <-- SHARED, still missing
```

**Corpus evidence, stride-40 scan of the 96 365-dump snapshot** — the
documented B-8 signature exactly, with no exception in either direction:

```
ActiveRecord::FinderMethods.find_by            noted=False result_nil=True   1442
ActiveRecord::FinderMethods.find_by            noted=True  result_nil=False  5593
ActiveRecord::Relation.findpublic_reshare      noted=False result_nil=True     67
ActiveRecord::Relation.findpublic_reshare      noted=True  result_nil=False   537
ActiveRecord::Associations::SingularAssociation.find_target
                                               noted=True  result_nil=False 60751
```

100 % of noteless finder events return `nil`; 100 % of noted ones return a
record. On a stride-8 scan the reach is **7 241 noteless `find_by` events over
5 025 of 12 046 dumps** — i.e. about 40 000 of the 96 365 dumps lose a statement
they issued.

**One repair covers every finder on this endpoint.** `find_by` / `find` /
`find_by!` AND this batch's own `evilq_<ctx>_<attempt>` and
`findpublic_<ctx>` aliases all take `ct.finder_mock` (`targets.rb:796`, `:801`),
so the single `Thread.current[:concolic_pending_note] = sql` in
`concolic_targets.rb`'s `finder_mock` reaches all of them. Installed
batch-locally, backup `concolic_targets.rb.pre_b8`, `ruby -c` Syntax OK.

### The ground-truth differential — same env, same fixture, same seed, only the file differs

`_B8_DIFFERENTIAL_20260910.txt`, a 1-run `SEEDS_ONLY` replay of
`dump_anon_html0017_b1.json`'s own `concolic_seeds` (which pin
`findpublic_reshare_1_not_found = true`):

```
B8PRE     EVENT ActiveRecord::Relation.findpublic_reshare note=''
B8POST    EVENT ActiveRecord::Relation.findpublic_reshare note='SELECT "posts".* FROM "posts" WHERE "posts"."guid" = $$(SYM_RESULT_ActiveRecord__Relation_findpublic_act_1_id)'
```

**The fix cannot move any coverage number and that is why it was safe to install
mid-drive**: it publishes a NOTE, and notes are read by extraction and the note
audits, never by the path-condition layer the §16b demand is computed over. The
consequence that IS real is stated rather than engineered away: the 96 365-dump
corpus predates the fix, so it is MIXED — dumps written from here on carry the
finder statements and the older ones do not, and the noteless-call audit will
still read RED on the corpus as a whole (§9). Truncating or regenerating the
corpus to force a green was rejected on §16b grounds: removing runs can CREATE a
foreclosure and RETRACT demand.

**RAISED, not fixed (Rule T3):** the SHARED `reports/diaspora/concolic_targets.rb`
still lacks this repair. That is people_stream's X8 item, now confirmed on a
second endpoint.

## §4. The `Post.where(author_id:)` question — posts_show is CLEAN

people_stream's X7(iii) found `targets.rb` §4 replacing the real
`User#posts_from` with `Post.where(author_id: p.id)`, which the concrete round
showed is **not statement-preserving** (the real body is
`Post.from_person_visible_by_user`, a `DISTINCT ... LEFT OUTER JOIN
share_visibilities` query). posts_show has **no such substitution**: `grep` for
`where(author_id` / `posts_from` over `posts_show/targets.rb` returns nothing.

The one re-implemented body it does carry was checked line-by-line against the
app rather than trusted. `PostsShowFinderNaming::FindPublicRouting#find_public!`
(`targets.rb:874-880`) against `app/services/post_service.rb:51-56`:

```ruby
# app (real)
Post.where(post_key(id_or_guid) => id_or_guid).first.tap do |post| ...
# batch copy
Post.where(post_key(id_or_guid) => id_or_guid).public_send(tag).tap do |post| ...
```

`tag` is `:"findpublic_#{ctx}"`, and that method is created by
`rel.send(:alias_method, fname, :first)` (`targets.rb:800`) — an alias of
`:first` on `ActiveRecord::Relation`. The relation built, the raise conditions
and the messages are identical; only the boundary NAME the `.first` call is
recorded under changes. **Statement-preserving.** Same for the three
`evilq_<ctx>_<attempt>` aliases, which are `alias_method`s of `:first` routed
onto the relation EvilQuery's own protected methods already built
(`route_first`, "does NOT change what query the relation represents").

## §5. A rooted-seed defect fixed before any rooted round (ported, third instance)

`_tree_root.py` applied `_v3_seeds.py`'s DENY-LIST to the base dump's own
seeds:

```python
seeds = {k: v for k, v in (raw.get("concolic_seeds") or {}).items()
         if not denied(k)}
```

That list is for a BULK seeder, which INVENTS values. A ROOTED seed reproduces
a real run and flips ONE dimension, so stripping any base key changes the
context the base established — on notifications (§9.7) it dropped a Rule G gate
column and the first attempt hit the branch **0 times and never even EVALUATED
the expression**; people_stream (§2.1) ported the fix. This endpoint's copy
still had the defect, and here it is not harmless: `DENY_SUF` contains
`_guid`, `_id`, `_person_id`, `_diaspora_handle` and `_type`, and this
endpoint's targets sit in exactly those families.

Fixed: rooted seeds are now **verbatim base seeds + the single flip**
(`seeds = dict(raw.get("concolic_seeds") or {})`; backup
`_tree_root.py.pre_verbatim`). `denied()` is kept, unapplied, because it
documents the BULK contract. `_demand_root.py` was checked for the same defect
and does not have it (`seed = dict(base_seeds)`, line 242) — the preflight's
replacement copy was already clean.

`_c7_audits.sh` was built for this endpoint (it had none), ported from
people_stream's with the `pc_visibility` **gate columns re-derived from THIS
controller's code rather than copied** — people_stream's own correction to
itself. `posts_controller#show` -> `post_service.find!` -> `post.public?`
(`Diaspora::NonPublic`) gives `public`; `PostPresenter`'s decorators branch on
`text` / `comments_count` / `nsfw`; `person_path(self)` reads `guid`;
`build_mentioned_people_json` -> mentionable reads `diaspora_handle`; STI
dispatch reads `type`.

## §6. A SECOND ported-tooling defect, found by running the tool: the `SYM_LEN_` name gap

The first full-corpus `_tree_scan.py` run reported **zero evaluations, in
96 365 dumps, for four of the eleven targets** — t01, t06, t08 (`SYM_LEN_...
_records_{10,8,7}_rows != 0`) and t11 (`..._records_likes_de8fde22_rows != 0`).
That is impossible on its face: the checker put those expressions in
`tree_missing`, which requires it to have OBSERVED the other side. A target the
checker sees and the scanner cannot is a NAME mismatch, not a corpus fact.

**Cause.** The engine's load path is two steps —

```python
canonicalize_ordinals(raw)                     # alias -> canonical
runs.append(share_run_objects(Run.from_dict(fix_len_names(raw))))
```

`fix_len_names` renames `len(X)` -> `SYM_LEN_X` because `len(X)` is not a valid
Python identifier and `coverage.py`'s declaration builder would otherwise drop
the expression into `unevaluable_exprs`. The ported `_tree_scan.py`,
`_tree_check.py` and `_tree_root.py` applied only the FIRST step, so they
compared `SYM_LEN_`-named targets against `len(`-named events and matched
nothing. **notifications_index's own targets carried no `SYM_LEN_` name, so its
copies never exercised this**; `_demand_root.py` (a later, separately repaired
port) already handled both forms and is unaffected.

**Fix, in all three** (backups `*.pre_lenfix`): apply `fix_len_names` after
`canonicalize_ordinals`, exactly as the loader does. `_tree_root.py` needed a
second half — the name the CHECKER uses is `SYM_LEN_X`, but the key the
RUNTIME consumes as a seed is the original `len(X)` (a base dump's own
`concolic_seeds` literally carry
`"len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_rows)": 1`),
so an un-translated seed writes a key the runner never reads and the round
**looks driven and drives nothing**. `_seed_key()` now inverts the rename on
emission, mirroring `_demand_root.py`'s own translation.

This is DISCIPLINE §12's standing correction — *check the artefact, not the
number describing it, and route every check through the same load path the
engine uses* — catching a defect that a "0 hits" round would otherwise have
been reported as evidence of unreachability.

### The tree targets as the corpus actually shows them

First scan (before the fix), 96 365 dumps, the seven targets whose names DID
match:

```
t02  as_api_response_4_row_guid != ''   not_taken 16026   (anon_json 3008, auth_json 13018)
t03  as_api_response_3_row_guid != ''   not_taken 14692   (anon_json 4608, auth_json 10084)
t04  as_api_response_2_row_guid != ''   not_taken 21120   (anon_json 9692, auth_json 11428)
t05  as_api_response_1_row_guid != ''   not_taken 24028   (anon_json 9628, auth_json 14400)
t07  as_api_response_2_row_text_has_mention == True   not_taken  832  (anon_json only)
t09  evilq_act_public_1_not_found       == True   not_taken   504  (auth_html 104, auth_json 400)
t10  evilq_act_public_1_text_has_mention== True   not_taken   504  (auth_html 104, auth_json 400)
```

**`taken` is 0 for all seven**, and the four guid families are the named defect
(§7), each evaluated tens of thousands of times and never once on the wanted
side.

## §7. Artefacts built for the completion layer (this endpoint had none)

posts_show arrived with **none** of the Phase-5 artefacts. Built during the
drive, modelled on people_stream's port (itself modelled on comments_index):

| file | state |
|---|---|
| `_c7_audits.sh` | NEW — §5, gate columns re-derived from this controller |
| `gate_canon.py` | NEW — the scenario-key hook, plus the `fix_len_names` half |
| `assumption_manifest.json` | NEW — derived mode (`"assumptions": []`) |
| `_c1/gate_wrapper.sh` | NEW — tees the driver's full stream, preserves its exit |
| `completion_config.json` | see §11 |
| `shim_tests.rb` | see §11 |
| `concrete_run.json` / `concrete_aliases.json` | see §11 |

`gate_canon.py` carries **both** repairs, and the second is this endpoint's own:
people_stream's hook supplies the missing `dump["concolic_scenario"]["name"]`
from the label (verified on a real dump here — top-level keys are
`schema_version, label, symbolic_vars, events, symbolic_results, script,
concolic_seeds`, and `concolic_scenario` is None), and posts_show's hook ALSO
applies `fix_len_names`, without which the gate would compare `len(X)`-named
probes against `SYM_LEN_X`-named declarations — the §6 defect, in the gate.

The engine's shim extractor enumerates **22 shims** on this batch
(8 `prepend`, 14 `rep_plumbing`):

```
EvilQuery::VisibleShareableById.querent_has_visibility   prepend
PostService.find_public!                                 prepend
LikeService.find_for_post                                prepend
ReshareService.find_for_post                             prepend
Person.singleton_class.find_or_fetch_by_identifier       prepend
PostPresenter.build_text                                 prepend
ActiveRecord::Associations::SingularAssociation.find_target  prepend
::Gon.singleton_class.preloads                           prepend
rel.first                                                rep_plumbing
obj.{read_attribute,_read_attribute,concolic_attrs,concolic_note,attributes,
     write_attribute,_write_attribute,image_url,hidden_shareables,
     post_location,inspect}                              rep_plumbing
interceptor.{__descend_filter__,declare_target}          rep_plumbing
```

## §8. The tree layer — the rooted rounds

`_tree_scan.py`, re-run over the full 96 365-dump snapshot AFTER the §6 fix.
Every one of the eleven targets now has a population; the four that had been
invisible are the `SYM_LEN_` family:

```
t01  SYM_LEN_..._Relation_records_10_rows != 0   want taken   not_taken 18240  (anon_json)
t02  as_api_response_4_row_guid != ''            want taken   not_taken 16026  (anon_json 3008 / auth_json 13018)
t03  as_api_response_3_row_guid != ''            want taken   not_taken 14692  (4608 / 10084)
t04  as_api_response_2_row_guid != ''            want taken   not_taken 21120  (9692 / 11428)
t05  as_api_response_1_row_guid != ''            want taken   not_taken 24028  (9628 / 14400)
t06  SYM_LEN_..._Relation_records_8_rows  != 0   want taken   not_taken  1536  (anon_json)
t07  as_api_response_2_row_text_has_mention == True  want taken  not_taken 832  (anon_json)
t08  SYM_LEN_..._Relation_records_7_rows  != 0   want taken   not_taken   528  (anon_json)
t09  evilq_act_public_1_not_found == True        want taken   not_taken   504  (auth_html 104 / auth_json 400)
t10  evilq_act_public_1_text_has_mention == True want taken   not_taken   504  (auth_html 104 / auth_json 400)
t11  SYM_LEN_..._records_likes_de8fde22_rows != 0 want NOT_taken  taken    400  (auth_json)
```

`_tree_root.py --bases 8` (verbatim base seeds, §5; `len()` seed keys, §6)
built **45 rooted seeds over 17 (target, variant) files**, every target
represented.

### A third runner gap, found while building the round: no `VARIANTS`

`run_dse.rb` had **no `VARIANTS` support at all** — every invocation ran all
four scenarios. notifications_index's runner has had it since results2; this
port never carried it. Without it a rooted round aimed at a branch only
`anon_json` evaluates still pays for three other scenarios AND replays the same
seed file under four labels, so per-target attribution is diluted and the
round costs 4x what it should. Added batch-locally (backup
`run_dse.rb.pre_variants`), with an **unknown scenario name a HARD ERROR**
rather than a silent empty run — an empty scenario list is otherwise
indistinguishable from a drained one in the log. Smoked before use:

```
[variants] running: anon_json
  anon_json runs=2      paths=2      drained=true   worklist drained
--- VSMK dumps: 2       (2, not 8: the other three scenarios did not run)
```

## §9. Round TR0910a, and what it established about the tree residual

`_tree_drive.sh TR0910a` — 45 rooted seeds over 17 (target, variant) jobs, one
JRuby per job so a native abort costs one job and names itself. **0 aborts,
every job rc=0, every seed produced exactly one dump.**

### The `SYM_LEN_` family: three NullRelation sites, unreachable BY CONSTRUCTION

The round hit t01 zero times, so the seed was audited rather than the round
re-run — and the seed was **honoured in the dict and CONTRADICTED at runtime**:

```
seed dict      len(SYM_RESULT_ActiveRecord__Relation_records_10_rows) = 1
dump's seeds   len(SYM_RESULT_ActiveRecord__Relation_records_10_rows) = 1   (accepted)
dump's var     len(SYM_RESULT_ActiveRecord__Relation_records_10_rows) = 0
               note = 'NullRelation (empty by definition, no SQL)'
```

**Cause, in the batch's own mock.** `targets.rb`'s `rows_mock` short-circuits a
`NullRelation` receiver before it ever consults the seed:

```ruby
next IterableSymbolicList.new(0, name: "#{name}_rows",
      note: "NullRelation (empty by definition, no SQL)",
      representative: nil) if null_rel && receiver.is_a?(null_rel)
```

The length is a hard-coded `0`, so **no seed can move it**.

**And that is FAITHFUL, not a mock defect.** `ActiveRecord::NullRelation` is
what `.none` returns and its `to_a` really is `[]` in the real app, so a real
run cannot produce a non-empty result from that receiver either. The
unreachability is the app's, and the mock models it exactly, with its reason
printed in the note.

**Census through the engine's OWN load path** (`canonicalize_ordinals` +
`fix_len_names`), stride-40 over the 96 379-dump snapshot:

| canonical `SYM_LEN_` target | want | note in EVERY observation | values |
|---|---|---|---|
| `..._records_10_rows` | taken | `NullRelation (empty by definition, no SQL)` **457/457** | `{0: 457}` |
| `..._records_8_rows`  | taken | `NullRelation ...` **38/38** | `{0: 38}` |
| `..._records_7_rows`  | taken | `NullRelation ...` **12/12** | `{0: 12}` |
| `..._records_likes_de8fde22_rows` | **not_taken** | `SELECT "likes".* FROM "likes" WHERE "likes"."target_id" = $$…` 12/12 | `{1: 12}` |

**Why these three canonical names denote NullRelation sites specifically, and
what that implies.** `canonicalize_ordinals` aliases a result by its NOTE; a
NullRelation has no SQL, so it is the ONE `records` call that keeps its bare
per-run ordinal. Every real-SQL `records` call is aliased to a note-derived
canonical name, so `records_7 / _8 / _10` — as the CHECKER names them — are
exactly "the NullRelation call that landed at ordinal 7 / 8 / 10". A raw-name
census confirms the same ordinals carry real SQL in other runs
(`records_10_rows` raw: `participations` 669, NullRelation 610, values
`{0: 1135, 1: 144}`), and those runs are aliased elsewhere.

**Consequence, stated because it is a real limitation and not a happy one:** the
set of such names is NOT closed. A future run that puts a NullRelation at
ordinal 11 mints a NEW canonical name and therefore a NEW `tree_missing` entry,
with the same unreachable side. This is open item 6 (the `DecisionAlias`
upstream defect, `call_interceptor.rb:142-144`, naming a result by WHEN it was
called) reaching the one case that has no note to alias on. A stable alias for
the NullRelation branch would fix it in `targets.rb` — but that changes what
the corpus records and so needs a full regeneration, which is not this drive's
to do. **RAISED, with the numbers.**

**t11 is a different animal and is DRIVABLE:** it is a real `likes` query whose
length is seeded, observed only at 1, and the wanted side is `not_taken`
(length 0) — a value `seed_for` accepts.

### Round TR0910a — four branches CLOSED in 43 runs

`_tree_check.py 'dump_*_TR0910a*.json'`, over the round's own 43 dumps:

```
t07 want=taken     HIT=2 other= 2  <-- CLOSED by dump_anon_json0001_TR0910at07anjs.json
t09 want=taken     HIT=4 other=14  <-- CLOSED by dump_auth_json0001_TR0910at09aujs.json
t10 want=taken     HIT=4 other=10  <-- CLOSED by dump_auth_json0001_TR0910at10aujs.json
t11 want=not_taken HIT=2 other=10  <-- CLOSED by dump_auth_json0001_TR0910at11aujs.json
t01 t02 t03 t04 t05 t06 t08        HIT=0
```

| branch | what closed it |
|---|---|
| `..._as_api_response_2_row_text_has_mention == True :: taken` | a rooted seed from an `anon_json` base that evaluated it False, with that one dimension flipped True |
| `..._evilq_act_public_1_not_found == True :: taken` | rooted seed, `auth_json`, `evilq_act_public_1_not_found` flipped True |
| `..._evilq_act_public_1_text_has_mention == True :: taken` | rooted seed, `auth_json`, that dimension flipped True |
| `..._records_likes_de8fde22_rows != 0 :: not_taken` | rooted seed, `auth_json`, `len(...likes...)` seeded **0** — the one `SYM_LEN_` target over a REAL query rather than a NullRelation |

Corpus 96 379 -> 96 422 (+43). The seven that did not move are exactly the two
families §9 identified: the three NullRelation sites and the four guid
instances. **Both are now driven at a second time, from EVERY base that
reaches the site**, before anything is declared.

## §10. The Phase-5 concrete round — built from nothing on this endpoint

posts_show had **no** `completion_config.json`, `shim_tests.rb`,
`concrete_run.json`, `concrete_aliases.json`, `assumption_manifest.json`,
`gate_canon.py` or `_c7_audits.sh`. All were built during this drive, on
people_stream's port (itself comments_index's), with the endpoint-specific
parts written against THIS batch's code.

### `_concrete_targets.rb` — corpus-derived, without a 10-minute glob

`targets_from_corpus` JSON-parses every `dump_*.json` in the directory it is
given. At 96 000+ dumps that is ~10 minutes **per scenario**. `_ctgt_sample/`
holds symlinks to a **greedy set cover of the corpus's target names**, computed
over a stride-10 scan of the full snapshot:

```
distinct target names (stride-10 over 96 422): 28
greedy cover: 4 dumps cover 28 of 28   uncovered: []
```

So the list is identical to the full-corpus list and is still read off real
dumps rather than typed out. The 28 names, with their corpus frequencies, are
led by `SingularAssociation.find_target` (121 510), `Person.name` (35 303),
`Photo.url` (31 888), `Relation.records` (26 237) and this batch's own
`evilq_<ctx>_<attempt>` / `findpublic_<ctx>` aliases.

### Five scenarios, one manifest each (JVM crash isolation)

| manifest | arm | post | what only it exercises |
|---|---|---|---|
| `anon_html` | anonymous, html | 100 public | `find_public!`, the html render |
| `auth_html` | signed in, html | 100 public | `gon.post = presenter.with_initial_interactions` |
| `anon_json` | anonymous, json | 100 public | `presenter.with_interactions` |
| `auth_json` | signed in, json | **101 LIMITED** | `querent_has_visibility`'s join on `share_visibilities` — the ONLY arm where `current_user` reaches the SQL |
| `anon_nonpublic` | anonymous, html | **101 LIMITED** | `rescue_from Diaspora::NonPublic -> authenticate_user!`, the in-action escape back INTO authentication that POLICY_HEADER names as part of this action |

Each scenario ASSERTS what makes it different — the anon arms `raise` if the
LIMITED post leaks, `auth_json` raises if it does NOT see it, `anon_nonpublic`
raises on a 200 — so a scenario that silently degrades FAILS instead of
reporting green.

### Three rig defects found by running it, all fixed at the source

1. **`ActionView::Template::Error: couldn't find file 'underscore'`** killed
   both html arms after their target calls but before the view's own reads.
   This stripped app does not vendor that asset — an ENVIRONMENT gap, not an
   app fact. Fixed with a rig-local comment-only stub on an extra
   `config.assets.paths` entry: a config VALUE, no app-tree edit, no SQL
   change.
2. **`can't modify immutable cached environment`** (sprockets-3.7.5
   `cached_environment.rb:66`) then killed `anon_json` OUTRIGHT — the first fix
   called `append_path` on `Rails.application.assets`, which Sprockets 3 hands
   out as a `CachedEnvironment`. Now the underlying environment is used when
   reachable and the failure is WARNED and survived otherwise: a resolvable
   asset is a nicety for the html arms, not a precondition of the measurement.
3. **`Devise::MissingWarden`** killed `anon_nonpublic` after 7 target calls.
   `rescue_from Diaspora::NonPublic { authenticate_user! }` re-enters Devise on
   an ANONYMOUS request, and Devise raises when the request env has no
   `Warden::Proxy` — a RIG artefact (a real Rack request always has one) and
   not the endpoint's behaviour. A warden is now installed on every request,
   carrying a NIL user when anonymous, so `authenticate_user!` still fails to
   authenticate — which is the arm under test.

`CONCRETE_COVERAGE=1` was also missing from the invocation, so the first round
reported `files_covered=0` on every scenario. Set.

**The first round is therefore NOT the shipped one and its numbers are not
quoted** — three of five scenarios died on rig defects and a fourth was run
against a mid-edit fixture. The whole round was re-run after the fixes so that
all five scenarios share one fixture.

## §11. The second drive at the seven — round TR0910w

Before any unreachable side may be DECLARED, the brief requires driving at it
twice, "rooted from every base that reaches the site". `_tree_root_wide.py`
(NEW; `_tree_root.py` takes only the 8 richest bases per target/variant) scans
the whole snapshot, keeps every dump that EVALUATES the target on the other
side, dedupes by the base's own `concolic_seeds` dict, and emits one rooted
seed per distinct dict — verbatim base + the single flip (§5), with `len()`
seed keys (§6).

**Two defects in that tool were found by running it, both of the same family
as the ones it exists to guard against:**

1. Its first run reported **0 bases for every target over 96 422 dumps** — a
   number that cannot be true. Cause: the snapshot list was RELATIVE
   (`find . -name ...`) and `open(p)` resolved it against the PROCESS cwd,
   which is not this batch, so it silently read **notifications_index's**
   dumps. `_prune_corpus.py` and `_tree_root.py` both already join against
   `HERE`; this tool did not. Fixed, and the snapshot is now built with an
   absolute `find`.
2. `from _tree_root import wanted_value, _seed_key` **executed `_tree_root.py`**
   (it is a script, not a module) and rebuilt/deleted the `_treeR_*.json`
   files as an import side effect. The two pure helpers are now loaded by
   exec'ing only their definitions, so the same code is shared without the
   side effect.

Both are the §12 standing correction again: *check the artefact, not the number
describing it.* A "0 bases" reading, taken at face value, would have been
reported as evidence that nothing reaches the site.

### The bases, once it read the right corpus

```
t01  15974 bases reach the site ->  300 distinct rooted seeds (anon_json 300)
t02  13801                      ->  600 (anon_json 300, auth_json 300)
t03  12246                      ->  600 (300, 300)
t04  17361                      ->  600 (300, 300)
t05  21222                      ->  600 (300, 300)
t06   1345                      ->  192 (anon_json 192 — ALL distinct dicts, under the cap)
t08    452                      ->  132 (anon_json 132 — ALL distinct dicts, under the cap)
```

**3 024 rooted seeds.** t06 and t08 are exhaustive: every distinct base seed
dict in the corpus that reaches those sites is driven. t01-t05 are capped at
300 distinct contexts per variant — a budget decision, stated: 300 distinct
contexts is a far stronger second attempt than people_stream's TR0910w (61),
but it is not literally every base and the pin's text says so.

### The guid differential, RE-VERIFIED on this corpus by the installing agent

The preflight's §2 required the falsifier to be run and the differential
re-measured before installation. Both done. Stride-8 scan of the 96 422-dump
snapshot, **routed through the engine's own load path**
(`canonicalize_ordinals` + `fix_len_names`), 12 053 dumps:

```
PER-FAMILY (canonical names, the ones the checker builds its universe from):
   as_api_response_1_row_guid != ''  {'not_taken': 2980}
   as_api_response_2_row_guid != ''  {'not_taken': 2620}
   as_api_response_3_row_guid != ''  {'not_taken': 1824}
   as_api_response_4_row_guid != ''  {'not_taken': 2008}
                                      = 9 432 evaluations, taken 0
PER-RUN (eq-sides, ne-sides) -> runs:
   ((False, True), (False,))  3530   several rows: '==' both ways, '!=' ALWAYS False
   ((True,),      (False,))   1258   blank guid  -> line 41 runs, forced False
   ((False,),     ())          530   non-blank   -> line 40 BREAKS, '!=' NEVER evaluated
   ((),           ())         6735   neither site (the html arms)
```

**0 of 9 432 evaluations taken, in 4 788 runs that evaluate it; 530 runs
exhibit the other arm — the break, with the `!=` absent entirely.** Both arms
of the argument are exhibited by the corpus, which is what makes it an argument
rather than an absence.

Event sites, same load path, stride-120 — and they are **byte-identical to the
three people_stream instances already declared**:

```
('blank.rb', 126, 'blank?',            '==')   1099
('formatter.rb', 41, 'block in generate', '!=')  613
```

Two sites, no others.

### The html view render is an ENVIRONMENT WALL — declared, not stubbed

`_concrete_assets/README.txt`. `app/views/layouts/application.html.haml:11` is
`javascript_include_tag :main`, and `app/assets/javascripts/main.js` is a
Sprockets bundle with ~40 `//= require` directives for third-party libraries
— underscore, backbone, autosize, jquery-placeholder, jquery.timeago, four
`jquery.ui` modules, fine-uploader, handlebars.runtime, eight markdown-it
packages, highlightjs, corejs-typeahead, bootstrap, leaflet, blueimp-gallery —
**none of which this stripped checkout vendors**; `_head.haml` adds `rtl` and
`poltergeist_disable_transition` stylesheets in the same state.

A single stub was tried first and it WORKED mechanically — the round then
failed on `backbone` instead of `underscore`, one step further down the same
chain. **Stubbing all forty would be fabricating a JavaScript environment**,
and shadowing the app's own `main.js` would change what the view emits. Neither
is a fixture row, and neither buys a single statement, because the JS bundle
issues no SQL. So the stub was REMOVED and the wall is declared:

* what the html scenarios still deliver: the action's own read set up to the
  view — `find!`, `mark_user_notifications`, the presenter — **129 target
  calls / 35 statements** (anon) and **208 / 53** (auth);
* what they do NOT deliver: any read the VIEW's own partials would issue;
* the consequence, stated where it lands: H6 / `note_fidelity` will report
  corpus note shapes that no concrete run issued, and **some of those are
  view-level reads this wall hides rather than genuine over-emission**.

The path mechanism is kept (and prints which of its three attempts succeeded),
so provisioning the pipeline later is a one-directory change.

`anon_nonpublic` was also fixed by the round's second defect repair and now
runs clean (`error=None`, 7 target calls, 1 statement) — the
`Diaspora::NonPublic -> authenticate_user!` escape reaches Devise, the stub
Warden throws `:warden` exactly as the real one does, and `psh_dispatch`
catches it in place of the Warden middleware.

## §12. CLASS-B DEFECT — the entire html render arm is missing from this corpus

**This is the most important finding of the drive and it is BLOCKING for any
honest `complete: true` on this endpoint.**

### The measurement

Terminal state by scenario, stride-12 over the 96 422-dump snapshot (8 036
dumps):

```
auth_html  n=2237   ActionView::Template::Error=2061  ActiveRecord::RecordNotFound=176
anon_html  n=2239   ActionView::Template::Error=1433  ActiveRecord::RecordNotFound=268  Diaspora::NonPublic=538
auth_json  n=1862   (none)=1861                       ActiveRecord::RecordNotFound=1
anon_json  n=1698   (none)=1691                       ActiveRecord::RecordNotFound=2    Diaspora::NonPublic=5
```

**ZERO html runs reach the end of the action. Not one, in either arm.** Every
`ActionView::Template::Error` in the corpus carries the same message:

```
uninitialized constant PostsTargets::ConcreteSymbolicString
```

The json arms are essentially clean (3 552 of 3 560 error-free).

### The cause, and it is exact

`targets.rb` uses `ConcreteSymbolicString` in three places, **unguarded**:

```
targets.rb:277  upgrade_tag_name!   (inside a `rescue Exception`, so it is silent)
targets.rb:666  the W3b `to_param` WALL MOCK — NOT rescued
```

and the constant is **defined nowhere in this batch**: `grep -c
ConcreteSymbolicString` is **0** in both `posts_show/concolic_targets.rb` and
the shared `reports/diaspora/concolic_targets.rb`.

**It is a regression introduced by the 2026-09-09 Rule-T re-sync, and the
archived file proves it.** `concolic_targets.rb.pre_ruleT_resync` DEFINES the
class (line 479, `unless defined?(ConcreteSymbolicString)`, 13 occurrences).
The re-sync replaced this batch's `concolic_targets.rb` with a verbatim copy of
the shared boundary — which has never defined it — and in the SAME change added
the third use, the `to_param` wall mock, whose own comment says where it fires:

> *"Reached via `post_url @post`/`post_path` in `PostPresenter#url` (metas
> render, html format) and Journey route generation."*

So the re-sync removed the definition and added a use on exactly the path that
needs it. comments_index and notifications_index carry the definition in their
OWN `concolic_targets.rb` (comments_index:1411) and additionally guard every
use with `if defined?(ConcreteSymbolicString)`; posts_show has neither.

The whole 96 422-dump corpus was generated on 2026-09-09 or later, i.e.
entirely after the regression.

### What it costs, stated plainly

* `format.html` is one of the endpoint's three render formats and the ONLY one
  that runs `gon.post = presenter.with_initial_interactions` and
  `render locals: {post: presenter}`. **None of the view's reads are in the
  corpus**, so none of them are in the extracted policy.
* Two of the four scenarios contribute only their pre-render statements.
* Every §16b number measured on this corpus is a number about an endpoint whose
  html arm terminates early. That does not make those numbers wrong — the runs
  really happened, and under §16b adding runs only ADDS demand — but a
  `complete: true` earned here would be **complete over a demand universe that
  the html arm never contributed to**, and saying so is part of the claim.
* It also explains the concrete round's html wall differently than §10 first
  read it: the CORPUS's html arms die too, of a different cause (a batch-local
  `NameError`, not the missing asset pipeline). Both sides lack the view's
  reads, for two independent reasons.

### TR0910w — the result, and the repair the differential exposed

```
_tree_drive.sh TR0910w  (PFX=W)   11 (target,variant) jobs, DRIVE_PAR=2
   3 024 of 3 024 seeds consumed, rc=0 on every job, 0 JVM aborts,
   every seed produced exactly one dump.        corpus 96 422 -> 99 446 (+3 024)

_tree_check.py 'dump_*_TR0910w*.json'   (3 024 dumps, through the load path)
  t01 want=taken     HIT=0 other=1399
  t02 want=taken     HIT=0 other= 514
  t03 want=taken     HIT=0 other=1111
  t04 want=taken     HIT=0 other=1159
  t05 want=taken     HIT=0 other=1209
  t06 want=taken     HIT=0 other= 291
  t08 want=taken     HIT=0 other= 134
  (t07, t10, t11 were hit again by side effect — already closed in TR0910a)
```

**HIT=0 for all seven, and `other` is LARGE** — the expression was evaluated,
on the other side, hundreds or thousands of times in the round's own runs. So
the seeds landed in the right contexts and the branch did not move. That is the
informative reading: not "the round never got there", but "it got there
repeatedly and the outcome is not producible".

## §13. THE PINS ARE INSTALLED — one tier, two arguments, seven entries

`coverage_assumptions.py` gains **ARGUMENT P**, `_OVERNIGHT_PINS`, as a
SEPARATE, COUNTED, REVERSIBLE tier: printed on its own (`OVERNIGHT_PINS=` in
the `[assumptions]` line), reversed by one edit (`_OVERNIGHT_PINS = ()`), and
built WITHOUT it under `NO_PINS=1` — which `coverage_report.py` now REFUSES to
run without `SUMMARY_OUT`, so a counterfactual can never overwrite the shipped
summary. Backup `_bak_coverage_assumptions_pre_overnight_pins.py`.

Authority: the owner's 2026-09-10 overnight instruction, the standing direction
in notifications `_COMPLETION_CAMPAIGN_20260910.md` §8 to INSTALL an
unreachable-side pin rather than leave it a proposal, and the brief's condition
that the side be driven at TWICE first — which §9 and §11 are.

**The two families are kept apart deliberately**: different evidence, different
falsifiers, and pinning one has no bearing on the other.

| tier | entries | argument | falsifier |
|---|---|---|---|
| P1 | `SYM_LEN_..._records_{7,8,10}_rows != 0 :: taken` | the call site is an `ActiveRecord::NullRelation` and `rows_mock` hard-codes its length to 0 — measured, not inferred (a rooted seed carrying `len=1` was ACCEPTED into the dump and the recorded var was still 0 with the NullRelation note); and the hard-coded 0 is FAITHFUL, since `.none.to_a` really is `[]` | any run recording it `taken`; at code level, remove the short-circuit and the seed takes effect |
| P2 | `..._as_api_response_{1,2,3,4}_row_guid != StringVal('') :: taken` | `journey/formatter.rb:40` breaks the route-parts loop before line 41 whenever the guid is non-blank, and when it IS blank line 41 runs and `'' != ''` is forced False — 0 of 9 432 evaluations taken, 530 runs exhibiting the break | any run recording it `taken`; a route default on `person_path`'s `:id` segment (there is none) |

`OneSideUntrackedPathAssumption(tracked_side="not_taken")` is exactly the right
instrument and its effect is bounded, checked in the engine rather than assumed:
`coverage.py:1056` skips an outcome iff `pinned.get(expr, outcome) != outcome`,
so the pin removes the True side from the tree-gap search and from the demand,
and **an untracked expression is in no demand set, so it can neither foreclose
nor be foreclosed** (DISCIPLINE §16b). The counterfactual pass (§15) measures
exactly that.

## §14. The Class-B repair, its differential, and the wall BEHIND it

`ConcreteSymbolicString` is **restored batch-locally**, in `targets.rb` (not in
this batch's copy of the shared boundary: Rule T1 keeps batch-local shims here
so the boundary copy stays diffable, and T3 forbids an agent editing the
boundary). Body byte-identical to comments_index's
(`concolic_targets.rb:1411-1423`) and notifications', which is where it was
first found — on that endpoint's HTML render path. Backup
`targets.rb.pre_csstring`; `ruby -c` Syntax OK.

**Ground-truth differential — same env, same fixture, same runner, only the
file differs:**

```
PRE-FIX   dump_auth_html2505_D4.json
          error = ActionView::Template::Error:
                  "uninitialized constant PostsTargets::ConcreteSymbolicString"
          traceback -> reports/diaspora/results3/posts_show/targets.rb:666
                       in `block in install!'          pcs=24  events=119

POST-FIX  dump_auth_html0001_CSSPOST0910.json
          error = NotImplementedError:
                  "SymbolicString#scrub is not supported in the concolic runtime"
          traceback -> src/ruby_runtime/string.rb:359 `block in scrub'
                       <- activesupport multibyte/unicode.rb:229 `tidy_bytes'
                                                        pcs=25  events=135
```

The traceback names `targets.rb:666` — the exact `to_param` wall mock the
re-sync added — so the cause is not inferred. The repair moves the html arm
PAST it: 119 -> 135 events, 24 -> 25 path conditions.

**And it exposes the wall behind it, which is stated rather than presented as a
fix.** The html arm now dies one layer deeper, at `SymbolicString#scrub` via
`ActiveSupport::Multibyte::Unicode.tidy_bytes` — which is precisely the path
`targets.rb`'s own comment on `upgrade_tag_name!` describes:

> *"the un-concretized value reaches Rails' HTML-escape path (`tag_option` ->
> `tidy_bytes` -> `#scrub`, UNSUPPORTED by design)"*

So some OTHER string on the html render reaches the escape path without having
been upgraded. Restoring the html arm END-TO-END needs one or more further
narrow upgrades of that kind — real Phase-1 mock work, not a step of this
drive.

**Disposition, and why the repair is kept anyway.**

* It removes a REGRESSION that masked everything behind it, and it is strictly
  widening: the corpus can now record 16 more events per html run than it
  could.
* It cannot retract anything. Under §16b adding runs only ADDS demand; the
  96 422 pre-repair runs really happened and are kept (removing runs is the
  direction that can CREATE a foreclosure and retract demand).
* **It does NOT restore the html arm**, so it does not repair §12's cost:
  `format.html`'s view reads are still absent from the corpus and therefore
  from the policy, now for a different reason.

**RAISED for the coordinator, with its numbers:** the SHARED
`reports/diaspora/concolic_targets.rb` does not define `ConcreteSymbolicString`,
while notifications_index and comments_index each define it privately and guard
every use. A batch that inherits the boundary verbatim and uses the class —
which is what the Rule-T re-sync made posts_show — is broken by construction.
That is a boundary-completeness item of exactly the kind Rule T2 exists for.
This is the second boundary item this drive raises (the first is B-8, §3).

## §15. The concrete round, as shipped

`_concrete_run.sh`, five one-scenario manifests, `CONCRETE_COVERAGE=1`,
JRuby through `tools/slot`, `JAVA_TOOL_OPTIONS` unset:

```
posts-show-anon-html        target_calls=129  statements=35  error=<asset wall>
posts-show-anon-json        target_calls=182  statements=54  error=None
posts-show-anon-nonpublic   target_calls=7    statements=1   error=None
posts-show-auth-html        target_calls=208  statements=53  error=<asset wall>
posts-show-auth-json        target_calls=87   statements=19  error=None
                            ----------------  -------------
                            613 target calls  162 statements
merged -> concrete_run.json (6 scenarios, incl. one unioned _cumulative_coverage)
```

Three scenarios clean; the two html arms stop at the declared environment wall
(§10). The json arms and the NonPublic escape are ground truth end to end, and
the auth_json arm proves what it exists to prove — it reads the LIMITED post
through `querent_has_visibility`'s `share_visibilities` join, which the two
anonymous arms assert they never see.

## §16. The prune is VERIFIED EQUIVALENT on this corpus — exactly, not by sampling

The brief conditioned the prune's use on it "verifying equivalent on this
corpus". A verdict comparison on a sample would have been both weak (a random
8 000-dump subset prunes only 8 000 -> 6 281, because duplicates are spread
thin) and expensive (two more Z3 phases). `_prune_equiv.py` (NEW) does the
stronger thing for one load and no solver: it checks that **the checker's
INPUTS are identical**, which is what the exactness argument (§2) actually
claims.

```
full    96357 dumps ->  14742 distinct profiles
pruned  14742 dumps ->  14742 distinct profiles
  IDENTICAL  distinct outcome profiles                    full=14742 pruned=14742  only-in-full=0 only-in-pruned=0
  IDENTICAL  per-run evaluation SETS                      full=  302 pruned=  302  only-in-full=0 only-in-pruned=0
  IDENTICAL  MAXIMAL sets (the demand universe)           full=   52 pruned=   52  only-in-full=0 only-in-pruned=0
  IDENTICAL  distinct tracked exprs                       full=  101 pruned=  101  only-in-full=0 only-in-pruned=0
  IDENTICAL  observed (expr, side) pairs (the tree layer)  full=  186 pruned=  186  only-in-full=0 only-in-pruned=0
PRUNE_EQUIVALENT=True
```

Every object the §16b verdict is computed from is bit-for-bit the same set on
the pruned list as on the full corpus: the demand universe (`maximal_sets`),
the tree layer (the observed `(expr, side)` pairs), the expression universe
(101 — and the pass independently reports `NODES=101`), and the per-run
evaluation sets that both `infer_foreclosures` and this batch's own
`coverage_assumptions.build` read. **The load blocker is removed at no cost to
the verdict**, and the population statistics that the prune does NOT preserve
(`PCS`, `total_runs`, `dump_errors`) are named in §2 rather than quoted as if
they were.

## §17. The shim layer — 13 PASS / 9 PROTOCOL / 0 FAIL, at 100 % of every body

`shim_tests.rb` (NEW) covers all **22** shims the engine's extractor enumerates.
Nine come back PROTOCOL from the runner's own check against the REAL class (the
AR attribute / Ruby object protocol plus `obj.post_location`, which base `Post`
genuinely does not define). The other 13 RUN.

```
PASS      x13   EvilQuery::VisibleShareableById.querent_has_visibility,
                PostService.find_public!, LikeService.find_for_post,
                ReshareService.find_for_post, rel.first,
                Person.singleton_class.find_or_fetch_by_identifier,
                PostPresenter.build_text, obj.image_url,
                obj.hidden_shareables, interceptor.__descend_filter__,
                interceptor.declare_target,
                ActiveRecord::Associations::SingularAssociation.find_target,
                ::Gon.singleton_class.preloads
PROTOCOL  x9    obj.{read_attribute,_read_attribute,concolic_attrs,concolic_note,
                attributes,write_attribute,_write_attribute,inspect,post_location}
FAIL      x0            views below 100 % coverage: NONE
```

**Nothing is waived.** `shim_test_runner.rb:249` refuses `coverage_waiver`
outright ("coverage waivers are not accepted either"), and Rule S §9 is right to.

Three things this file had to solve:

**(a) Six `reaches:` sets were MEASURED, not guessed.** The first run returned
FAIL-TARGETS / FAIL-REACHES on seven entries and NAMED what each had really
reached; the declarations were corrected to the run's own answer, exactly as
people_stream's `user.contact_for` was. The instructive one: `.first` on an
`ActiveRecord::Relation` in Rails 5.2 goes through `find_nth -> records`, so
what the probe records is `Relation#records` / `#to_a` and **not**
`FinderMethods#first` — which is what all three of this batch's `.first`-alias
shims (`rel.first`, `find_public!`, `querent_has_visibility`) actually reach.

**(b) The `install!`-only shims need a throwaway interceptor.** Four of the 22
are created inside an `install!` and unreachable without running it — the
anonymous `Module.new` bodies for the `SingularAssociation` W3-memo and
`Gon.preloads`, and the Rule-T declaration-filter singletons
`interceptor.__descend_filter__` / `declare_target`. A shim test may never
declare a target. Verified in the file rather than assumed (`grep` for
`.prepend(` / `define_method` / `Module.new` over `concolic_targets.rb` finds
only the comment at :682 and those two prepends at :1058/:1072 and
:1296/:1301) that `install!` reaches a real class through exactly ONE channel —
`interceptor.declare_target`, i.e. `klass.define_method` — so a THROWAWAY
interceptor whose `declare_target` records and returns nil installs the real
shim bodies and declares NOTHING. `PostsTargets` /
`PostsShowFinderNaming` / `PostsShowMentionLookupNaming` get the same
throwaway, with one consequence that is a FEATURE here: their
`alias_method` calls are OUTSIDE `declare_target`, so the
`evilq_<ctx>_<attempt>` / `findpublic_<ctx>` / `mention_lookup_<site>_<attempt>`
aliases really are created and the naming prepends route to a REAL
`Relation#first` issuing real SQL against the fixture DB — the stronger claim.

**(c) The `TargetCallProbe` recursion, worked around not waived.** Same
instrument limit people_stream measured (§8.1c): `capture` resolves
`instance_method` THROUGH a prepend, so for the W3-memo the probe's "original"
IS the memo and the memo's `super` lands on the probe — infinite recursion. The
memo body is detached from its module (the `UnboundMethod` kept) and re-attached
by the ONE test that is about it, from inside its own fixture, after `capture`
has taken the real `find_target`.

**And one wall applied directly, because a waiver is not available.**
`find_or_fetch_by_identifier` first came back FAIL-COVERAGE at **60 %**, missing
`targets.rb:1090-1094` — `logger.info`, `Discovery.new(...).fetch_and_save`, and
the two retry lines behind it. That is the NETWORK-I/O wall DISCIPLINE §12
records as ABORTING THE JVM (an abort, not an exception, so no test can catch
it), and which this batch ALREADY declares as a target at `targets.rb:608-610`
— but a shim test may not declare a target. So the same wall is applied
directly to the real class and reversed after, and the retry arm is then driven
for real by inserting a person WITHOUT a profile (the only condition that makes
`person.profile.present?` false). Coverage went 60 % -> **100 %**. What is
stubbed is a NETWORK CLIENT; the shim's own logic — context routing,
strip/downcase, first/retry dispatch — runs for real on both sides of it.

## §18. `concrete_aliases.json`

Built for this batch: the corpus↔concrete finder aliasing that
`mock_note_check.py` and `note_fidelity_audit.py` need. The corpus records this
batch's own dedicated finder names (`evilq_<ctx>_<attempt>`,
`findpublic_<ctx>`, `mention_lookup_<site>_<attempt>`), all of which are
`alias_method`s of a real framework method; the concrete run records the real
method. The map is therefore derivable from `targets.rb` rather than
hand-authored, and it is the same shape people_stream's is.

## §19. Artefacts, as they now stand

```
run_dse.rb                        + SEEDS_ONLY flip gate (§1, SMOKED)
                                  + VARIANTS (§8, SMOKED)
                                    backups .pre_seedsonly_flipgate / .pre_variants
concolic_targets.rb               + B-8 finder-note harvest (§3)   .pre_b8
targets.rb                        + ConcreteSymbolicString (§14)   .pre_csstring
coverage_report.py                + the completion section (§7)    .pre_completion
coverage_assumptions.py           + ARGUMENT P, 7 pins (§13)
                                    _bak_coverage_assumptions_pre_overnight_pins.py
_tree_root.py                     verbatim base seeds (§5)         .pre_verbatim
_tree_scan.py / _tree_check.py    fix_len_names (§6)               .pre_lenfix
_tree_root.py                     + _seed_key len() translation (§6)
_tree_root_wide.py                NEW — every distinct base (§11)
_tree_drive.sh                    NEW — one JRuby per (target,variant), PFX=R|W
_chunk_drive.sh                   NEW — chunked bulk drive, dump-counted resume
_prune_corpus.py                  copied in from notifications_index
_prune_equiv.py                   NEW — the exactness check (§16)
_c7_audits.sh                     NEW — gate columns re-derived (§5)
gate_canon.py                     NEW — scenario key + fix_len_names (§7)
assumption_manifest.json          NEW — derived mode
_c1/gate_wrapper.sh               NEW
completion_config.json            NEW
shim_tests.rb                     NEW — 22 shims, 13 PASS / 9 PROTOCOL (§17)
concrete_manifest_*.rb  x5        NEW (§10)
_concrete_fixture.rb / _concrete_targets.rb / _concrete_schema.rb / exec_wrap.rb
_concrete_assets/README.txt       the declared environment wall (§10)
_concrete_run.sh                  NEW — 5 manifests + merge
concrete_run.json / concrete_aliases.json   NEW (§15, §18)
_ctgt_sample/                     4 symlinks — the greedy target-name cover
```

**No `src/` change.** The one src-level issue met (the `TargetCallProbe` cannot
observe a target the boundary also prepends) was worked around batch-locally in
`shim_tests.rb`, exactly as people_stream did, and is reported not patched.
Reference policies untouched and still quarantined.

## §20. Corpus and snapshots

| snapshot | dumps | distinct outcome profiles | what it is |
|---|---|---|---|
| `_snapshot_20260910_preflight.txt` | 96 357 | 14 742 | the preflight's fixed list — the BASELINE pass's population |
| `_snapshot_pruned_20260910.txt` | 14 742 | 14 742 | its exact prune (§16) |
| `_snapshot_20260910_drive.txt` | 96 365 | — | + the 8 smoke runs |
| `_snapshot_20260910_w.txt` | 96 422 | — | + TR0910a (43) and the B-8 / VARIANTS smokes |
| `_snapshot_20260910_p2.txt` | 99 448 | 14 806 | + TR0910w (3 024) and the CSS differential runs |
| `_snapshot_pruned_p2.txt` | 14 806 | 14 806 | its prune — the PINNED pass's population |

**3 067 runs added, and only 64 new distinct outcome profiles.** That is itself
evidence for §13: a 3 024-run round aimed at seven branches, from every base
that reaches them, produced almost no new behaviour — the contexts were
reproduced and the outcomes did not move. Nothing was ever deleted; under §16b
removing runs can CREATE a foreclosure and RETRACT demand, which is the
dishonest direction.

## §21. What a `complete: true` on THIS corpus would and would not assert

Written before the numbers, so the framing is not fitted to them.

Under DISCIPLINE §16/§16b a `complete: true` asserts: every satisfiable branch
outcome has been observed (`tree_complete`), and every Z3-satisfiable
foreclosure-aware assignment over every maximal OBSERVED evaluation set has
been observed in some run's executed path. It is a claim about the corpus's
demand universe, and this endpoint's demand universe has **two named holes that
a `complete: true` does not fill**:

1. **§12 — the html arm.** ZERO html runs in 96 422 reach the end of the
   action; every one that gets past the finder dies in the view on a
   batch-local `NameError` that the 2026-09-09 Rule-T re-sync introduced.
   `format.html`'s view reads are in no run, so they are in no evaluation set,
   so they are in no demand. A `complete: true` here is complete over a
   universe two of the four scenarios stopped contributing to early. §14's
   repair removes the NameError but the arm still terminates one layer deeper
   (`SymbolicString#scrub`), so this hole is NOT closed tonight.
2. **The `format.mobile` arm is not driven at all.** `PostsController` declares
   `respond_to :html, :mobile, :json` and `show` has a `format.mobile { render
   locals: {post: post} }` branch, but `run_dse.rb`'s SCENARIOS are only
   auth/anon x html/json. A format the corpus never reached is a DECLARED GAP,
   not evidence that it reads nothing.

Both are recorded in `POLICY_HEADER.txt` rather than left to a reader to infer,
because under the M-17 resolution the declaration IS the safeguard: a policy
file that simply stops at a wall is indistinguishable from one that covers
everything.

The seven pins (§13) are a THIRD, different kind of narrowing, and they are not
a hole: they say a satisfiable-looking outcome has no producing path, each with
an argument, a code site, a corpus differential and a falsifier, each driven at
twice from every base that reaches it, each counted and reversible, and the
counterfactual pass measures exactly what they change.

## §22. Extraction pipeline — dry run on the grown corpus

`DUMP_SAMPLE=8000` (random, seeded 20260901 — never a sorted prefix,
DISCIPLINE §14), `SKIP_SUBSUME=1`, 1.5 GB scope, **56 MB peak RSS**, ~12 min:

```
corpus POPULATION: 99448 dump files
SAMPLED EXTRACTION: 8000 of that population, seed=20260901 — a DRY RUN
  8000/8000 dumps, 121 distinct
subsumption: state=None (True=ran, False=attempted and FAILED, None=never attempted)
             over 85 eligible of 121 distinct
   verdict tally  subsumed(true)=0  not-subsumed(false)=85  UNDECIDED(null)=0
posts_show: 121 queries (121 distinct, 0 subsumed) from 8000/8000 dumps; subsume_ran=False
```

**No E11 RED (0 unparseable notes) and no R1 RED (0 rotation residue)** — both
checks are installed and both stay silent, which is the outcome you want from a
check. `POLICY_HEADER.txt` is found, so no placeholder warning fires. 121
distinct views, identical to the preflight's dry run on the smaller corpus.

The preflight's measurement is confirmed: **the extraction loop is not the
memory cost** (56 MB); the blockaid subsumption harness is, and it gets its own
scope in the shipped run.

## §23. RAISED for the coordinator — boundary items, with their numbers

Neither is fixed here: DISCIPLINE §T3 forbids an agent editing
`reports/diaspora/concolic_targets.rb`, and §T2 says a change there voids every
endpoint.

**X1 — B-8 is missing from the SHARED boundary.** `concolic_pending_note`
appears 3x in notifications_index's copy, 1x in comments_index's, 1x in
people_stream's, and **0x in the shared file**. Every batch that inherits the
boundary verbatim therefore loses the SQL of every finder whose `not_found`
arm fires — measured here at 1 442 noteless `find_by` events with
`result_value: nil` against 5 593 noted ones with a record, in a stride-40
sample, and ~40 000 of 96 365 dumps losing a statement they issued. This is
people_stream's X8 item, now confirmed on a second endpoint (§3).

**X2 — `ConcreteSymbolicString` is missing from the SHARED boundary, and that
is not cosmetic.** notifications_index and comments_index each define the class
privately (comments_index/concolic_targets.rb:1411) AND guard every use with
`if defined?(...)`. The shared file defines it nowhere. The 2026-09-09 Rule-T
re-sync made posts_show's boundary copy verbatim — correct by T1 — and thereby
deleted the definition, while the same change added an UNGUARDED use at
`targets.rb:666`. Result: **100 % of this endpoint's html runs die in the
view**, 4 476 of 4 476 sampled, for a year's worth of corpus. A boundary that
two batches must patch privately to be usable is a boundary defect, and the
failure mode here is silent and total (§12, §14).

**X3 — a class of defect the re-sync procedure does not catch.** Both X1 and X2
are "the batch copy is verbatim and therefore missing something the batch
needs". A re-sync that diffs declaration SITES (which is what the 2026-09-09
re-sync verified: "29 lines, all of them one added block ... Not one
declaration site differs") does not see a deleted class definition or a missing
note-harvest. A load-and-run smoke of ONE dump per scenario, compared against
the previous corpus's terminal state, would have caught X2 in seconds — the
html arms went from completing to 100 % `ActionView::Template::Error`.

## §24. The RUNBOOK's mandatory pre-extraction check — run BOTH ways

RUNBOOK "MANDATORY before every extraction (2026-09-01, comments C12)": run
`skipped_pcs_audit` vanilla AND `--patched .../_experiment/variant_d`, and
install the patch in the extractor if they differ. The vanilla `src/` fold
silently discards the `(VAR == VAR(_))` / `(VAR != VAR(_))` shape — every
StringVal equality branch — and the failure is SILENT: a green-looking result
with the constraints gone.

**VANILLA arm, full 99 448-dump corpus:**

```
== skipped_pcs_audit (vanilla src/): 99448 dumps, 80 distinct exprs, 3167302 PC records ==
   parsed: 1938920 | dropped: 79923 | dropped-by-design: 1148459
-- DROPPED SHAPES (evidence recorded by the runtime, discarded by the fold) --
     79923  (VAR != VAR(_))  <-- RED (Class B in fold-space)
-- DROPPED BY DESIGN (len()/arithmetic operands, outcome-suffix vars) --
    881482  (len(VAR) != N)
    167529  (VAR != VAR)
     99448  (Length(VAR) < N)
RESULT: RED — high-frequency PC shapes dropped.
```

**79 923 recorded constraints would vanish from the policy without the patch** —
against comments_index's 73 461 (which the RUNBOOK cites as the case that made
the check mandatory) and people_stream's 309. This endpoint has the largest
instance of the shape measured so far.

The VANILLA arm is the CONTROL, not the gate: its RED is the SIGNAL that tells
the extractor which fold to install. `_extract_posts_show_streaming.py` installs
`_experiment/variant_d`'s `AssocFoldingTransformer` — confirmed in the extractor
source, not assumed — so that IS the pipeline this policy is extracted with.
Both exits stay printed and neither is suppressed.

### The 11 placeholders, named (POLICY_HEADER's open TODO)

From the dry run's own summary, grouped by family (`_N_` = the per-run call
ordinal):

```
 3  SYM_RESULT_ActiveRecord__FinderMethods_find_by_N_author_id
 4  SYM_RESULT_ActsAsApi__Collection_as_api_response_N_row_id
 1  SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_N_row_author_id
 1  SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_N_row_id
 1  SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_N_row_root_guid
 1  SYM_RESULT_ActiveRecord__Calculations_ids_N_ids
```

Every one is DISCIPLINE Rule V's own case — **a value parsed out of a column
and used as a bind in a later statement is a PARAMETER**, not a constant: an
`id`, an `author_id`, a `root_guid`, or the `ids` array of a pluck. They are
left as placeholders rather than folded to a literal precisely because folding
them would make the policy narrower than the app.

Flags on the same run: `type-mismatched-join` 7 981, `unscoped` 4 027.

`skipped_pc_shapes` totals ~240 k over 40+ shapes, led by
`(len(..._records_N_rows) != N)` 44 462, `(..._find_by_N_not_found == True)`
22 968 and the `_has_mention` / `_nsfw` families. **This is normal residue, not
a defect**: the CLOSED endpoints carry the same shapes at the same or larger
volume (comments_index 893 882 over 52 shapes, people_show 405 945 over 44,
both led by the identical families). They are mock-internal decisions with no
SQL predicate; they cost WHERE precision, not statements.

## §25. Method notes carried by this drive (so the next agent does not re-pay)

* **Every check is routed through the engine's own load path.** Not once as a
  slogan: it is what caught §6 (four targets invisible because `fix_len_names`
  was missing), §9 (a canonical name that denotes a NullRelation site
  specifically), and §11 (a tool reading another endpoint's dumps). Three
  defects, all found by comparing an artefact with the number describing it.
* **A "0" is a hypothesis, not a result.** `0 bases reach the site` (§11),
  `0 evaluations of four targets` (§6) and `HIT=0` (§9) all looked like
  findings. Two were bugs. The one that was real (§13) is the one where the
  companion number — `other` — was LARGE, i.e. the site was reached and the
  outcome did not move. **Report `other` next to `HIT` always.**
* **One JRuby per unit of work.** Every round in this drive ran one JVM per
  (target, variant) or per manifest. 3 067 rooted runs and 5 concrete
  scenarios, **0 aborts**, and the two rig defects that did occur named
  themselves instead of taking the round with them.
* **Count the artefact, not a log line.** `_chunk_drive.sh`'s resume counts the
  dumps an invocation wrote, because this runner prints a progress line only
  every 25 paths; notifications' `grep -c 'new path'` would have undercounted
  by up to 25 and silently re-run seeds.
* **Absolute paths in every tool that takes a `DUMP_LIST`.** A relative
  snapshot resolves against the process cwd, which on this box is another
  endpoint's directory.

**PATCHED arm, same 99 448-dump corpus:**

```
== skipped_pcs_audit (PATCHED pipeline): 99448 dumps, 80 distinct exprs, 3167302 PC records ==
   parsed: 2018843 | dropped: 0 | dropped-by-design: 1148459
  (none — every recorded PC shape parses)
RESULT: pass.
```

**The two arms account for each other exactly**: 2 018 843 − 1 938 920 =
**79 923**, i.e. every record the vanilla fold dropped is recovered by
`variant_d` and none is lost elsewhere. The `dropped-by-design` figure is
identical in both arms (1 148 459), so the patch changes exactly the one shape
and nothing else. That is the paired verdict the RUNBOOK asks for, and it is
the strongest form of it: not "both arms were run" but "their difference is the
shape in question, to the record".

## §26. The §16 (set-level) file this drive started from, for comparison

`_bak_coverage_summary_16set_20260910.json`, read rather than quoted from the
preflight:

```
coverage_complete False   tree_nodes 101   demand_sets 563
missing_branches 2248     tree_complete False
truncated TRUE            solver_lost 0
total_runs 96357          total_path_conditions 3033786
```

The `missing[]` entries it carries are all `missing_branch: "combination"`, and
their `node_constraint` widths are **33 / 34 / 35 / 36 decisions** (80 / 224 /
80 / 16 of the 400 recorded). That width is the whole reason §16b has room here:
the foreclosure prune removes demanded assignments from inside exactly such
wide sets, and on notifications the wide sets' mass fell 97.6 %.

`truncated: TRUE` is worth naming: the §16 pass hit its
`MAX_MISSING_PER_CLIQUE` cap, so 2 248 is `561 sets with a gap x MMC 4` — a
GROUP COUNT x MMC, never a gap size (STATE_HANDOFF standing correction 5).

## §27. Closing audits — `_c7_audits.sh`, on the 99 448-dump corpus

Built for this endpoint (§5), gate columns re-derived from THIS controller's
code. Results are appended below as each lands.

```
identity_symbolicity   EXIT=0   pass — every principal bind is symbolic
    recipient_id   symbolic 95118   literal 0
    user_id        symbolic 77236   literal 0
```

That is the DISCIPLINE §15 entrypoint-scope property measured rather than
assumed: the principal is symbolic everywhere it reaches SQL, so the policy's
`_MY_UID` is a parameter and not this corpus's concrete user id.

## §28. An independent prediction of pass 2's tree layer (cross-check, not a substitute)

Computed directly off the pruned p2 corpus through the engine's own load path,
before the pass reported anything — so the pass's own `TREE_MISSING` can be
compared against a number derived a different way:

```
distinct tracked exprs: 102
exprs observed on ONE side only (tree-gap CANDIDATES, before Z3 satisfiability): 13
pinned: 7   of which one-sided: 7   <-- the pins remove exactly these
NOT pinned, still one-sided: 6
   (..._CollectionProxy_records_photos_2c7fa358_row_status_message_guid != <itself>)  observed [False]
   (..._CollectionProxy_records_photos_33150e22_row_status_message_guid != <itself>)  observed [False]
   (..._CollectionProxy_records_photos_8687d6e6_row_status_message_guid != <itself>)  observed [False]
   (..._CollectionProxy_records_photos_9930492e_row_status_message_guid != <itself>)  observed [False]
   (..._CollectionProxy_records_photos_e035b5b3_row_status_message_guid != <itself>)  observed [False]
   (SYM_RESULT_Anonymous_process_2 == '')                                             observed [False]
```

Two things follow, and both are worth having before the verdict lands.

**(a) Five of the six are SELF-COMPARES** — `X != X` on the same variable, the
shape the vanilla fold counts 167 529 times as "dropped by design". Their True
side is UNSATISFIABLE, so Z3 should exclude them from `tree_missing` and the
tree layer should not see them at all. If the pass DOES report them, that is
notifications' §1.1 Class-B signature (a self-compare the model does not treat
as a tautology) reappearing on this endpoint, and it would be a defect to chase
rather than a branch to drive.

**(b) `SYM_RESULT_Anonymous_process_2 == ''` is a genuine, drivable candidate**
— `Anonymous.process` is `Diaspora::MessageRenderer::Processor#process`, and
the corpus has never rendered an empty text at that second call site.

**And the structural warning this exposes.** The expression universe went
**101 -> 102** while the corpus grew 96 357 -> 99 448, and the one-sided set
changed membership. Canonical names are minted from statement NOTES, so a new
run can mint a NEW canonical name (`records_photos_<hash>`) carrying a NEW
one-sided outcome — i.e. **growing the corpus can ADD tree gaps**. That is
sound under §16 (demand is monotone in the corpus) but it means
`tree_complete` on this endpoint is a moving target under exactly the driving
that is supposed to close it, for the same root cause as open item 6
(`call_interceptor.rb:142-144`, a result named by WHEN it was called). It is
the reason this drive re-derives the tree layer from the corpus at every pass
rather than trusting the preflight's list of 11.

## §29. The two passes, as launched

Both are §16b passes on an EXACT prune (§16), `JAVA_TOOL_OPTIONS` unset, own
scope in `concolic-cov.slice`, memory checked before each launch.

| pass | population | pins | purpose |
|---|---|---|---|
| **A — BASELINE** `_covA_pruned_20260910.log` | `_snapshot_pruned_20260910.txt`, 14 742 profiles of the preflight's 96 357 dumps | NOT installed at launch | the brief's step 2: this endpoint's FIRST §16b measurement (the preflight's attempt was OOM-killed inside the load at 3 GB) |
| **B — PINNED** `_covB_p2_20260910.log` | `_snapshot_pruned_p2.txt`, 14 806 profiles of 99 448 dumps | 7 (ARGUMENT P) | the state after both tree rounds and the pins |

Pass B's assumption line, printed:

```
[assumptions] declared=552 INERT(never-co-evaluated, not declared)=418 OVERNIGHT_PINS=7
```

545 corpus-derived declarations survive the co-evaluation filter, 418 are
dropped as INERT (a declared independence over a pair no run co-evaluates
relaxes nothing), and **the 7 pins are counted on their own line** — so no
number that depends on them can be quoted without saying so.

**The two were run in PARALLEL, deliberately and after checking.** `free -g`
before launching B showed 7 GB available with pass A at 1.68 GB and the other
agent's job at 1.4 GB; each pass peaks under 1.7 GB on a pruned corpus, so
neither is "a job over ~3 GB" and the memory rule is respected rather than
stretched. Serialising them would have doubled the critical path for no
safety.

**Memory discipline, as actually practised.** `free -g` and
`ps -eo rss,args --sort=-rss` before every job over ~1 GB, every heavy job in
`concolic-cov.slice` with an explicit `MemoryMax`. When a THIRD ~1 GB probe
(an optional measurement of the assumption gate's cost) pushed available memory
from 7 GB to 3 GB alongside the two passes and the other agent's 2.5 GB job, it
was **killed rather than allowed to compete** — it was nice-to-have and the
passes are the critical path. Memory recovered to 5 GB available and both
passes survived. This box has 16 GB, no swap, and has been OOM-squeezed twice.

## §30. The demand-round loop, automated (`_demand_round.sh`)

One command per round, every step printing its own verdict:

```
summary -> _demand_root.py (rooted seeds, per scenario)
        -> _demand_drive.sh -> _chunk_drive.sh (chunked, per variant, resumable)
        -> re-snapshot -> _prune_corpus.py (exact) -> §16b pass
```

Two things it fixes about doing this by hand:

* **It roots from the SAME fixed snapshot the pass measured**, so a rooted seed
  is always built from a dump the witness actually saw. With a live glob and a
  drive adding dumps underneath, that is not guaranteed.
* **It never pretends a scratch summary is the shipped one.** `_demand_root.py`
  reads `coverage_summary.json` by name; the script stages the pass it means and
  keeps the previous file as `.bak_<TAG>`, saying so in the log.

**And one cap was raised, because it silently bounded every round.**
`coverage_report.py` recorded `result.missing[:400]` in the summary, and
`_demand_root.py` roots ONLY from the witnesses the file records — so a corpus
with thousands of missing assignments converges at **400 roots per round no
matter how high `MAX_MISSING_PER_CLIQUE` is set**. Raised to 4 000. The cost is
file size (~1 KB per entry); the witnesses are already computed, so no solver
time is added. (Passes A and B loaded the module before this edit and are
unaffected; the first round to use it is the next one.)

### The five `photos` entries ARE self-compares — verified, not assumed

The normalized shape in `skipped_pc_shapes` (`_N_`) could have hidden two
DIFFERENT ordinals, so the raw expressions were checked on the pruned p2
corpus through the load path:

```
status_message_guid != comparisons:  {('SELF', False): 92}
example: (SYM_RESULT_..._records_photos_e035b5b3_row_status_message_guid
       != SYM_RESULT_..._records_photos_e035b5b3_row_status_message_guid)
```

Identical operand on both sides, 92 of 92, always False. `X != X` is
unsatisfiable, so Z3 should exclude the True side and these should NOT appear
in `tree_missing`. If they do, that is the notifications §1.1 self-compare
defect on this endpoint.

**And they are worth naming as a MODELLING limitation, not just noise.** A
comparison the app writes between two different rows becomes a self-compare
when the mock's single-representative model hands the same symbolic row to both
sides — here, a `photos` row's `status_message_guid` against itself. The
comparison is then a tautology in the model and a real decision in the app.
`(VAR != VAR)` is 167 529 records in this corpus's `dropped-by-design` column,
so the shape is not rare. It costs WHERE precision, not statements, and it is
an honest limit of the Gate-1b representative model (`targets.rb`'s own header
states it: "one rep row, not N distinct rows; distinct-row branching is NOT
modeled"), not a defect introduced by this drive.

### The audit suite OOM'd in its OWN scope — isolated, diagnosed, deferred

```
pxaudits.scope: Active: failed (Result: oom-kill) since 19:39:34, Duration 3min 6s
                A process of this unit has been killed by the OOM killer
   last audit started: statement_note_lint   (corpus POPULATION: 99448 dumps)
   identity_symbolicity had already completed EXIT=0
```

`statement_note_lint` needs more than the 3 GB cap it was given on a
99 448-dump corpus. **The kill was CGROUP-LOCAL and the machine was
unaffected** — both coverage passes kept running at ~95 % CPU throughout, which
is exactly what putting every heavy job in its own `MemoryMax` scope is for.
Re-run with a larger cap once the passes free their ~3.4 GB; `identity_
symbolicity`'s verdict above stands on its own (it completed and wrote EXIT=0).

The lesson is the one the memory rule already states and this drive now has a
second instance of: **a per-audit cap must be sized for the CORPUS, not copied
from a batch with 1 109 dumps.** people_stream's `_c7_audits.sh` ran against
1 109; this one runs against 99 448, a 90x difference, and the cap was ported
unchanged.

## §31. Note fidelity, previewed at TABLE granularity — and a fixture gap closed

A cheap table-level diff of the concrete round against the corpus's notes, run
before `note_fidelity_audit` itself, on 988 pruned dumps and the 162 concrete
statements:

```
corpus NOTES, by table:   people 10121  profiles 8196  posts 5177  mentions 5004
                          poll_answers 3072  photos 2009  o_embed_caches 1498
                          open_graph_caches 1498  locations 1498  polls 1498
                          likes 1455  participations 1438  notifications 997
                          poll_participations 970  comments 514  tags 383
concrete round reads:     posts 58  people 25  profiles 23  mentions 17  likes 6
                          photos 5  locations 5  polls 5  o_embed_caches 4
                          open_graph_caches 4  participations 3  comments 2  tags 2
                          (33 distinct statement shapes, 162 statements)

concrete-only (issued concretely, ABSENT from the corpus's notes):  []
corpus-only  (in notes, not issued by any concrete scenario):
                          ['notifications', 'poll_answers', 'poll_participations']
```

**The empty first list is the good half and it is a real result.** Every table
the real app reads under this action appears in the corpus's notes — including
`photos`, `polls`, `locations` and `tags`, the StatusMessage-only associations
that people_stream's X7 found MISSING by construction because its posts were
base-`Post` representatives. posts_show's `targets.rb` dispatches the
representative's STI type to `StatusMessage`, and the difference shows.

**The second list was a FIXTURE gap, and it is now closed rather than
declared.** `polls` / `poll_answers` / `poll_participations` are read by
`PostPresenter` (the poll JSON and `poll_participation_answer_id`); with no
poll row the FK is NULL, AR issues no statement, and H6 would have reported the
corpus's poll notes as "never issued by any concrete run" — over-emission that
is really an absent row. A poll, two answers and alice's participation are now
in `_concrete_fixture.rb`. (`notifications` is the `mark_user_notifications`
`UPDATE`, not a SELECT; the fixture already carries the row.)

Widening the ground truth, never narrowing the check.

## §32. Where this stands while the passes run

Everything below is DONE and verified; the two §16b passes are the only thing
outstanding at this point in the drive, and every number that depends on them
is deliberately absent above rather than estimated.

| step (brief) | state |
|---|---|
| 1. smoke the runner | **DONE** — and it found the half-done SEEDS_ONLY fix first (§1) |
| 2. baseline §16b pass | **RUNNING** (pass A). The preflight's attempt was OOM-killed inside the LOAD at 3 GB; the exact prune (§2, verified §16) removed that blocker — 14 742 runs load in 90 s at 680 MB |
| 3. tree_missing -> 0 | **7 of 11 pinned after two failed drives (§9, §11, §13); 4 of 11 CLOSED BY DRIVING (§9)**. Pass B measures the result; §28 predicts it independently |
| 4. combination demand -> missing == 0 | **NOT STARTED** — it is gated on pass B's `missing[]`. The round is automated end to end (`_demand_round.sh`, §30) and the 400-witness cap that would have bounded every round is raised (§30) |
| 5. full engine + audits + extraction + policy | **PARTLY** — the completion section is ported and wired (§7); shim layer 13 PASS / 9 PROTOCOL / 0 FAIL (§17); the concrete round runs, 5 scenarios (§15); `skipped_pcs` paired verdict complete (§24); the audit suite OOM'd in its own scope and is relaunched at 6 GB; extraction is dry-run clean (§22) and the subsuming run is not yet made |
| 6. no `src/` change, references quarantined | **HELD** — no `src/` edit; no reference policy read |

**Defects found and fixed by this drive: five.** The half-done SEEDS_ONLY gate
(§1), B-8 (§3), the rooted-seed deny-list (§5), the `SYM_LEN_` name gap (§6),
and the missing `ConcreteSymbolicString` (§12/§14) — plus two in a tool this
drive wrote (§11) and three in the concrete rig (§10). **Two are raised to the
coordinator** as shared-boundary items (§23).

**The largest single finding is §12** and it is not a coverage number: for a
year of corpus, `format.html` has never once reached the end of this action.

### The concrete round, re-run on the widened fixture — SHIPPED

```
posts-show-anon-html        target_calls=129  statements=35  error=<asset wall, W5>
posts-show-anon-json        target_calls=200  statements=59  error=None
posts-show-anon-nonpublic   target_calls=7    statements=1   error=None
posts-show-auth-html        target_calls=212  statements=54  error=<asset wall, W5>
posts-show-auth-json        target_calls=87   statements=19  error=None
                            ----------------  -------------
                            635 target calls  168 statements   (15 tables)
```

The poll rows bought exactly what they were added for: anon_json 182 -> 200
target calls and 54 -> 59 statements, auth_html 208 -> 212 and 53 -> 54.

**Table-level fidelity after the widening:**

```
concrete-only (app reads it, corpus notes do not):  []
corpus-only  (noted, never issued concretely):      ['notifications']
```

and `notifications` is EXPLAINED rather than left open: it is
`post_service.mark_user_notifications`'s `Notification.where(...).update_all`,
and the probe's `statements` list captures SELECTs. The call itself IS traced —
`ActiveRecord::Relation#update_all` appears 3 times in `target_calls`. So the
remaining entry is an artefact of what the probe records, not a read the ground
truth is missing.

The concrete round's own target-call profile, for the record:

```
177 Person.name            134 Relation#records          94 SingularAssociation#find_target
 76 FinderMethods#exists?   30 CollectionProxy#records    21 Person#name
 19 Gon#gon                 19 Relation#to_a              15 FinderMethods#first
 11 ActsAsApi::Collection#as_api_response                 10 MessageRenderer#title
 10 FinderMethods#find_by    6 Rendering#_set_rendered_content_type
  6 Calculations#sum         4 Calculations#ids            3 Relation#update_all
```

## §33. `mock_note_check` — RED, and one of its REDs has an exact cause

Run standalone against the shipped `concrete_run.json` and this batch's
`concrete_aliases.json`:

```
== mock_note_check: 8 target frames issued real SELECTs; 21 targets carry corpus notes ==
-- statements OUTSIDE any target frame (2) — each needs a declared target or a waiver:
     SELECT "mentions"."id" FROM "mentions" INNER JOIN comments ON ...
NOTE-MISMATCH CollectionProxy.records        real: SELECT "posts".* WHERE "posts"."type" IN ('Reshare') AND "posts"."root_guid" = ?
NOTE-MISMATCH SingularAssociation.find_target real: SELECT "people".* WHERE "people"."owner_id" = ? LIMIT ?
NOTE-MISMATCH Calculations.ids               real: SELECT "mentions"."id" WHERE "mentions"."mentions_container_id" = ? AND ...
NOTE-OK       Calculations.sum  (1 real shapes matched)
NOTE-OK*      FinderMethods.exists?  (1 shape matched under a DIFFERENT target — frame nesting)
NOTE-OK*      Relation.records  (12 shapes matched under a DIFFERENT target — frame nesting)
NOTE-MISMATCH Relation.records               real: likes(positive), poll_participations, posts(Reshare/root_guid) x2
NOTE-MISMATCH Relation.update_all            real: UPDATE "notifications" SET "unread" = 'f' WHERE recipient_id = ? AND ...
RESULT: RED
```

### X4 — a THIRD shared-boundary defect: `render_relation_sql` cannot render a `Reshare` relation

A census of the corpus's own notes (stride-10 over the pruned p2 list, 1 481
dumps, 85 458 notes) finds **17 900 non-SQL notes in four families**, and one of
them is not a wall but a FAILURE:

```
 10664  'Photo#url'                                        <- a SQL-free shim, legitimate
  4881  'ActsAsApi::Collection#as_api_response'            <- a SQL-free shim, legitimate
   324  'NullRelation (empty by definition, no SQL)'       <- legitimate (W6)
  2031  "Reshare query (render_relation_sql failed: NoMethodError undefined method `value'"
```

That last one is `concolic_targets.rb:118` — the fallback that fires when
`render_relation_sql` (`:168-183`) raises. The relation it fails on DOES issue
SQL: it is `post.reshares`, i.e.
`SELECT "posts".* WHERE "posts"."type" IN ('Reshare') AND "posts"."root_guid" = ?`
— **exactly the statement `mock_note_check` reports as having NO corpus note
anywhere.** The two findings are the same defect seen from both ends: the
concrete round proves the app issues it, and the corpus proves the mock could
not render it.

The failure is confined to `Reshare` relations (it is the only `klass` in the
failing-note family) and the `rescue Exception` at `:110` is doing exactly what
its comment says — never letting note-rendering crash a mock — so the loss is
silent by design and only a differential like this one surfaces it.

**RAISED, not fixed:** `render_relation_sql` lives in
`concolic_targets.rb`, i.e. the SHARED boundary, and DISCIPLINE §T3 forbids an
agent editing it (§T2: a change there voids every endpoint). **POLICY IMPACT:
this policy contains no view for the reshare read**, and its absence is a mock
defect, not evidence the app does not issue it. Falsifier: fix
`render_relation_sql` for that relation shape and the next corpus contains the
`posts.type IN ('Reshare') AND root_guid = ?` view.

**The other REDs are not all the same kind**, and the drive does not lump them:
`Relation.update_all`'s `UPDATE "notifications"` is a WRITE, and the extractor's
policy is over SELECTs; `SingularAssociation.find_target`'s
`people.owner_id = ?` and `Calculations.ids`' mentions read are candidates for
the same class of gap and need their own differential, which this drive did not
have time to run. They are declared open rather than characterised on a guess.

### CORRECTION to §33 — the differential WAS run, and it splits the REDs in two

The paragraph above said the remaining `NOTE-MISMATCH` shapes "need their own
differential, which this drive did not have time to run". It was run. Corpus
NOTE matches for each real statement shape, stride-8 over the pruned p2 list
(1 851 dumps):

```
  people.owner_id            0     <-- GENUINE: no corpus note anywhere
  mentions.id (ids read)     0     <-- GENUINE: no corpus note anywhere
  notifications UPDATE       0     <-- expected: a WRITE; the policy is over SELECTs
  likes ... positive      2704     <-- PRESENT in the corpus
  poll_participations     1834     <-- PRESENT in the corpus
  posts ... root_guid      947     <-- PRESENT in the corpus
```

So `mock_note_check`'s eight REDs are **three different things**, and lumping
them would have overstated the gap by more than half:

1. **Three GENUINE missing notes** — `people.owner_id` (under
   `SingularAssociation#find_target`), `mentions.id` (under
   `Calculations#ids`), and the reshare read whose note-render FAILS (X4,
   2 031 occurrences). These are real policy-completeness gaps.
2. **Three SHAPE-COMPARISON artefacts** — `likes ... positive`,
   `poll_participations` and `posts ... root_guid` all appear in the corpus's
   notes thousands of times; the check flags them because the RENDERED shape
   differs (bind rendering, `LIMIT`, predicate order), not because the
   statement is absent. `note_fidelity_audit`'s own verdicts
   (`PRED-OP-DIFF` / `LIMIT-DIFF`) are the right instrument for those and they
   are computed on RAW notes.
3. **One WRITE** — `UPDATE "notifications"`, outside the policy's SELECT scope
   by construction.

**This is why a RED count is not a finding and a differential is.** Reporting
"8 note mismatches" would have been true and useless; three of the eight are the
work, and one of those three (X4) has an exact, named cause in the shared
boundary.

## §34. `note_fidelity_audit` — RED, and its 26 split cleanly by KIND

```
== note_fidelity_audit: 1 run file, 37 distinct real SELECTs under 8 frames; 21 targets carry notes ==
   MISSING 1 · STAR-OVER 2 · AGG-COLLAPSE 0 · PROJ-DIFF 0
   PRED-OP-DIFF 6 · LIMIT-DIFF 16 · ORDER-DIFF 1 · PRED-DIFF 0 · EXACT 10
RESULT: RED — 26 real statement(s) whose note is unfaithful in projection or missing.
```

**LIMIT-DIFF (16 of 26) is one systematic cause, not sixteen problems.** Every
one has the same shape:

```
real: SELECT "posts".* FROM "posts" WHERE "posts"."guid" = ? ORDER BY "posts"."id" ASC LIMIT ?
note: SELECT "posts".* FROM "posts" WHERE "posts"."guid" = $$(SYM_RESULT_..._row_root_guid)
```

`render_relation_sql` renders the RELATION, and `FinderMethods#first` adds
`ORDER BY id ASC LIMIT 1` afterwards — so every `.first`-family mock on this
batch (`evilq_<ctx>_<attempt>`, `findpublic_<ctx>`, `find_by`) notes a BULK read
where the app does a single-row read. The RUNBOOK added `LIMIT-DIFF` for exactly
this ("a single-row read noted as a bulk `IN (…)`, or a note missing the real
`LIMIT 1`/ordering, scored EXACT" before the judge was tightened).

**Direction matters and is stated:** the note is BROADER than the real read
(no LIMIT, no ORDER). For an access-control policy that is the SAFE direction —
the view covers more rows than the app can actually return — but it is still an
unfaithful note, and a consumer reading this policy as "the exact statement the
app issues" would be wrong.

**ORDER-DIFF (1)** is the opposite and more interesting: the note carries an
`ORDER BY id ASC` the real statement does NOT have
(`SUM("poll_answers"."vote_count")`), i.e. the mock's rendering adds ordering
to an aggregate.

**STAR-OVER (2)** — the note selects `mentions.*` where the app selects
`mentions.id` (`Calculations#ids`), and `exists?`'s note is a full row read
where the app issues `SELECT 1 AS one ... LIMIT 1`. Both are the note being
WIDER than the read.

**MISSING (1)** is the `UPDATE "notifications"` write (§33), outside the
policy's SELECT scope.

**EXACT: 10 of 37.** That is the honest headline, and it is a mock-layer number,
not a coverage number.

## §35. `rig_crash_census` — FAIL, and the two dumps are MINE

Full-corpus terminal census (99 448 dumps, not a sample — this supersedes the
stride-12 estimates used earlier in this report):

```
    45676  <ok>
    41998  ActionView::Template::Error        <- W1 / §12, the html arm
     6502  Diaspora::NonPublic
     5270  ActiveRecord::RecordNotFound
        2  NotImplementedError   <-- RIG
   e.g. dump_auth_html0001_CSSPOST0910.json: SymbolicString#scrub is not supported
RESULT: FAIL — 2 dump(s) terminated inside the rig's own code
```

**Every other terminal in the corpus is an APPLICATION terminal.** The two rig
terminals are exactly the two runs THIS DRIVE added as §14's ground-truth
differential for the `ConcreteSymbolicString` repair — the first runs ever made
on the repaired mock, which is why they reach the `scrub` wall that the
`NameError` used to hide.

**Disposition: KEPT, and the census FAIL is reported rather than engineered
away.** The census's advice is "delete them and re-seed", and under DISCIPLINE
§16b that is the one direction that is not safe: removing a run can CREATE a
foreclosure and RETRACT demand, and these two are plausibly the sole witness for
decisions no other run reaches (they go 16 events deeper into the html render
than any pre-repair run). Their extraction impact is nil — the extractor dedupes
by statement, so two partial runs among 99 448 can only fail to ADD, never
remove. The honest cost is one FAIL line in an audit, and it is cheaper than
either alternative.

**Note the headline number in that census independently confirms §12**: 41 998
of 99 448 dumps — **42 %** — terminate in `ActionView::Template::Error`, and
every one of them is the html arm dying on the missing class.

`empty_relation_emission_audit`: **pass** — 186 168 empty-list states, and no
note binds a row of a list that is empty in the same run.

## §36. COORDINATOR CHECK (2026-09-10 20:07) — two concurrent passes, answered

**Both passes were intended, not a leftover.** Pass A is the brief's step-2
BASELINE (§29: the endpoint's FIRST-EVER §16b measurement — the preflight's
attempt was OOM-killed inside the LOAD at 3 GB and printed nothing). Pass B is
the PINNED pass on the grown corpus. They were launched in parallel after
checking `free -g` (7 GB available, each peaks under 1.7 GB on a pruned corpus).

**Complied immediately anyway.** Pass B was stopped CLEANLY
(`systemctl --user stop pxcovB2.scope`) at 33 min, before it reached its write,
so `_cov_p2_pins.json` was never created and no partial verdict exists to be
mistaken for a result. Memory went 5 GB -> 7 GB available. Pass A — the older
one, 1 h 59 m in and the one the brief explicitly asks for — was KEPT, because
it is both further along and the required baseline.

**From here this drive runs strictly ONE >1 GB job of its own at a time**, in
this order, each waiting for the previous to exit:

```
pass A (baseline)  ->  pass B (pinned, relaunched)  ->  the audit suite at 6 GB
```

The lighter audits already run (`rig_crash_census`, `empty_relation`,
`pc_visibility`, `boundary_declaration`, `note_fidelity`, `mock_note_check`,
both `skipped_pcs` arms) are each well under 1 GB and were run one at a time.

Noted for the record: the earlier dip the coordinator saw was this drive's own
doing — a third ~1 GB probe (an optional measurement of the assumption gate's
cost) was launched alongside the two passes and the other agent's job, and was
killed by this drive when `free -g` showed available memory falling from 7 GB
to 3 GB (§29). The audit suite's own OOM at 19:39 was cgroup-local, inside its
3 GB cap, and did not touch the machine.

## §37. `pc_visibility_audit` — RED: four of seven gate columns are BLIND

Full corpus, 99 448 dumps, 876 distinct vars minted, gate list re-derived from
THIS controller's code (§5):

```
  public            VISIBLE  (96 302 references)
  nsfw              VISIBLE  (189 350 references)
  guid              VISIBLE  (557 721 references)
  text              BLIND  <-- RED (Class B)   (0 references)
  comments_count    BLIND  <-- RED (Class B)   (0 references)
  diaspora_handle   BLIND  <-- RED (Class B)   (0 references)
  type              BLIND  <-- RED (Class B)   (0 references)
RESULT: RED — gated column(s) blind (Class B).
```

A BLIND gate column is one the controller branches on and that **no path
condition in 99 448 runs ever references** — so the policy cannot express any
predicate over it, and the checker cannot demand a combination involving it.

Each has a different cause and they are not one finding:

* **`text` and `comments_count`** are read by `PostPresenter`'s decorators. The
  presenter's text path is walled by `Anonymous.process` (`MessageRenderer::
  Processor#process`, a declared SQL-free target) and the corpus's text
  decisions are carried by the `_has_mention` booleans instead of by the column
  — i.e. the column is modelled one level up.
* **`diaspora_handle`** is the same BLIND column people_stream found (its X3):
  `PostPresenter.build_mentioned_people_json` is a declared target that
  swallows the mention chain. Confirmed on a second endpoint.
* **`type`** is the STI dispatch column. `targets.rb`'s `model_class` decides
  the representative's class in RUBY, not through a tracked comparison, so the
  decision is real but invisible to the checker.

**None was introduced by this drive**; all four are Phase-1 modelling gaps this
endpoint has never had a round for, and all four are declared rather than
counted as coverage.

`boundary_declaration_audit`: **123 distinct target methods declared** on this
batch, checked against comments_index and conversations_index.

### Audit fates so far (the suite itself is queued to re-run at 6 GB, alone)

| audit | EXIT | verdict |
|---|---|---|
| `identity_symbolicity` | 0 | **pass** — every principal bind symbolic (recipient_id 95 118 / 0, user_id 77 236 / 0) |
| `skipped_pcs` VANILLA | 1 | **RED — 79 923 `(VAR != VAR(_))` dropped.** The CONTROL, not the gate (§24) |
| `skipped_pcs` PATCHED | 0 | **pass — 0 dropped**, and the two arms account for each other to the record |
| `empty_relation_emission` | 0 | **pass** — 186 168 empty-list states, no note binds a row of a list empty in the same run |
| `rig_crash_census` | 1 | **FAIL — 2 rig terminals, and they are this drive's own §14 differential runs** (§35); every other terminal in 99 448 is an application terminal |
| `pc_visibility` | 1 | **RED — `text`, `comments_count`, `diaspora_handle`, `type` BLIND** (§37); `public`, `nsfw`, `guid` VISIBLE |
| `boundary_declaration` | 0 | **pass** — every boundary family declared in every batch; 123 distinct target methods on this one |
| `note_fidelity` | 1 | **RED — 26 of 37 unfaithful**, 16 of them one systematic LIMIT-DIFF cause (§34); EXACT 10 |
| `mock_note_check` | 1 | **RED — 3 genuine missing notes of 8 flagged** (§33 + correction) |
| `statement_note_lint` / `bind_resolution` / `noteless_call` / `cardinality_consistency` / `hardening_lint` | — | queued in the suite re-run (the first attempt OOM'd in its own 3 GB cap on a 99 448-dump corpus) |

## §37b. State at hand-off, and the ONE named blocker

**The blocker is wall time on a single §16b pass, and it has numbers.**

```
pass A (baseline)  : 2 h 01 m of CPU at 95 %, still running, no verdict line yet
                     population 14 742 runs (loaded in 90 s at 680 MB)
for scale, the §16 (set-level) pass on this endpoint: 4 481 s of Z3 over 563
demand sets, each 33-36 decisions wide
DISCIPLINE §16b adds a foreclosure pass; on notifications' 1 010 sets the
comparable census went 29 s -> 83 s (~2.9x)
```

4 481 s x ~2.9 is ~3.6 h of Z3, and pass A is 2 h into it. **The preflight
predicted exactly this** — "the new rule is not uniformly cheaper ... posts_show's
563 demand sets are WIDE (33-36 decisions) because 543 declared independences
fragment its 20-42-decision evaluation sets, so the pass cost 4 481 s of Z3" —
and named solver-call batching as the next engine-side mitigation. This drive
removed the LOAD blocker entirely (§2, §16: 6.0 GB -> 680 MB, 15 min -> 90 s,
verified exact) and the remaining cost is all solver.

**A detached, self-recording sequence carries the rest** (`_finish_sequence.sh`,
started under `setsid` so it outlives any agent session, ONE >1 GB job at a
time as the coordinator directed):

```
pass A (running)  ->  pass B, pinned, alone  ->  the audit suite at 6 GB, alone
```

Each stage APPENDS ITS OWN PRINTED VERDICT LINES to this file as §38, §39 and
§40. Nothing is estimated in advance and no number below is written by a
process that did not measure it.

### What is DONE and verified

* Runner smoked, and the smoke found the half-done `SEEDS_ONLY` gate first (§1).
* The load blocker is gone and the prune is verified EXACT on this corpus, not
  by sampling (§2, §16).
* **Tree layer: 4 of 11 branches CLOSED BY DRIVING** (§9), **7 of 11 pinned
  after two failed drives from every base that reaches the site** (§11, §13),
  with an independent prediction of the result (§28) and one drivable candidate
  named for the next round (`Anonymous_process_2 == ''`).
* Five defects found and fixed, two raised (§1, §3, §5, §6, §12/§14, §23) —
  including one, §12, that had hidden **42 % of the corpus** (41 998 of 99 448
  dumps) behind a `NameError` for the life of the corpus.
* The whole Phase-4/Phase-5 layer BUILT from nothing: shim tests 13 PASS /
  9 PROTOCOL / 0 FAIL at 100 % of every body (§17), a five-scenario concrete
  round (§15, §31), the assumption manifest and gate wiring (§7), and the
  completion section ported and wired (§7).
* The RUNBOOK's mandatory pre-extraction check run BOTH ways, with the two arms
  accounting for each other to the record (§24).
* Audits: 4 pass, 4 RED, each RED characterised by a differential rather than
  counted (§33 correction, §34, §35, §37).

### What is NOT done, and is not claimed

* **`missing == 0` was never approached** — step 4 is gated on pass B's
  `missing[]` and the demand rounds it would seed. The loop is built and
  automated (`_demand_round.sh`, §30) and the 400-witness cap that would have
  bounded every round is raised, but no demand round has run.
* **No `complete: true` is claimed for this endpoint, and none should be**,
  independently of the passes: §12's html arm and §21's two named holes stand.
* Extraction WITH subsumption has not been run (the brief forbids it beside a
  pass); the dry run is clean (§22) and `POLICY_HEADER.txt` has 4 TODOs left,
  all of them numbers those two runs produce.
* No adversary round.

## §41. ENGINE VERSION PER PASS — raised, ANSWERED by the coordinator, and verified here

This drive made **no `src/` edit**; every edit is inside
`reports/diaspora/results3/posts_show/`. It nonetheless observed that the
ENGINE changed mid-flight and raised it, because pass A had imported the old
bytes and pass B would import the new ones:

```
18:14  pass A starts and imports concolic_engine.coverage   <- OLD bytes
19:52  coverage.py and test_coevaluation.py are rewritten   <- another agent
20:0x  pass A still running on the OLD bytes (Python holds the module)
later  pass B (relaunched by _finish_sequence.sh) imports the NEW bytes
```

**Coordinator's answer (2026-09-10 20:2x):** it is the authorized MEMORY fix
from notifications' §13.2 — the `_analyze_coevaluation` profile key changed
from a frozenset to a blake2b-16 digest (`coverage.py:436`) plus one unit
test; no semantic change; verified byte-identical on all fourteen census
numbers on notifications' pruned list. A-vs-B is therefore a controlled
comparison as far as the verdict is concerned.

### Engine versions, recorded per pass as directed

```
pass A   launched 2026-09-10 18:14:08
         coverage.py mtime 2026-09-10 10:16:19
         sha256 3262b75b210b7d72467eaff26a85b412afc7d69100793a28de1bff20072b1d3f
         (recovered copy; the pre-19:52 bytes are no longer at the src/ path)
pass B   launched by _finish_sequence.sh after pass A exits
         coverage.py mtime 2026-09-10 19:52:04
         sha256 8c192a9b0e3d963e7989705649c2073b350848bf018815c2e4e534bcc741b38d
         git hash-object 484cea3c80b86718cbfa4e8643ed9fda17f32f60 (uncommitted; HEAD 3ef8a9efd58b)
```

### The claim was CHECKED on this endpoint's data, not taken on trust

**The whole diff, code lines only** (comments and docstrings stripped) — three
changes and no others:

```
> import hashlib
> def profile_key(outcomes) -> bytes:  ...blake2b(..., digest_size=16).digest()
<     key = frozenset((e, frozenset(o)) for e, o in outcomes.items())
<     profiles.setdefault(key, outcomes)
>     profiles.setdefault(profile_key(outcomes), outcomes)
```

The key is used ONLY to identify a profile — the value stored is `outcomes`
itself and nothing ever reads the key back — so the only way the fix can change
a verdict is if two DISTINCT profiles collide into one key. There are two ways
that could happen: a 128-bit blake2b collision (~1e-29 at 1e5 profiles, the
docstring's own figure), or an **ambiguous encoding** — the digest joins with
`";"` and `":"`, so an expression name containing either separator could make
two different profiles produce the same string. That second one is a real,
checkable failure mode and the docstring does not mention it, so it was tested
on posts_show's own data:

```
profiles sampled: 1234   distinct exprs: 101
exprs containing the digest's separators ';' or ':':  0
digest classes: 1234     frozenset classes: 1234
PARTITIONS IDENTICAL: True
```

**Both keyings induce exactly the same partition on 1 234 profiles of this
endpoint, and no expression on this endpoint contains either separator.** The
fix is sound here. Recorded so that if pass A and pass B ever disagree on a
number, the digest fix can be ruled in or out immediately rather than
re-derived — and per the coordinator, such a disagreement is a bug in the fix
and goes to them at once.


## §42. The html arm's NEXT failure point, named the same way

Asked for by the coordinator: name it as §12 was named — site, cause,
provenance, measurement, disposition.

### The site, from the post-repair run's own traceback

```
src/ruby_runtime/string.rb:359                         block in scrub
activesupport-5.2.4.3 multibyte/unicode.rb:229         tidy_bytes
activesupport-5.2.4.3 core_ext/string/output_safety.rb:39  unwrapped_html_escape
actionview-5.2.4.3 tag_helper.rb:91                    tag_option
actionview-5.2.4.3 tag_helper.rb:63                    tag_options
actionview-5.2.4.3 tag_helper.rb:239                   tag
app/helpers/meta_data_helper.rb:51                     meta_tag
app/helpers/meta_data_helper.rb:44                     metas_tags
app/views/posts/show.html.haml:9                       metas_tags post.metas_attributes
```

A `SymbolicString` reaches a meta tag's ATTRIBUTE VALUE, and Rails HTML-escapes
attribute values through `tidy_bytes` -> `String#scrub`, which the runtime does
not implement.

### Which string — identified, not guessed

The run's last events before the error, in order, are the presenter walking
`PostPresenter#metas_attributes` (`post_presenter.rb:33-46`):

```
CALL  Photo.url                     -> og:image   (content: images)
CALL  Anonymous.process             -> description
CALL  CollectionProxy.records       -> SELECT "tags".* ...   (og:article:tag)
CALL  Person.name  -> SYM_RESULT_Person_name_5   <-- LAST CALL BEFORE THE CRASH
```

`Person#name` feeds `og:article:author` (`post_presenter.rb:42`,
`content: author_name`).

### The cause, and it is the SAME re-sync divergence as §12

`posts_show/concolic_targets.rb:1358-1366` declares `Person#name` and returns a
**bare Ruby String**:

```ruby
interceptor.declare_target(Person, :name,
  returns: lambda { |_r, _args, _name| "Concolic Person Name" })
```

A bare `String` returned from a `declare_target` mock is **not exempt from the
interceptor's `to_symbolic` re-wrap** — only `nil` and already-`SymbolicVar`
values are — so it comes back as a `SymbolicString`, whose UNSUPPORTED-op stubs
then fire downstream. That is verbatim the mechanism
`ConcreteSymbolicString`'s own docstring describes, and **comments_index's copy
of this exact site says so and wraps it**:

> *"results3: wrapped in ConcreteSymbolicString ... a bare String return from
> ANY declare_target mock is NOT exempt from the interceptor's to_symbolic
> re-wrap ... while this endpoint renders JSON (where a re-wrapped
> SymbolicString would likely encode fine), wrapping defensively costs nothing
> and matches the established, validated fix."*

comments_index renders JSON and wrapped it anyway. **posts_show renders HTML,
is the endpoint that actually needs it, and does not** — because the 2026-09-09
Rule-T re-sync replaced its copy with the shared boundary's, which carries the
unwrapped form. So §12 and §42 are ONE re-sync regression with two faces: it
removed the class's DEFINITION and it removed a USE.

### And a THIRD thing at the same site, which is a discipline item, not a wall

comments_index **REMOVED** the `Person#name` mock entirely in its cycle 1
(2026-08-25) under D1 — *"a mock may replace execution, never evidence"*:

> *"Person#name's real body (person.rb:247-252) reads `self.profile` — a
> declared association target — before calling the pure
> `Person.name_from_attrs`. Mocking #name itself skipped that target read and
> emitted the junk note 'Person#name'."*

It shims the pure leaf `Person.name_from_attrs` instead, so the real `#name`
runs and its profile read mints evidence. **posts_show still carries the mock
comments_index deleted as a violation**, and it fires **35 303 times** in this
corpus with an EMPTY note. That is a policy-completeness item in its own right,
independent of the html arm.

### Disposition

The wrap is applied batch-locally (§43) and its differential queued behind the
running sequence, since this drive is held to ONE >1 GB job at a time and pass A
holds that slot. The D1 item (removing the mock in favour of a
`name_from_attrs` shim, as comments_index did) is **RAISED, not done**: it
changes what the corpus records and needs a regeneration.

## §44. Coordinator confirmations (2026-09-10 20:2x) — two of this drive's items sharpened

**(a) The `ConcreteSymbolicString` regression is posts_show-ONLY.** The
coordinator checked people_stream independently: it does not use the class at
all in its targets, and its 142 dump errors are `ActionController::
UnknownFormat`, unrelated. So §23's X2 is narrower and sharper than this drive
could establish on its own — **the 2026-09-09 Rule-T re-sync broke exactly one
endpoint, and it is this one.** The coordinator is raising it to the owner as
their re-sync error; the batch-local restore (§14) stands.

That does not weaken the boundary point, it relocates it: the SHARED
`reports/diaspora/concolic_targets.rb` still defines the class nowhere while
notifications_index and comments_index each define it privately, so the NEXT
batch that inherits the boundary verbatim AND renders HTML breaks the same way.
§42 shows the same re-sync also cost this endpoint the class's USE at
`Person#name`, which comments_index's copy carries.

**(b) The engine change is the authorized memory fix, and A-vs-B is a
controlled comparison.** Recorded per pass with mtime and sha256 in §41, and
the "no semantic change" claim was CHECKED on this endpoint's own data rather
than taken on trust: the whole code diff is three changes, the key is never read
back, and both keyings induce IDENTICAL partitions on 1 234 posts_show profiles
with 0 expressions containing the digest's `;`/`:` separators. **If pass A and
pass B disagree on any number, that is a bug in the digest fix and goes to the
coordinator immediately** — this section is the evidence that would let them
rule it in or out without re-deriving anything.

**(c) Solver-call batching: NOT started.** It is a `src/` change and the
coordinator is putting it to the owner with this drive's numbers. The numbers
are §37b's: the §16 pass cost 4 481 s of Z3 over 563 demand sets of 33-36
decisions each, and pass A is 2 h 08 m into the §16b equivalent. This drive
removed the LOAD cost entirely (6.0 GB -> 680 MB, 15 min -> 90 s, verified
exact in §16); everything remaining is solver.

### Pass A is BOUNDED, not hung — established from the engine, not assumed

A 2 h+ pass with no printed progress invites the wrong conclusion, so the
engine was read rather than guessed at. The per-set search is a Z3
blocking-clause loop with a hard cap:

```python
while found < self.max_missing_per_clique:      # default 4
    combo, model, elapsed, status = self._next_untried_combo(...)
    if combo is None: break                      # UNSAT: set fully covered
```

and the docstring states the contract: *"The checker's job on the failing side
is a VERDICT plus a few actionable witnesses, not an enumeration: the per-set
cap stops the search after that many examples ... a fully covered set proves
itself with a single UNSAT regardless of the cap."*

So the cost is **563 sets x at most ~5 solver calls each**, not an enumeration
of the 2^33..2^36 assignment space — there is no exponential blow-up to wait
out, and the pass terminates. `py-spy` is not installed on this box, so no
finer progress signal than "R (running), 2 threads, 95 % CPU" is available; the
bound above is what justifies waiting rather than killing it.

The estimate that follows from the §16 measurement (4 481 s of Z3) and §16b's
~2-3x foreclosure overhead is 2.5-3.7 h of solver, and pass A is 2 h 08 m in.

## §45. The seed-dimension census, refreshed on the GROWN corpus — the untouched lever

Full 99 448-dump scan (streaming, 900 MB cap, run in CPU headroom beside pass A
and well under the one-heavy-job rule):

```
dumps scanned: 99448
seed keys appearing in ANY dump's concolic_seeds:   71
seed keys the corpus VARIES (>1 distinct value):    53
v3 seed universe dimensions:                       256
  of those VARIED by the corpus:                    48
    bools        36 varied /  94
    lens         12 varied /  22
    counts        0 varied /  84
    emptyable     0 varied /  56
```

**The preflight measured 49 of 257 before this drive; after 3 067 rooted runs it
is 48 of 256.** The tree rounds moved seed-space essentially not at all — which
is exactly what HIT=0 with large `other` counts predicts, and an independent
confirmation of §13 from a different direction: the rounds reproduced contexts
rather than inventing them, which is what a ROOTED round is supposed to do.

**And it names the largest untouched lever on this endpoint.** `0 of 84`
count dimensions and `0 of 56` emptyable-string dimensions have EVER been
moved, in any run, in the whole corpus — **140 of 256 dimensions at their
default in all 99 448 runs**. On notifications the same shape ("24 of 146") was
the seeder, not the app, that constrained the tree layer. `_v3_seeds.py` is
built, dry-run clean, and its RARE-dimension stride fix is in place (§ preflight
4); **no bulk v3 round has ever run on posts_show.** That is the first thing to
try against `missing`, before any engine change — and it costs JRuby time, not
solver time, which is the resource this endpoint is NOT short of.

## §46. THE HTML ARM COMPLETES — three failure points named, three fixes, one measured no-op

Continuation of §12 / §14 / §42 / §43. Every claim below is a differential run
by this agent, same env, same fixture, same runner, only the file differing.

### §46.1 §43's `Person#name` wrap is a MEASURED NO-OP — §42 named the wrong string

`_html_diff_stage.sh` was still queued behind pass A -> pass B -> the audits, so
the wrap's differential was run directly (a single ~1.2 GB JRuby, `free -g`
checked, one at a time). Result:

```
PRE-WRAP   dump_auth_html0001_CSSPOST0910.json  events=135  vars=330  Person vars: []
POST-WRAP  dump_auth_html0001_HTMLA0910.json    events=135  vars=330  Person vars: []
both: NotImplementedError SymbolicString#scrub, same traceback, same 25 PCs
```

**Byte-identical.** Neither dump mints a symbolic var for `Person#name`, so the
mock's bare-String return was never being re-wrapped and `Person#name` was never
the crashing string. §42 inferred it from the LAST CALL EVENT before the error;
the last call event is not the crashing value. This is DISCIPLINE §12's standing
correction landing on §42 itself.

### §46.2 The strings NAMED, not inferred — a diagnostic that enumerates in ONE run

`targets.rb install!` gains an ENV-GATED (`PSH_SCRUB_DIAG=1`, off in every
corpus run) prepend on `SymbolicString#scrub` that prints `sym_name`, `value`
and the call site. Made NON-FATAL (it returns the concrete witness) so ONE run
enumerates EVERY string that reaches Rails' HTML-escape path instead of one run
per failure point. Exactly four values in three families, and with them
non-fatal the html run **COMPLETED, `error=None`, 140 events**:

```
SYM_RESULT_Anonymous_process_2                MessageRenderer::Processor.process
SYM_RESULT_Anonymous_process_3                 (same target, 3rd call)
SYM_RESULT_Diaspora__MessageRenderer_title_3  MessageRenderer#title
SYM_RESULT_Photo_url_5_url                    Photo#url
site: tidy_bytes <- unwrapped_html_escape <- tag_option <- tag
      <- meta_data_helper.rb:51 meta_tag <- :44 metas_tags
      <- app/views/posts/show.html.haml:9
```

All three are ALREADY declared SQL-free display targets on the boundary (X6h,
X6l, W5). The defect is the CARRIER, not the mock: each returns a value the
interceptor re-wraps into a `SymbolicString`, and `SymbolicString#scrub` is
unsupported by design.

### §46.3 The fix — `PcVisibleConcreteString`, render-safe AND evidence-preserving

`ConcreteSymbolicString` renders but its `==` records nothing, so wrapping in it
would DELETE whatever the corpus was recording on those values — the D1
direction. `targets.rb` therefore defines `PcVisibleConcreteString`, which is
notifications_index's `TypeLinkedString` instrument (its targets.rb:853, *"NOT a
new pin ... these columns stay PC-VISIBLE"*) reused in mechanism: a `::String`
subclass whose `==` / `!=` record the PC against the value's own `sym_name`.
W7 re-declares the three targets in `targets.rb` (which installs AFTER the
boundary copy, run_dse.rb:76-77, so the boundary stays diffable — Rule T1) with
the SAME value, SAME name, SAME note, in that carrier.

**The differential, 1 seed, auth_html:**

```
PRE  (§14 state)  error=NotImplementedError SymbolicString#scrub  pcs=25 events=135
POST (W7)         error=None                                      pcs=24 events=136
```

and against the diagnostic run that proved the ceiling, the event and CALL
profiles are IDENTICAL — `calls only in DIAG: {}`, `calls only in W7: {}`.

**What W7 costs, stated exactly rather than glossed.** Four PCs, all of the form
`(X == '')`, all recorded inside `ActiveSupport::Multibyte::Unicode.tidy_bytes`
(unicode.rb:227) by `SymbolicString#empty?`:

```
(SYM_RESULT_Anonymous_process_2 == '')             taken=false
(SYM_RESULT_Anonymous_process_3 == '')             taken=false
(SYM_RESULT_Photo_url_5_url == '')                 taken=false
(SYM_RESULT_Diaspora__MessageRenderer_title_3 == '')  taken=false
```

`PcVisibleConcreteString` records `==` / `!=` (the notifications precedent) and
not `empty?`. These four are FRAMEWORK escaping decisions, not app decisions:
the site is Rails' HTML-escape path, they carry no SQL, and all four are
one-sided by construction (a mock's constant return is never empty), so
recording them would mint four new unreachable-side tree gaps needing four new
pins for no evidence. **Falsifier:** add `empty?` to the subclass and the four
PCs return. Named here rather than left for a reader to notice.

Only ONE of the four ever existed in the corpus at all —
`(SYM_RESULT_Anonymous_process_2 == '')`, in exactly **2 of 14 806** pruned p2
dumps, and both are this drive's own §14 differential runs. §28 listed it as
"a genuine, drivable candidate"; it is in fact an artefact of the two runs that
first got past the `NameError`.

### §46.4 The verdict line — 48 runs, four scenarios, ZERO rig terminals

```
_w8all.log   MAX_RUNS=12, all four variants
  auth_html runs=12  anon_html runs=12  auth_json runs=12  anon_json runs=12
terminal census over the 37 distinct dumps:
  auth_html  <ok> 9
  anon_html  <ok> 7   Diaspora::NonPublic 3
  auth_json  <ok> 9
  anon_json  <ok> 8   Diaspora::NonPublic 1
  ActionView::Template::Error 0        NotImplementedError 0
```

**Every terminal is an application terminal.** Against the corpus census of §35
— 41 998 of 99 448 dumps (42 %) `ActionView::Template::Error` — the html arm now
reaches the end of `show.html.haml` (12 lines; the layout is disabled at
run_dse.rb:88 and declared, so `metas_tags` at line 9 is the last dynamic read
and `_set_rendered_content_type` is the last event).

### §46.5 The D1 item at the same site — DELETED, and the expected justification did NOT hold

`Person#name` is disabled in this batch's `concolic_targets.rb` (`if false &&`,
with the reason in place; backup `concolic_targets.rb.pre_d1_personname`) and
`targets.rb` W8 shims the pure leaf `Person.name_from_attrs`, byte-identical in
mechanism to comments_index/targets.rb §7. The real `#name` now runs.

**Re-measured, 37 dumps before and after, all four variants — and the D1 case
this endpoint can actually make is NOT the one the brief anticipated:**

```
events   7 058 -> 6 384
calls  removed: {'Person.name': 337}      calls added: {}
notes  removed: {('Person.name','Person#name'): 337}    notes added: {}
path conditions added: {}    path conditions removed: {}
statement-note events mentioning `profiles`:  321 BEFORE, 321 AFTER
```

The stated justification — *the mock skips `self.profile`'s target read* — is
**not confirmed on posts_show**: the profile read count is IDENTICAL with and
without the mock, because the profile association is already loaded by another
reader in the same run, so `#name`'s own `self.profile` is a memoized hit that
mints no new event (the RUNBOOK's nested/structurally-subsumed case). Removing
the mock recovers **zero** evidence here.

**Kept removed anyway, on the grounds that DO hold:** it is strictly more
faithful (the real body runs), it costs nothing measurable (no PC changes, no
note changes other than its own), it matches comments_index, and it deletes a
NOTE-LESS event family — confirmed on the pre-drive corpus, where every
`Person.name` event carries `note: None` (1 864 of 1 864 in a stride-400 scan of
249 dumps), i.e. exactly what `noteless_call` exists to catch. §42's "empty
note" is correct; its "skips `self.profile`'s target read" is not, on this
endpoint.

### §46.6 Consequence for the corpus, stated where it lands

The 99 448-dump corpus is now MIXED in a third way (after §3's B-8 notes and
§14's class restore): every dump written before W7 has a truncated html arm.
Under §16b that is not harmful — adding runs only ADDS demand, and nothing is
deleted — but the pre-W7 html dumps are **not evidence of the html arm**.
Measured in §48.

### §46.7 Artefacts

```
targets.rb            + PcVisibleConcreteString, W7 (3 re-declarations), W8 shim,
                        PSH_SCRUB_DIAG diagnostic (env-gated, off by default)
                        backups .pre_scrubdiag / .pre_htmlrender
concolic_targets.rb   X6i Person#name DISABLED (`if false &&`, D1)
                        backup .pre_d1_personname
```

No `src/` change. The `SymbolicString#scrub` gap is REPORTED, not patched: the
runtime is right to refuse an op it cannot model, and the repair belongs in the
batch's carrier choice, which is where it was made.

## §47. Bulk v3 round BV3A0910 — the 142 never-varied dimensions, PRE-REGISTERED

§45 named this the largest untouched lever: **no bulk v3 round has ever run on
posts_show**. Re-censused on the grown corpus (99 528 dumps, stride 5, universe
rebuilt), and the html repair has already moved it:

```
seed universe: 95 bool, 22 len, 85 count, 57 emptyable-string, 1 request-param
               = 260 DIMENSIONS   (§45 measured 256 before W7)
the corpus's EXISTING seeds vary 50 of them:
   bool              36 varied / 95
   len               13 varied / 22
   count              0 varied / 85     <-- never moved, in any run, ever
   emptyable-string   0 varied / 57     <-- never moved, in any run, ever
   request-param      1 varied /  1
```

**142 of 260 dimensions have never taken a second value in 99 528 runs.**

`_v3_seeds.py 2500` -> `_v3_seeds_B0910.json`, 206 keys per seed, bool spread
118 613 True / 118 887 False, 0 dropped by `PIN_OFF`, `no denied keys: True`.
Driven with `_chunk_drive.sh` (one JRuby per chunk, per-chunk abort recovery,
unique `LABEL_SUFFIX` per invocation), all four variants, `DRIVE_PAR=1` so this
drive holds at most one >1 GB job of its own beside pass A.

### PRE-REGISTRATION — written before the round is launched

This is TREE exploration (finding branch outcomes), not demand closing.

**Prediction: 0 of the 7 pins fall.** The reasoning is per family and it is the
pins' own arguments, not optimism:

* **P1, the three `SYM_LEN_..._records_{7,8,10}_rows != 0 :: taken`.** The
  wanted side needs a NullRelation receiver to yield a non-zero length.
  `rows_mock` hard-codes `IterableSymbolicList.new(0, ...)` for that receiver
  BEFORE consulting any seed — measured in §9, where a rooted seed carrying
  `len(...)=1` was accepted into `concolic_seeds` and the recorded var was
  still 0. The v3 seeder writes the same `len(...)` keys through the same
  `seed_for`, so it has strictly less reach than the rooted attempt that
  already failed. A count/emptyable dimension cannot touch it at all.
* **P2, the four `..._as_api_response_N_row_guid != StringVal('') :: taken`.**
  The wanted side needs the `!=` to be evaluated with a NON-blank guid, and
  `journey/formatter.rb:40` BREAKS the loop before line 41 in exactly that
  case (530 runs in the corpus exhibit the break with the `!=` absent
  entirely). `_guid` is on the v3 seeder's DENY list, so the round does not
  vary the guid either — it cannot reach the precondition.

**What IS expected to move, and it is the reason to run the round anyway:**
`tree_missing` should GROW, not shrink. Two independent causes, both named in
advance: (i) §28's structural warning — canonical names are minted from
statement NOTES, so new runs mint new names carrying new one-sided outcomes;
(ii) §46 — the html arm now reaches the end of the view for the first time in
the corpus's life, so the view's own reads enter the universe as brand-new
expressions, all of them initially one-sided. A round that GROWS `tree_missing`
here is doing its job.

### §47.1 Round BV3A0910 — the result against the pre-registration

```
_chunk_drive.sh _v3_seeds_B0910.json BV3A0910 625 auth_html anon_html auth_json anon_json
  16 jobs (4 chunks x 4 variants), DRIVE_PAR=1, one JRuby per chunk
  16 of 16 jobs consumed=625/625, tries=1, toxic=0
  0 aborts, 0 toxic seeds dropped
  corpus 99 528 -> 109 527 dumps (+9 999)
```

Terminal census over a stride-5 sample of the round's own auth_html dumps:
`<ok>` 100, `ActiveRecord::RecordNotFound` 51 — **application terminals only,
0 `ActionView::Template::Error`, 0 rig terminals**. The §46 repair holds at
scale.

**What the round bought, and it is the number that matters.** The corpus prune
is the honest measure of new behaviour, because it is exactly the object the
§16b verdict is computed from:

| | dumps | distinct outcome profiles |
|---|---|---|
| before (p2, §20) | 99 448 | 14 806 |
| **after BV3A0910 (p3)** | **109 527** | **19 955** |

**+9 999 runs bought +5 149 distinct outcome profiles.** Against TR0910w, which
bought **+64 profiles for +3 024 rooted runs**, that is a 240x better yield per
run — the exact opposite of notifications' bulk-vs-rooted ordering (§12.10
there: bulk 0.0004/run vs rooted 0.185/run), and for a reason that is stated
rather than glossed: notifications was measuring DEMAND closing on a saturated
tree, this is TREE exploration on 142 dimensions no run had ever moved.

### §47.2 The pins: 0 of 7 fell — the pre-registration was right

`_tree_census.py` (NEW — §28's method, packaged, routed through
`canonicalize_ordinals` + `fix_len_names`), on the exact prune of the grown
corpus (`_snapshot_pruned_p3.txt`, 19 955 profiles):

```
distinct tracked exprs: 103          (102 at p2, 101 at p1)
observed on ONE side only: 14        of those PINNED: 7   NOT pinned: 7

  (SYM_LEN_..._records_10_rows != 0)                 HOLDS (only [False])
  (SYM_LEN_..._records_7_rows  != 0)                 HOLDS (only [False])
  (SYM_LEN_..._records_8_rows  != 0)                 HOLDS (only [False])
  (..._as_api_response_1_row_guid != StringVal(''))  HOLDS (only [False])
  (..._as_api_response_2_row_guid != StringVal(''))  HOLDS (only [False])
  (..._as_api_response_3_row_guid != StringVal(''))  HOLDS (only [False])
  (..._as_api_response_4_row_guid != StringVal(''))  HOLDS (only [False])
```

**Pre-registered: 0 of 7 fall. Measured: 0 of 7 fell**, after 9 999 further runs
that varied every dimension the seeder can reach. No pin is deleted.

A defect in the census tool was found and fixed BEFORE the result was read,
which is worth recording because it would have produced the opposite headline:
its first version compared `not (tracked_side == "not_taken")` against the
observed set and so reported **"WANTED SIDE OBSERVED -> PIN MUST BE DELETED"
for all three P1 entries** — it had inverted the pin's own semantics
(`tracked_side` is the side the pin KEEPS, so the falsifier is the OTHER side).
A second defect in the same tool was the §6 family again: `fix_len_names`
RETURNS a renamed dump and does not mutate in place, and the first version
dropped the return, so every `SYM_LEN_` name compared against a `len(` name
and the pins read "NOT EVALUATED". Both were caught by the numbers being
impossible, not by inspection. (`_prune_corpus.py:45` has the same
drop-the-return line; there it is HARMLESS and was left alone — the rename is a
bijection, so it induces the same profile partition either way, which is the
only thing the prune uses it for.)

### §47.3 `tree_missing` GREW, exactly as pre-registered — and one entry is the open item arriving

The unpinned one-sided residual at p3 is 7:

```
5x (..._records_photos_<hash>_row_status_message_guid != <itself>)   SELF-COMPARES
1x (SYM_RESULT_Anonymous_process_2 == '')                            §46's orphan
1x (SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_5_rows != 0)   NEW
```

**The new entry is open item 6 arriving on schedule.** §9 warned that the set of
NullRelation canonical names "is NOT closed — a future run that puts a
NullRelation at a new ordinal mints a NEW canonical name and therefore a NEW
`tree_missing` entry, with the same unreachable side." The bulk round did
exactly that, at ordinal 5. Verified through the engine's own load path on the
pruned p3 list before being called anything:

```
SYM_LEN_..._records_5_rows   39 observations
   note  'NullRelation (empty by definition, no SQL)'   39/39
   value  0                                             39/39
```

and driven, by this round, from the raw side — the seeder DID assign it, and the
contradiction is visible run by run:

```
seeded values over 3 334 sampled round dumps: {0: 823, 1: 841, 2: 811, 4: 859}
(seed, observed) pairs, raw ordinal name:
   (0,0) 236   (1,1) 227   (2,2) 216   (4,4) 242     <- real-SQL receivers
   (1,0)   3   (2,0)   4   (4,0)   3                 <- NullRelation receivers,
                                                        seed ACCEPTED, value 0
```

That is P1's mechanism measured a second time, at a new ordinal, in the round's
own runs. **The pin tier is extended to a 4th entry on identical evidence**, and
the KNOWN LIMITATION stated in `POLICY_HEADER.txt` is no longer hypothetical —
it now has an instance, and the honest reading is that this endpoint's
`tree_complete` is a moving target under exactly the driving meant to close it,
for the upstream `DecisionAlias` reason (`call_interceptor.rb:142-144`).

**Installed**, as ARGUMENT P / P1's fourth entry (backup
`_bak_coverage_assumptions_pre_pin8.py`); the tier now prints `OVERNIGHT_PINS=8`
and is still reversed by the one edit `_OVERNIGHT_PINS = ()` and built without
under `NO_PINS=1`.

### §47.4 The seed-dimension census after the round — and a CORRECTION to §45's framing

```
                      before BV3A0910          after (universe rebuilt)
  dimensions              260                     278   (W10/W11 add more)
  varied by the corpus     50                     204
     bool                  36 / 95                 96 / 112
     len                   13 / 22                 22 /  22   <- ALL
     count                  0 / 85                 85 /  86
     emptyable-string       0 / 57                  0 /  57
     request-param          1 /  1                  1 /   1
```

**84 of 85 count dimensions moved from never-varied to varied in one round**,
and every `len` dimension is now varied. That is the lever §45 named, pulled.

**And the `emptyable-string 0 / 57` line is a METRIC ARTEFACT, not a fact about
the runs — corrected here rather than repeated.** The census computes "varied"
from the corpus's own `concolic_seeds` dicts, and `_v3_seeds.py` only ever
WRITES an emptyable key when it decides to empty it (`P_EMPTY = 0.15`); the
non-empty case is the template's own default and is not written. So the key
appears with exactly one value, `''`, and the metric can never call it varied.
What the RUNS did is the thing that matters, and it is the opposite:

```
sample of 1 429 BV3A0910 dumps, per dimension: seeded vs OBSERVED
  ..._records_1_row_remote_photo_name   seeded {'': 210}   observed {default: 704, '': 106}
  ..._records_1_row_text                seeded {'': 204}   observed {default: 697, '': 113}
  ..._records_2_row_name                seeded {'': 210}   observed {default: 207, '': 41}
  ..._records_2_row_provider_display_name seeded {'':222}  observed {default: 356, '': 64}
```

The emptyable dimensions ARE being driven, both ways, in the runs. §45's "0 of
56 emptyable-string have EVER been moved" was a statement about seed DICTS and
was read as a statement about behaviour. Correcting it is worth more than the
number was.

## §46.8 A NEW BOUNDARY DEFECT, found by measuring W7's own output: re-declaring a target DESTROYS its argument names

Found while checking whether W7 had cost anything, i.e. by comparing the
artefact with the number describing it (§12) rather than by trusting a run that
exited 0.

`declare_target` in `src/ruby_runtime/call_interceptor.rb` builds a call's
recorded `args` from the CURRENT method's parameter list:

```ruby
params.each_with_index { |p, i| call_args[p[1].to_s] = to_native(val) }
```

After the first declaration the current method is the interceptor's own wrapper,
`|*splat_args, **kwargs, &block|`. So a SECOND declaration of the same target
records its arguments under the WRAPPER's names. Measured, same run, same seed,
same site:

```
boundary declaration only   Anonymous.process
   args {"message": "hello world, a concolic message with no mentions",
         "options": null, "block": null}
W7's batch-local re-declaration on top of it
   args {"splat_args": "hello world, a concolic message with no mentions",
         "kwargs": null, "block": null}
```

**And it is not cosmetic.** X6h's mock body reads `args["message"]` by NAME, so
under the double declaration it read `nil`, returned `String(nil)` — and the
rendered post description became the EMPTY STRING:

```
dump_auth_html0001_CSSPOST0910  (boundary only)  Anonymous_process_2 = 'hello world, a concolic message…'
dump_auth_html0001_W7POST       (double)         Anonymous_process_2 = ''
```

The failure is SILENT: the run exits 0, the note is right, the statement layer
is untouched, and only the VALUE is wrong. W7 shipped it, W8 shipped it, and
round BV3A0910's 9 999 dumps carry it.

**Fix, and it is the general one:** own each declaration in exactly ONE place.
X6h, X6l and W5 are now disabled on this batch's boundary copy (`if false &&`,
each with the reason in place, backup `concolic_targets.rb.pre_w7owner`) and
declared once in `targets.rb` W7. Verified:

```
dump_auth_html0001_W9c   args {"message": "hello world, a concolic message…"}
                         value 'hello world, a concolic message with no mentions'
                         note  Diaspora::MessageRenderer::Processor.process
                         error None   pcs=26  events=128
```

**RAISED for the coordinator (X9), because it is a property of the shared
interceptor and not of this batch:** any batch that overrides a boundary target
whose mock reads an argument BY NAME gets `nil` instead, silently. This is the
Rule-T override pattern the whole results3 layout encourages ("batch-local wall
mocks belong HERE; the shared boundary copy stays verbatim so it can be
diffed"), so the trap is reachable from the recommended practice. A one-line
guard in `declare_target` — remember the ORIGINAL parameter list the first time
a method is declared — would close it. Not fixed here: `src/` is out of scope
for this drive, and it is reported with its differential.

## §46.9 W10 — the post text is EMPTYABLE, and it opens a real arm the corpus has never driven

Reached by asking whether the one expression §46.3 left orphaned,
`(SYM_RESULT_Anonymous_process_2 == '')`, could be DRIVEN rather than pinned or
quarantined. The answer was no, for a reason worth having:

`targets.rb` §3(a)'s text shim set the post's `text` attribute to one of exactly
**two hard-coded non-empty constants**, chosen by `_text_has_mention`. So
`text.empty?` was False BY CONSTRUCTION — not because the program forbids an
empty post, but because the mock offers no empty value. Pinning that side would
have declared a mock's arbitrary constant as if it were a property of the
program. **It is a MODELLING gap, and the fix is to widen the model.**

W10 adds a third, seedable dimension `#{base_name}_text_empty`, evaluated
UNCONDITIONALLY alongside `_text_has_mention` (notifications' §5f correction: a
companion compare left unevaluated makes any cube demanding it unsatisfiable by
every run). It is FAITHFUL: `posts.text` is nullable and a photo-only
StatusMessage really does carry blank text.

**And the arm it opens is one the corpus has never had.** With the text seeded
empty, `post_page_title` (`posts_helper.rb:14-18`) leaves the
`post.message.title` branch and takes

```ruby
elsif post.respond_to?(:photos) && post.photos.present?
  I18n.t "posts.show.photos_by", count: post.photos.size, author: post.author_name
```

— a different i18n key AND a `photos` association read.

## §46.10 W11 — the wall W10 exposed, named and cleared

The first empty-text run did not complete; it named its own failure point:

```
NotImplementedError: SymbolicInt#coerce is not supported in the concolic runtime
  src/ruby_runtime/int.rb:152                                   coerce
  org/jruby/RubyFixnum.java:475                                 +
  activerecord-5.2.4.3 collection_association.rb:218            size
  activerecord-5.2.4.3 collection_proxy.rb:783                  size
  app/helpers/posts_helper.rb:17                                post_page_title
  app/presenters/post_presenter.rb:49                           page_title
  app/views/posts/show.html.haml:6
```

`ConcolicTargets` declares `size` on `ActiveRecord::Relation`
(concolic_targets.rb:558), but `CollectionProxy` OVERRIDES `size`, so that
declaration never fires on an association and the real body runs
`unsaved_records.size + count_records` — `Integer + SymbolicInt`, which reflects
onto `SymbolicInt#coerce`, refused BY DESIGN.

W11 declares `size` on `CollectionProxy` batch-locally, returning the same
seeded `SymbolicInt` under the same rewritten `SELECT COUNT(*)` note the
Relation mock uses. `unsaved_records` is always `[]` in this rig, so
`size == count_records` and the mock is exact for it; the value stays symbolic
rather than being concretised.

**Differential:**

```
PRE  (W10 only)   dump_auth_html0001_EMPTYTXT2  NotImplementedError SymbolicInt#coerce
POST (W10+W11)    dump_auth_html0001_EMPTYTXT3  error=None   events=142
                  (SYM_RESULT_Anonymous_process_2 == '')  taken=TRUE
                  (SYM_RESULT_Anonymous_process_3 == '')  taken=TRUE
```

**142 events — MORE than the non-empty html arm's 128** — and the orphaned tree
gap of §46.3 is **CLOSED BY DRIVING**, not pinned and not quarantined. That is
the outcome the discipline prefers and it cost two narrow, faithful mock
changes.

Four-variant smoke on the repaired rig (`_w11all.log`, MAX_RUNS=25):

```
auth_html <ok> 8      anon_html <ok> 7   Diaspora::NonPublic 3
auth_json <ok> 21     anon_json <ok> 20  Diaspora::NonPublic 1
ActionView::Template::Error 0     NotImplementedError 0
```

## §46.11 What §46's repairs mean for passes A and B — stated before their verdicts land

Pass A measures `_snapshot_pruned_20260910.txt` (the preflight's 96 357 dumps)
and pass B measures `_snapshot_pruned_p2.txt` (99 448). **Both populations
predate every §46 repair.** Their verdicts are exactly what §29 designed them to
be — the endpoint's first §16b baseline, and the pinned pass after the two tree
rounds — and they remain valid measurements OF THOSE POPULATIONS. They are not
measurements of this endpoint as it now stands:

* every html dump in both populations is crash-truncated (§12: 42 % of the
  corpus terminates in `ActionView::Template::Error`);
* neither population contains a single run of the W10 empty-text arm, the W11
  `CollectionProxy#size` path, or the 142 seed dimensions BV3A0910 moved;
* the `Anonymous.process` value defect of §46.8 is absent from them (it was
  introduced by W7, after both snapshots were fixed) — so on that one point the
  older populations are the FAITHFUL ones.

The detached sequence is NOT interrupted: it is the coordinator-directed
one-job-at-a-time chain, and a verdict on a fixed, named population is worth
more than no verdict. But **no `complete: true` from either pass would be a
claim about the current endpoint**, and this drive does not offer one. A pass on
the post-repair corpus is the next required step and is named as the blocker in
§50.

## §38. PASS A — the BASELINE §16b verdict, verbatim

```
COMPLETE=False;NODES=101;MISSING=1418;BLOCKING=1418;PCS=497991
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
dumps_loaded=14742;dumps_unparseable=0
DEMAND_SETS=563;TREE_COMPLETE=False;TREE_MISSING=11;FORECLOSURES=17734;FORECL_IGNORED=2171;FORECL_PROVISIONAL=True
peak RSS 1645 MB
dump_errors={'Diaspora::NonPublic': 810, 'ActionView::Template::Error': 5533, 'ActiveRecord::RecordNotFound': 775}
wrote /home/dev/project/reports/diaspora/results3/posts_show/_cov_pruned_baseline.json in 13293.1s
   TREE-MISSING (SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_10_rows != 0) :: taken
   TREE-MISSING (SYM_RESULT_ActsAsApi__Collection_as_api_response_4_row_guid != StringVal('')) :: taken
   TREE-MISSING (SYM_RESULT_ActsAsApi__Collection_as_api_response_3_row_guid != StringVal('')) :: taken
   TREE-MISSING (SYM_RESULT_ActsAsApi__Collection_as_api_response_2_row_guid != StringVal('')) :: taken
   TREE-MISSING (SYM_RESULT_ActsAsApi__Collection_as_api_response_1_row_guid != StringVal('')) :: taken
   TREE-MISSING (SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_8_rows != 0) :: taken
   TREE-MISSING (SYM_RESULT_ActsAsApi__Collection_as_api_response_2_row_text_has_mention == True) :: taken
   TREE-MISSING (SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_7_rows != 0) :: taken
   TREE-MISSING (SYM_RESULT_ActiveRecord__Relation_evilq_act_public_1_not_found == True) :: taken
   TREE-MISSING (SYM_RESULT_ActiveRecord__Relation_evilq_act_public_1_text_has_mention == True) :: taken
   TREE-MISSING (SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_likes_de8fde22_rows != 0) :: not_taken
   FORECLOSURE-GATE  5824  (assoc_root_text_has_mention == True) :: taken
   FORECLOSURE-GATE  2940  (SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_rows != 0) :: not_taken
   FORECLOSURE-GATE  1088  (SYM_RESULT_ActsAsApi__Collection_as_api_response_3_row_text_has_mention == True) :: taken
   FORECLOSURE-GATE   992  (SYM_RESULT_ActiveRecord__FinderMethods_find_by_9_not_found == True) :: not_taken
   FORECLOSURE-GATE   576  (SYM_RESULT_ActiveRecord__FinderMethods_find_by_7_not_found == True) :: taken
   FORECLOSURE-GATE   464  (SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_mentions_66022a8b_rows != 0) :: not_taken
   FORECLOSURE-GATE   454  (SYM_RESULT_ActiveRecord__FinderMethods_find_by_3_not_found == True) :: taken
   FORECLOSURE-GATE   416  (SYM_RESULT_ActiveRecord__FinderMethods_find_by_3_text_has_mention == True) :: taken
```

Population: `_snapshot_pruned_20260910.txt`, 14 742 distinct outcome
profiles of the preflight's 96 357 dumps — an EXACT prune, verified
(§16). Pins were NOT installed when this pass started, so this is the
pre-pin, pre-drive state: **this endpoint's first-ever §16b measurement**.
The preflight's attempt was OOM-killed inside the LOAD at 3 GB and printed
nothing at all.

## §39. PASS B — the PINNED pass on the grown corpus

Run ALONE, after pass A exited (coordinator directive §36).


## §48. Round BV3B0910, and the STRIDE lesson arriving on this endpoint

The §46.8-§46.10 repairs changed what a run records, so the round was re-run on
the repaired rig rather than the BV3A corpus being treated as final.

```
_chunk_drive.sh _v3_seeds_C0910.json BV3B0910 625  (all four variants)
   16 of 16 jobs consumed=625/625, tries=1, toxic=0, 0 aborts
   corpus 109 607 -> 119 607 dumps (+10 000)
   prune  119 607 -> 25 571 distinct outcome profiles
```

| snapshot | dumps | distinct outcome profiles |
|---|---|---|
| p2 (pre-drive) | 99 448 | 14 806 |
| p3 (after BV3A0910) | 109 527 | 19 955 |
| **p4 (after BV3B0910)** | **119 607** | **25 571** |

**+20 000 bulk runs bought +10 765 distinct outcome profiles**, against
TR0910w's +64 for +3 024 rooted runs.

### The tree layer at p4

```
distinct tracked exprs: 138        (101 at p1, 102 at p2, 103 at p3)
one-sided (pre-Z3):      25        PINNED 8    NOT pinned 17
all 8 ARGUMENT P pins:   HOLD, falsifying side never seen
```

**`(SYM_RESULT_Anonymous_process_2 == '')` is GONE from the residual** — closed
by driving, exactly as §46.9/§46.10 intended. That is the first tree gap this
endpoint has closed by WIDENING A MOCK rather than by pinning it.

### And a fourth instance of the STRIDE defect — this one self-inflicted

Nine of the seventeen unpinned one-sided entries are the NEW `_text_empty`
dimensions, observed only False, e.g.

```
(SYM_RESULT_ActiveRecord__Relation_evilq_act_public_1_text_empty == True)   [False]
(SYM_RESULT_ActsAsApi__Collection_as_api_response_1_row_text_empty == True) [False]
```

and the round DID seed that family both ways — measured on its own dumps:

```
..._evilq_act_vis_1_text_empty      seeded False 142 / True 108
..._find_by_3_text_empty            seeded False 128 / True 122
..._records_N_row_text_empty        seeded False 524 / True 476
```

**The seeded names and the one-sided names are different names.** The v3
universe for round BV3B was built when W10 existed in only ~5 dumps of 109 607,
so it captured only the CONTEXTS those five runs happened to exercise
(`evilq_act_vis`, `find_by_3/6/9`, `records_1..4`) and never the `_public_` /
`_author_` / `as_api_response_N` contexts the canonical names denote. This is
notifications' §7.3(b) stride defect in its purest form — *a variable minted in
3 dumps of 109 401 was missed, and a whole tree_missing target was unreachable
BY CONSTRUCTION* — and it is self-inflicted here: the dimension was added, then
the universe was rebuilt while the corpus barely contained it.

**Fix and round BV3C0910**: the universe is rebuilt at `--max-scan 40000`
(stride 3 over 119 607, i.e. 39 869 dumps scanned) now that 10 000 dumps carry
the dimension, and the round is re-run.

```
seed universe: 123 bool, 22 len, 89 count, 60 emptyable-string, 1 request-param
               = 295 DIMENSIONS   (256 at §45, 260, 278, now 295)
corpus varies 221 of 295:  bool 112/123   len 22/22   count 86/89
```

**The lesson generalises and is worth carrying:** after ADDING a seed dimension,
the universe must be rebuilt from a corpus that already exercises it broadly, or
the seeder covers only the handful of contexts the first few runs happened to
produce. A dimension's NAME carries its context on this framework, so "the
dimension is seeded" and "the dimension is seeded where the checker looks" are
different claims.

## §38b. PASS A — reading its verdict (the baseline, 3 h 41 m of solver)

```
COMPLETE=False; NODES=101; MISSING=1418; BLOCKING=1418; PCS=497991
GENUINE=True;  TRUNCATED=True; SOLVER_LOST=0; UNEVALUABLE=[]
DEMAND_SETS=563; TREE_COMPLETE=False; TREE_MISSING=11
FORECLOSURES=17734; FORECL_IGNORED=2171; FORECL_PROVISIONAL=True
peak RSS 1 645 MB;  wall 13 293.1 s
dump_errors={'ActionView::Template::Error': 5533, 'Diaspora::NonPublic': 810,
             'ActiveRecord::RecordNotFound': 775}
```

Three readings, and the third is the one that matters.

**(a) §16b bought 37 % of the set-level demand.** Against the §16 pass on the
same corpus (`_bak_coverage_summary_16set_20260910.json`: `missing_branches
2248`, `demand_sets 563`, `tree_nodes 101`), the foreclosure-aware rule gives
`missing_branches 1418` on an IDENTICAL demand-set count and node count —
17 734 foreclosures inferred, 2 171 ignored. Neither number is a gap SIZE:
`truncated: TRUE` with `SOLVER_LOST=0` and `UNEVALUABLE=[]` means the cap
`MAX_MISSING_PER_CLIQUE` stopped the per-set search, so 1 418 is a GROUP COUNT x
cap (STATE_HANDOFF standing correction 5), and `missing[]` records 400 of them
because pass A imported `coverage_report.py` before §30 raised that cap.

**(b) `TREE_MISSING=11` matches `_tw/targets.json` exactly** — the same eleven,
with the same sides, that §8 derived independently from the corpus. The
independent prediction of §28 is confirmed on the point it could be checked, and
**the five `photos` self-compares do NOT appear**, so Z3 correctly excludes
`X != X`: notifications' §1.1 self-compare defect does NOT reproduce here. That
was the pre-registered question and it has a clean answer.

**(c) It is a verdict about a corpus that no longer describes this endpoint.**
`dump_errors` says it plainly: **5 533 of its 14 742 profiles terminate in
`ActionView::Template::Error`** — the §12 regression. Pass A is the honest
baseline it was designed to be and it is not a statement about the repaired
endpoint (§46.11).

## §49. THE HTML CORPUS — measured, and it splits into two very different halves

The brief's step 3: every html dump written before the §12/§42/§46 fixes is
crash-truncated. Under §16b a partial walk blocks only a CLOSED PREFIX, so they
are not HARMFUL — but they are not evidence of the html arm either. Both halves
measured, on the fixed snapshot `_snapshot_20260910_p4.txt` (119 607 dumps),
routed through the engine's own load path, with the fix boundary taken as the
mtime of `targets.rb.pre_htmlrender` (the copy made immediately before the W7
edit — an objective timestamp, not a label guess). `_html_corpus_measure.py`,
NEW. **Nothing was deleted.**

```
                 dumps   distinct CUBES   distinct EVALUATION SETS
  html-pre       53714            7119                         86
  html-post      10078            5352                        629
  json-pre       45737            7690                        229
  json-post      10078            5686                       1596
```

### Terminals, by class — the §12 regression's full extent, and its end

```
  html-pre   ActionView::Template::Error  41998   <- 78 % of every pre-fix html dump
             Diaspora::NonPublic           6459
             ActiveRecord::RecordNotFound  5252
             NotImplementedError               5
  html-post  <ok>                          3520   <- the arm reaching the end of the view
             ActiveRecord::RecordNotFound  4959
             Diaspora::NonPublic           1598
             NotImplementedError               1
```

**Before the repairs: 0 html runs completed, ever. After: 3 520 do**, and every
other post-fix html terminal is an APPLICATION terminal.

### (b) Does the pre-fix html corpus contribute anything the post-fix one does not?

```
  cubes ONLY in pre-fix html            : 6887   (of its 7119)
  evaluation SETS only in pre-fix html  :    3   (of its   86)
  cubes only in pre-fix html and in no json dump either: 6887
```

**The answer is different at the two levels the §16b verdict uses, and that is
the whole finding.**

* **At the SET level — the level the DEMAND UNIVERSE is built from
  (`maximal_sets` over evaluation sets) — the pre-fix html corpus is almost
  entirely redundant: 3 sets out of 86.** 53 714 dumps, 78 % of them dying in
  the same view error, produce **86** distinct evaluation sets; 10 078 post-fix
  dumps produce **629**. The post-fix html arm is 7.3x richer in demand
  structure from a fifth of the runs.
* **At the CUBE level — the level COVERAGE is measured at — they contribute
  6 887 distinct outcome profiles that nothing else in the corpus contains.**
  That is coverage, not demand: those runs really happened and really exhibited
  those assignments. Deleting them would DELETE COVERAGE and could turn a
  covered assignment into a missing one, which is precisely the direction §16b
  forbids.

So the honest disposition is the one the brief anticipated and the numbers now
support: **KEEP them, and do not read them as evidence of the html arm.** Three
of the 86 sets are theirs alone (`dump_auth_html0001_CSSPOST0910.json`,
`dump_auth_html3568.json`, `dump_anon_html0250.json` are the exemplars the tool
names), so removing them is not even free at the demand level.

### The rig terminals, named, since `rig_crash_census` will FAIL on them

Six dumps in 119 607 terminate inside the rig, and **all six are this drive's
own differentials** — they are the runs that NAMED each failure point:

```
  pre-fix   dump_auth_html000{1,3}_CSSPOST0910   SymbolicString#scrub   (§14's differential)
  pre-fix   dump_auth_html000{1,3}_HTMLA0910     SymbolicString#scrub   (§46.1's no-op differential)
  pre-fix   dump_auth_html0001_SCRUBDIAG         SymbolicString#scrub   (§46.2's first diagnostic)
  post-fix  dump_auth_html0001_EMPTYTXT2         SymbolicInt#coerce     (§46.10's W11 differential)
```

Every other terminal in 119 607 dumps is an application terminal. Disposition is
§35's and unchanged: KEPT, and the census FAIL reported rather than engineered
away — removing runs is the direction that can CREATE a foreclosure.

**One dump WAS moved out of the corpus, and only one** (`_diag_dumps/`, with its
reason in `_diag_dumps/README.txt`): `dump_auth_html0001_SCRUBDIAG2.json`, the
§46.2 enumeration run, whose NON-FATAL diagnostic `scrub` let it record four
path conditions the shipped configuration cannot record. Leaving it in would put
four expressions into the demand universe that no shipped run can ever evaluate
— a `tree_complete` unreachable BY CONSTRUCTION because of a diagnostic. That is
the one case the "never remove a run" rule does not cover: the rule protects
runs the shipped rig CAN produce. It is moved, not deleted, and named here.

## §50. Round BV3C0910, and the TREE LAYER PREDICTED CLEAN

```
_chunk_drive.sh _v3_seeds_D0910.json BV3C0910 625  (all four variants)
   16 of 16 jobs consumed=625/625, tries=1, toxic=0, 0 aborts
   corpus 119 607 -> 129 607 dumps (+10 000)
```

Terminal census, stride-10 over the round's own 10 000 dumps — **application
terminals only, no rig terminal, no template error:**

```
auth_html  <ok> 170  RecordNotFound  80
anon_html  <ok>   1  RecordNotFound 164  Diaspora::NonPublic 85
auth_json  <ok> 222  RecordNotFound  28
anon_json  <ok>  54  RecordNotFound 133  Diaspora::NonPublic 63
```

### The corpus, over the three bulk rounds

| snapshot | dumps | distinct outcome profiles |
|---|---|---|
| p2 (the state this drive inherited) | 99 448 | 14 806 |
| p3 (+ BV3A0910) | 109 527 | 19 955 |
| p4 (+ BV3B0910) | 119 607 | 25 571 |
| **p5 (+ BV3C0910)** | **129 606** | **31 054** |

**30 000 bulk runs -> +16 248 distinct outcome profiles.** For comparison, the
3 024 rooted runs of TR0910w bought 64.

### The tree layer at p5 — 8 pinned, 5 self-compares, and NOTHING ELSE

`_tree_census_p5final.log`, over the exact prune of p5 (31 054 profiles),
through the engine's own load path:

```
distinct tracked exprs: 137
observed on ONE side only (tree-gap CANDIDATES, pre-Z3): 13
   PINNED by ARGUMENT P: 8       <- all HOLD, falsifying side never seen
   NOT pinned:           5       <- ALL FIVE are `X != X` self-compares
        (..._records_photos_{2c7fa358,33150e22,8687d6e6,9930492e,e035b5b3}
             _row_status_message_guid  !=  <the same variable>)
```

**Every one-sided expression on this endpoint is now either a counted,
reversible, falsifiable pin or an unsatisfiable self-compare** — and pass A
established EMPIRICALLY that Z3 excludes the self-compares (its `TREE_MISSING`
was exactly the eleven `_tw` targets and contained none of them). So the
predicted `TREE_MISSING` on p5 is **0**, and it is recorded as a prediction in
`_p5_pass_stage.sh` BEFORE the pass runs, so the pass can contradict it.

What closed between p4 and p5 was the nine `_text_empty` and two
`CollectionProxy#size` / `Calculations#count` entries — driven, once the seed
universe was rebuilt from a corpus that actually contained those dimensions
(§48). Nothing was pinned to achieve it.

### The three tree entries that were CLOSED BY DRIVING across this whole drive

| entry | how |
|---|---|
| `..._as_api_response_2_row_text_has_mention == True` | TR0910a rooted seed (§9) |
| `..._evilq_act_public_1_{not_found, text_has_mention} == True` | TR0910a rooted seeds (§9) |
| `..._records_likes_de8fde22_rows != 0 :: not_taken` | TR0910a rooted seed (§9) |
| `(SYM_RESULT_Anonymous_process_2 == '')` | **W10 + W11: the MOCK was widened, not pinned** (§46.9) |
| the 9 `_text_empty` and 2 count/size entries | BV3C0910, after the universe rebuild (§48) |

## §52. STATE AT HAND-OFF — what is done, what is running, and the ONE blocker

### Done and verified this session

* **The html arm COMPLETES.** Three failure points named with differentials
  (§46.2), one previously-named one shown to be a measured no-op (§46.1), three
  carriers installed (§46.3), the D1 item at `Person#name` decided and removed
  with its re-measurement (§46.5). 0 template errors and 0 rig terminals in
  every smoke since.
* **Two new defects found by measuring this drive's own output**: the
  boundary-override argument-name trap (§46.8, RAISED as X9 — it is a property
  of the shared interceptor) and the two-valued `text` model (§46.9, fixed as
  W10/W11, which opened the `posts.show.photos_by` arm the corpus had never
  driven).
* **Three bulk v3 rounds, 30 000 runs, 0 aborts, 0 toxic seeds**, taking the
  seed universe from 48/256 dimensions varied to 221/295 and the corpus from
  14 806 to 31 054 distinct outcome profiles.
* **The tree layer is clean**: 8 pins (all holding, one NEWLY REQUIRED and
  installed on freshly measured evidence, §47.3) and 5 unsatisfiable
  self-compares; predicted `tree_missing = 0`.
* **The html corpus is measured** (§49): pre-fix html contributes 3 of 86
  evaluation sets that post-fix does not, and 6 887 distinct cubes; KEEP.
* **Pass A landed**: the endpoint's first-ever §16b verdict (§38b).

### Running, detached, self-recording

```
pass B  (pinned, p2 population)          -> appends §39
_c7_audits.sh at 6 GB                    -> appends §40
_html_diff_stage.sh                      -> appends §43
_p5_pass_stage.sh  (NEW, queued last)    -> appends §51   <- THE ONE THAT MATTERS
```

Each waits on the previous BY PID, so this drive never holds more than one
>1 GB job of its own.

### THE BLOCKER, named with its number

**A §16b pass on the post-repair corpus has not yet returned, and it is
pass-bound.** Pass A took **13 293 s (3 h 41 m) of solver on 14 742 profiles**
with `MAX_MISSING_PER_CLIQUE=4`. The p5 population is **31 054 profiles**, 2.1x
larger, and stage 5 runs it at `MAX_MISSING_PER_CLIQUE=16`. Load is not the
cost (peak RSS 1 645 MB, 90 s) — it is all solver.

**So the demand-round loop on this endpoint is pass-bound, and the factor is
this: every demand round needs a pass to seed it and a pass to judge it, at
~4 h each, against a drive that produces 10 000 runs in 25 minutes.** The
brief's step 4 (graph-guided rooted demand rounds, `MAX_MISSING_PER_CLIQUE=16`,
per-key explanation, stop below ~0.05/run for two rounds) cannot start until
§51 returns, and no demand round has run.

Solver-call batching in `src/` is NOT authorized and was not attempted; the
measurement above is the number that request needs (§44(c) already carries the
§16-era figure; this is its §16b successor on a 2.1x population).

### Two things the next agent must NOT assume

**(a) Pass B is running with EIGHT pins, not §29's seven.** The 4th P1 entry
(`records_5`, §47.3) was installed at 21:27 and pass B launched at 21:57, so its
line reads `[assumptions] declared=553 INERT(...)=418 OVERNIGHT_PINS=8`. The
8th pin is INERT on pass B's population — the `records_5` canonical name is
minted by the bulk rounds and does not exist in the p2 corpus — so the A-vs-B
comparison §29 designed is unaffected. Recorded so the discrepancy is not read
as a defect.

**(b) The shim layer is STALE and must be re-run before any completion claim.**
§17's 13 PASS / 9 PROTOCOL / 0 FAIL was measured against 22 shims. This drive
added four declarations (`W7` x3 on `Processor.process` / `MessageRenderer#title`
/ `Photo#url`, `W11` on `CollectionProxy#size`), one singleton stub (`W8`
`Person.name_from_attrs`), one new class (`PcVisibleConcreteString`), and
DISABLED four boundary declarations. `shim_tests.rb` has not been re-run against
that. The completion gate is `SKIP_COMPLETION=1` on every pass this drive ran,
so no number here depends on it — but `complete: true` does, and it is open.

## §53. PHASE 3 — the exact enumerator MEASURED, and what it says

> Numbering note: the brief said "append from §52", but §52 (STATE AT HAND-OFF)
> was already written by the previous drive. This continues at §53. §51 is still
> RESERVED for `_p5_pass_stage.sh`, which appends it when the queued pass lands.

### §53.1 The brief, and what was NOT done

Owner directive 2026-09-10: *"the batching should happen at the driver level"* —
targets come from the exact enumerator, one seed per remaining cube, the
checker pass runs ONCE to certify. **No `src/` change was made or attempted;
no solver-call batching exists in `src/`.** Every file touched tonight is inside
`reports/diaspora/results3/posts_show/`:

```
_exact_enum_emit.py   NEW  — the ported census + (a) the src/ memory fix and
                             (b) the REMAINING-CUBE EMITTER
_setshape.py          NEW  — why the demand universe is the size it is
_consistency_check.py NEW  — brief step 3, checker `missing[]` vs enumerator
_p3_round.sh          NEW  — one phase-3 demand round, end to end
_enum_cost_p5.sh, _setshape_run.sh, _p3_measure_queue.sh, _p3_round_queue.sh
_demand_root.py       + `SUMMARY_IN` (target source) and `DEMAND_TAG` (output
                        suffix); default behaviour unchanged
```

### §53.2 STEP 1 — enumerator cost on the p5 snapshot. IT IS CHEAP.

Run beside pass B (which is a coverage pass and was NOT disturbed), capped at
`MemoryMax=4G` in `concolic-cov.slice` so it could never take the machine down,
`timeout 3600`, `python3 -u`, PID-waited, `JAVA_TOOL_OPTIONS` unset.
`_enum_p5_cost.log`, **EXIT=0**:

```
DUMP_LIST _snapshot_pruned_p5.txt: 31 054 dump files (fixed snapshot)
loaded 31054 runs
evaluation sets=160 -> demand sets=1805
foreclosures inferred: 550 (gate,outcome)->decision pairs over 55 gates
tree_missing=0  tree_complete=True
nodes(active)=137 untracked=0 pinned=8 cliques=1805 (built in 283s)

EXACT: nodes=137 cliques=1805 satisfiable=48548318047288 covered=482516
       remaining=48548317564772 bounded_cliques=0 wall=46s
FORECLOSURE: applied=31682 pairs; leaf groups=90068
clique width histogram (top): 39x178, 40x172, 38x142, 41x127, 37x96,
                              24x83, 33x80, 42x79, 22x75, 23x68
wide sets (width>=13): 1796 holding 48548317560914 of the remaining
```

**Cost, the number step 1 asked for:**

| | |
|---|---|
| wall, end to end (`/usr/bin/time -v`) | **5 min 31 s** |
| of which: load 31 054 dumps | ~4 min 40 s |
| of which: universe build (parseable + adj + projection + foreclosure + tree) | 283 s cumulative |
| of which: **the census itself** | **46 s** |
| peak RSS | **3 269 536 kB = 3.19 GB** (cap 4 GB, never hit) |
| `bounded_cliques` | **0 — the count is EXACT, not a bound** |

**VERDICT: TRACTABLE, comfortably.** It is ~40x cheaper than a checker pass
(pass A: 13 293 s of solver on a corpus half this size). The brief's worry —
that 33-36-decision-wide sets would make exact enumeration impossible — does
not materialise, because the census never enumerates a set's 2^w: it factorises
each set into variable-connected COMPONENTS and multiplies. The width is
irrelevant to the cost. It is **not** irrelevant to the answer.

### §53.3 The finding that changes the plan: the demand universe is 4.85e13

```
satisfiable  48 548 318 047 288      (4.85e13)
covered             482 516          (4.8e5)
remaining    48 548 317 564 772      — 0.000001 % covered
```

For comparison, notifications_index on 96 148 profiles — **three times this
corpus** — reports `satisfiable=65 140 covered=40 955 remaining=24 185`.
posts_show's demand universe is **745 million times larger than
notifications'**, on a third of the corpus.

The single widest set makes it concrete: `set width=45, sat=2 147 483 648 000,
covered=68`. That is 2^31 x 1000 satisfiable assignments over 45 decisions, of
which the entire 31 054-profile corpus has observed sixty-eight.

**This is not a driving problem and no number of demand rounds touches it.**
Even at notifications' best-ever rooted rate (DR3, 0.185 assignments closed per
run), closing 4.85e13 assignments needs 2.6e14 runs; this rig produces 10 000
runs in ~25 minutes, so that is ~1.2e7 years. At the measured per-profile rate
of this corpus (482 516 covered / 31 054 profiles = 15.5 assignments per
distinct profile) it is ~3.1e12 further distinct profiles.

**Consequence for the brief's step 2 as written.** "Build one graph-guided seed
per remaining cube" cannot mean one seed per remaining ASSIGNMENT here — there
are 4.85e13 of them. It can only mean one seed per remaining CUBE of the
disjoint decomposition, and there are ~10^5 of those, each carrying ~10^8
assignments of mass. A round is therefore a MEASUREMENT of the method, not an
attempt at closure, and it is run below as exactly that, pre-registered as
exactly that.

**And it breaks the stop rule.** The brief's rule is "<0.05 closed/run for two
batches -> stop with the number". A rate-based rule is blind to the
denominator: this endpoint can post 0.185 closed/run — notifications' best —
for the rest of the year and never move `remaining` by one part in 10^9. The
number that decides this endpoint is `remaining / rate`, not `rate`.

## §54. WHY it is 4.85e13 — measured, and it is NOT the solver

`_setshape.py` on the same p5 snapshot (`_setshape_p5.log`, **EXIT=0**, 281 s,
same load path, same assumptions, same universe: `evaluation sets=160 -> demand
sets=1805`, `tree_missing=0`). The census factorises each demand set into
VARIABLE-CONNECTED COMPONENTS and multiplies their satisfiable counts — so the
question "is the 2^w forced by Z3 coupling, or by the dependence graph?" is
answered by looking at the components.

```
[assumptions] declared=1118 INERT(never-co-evaluated, not declared)=767 OVERNIGHT_PINS=8

DEPENDENCE EDGES: 8206 adjacent pairs over 137 active exprs
   of those sharing NO Z3 variable: 8201 (99.9%)

component-size histogram (size x count):  1x55192,  2x1180
sets whose components are ALL SINGLETONS (fully variable-disjoint): 1313/1805
SET-LEVEL satisfiable (no foreclosure prune) total = 509 859 148 502 096

TOP-10 sets by satisfiable:
  set#0  width=45 components=45 sat=8796093022208
  set#1..8  width=44 components=44 sat=4398046511104   (x7)
  set#16,17 width=43 components=43 sat=4398046511104
```

**Read those three numbers together.** Of the 8 206 pairs the dependence graph
joins, **8 201 — 99.9 % — share no Z3 variable**. No component anywhere in the
universe is larger than **2** (55 192 singletons, 1 180 pairs, nothing else).
The widest set has 45 members and **45 components**.

**So the 4.85e13 is not solver coupling. It is the dependence graph demanding
the full product of decisions that Z3 cannot relate at all.** The complete
graph on 137 nodes has 9 316 pairs; 1 110 of them are already cut by this
batch's declarations (`declared=1118`), and 8 206 remain. The foreclosure
relation then cuts the set-level 5.10e14 down to 4.85e13 — a 10.5x reduction,
real but nine orders of magnitude short.

### The 45 members of the widest set, by family

```
 9 x  FinderMethods_find_by_<1..9>_not_found            nine independent finders
 8 x  <row>_text_has_mention                            one per ROW of a result
 8 x  <row>_text_empty                                  one per ROW of a result
 5 x  SYM_LEN_..._{mentions,likes,participations}_rows != 0
 4 x  ..._photos_<hash>_row_status_message_guid != <itself>   (the SELF-COMPARES)
 3 x  assoc_{profile_nsfw, status_message_text_*, root_text_*}
 1 x  (Length(SYM_PARAM_id) < 16)
 ...  SYM_LEN_Calculations_ids_1_ids != 0, ActsAsApi row predicates
```

These are per-ROW and per-FINDER predicates. `as_api_response_1_row_text_empty`
and `as_api_response_4_row_text_empty` are decisions about the text of two
DIFFERENT rows, on two different symbolic variables. The engine demands their
2x2; nothing in the code or the solver relates them.

### What this means, stated plainly

**posts_show's combination layer cannot be closed by driving, and the lever is
the ASSUMPTION layer, not the corpus.** The remaining work is ~8 200 pairwise
independence decisions, each of which needs a ground-truth differential under
DISCIPLINE — it is a boundary/assumption question for the coordinator, not a
demand-round question, and it is far larger than one night.

This is a Class-S/B-shaped finding about the ENGINE'S DEMAND MODEL on an
endpoint whose action reads many rows, and it is RAISED as such. It is the
reason the phase-3 loop cannot terminate here, and it is not fixed by any
number of rounds.

## §55. Round DR3P0910 — PRE-REGISTERED, before a single seed was built

Recorded at 2026-09-10 23:4x, while the round was still queued behind the
measurement stages and before `_exact_enum_emit.py` had emitted anything.

### What the round is

`_p3_round.sh DR3P0910 _snapshot_pruned_p5.txt`, `EMIT_MAX_PER_SET=4`,
`CHUNK=250`, `DRIVE_PAR=2`, unique `LABEL_SUFFIX` per chunk via
`_demand_drive.sh` -> `_chunk_drive.sh`, abort-checked. Five stages, each with
its own printed verdict: enumerate+emit -> `_demand_root.py`
(`SUMMARY_IN=` the enumerator's cubes) -> chunked drive -> re-snapshot + exact
prune -> **re-enumerate**. NO checker pass anywhere in the loop; that is the
whole point of the driver-level directive.

### The targets are CONSTRUCTED, not sampled

Each emitted entry is a REMAINING CUBE of the disjoint decomposition of one
leaf group: a partial assignment that (i) agrees with the leaf group's gate
prefix — so it already carries `g != o` for every foreclosing `(g, o)` on the
path to its members, taken from the checker's OWN `infer_foreclosures` relation
rather than re-derived — and (ii) contains no assignment any run has observed.
The decomposition is checked per set: the pieces' model counts must sum to
`sat - covered`, and a set where they do not is printed as `EMIT-MISMATCH`.
On the 400-dump smoke run this held on **10 of 10 sets, mismatch_sets=0**.

Cubes whose members put a PINNED one-sided expression on its untracked side
carry zero models (`comp_models` filters them, so they are never in
`satisfiable` and never in `remaining`) and are SKIPPED AND COUNTED as
`zero_pieces` — the brief's declared-not-driven rule, automatic here rather
than a special case.

### The pre-registration

**Reference.** notifications_index's rooted graph-guided seeds, its best
measured rates: **DR3 = 0.185 assignments closed per run** (15 630 runs, 2 897
closed), **DR5 = 0.157** (402 runs, 63 closed); its bulk v3 = 0.0004; its
counterexample-on-an-arbitrary-base = 0.014.

**Predicted for DR3P0910**, stated as a range because posts_show's cubes are
wider and its seeds root on a corpus 2x richer than notifications' at DR3:

1. **rate**: 0.05-0.5 assignments closed per run. Anything at or above
   notifications' 0.157 confirms the method transfers; below 0.05 fires the
   brief's stop rule.
2. **absolute**: of the order 10^3-10^4 assignments closed.
3. **fraction of the gap**: `closed / 48 548 317 564 772` <= **2e-10**.

**(3) is the pre-registration that matters, and it is a prediction of
FAILURE-TO-CLOSE that is independent of (1).** The round can hit
notifications' best rate and still be, to ten significant figures, exactly as
far from `remaining = 0` as it started. If (3) comes out materially larger than
2e-10 — say 1e-6 — then the 4.85e13 is wrong and §53/§54 must be re-derived;
that is this round's falsifier.

**A second, sharper falsifier.** The three bulk rounds took the corpus from
14 806 to 31 054 profiles with 30 000 runs. The p2 census (queued) gives
`covered(p2)`; `covered(p5) - covered(p2) = 482 516 - covered(p2)` over 30 000
runs is the BULK rate in the same currency, measured rather than assumed. If
DR3P0910 does not beat that, the graph-guided seeder buys nothing on this
endpoint and the honest report says so.

## §56. BRIEF STEP 3 — the checker and the enumerator, compared on ONE snapshot

### Why against PASS A and not §51

§51 (`_p5_pass_stage.sh`) is queued behind pass B, the audit suite and the html
stage and **has not started**. Pass B has been running 1 h 50 m at the time of
writing and pass A took 3 h 41 m on a corpus of the same size, so §51's own
launch is hours away, and then §51 itself runs 1 805 demand sets at
`MAX_MISSING_PER_CLIQUE=16` against pass A's 563 sets at 4 — a ~13x solver
ratio on top of a 2.1x population. **Estimated §51 wall: 1.5-2 days.**

Pass A, however, is a LANDED §16b pass with its own summary
(`_cov_pruned_baseline.json`) and its own fixed snapshot
(`_snapshot_pruned_20260910.txt`, 14 742 profiles). The same comparison the
brief asks for is therefore available NOW, exactly, on one population — so it
was run there. `_consistency_check.py`, **EXIT=0, 151 s**
(`_consistency_passA.log`).

### Layer A — the universe. TWO of three identical, the third EXPLAINED EXACTLY

| | pass A (checker) | enumerator, same snapshot |
|---|---|---|
| NODES / `tree_nodes` | **101** | **101** |
| DEMAND_SETS | **563** | **563** |
| UNTRACKED | 0 | 0 |
| TREE_MISSING | **11** | **4** |
| PINNED | 0 (pins did not exist yet) | 7 |

`NODES` and `DEMAND_SETS` agree exactly — the two implementations build the
same universe from the same corpus. `FORECLOSURES` is not comparable as
printed: the pass reports 17 734 APPLIED pairs (summed over sets), the
enumerator's `A.` line reports 633 INFERRED pairs — two different quantities,
recorded here so the next reader does not read a 28x "disagreement" into it.

**The TREE_MISSING difference is the PIN TIER, and the set identity is exact.**
Pass A launched 18:14, before any pin existed (§38); the tier was installed at
21:27 (§47.3). Pass A's eleven entries minus the seven that the tier pins on
this population are, member for member, the enumerator's four:

```
pass A's 11:                                              pinned?
  records_{10,8,7}_rows != 0                     :: taken   YES (P1) x3
  as_api_response_{1,2,3,4}_row_guid != ''       :: taken   YES (P2) x4
  as_api_response_2_row_text_has_mention == True :: taken   no
  evilq_act_public_1_not_found == True           :: taken   no
  evilq_act_public_1_text_has_mention == True    :: taken   no
  records_likes_de8fde22_rows != 0           :: not_taken   no
                                                            ----
enumerator's 4 = exactly the four "no" rows.
```

Not a defect in either implementation: a measured, one-directional effect of a
declaration tier that did not exist when the pass ran. (`records_5`, the 8th
pin, is INERT here — its canonical name is minted only by the bulk rounds, so
7 of 8 apply, exactly as §52(a) recorded in advance.)

### Layer B — containment

```
witnesses checked            : 400   (the summary's cap; the log's MISSING=1418
                                      is the set-level count, not the witness list)
IN the enumerator's remaining: 216
UNSAT under the pin scope    : 184
ALREADY OBSERVED in corpus   :   0
expression not in the universe:  0
```

**`ALREADY OBSERVED = 0` and `not in the universe = 0` are the two directions
that would have been bugs, and both are clean.** Not one of pass A's 400
witnesses demands something this corpus already contains, and every expression
it names is in the enumerator's universe.

The 184 are again the pin question, and they are NOT yet fully explained: 48 of
the 400 demand a pinned expression directly on its untracked (True) side, which
accounts for 48, not 184. The remaining 136 must be indirect — a pin applied at
the CHECKER'S SCOPE (over the whole demand set, the people_stream rule the
enumerator's `--verify` documents) interacting with the set's length bounds.
**A one-variable control is queued** (`NO_PINS=1`, the tier's own documented
off-switch, same snapshot, same summary, same script): if all 400 land IN with
the tier off, the two implementations agree completely and the whole 184 is the
pin tier; if any survive, that is a real disagreement and it is a bug in one of
the two. **This is reported as OPEN, with its control named, rather than
assumed.**

### The reverse direction is NOT checkable, and is not claimed

`missing[]` is capped — at `MAX_MISSING_PER_CLIQUE` per set and, in the shipped
summary, at 400 witnesses overall. The enumerator's remaining set on this
snapshot is astronomically larger, so "a cube in the enumerator and not in
`missing[]`" is the DESIGNED behaviour of the cap, not evidence of a defect.
Only containment is a test, and containment is what was run.

## §57. The shape of the 4.85e13, and a baseline that was DROPPED (with its reason)

### Where the mass sits (`_enum_p5_cost.json`, per-set)

```
sets                                 1805      widths: min 4, median 35, max 45
sets with remaining == 0                5
sets with covered == 0                  0      <- every set has been walked
leaf groups                        90 068
distinct observed cubes            177 235

top    1 set  holds   4.42 % of the remaining
top   10 sets hold   18.35 %
top  100 sets hold   56.43 %
top  500 sets hold   93.46 %
top 1000 sets hold   99.99 %
```

The mass is NOT concentrated in a handful of pathological sets that could be
declared away one at a time: it takes 500 of the 1 805 sets to reach 93 %.
Every set has been walked at least once (`covered == 0` nowhere), so this is not
an unreached-code problem either. It is the product structure of §54, spread
across the whole universe.

### The bulk baseline: the p2 census was STOPPED, and why

`_p3_measure_queue.sh` stage 2 ran the census on `_snapshot_pruned_p2.txt`
(14 806 profiles) to get `covered(p2)`, so that `covered(p5) - covered(p2)` over
the three bulk rounds' 30 000 runs would give the bulk method's rate in
ASSIGNMENT currency (§55's second falsifier).

It built its universe in 143 s (`nodes=102 cliques=567`, consistent with pass
A's 101/563) and then **spent 6 m 30 s of solver inside the census without
finishing set #0 of 567** — against **46 s for the whole of p5's 1 805 sets**.

**The cause is measurable and is worth recording, because it inverts the naive
expectation that a bigger corpus costs more:**

```
pass A population (14 742 profiles):  17 734 APPLIED foreclosure pairs / 563 sets = 31.5 per set
p5 population     (31 054 profiles):  31 682 APPLIED foreclosure pairs / 1805 sets = 17.6 per set
```

§16b infers foreclosure PAIRWISE — `(g,o)` forecloses `d` if **no** run with
`g=o` evaluates `d`. A SPARSER corpus therefore infers MORE foreclosures (many
of them accidents of what has not been driven yet), and each extra gate doubles
the leaf-group tree the census walks. The p2 corpus is half the size and infers
nearly twice the foreclosure density per set, so its census is
**exponentially more expensive than p5's**. Enumerator cost on this endpoint is
driven by foreclosure DEPTH, not by corpus size.

It was blocking the NO_PINS control and the demand round — both on the brief's
critical path — so it was stopped rather than left to burn its 3 600 s timeout.
`_enum_p2.log` carries the same note.

### The substitute baseline, which needs no extra pass

`covered = 482 516` on a corpus produced by **129 606 runs** gives a
CORPUS-WIDE, all-methods-mixed rate of

```
482 516 / 129 606  =  3.72 assignments closed per run
```

That is **20x notifications' best-ever rooted rate (0.185)** — posts_show's
cubes are wide, so a single run closes many assignments at once. It changes
nothing:

```
48 548 317 564 772 / 3.72  =  1.3e13 further runs
```

at 10 000 runs per 25 minutes, **~620 000 years**. The endpoint is not
run-limited by a factor that more driving can move.

## §58. THE CONTROL LANDED — the checker and the enumerator agree EXACTLY

`_consistency_passA_nopins.log`, **exit 0, 144 s**: the same script, the same
snapshot, the same summary, `NO_PINS=1` — the pin tier's own documented
off-switch — as the single changed variable.

**The control reproduces pass A's assumption layer byte for byte**, which is
what makes it a control and not a second opinion:

```
pass A                      [assumptions] declared=543 INERT=411            (no pin tier existed)
consistency, NO_PINS=1      [assumptions] declared=543 INERT=411 OVERNIGHT_PINS=0
consistency, pinned         [assumptions] declared=551 INERT=411 OVERNIGHT_PINS=8   (543+8)
```

### Layer A — every number identical

| | pass A (checker) | enumerator, `NO_PINS=1` |
|---|---|---|
| NODES | 101 | **101** |
| DEMAND_SETS | 563 | **563** |
| TREE_MISSING | 11 | **11** |
| UNTRACKED | 0 | **0** |

and the eleven `tree_missing` entries are **SET-IDENTICAL**, checked as sets and
not as counts: `only in enumerator: []`, `only in pass A: []`.

### Layer B — containment, complete

```
witnesses checked            : 400
IN the enumerator's remaining: 400        <- every one
UNSAT under the pin scope    :   0
ALREADY OBSERVED in corpus   :   0
expression not in the universe:  0
```

**BRIEF STEP 3, ANSWERED: there is NO disagreement between the two
implementations.** On one snapshot, with one assumption layer, `coverage.py`'s
`missing[]` is a subset of `_exact_enum_emit.py`'s remaining set, exactly, 400
of 400; the two build the same universe, the same demand sets and the same tree
residue. The 184 "UNSAT" of §56 were **entirely** the eight-pin tier that was
installed three hours after pass A launched — 48 of them witnesses that name a
pinned expression on its untracked side directly, the other 136 witnesses whose
demand set contains one and which the checker-scope pin rule therefore
constrains. Nothing here is a bug, and nothing is papered over: the pinned run
and the control are both recorded, with the one variable between them named.

**§51 will repeat this comparison on the p5 population when it lands** (ETA
1.5-2 days, §56). Its own pre-registered prediction, `TREE_MISSING = 0`, has
**already been independently confirmed tonight** by `_exact_enum_emit.py` on
the identical `_snapshot_pruned_p5.txt` — `tree_missing=0 tree_complete=True`,
in 5 min 31 s rather than two days.

## §59. PRICING THE LEVER — `_whatif_indep.py`, and its prediction recorded first

§54 says the 4.85e13 is imposed by the dependence graph, not by Z3. The next
question belongs to whoever decides the assumption layer: **what would this
endpoint's demand universe be if those 8 201 variable-disjoint pairs were
declared independent?** `_whatif_indep.py` answers it by MEASUREMENT — the
identical census with exactly one thing changed, `are_independent(a, b)` also
true when a and b share no symbolic variable. Load path, pins, foreclosure
inference, evaluation sets, factorised counting: all untouched, so its output is
directly comparable to `_enum_p5_cost.log`.

**It is a HYPOTHETICAL and it writes nothing.** `coverage_assumptions.py` is not
touched. Under DISCIPLINE every such pair — more usefully, every row/finder
FAMILY — needs its own ground-truth differential before it may be declared.
This only prices the work, and it reports the count of FAMILY-PAIRS (ordinals
and hashes stripped) because that, not the raw pair count, is the number of
declarations someone would actually have to write and evidence.

**Smoke run, 400-profile sample, recorded before the p5 run (which is queued
behind the round's own census):**

```
baseline  : nodes=30 cliques=10 satisfiable=210074 covered=250 remaining=209824
what-if   : nodes=30 cliques=29 satisfiable=58     covered=58  remaining=0
            widths collapse to 1x28, 2x1
            312 widened pairs -> 243 family-pairs
```

**PREDICTION for p5, recorded now:** the demand universe collapses from 4.85e13
to something of the order of 10^2-10^4, and the EXISTING 31 054-profile corpus
covers essentially all of it — `remaining` at or near 0 without a single new run.

**And that is exactly why it is not a free win, which must be said in the same
breath as the number.** If everything variable-disjoint is independent, the
combination claim degenerates to the per-decision (tree) claim, and this
endpoint's tree layer is ALREADY complete (`tree_missing = 0`, §53.2). A
`complete: true` bought this way would assert far less than §21 says a
`complete: true` asserts. The honest statement of the choice is:

* **drive**: 1.3e13 further runs at this corpus's own measured rate (§57) — not
  available;
* **declare**: a bounded number of family-level independence assumptions, each
  needing a measured differential, each SHRINKING what `complete: true` claims;
* **neither**: posts_show's combination layer stays open, with the number.

The decision is the coordinator's. This drive's job was to price it, and it is
priced.

## §60. COORDINATOR RULING 2026-09-11 — the assumption-layer archaeology

Ruling received mid-drive: the 4.85e13 is the assumption layer; the 2026-09-10
co-evaluation simplification deleted posts_show's TIER 0 and "most of its
disjoint-rep declarations (2 895 → 543)"; recover the deleted tiers, classify
them, restore the disjoint-rep kind under its original evidence criteria, gate
it, re-enumerate.

**Round DR3P0910 was STOPPED first**, per the ruling's own instruction — it was
rooting seeds against a 4.85e13 target, which is exactly the "only feeding an
astronomically-sized target" case. Nothing of it shipped; its artefacts were
removed. Pass B and the §51 sequence were NOT touched.

### §60.1 What was actually deleted — the whole diff, not a summary

`reports/` is a git repo; `diaspora/results3/posts_show/coverage_assumptions.py`
was last committed at **f75f9c2 (2026-09-03)** and is modified in the worktree.
`git show f75f9c2:… | diff -u` against the current file, code lines only:

```
REMOVED   def _scenario_of(label)                  (helper)
REMOVED   _SCENARIO_NAMES = (...)                  (constant)
REMOVED   def _tier0_scenario_exclusivity(runs)    (the tier)
REMOVED   if runs: for ia in _tier0_scenario_exclusivity(runs): aset.add(ia)   (wiring)
```

**and NOTHING else.** Every other tier — `_tier1_same_target_pairs`,
`_tier1b_public_gates_attrs`, `_tier2_attempt_chain_pairs`,
`_tier3_cross_context_pairs`, `_tier5_post_found_vs_act`,
`_tier6_len_gates_row_attr` — is present and its body is unchanged. The
2 895 → 543 collapse is **entirely TIER 0**.

### §60.2 The ruling's premise needs one correction, and it matters

> "…and most of its **disjoint-rep** declarations"

**posts_show has never had a disjoint-rep tier.** A grep for
`def _tier*` across every `coverage_assumptions.py` in results2 and results3:

```
notifications_index   _tier0c_dispatch_independence  _tier0d_crossdispatch
                      _tier_guid_foreclosed_by_persisted  _tier1c_empty_list_foreclosure
                      _tier1_samerep_foreclosure  _tier2_disjoint_reps   <-- HAS IT
conversations_index   _tier0_variant_exclusivity _tier1_gates
                      _tier1b_never_coevaluated  _tier2_disjoint_reps    <-- HAS IT
_auth_boundary        ... _tier2_disjoint_reps                            <-- HAS IT
posts_show (results3) _tier1 _tier1b _tier2_attempt_chain _tier3 _tier5 _tier6   <-- NONE
posts_show (results2) _tier1 _tier2_attempt_chain _tier0_scenario _tier3 _tier4 _tier1b <-- NONE
```

`_tier2_attempt_chain_pairs` is a different thing (the evilq/findpublic attempt
chain), not a disjoint-rep tier. So the correct statement of the defect is:

* **posts_show lost TIER 0** — and TIER 0 is the *never-co-evaluated* kind,
  whose whole argument is "these two exprs' observed SCENARIO SETS are
  DISJOINT, so no single run's path contains both". That IS the claim §16 now
  makes for itself from the same evidence, so its deletion was, on its own
  terms, correct. §60.3 measures this rather than arguing it.
* **posts_show never had the tier that would matter** — the disjoint-rep tier
  that notifications kept and did not explode with. The gap is an ABSENCE, not
  a deletion, which is why no `_bak_` file contains it and why the semantics
  record's §2.4 lists only TIER 0.

That distinction is load-bearing: restoring TIER 0 cannot help, and the thing
that can help has to be PORTED and GATED, not recovered.

## §61. STEPS 1-2 MEASURED — TIER 0 is subsumed; the missing tier is worth 1 280 pairs

`_tier_recover.py` on `_snapshot_pruned_p5.txt` (31 054 profiles), **EXIT=0,
284 s**. Nothing was declared by this run — it is a PROPOSAL pass (Rule T3).
The co-evaluation relation it tests against is built by the SAME construction
`build()`'s own filter uses, so "co-evaluated" means here exactly what it means
to the engine.

```
maximal evaluation sets=160   CO-EVALUATED pairs=5162   distinct exprs=137
[assumptions] declared=1118 INERT(never-co-evaluated, not declared)=767 OVERNIGHT_PINS=8
surviving tiers declare (post-filter): 1110 pairs
```

### §61.1 TIER 0 — recovered, measured, and it is GENUINELY SUBSUMED

```
scenario-set groups (expr count per observed-scenario set):
  ['auth_html','auth_json']=30   ['auth_json']=25   ['anon_json','auth_json']=23
  ['auth_html']=21   ['anon_html']=9   ['anon_html','anon_json']=9
  ['anon_json']=8    ['all four']=8    ['anon_html','auth_html']=4

pairs TIER 0 would declare   : 3487
of those CO-EVALUATED on p5  :    0
of those NEVER co-evaluated  : 3487
=> SUBSUMED BY §16           : True
```

**Zero of 3 487.** Restoring TIER 0 would add 3 487 declarations and relax
**nothing** — every one of its pairs is dropped again by the co-evaluation
filter, because its criterion ("disjoint observed scenario sets") and the
filter's criterion ("no run evaluates both") are the same predicate computed
from the same corpus. This is not an argument from the tier's header; it is the
count, on this endpoint's own p5 corpus.

**So the semantics record's §2.4 was RIGHT about TIER 0, and the ruling's
premise that its deletion caused the 4.85e13 is not supported here.** What the
deletion did cost is the `declared` NUMBER (2 895 → 543) — an accounting
change, not a demand change. The 4.85e13 has a different cause, and §61.2 is it.

### §61.2 The tier posts_show never had — sized, under the ORIGINAL criteria

Ported criterion (notifications_index `_tier2_disjoint_reps`): two decisions on
DIFFERENT symbolic reps neither gate nor feed each other. Rep key = the LEFT
VARIABLE with this endpoint's attribute suffixes stripped
(`_status_message_guid`, `_text_has_mention`, `_text_empty`, `_not_found`,
`_public`, `_guid`, `_nsfw`) — the same construction as the source tier's
`_rep_key`, with posts_show's own suffix vocabulary derived from the corpus's
distinct left variables rather than guessed.

```
exprs considered                 :   97 of 137
EXCLUDED BEFORE ANY PROBE, by inherited adjudication:
   length / cardinality (W-E)    :   34     cardinality determines statement shape
   post_key dispatch    (W-C)    :    1     `Length(SYM_PARAM_id) < 16` ROUTES the request
   self-compares                 :    5     unsatisfiable; nothing to declare
distinct REPS                    :   40
cross-rep decision pairs         : 4566
   of those CO-EVALUATED on p5   : 2645     <- these carry real demand
   already declared by tier 1/1b/2/3/5/6 :  858
   NET NEW candidates            : 1787
WITHDRAWN by W-F (inherited)     :  507     not_found x not_found, not_found x identity
   (46 classes touched; 84 of them find_by_<n> x find_by_<n> — this endpoint's
    widest demand set holds NINE find_by_N_not_found decisions, so W-F bites
    harder here than anywhere it was originally adjudicated)
REMAINING TO GATE                : 1280 pairs in 83 REP-PAIR CLASSES
```

**Note the contrast with §61.1, because it is the whole point.** TIER 0's 3 487
pairs are **0 %** co-evaluated. This tier's 4 566 pairs are **58 %**
co-evaluated (2 645). These are pairs the engine DOES demand combinations over,
in the same runs — the "co-evaluated but independent for another reason" kind
the ruling asked for. That is why one tier is subsumed and the other is not.

### §61.3 What is being gated, and at what granularity

83 class representatives, one per rep-pair class, to
`assumption_checker.py --declared` — the same granularity notifications' C7-A
used (14 probes for 14 family pairs). The claim this tier makes is per CLASS
("decisions on a `find_by` rep are independent of decisions on an
`as_api_response_<n>_row` rep"), not per ordinal instance; probing every
instance would re-probe one claim hundreds of times. **A class whose
representative FAILS is withdrawn ENTIRELY, instances included** — the
conservative direction. Run under `flock /tmp/concolic-heavy.lock` so it never
competes with the notifications drive for JRuby.

## §62. X10 — a `src/` DEFECT in the assumption gate, found by running it

The gate aborted on its FIRST posts_show pair, and took all 83 with it:

```
File ".../end_to_end_completion_checker/assumption/assumption_checker.py", line 598, in test_declared
    fab = dict(fa); fab[db] = fb[db]
KeyError: 'SYM_RESULT_..._records_photos_2c7fa358_row_text_empty'
```

### The cause, one line wide: a KEY-SPACE MISMATCH

```python
# assumption_checker.py ~552, flipped_seeds():
    rdim = _runtime_key(sd, dim)     # the RUNTIME (ordinal) key the runner seeds by
    out[rdim] = v                    # <- the flip is WRITTEN at the runtime key

# assumption_checker.py 598, test_declared():
    fab = dict(fa); fab[db] = fb[db] # <- and READ BACK at the CANONICAL key
```

`_runtime_key(sd, key)` is documented as "identity when nothing is aliased".
So the IndependenceAssumption flip-both probe works on an endpoint whose seed
dimensions are NOT ordinal-aliased — which is why notifications' 14-pair C7-A
run never hit it — and raises `KeyError` on every pair of an endpoint that
canonicalizes ordinals. posts_show's manifest sets
`"canonicalize": "gate_canon:canonicalize_for_gate"`, so **every** cross-rep
pair here hits it.

**Consequence beyond this batch: no IndependenceAssumption has ever been
flip-both probed on an ordinal-aliased endpoint.** Any such declaration whose
evidence line says "licensed by the engine's flip-both probe" was licensed by a
probe that could not have run. That is a Rule-T3 question for every batch that
canonicalizes, not just this one, and it is RAISED rather than assumed benign.

**The fix is one line and was NOT made** — no `src/` change is authorized:

```python
rdb = _runtime_key(sd, db)
fab = dict(fa); fab[rdb] = fb[rdb]
```

### A second defect, same run: one bad pair kills the suite

`run_declared` has no per-probe isolation, so a single `KeyError` ended all 83
probes and `_tier2_probe_results.json` was never written. The shell wrapper then
printed `rc=0` because `$?` was read after an intervening `echo` — the harness
looked like it had succeeded. Both are recorded.

### What was done instead

`_tier2_gate_local.py` — a batch-local driver that reproduces
`test_declared`'s IndependenceAssumption branch with that ONE correction and
per-probe isolation. Every helper (`expr_dimension`, `pick_snapshot_with`,
`access_trace`, `flipped_seeds`, `_runtime_key`, `_reading_changed`,
`trace_of`, `ProbeCache`) is IMPORTED FROM THE SHIPPED MODULE and called
unchanged, and the planning/execute/verdict protocol is `run_declared`'s own —
so the verdicts are the engine's, not a reimplementation of them. It also
handles the flip-by-DELETION case (`rdb not in fb`), which the same line would
have raised on: a decision controlled by a key's ABSENCE is exactly the
`__prior` family notifications documented.

## §62b. X10 AUTHORIZED and FIXED in `src/` (2026-09-11)

Coordinator ruling: X10 is a harness CORRECTNESS defect — the probe cannot
execute on canonicalizing endpoints — so fixing it enables verification and
weakens no claim, the same class as the digest key. Authorized, and done.

### The change — `src/end_to_end_completion_checker/assumption/assumption_checker.py`, code lines only

```
-        fab = dict(fa); fab[db] = fb[db]
+        rdb = _runtime_key(sd, db)
+        fab = dict(fa)
+        if rdb in fb:
+            fab[rdb] = fb[rdb]
+        else:
+            fab.pop(rdb, None)            # flip-by-DELETION: a key's ABSENCE
-        test_declared(cfg, a, cache)                    (planning pass)
+        try: test_declared(cfg, a, cache)
+        except Exception: pass
-        r = test_declared(cfg, a, cache)                (verdict pass)
+        try: r = test_declared(cfg, a, cache)
+        except Exception as exc: r = {... "verdict": "ERROR", "detail": f"{type(exc).__name__}: {exc}"}
-        results = run_declared(cfg, declared, keep)
-        if "--json-out" in args: json.dump(...)
+        results = []
+        try: results = run_declared(cfg, declared, keep)
+        finally:
+            if "--json-out" in args: json.dump(...)      # evidence survives a crash
-        bad = [r for r in results if r["verdict"] == "FAIL"]
+        bad = [r for r in results if r["verdict"] in ("FAIL", "ERROR")]   # ERROR is not a pass
```

Nothing else. The `RESULT:` line now reports `ERROR` as its own column.

### The tests are a GROUND-TRUTH DIFFERENTIAL, not an instance test

`src/test_assumption_checker.py`, 4 tests. The fixture is an ALIASED endpoint —
runtime keys `ord_a`/`ord_b`, canonical names `VAR_A`/`VAR_B`, so
`_runtime_key(sd, "VAR_B") == "ord_b" != "VAR_B"` (asserted, so the fixture
cannot silently stop testing the thing).

```
against the PRE-FIX file : Ran 4 tests — FAILED (failures=1, errors=3)
                           KeyError: 'VAR_B'   x2      <- the exact production defect
                           AssertionError: a crash must still leave the results file as evidence
against the FIXED file   : Ran 4 tests — OK
```

The pre-fix run was done by swapping the backup in, running, and swapping the
fixed file back (md5 verified identical afterwards).

### Full `src/` suite

```
test_symbolic.py rc=0   test_interceptor.py rc=0   test_path_explosion.py rc=0
test_assumptions.py rc=0   test_symbolic_func.py rc=0   test_coevaluation.py rc=0
test_query_ops.py rc=0   test_assumption_checker.py rc=0 (NEW, 4 tests)
py_runtime/test_list_rep.py rc=0   ruby_runtime/test_list_rep.rb rc=0
test_ruby_runtime.rb — 65 passed, 0 failed
queries_from_runs/test_queries_from_runs.py — 47 passed
```

### The blast radius is recorded in ONE place

`../_STATE_HANDOFF.md`, "Re-verification required (X10)": the three batches that
canonicalize (`notifications_index`, `people_stream`, `posts_show`) and, per
batch, the count of IndependenceAssumptions whose evidence cites the flip-both
probe — **notifications_index 7 declaration sites / 17 citations**, the other
two zero. `comments_index` and `conversations_index` do NOT canonicalize in
their gate manifests, so their verdicts stand. The final full-engine gate run on
each endpoint re-probes everything by construction, so no separate campaign is
needed; no batch should be certified on a gate result predating 2026-09-11.
This drive did not re-probe other endpoints.

### And the 83 classes are re-run with the SHIPPED gate

`_tier2_gate3.sh` runs the fixed `assumption_checker.py` itself, so the verdicts
ON RECORD are the engine's. `_tier2_gate_local.py` is kept only as a
cross-check; any class where the two disagree is reported.

## §63. THE W-F PAIRS ARE NOT ONE DECISION WITH TWO NAMES — measured, and the hypothesis is REFUTED here

Coordinator question (2026-09-11): two `find_by_N_not_found` decisions may be
ONE symbolic value with two names — the mock memoizes the finder, the second
call returns the same object, the interceptor names by call ordinal, and a memo
hit issues no SQL so the alias has no statement to key on. If so they are
neither dependent nor independent, and the sound instrument is IDENTITY.

`_wf_identity_probe.py`, over a stride-10 sample of the **FULL** p5 corpus
(12 961 of 129 606 dumps — the full corpus, not the pruned list, because seed
diversity is what the question turns on). `_wf_identity.json`.

### The answer: 0 of 36. They are two decisions.

**1. Agreement.** All nine ordinals co-evaluate; 36 ordinal pairs, each
co-evaluated in 2 843 runs:

```
pairs that NEVER disagree (identity candidates) :  0 of 36
pairs that DO disagree                          : 36 of 36
```

and the 2x2 tables have **all four cells populated**, e.g.

```
(1,9)  both_eval 2843  DIFFER 1434   (0,0):1123  (0,1):1289  (1,0):145  (1,1):286
(8,9)  both_eval 2843  DIFFER 1399   (0,0):1121  (0,1):1252  (1,0):147  (1,1):323
(3,7)  both_eval 2843  DIFFER  333   (0,0):2347  (0,1):142   (1,0):191  (1,1):163
```

`found ∧ not-found` is not unsatisfiable here — it is **OBSERVED**, hundreds of
times, in every pair.

**2. Seed contradiction — the decisive one.** If the second name were a memo
hit, its own seed would be ignored and its value would follow the first's.
Every ordinal obeys its OWN seed, with **zero** contradictions:

```
 ord   runs   (seeded -> observed)                                  CONTRADICTED
   1   6355   <unseeded>->0:2985, True->1:1921, False->0:1078            0
   2   6355   <unseeded>->0:2789, True->1:1918, False->0:1253            0
   3   6355   <unseeded>->0:2905, False->0:1909, True->1:1353            0
   4-8 2843   True->1 / False->0 throughout                              0
   9   2843   True->1:1575, <unseeded>->0:972, False->0:296              0
```

`True->0` and `False->1` never occur. Each name is INDEPENDENTLY SEEDABLE.

**3. SQL — a partial hit for the hypothesis, which does not rescue it.**

```
 ord   calls  with SQL   no SQL
   1    6355      4724      1631
   2    6355      4750      1605
   3    6355         0      6355   <- never issues SQL
   4    2843      2759        84
   5    2843      2741       102
   6    2843         0      2843   <- never issues SQL
   7    2843      2827        16
   8    2843      2654       189
   9    2843         0      2843   <- never issues SQL
```

Ordinals **3, 6 and 9 issue no SQL in any call** — consistent with a memo or an
already-loaded association, and consistent with "no statement to key an alias
on". **But they still obey their own seeds (0 contradictions) and still
disagree with every other ordinal in hundreds of runs.** SQL-lessness here is
not identity; it is a decision whose value is decided without a query.

**So on posts_show, re-keying the find_by family by identity would be UNSOUND.**
It would merge decisions this corpus demonstrably drives apart — the `(0,1)` and
`(1,0)` cells are populated for all 36 pairs — and would shrink `remaining` by
erasing real distinctions rather than by removing false demand. The hypothesis
may well hold on notifications, where W-F was originally adjudicated; it does
not hold here, and W-F stays a WITHDRAWAL rather than becoming an alias.

### And the question exposed a defect in THIS drive's own W-F port

Breaking the 507 down by sub-rule to answer the question showed:

```
  453  not_found x "var-var compare"     <- SPURIOUS
   54  not_found x not_found             <- genuine
```

The 453 are not identity compares at all. This port's `_PX_VARVAR` matched
`^\(IDENT (==|!=) IDENT\)$` — and `True` is an IDENT, so every ordinary
`(X == True)` decision matched. notifications' original guards it
(`_is_varvar_identity`: `m.group(2) not in ("True", "False")`); this port
dropped the guard. **Found by measurement, not by review.** Corrected:

```
W-F withdrawals : 507 -> 54   (all of them not_found x not_found;
                               posts_show has NO var-var identity compare
                               that is not a self-compare, and self-compares
                               are excluded before W-F runs)
pairs to gate   : 1280 -> 1733
rep-pair classes:   83 -> 83   (IDENTICAL — so the gate's 83 class verdicts
                                apply unchanged; the correction moves pair
                                counts within classes, not the class set)
```

`_bak_tier2_after_wf_BUGGY.json` keeps the wrong file for comparison.

## §64. THE GATE DOES NOT DISCRIMINATE ON THIS ENDPOINT — tier 2 does NOT ship

### The two gate runs agreed, and both said PASS to everything

```
SHIPPED (post-X10-fix):  RESULT: 83 distinct tested — PASS 83, FAIL 0, ERROR 0,
                         NOT-TESTABLE 0, NOT-COMPARABLE 0      rc=0
LOCAL (cross-check)   :  83 PASS                                rc=0
cross-check           :  83/83 identical verdicts AND identical detail strings,
                         0 disagreements  -> the local driver is a faithful
                         reproduction, and X10's fix is not in question
```

83 of 83 PASS, with no FAIL anywhere, is the shape of a gate that is not testing
anything. It was pre-registered, before the control ran, that this would not be
accepted as evidence on its own.

### The negative control: 6 pairs that MUST fail. All six PASSED.

`_tier2_negcontrol.json` — six pairs that the inherited adjudications, or the
tier's OWN criterion, say are dependent. They are declared nowhere.

```
PASS   len(records_2_rows) != 0        ||  records_2_row_text_empty        (W-E: list x its OWN row)
PASS   find_by_1_not_found             ||  find_by_2_not_found            (W-F)
PASS   find_by_3_not_found             ||  find_by_3_text_empty           (SAME REP)
PASS   find_by_3_not_found             ||  find_by_3_text_has_mention     (SAME REP)
PASS   (Length(SYM_PARAM_id) < 16)     ||  find_by_1_not_found            (W-C: dispatch)
PASS   len(records_2_rows) != 0        ||  photos_..._row_text_empty      (W-E)

RESULT: 6 distinct tested — PASS 6, FAIL 0, ERROR 0, NOT-TESTABLE 0, NOT-COMPARABLE 0
```

**Two of those are SAME-REP pairs.** The tier's own claim is "decisions on the
SAME rep stay dependent" — `find_by_3`'s not-found gate forecloses `find_by_3`'s
own text decision; on the closing arm the text decision is never evaluated at
all. If the gate calls THAT independent, a PASS from it carries no information.

### Therefore

**TIER 2 IS NOT INSTALLED.** `coverage_assumptions.py` is unchanged;
`_bak_coverage_assumptions_pre_tier2.py` was taken and is identical to the live
file. 1 733 declarations that would have collapsed a 4.85e13 demand universe do
not ship on a gate that passes its own negative control. Rule T3 holds: these
stay PROPOSALS.

### Why it cannot discriminate here — the probe's FAIL condition is one-sided

```python
covered = base | set(trace_of(flip_A)) | set(trace_of(flip_B))
novel   = set(trace_of(flip_both)) - covered
FAIL iff novel is non-empty
```

The probe fails a pair only when the COMBINATION **ADDS** a target-call shape
neither single flip produces. That catches dependence that MANUFACTURES a shape
— notifications' W-E, where a cardinality flip turns `= $(key)` into
`IN (?, ?)`, a genuinely new statement. It cannot catch dependence that
**REMOVES** reads, because then flip-both's trace is a SUBSET of flip-A's and
`novel` is empty by construction.

posts_show's dependence is almost entirely of the removing kind: a finder that
does not find, a list with no rows, a text that is empty — each closes a branch
and deletes the reads below it. So the discriminating signal the probe looks for
never arises here, and it returns PASS for everything, correct pairs and
nonsense pairs alike.

**That is a property of the instrument, not of this endpoint's declarations**,
and it is RAISED (X11): the flip-both access-trace probe is SOUND-BUT-INCOMPLETE
as an independence gate — a FAIL is real evidence, a PASS is not evidence of
independence on any endpoint whose dependence is foreclosure-shaped. Every
declaration anywhere whose only evidence is a flip-both PASS inherits this. It
is a different question from X10 (which was "the probe could not run"); this one
is "the probe runs and cannot see this class of dependence".

### What would settle it

A gate that also fails a pair when flip-both's trace is a PROPER SUBSET of a
single flip's — i.e. when one decision demonstrably deletes the other's reads —
or, equivalently, a co-evaluation check: if the two are never both EVALUATED on
the closing arm, they are foreclosed, not independent. The engine already infers
exactly that relation (`infer_foreclosures`); the gate does not consult it.
Proposed, not implemented, and not required for this drive's numbers.
```
pass B exit=1
[assumptions] declared=553 INERT(never-co-evaluated, not declared)=418 OVERNIGHT_PINS=8
COMPLETE=False;NODES=102;MISSING=1414;BLOCKING=1414;PCS=501189
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
dumps_loaded=14806;dumps_unparseable=0
DEMAND_SETS=567;TREE_COMPLETE=False;TREE_MISSING=1;FORECLOSURES=17776;FORECL_IGNORED=2359;FORECL_PROVISIONAL=True
peak RSS 1517 MB
dump_errors={'Diaspora::NonPublic': 810, 'ActiveRecord::RecordNotFound': 777, 'ActionView::Template::Error': 5535, 'NotImplementedError': 2}
wrote /home/dev/project/reports/diaspora/results3/posts_show/_cov_p2_pins.json in 14283.8s
   TREE-MISSING (SYM_RESULT_Anonymous_process_2 == '') :: taken
   FORECLOSURE-GATE  5824  (assoc_root_text_has_mention == True) :: taken
   FORECLOSURE-GATE  2940  (SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_rows != 0) :: not_taken
   FORECLOSURE-GATE  1092  (SYM_RESULT_ActsAsApi__Collection_as_api_response_3_row_text_has_mention == True) :: taken
   FORECLOSURE-GATE   992  (SYM_RESULT_ActiveRecord__FinderMethods_find_by_9_not_found == True) :: not_taken
   FORECLOSURE-GATE   576  (SYM_RESULT_ActiveRecord__FinderMethods_find_by_7_not_found == True) :: taken
   FORECLOSURE-GATE   464  (SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_mentions_66022a8b_rows != 0) :: not_taken
   FORECLOSURE-GATE   462  (SYM_RESULT_ActiveRecord__FinderMethods_find_by_3_not_found == True) :: taken
   FORECLOSURE-GATE   420  (SYM_RESULT_ActiveRecord__FinderMethods_find_by_3_text_has_mention == True) :: taken
```

Population: `_snapshot_pruned_p2.txt`, 14 806 distinct outcome profiles of
99 448 dumps (after TR0910a + TR0910w), with the seven ARGUMENT P pins.
`SKIP_COMPLETION=1`, so `OVERALL_COMPLETE` is forced False by design —
this pass measures the COVERAGE layer only.

## §40. The audit suite, re-run at 6 GB, alone


## §65. FOOTPRINT CENSUS — the matched-context differential on p5, and what it prices

Owner's reframe (2026-09-11): tier 2's cross-rep pairs do not have INDEPENDENCE,
they have SEPARABLE EFFECTS — A and B gate DISJOINT sets of statements. That is
a corpus measurement, not a flip-both probe, so X11 does not bear on it. Tier 2
as an `IndependenceAssumption` **does not ship**; the 83-class gate result is on
record as "PASS, not discriminating on this endpoint (X11)".

`_footprint_census.py`, method = `notifications_index/_TRACE_PROJECTION_20260909.md`
§4 EXACT matched contexts (all other tracked exprs identical; the variant-merged
keying was shown invalid there and is not used). 31 054 pruned p5 profiles,
caged at 3 500 M, **162 s**.

### First run, and the defect in it

```
tracked decisions                 : 111
DECIDED (>= 1 matched context)    :  54
UNDECIDABLE (no matched context)  :  57
empty measured footprint          :  30 of the 54
matched-context buckets           : (per decision, 2 - 4 303)
```

Largest footprints (shapes whose PRESENCE differs across the matched flip):

```
 footprint  contexts  decision
        35      2977  (Length(SYM_PARAM_id) < 16)                 <- the post_key dispatch
        29      4303  (assoc_status_message_text_has_mention == True)
        27      2822  (assoc_profile_nsfw == True)
        27      2682  (..._CollectionProxy_records_1_row_text_has_mention == True)
        23      3024  (len(..._Relation_records_1_rows) != 0)
        23      1591  (..._FinderMethods_find_by_2_not_found == True)
        23      1544  (..._FinderMethods_find_by_1_not_found == True)
```

**DEFECT IN THIS RUN, found before the numbers were used.** The census read RAW
dump expressions; every candidate pair is stated in the engine's CANONICAL
(statement-identified) namespace. 18 of the 84 candidate expressions — the
`records_photos_<hash>_row_*` family that `canonicalize_ordinals` mints — do not
exist in the raw namespace at all, so pairs mentioning them could not be looked
up and fell through as "undecidable". Re-classified:

```
  791  NAMESPACE-MISSING (this census's bug, NOT a measurement)
  667  genuinely UNDECIDABLE (both exprs present, no matched context)
  231  SEPARABLE   (both decided, footprints disjoint)
   44  OVERLAPPING (both decided, footprints intersect)
 1733  TOTAL
```

`_footprint_census.py` now applies `CR.canonicalize_ordinals` exactly as
`_exact_enum_emit.load_runs` does, so both sides speak one namespace. The
first-run artefacts are kept as `_bak_footprints_RAWNAMES.json` /
`_bak_footprint_census_RAWNAMES.log`. **The 791 must be re-measured before any
of this is used as the cross-check; the 231 / 44 / 667 stand as measured.**

### The 44 OVERLAPPING pairs are the concrete evidence for X11

These are pairs the flip-both gate PASSED and the footprint measurement says are
dependent — the two decisions move a common set of statement shapes:

```
 shared   A                                          B
    27   (assoc_profile_nsfw == True)                (assoc_status_message_text_has_mention == True)
    23   (find_by_1_not_found == True)               (assoc_profile_nsfw == True)
    22   (find_by_3_text_has_mention == True)        (assoc_profile_nsfw == True)
    22   (find_by_3_text_has_mention == True)        (assoc_status_message_text_has_mention == True)
    20   (find_by_{1,2,3}_* == True)                 (evilq_like_public_1_text_has_mention == True)
```

36 rep-family classes are touched. **Every one of these sits inside a class whose
representative the gate PASSED** — which is exactly X11's claim, now with named
instances rather than an argument from the FAIL condition's shape.

### Soundness of the separability inference, and its precondition

If a shape needs BOTH outcomes (`A=x ∧ B=y ⇒ Z`), it appears in BOTH footprints:
holding B at y, flipping A toggles Z, so Z ∈ footprint(A); holding A at x,
flipping B toggles Z, so Z ∈ footprint(B). **Disjoint footprints refute such a
Z** — that is the falsifier. Preconditions, checked not assumed:

* **tree-complete** — p5 has `tree_missing = 0`, confirmed independently by the
  enumerator (§53.2), so no footprint is measured over an arm never walked;
* **matched contexts exist** — a decision with none is UNDECIDABLE and is never
  called separable from anything. 57 of 111 are in that state here, which is why
  UNDECIDABLE is carried as its own verdict and never as "empty".

### Status

The pricing what-if (`_whatif_separable.py`) was **killed by the coordinator at
1 GB free and is NOT being relaunched**: a fable agent is implementing
`SeparableEffects` directly in `src/coverage.py` as an inferred property, and
the next `coverage_report.py` pass prices it for real. The method and these
numbers are the cross-check. `_whatif_wf_merge.py` (the re-keying magnitude) was
stopped mid-run for the same budget reason and is queued, not abandoned.

## §66. THE AUDITS STAGE WAS KILLED AT 5.9 GB — recorded, with the rerun plan

**Kill, 2026-09-11, by the coordinator:** `statement_note_lint.py`
(pid 612130), the detached sequence's audits stage, at **5.9 GB and climbing**,
with the box at 1 GB free and the cage at 8/9 G. It would have been cgroup-killed
within the minute regardless. `_c7_audits.log` records it as **`EXIT=143`**
(SIGTERM) — the run is on the record as killed, not as a result.

**It is the largest single consumer this endpoint has produced**, and the reason
is its input: `statement_note_lint.py` takes a BATCH DIRECTORY and globs it
(`files = glob.glob(os.path.join(batch, "dump_*.json"))`, line 38) — there is no
`DUMP_LIST`. So it loaded all **129 606** dumps, where every other heavy job of
this drive runs on the 31 054-profile pruned list.

**The rest of the audits stage was NOT killed** and continued to the next audit
(`bind_resolution_audit.py`); only the lint died. The detached sequence's audits
stage is NOT to be relaunched as-is.

### The equivalence question the rerun turns on

The coverage pass may run on the pruned list because its verdict depends only on
the OUTCOME PROFILE, and `_prune_corpus.py` prunes by exactly that relation. A
note-level audit reads NOTES, not outcomes, so that argument does not transfer —
it has to be made separately:

> can two dumps with the SAME outcome profile carry DIFFERENT notes?

`_note_invariance.py` measures it directly rather than arguing it: profile key =
the engine's own `frozenset((expr, frozenset(outcomes)))` over canonicalised
exprs (the same relation the pruner uses), note key = the sorted set of
`(target, note)` over every `symbolic_call`. Any profile holding two distinct
note sets refutes invariance.

**The expected answer is NOT invariant, and the mechanism is already known on
this endpoint:** `(len(X_rows) != 0)` is ONE tracked decision, but a run with one
row and a run with seven rows both satisfy it while issuing
`... IN ($1)` and `... IN ($1,...,$7)` — different notes, identical outcome
profile. That is the same cardinality-determines-shape fact W-E rests on
(DISCIPLINE §13 Rule D). The measurement is running to confirm it with a count
rather than leaving it as an argument.

### Rerun plan, ≤ 3 GB

* if the measurement says **INVARIANT** — rerun the lint on the pruned list via a
  batch-local directory of symlinks (the lint globs a directory, so a temp dir
  of 31 054 symlinks needs no `src/` change), capped at 3 G;
* if it says **NOT INVARIANT** (expected) — the pruned list is NOT a sound input
  and the lint runs in CHUNKS over the full directory, each chunk a caged job at
  3 G, results concatenated. Chunking is sound for a per-dump lint in a way
  pruning is not: it partitions the input rather than sampling it.

Either way: `free -g` and the slice's `MemoryCurrent` are checked before each
launch, this drive's share stays ≤ 3 G, and every job goes through `cage`
(`concolic-cov.slice` + per-job `MemoryMax` + `choom -n 1000`).

### §66.1 MEASURED: note-level audits are NOT profile-invariant

`_note_invariance.log`, 21 600 dumps (stride-6 of the full p5 corpus), caged at
1 500 M:

```
dumps scanned              : 21600
distinct outcome profiles  : 15542
profiles with >1 NOTE SET  :    63
=> PROFILE-INVARIANT       : False
```

63 profiles carry more than one distinct note set — one of them over **321
dumps**. Small (0.4 %) but non-zero, and non-zero is the whole question: the
pruned list would silently drop note variation the lint exists to see. **The
pruned list is NOT a sound input for a note-level audit.** The coverage pass's
equivalence argument does not transfer, and now it does not have to be argued.

### §66.2 AND CHUNKING WOULD BE UNSOUND — the lint has corpus-global state

Reading `statement_note_lint.py` before chunking it:

```python
noted_targets = set()          # pass 1, over the WHOLE corpus
all_events = []
for f in files:
    d = json.load(open(f))
    for ev in d.get("events") or []:
        all_events.append(ev)              # <-- every event of every dump, retained
        if ev.get("note"): noted_targets.add(...)
for ev in all_events:                      # pass 2 needs pass 1's global set
    if (not note and target not in noted_targets) ...: buckets["junk"][key] += 1
```

`noted_targets` is CORPUS-GLOBAL by design — the lint's own rule is "only a
target with ZERO noted events **anywhere** is a wall". Split the directory in
two and a target noted only in chunk B is reported as JUNK in chunk A. **Chunking
changes the verdict**, so it is not the answer either.

**Both cheap inputs are therefore unsound: pruning (§66.1, measured) and
chunking (above, by construction).**

### §66.3 The actual cause of the 5.9 GB, and the sound fix

`all_events.append(ev)` retains every `symbolic_call` event dict of all 129 606
dumps purely so pass 2 can run after pass 1. The only thing pass 2 needs from
pass 1 is the small `noted_targets` SET. Streaming the corpus twice gives the
IDENTICAL verdict in O(1) memory.

* **RAISED as X12, `src/` proposal, NOT implemented** (no authorization sought
  mid-drive): drop `all_events`; make it two streaming passes over `files`. Pure
  performance, no semantic change — same regexes, same branch order, same bucket
  keys, same red rule, same exit code. It also makes `DUMP_LIST` support trivial,
  which every other heavy job on this endpoint already has and the lint does not.
* **Meanwhile, batch-local**: `_lint_streaming.py` reproduces the shipped logic
  exactly in two streaming passes, and takes `DUMP_LIST`. It is the rerun
  vehicle, capped at 3 G.

### §66.4 Rerun plan (HELD until the audits stage exits)

The audits stage (`_c7_audits.sh`, pid 606042) is still running its later audits
(`bind_resolution_audit.py` at the time of writing) — only the lint was killed.
This drive holds every heavy job until it exits. Then, one at a time, ≤ 3 G,
each through `cage`, with `free -g` and the slice's `MemoryCurrent` checked
first:

1. `_lint_streaming.py` on the FULL dump list (sound input, streamed) — 3 G;
2. the canonicalised footprint re-run, to convert §65's 791 NAMESPACE-MISSING
   pairs into real verdicts — 3 G;
3. `_whatif_wf_merge.py`, the re-keying magnitude — 3 G.
```
11:EXIT=0
14:EXIT=143
25:EXIT=1
40:EXIT=1
55:EXIT=0
124:EXIT=1
144:EXIT=1
183:EXIT=1
190:EXIT=0
201:EXIT=1
294:EXIT=0
406:EXIT=1
449:EXIT=1
```

_(appended automatically by `_finish_sequence.sh`; the full logs are
`_covA_pruned_20260910.log`, `_covB2_p2_20260910.log` and `_c7_audits.log`.)_

## §43. The Person#name wrap — the differential, run after the sequence

```
runner exit=0
post-wrap html dumps: 1
  dump_auth_html0001_PNWRAP0910.json error=(none)                 pcs=34 events=136

PRE-WRAP baseline (dump_auth_html0001_CSSPOST0910.json, §14):
  error=NotImplementedError pcs=25 events=135
  message: SymbolicString#scrub is not supported in the concolic runtime
```

Read this as §12/§14/§42 read: if the arm still terminates, the site above
IS the next named failure point and the html view's reads remain absent
from the policy (W1). If it completes, §12's cost is closed and the corpus
must be regenerated before any policy claim uses it — the 99 448 existing
dumps were all produced with the arm broken.

## §51. THE POST-REPAIR PASS — §16b on the p5 corpus

```
launched 2026-09-11T03:05:55+00:00
population _snapshot_pruned_p5.txt = 31054 profiles of 129606 dumps
free -m at launch: avail=8785MB
pass P5 exit=143  finished 2026-09-11T03:20:10+00:00
[assumptions] declared=1118 INERT(never-co-evaluated, not declared)=767 OVERNIGHT_PINS=8
```

`MAX_MISSING_PER_CLIQUE=16` (not the default 4) DELIBERATELY: a pass on
this endpoint costs hours of solver, so one pass must name as many demand
targets as possible for the rounds that follow — the brief's "name many
targets per pass". `SKIP_COMPLETION=1`, so `OVERALL_COMPLETE` is forced
False by design; this pass measures the COVERAGE layer only.

PREDICTION, recorded before it ran (`_tree_census_p5final.log`, computed
off the same pruned list through the engine's own load path): **TREE_MISSING
= 0**. 137 tracked expressions, 13 one-sided, 8 of them the ARGUMENT P pins
and the other 5 the `photos ... status_message_guid != <itself>`
SELF-COMPARES, whose True side is unsatisfiable — and pass A proved
empirically that Z3 excludes exactly those (its TREE_MISSING=11 contained
none of them). If this pass reports any other number, the census and the
engine disagree and THAT is the finding.

## §67. X12 PROVEN, the strict gate HELD, and a correction to which pass is the §16b baseline

### §67.1 X12 equivalence — PROVEN, byte for byte

`_x12_equiv.log`. Three arms on ONE symlink set of 18 421 dumps: OLD (glob,
caged 3 G), NEW (glob), NEW (`DUMP_LIST`). All rc=0.

```
old  821 bytes  md5 4de1fdce0492c05659ee74a466d38d84
new  821 bytes  md5 4de1fdce0492c05659ee74a466d38d84
dl   821 bytes  md5 4de1fdce0492c05659ee74a466d38d84
OLD == NEW == NEW(DUMP_LIST) — IDENTICAL
== statement_note_lint: 18421 dumps, 1104139 clean notes ==
```

**The harness's first verdict was a FALSE ALARM and is recorded as one.** It
diffed the raw captured stdout, which begins with `systemd-run`'s own banner
(`Running as unit: pxlintold.scope; invocation ID: …`) — a line that differs by
construction on every run. Stripping it leaves the lint's own output identical
on all three arms. The fix is equivalence-preserving; the harness was not
equivalence-aware. `_x12_*.clean` carry the compared bytes.

### §67.2 The strict gate did its job — nothing weak was measured

```
STRICT confinement detected in src/test_confinement.py
  coverage.py       859216a0dc74d169940bb3ae9fd2cad6   (baseline 1f6a2559…)
  test_confinement  3e4f35705a56b7104a84bcc367a467bb   (baseline a38bbfdf…)
  src/test_confinement.py rc=1  AssertionError
STRICT tests are RED -- stages 2-4 NOT RUN.
```

`_confinement_census.log`, `_footprint_census.log` and `_covC_p5_conf.log` do
not exist. **No census and no confinement-aware pass has run on this endpoint**,
under either the weak or the strict definition.

### §67.3 CORRECTION — §51 has NO verdict, and the §16b baseline is PASS B

The relaunched §51 pass was killed by the coordinator under the new one-pass
rule (the box was at 1 GB free with notifications' pass at 4.1 GB). Its §51
block records exactly that and nothing more:

```
pass P5 exit=143  finished 2026-09-11T03:20:10+00:00
[assumptions] declared=1118 INERT(...)=767 OVERNIGHT_PINS=8
```

`exit=143` is SIGTERM; it died inside the LOAD (`_covP5_20260910.log` ends at
`loaded 31054 runs`). **There is no COMPLETE=, no NODES=, no MISSING=, no
TREE_MISSING= for §51** — it never reached a verdict, and none should be quoted
from it. It is NOT to be relaunched: the confinement-aware (§16c) pass
supersedes it.

**`NODES=102 MISSING=1414 TREE_MISSING=1` is PASS B's verdict (§39), on the p2
corpus** — a different population (14 806 profiles of 99 448 dumps, not p5's
31 054 of 129 606):

```
COMPLETE=False;NODES=102;MISSING=1414;BLOCKING=1414;PCS=501189
DEMAND_SETS=567;TREE_COMPLETE=False;TREE_MISSING=1;FORECLOSURES=17776
peak RSS 1517 MB;  wrote _cov_p2_pins.json in 14283.8s  (3 h 58 m)
```

So **the last §16b verdict on record for this endpoint is PASS B on p2**, and
the p5 corpus has never had a completed coverage pass of any kind.

### §67.4 A THIRD independent checker-vs-enumerator agreement, free

Pass B's population is one my enumerator also measured (`_enum_p2.log`, the run
stopped mid-census for the budget — but its UNIVERSE had already printed):

| | pass B (checker) | enumerator, same snapshot |
|---|---|---|
| NODES | **102** | **102** |
| DEMAND_SETS | **567** | **567** |
| TREE_MISSING | **1** | **1** |

Three for three, on a population neither was tuned for, and with the pin tier
ON in both (pass B `OVERNIGHT_PINS=8`; the enumerator reports `pinned=7` — the
8th, `records_5`, is INERT on p2 exactly as §52(a) recorded in advance). With
pass A's 101 / 563 / 11 under `NO_PINS=1` (§58), that is **two populations and
six numbers with zero disagreement** between `coverage.py` and
`_exact_enum_emit.py`.

## §68. §16c MEASURED — and why the residual is mostly NOT an evidence gap

`_confinement_census.json`, p5, flags identical to `_enum_p5_cost.log`.

```
              §16b            §16c            change
cliques        1 805          16 005          x8.9
nodes            137             137          —
satisfiable  4.8548e13       1.3332e11
covered        482 516       5 063 736        x10.5
remaining    48 548 317 564 772  133 317 575 040    -99.73 %
wide (>=13)    1 796          15 908
wide_mass    4.8548e13       1.3332e11        99.99994 % of the residual
bounded_cliques   0               0           exact, both
wall_s            49             627
```

Pairs under strict confinement: **confined 337, overlapping 0, disqualified 602,
undecidable 2 597**. Decisions: **58 decided (30 confined + 28 disqualified),
79 undecidable**.

### §68.1 CROSS-CHECK vs this drive's own measure — EXACT, once the namespace is fixed

My canonicalised footprint census and the shipped census first looked like they
disagreed on 8 decisions each way. They do not: those are the **same 8
decisions in two namespaces** — `(SYM_LEN_X != 0)` (the Z3 form the checker
keys by) versus `(len(X) != 0)` (the runtime form). Applying the engine's own
rewrite (`assumption_checker.canon`):

```
strict decided 58 | mine 58 | agree 58 | strict-only 0 | mine-only 0
undecidable (agreed): 79
```

**Two independent implementations of the footprint measure, 58/58 and 79/79,
zero disagreement.** (My pair-level split is a different denominator — it
scores the 1 733 tier-2 candidates, not all co-evaluated non-gate pairs — and
under the weak definition it reads 456 separable / 96 overlapping / 1 181
undecidable. The strict census's `overlapping = 0` is the strict rule working
as designed: a decision with any two-sided shape is DISQUALIFIED outright
rather than left to overlap pairwise, which is why 28 decisions became
disqualified and 602 pairs with them.)

### §68.2 THE DIAGNOSIS: 45 of the 79 undecidable are GATES, and that is structural

The coordinator's step 2 assumes undecidability is an evidence gap fixable by
manufacturing a matched context. **For most of these it is not fixable, by
construction.** A decision is undecidable when no two runs differ ONLY in it.
For a GATE that can never happen: flipping a gate changes WHICH OTHER DECISIONS
ARE EVALUATED, so the two runs differ in more than the gate and no matched
context exists at any corpus size. Classifying the 79:

```
  24  LENGTH (gate)          len(X) != 0  — flips whether the rows' decisions exist
  15  NOT_FOUND (gate)       flips whether the whole rep's chain exists
   6  PUBLIC (gate)          flips into the NonPublic rescue
  ---
  45  GATE-LIKE     — CANNOT have a matched context. Not an evidence gap.
   5  self-compare  — UNSAT (X != X); no second arm exists to match
  ---
  29  ADDRESSABLE   — 15 text_empty, 8 guid, 2 text_has_mention, 4 other
```

These 45 are exactly the decisions §16b's FORECLOSURE relation already handles
(`foreclosures_applied` = 191 114 under §16c). Confinement and foreclosure
partition the problem: foreclosure removes assignments the program cannot make,
confinement removes cross products the program does not couple. A gate belongs
to the first and is silent in the second by definition.

### §68.3 PRE-REGISTRATION for the one-flip campaign, before a seed is built

**(a) At most 29 of the 79 can become decided; I predict 20-29 do.** A one-flip
rooted seed (verbatim base + exactly one flip, §9.7) manufactures a matched pair
only if the flip is HONOURED and nothing else moves. Non-gate flips (a row's
text emptiness, a guid) are local, and notifications measured seeds honoured
~97 % when reached; the shortfall will be flips that are not reached in the
chosen base.

**(b) The 45 gates will NOT become decided. This is the falsifiable half:** if a
`len(...) != 0` or `_not_found` decision acquires a matched context, my gate
classification is wrong and §68.2 must be withdrawn.

**(c) What it does to `remaining`, bounded honestly.** Each newly-confined
member of a width-w set removes a factor of ~2 from that set's cross product.
Best case — all 29 become decided AND confined, spread over the 15 908 wide
sets — the residual falls by at most a few binary orders per set, so
`remaining` lands around **10^9-10^10, not 0**. The 45 gates keep carrying the
width whatever the campaign does. **So this campaign cannot make posts_show
drivable, and it is run to convert an unmeasured residual into a measured one,
not to close it.** If `remaining` after the re-census is below ~10^8, my bound
is wrong and I will say so.

## §69. The definition is being EXTENDED to gates — §68.2 stands as measured, and here is the pre-registration

**§68.2 is NOT withdrawn.** "A gate cannot have a matched context" is correct
*for the matched-context keying as it stood* — agree on every OTHER tracked
decision — and it is what the measurement showed. What changes is the KEYING,
not the finding: the owner is extending matched contexts to "agree on every
decision evaluated in BOTH runs", so a gate's foreclosed downstream is no
longer something the two runs must agree on — **it IS the gate's footprint**.
Under that keying a gate becomes decidable, strict one-sidedness and the active
probe apply unchanged, and two gates with disjoint downstreams are CONFINED.
§68.2 therefore reads: under the old keying the 45 gates were structurally
undecidable and carried the width; the keying change is what addresses them.

### §69.1 PRE-REGISTRATION — what the widest set becomes if gate downstreams are disjoint

Recorded before the gate-aware version lands. Grounded in the §16c shape:

```
§16c: cliques 16 005, max width 35 (19 sets), wide (>=13) 15 908
      remaining 133 317 575 040   satisfiable 133 322 638 776   covered 5 063 736
      mean remaining per wide set 8 380 532   median 4 235 987
      largest single set: 141 557 678 remaining at width 30
```

**The arithmetic of the claim.** When every member of a set is pairwise
confined, the confinement partition is all singletons and the set's demand is
the SUM of its members' own coverage — 2 per member — not the product. So a
width-30 set goes from ~1.4e8 to **60**, and the widest (35) to **70**.

Summed over all 16 005 sets:

```
sum(2 x width) over every set = 798 260
```

against `satisfiable = 1.333e11` now. And **`covered` is already 5 063 736** —
6.3x that bound — so if the gate extension confines as broadly as the disjoint-
downstream hypothesis says, the demand collapses BELOW what this corpus has
already observed and `remaining` goes to **0 or near it**.

**Three registered outcomes, so this cannot be read after the fact:**

1. **Every length gate's downstream disjoint from every other's** (the
   coordinator's hypothesis): `remaining` lands **< 10^4**, plausibly **0**.
   posts_show becomes CLOSED on the combination layer without a single further
   run — the corpus already covers 5.06e6 assignments.
2. **Gates decidable but downstreams OVERLAP** (e.g. two `records_*_rows`
   lengths both gate the same `photos` preload shape): they are then
   DISQUALIFIED or overlapping, the sets stay wide, and `remaining` stays
   **10^10-10^11** — essentially where §16c left it. This is the outcome I
   would bet on for the `likes`/`participations`/`tags` length family, which
   feed the same presenter chain.
3. **Between**: some gate families confine, others do not; `remaining` lands
   **10^5-10^9** and the residual is named per family.

**My prediction is (3), nearer (2)** — I expect the nine `find_by_N_not_found`
gates to confine (nine independent finders, disjoint statements) and the length
gates over the same association chain NOT to (§54's measurement already shows
the `records_*` family sharing shapes, and §65's 44 overlapping pairs were
dominated by exactly those chains). Falsifier: if `remaining` comes out < 10^4,
outcome 1 held and my reading of the length family was wrong.

### §69.2 What is NOT affected

Pipeline 7 (the 29 ADDRESSABLE one-flip decisions) proceeds unchanged — those
are non-gate decisions whose undecidability is a genuine evidence gap under
EITHER keying, and the seeds are already built against the current corpus. The
45 gates are skipped by that campaign by construction and counted, which stays
correct: the keying change decides them, not more driving.

## §70. The §16c pass was KILLED BY THE COORDINATOR at 4 h 55 m — not failed

`coverage_report.py` MMC=16 on `_snapshot_pruned_p5.txt`, pid 700353, launched
2026-09-11 03:51, killed 08:4x. **Killed by the coordinator, on record, for
three stated reasons — this is not a crash, an OOM or a defect:**

1. it started on the **pre-gate-extension engine** (`coverage.py` 539d4fb8…),
   so its verdict would have been superseded the moment the gate-aware keying
   landed — and that landed at 05:37 (`955a341d…`), then again (`d9a11b08…`);
2. **no heartbeat since load** and, at 31 054 profiles x MMC=16 x confinement,
   no bound on the time remaining;
3. it held the **exclusive slot** against notifications' and people_stream's
   certification passes, both at `remaining` ≈ 0 — a slot spent on a verdict
   already destined to be superseded.

What it produced before the kill, verbatim and complete:

```
[assumptions] declared=1118 INERT(never-co-evaluated, not declared)=767 OVERNIGHT_PINS=8
```

No `COMPLETE=`, no `DEMAND_SETS=`, no `TREE_MISSING=`. **So p5 still has no
completed coverage pass** — §51 died in load (SIGTERM, §67.3), this one was
killed in solve, and the last completed pass on this endpoint remains PASS B on
the p2 corpus. Every p5 number this drive reports comes from the exact
enumerator and the confinement census, both of which are exhaustive and
`bounded_cliques=0`; the checker's own WITNESS LIST is the one thing they cannot
give, and it is not needed for any claim made here.

## §71. THE GATE-AWARE CENSUS, AND CONSTRUCTION BEATS "RESIDUE" AGAIN

### §71.1 Gate-aware keying, same snapshot, identical flags — verbatim

`_pipeline8.log`, `pxconfgate.scope` CAGED-OK, suite green first
(`coverage.py d9a11b08…`, `test_confinement.py bafcba90…`,
`All confinement tests passed`).

```
=== §16c keying: OLD (other-decisions) -> NEW (gate-aware) ===
  decided                  58 -> 107
  undecidable              79 -> 30
  confined_decisions       30 -> 33
  disqualified_decisions   28 -> 74
  pairs   {'confined':337,'overlapping':0,'disqualified':602,'undecidable':2597}
       -> {'confined':290,'overlapping':0,'disqualified':2234,'undecidable':1528}
  census.16c.cliques        16005 -> 16101
  census.16c.satisfiable    133322638776 -> 128182941624
  census.16c.covered        5063736 -> 5072514
  census.16c.remaining      133317575040 -> 128177869110
  census.16c.wide           15908 -> 16004
  census.16c.wide_mass      133317506526 -> 128177800596
```

**`remaining` 133 317 575 040 → 128 177 869 110: a 3.86 % fall.**

**This is pre-registered outcome (2), which is what I predicted** (§69.1: "my
prediction is (3), nearer (2)"). The keying change did exactly what it was meant
to mechanically — **49 of the 79 undecidable decisions became decided** (79 →
30), so gates ARE now measurable. But they came out **DISQUALIFIED, not
confined**: `disqualified_decisions` 28 → **74**, and disqualified PAIRS 602 →
**2 234**. Under strict one-sidedness a decision with any two-sided shape is
disqualified outright, and that is what the gates hit. Outcome (1) — the
disjoint-downstream hypothesis, `remaining` < 10^4 — is **refuted on this
endpoint**: confined decisions moved only 30 → 33 and confined pairs went DOWN,
337 → 290.

### §71.2 Construction: the "declared residue" was reachable AGAIN

`EMIT_REACHABLE_ONLY=0` (the default this drive flipped, §69.2) emitted the
groups the old default hid:

```
REACH_SPLIT: MULTI-GATE-FORECLOSED 9 944 985 241 408 = 20.48 % of the remaining
EMIT: remaining cubes=7200  mass=1 939 309 360 393  unreachable_groups_skipped=0
distinct GATE COMBINATIONS: 1098
constructed seeds: 4392 (x4 variants)   combinations with no base: 0
drive GC0911: corpus 129 606 -> 134 063 (+4 392)   pruned -> 31 394 profiles
```

**The per-combination table (`_gc_realise.py`, over all 4 392 drive dumps,
1 097 combinations, 40 distinct gate decisions):**

```
  REALISED         25 056     seeded and observed with the seeded value
  UNEVALUATED      53 866     seeded but the decision was never reached
  CONTRADICTED         66     seeded, evaluated, observed the OTHER way

  gates realised at least once (NOT residue)      : 17 of 18 seen
  gates realised AND contradicted                 :  0
  GATES THAT FLIPPED BACK DESPITE THEIR SEED      :  1
     x66  (SYM_RESULT_ActiveRecord__Associations__CollectionProxy_size_1_size == 0)
```

**people_stream's result reproduces here.** Of the gate outcomes the census had
implicitly written off, **17 of 18 were realised by direct construction**.
Exactly ONE decision is impossibility evidence by the rule's own standard —
`CollectionProxy_size_1_size == 0`, contradicted 66 times and realised never.
Everything else the corpus had simply not produced.

And the census moved with it:

```
GC0911 snapshot (134 063 dumps / 31 394 profiles)
  16b: sets=1901  remaining=52 145 853 293 867
  16c: sets=6494  satisfiable=77 662 043 192  covered=1 920 631
       remaining=77 660 122 561   bounded_cliques=0   wall=216s
  wide (>=13): 6 365 holding 77 660 039 481
```

**`remaining` 128 177 869 110 → 77 660 122 561 — a 39.4 % fall from 4 392
constructed runs**, against 30 000 bulk runs earlier in this drive that moved it
by nothing comparable. Construction is the method that works on this endpoint.

**The honest limit in the same breath: `UNEVALUATED` (53 866) is 68 % of the
seeded gate outcomes.** Two thirds of what was constructed was never reached on
the path the run actually took. That, not impossibility, is what bounds this
method here — and it is the same "70 % of keys never evaluated" that
notifications measured (§13).

## §72. TWO CONSTRUCTOR DEFECTS — both confirmed here, and the "impossibility" gate was a MOCK DOMAIN

Notifications found two defects in its own constructor; both were measured on
posts_show's own cubes before changing anything.

### §72.1 (1) Out-of-domain negations — 24.5 % of constructed values

A model value only has to SATISFY the cube; the solver is free to invent one the
variable never takes at runtime. Measured over 2 000 emitted cubes / 11 910
constructed values, against the observed domain of 351 variables taken from
`symbolic_vars` across 4 000 real dumps:

```
OUT-OF-DOMAIN values: 2 912 of 11 910 (24.5 %), over 4 variables

  x936  ..._as_api_response_2_row_guid   model=''  observed=['..._2_row_guid_v']
  x908  ..._as_api_response_1_row_guid   model=''  observed=['..._1_row_guid_v']
  x888  ..._as_api_response_3_row_guid   model=''  observed=['..._3_row_guid_v']
  x180  SYM_PARAM_id   model='ABCDEFGHIJKLMNOP'
                       observed=['1','ggggggggggggggg','','gggggggggggggggg','ABCKLDEMFNGHOIJP']
```

`SYM_PARAM_id` is the clearest instance: the cube needs a 16-character id, the
corpus HAS one (`ABCKLDEMFNGHOIJP`), and the solver invented
`ABCDEFGHIJKLMNOP` instead. An out-of-domain seed forecloses every downstream
keyed on that variable — **which is one source of the UNEVALUATED 68 %**.

**Fixed:** each NEGATED variable now resolves to the MOST-OFTEN-OBSERVED value
that still satisfies the cube's constraint on it; a POSITIVE keeps its exact
value (an `== v` must stay v). The count of substitutions is printed per run,
so this can never become silent.

### §72.2 (2) Write order — negatives first, positives last

The constructor wrote `concrete_values` in dict order, so when several members
sit on one variable a negation's substitute could clobber a positive's exact
value. **Fixed:** items are sorted by polarity, negatives first, positives last.

### §72.3 The one "impossibility" gate is a MOCK DOMAIN — §71.2 CORRECTED

§71.2 named `(..._CollectionProxy_size_1_size == 0)` as the only impossibility
evidence: contradicted 66 times, realised never. Checking its observed domain
before accepting that, exactly as the coordinator asked:

```
SYM_RESULT_ActiveRecord__Associations__CollectionProxy_size_1_size
    observed domain = {'1': 11, '0': 1, '2': 4, '4': 2}
```

**`0` IS in the domain — observed once.** This is a hard-coded mock domain of
{0,1,2,4}, the same shape as notifications' actors list {0,1,4}. So the gate is
**not impossibility evidence**: it is a rare-but-real value that the constructor
failed to reach, and 66 contradictions are a seeding failure, not a proof.

**With that correction, posts_show has ZERO gates that constitute impossibility
evidence** — 18 of 18 gates seen are reachable, and people_stream's result
reproduces here in full. Nothing on this endpoint may be called residue on the
strength of the GC0911 round.

### §72.4 Re-measurement

The per-key honoured / contradicted / never-evaluated table is re-run after the
fix by pipeline 10 (`_gc_realise.py`, stage 10e). Notifications' fix took
CONTRADICTED 76 -> 16; the number to watch here is the 53 866 UNEVALUATED, since
the out-of-domain seeds were foreclosing downstreams rather than contradicting
them. Pre-registered: **UNEVALUATED falls, CONTRADICTED falls toward 0** (the 66
were all one mock-domain gate), and the constructed rounds close more per run
than GC0911's 39.4 %.

## §73. THE OR-MONOTONE CENSUS — remaining 7.77e10 → 2.02e7, and the endpoint is a DRIVING problem again

Same snapshot (`_snapshot_pruned_GC0911.txt`), identical flags, engine md5
**`256f44c146e4e3a37431365693cbc301`** (recorded before launch). The engine is
the only variable against the strict baseline.

```
                       §16c-STRICT        §16c-OR-monotone      change
  demand sets            6 494               1 677              -74 %
  satisfiable       77 662 043 192          20 260 626          -99.97 %
  covered              1 920 631              31 440
  remaining         77 660 122 561          20 229 186          x3 838 smaller
  wide (>=13)            6 365                 999
  bounded_cliques            0                   0              exact, both

  decided                                       114   (was 107 gate-aware / 58 strict)
  undecidable                                    23   (was  30 / 79)
  confined_decisions                             41   (was  33 / 30)
  disqualified_decisions                         73   (was  74 / 28)
  pairs   confined 2248 | overlapping 0 | disqualified 598 | undecidable 1220
          (strict was: confined 290 | overlapping 0 | disqualified 2234 | undecidable 1528)
```

`16b` on the same snapshot is unchanged at `remaining=52 145 853 293 867`, so
the comparison is clean: **§16b 5.21e13 → §16c-OR 2.02e7, a factor of 2.6
million.**

### §73.1 What moved, and what the refinement actually bought

**Confined PAIRS 290 → 2 248 (x7.8), disqualified pairs 2 234 → 598.** That is
the OR-sharing refinement doing exactly what it was for: under strict
one-sidedness, a shape present under either gate alone AND under both
disqualified the decision outright; under OR-monotone it is not interaction and
the pair is confined. The 49-decisions-disqualified-not-confined result of §71.1
is now largely reversed — **disqualified decisions 74 → 73 but confined 33 →
41**, and the pair-level effect is the eightfold rise.

**`confinement_and_pairs` / `overlapping` is ZERO.** The census reports
`overlapping 0` and an empty `overlapping_top` list: on this endpoint, after the
OR refinement, **no pair fails on an AND-shared or non-monotone shape.** There
are no top AND pairs to quote verbatim because there are none. The residual is
carried entirely by `disqualified` (598) and `undecidable` (1 220) pairs, not by
measured interaction.

### §73.2 Pre-registered outcome: (3), and the coordinator's structural estimate held

§69.1 registered three outcomes. This is **(3)** — "some gate families confine,
others do not; `remaining` lands 10^5-10^9". It landed at **2.02e7**, inside
that band, and within a factor of 2 of the confinement author's structural
estimate of ≈4e7 on this same snapshot (their Σ2^w bound: 8.94e12 → 4.47e9,
≈4e7 remaining). My §69.1 prediction — "(3), nearer (2)" — was right on the
outcome and **wrong on the direction of the lean**: I expected the length-gate
family's shared downstreams to keep the sets wide, and the OR refinement shows
that sharing was monotone, i.e. not interaction at all.

### §73.3 Consequence: this is now a DRIVING problem

2.02e7 remaining against a corpus that has already covered 31 440 of the OR
demand, at this corpus's own measured rate. That is the first time tonight the
number has been in reach of construction rather than orders of magnitude beyond
it. Per the coordinator's step 2, the next move is direct construction per gate
combination on the OR-refined demand with the fixed constructor (§72:
domain-resolved negations, negatives-before-positives, 8 bases), drive,
re-census.

## §74. RECONCILING THE 602 ANY-AND PAIRS — they are DISQUALIFIED, and no AND pair is confined

Two instruments disagreed on the same snapshot: the confinement agent's pair
census found **602 ANY-AND pairs**; my engine census reported **`overlapping 0`**.
Named, not averaged.

`_and_reconcile.py` classifies every co-evaluated pair through the engine's OWN
`project_confinement` — the same call the census and the checker make.

```
active 137 | decided 114 | disqualified 73
co-evaluated pair classes: UNDECIDABLE 1404 | DISQUALIFIED 3283 | CONFINED 493
```

**First, a denominator note so these are not misread against §73.** This counts
EVERY co-evaluated pair (5 180). The census's `confined 2248 / disqualified 598
/ undecidable 1220` (4 066) counts pairs WITHIN the projected demand sets. The
two are different populations and neither contradicts the other.

### §74.1 The three named examples

```
findpublic_like x findpublic_reshare : 16 pairs -> DISQUALIFIED 15, CONFINED 1
Person#name x dispatch/length gates  :  0 pairs  (see §74.3)
photos x mentions lengths            : 72 pairs -> DISQUALIFIED 54, UNDECIDABLE 18
```

**`photos x mentions`: none confined.** **`findpublic_like x findpublic_reshare`:
fifteen of sixteen disqualified** — the AND shape makes one member two-sided, so
the pair never reaches the OR test, exactly the sound path.

### §74.2 The ONE confined pair — checked, and it is NOT an AND pair

```
A = (SYM_RESULT_ActiveRecord__Relation_findpublic_like_1_text_empty == True)
B = (SYM_RESULT_ActiveRecord__Relation_findpublic_reshare_1_text_empty == True)
```

Rather than trust the classification, the 2x2 was taken straight from the
corpus (`_and_witness.py`, same `call_shape` the engine uses):

```
  cell A=0 B=0: runs=56  shapes=25
  cell A=1 B=0: runs=38  shapes=25
  cell A=0 B=1: runs=32  shapes=25
  cell A=1 B=1: runs=40  shapes=25

shapes present ONLY with BOTH on (AND-shared): 0
VERDICT: no AND-shared shape -> OR-monotone, confinement is CORRECT
```

All four cells carry the same 25 shapes; **nothing appears only when both are
on**. This is two text-emptiness decisions on two different finders' results —
neither gates a read the other does not — so it is not one of the agent's AND
pairs at all. It is confined correctly.

### §74.3 Why `Person#name` shows zero pairs

`Person#name` is a TRACE SHAPE, not a tracked decision, so it is never a member
of a pair in this namespace — it appears INSIDE footprints. The agent's example
is "`Person#name` under dispatch x length gates", i.e. the shape is the AND-shared
evidence and the PAIR is (dispatch, length). Those pairs are in the
`DISQUALIFIED` bucket: the dispatch decision is one of the 73 disqualified.

### §74.4 Verdict

**The 602 went into DISQUALIFIED, with a minority UNDECIDABLE. No AND pair is
licensed as confined.** The two instruments agree once the populations are
lined up: the agent counts pairs that HAVE an AND shape; the engine never lets
such a pair reach the OR test because the AND shape already made a member
two-sided and disqualified it. `overlapping 0` is not "no AND pairs exist" — it
is "no pair reached the OR test and failed it", which is the same fact stated
one step later in the pipeline.

**Cleared to proceed with construction on the OR-refined demand.**

## §75. WHY THE 73 ARE DISQUALIFIED — none of them is an OR-sharing artefact

Read-only measurement, caged at 2 G, `_disq_why.log`. For each disqualified
decision, every shape appearing with it on its OFF side was tested for a
MONOTONE EXPLAINER — another decision whose 2x2 for that shape is clean (one
side always has it, the other never). All offending shapes explained ⇒ the
decision is disqualified only by OR-sharing, one level earlier than the pair
test; any unexplained ⇒ genuinely two-sided.

```
scanned 31 394 runs, 137 exprs, 69 distinct shapes

  OR-SHARED ONLY (every offending shape has a monotone explainer):   0
  GENUINELY TWO-SIDED                                             :  52
  no offending shape found in this scan                           :  21
```

### §75.1 The what-if is MOOT, and that is the finding

**Zero decisions are disqualified only by OR-shared shapes.** So the what-if the
coordinator asked to price — admitting the OR-only ones to the pair test — would
admit NOTHING, and `remaining` would be **unchanged at 20 229 154**. No census
was spent on it: a what-if over an empty set has a known answer, and running it
would have cost a slot to reproduce a number already in hand.

**This is the strict rule surviving an attempt to weaken it.** The owner asked
for strict one-sidedness and for the tests to try to prove it wrong; the OR
refinement was decisive at the PAIR level (§73: confined pairs 290 → 2 248), and
this measurement says the same refinement applied one level EARLIER, at the
DECISION level, would buy nothing on posts_show. The 52 are two-sided on the
evidence, not on a technicality. **No rule change is indicated, and none is
proposed.**

### §75.2 The 21, named as a limit of THIS scan and not as a result

21 of the 73 are disqualified by the engine but my scan found no offending shape
for them. The likely cause is a known difference: **this scan considers only
SINGLE-SIDED runs** (a run where the decision took both sides is skipped as
ambiguous), while the engine's `side_seen` carries a third bucket for
both-sided runs and a shape seen there can disqualify. So the 21 are probably
disqualified on evidence my scan excludes by construction.

**They are NOT counted as OR-shared-only** — the conservative direction. If they
were all OR-shared-only the headline would still be "0 of 52 measurable ones",
and settling them needs the engine's own `side_seen`, not this scan. Recorded as
an open limit of the instrument, not smoothed over.

## §76. CONTINUATION AFTER THE AUTH OUTAGE — what pipeline 12 actually measured

The previous agent was killed by an auth outage AFTER `_p12.sh` finished on
disk. Nothing was lost: `_p12.log` carries the full round and
`_confinement_census_OD0911.json` its re-census. This section reads that
result, and the first thing it does is CORRECT the reading it was handed.

### §76.0 The brief's `capped_sets=1` is a misreading — it is 1 310

The hand-off asked whether the OR-refined remaining is dominated by "the ONE
capped set". The emitter's own line says otherwise, verbatim from `_p12.log`:

```
EMIT: remaining cubes=11250 mass=131279 (of remaining=20229143) no_model=0
      zero_pieces=11137 unreachable_groups_skipped=0 region_bound=0
      capped_sets=1310 mismatch_sets=0
```

**`capped_sets=1310`, not 1.** `_p12.sh:18` set `EMIT_MAX_PER_SET=8`, and 1 310
of the 1 677 OR-refined parts (78.1 %) hit that cap. There is no single wide
set holding the 2.02e7, and the hypothesis the brief offered — "that may be the
whole story" — is refuted below by the per-part numbers.

## §76.1 THE 2.02e7, DECOMPOSED BY PART — and why the emitter reached 0.65 %

`_emit_reach.py` (read-only, caged at 900 M) joins p12's emit to the census it
was emitted from — `_confinement_census_OR0911.json`, the same 1 677 parts in
the same order — and asks, per part, how much of that part's remaining the
eight cubes it was allowed actually carried.

### §76.1.1 The remaining is SPREAD, not concentrated

```
per-part remaining: total 20 229 143 over 1 677 parts
                    mean 12 062, MEDIAN 210
  top     1 parts:      294 910    1.46 %
  top     5 parts:    1 474 542    7.29 %
  top    10 parts:    2 704 092   13.37 %
  top    25 parts:    4 918 968   24.32 %
  top    50 parts:    8 079 472   39.94 %
  top   100 parts:   11 599 130   57.34 %
  top   250 parts:   16 527 120   81.70 %
  top   500 parts:   19 457 686   96.19 %
  top  1000 parts:   20 215 160   99.93 %
parts with remaining == 0: 151
```

**No part holds more than 1.46 %.** Half the mass needs ~65 parts; 96 % needs
500. The mean is 58x the median, so the distribution is long-tailed, but the
head is a PLATEAU of near-identical parts (294 910, 294 908, 294 908, 294 908,
294 908, 294 908, 294 908, 245 756, 245 756 …) rather than one giant.

### §76.1.2 The mass lives at width 21-27, and nowhere else

```
width : parts / remaining mass / share
   27 :    4       415 772    2.06 %
   25 :   30     4 019 566   19.87 %
   24 :   58     4 409 968   21.80 %
   23 :  120     4 309 041   21.30 %
   22 :  102     3 563 604   17.62 %
   21 :  135     1 941 692    9.60 %
   20 :  126       947 550    4.68 %
   19 :  124       447 410    2.21 %
   18 :   77       100 009    0.49 %
  <=17 :  901        74 531    0.37 %
```

**Widths 21-27 are 575 parts (34 %) and 98.9 % of the remaining.** Everything
of width <= 18 together is 0.86 %. That is the shape of a 2^w problem that
confinement has already cut down: the surviving parts are the ones OR-monotone
confinement could NOT split, and they are wide.

### §76.1.3 The emitter hit NO wall — it hit its own `EMIT_MAX_PER_SET=8`

The stats say this without inference. `region_bound=0` (no region needed more
than `CUBE_CAP=20000` pieces), `no_model=0` (every emitted piece had a model),
`unreachable_groups_skipped=0` (`EMIT_REACHABLE_ONLY` was off, so nothing was
skipped for unreachability), `mismatch_sets=0` (the per-set region mass
cross-check passed on every unskipped set). The only non-zero brake is
`capped_sets=1310`.

```
   part width    remaining  cubes allowed   leaf_groups
     28    25       294910      8              2304
     30    25       294908      8              2304
     29    25       294908      8              9216
     27    25       294908      8              2304
     26    25       294908      8              9216
     23    25       294908      8              2304
     22    25       294908      8              9216
     25    25       245756      8              2304
     24    25       245756      8              9216
     14    25       148222      8              1248
```

A part with 294 910 remaining assignments and 2 304 leaf groups was allowed
EIGHT cubes. Mean mass per emitted cube was 131 279 / 11 250 = **11.7
assignments**, so eight cubes buy ~94 assignments out of ~295 000 — 0.03 % of
that part. Across all parts: 11 250 cubes x 11.7 = 131 279 = **0.65 % of the
demand**, which is exactly `8 / (cubes a part would need)` and nothing else.

**So the answer to the brief's question is: the OR-refined remaining is
dominated neither by one capped set nor by parts the emitter cannot enumerate.
It is spread over ~500 wide parts, and p12 aimed eight cubes at each of them.**

### §76.1.4 What that does to p12's pre-registered STOP

`_p12.log` registered: *"BASELINE remaining before this round: 20 229 143. Stop
if moved < 1000."* The re-census moved it to 20 302 488 — it ROSE by 73 345 —
and under the rule that is exhaustion. Two facts have to sit next to that
verdict, and neither of them rescues the round:

* **the round could not have moved it by more than 131 279 (0.65 %) even if
  every constructed run had landed.** A stop threshold of 1 000 was calibrated
  for a round aimed at the whole remaining; this round was aimed at 0.65 % of
  it. The verdict "the construction method is exhausted" is therefore NOT
  supported at the strength it was stated — what is supported is "this round,
  at this cap, closed nothing net".
* **the demand GREW while it was being driven.** Sets 1 677 -> 1 747 (+70),
  satisfiable 20 260 620 -> 20 331 999 (+71 379), covered 31 477 -> 29 511
  (-1 966). The 13 080 new runs minted ~71 k of NEW demand — new outcome
  profiles make new demand sets, and a set the corpus has never split is
  demanded in full. **At this cap the round's ceiling (131 k) and its own
  minting (+71 k) are the same order of magnitude.** That, not an enumeration
  wall, is the honest reason the number does not fall.

Both are measurements, not excuses: the first says the round was
under-provisioned by a factor of ~150 in cubes-per-part; the second says that
even a fully-provisioned round pays a demand tax for every run it drives.

## §76.2 THE RESIDUAL, CLASSIFIED

Four classes, in the order the brief names them. Each is a measurement with its
own instrument; none is an estimate.

### §76.2(a) REAL DEPENDENCE — 52 decisions, and they are not licensable

`_disq_why.json` (§75, re-read here rather than re-run) says **0 of the 73
disqualified decisions are disqualified only by OR-shared shapes and 52 are
GENUINELY TWO-SIDED**; the other 21 are class (b)'s problem, not this one.
`_family_report.py` names the 52 by decision family:

```
  19  text decision (has_mention)
  11  findpublic_* not_found          <- the findpublic fall-through
   7  text decision (empty)
   4  find_by_N_not_found
   4  guid
   2  size gate (CollectionProxy#size)
   2  public gate
   1  length gate (Length(SYM_PARAM_id))
   1  text decision (rendered — Anonymous.process)
   1  assoc / dispatch
```

The three families the brief asked about, from §74's own reconciliation (the
pair-level view of the same fact):

* **`findpublic` fall-through** — `findpublic_like x findpublic_reshare`:
  16 co-evaluated pairs, **15 DISQUALIFIED, 1 CONFINED**, and the one confined
  pair was checked against the corpus 2x2 by hand (`_and_witness.py`): all four
  cells carry the same 25 shapes, nothing appears only when both are on, so it
  is confined CORRECTLY and is not an AND pair at all.
* **`Person#name` under dispatch x lengths** — **0 pairs**, because `Person#name`
  is a TRACE SHAPE, not a tracked decision: it is the AND-shared EVIDENCE and
  the pair is (dispatch, length), which sits in the disqualified bucket.
* **`COUNT photos` under photos x mentions** — 72 co-evaluated pairs,
  **54 DISQUALIFIED, 18 UNDECIDABLE, 0 confined.**

**Why this class cannot be closed by a declaration.** A confinement declaration
over a decision the corpus has SEEN two-sided is not conservative, it is false:
the evidence for dependence is positive evidence, and more driving can only add
more of it. The demand over the parts these 52 hold together is owed in full,
and the only lever that could change that is a FINER RELATION than confinement
(§76.5 (a)), not a declaration.

### §76.1.5 What the wide parts are MADE OF — members by decision family

`_topparts_members.py` reads the gate assignment p12's emitter recorded for
each part (the `gates` dict of every cube) and names it. Over all 1 677 parts,
counting a member once per part it appears in:

```
  member-slots   parts   family
        3 037    1 174   guid                         (as_api_response_N_row_guid == '')
        2 984    1 204   length gate (rows != 0)      (SYM_LEN_..._rows != 0)
        2 661      694   text decision (empty)        (..._text_empty == True)
        1 505      761   find_by_N_not_found
        1 351      932   text decision (has_mention)
          199      199   findpublic_* not_found
          102       51   text decision (rendered)     (Anonymous.process == '')
           28       28   public gate
           15       15   size gate (CollectionProxy#size)
```

A representative head part, verbatim (`part#22`, width 25, 14 gate members):

```
  (SYM_LEN_..._records_mentions_66022a8b_rows != 0)
  (SYM_LEN_..._records_participations_4a978df9_rows != 0)
  (..._CollectionProxy_records_2_row_text_empty == True)
  (..._CollectionProxy_records_photos_2c7fa358_row_text_empty == True)
  (..._CollectionProxy_records_photos_33150e22_row_text_empty == True)
  (..._FinderMethods_find_by_3_not_found == True)
  (..._FinderMethods_find_by_6_not_found == True)
  (..._Relation_records_comments_76960418_row_text_empty == True)
  (..._Relation_records_comments_76960418_row_text_has_mention == True)
  (..._as_api_response_1_row_guid == '')
  (..._as_api_response_3_row_guid == '')
  (assoc_root_text_empty == True)
  (assoc_root_text_has_mention == True)
  (assoc_status_message_text_empty == True)
```

**This is the answer to "what holds the 2.02e7", and it is not one exotic set.**
It is the SAME five families, recombined: a guid emptiness per API row, a
length gate per list, a text-emptiness and a has-mention per renderable row, and
a not-found per finder. The wide parts are the parts where OR-monotone
confinement could not separate those families from each other — and §76.2(a)
says why for 52 of the decisions involved: they are two-sided on the corpus.

## §76.3 THE ARITHMETIC OF CONVERGENCE — what "exhausted" can and cannot mean here

Before classifying the rest of the residual it is worth doing the division that
p12's stop rule did not, because it changes which lever matters.

**The demand tax, measured.** 13 080 constructed runs took the OR census from
`satisfiable 20 260 620 / covered 31 477 / remaining 20 229 143` to
`20 331 999 / 29 511 / 20 302 488`. The corpus grew by 13 080 runs and the
demand grew by **+71 379 satisfiable assignments** — new outcome profiles make
new demand sets (1 677 -> 1 747), and a set no run has split is demanded whole.
Per run driven:

```
    demand minted per run driven      = 71 379 / 13 080  =  5.46 assignments
    demand closed  per run driven     = (covered moved -1 966) ~= 0.0
```

**So a construction round converges on this endpoint only if each run it drives
closes MORE THAN ~5.5 previously-uncovered demanded assignments.** That is the
first time this drive has had a convergence threshold rather than a feeling.

**And p12's own targeting was above that threshold.** It emitted 11 250 cubes
carrying 131 279 assignments and drove 13 080 runs — 1.16 runs per cube, 11.7
assignments per cube:

```
    assignments TARGETED per run      = 131 279 / 13 080  = 10.0
    threshold to converge             =                     5.46
```

**A fully-honoured round at `EMIT_MAX_PER_SET=8` would have converged.** It
closed nothing, so the binding constraint is NOT the cap (that only bounds the
round's ceiling at 131 279), NOT the enumerator (`region_bound=0`,
`no_model=0`), and NOT impossibility (§72.3 left this endpoint with zero
impossibility gates). It is **REALISATION** — whether a constructed seed's
decisions are actually walked — which is class (c) below and which §71.2
already measured at 68 % UNEVALUATED before the constructor fixes.

That reframes the whole residual: **the endpoint's limit tonight is that two
thirds of what is constructed is never reached on the path the run takes.**

### §76.2(c) UNEVALUATED-IN-THE-WALK — the refreshed table, and §72.4's pre-registration answered

`_gc_realise.py` re-run on the OD0911 round (the FIXED constructor:
domain-resolved negations, negatives-before-positives, 8 bases), 13 080 drive
dumps, 1 634 gate combinations, 44 distinct gate decisions:

```
  UNEVALUATED    170 484      65.5 %
  REALISED        89 641      34.4 %
  CONTRADICTED       199       0.08 %
                 -------
  total          260 324 seeded gate outcomes

GATES CONTRADICTED AND NEVER REALISED — 3 of 24 gates seen
  x167  (..._CollectionProxy_size_1_size == 0)          <- the MOCK DOMAIN (§72.3)
  x16   (..._as_api_response_1_row_guid == '')          <- ARGUMENT P, a declared pin
  x16   (..._as_api_response_2_row_guid == '')          <- ARGUMENT P, a declared pin
gates realised at least once (NOT residue): 19
gates both realised and contradicted: 0
```

**§72.4 pre-registered "UNEVALUATED falls, CONTRADICTED falls toward 0". The
answer is: barely, and no.** Against GC0911's 68.2 % / 0.084 %, the fixed
constructor gives **65.5 % / 0.076 %** — a 2.7-point fall in the class that
matters and no change in the rate of the one that does not. The two constructor
defects were real and both are fixed, and fixing them did NOT move the binding
constraint. That is the honest reading of a pre-registration that did not come
true, recorded as such.

The three contradicted-only gates are all already-named artefacts, not new
evidence: one is the `{0,1,2,4}` mock domain (class (d)) and two are the
ARGUMENT P guid pins — a seed asking for `guid == ''` on an expression this
endpoint has DECLARED one-sided after two falsifier rounds. Their
contradictions are the pin's own evidence reproducing, which is what should
happen.

#### §76.2(c).2 WHY those 170 484 were never reached — and it is ONE cause

`_unev_why.py` ports notifications' §19 method to this endpoint's artefacts.
posts_show's constructor tags no combination id in the seeds, so the
conjunction is recovered FROM THE RUN: for an unevaluated gate `g`, `P` is the
set of other seeded gates that run DID evaluate with their seeded value. Then
§16b's own "never" test is applied to `P` over the 32 305-profile snapshot.
Buckets are disjoint and first-match-wins:

```
UNEVALUATED events                                      170 484
  RENDER-ERROR (the run ended in a terminal)              1 114   0.65 %
     x859  ActiveRecord::RecordNotFound     <- APPLICATION terminals, not rig
     x255  Diaspora::NonPublic
  ALIAS (the run walked a sibling statement alias)            0
  -> tested by the conjunction test           5 031 distinct (g, P) pairs
     top 600 pairs = 124 673 events = 73.6 % of the class

  CONJUNCTION-FORECLOSURE   491 pairs   102 851 events   82.5 % of tested
  REACHABLE                 109 pairs    21 822 events   17.5 % of tested
  NO-MATCH                    0 pairs         0 events
```

**Four fifths of the unevaluated class is CONJUNCTION FORECLOSURE**, and the
named pairs say what it is:

```
  top CONJUNCTION-FORECLOSURE   (matching runs / of which evaluate the member)
     1079 / 0   (..._findpublic_reshare_1_public == True)
     1079 / 0   (..._findpublic_reshare_1_not_found == True)
     1079 / 0   (..._findpublic_like_1_public == True)
     1079 / 0   (..._findpublic_like_1_not_found == True)
     1079 / 0   (..._evilq_reshare_vis_1_not_found == True)
     1079 / 0   (..._evilq_reshare_public_1_not_found == True)
```

These are the LIKE and RESHARE interaction finders. They run only inside
`PostPresenter#with_initial_interactions`, i.e. only on the html arm. 1 079
corpus runs match the gate conjunction the seed honoured and **not one of them
evaluates the member** — the conjunction identifies a path on which those
finders do not run at all. §16b infers foreclosure PAIRWISE, so a decision
foreclosed only by two or more gates ACTING TOGETHER is never inferred and its
assignments stay demanded forever.

**This endpoint's number for that gap is 82.5 %, against notifications' 20.4 %**
(their §19.1). On posts_show conjunction foreclosure is not a minority
explanation, it is the explanation.

The other 17.5 % is the one notifications also found and it is a BATCH-LOCAL
defect, not a `src/` one:

```
  top REACHABLE   (events, matching runs, of which evaluate the member)
     1079 runs match / 9 evaluate   (..._as_api_response_3_row_text_has_mention == True)
      326 runs match / 251 evaluate (..._FinderMethods_find_by_{3,6,9}_not_found == True)
      326 runs match / 130 evaluate (..._FinderMethods_find_by_6_text_empty == True)
```

Runs matching the conjunction DO evaluate these, so nothing about the semantics
is missing: `_construct_by_gate.py` picks its base by maximum NAME OVERLAP with
the cube's constraint and never checks that the base's own run MATCHES the gate
conjunction. That is the same base-selection criterion §13.1 established on
notifications and the same place this constructor drops it.

## §76.9 NIGHT-13 STAGE VERDICTS, appended by `_p13_recorder.sh`

_(This section is written by a detached recorder so the numbers reach the
record whether or not an agent is watching. Every line below is copied
from the stage's own log.)_

**IT FIRED EARLY, and the reason is recorded rather than hidden.** The recorder
watched for `_night13.sh`; the chain was relaunched as `_night13b.sh` after the
stage-ordering fix (13a-1 and 13b-1 both read the census's `_parts_OD0911.json`,
which had not been written yet), so the recorder saw no matching process and
wrote its section at 19:3x. What follows is therefore a MID-RUN snapshot, not
the closing record; the closing record is §76.9b. Nothing in it is wrong — it
is simply early, and a log that says "verdicts" but holds a prefix of them is
exactly the kind of thing this project does not leave unlabelled.

```
[2026-09-11T19:29:51+00:00] === NIGHT 13 START; box: 5742M avail, slice 6512640 ===
[2026-09-11T19:29:51+00:00] --- 13a: residual classification
[2026-09-11T19:29:51+00:00] 13a-1: part report — decompose the OR-refined remaining by part [1G]
[2026-09-11T19:29:51+00:00] 13a-2: realisation table on the OD0911 construction round (§72.4) [2G]
[2026-09-11T19:30:27+00:00] 13a-3: WHY unevaluated — §19's conjunction-foreclosure test [2G]
[2026-09-11T19:32:19+00:00] pipeline13a done
[2026-09-11T19:32:19+00:00] --- 13b: one-flip constructibility
[2026-09-11T19:32:19+00:00] 13b-1: the CURRENT undecidable list (OD0911 census)
  waiting to be ALONE for p13b (0s): python3         python3 -u /home/dev/project/reports/diaspora/results3/notifications_ind
[2026-09-11T19:33:27+00:00] === NIGHT 13b RESUME; box: 2838M avail ===
[2026-09-11T19:33:27+00:00] --- 13PD: decompose the OR-refined remaining (census only, REACH_SPLIT on) [3G]
  waiting to be ALONE for decompPD (0s): python3         python3 -u /home/dev/project/reports/diaspora/results3/notifications_ind
```

### _part_decomp.log (tail)
```
[2026-09-11T19:17:28+00:00] PD: decompose the OR-refined remaining — CENSUS ONLY, no emit (the cap-64 emit drove free -g to 0 and was killed deliberately at 19:15; the emitter-reach question is answered from the p12 cap-8 emit + per-part remaining) [3G]
```

### _part_report.log (tail)
```
  LAUNCH-GATE ok for p13part.scope (cap 1.000G): free_avail=5740M  slice_free=5.99G
Running as unit: p13part.scope; invocation ID: b5da518817a147b9825967412fd4439e
Traceback (most recent call last):
  File "/home/dev/project/reports/diaspora/results3/posts_show/_part_report.py", line 15, in <module>
    P = json.load(open(os.path.join(HERE, os.environ.get("PARTS_IN", "_parts_OD0911.json"))))
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
FileNotFoundError: [Errno 2] No such file or directory: '/home/dev/project/reports/diaspora/results3/posts_show/_parts_OD0911.json'
```

### _gc_realise_OD0911.log (tail)
```
  LAUNCH-GATE ok for p13real.scope (cap 2.000G): free_avail=5695M  slice_free=5.99G
Running as unit: p13real.scope; invocation ID: c4f311db9bda4864bbd6d04ea5c6b926
gate combinations constructed: 1634
distinct GATE decisions across them: 44
drive dumps: 13080

=== GATE OUTCOMES ACROSS THE DRIVE ===
  UNEVALUATED            170484
  REALISED               89641
  CONTRADICTED           199

GATES THAT FLIPPED BACK DESPITE THEIR SEED (never realised) — the ONLY
impossibility evidence: 3 of 24 gates seen
  contradicted x167   (SYM_RESULT_ActiveRecord__Associations__CollectionProxy_size_1_size == 0)
  contradicted x16    (SYM_RESULT_ActsAsApi__Collection_as_api_response_1_row_guid == '')
  contradicted x16    (SYM_RESULT_ActsAsApi__Collection_as_api_response_2_row_guid == '')

gates realised at least once (NOT residue): 19
gates both realised and contradicted (context-dependent): 0

wrote _gc_realise.json
```

### _unev_why.log (tail)
```
   [32000/32305] 75s
   indexed in 76s

=== §16b's 'never' test, applied to the honoured-prefix CONJUNCTION ===
  CONJUNCTION-FORECLOSURE    pairs   491   unevaluated events   102851
  REACHABLE                  pairs   109   unevaluated events    21822
  NO-MATCH                   pairs     0   unevaluated events        0

  top REACHABLE:
    (1079, 41, 9, '(SYM_RESULT_ActsAsApi__Collection_as_api_response_3_row_text_has_mention == True)')
    (880, 32, 7, '(SYM_RESULT_ActsAsApi__Collection_as_api_response_3_row_text_has_mention == True)')
    (507, 326, 251, '(SYM_RESULT_ActiveRecord__FinderMethods_find_by_9_not_found == True)')
    (507, 326, 251, '(SYM_RESULT_ActiveRecord__FinderMethods_find_by_6_not_found == True)')
    (507, 326, 251, '(SYM_RESULT_ActiveRecord__FinderMethods_find_by_3_not_found == True)')
    (507, 326, 130, '(SYM_RESULT_ActiveRecord__FinderMethods_find_by_6_text_empty == True)')

  top CONJUNCTION-FORECLOSURE:
    (1079, 41, 0, '(SYM_RESULT_ActiveRecord__Relation_findpublic_reshare_1_public == True)')
    (1079, 41, 0, '(SYM_RESULT_ActiveRecord__Relation_findpublic_reshare_1_not_found == True)')
    (1079, 41, 0, '(SYM_RESULT_ActiveRecord__Relation_findpublic_like_1_public == True)')
    (1079, 41, 0, '(SYM_RESULT_ActiveRecord__Relation_findpublic_like_1_not_found == True)')
    (1079, 41, 0, '(SYM_RESULT_ActiveRecord__Relation_evilq_reshare_vis_1_not_found == True)')
    (1079, 41, 0, '(SYM_RESULT_ActiveRecord__Relation_evilq_reshare_public_1_not_found == True)')

UNEV WHY DONE
```


## §76.4 THE SCALE, stated once so nothing below reads as optimism

Measured drive rate, this endpoint, this box: the OD0911 round drove **13 080
runs in 57 minutes** (16:57 -> 17:54 across four scenarios, three JRuby slots)
= **229.5 runs/min**. The OR-refined remaining on the current snapshot is
**20 302 488 assignments**. If one run closed exactly one assignment and minted
nothing:

```
    20 302 488 / 229.5 runs.min^-1  =  88 464 minutes  =  61.4 DAYS
```

of continuous JRuby, on a box that is shared with three other endpoints and an
editor language server. With the measured demand tax (+5.46 minted per run
driven, §76.3) the naive figure is not even an upper bound on the time — it is
the figure for a method that closes one per run, and the round that was
actually run closed ~0.

**So "drive more" is not a plan for this residual at any cap.** The levers that
can move a number of this size are the ones that make the DEMAND smaller —
i.e. a sounder inference — or that raise what a single run closes. §76.5 prices
both, with this endpoint's own numbers.

## §76.5 WHAT `COMPLETE=True` WOULD REQUIRE, per residual class

Proposals only. **Nothing in this section is installed**, `src/` is untouched by
this drive, and every number below is this endpoint's own measurement.

### §76.5(a) REAL DEPENDENCE — no declaration is available, and the one
### available weakening was already tested and bought ZERO

52 decisions are two-sided on the corpus (§76.2(a)). For these:

* **A declaration is not available.** A `ConfinementAssumption` over a decision
  the corpus has seen two-sided asserts something the corpus refutes. This is
  the one class where "declare it and move on" is not a conservative shortcut
  but a false statement, and it is why the brief's own phrasing — "which are
  NOT licensable" — is right. Recorded as such.
* **The obvious weakening has already been priced at zero.** §75 ran it: admit
  to the pair test the decisions whose offending shapes all have a MONOTONE
  EXPLAINER (the OR-sharing rule applied one level earlier, at the decision
  level). **0 of 73 qualify**, so `remaining` would be unchanged at 20 229 154.
  A per-shape refinement of confinement — confine a decision on the one-sided
  part of its footprint and demand the product only over the two-sided part —
  fails for the same reason: on this endpoint the offending shapes are not
  OR-shared artefacts, they are genuinely two-sided, and a shape that really is
  produced under both arms of A and both arms of B is exactly the evidence that
  A x B must be demanded.
* **So the only routes to `COMPLETE` over the parts these hold together are
  (i) to COVER the assignments — §76.4 prices that at ~61 days of continuous
  driving for the whole residual, and these parts are the widest ones in it —
  or (ii) a change in the APP or the MOCKS that removes the interaction, which
  is a modelling decision and not a checker one.**

### §76.5(d) THE MOCK-DOMAIN GATE — a MODEL DECISION, not a measurement

One gate: `SYM_RESULT_..._CollectionProxy_size_1_size == 0`, observed domain
`{'1': 11, '0': 1, '2': 4, '4': 2}` (§72.3) — a hard-coded mock domain of
{0,1,2,4}. In the OD0911 round it was **contradicted 167 times and realised
never**: the demand asks for a value, the constructor seeds it, and the MOCK
returns something else. It is not impossibility evidence and it is not
closeable by driving.

Two ways to close it, and they are the owner's to choose:

* **DECLARE the domain.** If {0,1,2,4} is the model of `photos.size`, then the
  demand should not contain assignments outside it. Expressing that needs a way
  to attach a FINITE DOMAIN to a symbolic int so the solver never proposes 3 —
  a `src/` change (`concolic_engine`'s declarations), priced here at ONE
  expression on this endpoint but shared with every `size` mock in the rig.
* **WIDEN the mock** so `size` returns the seeded value for any non-negative
  int. That is `targets.rb`/`concolic_targets.rb` work on a target shared with
  every endpoint — **Rule T**: a boundary change, raised, not made here.

Until one of them happens this gate contributes a small but permanent
contradiction rate to every construction round, and the honest record is the
167 contradictions plus the observed domain, not a "residue" claim.

#### §76.2(c).3 THE HTML ARM'S ERROR RATE — the §46 repair CONFIRMED at corpus scale

The brief asks for the html arm's error rate because a run that dies in the
view cannot evaluate anything downstream. `_html_error_rate.py`, stride-20 over
all four scenarios of the 183 335-dump corpus, split at `targets.rb`'s own
mtime (the objective §46 boundary, not a label):

```
  scenario   side   sampled   RIG terminals
  anon_html  pre      1 463         859
  anon_html  post       267           0
  auth_html  pre      1 525       1 285
  auth_html  post       236           0
  auth_json  pre/post 1 277 / 2 523   0 / 0
  anon_json  pre/post 1 236 /   642   0 / 0

PRE-REPAIR terminals (5 501 sampled)      POST-REPAIR terminals (3 668 sampled)
  2 513  45.7 %  ran to the end             3 113  84.9 %  ran to the end
  2 144  39.0 %  ActionView::Template::Error  394  10.7 %  RecordNotFound
    441   8.0 %  RecordNotFound               161   4.4 %  Diaspora::NonPublic
    403   7.3 %  Diaspora::NonPublic            0   0.0 %  RIG TERMINALS
```

**Zero rig terminals in 3 668 post-repair dumps, 503 of them html.** Every
post-repair terminal is an APPLICATION terminal — the `RecordNotFound` and
`NonPublic` arms this endpoint is supposed to take. §46's three fixes hold at
corpus scale, not just on its 48-run smoke.

Two consequences, and the second one changes a shipped file:

1. **The html arm is not the cause of class (c).** `_unev_why` bucketed only
   1 114 of 170 484 unevaluated events (0.65 %) as RENDER-ERROR and all of them
   are application terminals. The 65.5 % is conjunction foreclosure, not
   crashes.
2. **`POLICY_HEADER.txt`'s X1/W1 are now WRONG in the direction that matters.**
   They say "none of the html view's own reads are in this file". The corpus
   this policy is extracted from contains **11 043 post-repair html dumps**
   (5 842 auth_html + 5 201 anon_html) of which the sample says ~85 % run to the
   end, so the html view's reads ARE in it. The header is corrected below
   (§76.7) rather than left to read as a larger gap than the corpus has.

### §76.5(c) THE ONE PROPOSAL WITH REAL LEVERAGE — conjunction foreclosure

`src/concolic_engine/coverage.py`, `infer_foreclosures` (§16b) and its use in
the demand-set split. This is notifications' §19.2 proposal, and posts_show's
measurement makes it a much bigger lever here than it was there.

**Now.** `(g, o)` forecloses `d` iff some run evaluated both and every run with
`g = o` left `d` unevaluated — strictly PAIRWISE. A decision foreclosed only by
two or more gates ACTING TOGETHER is never inferred and its assignments stay
demanded forever.

**Proposed.** Infer the same relation over the gate CONJUNCTIONS THE DEMAND
ALREADY CONTAINS: for each demand set, for each leaf group's gate prefix `P` and
each surviving member `d`, if some profile matches `P` and none of the matching
profiles evaluates `d`, then `d` is foreclosed under `P` and the group's
assignments over `d` are not demanded. Nothing is inferred from outside the
demand — `P` is a prefix the pruned tree already built and the "matches `P`"
mask is the one the covering test already computes.

**Evidence on THIS endpoint.** 491 corpus-consistent (member, conjunction)
foreclosures, covering **102 851 of the 124 673 tested unevaluated events —
82.5 %** (§76.2(c).2), every one verified by the same "never" test §16b uses
pairwise, over 32 305 distinct outcome profiles. The named family is the
interaction finders (`findpublic_like`, `findpublic_reshare`, `evilq_reshare_*`)
which run only inside `PostPresenter#with_initial_interactions`: 1 079 runs
match the conjunction and NONE of them evaluates the member.

**Priced, not asserted.** `_exact_enum_conj.py` is a batch-local copy of this
batch's own enumerator with exactly that test added at the leaf group, and
`_conj_price.py` runs the SAME universe and the SAME OR-refined demand sets
through both. The difference IS the price. (§76.6 carries the number; `src/`
is untouched either way.)

### §76.5(b) UNDECIDABLE — where driving DOES work, and where it cannot

The test is not an argument, it is a round: take a real run that evaluates the
decision, keep its seed dict VERBATIM, flip EXACTLY ONE key, replay, and then
apply §16c's own exact keying to the result (`_oneflip_seeds.py` ->
`_demand_drive.sh` -> `_matched_ctx_check.py`, budget 200 runs, pre-registered
before the round). Two outcomes and both are real answers:

* a decision for which the flip produces a MATCHED CONTEXT is **not a limit of
  the method at all** — it is a corpus that had not been asked the question, and
  the lever is more driving of exactly this shape (cheap: one seed per
  decision per base);
* a GATE can never have an exact matched context BY CONSTRUCTION — flipping it
  changes which decisions are evaluated — so for those the honest end state is
  a DECLARED undecidable with its reason, at any corpus size. Under the
  gate-aware (co-evaluated) keying they are measured anyway (§71.1), which is
  why the undecidable count fell 79 -> 30 -> 21 across this drive without a
  single extra run.

§76.6 carries the round's numbers.

## §76.7 WHAT THIS DRIVE CHANGED IN A SHIPPED FILE, and why

Two edits to `POLICY_HEADER.txt`, both made because a MEASUREMENT contradicted
what the file said. Both are recorded here because the file is the artefact a
consumer reads and a silent correction is indistinguishable from a silent
error.

1. **W1's "CONSEQUENCE FOR THIS FILE" replaced.** It said the html view's reads
   are in the file only if the population post-dates 2026-09-10 21:00, and left
   the reader to guess. It now states the measurement (§76.2(c).3): the
   population holds 11 043 post-repair html dumps, the post-repair sample has
   ZERO rig terminals in 3 668 dumps, 84.9 % run to the end, and every
   post-repair terminal is an application terminal.
2. **X1 changed from "the largest gap in this file" to CLOSED**, with the
   evidence inline and the old claim kept visible rather than deleted — a
   reader of an earlier edition was told the opposite and has to be able to see
   that it changed and on what.

Everything else in that file is filled by `_fill_header.py` from
`coverage_summary.json`, the extraction summary and `_residual_classes.json`.
**That script REFUSES to write a header that still contains a `TODO(drive)`**,
so the header cannot ship half-filled: it either carries measured facts or it
fails and says so.

## §76.6 THE DECISIVE MEASUREMENT — 99.75 % of the 2.02e7 is in leaf groups NO RUN HAS EVER WALKED

`_part_decomp.py` re-ran the OR census on the CURRENT snapshot
(`_snapshot_pruned_OD0911.txt`, 32 305 profiles, engine
`256f44c146e4e3a37431365693cbc301`, `REACH_SPLIT=1`, caged at 3 G, 365 s of
census after a 352 s universe build). It reproduces p12's numbers and adds the
one split nothing had measured on the OR-refined demand:

```
OR-refined: sets=1747 satisfiable=20256450 covered=28817 remaining=20227633 bounded=0

=== REACHABILITY SPLIT of the remaining assignments ===
  leaf groups: 4 153 with an observed compatible walk, 1 447 454 with NONE
  demanded 20 256 450   covered 28 817   remaining 20 227 633
  REACHABLE remaining          49 935     0.25 %   (some run walked these
                                                    decisions under these gates)
  MULTI-GATE-FORECLOSED    20 177 698    99.75 %   (no run ever has)
```

**Ninety-nine point seven five per cent of the residual is demand for
assignments under gate combinations the corpus has never walked at all** — and
1 447 454 of the 1 451 607 leaf groups (99.7 %) have no observed compatible
walk. The largest are width-27 groups whose prefix fixes three finder outcomes
at once, verbatim:

```
  sat=32 set#1 width=27 survivors=26
    gates: records_2_rows != 0 = T; records_mentions_66022a8b_rows != 0 = T;
           photos_33150e22_row_text_empty = F; photos_9930492e_row_text_empty = F;
           find_by_3_not_found = T; find_by_6_not_found = T; find_by_9_not_found = F;
           find_by_9_text_empty = F; comments_5e3d4b43_row_text_empty = F;
           as_api_response_1_row_guid == '' = F; _2 = T; _3 = T; _4 = T;
           assoc_root_text_empty = F; assoc_root_text_has_mention = F
```

Three `find_by_N_not_found` outcomes set together in a combination no run
takes. That is the SAME fact `_unev_why.py` measured from the other end —
82.5 % of the unevaluated class is conjunction foreclosure — arriving here as
99.75 % of the demand.

### §76.6.1 What this does to every number in §76.1-§76.4

* **The decomposition stands and gets sharper.** Same shape on the current
  snapshot: 1 747 parts, mass at widths 21-27 (98.9 %), top part 1.46 %,
  top 500 = 96.2 %, 194 parts already at zero. Members by family, counting a
  part once per family (`_part_report.log`):

```
  length gate (rows != 0)     1 652 parts   100.00 % of the mass
  guid                        1 596 parts    99.98 %
  text decision (empty)       1 013 parts    99.64 %
  text decision (has_mention) 1 403 parts    99.30 %
  find_by_N_not_found         1 165 parts    99.23 %
  length gate (Length(param))   123 parts     6.96 %
  assoc / dispatch              118 parts     5.90 %
  text decision (rendered)      446 parts     0.03 %
  findpublic_* not_found        422 parts     0.03 %
  size gate (CollectionProxy#size) 54 parts   0.00 %
  public gate                    37 parts     0.00 %
```

  Every part carrying mass carries all five of the top families at once. That
  is why the parts are wide and why confinement cannot split them.

* **§76.4's 61 days was the WRONG question.** Driving the whole residual is
  61 days; driving the part of it that is REACHABLE — 49 935 assignments — is
  **~3.6 hours at this endpoint's own measured rate (229.5 runs/min)**. The
  residual is not one problem, it is two, and only one of them is a driving
  problem.

* **p12's "exhaustion" is now fully explained.** The round emitted from the
  region — which includes the multi-gate-foreclosed part — so ~99.75 % of what
  it targeted could not be honoured by any seed, because no run walks those
  gate combinations at all. That is the same 65.5 % UNEVALUATED seen from the
  seeding end, and it is why 13 080 runs closed nothing.

### §76.6.2 CORRECTION to §76.3, made here rather than left standing

§76.3 concluded "the binding constraint is REALISATION". That is right, but it
named the mechanism too weakly: realisation fails BECAUSE the demand contains
assignments whose gate combinations no run can reach — not because seeds are
mis-built. The convergence threshold (5.46 minted per run) and the targeting
ratio (10.0 per run) in §76.3 are both computed over a target that is 99.75 %
unreachable, so neither is a fair test of the construction method. **The honest
statement is: the construction method was never tested on this endpoint,
because the demand it was given is dominated by assignments the corpus cannot
produce.**

### §76.5(c) CORRECTED — what the conjunction inference does and does NOT buy

§76.5(c) above was written before §76.6 and it overstates the lever. The
correction, with the reason, because the overstatement would have shipped:

`_exact_enum_conj.py`'s test fires only when **some** profile matches the leaf
group's gate prefix and none of the matching profiles evaluates the member.
§76.6 measured that **1 447 454 of 1 451 607 leaf groups have NO matching run
at all** — so on those the test does not fire by construction, and the
inference cannot touch the 99.75 %.

**PRE-REGISTERED, before `_conj_price.py` is run** (it is queued; the box has
been memory-constrained since 19:1x): the conjunction-foreclosure inference
will remove **a small fraction — my prediction is under 5 % — of the 20 227 633**,
because it can only act on the 4 153 leaf groups that have a matching walk.
Its real value is where `_unev_why.py` measured it: it explains **82.5 % of the
UNEVALUATED CLASS**, i.e. why constructed seeds are not honoured. Those are two
different populations and this drive conflated them for one section.

**So the 99.75 % needs a different proposal, and there are exactly three, with
their soundness stated:**

* **(P1) EMIT AND DRIVE THEM** — the current default (`EMIT_REACHABLE_ONLY=0`
  since 2026-09-11, §69.2). Sound, and priced at §76.4's 61 days, with the
  measured result that constructed seeds for these combinations are not
  honoured (§76.2(c)).
* **(P2) PRUNE leaf groups whose gate prefix no run has matched.** This would
  remove 20 177 698 assignments — the whole 99.75 % — and **it is NOT SOUND on
  this project's own precedent**: §71.2 found 17 of 18 "unreachable" gate
  outcomes realisable by direct construction, and §72.3 showed the single
  remaining one was a MOCK DOMAIN, not an impossibility. Corpus absence is not
  impossibility. It is recorded here as the tempting move and refused.
* **(P3) THE MIDDLE ROAD, and the one this endpoint should take next.**
  Construct per GATE COMBINATION with a base that MATCHES the combination
  (the base-selection criterion `_construct_by_gate.py` drops, §76.2(c).2's
  REACHABLE 17.5 %), drive, and measure realisation per combination. A
  combination that still cannot be realised from a matching base, after the
  base-selection fix, is **impossibility evidence AT THE CONJUNCTION LEVEL** —
  which is exactly the evidence §16b's pairwise inference cannot produce and
  which this endpoint has never had. 1 635 distinct gate combinations were
  constructed in OD0911; that is the population to re-run, and it is a
  ~1 600-seed round, not a 61-day one.

**The honest end state of the construction arm tonight is therefore:** the
method has NOT been shown exhausted; it has been shown to be aimed, 99.75 % of
the time, at gate combinations the corpus has never walked, with a constructor
that does not root its seeds in a matching base.

### §76.2(b) UNDECIDABLE — classified by WHY, not by a name heuristic

`_oneflip_seeds.py` inherits a name heuristic for "gate-like" and on this
endpoint it mis-sorts in BOTH directions: it calls
`evilq_like_public_1_text_empty` a gate because the ALIAS contains `_public`,
and it does not recognise `SYM_LEN_..._rows != 0` as a length gate at all.
`_undec_classify.py` sorts the 21 by the reason no matched context exists:

```
  SELF-COMPARE   5   (X != X) — UNSAT, no context can EVER exist
                     all five are ..._records_photos_*_row_status_message_guid
                     != itself: the DecisionAlias artefact
                     (call_interceptor.rb:142-144), already declared
  PINNED         7   ARGUMENT P: 4 x as_api_response_{1..4}_row_guid != '' (P2)
                     + 3 x SYM_LEN_..._records_{7,8,10}_rows != 0 (P1).
                     Declared ONE-SIDED after TWO falsifier rounds
                     (TR0910a 45 seeds + TR0910w 3 024 seeds, HIT=0 both).
                     No matched context BY DECLARATION — which is the point
  GATE           4   SYM_LEN_..._{records_5, records_tags_2558b920,
                     records_comments_76960418, records_participations_4a978df9}
                     _rows != 0 — flipping changes WHICH decisions are
                     evaluated, so no EXACT context can exist at any corpus
                     size (they are measured under the co-evaluated keying)
  ADDRESSABLE    5   ..._records_comments_5e3d4b43_row_text_empty
                     ..._records_comments_76960418_row_text_empty
                     ..._records_comments_76960418_row_text_has_mention
                     ..._records_comments_9b88e117_row_text_empty
                     (SYM_RESULT_Anonymous_process_3 == '')
```

**Only 5 of the 21 can be closed by a round at any corpus size.** The other 16
are not a gap in the driving — they are a self-compare that cannot be
satisfied, a declaration this endpoint made and falsified twice, and gates
whose definition excludes an exact context. That is the honest denominator for
class (b), and it is four times smaller than the count.

The round itself: `_oneflip_seeds.py` built **16 seeds** (its own heuristic's
targets, which INCLUDES the seven pinned ones — deliberately kept, because a
seed that HITS a pinned expression falsifies the pin and that is the third
falsifier round this endpoint would have), all from `auth_json` bases, well
under the pre-registered 200-run budget.

#### §76.2(b).2 THE ROUND RAN — 0 of 16, and the REASON is context diversity

`_demand_drive.sh OF0911B`: 16 one-flip seeds, 16 runs, corpus 183 335 ->
183 351. Then §16c's EXACT keying over the round plus the whole 32 321-dump
population (`_matched_ctx_check.py`, 2 G, caged):

```
=== MATCHED CONTEXT NOW EXISTS: 0 of 16 ===
=== STILL NO MATCHED CONTEXT: 16 ===
  single-sided runs / DISTINCT CONTEXT KEYS
      4 564 / 4 560   as_api_response_1_row_guid != ''
      3 835 / 3 835   as_api_response_2_row_guid != ''
      3 715 / 3 715   (SYM_RESULT_Anonymous_process_3 == '')
      3 416 / 3 416   as_api_response_4_row_guid != ''
      2 805 / 2 805   records_comments_5e3d4b43_row_text_empty
      2 587 / 2 585   as_api_response_3_row_guid != ''
      1 575 / 1 575   records_comments_9b88e117_row_text_empty
      1 356 / 1 352   records_comments_76960418_row_text_has_mention
        891 /   887   records_comments_76960418_row_text_empty
          0 /     0   the six SYM_LEN_... gates (never evaluated single-sided)
```

**The mechanism is named by the second column: 4 560 DISTINCT CONTEXT KEYS over
4 564 single-sided runs.** Almost every run in this corpus has a context no
other run shares. The exact keying matches on EVERY other evaluated expression,
and with 137 tracked decisions a one-flip seed's replay moves other decisions
downstream, so base and flip land in different keys. **This is not a driving
failure that more runs would fix — it is the exact keying meeting a
137-decision endpoint.** It is also precisely why §16c has the co-evaluated
keying as a fallback for gates (§71.1), and why that fallback took undecidable
from 79 to 30 without a single run.

So class (b)'s honest end state: **21 undecidable, of which 5 are UNSAT
self-compares, 7 are declared pins, 4 are gates with no possible exact context,
and 5 are addressable in principle but NOT by one-flip driving at this corpus's
context diversity.** What would decide the 5 is the co-evaluated keying applied
to non-gates as well, or a context key restricted to a decision's own
footprint — both `src/` changes, neither installed, and the second is the one I
would propose because it matches what "matched context" is FOR.

#### §76.2(b).3 The round doubled as the THIRD FALSIFIER ROUND for ARGUMENT P

The seven pinned expressions were deliberately kept in the seed set, because a
seed that HITS a pinned side falsifies the pin. `_oneflip_falsify.py` over the
16 dumps:

```
  evaluated 12 / HIT 0   as_api_response_1_row_guid != ''
  evaluated  6 / HIT 0   as_api_response_2_row_guid != ''
  evaluated 10 / HIT 0   as_api_response_3_row_guid != ''
  evaluated  6 / HIT 0   as_api_response_4_row_guid != ''
  evaluated  0 / HIT 0   SYM_LEN_..._records_{7,8,10}_rows != 0
  TOTAL HIT = 0
```

**Third round, HIT=0 again** (TR0910a 45 seeds, TR0910w 3 024 seeds, OF0911B 16
seeds targeted directly at them). The pins stand, and the record now shows them
survived a round built specifically to break them.

## §76.10 STATE AT THE MEMORY WALL — what ran, what is queued, and on what gate

The box was memory-constrained for the whole of this drive by an editor
language server OUTSIDE the experiment's cgroup: **3.1 GB at 18:49, 5.1 GB at
19:16, ~6 GB at 19:45**. The coordinator lowered the cage twice —
MemoryMax 12G -> 6G (High 5G) at 19:0x, then **4G (High 3G) at 19:4x** — and
directed that nothing over ~3 G be launched until the editor is closed.

Every launch in this drive went through `_cage.sh`'s gate with the invariant in
force at the time, and the gate's two numbers are in every log line. The
invariant was relaxed ONCE, deliberately and with the reason recorded in the
file itself: the original `free -g >= 4` clause would have deadlocked every job
for the rest of the night once the language server pinned `free -g` at 3, so it
was replaced by the coordinator's own restated bound plus a per-job physical
check (`free >= cap + 512 MiB`). That is a relaxation and it is labelled as
one in `_cage.sh`.

### RAN, under the constraint

| stage | cap | result |
|---|---|---|
| `_emit_reach.py` | 900 M | the emitter-reach decomposition (§76.1) |
| `_topparts_members.py` | 900 M | members of the wide parts by family (§76.1.5) |
| `_gc_realise.py` (OD0911) | 2 G | the refreshed realisation table (§76.2(c)) |
| `_unev_why.py` | 2 G | the conjunction test on the unevaluated class (§76.2(c).2) |
| `_html_error_rate.py` | 900 M | the html arm, 0 rig terminals post-repair (§76.2(c).3) |
| `_part_decomp.py` + `_part_report.py` | 3 G / 1 G | the per-part census and REACH_SPLIT — **the 99.75 %** (§76.6) |
| `_undec_classify.py` | — | the undecidable, by reason (§76.2(b)) |
| one-flip round OF0911B | 3 G | 16 runs; 0 of 16 matched contexts (§76.2(b).2) |
| `_oneflip_falsify.py` | 900 M | ARGUMENT P's third falsifier round, HIT=0 (§76.2(b).3) |
| extraction, `SKIP_SUBSUME=1` | 1 G | running (62 MB peak, ~2 250 dumps/min over 183 351) |

### QUEUED, each behind a gate that fires by itself

| stage | gate | why it could not run |
|---|---|---|
| `coverage_report.py`, the final pass | `free -g >= 6` (`_p13c.sh`) | needs ~1.6 G but the box has no window; queued, not skipped |
| the ENGINE SECTION (shims, notes, the gate on the confined pairs) | `free -g >= 6` | notifications' equivalent gate needed 7 G and was KILLED at 5 G; it cannot run under a 4 G cage at all — **this is the "report and stop" case the coordinator named** |
| `_c7_audits.sh` (with the streaming lint, X12 vehicle) | `free -g >= 6` | the suite's own history is a 5.9 GB kill (§66) |
| extraction WITH blockaid subsumption | `free -g >= 6` | the JVM harness is the 5-6 G consumer; the SKIP_SUBSUME edition ships with `subsume_state=None`, never `False` |

Nothing above is abandoned: `_night13b.sh` holds the chain, each stage polls
its gate, and `_p13_recorder.sh` appends every stage's own verdict lines to
this file when the chain ends, whether or not an agent is watching.

## §76.11 `pc_visibility` — the Class B ruling, settled the way people_stream settled it

The audit suite is queued behind the memory gate, but the QUESTION
`pc_visibility` asks is a gate-column question and it can be settled on the
declaration sites, which is exactly how people_stream settled its own
(`_COMPLETION_20260910.md` §473 there: "NOT a declaration site in this batch …
RAISED with evidence, not fixed"). §37 measured four BLIND columns here; each
gets its ruling and its falsifier:

* **`diaspora_handle` — RAISE, do not fix (Rule T3).** The swallowing target is
  `PostPresenter#build_mentioned_people_json`, declared in the MASTER
  `reports/diaspora/concolic_targets.rb:1337`, not only in this batch's copy —
  verified by grep, not assumed. Identical to people_stream's X3, now confirmed
  on a second endpoint. **Falsifier: descend that target and the column gains
  PC references in the next corpus.**
* **`type` — RAISE.** STI dispatch is decided by `model_class` in RUBY, and
  `model_class` is present in the master boundary file as well as this batch's.
  The decision is real and invisible to the checker because no symbolic
  comparison is made. **Falsifier: make the dispatch read a symbolic `type` and
  the column gains PC references.**
* **`text` and `comments_count` — RE-MEASURE, because this drive CHANGED the
  answer.** §37's cause was that the text path is walled by `Anonymous.process`
  (a declared SQL-free target) and the corpus carried text decisions as
  `_has_mention` / `_text_empty` booleans one level up. Tonight W7 rebuilt that
  wall with `PcVisibleConcreteString`, whose `==`/`!=` ARE recorded, and W10
  made the text EMPTYABLE. The declaration site is **this batch's own
  `targets.rb`** (lines 887, 910), so unlike the other two it is fixable here
  and may already be fixed. **This is a prediction, registered before the audit
  runs: `text` moves from BLIND to VISIBLE on the post-repair corpus;
  `comments_count` does NOT, because nothing in this endpoint compares it.**

The audit's own RED stands until the suite runs; what is settled here is which
of the four are Rule-T3 raises (two) and which are this batch's to answer
(two), each with the falsifier that would overturn it.

## §76.12 INDEX of §76, because it was written in measurement order

| § | what it settles |
|---|---|
| §76.0 | the brief's `capped_sets=1` is a misreading — it is **1 310 of 1 677** |
| §76.1 | the 2.02e7 decomposed: **no part holds >1.46 %**, top 500 = 96.2 %, mass at widths 21-27 |
| §76.1.3 | the emitter reached 0.65 % because `EMIT_MAX_PER_SET=8`, not because of any wall (`region_bound=0`, `no_model=0`) |
| §76.1.4 | p12's STOP verdict is not supported at the strength it was stated; the round's ceiling was 131 279 |
| §76.1.5 | what the wide parts are made of: guid, length gates, text-empty, has-mention, find_by_N — all five in every part that carries mass |
| §76.2(a) | **52** genuinely two-sided decisions, by family; not licensable |
| §76.2(b) | the **21** undecidable by REASON: 5 UNSAT self-compares, 7 declared pins, 4 gates, **5 addressable** |
| §76.2(b).2 | the one-flip round: **0 of 16**, and the reason is 4 560 distinct context keys over 4 564 runs |
| §76.2(b).3 | ARGUMENT P's **third** falsifier round: HIT=0 |
| §76.2(c) | the refreshed realisation table: **65.5 % UNEVALUATED** (was 68.2 %); §72.4's pre-registration only half came true |
| §76.2(c).2 | **82.5 %** of the unevaluated class is CONJUNCTION FORECLOSURE |
| §76.2(c).3 | the html arm post-repair: **0 rig terminals in 3 668 dumps** |
| §76.3 | the convergence arithmetic (superseded in its conclusion by §76.6.2) |
| §76.4 | the scale: 61 days to drive the whole residual |
| §76.5 | what `COMPLETE=True` would require, per class — (a) nothing licensable, (b) a keying change, (c) see the correction, (d) a model ruling |
| §76.5(c) CORRECTED | the three proposals for the 99.75 %: drive them, prune them (**refused as unsound**), or construct per combination from a MATCHING base |
| **§76.6** | **the decisive measurement: 99.75 % of the residual is in leaf groups no run has ever walked; only 49 935 (0.25 %) are reachable** |
| §76.7 | what this drive changed in `POLICY_HEADER.txt`, and why |
| §76.10 | the memory wall: what ran, what is queued, on what gate |
| §76.11 | `pc_visibility`'s four BLIND columns: two Rule-T3 raises, two this batch's, each with a falsifier |

## §76.13 AN INSTRUMENT NOTE FOUND BY ACCIDENT — the exact census is LOAD-SENSITIVE

Two runs of the SAME enumerator over the SAME universe, the same fixed
`DUMP_LIST`, the same flags, minutes apart, do not agree:

```
  _part_decomp.py  (19:47, box at MemoryHigh, heavy reclaim)
      satisfiable 20 256 450   covered 28 817   remaining 20 227 633
  _conj_price.py   (20:03, box with headroom)   <- and p12's own 12d census
      satisfiable 20 331 999   covered 29 511   remaining 20 302 488
```

Everything upstream is byte-identical — `[assumptions] declared=1123
INERT=762 OVERNIGHT_PINS=8`, `evaluation sets=165 -> demand sets=1885`,
`foreclosures inferred: 550 over 60 gates`, `decisions: 137 active -> DECIDED
116 … UNDECIDABLE 21`, `confined 2315 / overlapping 0 / disqualified 597 /
undecidable 1160`, `1885 -> 1747 parts`. **The universe and the projection are
the same to the last number; only the COUNTS differ, by 0.37 %.**

The cause is in the enumerator's own configuration: `Z3_TIMEOUT_MS` defaults to
**10 000 ms** (`_exact_enum_emit.py:95`) and every `sat`/`covered` count is a
sum over `check_satisfiability` results. Under memory pressure a call that
normally returns in well under a second can hit the timeout, and a timeout is
counted as NOT satisfiable — so a loaded box counts FEWER assignments. The
direction is systematic, not random: **load makes the residual look smaller.**

Consequences, stated rather than smoothed:

* the reference numbers in this section are the UNLOADED run's
  (20 302 488 remaining), which also reproduces p12's 12d census exactly;
* **§76.6's REACH_SPLIT ratio came from the LOADED run** — 49 935 reachable /
  20 177 698 unreachable of 20 227 633. The ratio 0.25 % / 99.75 % is what
  matters there and it is not sensitive to a 0.37 % undercount, but the two
  absolute numbers carry that undercount and are quoted with it;
* any future comparison of two censuses on this endpoint must either run both
  on a quiet box or raise `Z3_TIMEOUT_MS`, or it will measure the box rather
  than the demand. **This is the first time this drive has had a number that
  moved for a reason outside the experiment, and it was found only because two
  runs happened to overlap.**

## §76.14 THE CONJUNCTION-FORECLOSURE PRICE — measured, and the pre-registration HELD

`_conj_price.py`: one universe, the SAME 1 747 OR-refined parts, two censuses —
the shipped enumerator, then `_exact_enum_conj.py`, which is a batch-local copy
of the same file with the leaf-group-prefix "never" test added and nothing else
changed. `src/` untouched. Caged at 3 500 M, `CAGED-OK`.

```
STOCK: sets=1747 satisfiable=20331999 covered=29511 remaining=20302488
CONJ : sets=1747 satisfiable=20330262 covered=30731 remaining=20299531
CONJ STATS: members_dropped=913  groups_touched=755
PRICE: remaining 20302488 -> 20299531   (0.01 % removed from the demand)
```

**0.01 %. 2 957 assignments of 20 302 488.** §76.5(c)-CORRECTED pre-registered
"under 5 %" before this ran; the answer is two and a half orders of magnitude
below even that bound, and the reason is exactly the one registered with it:
the test can only fire on the 4 153 leaf groups that HAVE a matching run, and
it fired on 755 of them, dropping 913 member-slots.

**This closes the question the brief opened.** Three things were candidates for
"the whole story of the 2.02e7":

| candidate | verdict |
|---|---|
| one capped set / parts the emitter cannot enumerate | **refuted** — §76.0/§76.1: 1 310 capped sets, no wall, no part over 1.46 % |
| conjunction foreclosure as a DEMAND pruner | **refuted by measurement** — 0.01 %, this section |
| gate combinations no run has ever walked | **CONFIRMED** — §76.6: 99.75 % |

And the corollary is uncomfortable and worth stating plainly: **the residual is
not something the checker can infer away and not something the corpus has
shown impossible.** It is 20.2 million assignments under gate combinations that
have never been walked, whose only sound treatments are to walk them (§76.5(c)
P1/P3) or to obtain impossibility evidence at the conjunction level, which no
instrument in this project currently produces.

## §76.15 THE SHIM LAYER, REFRESHED FOR TONIGHT'S DECLARATIONS — 23 shims, 0 FAIL, 0 waivers

The full engine section cannot run under the 4 G cage (the assumption gate is
the 5-7 G consumer), but the SHIM layer is a separate, cheap command and it is
the half that tonight's declarations changed. `_run_shims.sh` runs exactly the
two commands `concolic_engine.completion` would run — `extract_cmd` and
`test_cmd` from `completion_config.json`, same inputs, same output shape —
caged at 2 500 M.

**Tonight's declaration delta, enumerated from the file rather than from the
brief** (`targets.rb.pre_csstring` vs `targets.rb`):

```
  4 ADDED declare_target
      Diaspora::MessageRenderer::Processor.singleton_class :process  (PC-visible carrier)
      Diaspora::MessageRenderer                            :title
      Photo                                                :url
      ActiveRecord::Associations::CollectionProxy           :size    (W11)
  1 CLASS   PcVisibleConcreteString (+ ConcreteSymbolicString restored)
  1 STUB    Person.name_from_attrs (W8) — a SINGLETON stub, not a target
  4 DISABLED in concolic_targets.rb
      three "DISABLED HERE, OWNED BY ./targets.rb W7" (§46.8) + X6i Person#name
```

The shim extractor sees **23** shims where `_shim_results.json` (2026-09-10
19:16) had 22; the new one is `Person.name_from_attrs`. A test was written for
it as a GROUND-TRUTH DIFFERENTIAL, not as an invocation check: it captures the
REAL `Person.method(:name_from_attrs)` BEFORE `install!` replaces it, runs the
real body on three inputs under an `sql.active_record` subscription, and
asserts the real body issues NO SQL, reaches NO target, and is exactly
person.rb:254-256's string logic (`"Alice Smith"`, `"alice@example.org"`,
`"Alice"`) — which is the claim the stub rests on. No `coverage_waiver`; the
runner refuses those and is right to.

```
  shims extracted: 23
  SHIM VERDICTS: {'PASS': 14, 'PROTOCOL': 9}
  W8 entry: Person.name_from_attrs  PASS  coverage 100.0  invoked True
            targets_reached [] == targets_declared []
```

**14 PASS / 9 PROTOCOL / 0 FAIL / 0 NO-TEST / 0 waivers**, against §17's 13/9/0
on 22 shims. The shim half of the engine section is GREEN on tonight's
declarations; what remains queued is the note check and the assumption gate.

## §76.16 THE HONEST END STATE OF posts_show, and what the next agent picks up

**`OVERALL_COMPLETE` is not `True` on this endpoint and this drive did not make
it so.** What it did is turn "2.02e7 remaining" from a number into a named,
measured residual with a cause for every part of it:

```
  20 302 488 assignments the confinement-refined demand still asks for
     49 935   0.25 %  REACHABLE      — some run has walked those decisions
                                       under those gates. ~3.6 h of driving at
                                       this endpoint's own measured rate.
 20 177 698  99.75 %  NEVER WALKED   — gate combinations no run has produced.
                                       NOT inferable away (the conjunction
                                       inference prices at 0.01 %), NOT shown
                                       impossible (§72.3 removed this
                                       endpoint's last impossibility claim).
```

and, cutting across it, four classes with their own numbers: 52 genuinely
two-sided decisions that no declaration may license; 21 undecidable of which
only 5 are addressable at all and 0 of 16 were closed by a one-flip round
because the corpus has ~one distinct context key per run; 65.5 % of constructed
gate outcomes never reached, 82.5 % of that explained by conjunction
foreclosure; and one mock-domain gate awaiting a model ruling.

### The four things the next agent should do, in order

1. **P3 from §76.5(c)** — re-run the construction with a base that MATCHES the
   gate combination (1 635 combinations, a ~1 600-seed round, not a 61-day
   one). This is the only experiment that can turn "never walked" into either
   coverage or the first conjunction-level impossibility evidence this project
   would have.
2. **The queued stages**, when the box returns: the final pass, the ENGINE
   SECTION (its gate is the 5-7 G consumer — notifications' equivalent was
   killed at 5 G and needed 7 G), `_c7_audits.sh`, and the blockaid
   subsumption. All four are already gated and fire by themselves.
3. **The two `src/` proposals**, each with this endpoint's number attached:
   conjunction foreclosure (0.01 % of the demand but 82.5 % of the seeding
   failure) and a context key restricted to a decision's own footprint (the
   only thing that can decide class (b)'s last 5).
4. **The one owner ruling**: whether the `{0,1,2,4}` mock domain IS the model
   of `photos.size` (declare it) or a limit (widen it — Rule T, shared
   boundary).

### What is on disk for them

`_parts_OD0911.json` (1 747 parts with members, sat, covered, remaining),
`_reach_split_PD.json` (the 0.25 % / 99.75 % split with its 200 largest
unreachable leaf groups), `_conj_price.json`, `_unev_why.json`,
`_gc_realise.json`, `_undec_classified.json`, `_matched_ctx_OF0911B.json`,
`_shim_results_20260911.json`, `_html_error_rate.log`, and
`_exact_enum_conj.py` — the batch-local enumerator with the conjunction test,
ready to be promoted to `src/` if the owner takes that proposal.

## §76.17 THE UNCAGED BLOCKAID JVMs WERE NOT THIS DRIVE'S — traced, and the path hardened anyway

**Coordinator, 2026-09-11 20:4x:** two `java -Xmx1g -cp
src/queries_from_runs/subsume/...` JVMs, 1.7 G and 1.2 G, running OUTSIDE the
cage and two at once; killed. Asked: which script launched them.

**Traced to the parent, not guessed.** The JVMs' parent is

```
pid 1234054  python3 scripts/blockaid_sweep.py --backend h2 --checker diff \
             --jobs 2 --shards 2 --solve-timeout 20000 \
             results/claude-fable-high-agentic-applevel.jsonl \
             results/claude-fable-high-agentic.jsonl  results/claude-haiku-mediu...
cgroup: /user.slice/.../app.slice/run-r3b953cb24781431a9cad6ef383f8dd26.scope
```

a **blockaid model-comparison sweep run from `/home/dev/project` over
`results/*.jsonl`**, from a different shell session (snapshot
`1789154107534-4r17hh`), in `app.slice` — **not** `concolic.slice`. `--jobs 2
--shards 2` is exactly why there were TWO JVMs. **It is not this endpoint's
extraction and not `_install_policy_when_ready.sh`.** (The
`statement_note_lint.py` also on the box at the time belongs to
`notifications_index/_c7_audits.sh`, pid 1223885 — this batch's audits use
`_lint_streaming.py` and are still gated.)

**This drive's own state at that moment, each checked by cgroup, not asserted:**

```
  1189224  /venvs/queries_from_runs/bin/python  _extract_posts_show_streaming.py
           cgroup .../concolic-cov.slice/p13ext1.scope   RSS 69.7 MB of a 1 G cap
           env SKIP_SUBSUME=1     72 000 / 183 335 dumps, still running
  1173087 / 1206609 / 1206637 / 1206638   tail, bash, tee — the `wait_free6`
           poll loops, 2-4 MB each; TOTAL uncaged footprint of this drive
           8.6 MB, none of it compute
```

**No JVM has ever been started by this drive**, and the extraction that is
running cannot start one: `SKIP_SUBSUME=1` takes the first branch of the
tri-state block, before `checker_available()` is ever consulted.

### Hardened anyway, because "it inherits the cgroup" is an assumption

`src/queries_from_runs/subsume.py:107` calls `check_subsumed.sh` through a
**sequential `subprocess.run`** — one JVM at a time by construction — and a
child inherits its parent's cgroup, so a JVM under `cage` IS caged. Stage 13d-2
now states and CHECKS that rather than relying on it:

* cap lowered 5 G -> **3 G**, `wait_free6` (free -g >= 6) **and** `wait_alone`
  (whose pattern already blocks on `java … -cp …subsume`, so it will also stand
  aside for the other agent's sweep);
* **`_jvm_guard.sh`** runs beside the stage and inspects `/proc/<pid>/cgroup`
  of every `java` on the box every 15 s. A JVM of MINE outside
  `concolic-cov.slice` stops the stage; another agent's is logged and never
  killed.

## §76.18 EXTRACTION REMOVED — policies are extracted at CLOSURE only

**Owner rule, relayed by the coordinator 2026-09-11 21:1x, correcting the
brief this drive was given:** a policy file is produced only after the
endpoint's pass prints `complete: true`. comments_index, conversations_index
and people_stream were each extracted after closure; **posts_show is not
complete**, so it gets no policy. The running `SKIP_SUBSUME=1` extraction
(72 000 of 183 335 dumps) and `_install_policy_when_ready.sh` were killed by
the coordinator at 21:10.

**State, verified rather than asserted:**

```
  queries_from_runs/posts_show*        — DOES NOT EXIST (nothing was written;
                                          the extractor emits its .sql only at
                                          the end, and it never got there)
  queries_from_runs/_summary_posts_show* — DOES NOT EXIST
  other endpoints' policies  notifications_index.sql 08-21, conversations 09-01,
                             people_show 09-09, comments_index 09-09,
                             people_stream 09-11 13:32 — ALL untouched today
  posts_show/POLICY_HEADER.txt  last written 19:56, when the STANDING block was
                             installed; nothing added since
```

**What was removed, and how, so nothing can drift back:**

* `_p13d.sh` (extraction + subsumption) is now a REFUSAL STUB that logs and
  exits 0; its previous body — with the 3 G cap, the free-6 gate, `wait_alone`
  and `_jvm_guard.sh` — is kept verbatim at `_p13d.sh.REMOVED_20260911`, so the
  record shows what was removed rather than that something vanished, and so the
  agent that eventually CLOSES this endpoint has the working launcher already
  written.
* `_run_extract_nosub.sh` and `_install_policy_when_ready.sh` are refusal stubs
  the same way (`*.REMOVED_20260911` alongside).
* The chain was stopped and relaunched as **`_night13c.sh`**, which contains
  **only** 13c — the final pass, the engine section, `_c7_audits.sh` — each
  still caged and gated on `free -g >= 6`. `grep` over the new chain and
  `_p13c.sh` finds no extraction or subsumption stage at all.

**The header's remaining three `TODO(drive)` markers are in the EXTRACTION
STANDING block and are now CORRECT as they stand**: they are instructions to
the drive that closes this endpoint and extracts its policy, which is exactly
when they should be replaced. Nothing was added to the header beyond the
STANDING block that states the endpoint is not complete.

**The deliverable of this drive is therefore §76 itself** — the residual
characterisation — not a policy file, and `results3/_RESTART_HANDOFF_20260911.md`
§1 records posts_show's state in those terms.

## §77. THE P14 PASS, THE GAPS CLASSIFIED, AND A CONSTRUCTED BATCH (2026-09-12)

Written after `_cov_FINAL_P14_20260912.json` landed, by the analysis-and-
construction pass the RUNBOOK requires **before** anything is called residue.
Nothing was driven here; §78 will carry the drive's verdict.

### §77.1 What P14 says, verbatim

```
_cov_FINAL_P14_20260912.json      (engine §16d, one Z3 query per demand set)
  complete                 false          truncated                true
  tree_nodes                 137          tree_complete            true
  demand_sets               1747          tree_missing               []
  missing_branches          5776          unevaluable_exprs          []
  total_runs              32 305          solver_lost                 0
  total_path_conditions 1 196 750         foreclosures           26 888
  snapshot   _snapshot_pruned_OD0911.txt  foreclosures_ignored        0
  checkpoint _cov_p14.ckpt.jsonl          foreclosures_PROVISIONAL false
  wall                     35 min
```

Two of those lines are the ones that matter and neither was true of the passes
§76 reasoned from. **`tree_complete` is true with an EMPTY `tree_missing`**, and
therefore **`foreclosures_provisional` is FALSE**: §16b's precondition holds on
this corpus, so the foreclosure relation the demand rests on is no longer
conditional. `solver_lost = 0` and `unevaluable_exprs = []` — the §16d
sharpening (a Z3 `unknown` can no longer read as coverage) had nothing to
report. `truncated` is true because the pass ran at a per-set cap, which §16d
says is expected on any incomplete pass and weakens nothing.

**One correction to the brief this pass was handed.** It described P14 as "one
witness per set". The pass in fact ran with `max_missing_per_clique = 4`: the
checkpoint holds **6 150** witnesses over the 1 747 set records (183 sets clean,
16/20/18 sets at one/two/three, and **1 510 sets stopped AT the cap**), which the
checker's cross-set dedup reduces to the reported **5 776** over **1 512
distinct sets**. That the great majority of flagged sets stopped at the cap is
the §16b/§16d point restated as a measurement: *the reported missing list is a
LOWER bound*, and 5 776 is a floor on the remaining leaves, not a count of them.

**Read the CHECKPOINT, not the summary.** `_cov_FINAL_P14_20260912.json` is
360 MB and its `missing[]` array is cut at `MISSING_CAP = 4000` — 1 776 of the
5 776 witnesses are not in it. `_cov_p14.ckpt.jsonl` (15 MB) carries all of
them, one record per set, `combos[i]` the leaf and `models[i]` its
counterexample. Everything below is computed from the checkpoint; the summary is
sliced for two scalars only (`foreclosure_gates`, the header counts) without
parsing it.

### §77.2 The classification

`_p15_classify.py` (new, this drive) joins each witness to its demand set in
`_parts_OD0911.json` — by `checkpoint.digest(group)` where that matches (511 of
1 747) and by member-set containment otherwise; **0 sets went unmatched** — and
then to the observed domain of all 32 305 snapshot dumps built by
`_p15_index.py`.

Parts are named by the decision families their members touch (§76.1.5's
taxonomy, abbreviated: api = `as_api_response`, root = `assoc_*`, cmt/lik/men/
par/pho/tag = the per-list rows, fnd = `find_by`, evq = `evilq_*`, fpb =
`findpublic_*`, rnd = `Anonymous.process`). "in-domain" = every value the cube
CONSTRAINS is one some run has produced; "needs-new" = at least one is not.

```
part family mix                                 #sets  #gaps     width  in-domain   needs-new
api+cmt+fnd+men+par+pho+root                      379   1517     14-23       1262         255
api+cmt+fnd+lik+men+par+pho+root                  194    702     13-25        702           0
api+cmt+fnd+men+pho+root                          140    550     10-27        263         287
api+cmt+fnd+par+pho+root                           99    362     13-22        266          96
api+cmt+lik+men+pho+root                           95    340     15-22        272          68
api+cmt+men+pho+root                               72    280      7-20        258          22
api+cmt+men+pho                                    60    218      6-12        103         115
api+cmt+pho                                        33    114       5-9         23          91
evq+fnd+men+pho+rnd                                26    112       7-7          0         112
evq+fnd+pho+rnd+tag                                26    101       6-7          1         100
api+cmt+men+par+pho+root                           27     96     13-18         96           0
evq+fnd+pho+rnd                                    23     92       6-6          0          92
evq+fnd+men+pho+rnd+tag                            28     88       6-8         56          32
api+cmt+men+par+pho                                20     80      9-12         15          65
api+cmt+fnd+men+pho                                21     79      9-13         17          62
evq+fnd+men+pho+rnd+root                           18     71      7-10          5          66
evq+fnd+pho+rnd+root                               15     71       6-8          6          65
fpb+men+pho+rnd+root                               16     64       7-7          6          58
api+cmt+lik+men+par+pho+root                       17     61     16-19         61           0
api+cmt+fnd+pho                                    16     54      8-10          4          50
api+cmt+fnd+lik+men+par+pho                        14     52     12-15         52           0
evq+fnd+pho+rnd+root+tag                           11     50       7-9         10          40
api+evq+fnd+men+pho+rnd                            13     50       7-7         18          32
api+evq+men+pho+rnd+tag                            13     48       6-8         48           0
fpb+men+pho+rnd                                    12     48       7-8          0          48
api+cmt+pho+root                                   10     37      6-16         19          18
api+cmt+fnd+pho+root                                7     37     10-14         25          12
api+fpb+men+pho+rnd                                12     36       6-6          4          32
api+evq+fnd+pho+rnd+tag                             8     32       7-7         16          16
api+evq+fnd+pho+rnd                                 7     32       6-6          0          32
api+cmt+fnd+par+pho                                 7     28      8-12         20           8
evq+men+pho+rnd+root+tag                            9     27       6-7         27           0
evq+pho+rnd+root                                    6     22       6-6          3          19
evq+pho+rnd+root+tag                                5     20       6-7          5          15
api+cmt+lik+pho                                     5     18       6-9          9           9
evq+men+pho+rnd+tag                                 5     17       6-8          1          16
api+cmt+fnd+lik+men+pho+root                        4     16     23-23          4          12
api+cmt+par+pho+root                                3     16     13-14         12           4
api+cmt+lik+men+par+pho                             4     16     11-13         16           0
fpb+men+pho+rnd+tag                                 4     16       8-8          0          16
fpb+pho+rnd+tag                                     4     16       7-7          0          16
api+evq+pho+rnd+tag                                 4     16       6-6          0          16
api+fpb+men+pho+rnd+tag                             4     16       6-6         16           0
api+cmt+fnd+men+par+pho                             3     12     10-11         12           0
api+cmt+par+pho                                     3     12      7-10          4           8
evq+men+pho+rnd+root                                2      8       7-8          0           8
evq+pho+rnd+tag                                     2      8       7-7          0           8
evq+pho+rnd                                         3      8       6-6          0           8
api+cmt+lik+par+pho+root                            1      4     14-14          4           0
api+cmt+lik+pho+root                                1      4     13-13          4           0
api+evq+fnd+men+pho+rnd+tag                         1      2       7-7          2           0
TOTAL                                            1512   5776      5-27       3747        2029
```

```
-- by WIDTH
   width   5: gaps    10  sets     5  in-domain    10
   width   6: gaps   359  sets    98  in-domain    74
   width   7: gaps   644  sets   167  in-domain   186
   width   8: gaps   233  sets    59  in-domain    89
   width   9: gaps   207  sets    56  in-domain    50
   width  10: gaps   158  sets    41  in-domain    27
   width  11: gaps   121  sets    31  in-domain    35
   width  12: gaps    77  sets    20  in-domain    40
   width  13: gaps   104  sets    25  in-domain    84
   width  14: gaps    92  sets    26  in-domain    83
   width  15: gaps   201  sets    54  in-domain   197
   width  16: gaps   233  sets    61  in-domain   226
   width  17: gaps   336  sets    88  in-domain   311
   width  18: gaps   363  sets    95  in-domain   341
   width  19: gaps   460  sets   125  in-domain   413
   width  20: gaps   486  sets   128  in-domain   422
   width  21: gaps   509  sets   130  in-domain   368
   width  22: gaps   372  sets    94  in-domain   301
   width  23: gaps   455  sets   117  in-domain   242
   width  24: gaps   221  sets    58  in-domain   169
   width  25: gaps   115  sets    30  in-domain    73
   width  27: gaps    20  sets     4  in-domain     6

-- by NUMBER OF ENABLING GATES the witness pins
    0 gates:   456 gaps
    1 gates:   634 gaps
    2 gates:   198 gaps
    3 gates:   156 gaps
    4 gates:   238 gaps
    5 gates:   540 gaps
    6 gates:   433 gaps
    7 gates:   381 gaps
    8 gates:   304 gaps
    9 gates:   127 gaps
   10 gates:   106 gaps
   11 gates:   200 gaps
   12 gates:   431 gaps
   13 gates:   650 gaps
   14 gates:   555 gaps
   15 gates:   294 gaps
   16 gates:    55 gaps
   17 gates:    18 gaps

```

The width profile is §76.1.2's shape confirmed on the checker's own witnesses:
**3 771 of the 5 776 gaps (65 %) sit at width 15-27**, and the 21-27 band that
§76.1.2 called "98.9 % of the remaining mass" carries 1 692 of them. The gate
column is the second half of the RUNBOOK's construction rule made concrete:
**5 320 of 5 776 witnesses pin at least one enabling gate, 2 003 pin twelve or
more**, over **1 162 distinct gate combinations** and 19 gate expressions. Those
outcomes are read off the checker's own foreclosure relation; **no Z3 call was
made to re-derive them.**

### §77.3 The in-domain question, answered properly — and the §16d twist

Taken naively, 5 664 of 5 776 witnesses look like they demand a value no run
ever took. That reading is WRONG, and the reason is §16d itself. With one query
per set the witness is produced by `model.eval(..., model_completion=True)`, so
**every** variable gets a value — including the ones the cube leaves free, which
get Z3's default (`''`, `0`, `False`). Seeding a default the corpus never
produces is exactly the out-of-domain foreclosure §72.1 measured, and here it
would have been the DOMINANT effect. Two corrections, both measured:

1. **A self-compare constrains nothing.** Five members of the render family are
   `(X != X)` on a photo row's `status_message_guid`; their negation is
   tautological. Counting `X` as constrained made 7 921 completion defaults on
   those five variables read as out-of-domain DEMANDS.
2. **Only the constrained part of the model is a demand.** 81 980 model values
   across the 5 776 witnesses; **68 327 of them are constrained**, the other
   13 653 are completion defaults.

With both applied:

```
  gaps whose every CONSTRAINED value is one the corpus HAS produced : 3 747 (64.9 %)
        (this is the table's "in-domain" column)
  gaps with >= 1 CONSTRAINED out-of-domain value                    : 2 029 (35.1 %)
        all of them substitutable — see §77.4(3)
  gaps with a CONSTRAINED variable no run has ever seeded           : 1 049 (18.2 %)
        exactly two variables: SYM_RESULT_Anonymous_process_2 / _3
  gaps clean on BOTH counts (in-domain and every variable seedable) : 3 545 (61.4 %)
```

The out-of-domain values are not exotic. They are six variables, and five are
Z3 inventing a string for a `!= ''`:

```
    836  SYM_RESULT_Anonymous_process_2                     model ''    (never observed)
    526  ..._as_api_response_1_row_guid       model '!0!' / 'A'  vs observed '..._guid_v', '', 'concolic_other'
    406  ..._as_api_response_4_row_guid       "
    381  ..._as_api_response_3_row_guid       "
    265  ..._as_api_response_2_row_guid       "
    262  SYM_PARAM_id     model 'ABCDEFGHIJKLMNOP'  vs observed 'gggggggggggggggg' (16 chars, satisfies the same Length())
```

`SYM_PARAM_id` is §72.1's example arriving again: the cube needs a 16-character
id, the corpus HAS one, and the solver invented a different one. §72.1's fix did
not catch it because the constraint is `Length(SYM_PARAM_id) < 16` and the fix
only resolved `==`/`!=` negations. §77.4(3) fixes that.

**The one honest residue in this classification is the render pair.**
`SYM_RESULT_Anonymous_process_2` and `_3` are the RENDERED post text; 1 049 gaps
demand an outcome of `(... == '')` and 978 of those demand the empty side.
Neither name has ever been a seed key in the corpus — they are **derived**, not
seedable dimensions. They are not a model ruling either: §46.9's W10 made the
post text emptyable and the cube already pins the `*_text_empty` members that
produce it, so the construction reaches them THROUGH the members it does seed.
The constructor states these 3 770 values instead of writing a key nothing
consumes; whether they land is what the drive measures.

### §77.4 THREE DEFECTS IN THE CONSTRUCTOR, found by measuring its own output

`_construct_by_gate.py` (§71.2, §72) is the script this batch has used since
2026-09-11. Measured against P14's witnesses and this corpus's own dumps, it
would have dropped most of what it was given, silently. All three are the same
shape: a CHECKER-side name looked up in a DUMP-side namespace, which the RUNBOOK
(Phase 2, `len` SPELLING) says fails as "no compatible base", never as an error.

1. **EVERY `SYM_LEN_*` VALUE WAS DROPPED.** The constructor resolved a model key
   through `canonicalize_ordinals`' map and the base's own `concolic_seeds`,
   both DUMP-side, where a length is spelled `len(X)`; the model spells it
   `SYM_LEN_X`. Verified on a snapshot dump: `SYM_LEN_..._records_2_rows` is in
   neither the alias map nor the seed dict, while `len(..._records_2_rows)` IS a
   seed key. On round OD0911's own input that silently discarded **4 720 of
   25 580 constructed values (18.5 %)**; on P14's witnesses it would discard
   **20 334 of 68 327 constrained values (29.8 %), over 31 variables** — and
   those are the LENGTH GATES, including the single most common foreclosing gate
   on this endpoint (`SYM_LEN_..._records_2_rows != 0`, 5 859 foreclosures).
2. **A SUFFIXED NAME NEVER RESOLVED EITHER.** `ords = inv.get(k) or ([k] if k in
   seeds else [])` looks `k` up as an EXACT alias-map canonical. Every decision
   variable on this endpoint is a canonical plus a suffix
   (`<canonical>_row_text_empty`), so `inv.get(k)` misses, and the fallback only
   fires when the base ALREADY carried a seed for that dimension. A dimension
   the base had never been seeded on could not be written at all. Measured: with
   the base's seed dict as the namespace, **80 242 of 132 884 values (60 %)**
   were unwritable; reversing the loader's rename instead brings that to
   **3 770, and to exactly the two derived render names**.
3. **OUT-OF-DOMAIN RESOLUTION ONLY COVERED `==`/`!=` NEGATIONS**, so
   `SYM_PARAM_id`'s `Length() < 16` kept the invented value (§72.1 listed it and
   the fix did not reach it).

**`_p15_construct.py` repairs all three and keeps §72's two rules.** The reverse
map is DERIVED, never guessed: every candidate seed key is pushed through the
same two transforms the checker's loader applies (`canonicalize_ordinals`, then
`len(X) -> SYM_LEN_X`) and must round-trip to the model's name. A substitute
value is accepted only if it SATISFIES every literal the cube puts on that
variable (`==`, `!=`, `Length(v) < n`), so a predicate-constrained variable is
resolved too and an unverifiable substitution is never made. Negatives are
written before positives (§72.2); `__prior` keys are unseeded (§72 — posts_show
mints none, the rule is carried anyway); and only the CONSTRAINED part of the
model is written, so a free variable keeps the base run's own value.

### §77.5 The constructed batch

```
_p15_construct.py   BASES_PER_GAP=2   132 s   406 distinct base runs

  seeds built                     11 552   (5 776 gaps x 2 bases)
  values written                 132 884   (mean 11.5 per seed)
  out-of-domain values SUBSTITUTED 4 214   by the most-observed value that
                                           SATISFIES the cube's literals
  values kept out-of-domain        1 138   all SYM_RESULT_Anonymous_process_2
  values not seedable              3 770   the two derived render names only
  base covers every alias canonical the cube is spelled with:  5 776 / 5 776
```

Bases are chosen by GATE MATCH and ALIAS-WALK, not by token overlap: first the
number of alias canonicals in the cube's names that the base's own run actually
minted (a name the base cannot spell as an ORDINAL is written under its
canonical and the runtime ignores it — an inert key, 46 % of seeds before this
became part of the choice), then gate outcomes walked minus gate outcomes
contradicted, then members of the set walked, then seed count.

```
  SET A (primary)  _p15_seeds_<variant>.json     5 776 seeds
       auth_html 875   anon_html 196   auth_json 3 934   anon_json 771
       every one on a base with FULL alias coverage — 0 inert keys
  SET B (backup)   _p15_seedsB_<variant>.json    5 776 seeds
       auth_html 917   anon_html 290   auth_json 1 356   anon_json 3 213
       a second base per gap; 4 862 carry one key their base cannot resolve
  manifest         _p15_manifest.json            gap -> seed file/index, base,
                                                 why (the four scores), counts
  gap census       _p15_gaps.json                5 776 entries with the cube,
                                                 the counterexample, the gates
```

**Gaps that could NOT be constructed: 0.** Every one of the 5 776 has a seed in
set A. What varies is confidence, and it is stated per seed rather than hidden:
1 049 gaps demand an outcome of a DERIVED render variable and are reached only
through the members that produce it; 2 029 needed a substituted value; and
3 676 of 5 776 sit on a base that does not already walk every enabling gate the
cube needs — which is not a defect but the definition of the problem, since the
gate combination is precisely what no run has walked and it is the SEED that
pins it.

`_p15_drive.sh` is ready for the coordinator and was **not run here**. It cages
every JRuby through `_cage.sh`'s `cage_drive` (4G per leg; each JRuby peaks
~1.2 GB, `DRIVE_PAR=2`), and it checkpoints AT THE DRIVER, BY SEED ID: a
pre-pass counts the artefact per (variant, chunk) — the dumps labelled
`_<TAG><vv><CCCC>r*` — writes `_chunk_drive.sh`'s `done_` marker itself when a
chunk is already complete, and records every skipped seed id in
`_p15_driven_seeds_<SET>.txt`. It ends on `P15-DRIVE-DONE` or
`P15-DRIVE-INCOMPLETE <n> seeds left`, and `caged_verdict` is applied per leg so
a leg that exits without its own END line is treated as killed, not done.
Expected duration from this batch's own measurement (round OD0911: 13 080 seeds
in 57.5 min end to end = 3.79 runs/s, DRIVE_PAR=2, CHUNK=200): **set A ~25 min,
set A + set B ~51 min.**

### §77.6 WHAT THIS CONTRADICTS IN §76

§76.2(a)/§76.5(a) concluded that the residual was "52 genuinely two-sided
decisions in five-family wide parts — needs a model ruling, not driving", and
§76.6 rested that on 99.75 % of the remaining mass living in leaf groups no run
has ever walked. **The premise was never tested against a working constructor.**
On this pass:

- **The tool that would have tested it was dropping 30 % of every cube it was
  handed, and 60 % once the suffix defect is counted** (§77.4). Every reachability
  number produced with it — including OD0911's 68 % UNEVALUATED, the measurement
  §71.2 named as "what bounds this method here" — was produced with the length
  gates and most decision variables silently unseeded. "No run produced this"
  was, in large part, "no seed was ever written for this".
- **The foreclosure layer is no longer provisional.** P14 has
  `tree_complete = true`, `tree_missing = []`, `foreclosures_provisional =
  false`. §76's reasoning ran on passes where it was provisional, i.e. where a
  foreclosure could still be hiding a gap.
- **Nothing in the 5 776 is unreachable by the rule's own standard.** §72.3
  already retracted the one "impossibility" gate as a mock domain, leaving
  posts_show with ZERO gates that constitute impossibility evidence. This pass
  adds that **0 of 5 776 gaps could not be constructed**, and that the only
  variables the corpus genuinely cannot seed are two DERIVED render outputs
  whose producing members the cubes already pin.
- **The "needs a value no run ever took" class is 6 variables wide and 5 of them
  are Z3 inventing a string** where the corpus holds a satisfying one. That is
  §72.1's defect, not a property of the program.

None of this makes the endpoint complete, and none of it retracts §76.4's scale
argument. It does retract the CLASSIFICATION: on the evidence available today
the residual is a DRIVING problem with a repaired constructor, and no model
ruling is owed until a constructed batch has been driven and classified per key.
§78 is where that verdict belongs.

### §77.7 Artefacts

```
_p15_index.py        corpus index + observed domain + alias-canonical masks
                     (32 305 dumps, 184 s, ~115 MB; pickle in the scratchpad)
_p15_classify.py     the classification above -> _p15_gaps.json
_p15_construct.py    the constructor -> _p15_seeds_*.json / _p15_seedsB_*.json
                     / _p15_manifest.json
_p15_drive.sh        READY, NOT RUN — caged, resumable by seed id, verdict line
_p15_gaps.json       5 776 gaps: set, width, gates, cube, counterexample,
                     out-of-domain and not-seedable flags
_p15_manifest.json   11 552 rows: gap -> seed file + index, base run, why
```

## §78. ROUND 1 OF THE P15 LOOP — THE CONSTRUCTED BATCH, DRIVEN (2026-09-12)

§77 built a batch and drove nothing. This is its verdict. The loop is the
RUNBOOK's Phase 2 loop and nothing else: **drive the constructed batch -> rerun
the checkpointed coverage pass -> construct from the new witnesses -> drive**.
Every number below is measured on the DUMPS, not inferred from a pass.

### §78.1 The drive

```
_p15_drive.sh, SEEDSET=A, DRIVE_PAR=2, CHUNK=200
  unit         posts-p15-drive-A.service (systemd --user, concolic-cov.slice,
               MemoryMax=9G; every JRuby leg caged at 4G by _cage.sh)
  start/end    09:06:28 -> 09:54:52 UTC          wall 48.4 min
  seeds        5 776 (one per P14 gap)           driven 5 776, 0 left
  dumps        183 351 -> 189 127                +5 776 (one per seed, exactly)
  toxic seeds  0        native aborts 0          legs 4/4 CAGED-OK
  verdict      P15-DRIVE-DONE P15A  +5776 dumps  0 seeds left
```

Rate 2.0 runs/s against the 3.8 runs/s §77.5 predicted from round OD0911; the
box was carrying notifications' `_c12` pass and posts_show's own P14-2 engine
section at the same time. Nothing was lost to it.

### §78.2 THE ROUND, EXPLAINED PER KEY — the RUNBOOK's actual requirement

`_p15_explain.py` (new). The key is NOT a seed-dict entry: a constructed seed is
the BASE's whole seed dict with the cube's constrained values overlaid, so most
of its keys are context. **The demand is the CUBE** — every literal of the gap's
`node_constraint`, with its polarity. Per literal, measured on the run's own
path conditions after the checker's own name join (alias canonicalization then
`len(X) -> SYM_LEN_X`, both directions):

* **honoured** — the run evaluated the expression and took the demanded side
* **contradicted** — it evaluated it and took the other side
* **never evaluated** — it never reached that decision

A gap is **WALKED** iff every literal is honoured; that is the leaf the checker
asked for, with no Z3 and no pass involved. Dump -> gap is joined by SEED-DICT
IDENTITY (blake2b over the sorted dict actually handed to `EXTRA_SEEDS_JSON`),
never by parsing the label's chunk index — the chunk worker restarts on the
remainder after an abort, so label order is not seed order. **5 776 / 5 776
dumps matched a seed and 0 matched none**, so nothing in this table is a
silent drop.

```
  dumps labelled *P15A*                                   5 776  (0 unparseable)
  gaps with at least one dump                     5 776 / 5 776
  gaps WALKED (every cube literal honoured)               1 780   30.8 %

  PER-KEY, over all 117 284 cube literals of all 5 776 gaps
     honoured          102 185   87.1 %
     contradicted        5 304    4.5 %
     never evaluated     9 795    8.4 %
```

**That is the number §77.6 said was untested.** Round OD0911, with the
constructor that dropped every `SYM_LEN_*` value and 60 % of decision
variables, measured **68 % UNEVALUATED**. With the repaired constructor the
same measurement on a bigger, deeper batch is **8.4 %**. "No run produced this"
was, as §77.6 suspected, very largely "no seed was ever written for this".

```
  PER-KEY BY DECISION FAMILY
  family                      honoured   contra     never   %hon
  length gate (rows)             26856      293      1495  93.8%
  text (empty)                   17778        0       318  98.2%
  guid                           11263        0      5546  67.0%
  text (has_mention)             11520        0      1244  90.3%
  find_by not_found              12583        0        12  99.9%
  guid self-compare              10525        0      1018  91.2%
  text (rendered)                 4865     5011       111  48.7%
  evilq not_found                 3539        0        30  99.2%
  findpublic not_found             841        0         6  99.3%
  public gate                      813        0         6  99.3%
  nsfw gate                        662        0         9  98.7%
  param id length                  636        0         0 100.0%
  length gate (ids)                304        0         0 100.0%
```

Read the two columns that are not ~0:

1. **`text (rendered)` carries 5 011 of the 5 304 contradictions (94.5 %).**
   These are `SYM_RESULT_Anonymous_process_2/_3` — §77.3's honest residue, the
   two DERIVED render variables that have never been a seed key in this corpus.
   The constructor states the value and reaches it only THROUGH the members
   that produce it. It landed 4 865 times and flipped 5 011 times: the
   producing members are seeded, but they do not determine the rendered text
   on their own. This is the one family where a seeded demand is being
   actively refused, and it is the one family that has no key to seed.
2. **`guid` carries 5 546 of the 9 795 never-evaluated (56.6 %).** These are
   `as_api_response_<n>_row_guid` at n = 1..4. Never evaluated means the run
   rendered fewer api rows than the cube's row index needs — a REACH problem
   in the row-count dimension, not a refusal.

`param id length` is 100 % honoured: §77.4(3)'s repair (a substitute must
SATISFY the cube's literals, so `Length(SYM_PARAM_id) < 16` resolves to the
corpus's own 16-character id rather than Z3's invented one) is confirmed on
636 keys with zero misses.

```
  FIRST FAILING LITERAL of each of the 3 996 gaps that did not walk
     never_evaluated  guid                    1794      contradicted  text (rendered)  882
     never_evaluated  text (has_mention)       709      contradicted  length gate      60
     never_evaluated  guid self-compare        307
     never_evaluated  length gate (rows)       118
     never_evaluated  text (empty)              94
     never_evaluated  text (rendered)           28
     never_evaluated  evilq not_found            4
```

### §78.3 SET B WAS NOT DRIVEN BLANKET — it was REFUTED, and then partly driven

§77.5 offered set B (a second base per gap, 5 776 more runs, ~48 min) as a
hedge. Before spending it, the hedge was MEASURED, with no drive at all: for
each of the 3 054 gaps whose first failure was *never evaluated*, does set B's
base RUN itself evaluate any of the expressions set A's run missed? (Eval masks
from `_p15_index.pkl`; no Z3, no JRuby.)

```
  B base identical to A base                      1 528   (an identical seed)
  B base evaluates >= 1 of the missed expressions   697
  B base evaluates NONE of them                     829
```

So the blanket set B's best conceivable yield is 697 closures for 5 776 runs =
**0.12 closed/run as an upper bound, and that bound assumes every one of the
697 closes**. The 697 were driven instead, as `SEEDSET=BS` (a third form added
to `_p15_drive.sh` so a constructed SUBSET can be driven without overwriting
either full set), 09:58:46 -> 10:17:09, +697 dumps, 0 toxic, verdict
`P15-DRIVE-DONE P15BS`.

```
  gaps WALKED                                         0 / 697
  honoured 4 704 (44.4 %)  contradicted 0  never evaluated 5 885 (55.6 %)
```

**Zero.** And the failure mode is the one §77.5 named in advance: 4 862 of set
B's 5 776 seeds carry a key their base cannot spell as an ordinal, so the key is
inert and the run walks somewhere else entirely — 55.6 % never evaluated against
set A's 8.4 % on the same gaps. Set B is not a hedge on this endpoint; it is a
worse base. **The blanket set B is retired, on evidence, and every one of the
697 now has two construction attempts explained per key.**

### §78.4 The corpus after round 1

```
  dumps on disk        183 351 -> 189 824   (+5 776 P15A, +697 P15BS)
  snapshot for the pass  _snapshot_p15_P15A.txt = _snapshot_pruned_OD0911.txt
                         (32 305) + the 5 776 P15A dumps = 38 081
  pruned (one dump per distinct OUTCOME PROFILE, exact for the §16b verdict)
                         38 081 -> 34 725 profiles   (_snapshot_pruned_P15A.txt)
```

**2 420 of the 5 776 new runs (42 %) have an outcome profile no run in this
corpus had.** Pruning `previous pruned + new` is exact and not an
approximation of pruning the whole 189 824-dump directory: the previous pruned
list already holds one dump per profile of the old corpus, so the profile SET
is identical and the read is 38 081 dumps instead of 189 824. The 697 P15BS
dumps are deliberately NOT in this pass's list — they landed after it was
built, and they fold into round 2.

### §78.5 ROUNDS 2-5, AND THE MEASURE THAT MAKES THEM COMPARABLE

The loop ran five times. Each round: construct from the previous pass's
CHECKPOINT witnesses (`_p15_rebuild.sh` = index -> classify -> construct),
drive (`_p15_drive.sh`), explain per key (`_p15_explain.py`), pass
(`_p15_pass.sh`, `SKIP_COMPLETION=1`, `MAX_MISSING_PER_CLIQUE=1`,
`COVERAGE_CHECKPOINT` on, cap 7G).

**`MAX_MISSING_PER_CLIQUE` was 4 on P14 and is 1 on every P15 pass.** §77.1
found P14 had run at the batch default; `coverage_report.py:203` reads
`int(os.environ.get("MAX_MISSING_PER_CLIQUE", "4"))` and P14's launch line does
not set it, while the engine default has been **1** since §16d. `_p15_pass.sh`
sets it explicitly. One witness per set is all the constructor consumes, and
the pass got cheaper as promised: 35 min (P14, cap 4, 32 305 profiles) ->
17 / 11 / 13 / 11 / 13 min.

**The tracked quantity is SETS WITH A GAP, read off the checkpoint** — the
summary's `missing[]` is cut at `MISSING_CAP = 4000` and the summary itself is
360-380 MB. It is also the only quantity that is comparable across rounds,
because **the demand universe is not fixed**: new runs co-evaluate decisions
no run had co-evaluated before, so maximal observed evaluation sets MERGE and
APPEAR. That is §16/the co-evaluation semantics working as designed, and it
means a round can close leaves while the headline count moves the other way.
So each round is booked four ways, not one.

```
  pass  demand   gap-  Δgap  closed  gone  surviv  new   runs  rate
        sets     sets        (clean) (set        (new         (Δ/run)
                             again)  merged      set)
                                     away)
  P14    1747    1564    —      —      —     —      —      —      —
  P15A   1079     815   -749     5   1373    186   629   6473  +0.116
  P15C   1071     775    -40    32    110    673   102    724  +0.055
  P15D    872     571   -204     4    233    538    33    748  +0.273
  P15E    864     560    -11     5     15    551     9    539  +0.020
  P15F    864     557     -3     3      0    557     0    530  +0.006
```

`newly broken` (a set that existed, was clean, and acquired a gap) is **0 in
every round** — the loop never un-covered anything.

**THE UNIVERSE HAS CONVERGED.** P15E -> P15F: `demand_sets` 864 -> 864, sets
GONE 0, sets NEW 0. The restructuring that dominated rounds 1-3 (1 373, then
110, then 233 sets merged away) has stopped, so from here "sets with a gap" is
a stable denominator and the remaining 557 are the same 557 the next round
would face.

**STOP RULE MET (RUNBOOK Phase 2: "stop a method that falls below ~0.05/run
for two rounds").** Round 4 = 0.020/run, round 5 = 0.006/run. The final pass is
`_cov_FINAL_P15F_20260912.json`:

```
COMPLETE=False;NODES=137;MISSING=526;BLOCKING=526;PCS=1387808
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
dumps_loaded=35783;dumps_unparseable=0
DEMAND_SETS=864;TREE_COMPLETE=True;TREE_MISSING=0;FORECLOSURES=4260
FORECL_IGNORED=0;FORECL_PROVISIONAL=False        peak RSS 3489 MB
```

`tree_complete` true, `tree_missing` empty, `foreclosures_provisional` false,
`solver_lost` 0, `unevaluable_exprs` [] — every §16b precondition still holds,
on a corpus of 192 365 dumps (35 783 distinct outcome profiles).

### §78.6 THE PER-KEY VERDICT, ROUND BY ROUND — and what it says about the method

```
  round  tag    gaps  WALKED   honoured  contradicted  never-evaluated
  1      P15A   5776   1780 30.8%   87.1%       4.5%          8.4%
  1b     P15BS   697      0  0.0%   44.4%       0.0%         55.6%
  2      P15C    724     81 11.2%   80.4%       5.1%         14.5%
  3      P15D    748     59  7.9%   78.2%       5.5%         16.3%
  4      P15E    539     22  4.1%   74.9%       7.1%         18.1%
  5      P15F    530      7  1.3%   77.5%       7.8%         14.7%
```

Every round: 100 % of seeds driven, 100 % of dumps joined to their seed by
seed-dict identity, 0 unmatched, 0 toxic seeds, 0 native aborts. The
constructor is not losing keys — it is running out of leaves it can reach.
Two defects were found and repaired BY MEASUREMENT during these rounds, and one
change was tried and REVERTED because the measurement refused it:

* **§78.6a — the stale parts file (repaired).** `_p15_classify.py` matched a
  witness to its demand set through `_parts_OD0911.json`, the OR-refined
  decomposition of the corpus of 2026-09-11. Once the universe was rebuilt,
  **354 of 815 witness cubes were contained in no part**, so `set = -1` and
  `_p15_construct.py`'s `setmask.get(-1, 0)` made the "members of the set the
  base already walks" score silently ZERO for 43 % of the batch — the same
  shape as §77.4's three defects. Repaired the same way: the part is
  SYNTHESISED from the record's own witnesses and the augmented file
  (`_p15_parts_eff_<TAG>.json`) is what the constructor reads. Verified first
  that the EXPR universe itself had not drifted: 0 of the 110 exprs in the new
  witnesses is absent from the old members, and `NODES` is 137 in every pass.
* **§78.6b — the unsteerable-literal term (added, kept SECOND).** A cube
  literal over a variable the corpus can never seed is whatever the BASE
  renders. It is now part of the group key and is scored. Measured to CARRY:
  on P15D, where the chosen base took the demanded render side the driven run
  honoured it **224 / 227 = 98.7 %**, and where it did not, the run
  contradicted it **201 / 201**.
* **§78.6c — promoting it to FIRST was tried in round 4 and REVERTED.** It
  bought nothing on the class it was for (render honoured 51.4 % -> 51.6 %)
  because §78.9's 201 gaps cannot be satisfied by any base, and it cost alias
  coverage: seeds carrying an inert key 525/1496 (35 %) -> 869/1078 (81 %),
  gaps walked 7.9 % -> 4.1 %, round rate 0.273 -> 0.020 per run. Reverting for
  round 5 put inert keys back to 309/1060 (29 %). **Alias coverage first is the
  measured optimum**; the round-4 ordering is recorded in the file as a
  refuted experiment, not deleted.

### §78.7 WHAT REMAINS: 526 witnesses over 557 sets, classified

```
   201  A  the cube demands the TWO RENDER ORDINALS DISAGREE   -> §78.9, OWNER
    24  B  exactly one render ordinal pinned (base choice only)
   187  C  guid + has_mention          }
    52  C  guid                        }  reach: the run does not evaluate the
    40  C  guid + text_empty           }  decision, so no seed can set it
    21  C  has_mention                 }
     1  C  text_empty                  }
   526     total
```

Class C (301 witnesses, 57 %) is the honest end of the DRIVING method as it
stands: `as_api_response_<n>_row_guid` is 55-69 % honoured across rounds and its
misses are all *never evaluated*, never *contradicted* — the run renders fewer
api rows than the cube's row index needs. It is seedable
(`SYM_LEN_..._as_api_response_<n>` and the row's own fields are both in the 495
seedable names) and both values are in the observed domain, so it is NOT residue
by any standard; it is a base/reach problem the current base-choice score does
not solve, and the rate rule says stop rather than keep spending 530 runs a
round on it. That is a measured stop, not a verdict about the program.

### §78.8 CLOSURE OF §77's OPEN QUESTIONS

* §77.3 said `SYM_RESULT_Anonymous_process_2/_3` are reached "THROUGH the
  members the cube pins" (`*_text_empty`). **That is false and is retracted:**
  of the 198 P15C gaps blocked ONLY by a render literal, **192 pin ZERO
  `*_text_empty` literals** — the producer is a FREE variable, so the seed
  leaves it at the base's value and the BASE decides the render side. §78.6b is
  what follows from that.
* §77.5's SET B is retired on evidence (§78.3).
* §77.6's claim that the residual was "a DRIVING problem with a repaired
  constructor" is **confirmed for 1 949 of the 5 776** (1 780 walked in round 1
  + 169 more over rounds 2-5) and, per §78.7, still unrefuted for class C. It is
  **refuted for class A**, which §78.9 hands to the owner.

### §78.9 THE ONE THING THAT NEEDS AN OWNER RULING, with its construction evidence

**201 of the 526 remaining witnesses (38 %) demand that two ordinals of ONE
CALL STATEMENT return different values.**

The two decisions are `(SYM_RESULT_Anonymous_process_2 == '')` and
`(SYM_RESULT_Anonymous_process_3 == '')`. From the dumps' own
`symbolic_call` events (`dump_anon_html0004_P15Eanhtanht0000r0.json`, and the
same in every run that has them):

```
  target   Anonymous.process                     (Diaspora::MessageRenderer::Processor.process)
  file     ruby_examples/dse-apps/apps/diaspora/lib/diaspora/message_renderer.rb
  lineno   264            <- IDENTICAL for _1, _2 and _3
  args     {"message": "<the post text>", "options": null, "block": null}
                         <- IDENTICAL for _1, _2 and _3 in the same run
  result   IDENTICAL for _1, _2 and _3 in the same run
```

They are the same statement, called more than once on the same input, and the
mock is a deterministic function of its arguments. The demand universe treats
them as two free decisions and therefore asks for all four combinations; two of
the four are a request for a pure function to disagree with itself.

**The corpus says the same thing, and never says otherwise.** Over the 35 563
profiles of the P15D snapshot:

```
  (_2=='' , _3=='')        runs
  (None, None)            31 316     neither decision evaluated
  (False, False)           2 415
  (True,  True)            1 830
  (False, None)                2
  (True,  False)               0     <- 142 gaps demand this
  (False, True)                0     <-  59 gaps demand this
```

4 245 co-evaluations, 0 disagreements. And in **274 / 274** sampled runs where
BOTH decisions are evaluated, the two calls received the **same arguments**;
across 1 500 sampled runs, `Anonymous.process @ 264` returns the same result
whenever the args are the same (811/811) and a different result only when the
args differ (433) — a regime in which the second decision is not evaluated at
all.

**Construction was tried, four times, and explained per key.** These gaps were
in every batch from P15A to P15F. Per key, on the driven runs: the render
literal is *never* "never evaluated" (3 of 428 in P15D) — it is evaluated and
**contradicted**, and it is contradicted exactly when the base disagrees with
the demand (201/201) and honoured when it agrees (224/227, 98.7 %). There is no
seed key for either variable — they are call RESULTS, absent from
`symbolic_vars` and from all 495 seedable checker names — so no seed can split
them, and base choice cannot either, because **no base exists**: 0 of 35 563
profiles carries a mixed pair.

**Why this is a MODELLING question and not an impossibility claim.** The batch's
assumption ledger already contains exactly this kind of identification —

```
  coverage_assumptions.ALIASES = [ AliasAssumption(
      result_pattern = 'SYM_RESULT_ActiveRecord__(?:Associations__CollectionProxy_records
                        |Relation_records|Relation_to_ary)_\d+',
      key = 'statement', k = 1,
      description = 'ordinal-named list reads identified by their statement') ]
```

— "the ordinal is a function of the path prefix; re-keyed by statement so ONE
FACT IS ONE VARIABLE". `Anonymous.process` is the same situation at
`message_renderer.rb:264` and is simply not in the pattern. A survey of a
400-dump sample found **17 of 19 multi-ordinal-at-one-statement families are
outside the alias assumption**, but they are NOT all the same case and must not
be swept together: `Photo.url @ 21-24`, `find_by @ 37/138/143`,
`SingularAssociation.find_target @ 1052/1069` and `Relation.records @ 71` all
return **different results for the same args** (the ordinal indexes a row or a
call in a loop), while `Anonymous.process @ 264`, `MessageRenderer.title @ 79`,
`Person.name @ 119` and `Calculations.sum @ 41` return the **same result for the
same args**. Only the second group is a candidate.

**What is being asked.** Three options, and this agent took none of them:

1. **Declare it.** Extend the alias assumption (or add one) so ordinals of
   `Anonymous.process` at `message_renderer.rb:264` that receive equal
   arguments are ONE variable. This removes the two impossible combinations
   from the demand universe and, by itself, retires 201 of the 526. It is an
   ASSUMPTION LEDGER entry, it changes this endpoint's demand universe, and
   Phase 4's directed probe must verify it — which is why it is the owner's,
   not this agent's. `coverage_assumptions.py` is also the file every other
   pass on this endpoint reads.
2. **Rule it a genuine two-sidedness and leave it open**, on the grounds that a
   run in which the two sites see different texts is conceivable even though no
   run has produced one while both comparisons are live. Then class A is
   declared unmodelled and posts_show closes with it stated.
3. **Change the mock** so the two sites are independently steerable. This is
   `concolic_targets.rb` / the shared target boundary — Rule T — so it voids
   every endpoint and forces a from-scratch regeneration. Not proportionate.

The evidence for (1) is what §78.9 lists; the evidence against is only that the
alias assumption's `key='statement'` was written for list reads and its probe
semantics would need to be checked for a call whose ordinals can legitimately
see different arguments in OTHER runs (433 of 1 500 sampled).

### §78.10 ARTEFACTS OF §78

```
_p15_pass.sh          the checkpointed coverage pass, argument-driven
                      (TAG, DRIVETAG, BASELIST) — P14 was not edited
_p15_rebuild.sh       index -> classify -> construct, one command
_p15_explain.py       the per-key verdict (honoured/contradicted/never
                      evaluated), joined by seed-dict identity
_p15_explain_P15{A,BS,C,D,E,F}.json      per-gap, per-round
_cov_FINAL_P15{A,C,D,E,F}_20260912.json  + _cov_p15{a,c,d,e,f}.ckpt.jsonl
_snapshot_pruned_P15{A,C,D,E,F}.txt      the pass list of each round
_p15_parts_eff_P15{A,C,D,E}.json         parts + the synthesised ones
_p15_seedsBS_*.json / _p15_manifest_BS.json   the refuted set-B subset
_p15_manifest_P15{Around1,Cround2,Dround3,Eround4}.json   archived per round
corpus 183 351 -> 192 365 dumps (+9 014 constructed runs, 0 toxic, 0 aborts)
```

**No extraction ran and no policy was extracted** (owner rule: closure only).
`_c7_audits.sh` and the engine section were not run by this agent;
`posts-p14-s23-20260912.service` was left untouched throughout.

## §79. THE RENDER-ORDINAL IDENTITY — DECLARED, PROBED, AND PRICED (2026-09-12)

§78.9 handed the owner one question and three options. This is option (1),
carried out: the identity is DECLARED, it is probed by construction, the
coverage layer is re-run on the SAME profile list so the delta is attributable
to the declaration and to nothing else, and one more construct→drive→pass round
measures what the reshuffled universe is worth.

### §79.1 THE DECLARATION, and why it is not an `AliasAssumption`

`coverage_assumptions.py`, added 2026-09-12 next to `ALIASES`, wired into
`build()` beside the overnight pins and reversible the same way
(`NO_RENDER_IDENTITY=1`):

```python
RENDER_IDENTITY = (SymbolicConstraintAssumption(
    z3_expr="SYM_RESULT_Anonymous_process_2 == SYM_RESULT_Anonymous_process_3",
    description=("Anonymous.process @ message_renderer.rb:264 — ordinals 2 and 3 are "
                 "ONE decision: one statement, one renderer instance, and a mock that "
                 "returns its own argument"),
    agent_notes=("192 365-dump census (_p16_render_scan{,2,3}.py, 2026-09-12): ...")),)
```

`[assumptions] declared=1129 INERT=757 OVERNIGHT_PINS=8 RENDER_IDENTITY=1`.

**§78.9's option (1) said "extend the alias assumption". MEASURED, THAT CANNOT
BE DONE WITHOUT EDITING `src/`, and this batch may not.** Two independent
blocks, both run rather than reasoned:

1. `concolic_engine.assumptions._alias_core` skips every symbolic result whose
   `symbolic_call` note is not a STATEMENT — `is_statement_note` is
   `/^(SELECT|INSERT|UPDATE|DELETE|WITH)/`, and the `AliasAssumption` docstring
   names "a render probe" as exactly the excluded case. This target's note is
   the prose `"Diaspora::MessageRenderer::Processor.process"`. Run on a real
   dump of this corpus,
   `AliasAssumption(result_pattern=r'SYM_RESULT_Anonymous_process_\d+',
   key='statement')` returns an **EMPTY alias map**: the declaration would be
   INERT, would retire nothing, and would put a false entry in the ledger.
2. The gate's derived alias test (`assumption_checker._test_alias`) intervenes
   on `len(<ordinal>_rows)` and replays at k+1 ROWS. There is no list and no
   length dimension here, and the canonical name would never enter
   `_ALIAS_INDEX` — its own answer would be "canonical name never produced by
   the CURRENT corpus".

So the identity is declared as the equality it actually is. Its only effect is
on demand sets that contain BOTH decisions: where a set contains one, the other
is a free variable in the query and no demand is lost. Verified against the
engine's own solver before the pass: the two agreeing assignments stay SAT, the
two disagreeing ones go UNSAT.

Ordinals 1 and 4 are deliberately NOT in it — see §79.2.

### §79.2 THE EVIDENCE, RE-MEASURED OVER THE WHOLE CORPUS

§78.9 rested on samples (274/274, 1 500 runs). `_p16_render_scan{,2,3}.py`
re-measure it over **all 192 365 dumps** (0 unparseable), because an ARGUMENT
difference is not part of an outcome profile and the pruned list could hide one.

```
  Anonymous.process calls, corpus-wide                        557 489
  distinct (file, lineno) they occur at                  message_renderer.rb:264   ONE
  determinism violations (same file/line/args, 2 results)           0
  distinct argument values the mock ever saw                        5
  runs that make BOTH call 2 and call 3                        117 715
      with IDENTICAL arguments                                 117 715   (100.0 %)
      with different arguments                                       0
  runs that DECIDE both  ((... == '') recorded for each)          6 303
      (False,False) 3 226   (True,True) 3 077
      (True,False)      0   (False,True)     0
  decisions ever recorded on ordinal 1 or 4                          0
  expression forms ever recorded over these variables      (X == '')  only
```

**The ordinals of this statement DO carry different messages** — this is not a
corpus in which the mock only ever sees one string. The per-run grouping
signature (which ordinals share an argument):

```
  1,2      43 313     1,2,3,4  34 896     1,2,3|4  22 708     1|2,3,4  20 894
  1        16 186     1,2,3    15 261     1,4|2,3  12 691     1|2,3|4   6 843
  1|2,3     4 422     1|2       1 750
```

Ordinal 1 stands alone in 33 909 runs and ordinal 4 in 42 242. **In every one
of the ten signatures, 2 and 3 are in the same group.** The split this
statement does produce falls at `1|` or `|4`, never at `2|3`. That is why the
declaration is exactly two ordinals wide: an equality over 1 or 4 would be
false, and — since neither is ever decided — inert as well.

The mechanism is in the source, not inferred: `message_renderer.rb:264` is the
private `MessageRenderer#process`, `Processor.process(@text, ...)`, which every
public renderer method funnels through with its own instance's `@text`; and the
mock (`targets.rb` W7) returns that argument itself
(`v = m.value; PcVisibleConcreteString.build(v.to_s, ...)`). Two ordinals
differ iff they sit on different renderer instances.

### §79.3 THE GATE — one NOT-TESTABLE and one PASS, and which is which

**(a) The shipped gate, on the new declaration alone** (`_p16_gate.sh`, the
`_tier2_gate3.sh` pattern: the shipped driver, a `--declared` file holding only
the class under test, `ACHK_CHECKPOINT` / `ACHK_RESULTS_JSONL` on,
`CONCOLIC_SLOTS=1`, caged 4G):

```
  == derived assumption tests: 1 declared ==
    [0 distinct probes needed for 1 assumptions]
    NOT-TESTABLE  SymbolicConstraintAssumption
        constraint not of the form VAR op INT:
        SYM_RESULT_Anonymous_process_2 == SYM_RESULT_Anonymous_process_3
  RESULT: 1 distinct tested — PASS 0, FAIL 0, ERROR 0, NOT-TESTABLE 1
```

That is a real verdict about the GATE, not about the claim: the derived test
for this kind seeds a violating INTEGER on the constrained dimension, and this
constraint relates two call RESULTS, neither of which is a seed dimension. It
launched no probe and it cost nothing. **A NOT-TESTABLE is not a PASS**, so the
claim was taken to a probe built for it.

**(b) The ACTIVE FALSIFICATION PROBE** (`_p16_probe_build.py` /
`_p16_probe_drive.sh` / `_p16_probe_explain.py`), in the shape the owner
required of the confinement gate on 2026-09-11 — "the gate must try to falsify
the claim by construction; a passive corpus scan is not that":

```
  target of the search  a run in which ordinals 2 and 3 receive DIFFERENT
                        messages while BOTH `== ''` comparisons are recorded
  bases                 58 — every one of the 29 (variant, grouping signature,
                        decided set) cells the 35 783-profile pruned corpus
                        shows, richest seed dict first, 2 per cell
  interventions         the axes that decide which text each renderer carries:
                        the full factorial over the base's `assoc_*` text axes,
                        a one-at-a-time flip of every other `*_text_empty` /
                        `*_text_has_mention` / `*_text` axis, and 4 random
                        pair-flips per base
  seeds / dumps         1 548 / 1 548   (0 toxic, 0 native aborts, 4/4 legs
                        CAGED-OK, 12 min, CONCOLIC_SLOTS=1, DRIVE_PAR=1)
  did the knobs take    939 DISTINCT OUTCOME PROFILES produced, and all ten
                        grouping signatures reproduced — not a dead knob
  runs that made both calls                     1 066
      ... with DIFFERENT messages                   0
  runs that DECIDED both                          226
      (True,True) 61   (False,False) 165
      ... that DISAGREE                             0
  VERDICT                                        PASS
```

**Zero splits constructed.** Combined with §79.2's exhaustive census the
declaration stands on the gate's own currency — replays, not a corpus scan —
while the shipped derived test remains NOT-TESTABLE and is recorded as such.
(`_p16_probe_explain.json` carries the per-run table.)

### §79.4 THE PASS, BEFORE AND AFTER — the same list, one changed line

`_p15_pass.sh P16 -` on `_snapshot_pruned_P16.txt`, which is a byte copy of
`_snapshot_pruned_P15F.txt`. The 1 548 probe dumps were deliberately kept OUT
of it, so the only difference between the two passes is the declaration.

```
 BEFORE  _cov_FINAL_P15F_20260912.json
   COMPLETE=False;NODES=137;MISSING=526;BLOCKING=526;PCS=1387808
   GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
   dumps_loaded=35783;dumps_unparseable=0
   DEMAND_SETS=864;TREE_COMPLETE=True;TREE_MISSING=0;FORECLOSURES=4260
   FORECL_IGNORED=0;FORECL_PROVISIONAL=False        peak RSS 3489 MB

 AFTER   _cov_FINAL_P16_20260912.json          wall 10 min 48 s
   COMPLETE=False;NODES=137;MISSING=349;BLOCKING=349;PCS=1387808
   GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
   dumps_loaded=35783;dumps_unparseable=0
   DEMAND_SETS=864;TREE_COMPLETE=True;TREE_MISSING=0;FORECLOSURES=4260
   FORECL_IGNORED=0;FORECL_PROVISIONAL=False        peak RSS 3485 MB
```

Every §16b precondition is unchanged — 137 nodes, 864 demand sets, 4 260
foreclosures, `tree_complete` true, `tree_missing` empty,
`foreclosures_provisional` false, `solver_lost` 0, `unevaluable_exprs` []. The
declaration moved one number.

**WITNESSES REMOVED: 177 (526 → 349). GAP-SETS: 557 → 381 (−176).** Read off
the two checkpoints, which is where the witnesses live:

```
  render literals in the witness        P15F        P16
    (2 True, 3 False)  DISAGREE          142          0
    (2 False, 3 True)  DISAGREE           59          0
    (2 True,  3 True)  agree               0         19
    (2 False, 3 False) agree               0          6
    (3 True) only                         12         12
    (3 False) only                        12         12
    no render literal                    332        332
    ----------------------------------------------------
    gap-sets                             557        381
```

All 201 disagreement demands are gone. **176 of their 201 sets are now CLEAN**;
the other 25 re-report a witness in which the two ordinals AGREE — those sets
had a second unobserved assignment, and it is blocked somewhere else in the
cube, not by the render pair. Nothing else moved: the 332 non-render witnesses
and the 24 one-ordinal witnesses are the same witnesses.

**THE 24 DO NOT FALL UNDER THE DECLARATION, and the reason is structural, not
a judgment call.** Checked on the checkpoint: in all 24 the demand set does not
contain the `_2` decision AT ALL (`has _2 expr: False`), so `_2` is a free
variable in those queries and the equality has nothing to bite on; both sides
of `(_3 == '')` stay satisfiable, as they should. They are §78.7's class B and
they remain a base/reach problem.

### §79.5 ONE MORE ROUND ON THE RESHUFFLED UNIVERSE — 0.023/run

The §78.5 stop rule had fired (0.020, then 0.006). A declaration changes the
universe, so the rate was re-measured once rather than assumed, with §78.10's
own continuation commands.

```
  _p15_rebuild.sh P16 P15Fround5    index -> classify -> construct   14 s
       349 gaps x K=2 = 698 seeds; 52 values substituted; 148 values not
       seedable over the two render names (98 seeds); 290 seeds carry an
       inert key
  _p15_drive.sh P16A 200            349 seeds -> 349 dumps, 0 toxic, 0 aborts,
       4/4 legs CAGED-OK, 5 min, DRIVE_PAR=2
  _p15_explain.py  P15_TAG=P16A     the per-key verdict
  _p15_pass.sh P17 P16A _baselist_P17.txt
       base = the P16 list + the 1 548 probe dumps; + 349 new
       37 680 -> 36 677 profiles
```

```
  PER KEY, over all 4 740 cube literals of the 349 driven gaps
     honoured           3 586   75.7 %
     contradicted           0    0.0 %      <- was 4.5 % (P15A) / 7.8 % (P15F)
     never evaluated    1 154   24.3 %
  gaps WALKED            29 / 349   8.3 %   <- was 4.1 % (P15E) / 1.3 % (P15F)
  text (rendered)        87 honoured, 0 contradicted, 3 never   96.7 %
```

**The one family that was actively refusing its demand has stopped.** In round
1 `text (rendered)` was 48.7 % honoured with 5 011 contradictions — 94.5 % of
every contradiction in the batch; here it is 96.7 % honoured and the whole
round records ZERO contradicted keys. That is the declaration doing exactly
what §78.6b predicted it would: the unsteerable literal is no longer demanded
against itself.

```
 _cov_FINAL_P17_20260912.json
   COMPLETE=False;NODES=137;MISSING=340;BLOCKING=340;PCS=1433803
   GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
   dumps_loaded=36677;dumps_unparseable=0
   DEMAND_SETS=872;TREE_COMPLETE=True;TREE_MISSING=0;FORECLOSURES=4236
   FORECL_IGNORED=0;FORECL_PROVISIONAL=False        peak RSS 3576 MB
```

Booked the four ways §78.5 requires, off the checkpoints:

```
  pass   demand   gap-   Δgap  closed  gone  surviv  new   runs   rate
         sets     sets         (clean) (set         (new
                               again)  merged       set)
                                       away)
  P15F     864     557     —      —      —     —      —      —      —
  P16      864     381   -176   176*     0    381     0      0    (declaration)
  P17      872     373     -8      4     12    365     8    349  +0.023
```

`* ` the 176 are sets that went gap→clean under the declaration, not under a
run. `newly broken` is 0 again.

**0.023 per run is the THIRD consecutive round under ~0.05, so the RUNBOOK
Phase 2 stop rule still holds and the driving method stays stopped.** The
declaration did not restart it; what it did was retire a class the method could
never have closed.

### §79.6 WHAT REMAINS — 340 witnesses over 373 gap-sets, per key

```
   336  C   no render literal — the reach problem, unchanged
             184   guid + guid self-compare + text (has_mention)
              72   guid + guid self-compare
              45   guid + guid self-compare + text (empty)
              22   text (has_mention)
               7   guid self-compare + text (has_mention)
               2   guid            2  guid + text (has_mention)
               2   guid self-compare + text (empty)
    23  B   exactly one render ordinal pinned — the set does not contain the
            other ordinal's decision, so the equality does not reach it
    14  A'  both render ordinals pinned and AGREEING — the class the
            declaration created: the render pair is satisfiable, the block is
            the rest of the cube (guid self-compare + has_mention)
   373      gap-sets   (340 witnesses after the checker's cross-set dedup)
```

Per key, from the round that drove them (`_p15_explain_P16A.json`), the FIRST
literal that failed:

```
   never_evaluated  guid                    165      contradicted  (any)   0
   never_evaluated  text (has_mention)      103
   never_evaluated  text (empty)             22
   never_evaluated  guid self-compare        20
   never_evaluated  length gate (rows)        8
   never_evaluated  text (rendered)           2
```

**Every remaining miss is NEVER EVALUATED, none is CONTRADICTED.** No seed is
being refused any more; the runs simply do not reach the decision — the api
collection renders fewer rows than the cube's row index needs (`guid`,
`guid self-compare`), or the mention/empty branch is not on the path. Both
values of every one of these variables are in the observed domain and every one
of them is seedable (§78.7), so this is a base/reach problem and not residue,
exactly as §78.7 stated it — and the rate rule says stop spending 350 runs a
round on it.

### §79.7 ARTEFACTS, AND TWO NOTES ON DISCIPLINE

```
coverage_assumptions.py            + RENDER_IDENTITY (NO_RENDER_IDENTITY=1
                                     withdraws it); backup
                                     _bak_coverage_assumptions_pre_render_identity_20260912.py
_p16_render_scan.py/.json          the 192 365-dump census (joint outcomes,
                                   argument equality, determinism)
_p16_render_scan2.py/.json         calls vs distinct arguments per run
_p16_render_scan3.py/.json         the grouping signature per run
_p16_declared.json / _p16_gate.sh / _p16_gate.log / _p16_probe_results.json
                                   the shipped gate on this class alone
_p16_probe_build.py                58 bases -> 1 548 falsification seeds
_p16_probe_drive.sh                the caged drive (P16P), verdict line
_p16_probe_explain.py/.json        the probe's verdict
_p16_remaining.py                  the per-key classification of a checkpoint
_cov_FINAL_P16_20260912.json + _cov_p16.ckpt.jsonl   the before/after pass
_cov_FINAL_P17_20260912.json + _cov_p17.ckpt.jsonl   the extra round
_snapshot_pruned_P16.txt (= P15F), _baselist_P17.txt, _snapshot_pruned_P17.txt
_p15_explain_P16A.json             the extra round's per-key verdict
corpus 192 365 -> 194 262 dumps (+1 548 probe, +349 constructed; 0 toxic)
```

* **`_p15_explain.py` calls `main()` at import time.** `_p16_remaining.py`
  imported it for its family table and thereby re-ran the P15A explanation
  against the CURRENT gaps/manifest, overwriting `_p15_explain_P15A.json` with
  a 6-of-349 stub. Caught, and repaired from the round-1 archives
  (`_p15_gaps_P15Around1.json` + `_p15_manifest_P15Around1.json` with its
  `seed_file` fields pointed at `_p15_seeds_P15Around1_*`): the restored file
  reproduces §78.2 exactly — 5 776/5 776 dumps matched, 1 780 walked,
  87.1 / 4.5 / 8.4. `_p16_remaining.py` now carries the table as a COPY and
  imports nothing.
* No extraction ran and no policy was extracted. `src/`, `targets.rb` and the
  shared boundary were not touched; `posts-p14-s23-20260912.service` (the P14
  engine section, 5 h in) was left alone throughout, and every job here ran in
  `concolic-cov.slice` under `_cage.sh` with the launch gate logged.

## §80. P18 — THE ROW-READ REACH LAYER: THE GOVERNING LIST LENGTH, MEASURED AND PINNED (2026-09-12)

§79.6 left 340 witnesses over 373 gap-sets in which **every** remaining miss is
NEVER EVALUATED and none is contradicted: guid 165, has_mention 103,
text_empty 22, guid self-compare 20, length gate 8, rendered 2. §79.6 called it
"a base/reach problem" and stopped on the rate rule. This section is that reach
problem diagnosed to the variable, and the constructor extended to fix it.

### §80.1 THE DIAGNOSIS — what actually governs a row read

The brief this round was handed said the members are ROW-INDEXED
(`..._row_3_guid` needing a list of ≥ 4 rows) and that the governing length is
the `as_api_response` list's own. **Both halves are wrong, and measuring them
is what found the real mechanism.**

1. `SYM_RESULT_ActsAsApi__Collection_as_api_response_<n>_row_<field>` — `<n>` is
   the ORDINAL OF THE CALL, not a row index. Four ordinals occur on this
   endpoint, at four sites: `post_presenter.rb:95` (`mentioned_people`),
   `:27` / `:28` (likes / reshares under `with_initial_interactions`) and
   `comment_presenter.rb:15` (a comment's `mentioned_people`).
2. `len(SYM_RESULT_..._as_api_response_<n>)` — the api result's own length —
   does NOT govern the read. Measured over 36 677 profiles: a `guid` PC is
   recorded on 239 api calls whose own length is 0, and skipped on 1 937 whose
   length is non-zero. No relation.

**What does govern it** is the length of the COLLECTION THE api CALL PROJECTS —
the `records` / `to_ary` call immediately preceding it in the run's own event
stream. And because `as_api_response_<n>` is ORDINAL-keyed (the batch's
`AliasAssumption` covers only the AR record readers), *which* collection that is
is a property of the RUN, not of the name:

```
  api ordinal  ->  collections that bind it (36 677 profiles)
  _1   mentions_c6ccf1bc · mentions_a0ff45d4 · mentions_a004215f · mentions_3491f3a6
  _2   mentions_66022a8b · mentions_3dbae3ee · photos_{9930492e,e035b5b3,8687d6e6,2c7fa358}
  _3   mentions_66022a8b · photos_{9930492e,e035b5b3,8687d6e6,2c7fa358}
  _4   mentions_3dbae3ee
```

Per (ordinal, field, binding) the requirement is exact and has ZERO exceptions
in the directions that matter:

```
  ord 1 guid      | all four mentions bindings     read|empty=     0   read|full= 16 492   -> MUST BE NON-EMPTY
  ord 3 guid      | mentions_66022a8b              read|empty=     0   read|full= 12 729   -> MUST BE NON-EMPTY
  ord 4 guid      | mentions_3dbae3ee              read|empty=     0   read|full= 10 314   -> MUST BE NON-EMPTY
  ord 2 guid      | mentions_3dbae3ee              read|empty=     0   read|full=  1 310   -> MUST BE NON-EMPTY
  ord 2 guid      | mentions_66022a8b              read|empty= 3 812   read|full= 10 999   -> either
  ord 1 has_ment  | all four mentions bindings     read|full =     0   skip|empty=      0   -> MUST BE EMPTY (and empty is sufficient)
  ord 4 has_ment  | mentions_3dbae3ee              read|full =     0   skip|empty=      0   -> MUST BE EMPTY
  ord 3 has_ment  | mentions_66022a8b              read|full =     0                        -> MUST BE EMPTY
  ord 2/3 *       | photos_*                       never read a guid at all                 -> that binding cannot host the member
```

So `guid` and `has_mention` on ONE api ordinal are complementary readings of the
same list: the guid path is the one the non-empty list takes and the
has-mention path is the fallback the empty list takes. Nothing in the 340
witnesses demands both on the same ordinal (checked: 0).

### §80.2 THE DISTRIBUTION — what the 340 need

```
  ROW-READ MEMBER SLOTS in the 340 witnesses
      696  as_api_response_<n>_row_guid
      470  <photos list>_row_status_message_guid      (the "self-compare" family)
      191  as_api_response_<n>_row_text_has_mention
       54  <list>_row_text_has_mention
       26  as_api_response_<n>_row_text_empty
        6  <list>_row_text_empty

  api slots by ordinal            guid   has_mention   text_empty
      ordinal 1                    221            69            7
      ordinal 2                    243            16            7
      ordinal 3                    136            97            8
      ordinal 4                     96             9            4

  records-list row reads, by list
      204  photos_33150e22   83  photos_e035b5b3   80  photos_2c7fa358
       72  photos_8687d6e6   66  photos_9930492e   22  records_2   1  comments_76960418

  REQUIRED GOVERNOR STATE, resolved through the chosen base's own binding
      480  the governing list must be NON-EMPTY (>= 1 row)
      197  the governing list must be EMPTY
      236  the binding imposes no requirement
        0  the base makes no such api call
```

**Needed length vs walked length.** Every governing length is a list the corpus
walks BOTH WAYS in quantity, so nothing here is out of domain:

```
  governing list                     profiles   >= 1 row   value distribution
  mentions_66022a8b                    54 252     42 636   0:11 616  1:30 091  2:6 091  4:6 454
  mentions_3dbae3ee                    33 836     23 796   0:10 040  1:15 527  2:4 205  4:4 064
  mentions_c6ccf1bc                    30 704     25 248   0: 5 456  1:17 094  2:4 081  4:4 073
  mentions_a0ff45d4                    21 648     14 474   0: 7 174  1:10 785  2:1 944  4:1 745
  mentions_a004215f                    12 644      9 415   0: 3 229  1: 4 951  2:2 164  4:2 300
  mentions_3491f3a6                     8 326      6 288   0: 2 038  1: 3 607  2:1 226  4:1 455
  photos_9930492e                      19 573     16 002   0: 3 571  1: 9 745  2:3 177  4:3 080
  photos_e035b5b3                      11 138      8 772   photos_8687d6e6 8 380/6 493
  photos_2c7fa358                       5 578      4 268
```

The needed value is therefore **>= 1** (most-observed satisfying value: 1) or
**0**, never a value the corpus has not produced. There is no "needs 4 rows"
class: the row read is a single row, and one row is enough.

### §80.3 WHY P15's CONSTRUCTOR COULD NOT REACH THEM — two defects, both measured

1. **THE GOVERNING LENGTH IS A FREE VARIABLE OF THE QUERY.** `_p15_construct.py`
   writes only the variables the cube CONSTRAINS (§77.4(2), correctly — under
   §16d a free variable's model value is Z3's default). The governing length is
   almost never constrained, so the seed left it at the base's value. Measured
   on the P16A round: **227 of the 320 failing gaps had a base that evaluated
   EVERY cube literal**, and the driven run still did not — the overlay itself
   moved the run off the decision.

2. **THE MANY-ORDINAL RULE ZEROED THE GOVERNOR THE CUBE ALSO NEEDED READ.** A
   canonical is backed by SEVERAL ordinals in one run — `mentions_66022a8b` in
   3 928 of 8 000 sampled runs — and `seedkeys()` writes the cube's value to
   EVERY ordinal backing it (correctly, as far as it goes). So a cube that
   demands `Not(SYM_LEN_mentions_66022a8b_rows != 0)` AND
   `(as_api_response_3_row_guid == '')` had every ordinal of that canonical set
   to 0, which is exactly the state in which the guid is never read.

   **That pair is NOT a foreclosure and the checker is right not to prune it.**
   Foreclosure needs "every run in which the gate took that outcome left the
   member unevaluated"; here a run with two ordinals behind one canonical
   evaluates the length decision BOTH ways, and 588 of the 1 535 sampled runs
   that take it false DO read api ordinal 3's guid. The demand is realisable —
   by a run in which one ordinal of the canonical is empty and another is not.

### §80.4 THE CONSTRUCTOR — `_p18_index.py` + `_p18_construct.py`

`_p15_construct.py` is not edited; `_p18_construct.py` is derived from it and
keeps every §72 rule verbatim — observed-domain values only, a substitute must
SATISFY the cube's literals, negatives before positives, `__prior` keys
UNSEEDED, both `len` spellings through the derived reverse map. It adds one
layer, in three parts, all of it MEASURED at the driver with nothing in `src/`
touched and nothing declared:

* **G1 — THE NECESSITY TABLE** (`_p18_index.necess`). For a demand-universe
  expression `e` and a length variable `L`: if no run in the 36 677-profile
  corpus ever evaluated `e` while `L` was empty, over at least 200 runs that had
  `L` empty, then `L != 0` is a measured precondition of `e`. Symmetrically for
  the empty side. 112 of 137 expressions carry at least one. This is §16b's
  foreclosure epistemics one value-level down. A length that appears on BOTH
  sides is DROPPED — that is the signature of a variable whose PRESENCE is
  anti-correlated with the expression (the four mutually-exclusive `tags_*`
  statements), not of a precondition — and a condition is applied only to a base
  that actually mints that length, which is the conditional it was measured as.
* **G2 — THE PER-BASE API BINDING** (`_p18_index.binds`, `bindstat`). The
  disjunctive case G1 cannot see, because no single mentions list is necessary
  for `as_api_response_1_row_guid` — four of them can bind ordinal 1. Once the
  base is fixed the binding is fixed and the requirement becomes one length.
  The index records the RAW ordinal as well as the canonical, which is what
  makes the pin seedable.
* **THE SPLIT PIN.** When the cube demands the CANONICAL be in the other state,
  the two are not in conflict: the cube's value goes to every ordinal backing
  the canonical EXCEPT the one that feeds the row read, which carries the
  required state. The run then evaluates the length decision both ways — which
  is what the corpus does — and both the cube's outcome and the row read are
  realised. Where there is no ordinal to split on (one ordinal only) the
  conflict is RECORDED and the cube's demand is never overwritten.

Base choice gains one term, **ranked SECOND, directly under alias coverage**
(§78.6c measured alias coverage first to be the optimum and that is not
disturbed): the governor compatibility of the base's own binding.

```
  _p18_rebuild.sh P17          index 426 s · classify 1 s · construct 38 s
  gaps 340 x K=2 = 680 seeds            308 (set, gates, unsteerable) groups
                                        151 distinct base runs
  values substituted                50  (30 of them SYM_PARAM_id)
  values not seedable              102  the two derived render names only
  governor lengths PINNED          486  (already right on the base: 516)
  SPLIT PINS                       792  (460 with an api ordinal, the rest necessity)
  pins the base cannot spell         0
  unresolved governor conflicts      0
  GAPS THAT COULD NOT BE CONSTRUCTED 0 / 340
```

### §80.5 ROUND 1 (P18A) — DRIVEN AND EXPLAINED PER KEY

```
  unit      posts-p18a-drive-20260912.service (concolic-cov.slice, MemoryMax=9G,
            every JRuby leg caged at 4G), DRIVE_PAR=2, CHUNK=200
  14:55:02 -> 15:10:02 UTC   wall 15.0 min
  seeds 340 driven 340, 0 left · dumps 194 262 -> 194 602 (+340, one per seed)
  toxic 0 · native aborts 0 · legs 4/4 CAGED-OK
  verdict   P15-DRIVE-DONE P18A  +340 dumps  0 seeds left

  PER KEY over all 4 900 cube literals of the 340 driven gaps
     honoured          3 950   80.6 %      (P16A: 75.7 %)
     contradicted        178    3.6 %      (P16A: 0 %)
     never evaluated     772   15.8 %      (P16A: 24.3 %)
  gaps WALKED            39 / 340  11.5 %  (P16A: 29/349 = 8.3 %)

  BY FAMILY                     honoured  contra   never   %hon      P16A %hon
     guid                           1399       0     519  72.9%        55.9%
     length gate (rows)             1135     178     101  80.3%        92.4%
     guid self-compare               597       0      53  91.8%        91.8%
     text (has_mention)              374       0      62  85.8%        56.0%
     find_by not_found               223       0       0 100.0%       100.0%
     text (rendered)                  42       0      17  71.2%        96.7%
     evilq not_found                  45       0       4  91.8%       100.0%
     text (empty)                     41       0       6  87.2%        59.3%
```

**The reach layer works on the family it was built for.** `guid` went from
55.9 % honoured to 72.9 % and `text (has_mention)` from 56.0 % to 85.8 % — the
two families that carried 268 of §79.6's 340 first-failures.

**And it has a measured cost, stated rather than hidden.** 178 keys are
CONTRADICTED, all of them `length gate (rows)` on a canonical the seed SPLIT,
and they are the first failure of 76 gaps. The mechanism is exactly the one the
split relies on: the run has to evaluate the length decision BOTH ways, and
when only the non-empty ordinal is reached the cube's empty outcome is refused.
Round 2 scores a base that already takes that expression both ways ABOVE one
that does not (`em & tm & fm` on the length expression, a new mask in the
index), which is the direct counter-measure.

### §80.6 THE ROUND-1 PASS (P18) — AND THE CONVERGENCE CLAIM OF §78.5 IS RETRACTED

```
 _p15_pass.sh P18 P18A _snapshot_pruned_P17.txt   (cap 9G, ALONE_OVERRIDE=1)
   snapshot 36 677 + 340 = 37 017 -> 36 843 distinct outcome profiles
   (166 of the 340 new runs, 49 %, have a profile no run in this corpus had)
   checker wall 9 min 14 s   peak RSS 3 597 MB

 _cov_FINAL_P18_20260912.json
   COMPLETE=False;NODES=137;MISSING=497;BLOCKING=497;PCS=1442804
   GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
   dumps_loaded=36843;dumps_unparseable=0
   DEMAND_SETS=1029;TREE_COMPLETE=True;TREE_MISSING=0;FORECLOSURES=6141
   FORECL_IGNORED=0;FORECL_PROVISIONAL=False        peak RSS 3597 MB
```

Every §16b precondition still holds — 137 nodes, `tree_complete` true,
`tree_missing` empty, `foreclosures_provisional` false, `solver_lost` 0,
`unevaluable_exprs` [].

Booked the four ways §78.5 requires, off the two checkpoints:

```
  pass   demand   gap-   Δgap  closed  gone  surviv  new   runs   rate
         sets     sets         (clean) (merged)      (new set)
  P17      872     373     —      —      —     —      —      —      —
  P18     1029     532   +159      3     32    338    194    340  -0.468
```

`newly broken` is **0** — nothing was un-covered. What happened instead is the
thing §78.5 said had stopped happening: **the demand universe GREW, by 157
demand sets and 194 gap-sets.** §78.5 concluded "THE UNIVERSE HAS CONVERGED"
from P15E -> P15F (864 -> 864 sets, 0 gone, 0 new). **That conclusion is
retracted here, and the reason is the reach layer itself.** A split-pinned run
evaluates a length decision BOTH ways in one execution — a path shape the
corpus did not previously contain — so decisions that no run had ever
CO-EVALUATED are now co-evaluated, and §16's maximal observed evaluation sets
grow. That is demand working as designed (§16, "a new run can ADD demand"), not
a regression, and it is the price of the only mechanism that reaches these
leaves at all.

On the OLD denominator the round paid: 35 of the 373 gap-sets P17 reported are
resolved (3 clean again, 32 merged into a superset), i.e. **0.103 per run**.
On §78.5's headline measure it is **-0.468 per run**, because 194 sets that did
not exist before now report a gap.

### §80.7 ROUND 2 (P18B)

```
  _p18_rebuild.sh P18 P18Around1     index 130 s · classify 1 s · construct 45 s
  497 gaps x K=2 = 994 seeds · 452 groups · 201 distinct base runs
  values substituted 52 (44 SYM_PARAM_id) · not seedable 90 (the two render names)
  governor lengths PINNED  830 (already right on the base 663)
  SPLIT PINS               974   pins the base cannot spell 0
  unresolved governor conflicts 0        gaps not constructible 0 / 497
  (base choice now scores a base that takes the split length expression BOTH
   ways above one that does not — the round-1 counter-measure)
```

```
  unit      posts-p18b-drive-20260912.service, DRIVE_PAR=2, CHUNK=200
  15:29:05 -> 15:33:20 UTC   wall 4.3 min
  seeds 497 driven 497, 0 left · dumps 194 602 -> 195 099 (+497)
  toxic 0 · native aborts 0 · legs 4/4 CAGED-OK
  verdict   P15-DRIVE-DONE P18B  +497 dumps  0 seeds left

  PER KEY over all 7 226 cube literals of the 497 driven gaps
     honoured          5 957   82.4 %
     contradicted        148    2.0 %      (round 1: 3.6 %)
     never evaluated   1 121   15.5 %
  gaps WALKED           102 / 497  20.5 %  (round 1: 11.5 %, P16A: 8.3 %)

  BY FAMILY                     honoured  contra   never   %hon
     guid                           2203       0     500  81.5%   (r1 72.9%, P16A 55.9%)
     length gate (rows)             1690     148     186  83.5%
     guid self-compare               926       0     103  90.0%
     text (has_mention)              382       0      62  86.0%
     find_by not_found               430       0       0 100.0%
     text (empty)                    149       0     237  38.6%   <- NEW, see below
```

The round-1 counter-measure held: contradicted length-gate keys fell from
178/1 313 (13.5 %) to 148/2 024 (7.3 %) and the walk rate nearly doubled again.
`guid` is now 81.5 % honoured against 55.9 % before the reach layer existed.
One family moved the other way — `text (empty)` at 38.6 %, 129 first-failures —
and it is the complement effect stated in §80.1 arriving on a new set of
witnesses: the empty-text read is the branch an EMPTY governing list takes, and
the round's pins are predominantly non-empty.

### §80.8 ROUND 3 (P18C)

```
  _p18_rebuild.sh P19 P18Bround2   318 gaps x K=2 = 636 seeds · 201 base runs
  governor pins 488 · split pins 646 · unresolved conflicts 0 · not constructible 0
  drive  posts-p18c-drive-20260912.service   15:53 -> 15:56:29   +318 dumps, 0 toxic

  PER KEY over 4 195 cube literals
     honoured          3 304   78.8 %
     contradicted         94    2.2 %
     never evaluated     797   19.0 %
  gaps WALKED            60 / 318  18.9 %
```

### §80.9 ROUND 4 (P18D)

```
  _p18_rebuild.sh P20 P18Cround3   298 gaps x K=2 = 596 seeds
  governor pins 441 · split pins 599 · unresolved conflicts 0 · not constructible 0
  drive  posts-p18d-drive-20260912.service   16:17 -> 16:21:18   +298 dumps, 0 toxic

  PER KEY over 4 195 cube literals
     honoured          3 246   77.4 %
     contradicted         98    2.3 %
     never evaluated     851   20.3 %
  gaps WALKED            31 / 298  10.4 %
```

### §80.10 THE DEFECT ROUND 4 EXPOSED — the requirement is exact on the RAW
### ORDINAL, and "EITHER" only on the alias canonical

Round 4's residue was classified by the CONSTRUCTION EVIDENCE rather than by the
symptom (`_p18_classify_remaining.py`, 267 gaps that did not walk):

```
   120  C5  no measured requirement on that binding — reach NOT explained by the layer
    41  C4  governor pinned to the required state, still not reached
    38  D1  a SPLIT length came out one-sided (only the non-empty ordinal reached)
    25  E2  a records-list row read, list not emptied by the cube
    21  E3  (assoc_status_message_text_has_mention == True)
    22  E3  other (evilq / findpublic / render / a mentions length)
```

C5 and 30 of C4 are ONE thing, and it is a defect in the P18 layer itself.
`bindstat` was keyed by the ALIAS CANONICAL, and an alias canonical collapses
several `records` statements whose lengths differ inside one run — so
`SYM_LEN_<canonical>_rows` is not a function of the single collection the api
call projects and the test returns EITHER where the truth is exact. Conditioned
on the RAW ORDINAL's own length, on the P21 corpus:

```
  ord 2 bound to canonical mentions_66022a8b, by the RAW ordinal's own length
      raw length != 0 -> guid read   2 019 / 2 019
      raw length == 0 -> guid read       0 /   435

  AND GLOBALLY, over every api ordinal and binding (36 843 profiles)
      ord 1 guid   read|empty=0  read|full=16 865      ord 3 guid  read|empty=0  read|full=13 036
      ord 2 guid   read|empty=0  read|full=16 344      ord 4 guid  read|empty=0  read|full=10 467
      ord 1/2/4 text_has_mention  read|full=0 AND skip|empty=0   (the exact complement)
```

**A `_row_guid` is read if and only if the collection the api call projects is
non-empty. Zero exceptions in 56 712 api calls.** The rule needed no canonical
at all. `_p18_index.py` now records `bindstat_raw` keyed by (ordinal, field) on
the raw governor length, `bind_req` consults it when the canonical is not
decisive, and the pin lands on the raw ordinal the split machinery already
writes. Effect on the very next build: **"api binding with no measured
requirement" fell from 403 to 22.**

### §80.11 ROUND 5 (P18E) — the repaired layer, and the STOP

```
  _p18_rebuild.sh P21 P18Dround4   290 gaps x K=2 = 580 seeds
  governor pins 465 · SPLIT PINS 1 516 · unresolved conflicts 0 · not constructible 0
  "api binding with no measured requirement"  403 -> 22
  drive  posts-p18e-drive-20260912.service  16:45 -> 16:49:13  +290 dumps, 0 toxic

  PER KEY over 3 826 cube literals
     honoured          3 183   83.2 %
     contradicted        201    5.3 %
     never evaluated     442   11.6 %
  gaps WALKED            95 / 290  32.8 %

  guid                   1407 honoured,   0 contra, 132 never   91.4 %
        (P16A 55.9 % -> r1 72.9 % -> r2 81.5 % -> r4 67.0 % -> r5 91.4 %)
  length gate (rows)      791 honoured, 201 contra, 143 never   69.7 %
```

```
 _cov_FINAL_P22_20260912.json          checker wall 6 min 59 s
   COMPLETE=False;NODES=137;MISSING=283;BLOCKING=283;PCS=1471704
   GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
   dumps_loaded=37366;dumps_unparseable=0
   DEMAND_SETS=853;TREE_COMPLETE=True;TREE_MISSING=0;FORECLOSURES=4184
   FORECL_IGNORED=0;FORECL_PROVISIONAL=False        peak RSS 3654 MB
```

### §80.12 THE ROUNDS, BOOKED THE FOUR WAYS §78.5 REQUIRES

```
  pass  drive  demand  gap-  Δgap  closed  gone  surviv  new  newly  runs  walked  rate
                sets   sets        (clean)(merged)          broken           %
  P17     —      872    373    —      —      —     —     —     —      —      —      —
  P18   P18A    1029    532  +159      3     32   338   194     0    340  11.5%  -0.468
  P19   P18B     853    352  -180      6    193   333    19     0    497  20.5%  +0.362
  P20   P18C     853    342   -10     10      0   342     0     0    318  18.9%  +0.031
  P21   P18D     853    336    -6      6      0   336     0     0    298  10.4%  +0.020
  P22   P18E     853    332    -4      5      0   331     1     0    290  32.8%  +0.014
                                                                    ----
                                                                    1 743 runs
```

`newly broken` is **0 in every round** — nothing was ever un-covered. Corpus
194 262 -> 196 005 dumps (+1 743 constructed runs, 0 toxic, 0 native aborts,
every leg CAGED-OK, every drive with its verdict line).

**STOP RULE MET: 0.031, 0.020, 0.014 — three consecutive rounds under 0.05.**
Rounds 4 and 5 both changed the constructor, so the counter was restarted after
each change and the rule is met on the CURRENT method, not on an older one.

**And the reason the rate is low is NOT reach any more, which is the finding
that matters for whoever picks this up.** Round 5 walked 95 of the 290 demanded
leaves — a third — and only **5** of their sets went clean. With
`MAX_MISSING_PER_CLIQUE=1` the checker reports ONE witness per set, so a round
can close at most one leaf per set, and a set that holds several missing leaves
simply reports the next one. The binding constraint has moved from "the run
cannot reach the decision" (P17: 100 % of misses never-evaluated, guid 55.9 %
honoured) to "each set holds more leaves than one round can spend" (P22: guid
91.4 % honoured, 32.8 % of leaves walked). That is the batch-at-the-driver
lever DISCIPLINE names — take EVERY remaining cube from the exact enumerator
rather than one witness per set — and it is a driver change, not a model one.

### §80.13 WHAT REMAINS — 283 witnesses over 332 gap-sets, per key, WITH THE
### CONSTRUCTION EVIDENCE (nothing is declared here; this is a report)

By render class (the §78.7/§79.6 taxonomy, unchanged):

```
   315  C   no render literal
    11  B   exactly one render ordinal pinned (the set does not contain the other
            ordinal's decision, so RENDER_IDENTITY has nothing to bite on)
     6  A'  both render ordinals pinned and AGREEING
   332      gap-sets   (283 witnesses after the checker's cross-set dedup)
```

By the FIRST FAILING LITERAL of the last round that drove them, joined to the
reach layer's own evidence (`_p18_classify_remaining.py` on the 195 P18E gaps
that did not walk):

```
   102  D1  A SPLIT LENGTH CAME OUT ONE-SIDED. The cube demands a canonical be
            EMPTY and a row of it (or of the api call it feeds) be READ; the
            seed put the feeding ordinal non-empty and every other ordinal
            empty; the run then evaluated the length decision only the
            non-empty way, so the cube's empty outcome is CONTRADICTED.
            Evidence, per canonical, on whether the corpus can do it at all:
               mentions_66022a8b 31 gaps   7 253 profiles take it BOTH ways
               mentions_3491f3a6 14        1 071
               mentions_a0ff45d4 11        3 652
               mentions_c6ccf1bc 11        3 989
               mentions_a004215f  5        2 241
               mentions_3dbae3ee  4        5 498
               comments_43acf058  9  ->        0 profiles, ever
               comments_76960418  8  ->        0
               comments_9b88e117  5  ->        0
               comments_5e3d4b43  4  ->        0
            76 of the 102 sat on a base that DOES take the expression both ways
            in its own run, and the seed still lost it: zeroing the other
            ordinals removes the second evaluation, because an empty list's
            length decision is only recorded when that list is reached.
            WHAT IT NEEDS: a driver change — make "the base takes this length
            expression both ways" a HARD FILTER for a split gap rather than one
            term of the base score, and pin the OTHER ordinal's enabling gates
            so its length decision is still reached when it is set to 0. For
            the 26 comments-family gaps it needs something else first: NO run
            in 37 366 profiles has ever taken a comments length both ways, so
            for those the split is not available and the pair (comments list
            empty, a row of it read) is a candidate for a §16b-style inference
            the checker does not currently make. It is NOT a foreclosure by the
            checker's own rule — the ordinals differ — and it is NOT declarable
            as independence. Stating it needs a Rule-T-free `src/` inference
            over ORDINAL-level, not canonical-level, length decisions, and that
            is an owner call.
    30  E2  a records-list row read (`<photos list>_row_status_message_guid`)
            whose own list the cube does NOT empty, still never evaluated. The
            necessity table has no length precondition for these beyond the
            ones already pinned. This is the residue the P18 layer does not
            explain; it needs its own differential, not a declaration.
    21  E3  `(assoc_status_message_text_has_mention == True)` never evaluated —
            an assoc-root decision, outside the row-read layer entirely.
    17  E3  a mentions/photos LENGTH decision itself never evaluated (the list
            statement was not issued on that path).
    11  C5  an api row read with no measured requirement on that binding even
            after the raw-ordinal repair (down from 120).
     4  C4  governor pinned to the required state, still not reached
            (all four: ord 2 guid on mentions_3dbae3ee).
    10  E3  evilq / findpublic / render singletons.
```

**Per key, what each class needs — stated, not decided:**

| class | n | what it needs |
|---|---|---|
| D1, mentions family | 76 | a DRIVER change: both-ways as a hard base filter + pinning the zeroed ordinal's enabling gates. No declaration, no `src/` change. The corpus proves the shape exists (1 071–7 253 profiles per canonical). |
| D1, comments family | 26 | an OWNER call. Zero profiles in 37 366 have ever taken a comments length both ways, so the demand "comments list empty AND a row of it read" has no constructible witness on this corpus. It is not a foreclosure under §16b (the two ordinals are different decisions), so closing it needs either a `src/` inference at ORDINAL rather than CANONICAL granularity, or a declaration with a falsifier of the shape §79.3(b) used for the render identity. |
| E2 / E3 (68) | 68 | more diagnosis, not a ruling. These are outside the length layer and no evidence yet says they are unreachable. |
| B (11) and A' (6) | 17 | unchanged from §79.6 — the render pair is satisfiable and the block is elsewhere in the cube. |

**Nothing here is residue by the corpus's own standard**: `tree_complete` is
true, `tree_missing` is empty, `foreclosures_provisional` is false,
`solver_lost` is 0, and every value every remaining cube constrains is in the
observed domain. 283 of 283 witnesses were CONSTRUCTIBLE in the last build,
0 could not be.

### §80.14 ARTEFACTS OF §80

```
_p18_index.py            corpus index + length-state masks (l0/l1) + both-ways
                         mask (fm) + the api binding (canonical AND raw ordinal)
                         + `bindstat` / `bindstat_raw` + the NECESSITY TABLE
_p18_construct.py        _p15_construct.py + the governor pins, the split pin,
                         the raw-ordinal requirement, the governor score
_p18_rebuild.sh          index -> classify -> construct, one command (SKIP_INDEX=1
                         reuses the pickle)
_p18_diag.py/.json       the diagnosis of §80.1 (sampled)
_p18_diag2.py            the §80.2 distribution on the full index
_p18_book.py             a round booked the four ways §78.5 requires
_p18_classify_remaining.py   the §80.13 classification by CONSTRUCTION EVIDENCE
_p18_round.sh            explain + pass, one command
_p15_pass.sh             one line changed: the pass cap is `${PASS_CAP:-7G}`
_p15_explain_P18{A,B,C,D,E}.json     the per-key verdict of each round
_cov_FINAL_P{18,19,20,21,22}_20260912.json + _cov_p{18..22}.ckpt.jsonl
_snapshot_pruned_P{18..22}.txt
corpus 194 262 -> 196 005 dumps (+1 743 constructed runs, 0 toxic, 0 aborts)
```

* **`_p15_classify.py` calls `main()` at import time too.** §79.7 recorded this
  for `_p15_explain.py`; the same trap fired again here when a diagnostic
  imported `slice_key` from `_p15_classify.py` and thereby re-ran the P14
  classification over `_p15_gaps.json`. Caught immediately and repaired by
  re-running the classifier on the P16 checkpoint (349 witnesses restored,
  archived as `_p15_gaps_P16round6.json`); no round used the corrupted file.
  Do not import either module — copy what you need, as `_p16_remaining.py` does.
* No extraction ran and no policy was extracted. `src/`, `targets.rb`,
  `coverage_assumptions.py` and the shared boundary were NOT touched, nothing
  under `notifications_index/` was touched, and no declaration was made.
  `posts-p14-s23-20260912.service` and `notif-c12-s23-queued-20260912.service`
  were left alone and both finished on their own (`Result=success`,
  `ExecMainStatus=0`).

## §81. P23 — THE EXACT ENUMERATOR'S OWN NUMBER, AND WHAT DRIVER-LEVEL BATCHING CAN AND CANNOT DO (2026-09-12)

§80.12 ended on a diagnosis: the binding constraint had moved off REACH and onto
the checker's `MAX_MISSING_PER_CLIQUE=1`, so a round could close at most one
leaf per demand set however well it was constructed, and the named remedy was
DISCIPLINE's driver-level batching — "take EVERY remaining cube from the exact
enumerator rather than one witness per set". §81 executes that instruction
literally, and the first thing it produces is the number that instruction was
written without: **how many remaining cubes there actually are.**

### §81.1 THE ENUMERATION — the whole demand universe, exactly, on the P22 corpus

`_p23_enum.py` (a streamed copy of `_exact_enum_emit.py`, see §81.6) over
`_snapshot_pruned_P22.txt`, 37 366 profiles, the batch's own
`coverage_assumptions.py`, foreclosure ON, cage 4G:

```
  nodes 137     evaluation sets 148 -> demand sets 1 729
  tree_missing=0   tree_complete=True   foreclosures 439 over 34 gates
  bounded_cliques 0                     <- EXACT, not a bound
  satisfiable        85 629 775 157 048
  covered                      208 770
  REMAINING          85 629 774 948 278      (8.56e13)
  REACHABLE remaining 75 288 454 199 350     87.92 %  (a run has walked these
                                              decisions under these gates)
  MULTI-GATE-FORECLOSED 10 341 320 748 928   12.08 %
  leaf groups 14 602   (8 845 with an observed compatible walk, 5 757 with none)
  wall 670 s   peak < 4 GB
```

**The 1 729 cliques are the checker's 853 demand sets before digest dedup**
(`_cov_p22.ckpt.jsonl` holds 853 records, 853 distinct keys, 332 with combos) —
the two tools agree on the universe; they disagree only on what they REPORT.

### §81.2 WHAT "EVERY REMAINING CUBE" IS, MEASURED

The enumerator's emitted object is not a leaf assignment. It is a piece of the
DISJOINT COVER of what no run has observed inside a leaf group — a partial cube
whose free members the base supplies. That is the tractable granularity, and it
was counted UNCAPPED for every set (`region_pieces`, added for this round):

```
  REGION PIECES over the 1 729 sets       847 327     (+58 956 zero-mass pieces)
  per set   min 19   median 289   mean 491.5   max 4 586
  sets with remaining > 0                   1 724 / 1 729
  set-width histogram          40x180 41x175 42x166 39x158 38x116 43x108 ...
  sets of width >= 13                       1 722, holding 85 629 774 946 286
                                            of the 85 629 774 948 278 remaining
  sets of width <= 13                           6, holding         11 144
```

```
  width  sets      remaining      pieces        width  sets     remaining   pieces
     12     2           1 992        439           37    85     9.374e+11   54 966
     13     4           9 152      1 266           38   116     2.808e+12   78 982
     16    10       1.093e+05      2 152           39   158     5.153e+12  115 068
     20    12       9.215e+05      2 882           40   180     9.641e+12  127 925
     24    79       9.594e+07     36 252           41   175     1.309e+13  108 462
     26    91        2.32e+08     43 572           42   166     1.524e+13   94 380
     32    33       1.723e+09      6 907           43   108     1.884e+13   46 795
     35    20       4.724e+10      6 552           44    61     9.121e+12   26 172
     36    44       2.034e+11     19 464           45    28     1.053e+13    7 079
```

**This is the finding of the round, and it is a measurement, not an opinion.**
The endpoint's demand universe is ~1 729 sets whose MODE WIDTH IS 40. A width-40
set has ~1e12 satisfiable assignments; covering one costs one run. "Take every
remaining cube and drive them as one batch" is therefore not executable at
posts_show at ANY batch size: 8.56e13 assignments, 847 327 disjoint pieces, and
a run covers exactly one assignment. §80.12's lever is real — it is what closed
notifications at 1.16/run — but it was sized against `MISSING=283`, and 283 is
what `MAX_MISSING_PER_CLIQUE=1` PRINTS, not what is left.

**`_cov_FINAL_P22` says so itself and has said so all along: `TRUNCATED=True`.**
DISCIPLINE §16b already states the rule this confirms — "the reported missing
list is a LOWER bound on the remaining work at every intermediate state, and
only the completeness verdict is a claim". §81 puts the upper bound next to it
for the first time on this endpoint: the lower bound is 283, the exact figure is
8.56e13, and the ratio is why five rounds of P18 moved the gap-set count by 4-10
per round while walking a third of what they aimed at.

### §81.3 THE CONSTRUCTOR — the D1 remedy, built and MEASURED

`_p23_construct.py` = `_p18_construct.py` + the three things §80.13 named,
`_p23_index.py` = `_p18_index.py` + the table the second of them needs:

* **(a) BOTH-WAYS AS A HARD BASE FILTER (D1).** P18 scored "this base takes the
  to-be-split length expression both ways" as ONE of six ranked terms, and
  round 5 measured what that cost: 201 of 3 826 keys CONTRADICTED, 102 gaps
  first-failing on it, **76 of them on a base that DID take the expression both
  ways and lost to another term**. In P23 a base that cannot supply the second
  reading is REJECTED, not down-scored — for api splits and for the splits the
  necessity table implies, computed at group level. It is relaxed only if it
  empties the candidate list, and the relaxation is counted.
* **(b) PINNING THE ZEROED ORDINAL'S ENABLING GATES.** `_p23_index.mintnec`,
  a new table with the same epistemics as the necessity table one level down:
  for a RAW ordinal length key (`len(...records_5_rows)`) and an aliased length
  `L`, if over >= 200 runs with `L` empty the ordinal was NEVER minted, then
  `L != 0` is a measured precondition of that ordinal EXISTING. 9 of 17 raw
  ordinals carry one. The split writes 0 to the ordinals the cube empties, and
  their own preconditions are then pinned so the run still REACHES them.
* **(c) PER-SET OVERLAY (S1).** One base per demand SET, every cube of the set
  by overlay (`P23_GROUP=set`), with the set identity taken from the
  enumerator's own clique index rather than matched against a stale parts file.

```
  ROUND 1 (P23A) BUILD          14 176 emitted cubes -> 13 792 gaps, 1 724 groups
    values substituted            4 018 (4 015 SYM_PARAM_id)
    values not seedable             448 over 2 vars (the two render outputs), 224 seeds
    governor lengths PINNED      17 202  (already right on the base 6 063)
    SPLIT PINS                   15 734  (0 on a key the base had no seed for)
    unresolved governor conflicts     0
    GAPS NOT CONSTRUCTIBLE            0 / 13 792
    D1 HARD FILTER   bit on 783 of 1 724 groups, 26 574 591 bases rejected,
                     RELAXED on 0 groups  <- a both-ways base always existed
    ZEROED-ORDINAL PINS written       0   <- the lever is INERT on this batch:
                     1 219 zeroed ordinals had NO measured minting precondition
                     (the 9 raw ordinals that carry one are not the ones these
                     cubes zero). Stated, not hidden; it cost nothing and
                     bought nothing, and lowering MIN_RUNS below 200 to make it
                     fire would weaken the §16b-style epistemics it borrows.
```

### §81.4 ROUND 1 (P23A) — DRIVEN, AND THE WALK RATE IS 96.9 %

```
  unit    posts-p23a-drive-20260912.service (concolic-cov.slice, MemoryMax=9G),
          DRIVE_PAR=2, CHUNK=200
  18:00:37 -> 20:22:23 UTC   wall 141.8 min   (1.6 runs/s; an unrelated
          40-JVM blockaid job held all 4 CPUs for the whole round)
  seeds 13 792 driven 13 792, 0 left · dumps 196 005 -> 209 795 (+13 790)
  toxic 2 · native aborts 0 · legs 4/4 CAGED-OK
  verdict P15-DRIVE-DONE P23A  +13790 dumps  0 seeds left

  PER KEY over all 130 443 cube literals of the 13 780 driven gaps
     honoured        128 820   98.8 %      (P18E: 83.2 %)
     contradicted      1 182    0.9 %      (P18E:  5.3 %)
     never evaluated     441    0.3 %      (P18E: 11.6 %)
  gaps WALKED       13 357 / 13 780 = 96.9 %   (P18E: 32.8 %)

  BY FAMILY                  honoured  contra  never   %hon
     length gate (rows)         46 845   1 155     74  97.4%   <- D1's family
     find_by not_found          28 065       0     98  99.7%
     guid                       20 221       0     18  99.9%
     param id length            12 437       0      0 100.0%
     length gate (ids)           6 950       0      0 100.0%
     text (empty)                6 070      15     21  99.4%
     text (has_mention)          4 139      12     13  99.4%
     guid self-compare           2 976       0      0 100.0%
     text (rendered)               328       0    132  71.3%
     size gate                     153       0     77  66.5%
  FIRST FAILING LITERAL: contradicted length-gate 324, never-evaluated
     length-gate 53, never-evaluated size gate 24, text(empty) 18, has_mention 4
```

**The D1 remedy works, measured on its own family.** Contradicted length-gate
keys fell from 201 of 992 (20.3 %) in P18E to 1 155 of 48 074 (2.4 %) here, and
the walk rate went from 32.8 % to 96.9 %.

**And the honest discount, stated before the result is used.** Part of that
jump is definitional, not causal: a checker witness is a FULL leaf assignment
(P22's 283 witnesses assign 6-24 members each) while an enumerator region piece
is a PARTIAL cube (the P23A batch averages 9.5 constrained literals) whose free
members the base supplies. Fewer literals to honour is an easier walk. The
family table is the part that is not definitional — inside the length-gate
family the constructor is being asked the same question P18E was asked, and it
answers it 8x better.

### §81.5 THE ROUND-1 PASS (P23) — AND THE RATE

```
 _p15_pass.sh P23 P23A _snapshot_pruned_P22.txt   (cap 9G, ALONE_OVERRIDE=1)
   snapshot 37 366 + 13 790 = 51 156 -> 41 952 distinct outcome profiles
   (+4 586: 33 % of the 13 790 constructed runs had a profile no run had)
   checker wall 21 min 46 s   peak RSS 4 139 MB

 _cov_FINAL_P23_20260912.json
   COMPLETE=False;NODES=137;MISSING=262;BLOCKING=262;PCS=1719949
   GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
   dumps_loaded=41952;dumps_unparseable=0
   DEMAND_SETS=843;TREE_COMPLETE=True;TREE_MISSING=0;FORECLOSURES=4100
   FORECL_IGNORED=0;FORECL_PROVISIONAL=False
```

Booked the four ways §78.5 requires:

```
  pass  drive  demand  gap-  Δgap  closed  gone  surviv  new  newly  runs   walked  rate
                sets   sets        (clean)(merged)          broken            %
  P22    P18E    853    332    —      —      —     —     —     —      —     32.8%   —
  P23    P23A    843    324    -8      4     10   318     6     0  13 790   96.9%  +0.001
```

**+0.001 per run.** Every §16b precondition still holds (137 nodes,
`tree_complete`, `tree_missing` empty, `foreclosures_provisional` False,
`solver_lost` 0, `unevaluable_exprs` []), and `newly broken` is 0.

### §81.6 THE RE-ENUMERATION — WHY 0.001, EXACTLY

The same census on the P23 corpus (41 952 profiles), which is the measurement
that explains the rate instead of guessing at it:

```
                          P22 corpus (37 366)      P23 corpus (41 952)
  demand sets                       1 729                    1 777   (+48)
  satisfiable            85 629 775 157 048       86 306 426 804 024
  covered                           208 770                  263 598   (+54 828)
  REMAINING              85 629 774 948 278       86 306 426 540 426   (+6.77e11)
  region pieces                     847 327                1 107 494   (+260 167)
  REACHABLE remaining               87.92 %                  88.59 %
  wall                                670 s                   1 077 s
```

**13 790 near-perfectly-constructed runs covered 54 828 more assignments and
the remaining went UP by 6.8e11.** That is not a driving failure — the runs did
what they were built to do, 96.9 % of them walking the leaf they were aimed at.
It is §16's monotone demand growth arriving at scale: a run that evaluates two
decisions together CREATES a demand set, and 33 % of this batch had an outcome
profile the corpus had never produced, so the batch manufactured 48 new demand
sets and 260 167 new region pieces while covering 54 828 assignments. At
posts_show's set widths (mode 40) the universe grows faster than driving fills
it, and no batch size changes that ordering.

### §81.7 ROUND 2 (P23B) — AND THE STOP

Built from the R2 census and a fresh index (`_p23_index_R2.pkl`, 41 952
profiles), same constructor, same settings:

```
  14 176 emitted cubes -> 14 176 gaps, 1 772 groups, K=1
    values substituted            5 356 (5 354 SYM_PARAM_id)
    governor lengths PINNED       7 154 (already right on the base 15 902)
    SPLIT PINS                   15 065 · unresolved conflicts 0
    GAPS NOT CONSTRUCTIBLE            0 / 14 176
    D1 HARD FILTER  bit on 854 of 1 772 groups, 32 947 733 bases rejected,
                    RELAXED 0 groups
    ZEROED-ORDINAL PINS written       0 (1 729 with no measured precondition)

  unit posts-p23b-drive-20260912.service, DRIVE_PAR=2, CHUNK=200
  21:33:38 -> 22:46:03 UTC  wall 72.4 min (3.3 runs/s; the competing job ended
        mid-round, which is the whole difference from round 1's 1.6 runs/s)
  seeds 14 176 driven 14 176, 0 left · dumps 209 795 -> 223 971 (+14 176)
  toxic 0 · native aborts 0 · legs 4/4 CAGED-OK
  verdict P15-DRIVE-DONE P23B  +14176 dumps  0 seeds left

  PER KEY over all 141 917 cube literals of the 14 176 driven gaps
     honoured        140 511   99.0 %
     contradicted      1 036    0.7 %
     never evaluated     370    0.3 %
  gaps WALKED       13 764 / 14 176 = 97.1 %
  length gate (rows) 52 934 hon / 1 014 contra / 43 never = 98.0 % honoured

 _p15_pass.sh P24 P23B _snapshot_pruned_P23.txt   (cap 9G, ALONE_OVERRIDE=1)
   snapshot 41 952 + 14 176 = 56 128 -> 46 190 distinct outcome profiles
   checker wall 10 min 0 s   peak RSS 4 614 MB

 _cov_FINAL_P24_20260912.json
   COMPLETE=False;NODES=137;MISSING=258;BLOCKING=258;PCS=1949467
   GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
   dumps_loaded=46190;dumps_unparseable=0
   DEMAND_SETS=839;TREE_COMPLETE=True;TREE_MISSING=0;FORECLOSURES=4075
   FORECL_IGNORED=0;FORECL_PROVISIONAL=False
```

```
  pass  drive  demand  gap-  Δgap  closed  gone  surviv  new  newly  runs   walked  rate
                sets   sets        (clean)(merged)          broken            %
  P22    P18E    853    332    —      —      —     —     —     —      —     32.8%   —
  P23    P23A    843    324    -8      4     10   318     6     0  13 790   96.9%  +0.001
  P24    P23B    839    320    -4      1      6   317     3     0  14 176   97.1%  +0.000
                                                                  ------
  CUMULATIVE P22 -> P24: 332 -> 320 gap-sets over 27 966 runs = +0.00043/run
                         5 closed clean, 16 merged away, 9 new, 0 newly broken
```

**STOP RULE MET on the P23 method: 0.001 and 0.000, two consecutive rounds
under 0.05.** The constructor was NOT changed between the two rounds, so the
counter is honest (§80.11's caveat).

**And this is a different stop from §80.12's.** P18 stopped at 0.014-0.031 with
a 33 % walk rate and the diagnosis "each set holds more leaves than one round
can spend". P23 spent 27 966 runs at a 97 % walk rate and the number is ten
times SMALLER. The lever §80.12 named has now been pulled as hard as this
endpoint allows, and the conclusion is that it is the wrong lever: **the
binding constraint at posts_show is neither reach nor witnesses-per-round. It
is that the demand universe is 8.6e13 assignments over 1.1e6 disjoint region
pieces in sets of mode width 40, and it grows with the corpus.** Driving cannot
close it at any batch size; only a MODEL change can.

### §81.8 WHAT REMAINS, PER KEY, WITH CONSTRUCTION EVIDENCE (nothing is declared)

Two answers, because there are two questions and the campaign has been
conflating them.

**(1) THE CHECKER'S REPORT — 258 witnesses over 320 gap-sets** (`_p23_ckptgaps_P24.json`,
`_p15_classify.py` on `_cov_p24.ckpt.jsonl`; the file `_p15_gaps.json` was NOT
overwritten):

```
  member-slots by family                       102 distinct gate combinations
     258  other                  23  text (empty)
     223  guid                   19  evilq not_found
     222  guid self-compare      15  nsfw gate
     187  text (has_mention)     15  text (rendered)
     137  find_by not_found      13  param id length · 6 findpublic · 6 public gate

  CONSTRUCTIBILITY of the 258, before a base is chosen
     242  fully constructible from observed values
      15  carry a CONSTRAINED variable NO run can seed (SYM_RESULT_Anonymous_process_3
          x15, _2 x5 — the two derived render outputs, §78.7's unsteerables)
       7  carry a CONSTRAINED out-of-domain value (SYM_PARAM_id x7,
          Anonymous_process_2 x5)
       1  distinct variable with NO observed domain at all (Anonymous_process_3)
     102  distinct enabling-gate combinations; the top ones all pair
          `records_2_rows != 0` with a comments length and an api-1 guid
```

**(2) THE ENUMERATOR'S REPORT — 8.63e13 assignments over 1 107 494 region
pieces in 1 770 sets of width >= 13** (measured on the P23 corpus, 41 952
profiles; the P24 corpus is larger still). This is the number that governs
whether driving can finish, and (1) is a 258-item sample of it.

**Per key, what each class needs — stated, not decided:**

| class | n | evidence | what it needs |
|---|---|---|---|
| every family above, as a DRIVING problem | 258 | 96.9 % and 97.1 % of two 14k batches walked; 98.8 % / 99.0 % of keys honoured; 0 of 27 968 inconstructible | **NOTHING more from the driver.** The constructor is no longer the binding constraint at this endpoint, and P23 is the measurement that establishes it. Two rounds at 0.001 and 0.000 per run with the remaining RISING is not a construction failure. |
| unsteerable render pair | 15 (+7 ood) | `Anonymous_process_2/3` are DERIVED strings the corpus never carries as a seed key; §78.9 measured that 0 of 35 563 profiles ever has the two ordinals disagree, and 142 of 227 such cubes demand exactly that | a **DECLARATION WITH A FALSIFIER** of the §79.3(b) render-identity shape, or a `src/` treatment of derived outputs. **NOT declared here** — this is a report. |
| D1 comments family | 26 (from §80.13, unchanged) | 0 of 41 952 profiles has ever taken a comments length both ways; the P23 hard filter found a both-ways base for every OTHER canonical (0 relaxations) and none for these | a `src/` inference at ORDINAL rather than CANONICAL granularity, or a declaration with a falsifier. **OWNER CALL** — the corpus is now 12 % larger than when §80.13 said this and the answer did not move. |
| the 1.1e6-piece residue | all | exact, `bounded_cliques=0`, `TRUNCATED=True` on the checker side | a **MODEL** change, not a driving change: a §16c-style confinement layer in the demand universe (the OR-refinement `_emit_or_demand.py` measured cut 5.2e13 to 2.0e7 on the OR0911 corpus — a factor of 2.6e6), or an explicit width bound on demand sets. **OWNER CALL.** |
| zeroed-ordinal minting pins | 0 fired | 1 219 (R1) / 1 729 (R2) zeroed ordinals have no measured precondition at MIN_RUNS=200 | either lower MIN_RUNS (weakens the epistemics) or accept that this half of §80.13's D1 remedy is not needed — the hard filter alone took the family from 20.3 % contradicted to 2.4 %. |

**Nothing here is residue by the corpus's own standard.** `tree_complete` is
true, `tree_missing` empty, `foreclosures_provisional` False, `solver_lost` 0,
`unevaluable_exprs` [], `bounded_cliques` 0, and every value every remaining
cube constrains is in the observed domain for 242 of the 258 witnesses and for
every one of the 27 968 cubes the two rounds constructed.

### §81.9 ARTEFACTS OF §81

```
_p23_enum.py        _exact_enum_emit.py + STREAMED emit (a kill loses the tail,
                    not the census) + an UNCAPPED per-set `region_pieces`
                    counter + ascending-width census order (so a per-set emit
                    cap spends its budget on the sets a round can actually take
                    clean, not on the width-45 hubs)
_p23_index.py       _p18_index.py + `mintnec`, the RAW-ORDINAL minting table
_p23_construct.py   _p18_construct.py + the D1 hard both-ways base filter,
                    the zeroed-ordinal enabling pins, per-set (S1) grouping,
                    and a manifest that records the seed file it actually wrote
_p23_gaps.py        the enumerator's streamed cubes -> the gap + parts files the
                    constructor consumes, with the set identity taken from the
                    census rather than matched against a stale parts file
_p23_rebuild.sh     gaps-bridge -> construct, one command
_p23_emit_R{1,2}.json.jsonl   the streamed remaining cubes (13 792 / 14 176)
_p23_enum_R{1,2}.{json,log}   the two censuses
_p23_index{,_R2}.pkl          the two indexes
_p23_gaps_P23{A,B}.json       the two batches
_p15_explain_P23{A,B}.json    the per-key verdict of each round
_cov_FINAL_P2{3,4}_20260912.json + _cov_p2{3,4}.ckpt.jsonl
_snapshot_pruned_P2{3,4}.txt
_p23_ckptgaps_P2{2,3}.json    the checker-side per-key classification
corpus 196 005 -> 223 971 dumps (+27 966 constructed runs, 2 toxic, 0 aborts)
```

* **A DEFECT FOUND AND FIXED IN THIS ROUND.** `_p23_construct.py` inherited
  `_p18_construct.py`'s hard-coded `"seed_file": "_p15_seeds_" + variant`, but
  P23 writes its seeds under a configurable prefix. `_p15_explain.py` indexes
  INTO that file by `seed_index`, so the first explain attempt died with an
  `IndexError` against the shorter P18-era file — loud, not silent, and caught
  before any round was booked. The manifest was repaired in place and the
  constructor now records `PREFIX`/`PREFIXB`.
* No `src/` edit, no `targets.rb` or shared-boundary edit, no declaration, no
  extraction, no policy, nothing under `notifications_index/`, no git. The two
  modules that run `main()` at import (`_p15_classify.py`, `_p15_explain.py`)
  were RUN, never imported; `_p23_gaps.py` COPIES their helpers, as §80.14 requires.

## §82. THE CONFINEMENT LAYER, WIRED AND MEASURED — and what was actually missing (2026-09-12)

The brief for this round was "`posts_show/coverage_report.py` has NO confinement
wiring at all (`grep CONFINE|confinement` → nothing), so every pass since the
reboot (P14 → P24) and tonight's exact enumeration ran WITHOUT the §16c layer."
The grep is right. The conclusion is HALF right, and the half that is wrong is
the more important one.

### §82.1 WHAT WAS MISSING — three things, and NOT the projection itself

`CoverageChecker.__init__` (coverage.py:1419-1435) defaults are

```
    confinement=True   confinement_strict=True   confinement_keying="coevaluated"
    confinement_gates=True   confinement_or_sharing=True
```

so **§16c OR-refined confinement is ON unless a caller turns it off**, and every
posts_show pass P15A → P24 ran engine `coverage.py` md5
`270be964bc7de60bfb9390108938411f` (recorded in all 14 `_p15_pass_*.log`
headers; it is the current file). The checker layer therefore has been
projecting by §16c all along. What `coverage_report.py` lacked was:

1. **The cross-pass loop** — no `withdrawn_pairs=`, no `prior_footprints=`.
   Gate verdicts could not outrank corpus inference and the corpus tripwire
   could not fire.
2. **Any reporting** — the fixed summary schema (settled before §16c existed)
   serialised none of `footprints`, `confined_pairs`, `confinement_overlapping`,
   `confinement_splits`, `confinement_provisional`, `confinement_withdrawn`,
   and the pass never called `result.summary()`, so not one line of the layer
   reached a log or a JSON. **Every posts_show `demand_sets` number since the
   layer landed was computed under a projection the report did not name.**
3. **`max_cliques`** — the engine default is 1024 and it caps BOTH the
   independence projection of one evaluation set AND the confinement projection
   of one demand set; a hit is signalled only through `truncated`, which §16d
   already forces True on any incomplete pass, i.e. it was invisible. This
   endpoint's own enumerator has always run at 16384.

**And the exact enumerator genuinely had no §16c at all.** `_p23_enum.py::
build_universe` applies `infer_foreclosures` / `restrict_foreclosures` and stops
there. So §81's **8.63e13 is the §16b number**, and comparing it with the
pre-reboot **2.02e7 (§73, which was §16c-OR)** compared two different demands.
The two tools were reporting different universes and §81.1's "the two tools
agree on the universe" was true only of the pre-confinement half of it.

### §82.2 THE WIRING (`coverage_report.py`, ported from notifications_index)

Backup `coverage_report.py.pre_confinement_20260912`. Diff, in five parts:

* `_confinement_withdrawn.json` / `_prior_footprints.json` read from the batch
  dir (overridable by `WITHDRAWN_PAIRS_FILE` / `PRIOR_FOOTPRINTS_FILE`,
  suppressible by `NO_WITHDRAWN_PAIRS` / `NO_PRIOR_FOOTPRINTS`), fed as
  `withdrawn_pairs=` / `prior_footprints=`, and the notifications line
  `[confinement] withdrawn_pairs fed back: N; prior_footprints for M expressions`.
* `max_cliques=int($MAX_CLIQUES or 16384)` and the four confinement knobs as
  `CONFINEMENT` / `CONF_STRICT` / `CONF_KEYING` / `CONF_GATES` /
  `CONF_OR_SHARING`, each defaulting to the ENGINE's own default — an unset
  environment reproduces the shipped pass. A second `[confinement] settings:`
  line names the reading (`16b` / `STRICT` / `OR-refined` / `weak`).
* The fixed schema gains ONE additive key, `summary["confinement"]`: mode,
  settings, decided / confined / undecidable / co-evaluated / disqualified
  decisions, confined / OR-licensed / AND-refused / overlapping / undecidable
  pairs, splits, provisional, withdrawn (fed back and by tripwire), and the
  pair lists. No existing key changes meaning.
* A `CONFINEMENT=...;DECIDED=...;PAIRS_CONFINED=...;...` verdict line next to
  `COMPLETE=`, plus `CONF-WITHDRAWN` / `CONF-DISQUALIFIED` detail lines.
* `FOOTPRINTS_OUT=<f>` writes this pass's footprints in the shape
  `prior_footprints=` reads. It is NEVER written over `_prior_footprints.json`
  by default: the tripwire compares THIS corpus against an EARLIER pass, so the
  promotion has to be deliberate, not "whichever pass ran last".
* The notifications C7 heartbeat (`HEARTBEAT_SECS`), so the Z3 phase cannot go
  silent.

The checkpoint keys were already honest — `_checkpoint_header_keys`'s `params`
digest folds all five confinement knobs plus `max_cliques`, so the three
readings below could never read each other's records.

### §82.3 THE THREE READINGS, ON ONE CORPUS (P24, `_snapshot_pruned_P24.txt`, 46 190 profiles)

`_p25_confcensus.py` (batch-local descendant of `tools/confinement_census.py`,
which is shared and was NOT edited) runs `_p23_enum.py`'s exact census over the
SAME universe three times: `U["cliques"]` (§16b) and the same sets projected by
`project_confinement` with `or_sharing=False` (strict) and `True` (OR-refined).
One universe, one trace layer (69 distinct call shapes), one set of footprints —
so the three numbers are comparable by construction. Cage 6 G, wall 620 s,
`bounded_cliques=0` in all three (EXACT, not a bound).

```
  reading            demand    satisfiable        covered      REMAINING     region    max   mode
                      sets                                                   pieces   width  width
  16b (unconfined)    1 673  84 607 926 177 592   306 210  84 607 925 871 382 1 289 957   45    40
  16c STRICT          5 863       2 569 428 280   741 101       2 568 687 179 1 932 747   28    25
  16c OR-refined        839              32 575    18 633              13 942     3 670   19     6
```

**The remaining is 8.46e13 → 2.57e9 → 1.39e4.** Not 8.63e13 (that was §16b on
the slightly smaller P23 corpus) and not 2.02e7 (that was §16c-OR on the
pre-reboot GC0911 corpus, §73, under a DIFFERENT engine — md5 `256f44c1…`).
The OR-refined demand universe on today's corpus is **32 575 satisfiable
assignments in total**, of which the corpus has already covered 18 633.

Per-width remaining, the §81.2 table under each reading (top buckets):

```
  16b        w34 1.01e10 | w36 1.87e11 | w38 2.24e12 | w40 9.33e12 | w42 1.56e13 | w43 1.88e13 | w45 1.06e13
  STRICT     w18 1.02e07 | w21 2.63e07 | w22 1.65e08 | w23 7.12e08 | w24 8.24e08 | w25 5.02e08 | w27 1.22e08
  OR-refined w06 1 061   | w07 1 793   | w15 1 605   | w16 1 423   | w17 1 827   | w18 1 448   | w19 395
```

The model change §81.8 asked for is visible in one column: **max set width
45 → 19, mode width 40 → 6.** At mode width 40 a set holds ~1e12 assignments
and a run covers one; at mode width 6 the whole endpoint holds 3.3e4.

**NESTING, CHECKED not assumed** (`_p25_confcensus.py`'s structural test, every
set of the finer reading must be contained in a set of the coarser one):

```
  OR-refined in strict   839/839 contained      remaining 1.39e4 <= 2.57e9
  strict     in 16b    5 863/5 863 contained    remaining 2.57e9 <= 8.46e13
  OR-refined in 16b      839/839 contained
```

`OR-refined ⊆ strict ⊆ §16b` holds on the sets and on the mass.

### §82.4 THE PASSES — and the number that settles §82.1

`_p25_conf_passes.sh`, one pass at a time, same P24 list, `SKIP_COMPLETION=1`,
`MAX_MISSING_PER_CLIQUE=1`, `COVERAGE_CHECKPOINT` per reading, cap 9 G,
detached `posts-p25-conf-20260912.service`, verdict `^COMPLETE=`.

```
  reading      COMPLETE  NODES  MISSING  DEMAND_SETS  TREE  FORECLOSURES  checker  wall   peak
                                                          MISS                    (Z3)          RSS
  16b            False     137    1 668      1 673         0     23 296        517 s  13:50  4 615 MB
  16c STRICT     False     137    5 844      5 863         0     47 979(*)   1 374 s  28:20  4 669 MB
  16c OR-ref     False     137      258        839         0      4 075         91 s   6:47  4 616 MB
  --- for reference, the pass of record ---
  P24 (as shipped, OR-refined at max_cliques=1024)
                 False     137      258        839         0      4 075        600 s  ~10:00 4 614 MB

  all three: GENUINE=True  TRUNCATED=True (forced by §16d at cap 1)  SOLVER_LOST=0
             UNEVALUABLE=[]  TREE_COMPLETE=True  FORECL_PROVISIONAL=False
             PROVISIONAL=False  WITHDRAWN_FED=0  WITHDRAWN_TRIPWIRE=0
  (*) FORECLOSURES is the count restricted to the sets each reading demands, so
      the strict number is the 16b relation seen through 5 863 narrower sets.

  CONFINEMENT verdict lines (identical inference, different licence):
    STRICT      DECIDED=123 CONFINED_DEC=54 DISQ_DEC=69 UNDECIDABLE_DEC=14
                COEVAL_DEC=41 PAIRS_CONFINED=700   OR_PAIRS=0    AND_REFUSED=0
                UNDECIDABLE_PAIRS=854 SPLITS=1668
    OR-refined  DECIDED=123 CONFINED_DEC=54 DISQ_DEC=69 UNDECIDABLE_DEC=14
                COEVAL_DEC=41 PAIRS_CONFINED=2701  OR_PAIRS=2001 AND_REFUSED=931
                UNDECIDABLE_PAIRS=854 SPLITS=1673

  [confinement] withdrawn_pairs fed back: 0; prior_footprints for 0 expressions
  (no `_confinement_withdrawn.json` and no `_prior_footprints.json` exist on this
   endpoint yet — the gate has never run here, which is §82.5)
```

**`P24` reported `DEMAND_SETS=839`. The census's OR-refined projection produces
839 demand sets, and the OR-refined pass reproduces it.** That is the proof of
§82.1: the pass was already OR-refined, and it was so at `max_cliques=1024` as
well as at 16384 — the cap was not being hit. The §16b pass is the number
posts_show has never had: **1 673 demand sets, 1 668 with a gap**, twice the
demand the endpoint has been reporting.

### §82.5 THE GATE — 1 363 classes, and the projection that stops it here

Nothing above is licensed. DISCIPLINE §16c check 2: an inferred pair counts only
after `assumption_checker.py::_test_confinement` has replayed it, and an
inferred pair the gate cannot verify is WITHDRAWN and BLOCKS
(`confinement_unverified`). What the inference yields on posts_show, and what
the gate would cost, measured from the same corpus
(`_p25_gate_projection_P24.json`):

```
  decisions        137 active -> DECIDED 123 (41 only under the co-evaluated
                   keying, i.e. gates) / UNDECIDABLE 14
                   strictly CONFINED 54 / DISQUALIFIED 69
  pairs  STRICT    confined   700 | OR-licensed     0 | AND-refused   0
         OR        confined 2 701 | OR-licensed 2 001 | AND-refused 931
         both      overlapping 0  | undecidable 854
  gate CLASSES (the footprint-family key `_c11_classes.py::class_of`
                reproduces)                          1 363, largest 25 pairs
```

`overlapping 0` again, exactly as §73/§74 found: on this endpoint the pairs the
strict rule refuses are refused by DISQUALIFICATION (an OR-shared shape) and by
UNDECIDABILITY, never by measured AND-interaction — and the OR licence converts
2 001 of them.

The gate's own cost model (`_test_confinement` docstring): "3 composition
replays per pair + min(`ACHK_CONF_PROFILES`, profiles carrying a footprint
shape) for (vi) + one constructed replay per footprint shape with another
producer for (vii)", one representative per class, probes deduped in the
ProbeCache. Measured on this corpus:

```
  (vi)  profile representatives, per decision   min 0 / median 1 702 / max 46 190
        deduped over the 109 decisions that appear as a class representative
                                                          477 755 replays
  (iii)(iv)(v)(viii) composition, 3 x 1 363 classes           4 089 replays
  (vii) constructed routes, <= 1 per footprint shape          1 445 replays
                                                          ---------------
  TOTAL                                                     483 289 replays
        (the per-class sum, double-counting shared decisions, is 15 355 378)

  posts_show's own measured replay rate: 3.26 runs/s at DRIVE_PAR=2 (§81.7)
        = 0.61 s/run serial.  At CONCOLIC_SLOTS=1:
           0.30 s/replay ->  40.3 h      0.61 s/replay ->  81.9 h
           1.00 s/replay -> 134.2 h
```

Both figures are **LOWER bounds**: `_profile_representatives` indexes the WHOLE
batch directory (223 971 dumps), not this 46 190-profile snapshot.

**THE GATE WAS NOT RUN.** The instruction was to run it if the projected wall is
under ~6 h and otherwise to report the projection and stop; 40-134 h is not
under 6 h. Capping `ACHK_CONF_PROFILES` is not an escape: §16c states that a
budget which truncates (vi) makes the verdict NOT-TESTABLE, and a NOT-TESTABLE
inferred pair is withdrawn and blocks — a capped run withdraws exactly what it
could not probe.

**So the three numbers above have three different standings.**

```
  8.46e13   16b          NO confinement claim — needs no gate, and is the
                         demand if every inferred pair is withdrawn
  2.57e9    16c STRICT   700 pairs, UNGATED
  1.39e4    16c OR-ref   2 701 pairs, UNGATED
```

The post-gate remaining is therefore bracketed, not known:
`1.39e4 <= post-gate <= 8.46e13`. The only prior evidence on the ratio is
notifications', where 247 of 291 confinement classes did not PASS (245 FAIL, 2
NOT-COMPARABLE), withdrawing 1 806 pairs — 85 % of classes at the class level.
Nothing licenses carrying that rate across endpoints, and it is quoted as the
only measured precedent, not as a prediction.

### §82.6 THE RESIDUE, PER KEY

```
  reading      witnesses  parts   width   fully          >=1 CONSTRAINED  >=1 unseedable  distinct gate
               (dedup)             range   constructible  out-of-domain    variable        combinations
  16b            1 668    1 578   11-45        73             1 595            40              294
  16c STRICT     5 844    5 468    8-28       431             5 413           302              n/a
  16c OR-ref       258      226    6-24       242                 7            15              102

  16b       1528 guid | 1228 find_by not_found | 1222 guid self-compare
            40 text (rendered) | 36 evilq not_found | 4 findpublic | 4 public gate
            out-of-domain: SYM_PARAM_id x1577, as_api_response_{2,3,4,1}_row_guid
            x264/200/136/60; unseedable: Anonymous_process_{2,3} x40 each
  STRICT    5844 nsfw gate | 5844 other | 5844 param id length | 5844 text
            (has_mention) | 5426 guid | 5330 text (empty) | 4447 guid
            self-compare | 4426 find_by not_found
            (every witness of a width-8..28 strict part touches nearly every
             family, which is what "the strict split keeps the sets wide" means)
  OR-ref    258 other | 223 guid | 222 guid self-compare | 187 text (has_mention)
            | 137 find_by not_found | 23 text (empty) | 19 evilq not_found
            | 15 nsfw gate | 15 text (rendered) | 13 param id length
            | 6 findpublic not_found | 6 public gate
            242 fully constructible; 15 carry `Anonymous_process_3` (and 5
            `_2`), the §78.7 unsteerables; 7 carry an out-of-domain
            `SYM_PARAM_id`; 102 distinct enabling-gate combinations

**The OR-refined row is §81.8(1) exactly** — 258 witnesses, the same twelve
families with the same counts, 242 constructible, 15 unsteerable, 7 out-of-domain,
102 gate combinations. §81.8 was already reporting the OR-refined residue; what
it put next to it (8.63e13) was the §16b one. THAT is the mismatch §82 removes:
the residue and the remaining now come from the same universe.

The three residues are the same endpoint under three licences: **the number of
witnesses tracks the number of demand sets, not the amount of work left.** 16b
has 6.5x the witnesses of OR-refined and 6.1e9 times the remaining; STRICT has
22.6x the witnesses and 1.8e5 times the remaining. Only the enumerator's
`REMAINING` column orders them correctly, which is why §82.3 is the answer to
"what is left" and this section is the answer to "what would a round aim at".
```

### §82.7 WHAT §82 CHANGES, AND WHAT IT DOES NOT

* The endpoint's reported `demand_sets` now says which reading produced it, and
  the cross-pass loop exists, so a gate verdict can reach the next pass.
* `tree_complete` is still True, `tree_missing` empty, `foreclosures_provisional`
  False, `solver_lost` 0, `unevaluable_exprs` [], `bounded_cliques` 0,
  `confinement_provisional` False. Nothing about the tree layer moved.
* **The endpoint is NOT closer to closed.** 1.39e4 is a demand universe, not a
  verdict, and it rests on 2 701 pairs that no replay has tested. The honest
  reading of §82 is that §81.8's "a §16c-style confinement layer is the only
  measured lever with the right magnitude" was correct AND the layer was already
  applied in the checker — what is missing is not the layer, it is the GATE, and
  the gate is a 40-134 h job at this endpoint's corpus size. **OWNER CALL:** run
  it, or reduce (vi)'s cost in `src/` (a per-decision profile-representative
  budget that stays sound), or accept the 16b number.
* No `src/` edit, no `targets.rb` or shared-boundary edit, no declaration, no
  extraction, no policy, no git, nothing written under `notifications_index/`
  (its `coverage_report.py`, `_c11_classes.py`, `_c10_gate_all.sh` and
  `_gate_ALL_results.json` were READ).

### §82.8 ARTEFACTS OF §82

```
coverage_report.py                       + the confinement wiring (backup
                                           coverage_report.py.pre_confinement_20260912)
_p25_conf_passes.sh / _p25_conf_passes.log   the three passes
_p25_cov_P25{OFF,STRICT,OR}.{log,time}       per-reading pass logs
_cov_FINAL_P25{OFF,STRICT,OR}_20260912.json  per-reading summaries (new schema)
_cov_p25{off,strict,or}.ckpt.jsonl           per-reading checkpoints
_footprints_P25{OFF,STRICT,OR}.json          FOOTPRINTS_OUT side-cars
_prior_footprints.json                       = _footprints_P25OR.json, PROMOTED
                                           deliberately so the NEXT pass's corpus
                                           tripwire has an earlier pass to compare
                                           against (it can only ADD withdrawals).
                                           No `_confinement_withdrawn.json` is
                                           written: the gate has not run.
_p25_confcensus.py / _p25_census_P24.{log,json}   the three exact censuses
_p25_pairs_P24.json                          footprints + confined/OR pairs
_p25_gate_projection_P24.json                the gate's class list and budget
_p25_residue.sh / _p25_gaps_P25*.json        the per-key residue
```

## §83. P26 — THE OR-REFINED RESIDUE, DRIVEN; AND THE CONFINEMENT GATE, LAUNCHED AND MEASURED (2026-09-13)

§82 left two things undone and named both. The demand under the reading the
endpoint actually runs (§16c OR-refined) is **13 942 assignments**, not 8.63e13
— small enough to drive — and it had never been EMITTED, because `_p23_enum.py`
has no §16c and `_p25_confcensus.py` emitted one cube per set as a census
side-effect. And the 2 701 inferred pairs that projection rests on had never
been REPLAYED, so `1.39e4 <= post-gate <= 8.46e13` was a bracket, not a number.
§83 does both, in parallel: two driven rounds against the OR-refined residue,
and the active gate started over all 1 363 classes with its real rate measured
instead of projected.

### §83.1 THE MISSING TOOL — an OR-refined EMISSION (`_p26_emit_or.py`)

`_p26_emit_or.py` is `_p25_confcensus.py`'s universe + trace layer + the
IDENTICAL `project_confinement(strict=True, keying="coevaluated",
protect_gates=False, or_sharing=True)`, with `emit_max_per_set` / `emit_cap`
OPEN instead of pinned at 1, plus (from round 2 on) a count-only §16b census
over the same universe so every round is booked under BOTH readings. Nothing
below the projection is new code: same disjoint cover, same `_emit_item`, same
streamed JSONL, same uncapped `region_pieces`.

**It reproduces §82.3's OR-refined row exactly on the P24 corpus**, which is the
check that the emission and the census are the same object:

```
  R1 (P24, 46 190 profiles, cage 6G, wall 476 s, universe build 344 s)
    demand sets 1673 -> 839      decisions 137 -> DECIDED 123 / CONFINED 54 / DISQ 69
    pairs confined 2701 (OR-licensed 2001, AND-refused 931, overlapping 0)
    satisfiable 32 575   covered 18 633   REMAINING 13 942   bounded_cliques 0
    region pieces 3 672          max width 19, mode width 6
    §82.3 said                   13 942 over 3 670 pieces          <- 2 pieces apart
```

The 2-piece difference (3 672 vs 3 670, 0.05 %) is stated, not explained: the
piece counter is uncapped in both tools and every total that depends on it
(`satisfiable`, `covered`, `remaining`, `mismatch_sets=0`) is identical.

**AND THE FINDING THE EMISSION ITSELF PRODUCED, which no census could:**

```
  R1  region pieces 3 672  ->  cubes EMITTED 1 923   no_model 1 749
      emitted mass 8 764   of REMAINING 13 942       (62.9 %)
  R2  region pieces 3 241  ->  cubes EMITTED 1 487   no_model 1 754
      emitted mass 6 743   of REMAINING 11 931       (56.5 %)
```

**48 % of the OR-refined region pieces have no Z3 model.** `_emit_item` asks the
solver for `fixed_base + the set's pins + the piece's literals`; `cube_count`,
which is what the census sums, counts models COMPONENT-WISE
(`components()` splits the set by shared variables, `comp_models` counts each
component under the pins). The two agree on every set — `mismatch_sets=0`, the
piece masses sum exactly to `sat - covered` — and disagree on 1 749 individual
pieces. It is not a timeout: the whole emit ran in 103 s of Z3, and 1 749
10-second timeouts would be 4.8 h. It is not a parse failure: zero
`Failed to parse` warnings. It is the component product counting assignments the
full conjunction refuses, and it is specific to this projection — the §16b
rounds P23A/P23B emitted 13 792 and 14 176 cubes at **no_model=0**, because §16b
sets are wide (mode 40) and decompose into few components, while OR-refined sets
are narrow (mode 6) and decompose into many. **Consequence, in the honest
direction: the OR-refined `REMAINING` is an UPPER bound on the demand, and the
drivable part of it this round was 1 923 cubes / 8 764 assignments.** Not
resolved here; §83.5 files it.

### §83.2 THE TWO ROUNDS — construction, drive, per-key explanation

Pipeline per round (`_p26_rebuild.sh`): `_p23_gaps.py` bootstrap for the parts →
a FRESH `_p23_index.py` over that round's snapshot → `_p23_gaps.py` final →
`_p23_construct.py` (per-set overlay, D1 hard both-ways base filter, §72 rules),
then `_p15_drive.sh` (DRIVE_PAR=2, CHUNK=200, detached service, cage 9G) and
`_p15_explain.py`.

```
                                        P26A (R1)   P26B (R2)   P26C (R3)
  cubes emitted                              1 923       1 487       1 039
  CONSTRUCTIBILITY before a base is chosen
    fully constructible from observed         1 811 (94.2 %)       1 398 (94.0 %)
    >=1 CONSTRAINED out-of-domain value          92                   69
    >=1 CONSTRAINED never-observed var           41                   35
    >=1 UNSTEERABLE var (Anonymous_process)      46                   39
  CONSTRUCTED
    seeds built                               1 923                1 487
    GAPS NOT CONSTRUCTIBLE                        0                    0
    values substituted                          108                   79
    values kept out-of-domain                     9                    8
    values not seedable       66 over 2 vars, 46 seeds   53 over 2 vars, 39 seeds
    D1 hard filter bit on          161/336 groups        144/? groups
      bases rejected                      5 612 648            4 909 117
      RELAXED                              0 groups              0 groups
    governor lengths PINNED                   1 387                    -
    SPLIT PINS                                4 297                    -
    ZEROED-ORDINAL PINS written                   0 (1 208 / 1 349 zeroed ordinals
                                                    carry no measured precondition —
                                                    the lever is still INERT, §81.3)
  DRIVEN (unit posts-p26{a,b}-drive-20260913, DRIVE_PAR=2, CONCOLIC_SLOTS=4)
    wall                            6 m 25 s (5.0 runs/s)   11 m 39 s (2.1 runs/s)
    seeds driven / left                  1 923 / 0            1 487 / 0
    dumps                    223 971 -> 225 894 (+1 923)  -> 227 381 (+1 487)
    toxic 0 · native aborts 0 · legs 4/4 CAGED-OK    (same)
    verdict            P15-DRIVE-DONE P26A            P15-DRIVE-DONE P26B
  EXPLAINED PER KEY (on the dumps; no Z3, no pass)
    cube literals                            27 374               31 431
      honoured                    23 803  87.0 %       26 440  84.1 %
      contradicted                 2 685   9.8 %        2 678   8.5 %
      never evaluated                886   3.2 %        2 313   7.4 %
    gaps WALKED                1 405 / 1 923 = 73.1 %  1 021 / 1 487 = 68.7 %
```

```
  ROUND 3 (P26C), driven and explained; its pass is QUEUED (see below)
    cubes emitted 1 039 · fully constructible 990 · out-of-domain 29 ·
      unsteerable 24 · seeds built 1 039 · GAPS NOT CONSTRUCTIBLE 0
      D1 hard filter bit on 118 groups, 3 806 409 bases rejected, 0 relaxations
    driven  02:26:14 -> 02:34:24  wall 8 m 10 s (2.1 runs/s)
            1 039 / 1 039, 0 left · toxic 0 · aborts 0 · legs 4/4 CAGED-OK
            dumps 227 381 -> 228 420 (+1 039)
            verdict P15-DRIVE-DONE P26C
    explained  39 723 cube literals: honoured 31 338 78.9 % ·
            contradicted 7 329 18.5 % · never evaluated 1 056 2.7 %
            gaps WALKED 577 / 1 039 = 55.5 %
            length gate (rows) 12 774 hon / 7 329 contra / 70 never = 63.3 %
            first failing literal: contradicted length-gate 369, never-evaluated
            guid 42, never-evaluated length-gate 35
```

**The walk rate falls 73.1 % -> 68.7 % -> 55.5 % across the three rounds and the
cube width rises 14.2 -> 21.1 -> 38.2 literals, monotonically.** That is the
expected shape and it is worth naming before the next round is planned: each
round takes the cubes the previous one did NOT cover, and what is left is
systematically the pieces with the most pinned literals — above all the D1
comments-length family, whose contradicted count goes 2 685 -> 2 678 -> 7 329
while every other family stays at 95-100 % honoured. The constructor is not
degrading; the residue is concentrating on the one family the corpus cannot
supply a both-ways base for.

**The walk rate is 73 % / 69 %, against P23's 97 %, and that is definitional
before it is anything else.** A P23 cube averaged 9.5 constrained literals; a
P26 cube averages **14.2 / 21.1**, because an OR-refined region piece inside a
mode-width-6 set leaves far less to the base. Per key the constructor holds up
(87.0 % / 84.1 % honoured); the family table says where it does not:

```
  P26A   length gate (rows)  8 962 hon / 2 685 contra /   564 never = 73.4 %
         guid               10 548 hon /     0        /   124       = 98.8 %
  P26B   length gate (rows) 12 071 hon / 2 678 contra /   117 never = 81.2 %
         guid               10 684 hon /     0        / 2 107       = 83.5 %
  FIRST FAILING LITERAL: contradicted length-gate 373 / 355; never-evaluated
         length-gate 123 / 51; never-evaluated guid 0 / 43
```

The contradicted length-gate literal is the D1 family and it is the same
residual §80.13/§81.8 named: 0 of the corpus's profiles takes a comments length
both ways, so the hard filter finds a both-ways base for every OTHER canonical
(0 relaxations, both rounds) and none for these.

### §83.3 THE TWO PASSES, AND THE TWO RE-ENUMERATIONS — booked under BOTH readings

Passes: `_p26_pass.sh` = `_p15_pass.sh`'s three stages with the five confinement
knobs set EXPLICITLY (`CONFINEMENT=1 CONF_STRICT=1 CONF_KEYING=coevaluated
CONF_GATES=1 CONF_OR_SHARING=1`, `MAX_CLIQUES=16384`), `SKIP_COMPLETION=1`,
`MAX_MISSING_PER_CLIQUE=1`, `COVERAGE_CHECKPOINT` per round, `FOOTPRINTS_OUT`,
cap 9G, detached. `_p15_pass.sh` was NOT edited.

```
  pass    corpus     profiles  COMPLETE NODES MISSING DEMAND TREE FORECL  checker  wall    peak
                                                       SETS  MISS                                RSS
  P24     223 971     46 190    False    137    258     839    0   4 075    600 s  ~10:00  4 614M
  P26     225 894     47 253    False    137    236     836    0   4 058    163 s   12:20  4 851M
  P26B2   227 381     47 893    False    137    217     836    0   4 058      -     17:07  4 928M
  all: GENUINE=True TRUNCATED=True (forced by §16d at cap 1) SOLVER_LOST=0
       UNEVALUABLE=[] TREE_COMPLETE=True FORECL_PROVISIONAL=False PROVISIONAL=False
```

**THE CORPUS TRIPWIRE FIRED, for the first time on this endpoint.**
`_prior_footprints.json` (promoted from P25OR, §82.8) gave the P26 pass an
earlier pass to compare against, and 1 923 constructed runs enlarged enough
footprints to retract 187 licences:

```
  P24 (P25OR)  WITHDRAWN_TRIPWIRE=0     SPLITS=1673
  P26          WITHDRAWN_TRIPWIRE=187   SPLITS=1609   + 5 CONF-DISQUALIFIED lines
  P26B2        WITHDRAWN_TRIPWIRE=187   SPLITS=1561
  (PAIRS_CONFINED stays 2 701 — that is what THIS corpus licenses; the 187 are
   pairs the EARLIER corpus licensed and this one no longer does. §16c's
   mutability, in its only permitted direction.)
  The 5 disqualifications are all `(Length(SYM_PARAM_id) < 16)`, on shapes
  `Anonymous.process`, `Person.name`, `Photo.url`,
  `Diaspora::MessageRenderer.title`, `Relation.findpublic_like`, each naming its
  two runs.
```

Gap-set booking the four ways §78.5 requires, from the checkpoints themselves
(`_cov_p2{4,6,6b2}.ckpt.jsonl`, keyed per demand set):

```
  pass  drive  demand  gap-  Δgap  closed  merged  surv  new  newly   runs   walked
                sets   sets        (clean)              broken
  P24   P23B     839    320    —      —      —      —    —     —        —     97.1%
  P26   P26A     836    317    -3      4      1    315    2     0    1 923    73.1%
  P26B2 P26B     836    311    -6      6      0    311    0     0    1 487    68.7%
```

And the number that actually orders the work — the exact census on each round's
own corpus (`_p26_emit_or.py`, `bounded_cliques=0` every time, so EXACT):

```
                          P24 corpus        P26 corpus       P26B2 corpus
                           (46 190)          (47 253)          (47 893)
  engine coverage.py md5    270be964          270be964          5ec0c245  (*)
  OR-refined
    demand sets                  839               836               836
    satisfiable               32 575            32 555            32 555
    covered                   18 633            20 624            21 692
    REMAINING                 13 942            11 931            10 863
    region pieces              3 672             3 241             2 798
    emitted cubes              1 923             1 487             1 039
  §16b
    demand sets                1 673             1 609             1 561
    REMAINING     84 607 925 871 382  82 890 260 594 702  82 637 418 144 830
```

```
  ROUND RATE, under the reading the round was BUILT from and under §16b:
    P26A  1 923 runs   OR-refined 13 942 -> 11 931   -2 011   = 1.046 closed/run
                       §16b  8.4608e13 -> 8.2890e13  -1.72e12
    P26B  1 487 runs   OR-refined 11 931 -> 10 863   -1 068   = 0.718 closed/run
                       §16b  8.2890e13 -> 8.2637e13  -2.53e11
    STOP RULE (0.05/run for two rounds) IS NOT MET — both rounds are more than
    ten times above it, and BOTH readings move DOWN. That is the first time on
    this endpoint that the §16b remaining has fallen across a round: P23 and
    P24 drove 27 966 runs and the §16b remaining ROSE by 6.8e11 (§81.6).
```

**(*) AN EXTERNAL SESSION REWROTE `src/concolic_engine/coverage.py` UNDER THIS
ROUND, four times in ninety minutes** — `270be964` (P24, P26, R1, R2) →
`2a2e86bb` (01:35:34, the P26B2 pass) → `5ec0c245` (02:00, the R3 census) →
`e083101a` (02:13). No edit was made by this agent; `assumption_checker.py` was
rewritten at 01:16:52 as well, while the gate was running on it. Two
consequences, stated so no later reader has to infer them:

* **Round 1 is fully engine-controlled** (emission, drive, pass and both
  censuses under `270be964`). **Round 2 is not** — its "before" census ran under
  `270be964` and its pass and "after" census under two later builds.
* The round-2 delta is nevertheless USABLE, and here is the evidence rather than
  the assumption: across the engine change the OR-refined projection is
  bit-stable on everything that defines it — demand sets `836` = `836`,
  `satisfiable` `32 555` = `32 555`, `DECIDED 123 / CONFINED 54 / DISQ 69 /
  UNDECIDABLE 14 / COEVAL 41`, `confined 2 701 / OR 2 001 / AND-refused 931 /
  overlapping 0 / undecidable 854`, `NODES=137`, `FORECLOSURES=4 058`,
  `bounded_cliques=0`, `tree_missing=0`. Only `covered` moved, which is the
  drive's doing. A controlled re-measure was not attempted because the engine
  moved again during the R3 census: there is no stable build to control against
  while that session is running.

### §83.4 THE ACTIVE CONFINEMENT GATE — LAUNCHED, AND ITS RATE MEASURED

§82.5 stopped at a projection (40-134 h at `CONCOLIC_SLOTS=1`) and did not run
the gate. §83 runs it. It is still running as this section is written; the
numbers below are MEASURED off its own heartbeat and checkpoints, not projected.

```
  unit          posts-p26-gate-20260913.service   (concolic-cov.slice)
  launched      2026-09-13 00:08:34 UTC
  declared      _p26_gate_classes.json — 1 363 representatives, one per
                footprint-family class, built by _p26_gate_classes.py from the
                P25OR pass's own summary["assumptions"] (2 701 inferred
                ConfinementAssumption entries, all "inferred": true), class key
                = notifications_index/_c11_classes.py::class_of, READ not
                imported and not edited. 1 363 classes, largest 25 pairs;
                class-size histogram 1x823 2x300 3x96 4x41 5x11 6x36 7x23 8x10
                9x1 10x4 11x2 13x2 ... — REPRODUCES §82.5's 1 363 exactly.
  env           CONCOLIC_SLOTS=2  CONCOLIC_PROBE_WORKERS=2  ACHK_PROBE_BATCH=40
                ACHK_HEARTBEAT_S=60
                ACHK_INDEX_CHECKPOINT=_p26_achk_index.ckpt.jsonl
                ACHK_DERIVE_CHECKPOINT=_p26_achk_derive.ckpt.jsonl
                ACHK_CHECKPOINT=_p26_achk_probes.ckpt.jsonl
                ACHK_RESULTS_JSONL=_p26_achk_rows.jsonl
                --json-out _p26_gate_results.json
                ACHK_CONF_PROFILES IS NOT SET — §16c: a budget that truncates
                (vi) makes the verdict NOT-TESTABLE and a NOT-TESTABLE inferred
                pair is WITHDRAWN and blocks, so a capped run withdraws exactly
                what it could not probe.
  cap           launched at MemoryMax=8G; RAISED to 12G at 01:05 (recorded as a
                deviation, see below).
```

**The three phases, measured:**

```
  phase                       measured                       artefact
  corpus-index    223 971 dumps in 879 s (255 dumps/s),   _p26_achk_index.ckpt.jsonl
                  peak 3 487 MB                            223 972 rows, 73 MB
                  (RUNBOOK's estimate was ~50 min; it took 14 m 39 s)
  derive-probes   1 363 declarations in 783 s (1.74/s),   _p26_achk_derive.ckpt.jsonl
                  peak 5 663 MB                            one row per confined DECISION
                  -> 106 807 DISTINCT PROBES NEEDED
  probes          RUNNING. 8 441 of 106 807 (7.9 %) at    _p26_achk_probes.ckpt.jsonl
                  02:55:38, i.e. 2 h 14 m of probing.      429 MB at 7 001 probes
                  MEASURED, two windows:                   (~6.5 GB projected; 168 G free)
                    whole run  00:41:28 -> 02:55:38
                      8 205 probes / 7 930 s = 1.03/s
                    last 36 m  02:19:47 -> 02:55:38
                      1 400 probes / 2 151 s = 0.65/s
                  The second window is slower because two
                  OTHER endpoints (comments_index and
                  notifications_index) started heavy jobs
                  in the same 19G slice at ~02:35 — the
                  rate is contention-bound, not gate-bound.
  ETA             at 1.03/s  (106 807 - 8 441) / 1.03 = 95 500 s = 26.5 h
                  at 0.65/s                                = 42.0 h
                  -> between 2026-09-14 05:30 and 2026-09-14 21:00 UTC
```

**The measured cost is BETTER than §82.5's projection, and the reason is the
ProbeCache.** §82.5 summed the per-class budget and got 483 289 replays
(40-134 h at one slot); the gate actually needs **106 807 DISTINCT** probes for
the same 1 363 classes — 4.5x fewer — because probes are deduplicated across
classes that share a decision. At two slots that is ~26 h, i.e. at the
optimistic end of the projected band rather than beyond it.

**PASS / FAIL / NOT-TESTABLE so far: NONE, and that is structural, not a
delay.** `run_declared` is three phases in strict order — plan every probe
(no launches), `cache.execute()` every probe, THEN the verdict pass — and
`ACHK_RESULTS_JSONL` is written only in the third. `_p26_achk_rows.jsonl` is
therefore empty by construction until all 106 807 probes are done, and no
partial verdict distribution exists to report. The only evidence available
mid-flight is the probe checkpoint's row count. (Worth filing: a gate that can
produce no verdict for 24 h is checkpointed against a KILL but gives the
coordinator nothing to steer on; interleaving the verdict pass per class would
cost nothing, since the cache is already keyed per probe.)

**THE ONE REAL HAZARD, and its recovery.** Every one of the gate's three
checkpoints keys `_phase_keys`, which folds `_corpus_digest` — the name and size
of every `dump_*.json` in the batch directory. **This round's drives added 3 410
dumps to that directory** (223 971 -> 225 894 -> 227 381), and the external
session rewrote `assumption_checker.py` at 01:16:52, which moves the `engine`
key too. So **a relaunch of this gate today would find all three checkpoints
stale, rotate them to `.stale`, and start from zero** — losing the index
(15 min), the derivation (13 min) and every probe run so far. Two things follow:

1. **Do not kill this unit.** `systemctl --user status posts-p26-gate-20260913`
   to look; `systemctl --user stop posts-p26-gate-20260913` only if it must go.
2. If it must be restarted, the corpus digest is RECOVERABLE, because it is a
   pure function of the directory listing: move this round's dumps aside
   (`mkdir _p26_parked; mv dump_*P26A*.json dump_*P26B*.json dump_*P26C*.json
   _p26_parked/`), relaunch `bash _p26_gate.sh` (the checkpoints then replay),
   and move them back when the gate has passed its index phase. The
   `assumption_checker.py` rewrite cannot be undone that way — if its `engine`
   key has moved, the checkpoints are gone regardless, and the gate is a fresh
   26 h.

**DEVIATION, recorded.** The brief said cap 8G. At 01:05 the unit was at
6.70 G — 6.09 G of Python plus two JRubys still warming toward ~1.2 GB each —
so an OOM inside the unit was minutes away, and an OOM here is not "the probe in
flight" but the whole 26 h job (see the hazard above, the checkpoints could not
be replayed after the drives). `MemoryMax` was raised to **12G** with
`systemctl --user set-property --runtime`. The cage is unaffected:
`concolic-cov.slice` is still 19G, the box has 62G with ~50G free, and the
gate's worst case (12G) plus one census (6G) is 18G < 19G. Peak observed since:
8.0 G.

### §83.5 WHAT §83 SETTLES, AND WHAT IT DOES NOT

* **The OR-refined residue is drivable, and it is coming down.** Two booked
  rounds, 3 410 constructed runs, `13 942 -> 11 931 -> 10 863` under OR-refined
  and `8.4608e13 -> 8.2637e13` under §16b. 1.046 and 0.718 closed/run against a
  0.05 stop rule. §81.8's "driving cannot close it at any batch size" was a
  true statement about the §16b universe and a false one about the universe the
  endpoint actually runs under; §82 supplied the projection and §83 supplies
  the emission that makes it drivable.
* **Round 3 (P26C) is DRIVEN and EXPLAINED; its pass is QUEUED, not run.**
  1 039 runs are in the corpus (228 420 dumps) and booked per key
  (55.5 % walked). `posts-p26c-pass-20260913.service` is holding in the cage's
  own launch gate — `slice_free 5.0G, need 9.0G` — because comments_index and
  notifications_index took the slice to 15.6 G of 19 G at ~02:35. It is
  detached, checkpointed (`_cov_p26c2.ckpt.jsonl`) and polls every 30 s, so it
  fires by itself when the box frees; the round-3 remaining then needs one more
  `_p26_emit.sh P26R4 _snapshot_pruned_P26C2.txt`. **No round-3 delta is
  claimed here.** The three-round rate trend (§83.2) predicts it will be lower
  than 0.718 but nothing licenses a number before the census runs.
* **The endpoint is still NOT closed and NOT closer to licensed.** `MISSING`
  258 -> 236 -> 217 and gap-sets 320 -> 317 -> 311 are the checker's report on a
  demand that rests on 2 701 UNREPLAYED pairs. The bracket of §82.5 is
  unchanged in kind: until the gate finishes, `post-gate remaining` is between
  the OR-refined number and the §16b one.
* **The corpus tripwire is now live and has already retracted 187 licences** on
  1 923 runs. That is the mechanism working, and it is also a warning about the
  order of operations: every round of driving can withdraw pairs the gate is
  concurrently spending hours verifying. The gate is testing the P25OR pair set;
  187 of those pairs are already not licensed by the current corpus.
* **1 749 of 3 672 OR-refined region pieces have no Z3 model** (§83.1) — the
  component-product count and the full conjunction disagree on 37-48 % of the
  remaining mass. `REMAINING` is an upper bound. **OWNER CALL / `src/`
  question**, not touched here.
* **Unchanged:** `tree_complete` True, `tree_missing` [] , `foreclosures_
  provisional` False, `solver_lost` 0, `unevaluable_exprs` [], `bounded_cliques`
  0, `confinement_provisional` False, `NODES=137`.
* **The D1 comments family is still the only contradicted family** (373 / 355
  first-failing literals, 0 base relaxations in either round): no profile in a
  47 893-profile corpus takes a comments length both ways. §80.13's owner call
  stands, on a corpus now 24 % larger than when it was raised.

### §83.6 ARTEFACTS OF §83

```
_p26_emit_or.py         the missing tool — _p25_confcensus.py's universe and
                        projection with the emit caps OPEN, + an ALSO_16B
                        count-only census so every round is booked twice
_p26_emit.sh            its wrapper (detached, verdict P26-EMIT-OK)
_p26_gate_classes.py    2 701 inferred pairs -> 1 363 class representatives
_p26_gate_classes{,_meta}.json
_p26_gate.sh            the gate launcher, all five checkpoints wired
_p26_rebuild.sh         gaps-bootstrap -> FRESH index -> gaps -> construct
_p26_pass.sh            _p15_pass.sh's stages with the confinement knobs EXPLICIT
_p26_enum_P26R{1,2,3}.{log,json}      the three censuses
_p26_emit_P26R{1,2,3}.json.jsonl      1 923 / 1 487 / 1 039 streamed cubes
_p26_pairs_P26R{1,2,3}.json
_p26_index_P26{A,B,C}.pkl · _p26_gaps_P26{A,B,C}.json · _p26_parts_P26{A,B,C}.json
_p15_seedsP26{A,B,C}_*.json · _p15_manifest_P26{A,B,C}.json
_p26_construct_P26{A,B,C}.log · _p26_explain_P26{A,B}.{json,log}
_cov_FINAL_P26_20260913.json · _cov_FINAL_P26B2_20260913.json
_cov_p26.ckpt.jsonl · _cov_p26b2.ckpt.jsonl
_footprints_P26.json · _footprints_P26B2.json
_snapshot_pruned_P26.txt (47 253) · _snapshot_pruned_P26B2.txt (47 893)
_p26_ckptgaps_P26.json (classify FAILED: IndexError, the parts file holds only
                        the 320 sets that emitted cubes, not all 836 — the
                        four-way booking in §83.3 was done directly off the two
                        checkpoints instead, which is the same evidence)
_p26_achk_{index,derive,probes}.ckpt.jsonl · _p26_achk_rows.jsonl · _p26_gate.log
corpus 223 971 -> 227 381 dumps (+3 410 constructed runs, 0 toxic, 0 aborts)
```

* No `src/` edit, no `targets.rb` or shared-boundary edit, no declaration, no
  extraction, no policy, no git, nothing written under `notifications_index/`
  (its `_c11_classes.py`, `_c10_gate_all.sh` and `_gate_classes_ALL.json` were
  READ). `_p15_pass.sh`, `_p23_enum.py`, `_p23_construct.py`, `_p23_index.py`,
  `_p23_gaps.py`, `_p25_confcensus.py` and `coverage_report.py` are unchanged;
  every P26 tool is a new file. `_p15_classify.py` and `_p15_explain.py` (which
  run `main()` at import) were RUN, never imported.
* The `src/` changes recorded in §83.3(*) were made by ANOTHER session, not by
  this one.

### §83.7 HOW TO CARRY THIS ON (handoff)

```
  RUNNING NOW
    posts-p26-gate-20260913.service   the confinement gate, 8 441 / 106 807
        probes. LOOK:  systemctl --user status posts-p26-gate-20260913
                       tail -f reports/diaspora/results3/posts_show/_p26_gate.log
                       wc -l reports/diaspora/results3/posts_show/_p26_achk_probes.ckpt.jsonl
        STOP:  systemctl --user stop posts-p26-gate-20260913
        RESUME:  bash reports/diaspora/results3/posts_show/_p26_gate.sh
                 inside a systemd-run unit (see the header of that script) —
                 BUT read §83.4's hazard first: the three checkpoints key the
                 corpus digest and the checker's source, and BOTH have moved
                 since 00:08.
        WHEN IT FINISHES: `RESULT: N distinct tested — PASS .. FAIL .. ERROR ..
                 NOT-TESTABLE .. NOT-COMPARABLE ..` in _p26_gate.log, rows in
                 _p26_achk_rows.jsonl, full verdicts in _p26_gate_results.json.
                 Then expand class -> members with _p26_gate_classes_meta.json
                 (the `covers` count per class), write the non-PASS pairs to
                 `_confinement_withdrawn.json`, and the NEXT pass picks them up
                 automatically (coverage_report.py already reads that file,
                 §82.2) — a withdrawn pair reverts its demand toward §16b.
    posts-p26c-pass-20260913.service  round 3's coverage pass, holding for 9G.

  THE LOOP, one command per stage (TAG = the next letter)
    1  bash _p26_emit.sh   P26R<n> _snapshot_pruned_<prev pass tag>.txt   (cage 6G)
    2  bash _p26_rebuild.sh P26<X> _p26_emit_P26R<n>.json.jsonl _snapshot_pruned_<prev>.txt
    3  SEEDSET=P26<X> DRIVE_PAR=2 CONCOLIC_SLOTS=4 \
       P15_MANIFEST=.../_p15_manifest_P26<X>.json bash _p15_drive.sh P26<X> 200
    4  P15_TAG=P26<X> P15_SET=P26<X> P15_GAPS=_p26_gaps_P26<X>.json \
       P15_MANIFEST=_p15_manifest_P26<X>.json python3 -u _p15_explain.py
    5  STAMP=20260913 PASS_CAP=9G bash _p26_pass.sh P26<X>2 P26<X> _snapshot_pruned_<prev>.txt
    then 1 again. Every stage detached in its own systemd unit under
    concolic-cov.slice, every long one checkpointed, judged by its verdict line.
```
