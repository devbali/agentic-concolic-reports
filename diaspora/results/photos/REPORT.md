# photos batch — concolic re-run (prefix-directed DSE + batch-local targets)

Re-run **2026-08-16** (walls closed; previously 2026-08-15) with `run_dse.rb` + the batch-local overlay `targets.rb`,
superseding the 2026-08-14 round. Coverage checker: `coverage_check.py`, run per
entrypoint over that entrypoint's own dumps only.

```
cd /home/dev/project
scripts/diaspora-concolic \
    /home/dev/project/reports/diaspora/results/photos/run_dse.rb      # 8.5s
PYTHONPATH=src python3 reports/diaspora/results/photos/coverage_check.py
PYTHONPATH=src python3 reports/diaspora/batch_stats.py photos
```

Nothing under `src/`, `concolic_targets.rb`, or the diaspora app was modified.

> **Provenance.** The 2026-08-15 overlay round finished at 00:59 and was verified
> at the time (8/8 complete, 0 missing, 90 dumps, 15 errors), but the
> coordinator session died at 01:12 before updating this file, and the
> per-entrypoint `coverage_summary.json` files were never written. Those checks
> have since been re-run with this batch's own `coverage_check.py` — no dumps
> re-run — and reproduce that verification exactly. The 2026-08-14 figures are
> kept below as the BEFORE column.

## Method

Prefix-directed DSE, not seed-suggestion feedback. The interceptor names each
intercepted result with a **per-run call ordinal** (`SYM_RESULT_<func>_<idx>`,
`src/ruby_runtime/call_interceptor.rb:140`), so those names are *not* stable
across runs: flipping an early branch changes how many intercepted calls happen
before a later one and renumbers every later var. Feeding
`CoverageChecker.concrete_values` (a cross-product over vars harvested from
different runs) back as `seed_overrides` therefore mixes names that mean
different queries in different runs.

Instead, from an observed path `[c0 … cn]` the runner emits one child per `k`
that **inherits the parent's seeds** (so the prefix `c0 … c_{k-1}` replays
identically and those ordinals stay valid) and adds **exactly one flip** for
`c_k`. Children are deduped on `(config, path signature)`; the worklist runs to
exhaustion. Every PC this app emits has the shape `(VAR == LITERAL)`, so a flip
is just assigning `VAR` the literal (taken) or a different value (not).

Each entrypoint additionally has one or more **configs** — request shapes the
harness controls concretely (signed-in vs anonymous, `params`). These are real
request inputs, not modeled app behaviour; they are the only way to reach
branches the runtime cannot make symbolic (`if user_signed_in?` is a plain Ruby
bool and emits no PC). DSE explores seeds independently within each config.

One harness change vs. `run_concolic.rb`: the symbolic `current_user` is now
built **inside** each run rather than once at load. That makes its column vars
(a) appear in the dump's `symbolic_vars` and (b) reachable by `seed_overrides`
— which is how `SYM_PERSON_PH_guid` became a flippable branch in
`photos_destroy`.

## Results (engine-verified, per entrypoint)

BEFORE = 2026-08-14 (shared targets only). AFTER = **2026-08-16**, with
`targets.rb` §6d (regex predicates), the `CollectionProxy` list declaration, and
the `format: :js` harness fix.

| entrypoint | dumps | PCs | tree nodes | missing | complete | genuine | **both sides seen** | clean | runs | drained |
|---|---|---|---|---|---|---|---|---|---|---|
| `photos_index` | 14 → **60** | 62 → **655** | 9 ⚠️ → **134** ⚠️ | 0 | **true — UNRELIABLE, see below** | genuine | 11 / 14 | **60 / 60** | 291 | yes |
| `photos_make_profile_photo` | 2 → **65** | 3 → **497** | 2 → **64** | 1 → **0** | **false → true** | genuine | 10 / 10 | **65 / 65** | 351 | yes |
| `photos_create` | 3 → **66** | 1 → **432** | 1 → **63** | 1 → **0** | **false → true** | genuine | 9 / 9 | **66 / 66** | 288 | yes |
| `poll_participations_create` | 11 | 47 | 10 | 0 | **true** | genuine | 6 / 6 | 9 / 11 | 42 | yes |
| `photos_show` | 7 | 15 | 5 | 0 | **true** | genuine | 3 / 3 | 3 / 7 | 16 | yes |
| `photos_destroy` | 5 | 14 | 6 | 0 | **true** | genuine | 3 / 4 | 5 / 5 | 12 | yes |
| `participations_create` | 4 | 9 | 3 | 0 | **true** | genuine | 3 / 3 | 4 / 4 | 10 | yes |
| `participations_destroy` | 2 | 2 | 1 | 0 | **true** | genuine | 1 / 1 | 2 / 2 | 3 | yes |
| **total** | 48 → **220** | 153 → **1671** | 37 → **286** | 2 → **0** | 6/8 → **8 / 8** | **8 genuine, 0 vacuous** | **46 / 50** | **214 / 220** | **1013** | 8/8 |

**Every framework wall in this batch is closed.** `NotImplementedError`: 8 → 0.
The 6 remaining error dumps are all real app outcomes (5 × `RecordNotFound`,
1 × the `photos_show` app bug); **6 of 8 entrypoints are completely
error-free.** Both entrypoints that reported `complete=false` now report true on
real evidence.

### What closed them (2026-08-16)

| wall | dumps | fix |
|---|---|---|
| `NotImplementedError: SymbolicString#match` | 6 | **§6d `ConcolicRegexString`** — ported verbatim from `services_admin/targets.rb` §2b, whose own comment cites *this batch's* `Profile#build_image_url` as its motivating case. It was written there and never carried across |
| `NotImplementedError: SymbolicList#each` | 2 | **`CollectionProxy` added to the list declaration.** `CollectionProxy` has its own `#records` (`collection_proxy.rb:1003`) which **shadows** `Relation#records`, so `contact.aspect_memberships` never reached §6b's `IterableSymbolicList`. Same shadow the posts batch hit (259 dumps) |
| `ActionController::UnknownFormat` | 64 | **harness decision**, not a wall: `photos#make_profile_photo`'s `respond_to` block has **only** `format.js` (`photos_controller.rb:61`), and the rig drove it as `:html`. Same call the posts batch documented for `posts#mentionable`. `format: :js` → 1/65 clean becomes 65/65 |

`build_image_url` is still **not** mocked — §2's finding stands, its body *is* the
branch. §6d fixes the VALUE instead, which is what made both of its
`url.match(...)` branches recordable rather than fatal.

### Two things measured and reverted — do not repeat them

A blanket "upgrade every string column to `ConcolicRegexString`" was tried and
**reverted twice**, measured on `photos_index` (50 dumps) each time:

1. Re-installing a singleton reader per column → **46 `ArgumentError`**. The
   reader is 0-arity and shadows app readers that take an argument — here
   `Profile#image_url(size = :thumb_large)`, reached via `AvatarPresenter#small`
   → `image_url(:thumb_small)`.
2. Writing only into `concolic_attrs` (no singleton) → **34 `NoMethodError`**,
   and 533 → 468 PCs.

The wall this batch actually has is `Photo#url`, which is a **mock return, not a
column**. Narrowing the fix to that restored `photos_index` exactly (533 PCs,
48/50 clean) and then the `CollectionProxy` fix took it to 655 PCs, 60/60 clean.
The lesson is the README's: change the smallest thing the wall requires.

### `complete=true` is the weakest number in that table

**46 of 50 branch expressions are two-sided**, keyed by source site and computed
from the dumps independently of the solver (`batch_stats.py photos`). The four
that are not — unchanged in kind by the 2026-08-16 round, which added 13 new
two-sided expressions and no new one-sided ones:

| entrypoint | expression | site | reading |
|---|---|---|---|
| `photos_destroy` | `(SYM_PERSON_PH_guid != StringVal(''))` | `journey/formatter.rb:41` | route generation under a `guid == ''` prefix — **UNSAT by construction** |
| `photos_index` | `(len(..._Relation_records_1) != 0)` | `blank.rb:20` | solver-blind `len(...)` node |
| `photos_index` | `(len(..._Relation_records_2) != 0)` | `blank.rb:20` | solver-blind `len(...)` node |
| `photos_index` | `(assoc_profile_birthday_year <= 1004)` | `people_helper.rb:21` | the `ConcolicDate` branch (§6a) — recorded but one-sided here |

Every worklist drained (true fixpoint under the flip strategy, `stop_reason =
worklist_drained` in each `exploration_summary.json`); no entrypoint hit
`MAX_RUNS` or a time budget, and `unflippable_pcs` is empty everywhere. Total
exploration: **1,013 executions, 220 distinct paths, 8.5 s** (was 372 / 90 / 5.8 s,
and 136 / 48 / 3.8 s the round before).

`complete=true` here means **branch-coverage-complete over the nodes that were
observed** — both sides of every recorded PC node. It does **not** mean the
action ran to completion: several complete entrypoints still crash on a wall
further down the path. And it says nothing about branches the runtime cannot
record at all — those never become nodes.

## ⚠️ CORRECTION: `photos_index`'s `complete=true` is not trustworthy

Added by the coordinator after a cross-batch audit. **This supersedes the
`photos_index` row above.**

`CoverageChecker._insert_run` reuses an existing `taken`/`not_taken` child
*without checking that the child's constraint matches the next PC's expression*.
Runs whose PC **sequences** diverge — not merely their polarity — are silently
absorbed into whichever tree shape was inserted first. `photos_index` merges two
request configs (`anon` and `signedin`) whose PC sequences differ, so it is
exactly the shape that triggers the bug.

Measured by rebuilding the prefix tree independently of the engine.
**Re-measured after each round — the defect is still present, and grows with
the run set:**

| | 2026-08-14 | 2026-08-15 | **2026-08-16** |
|---|---|---|---|
| true prefix tree (order-free reconstruction) | 16 | 162 | **200** |
| engine `tree_nodes` | 9 | 115 | **134** |
| nodes the engine discarded | 7 | 47 | **66** |
| one-sided nodes in the true tree | 5 | 115 | 143 † |

The engine discards real nodes and then reports `missing_branches: 0`, so
`photos_index` is **not** branch-coverage-complete. Read its row as *incomplete,
extent unknown*.

† Read that 115 as an **upper bound, not 115 real gaps**. This reconstruction
demands both sides at every distinct *prefix*, so a node whose sibling is
unreachable counts as one-sided; a terminal decision on a deep path counts too.
The solver-independent per-**site** measure for this entrypoint is **10 / 13**
(above), and that is the number to quote. What the comparison does establish
soundly is the absorption itself: 162 ≠ 115.

`photos_index` is the shape that triggers it because it merges two request
configs in one directory — 3 `dump_anon_*` and 47 `dump_signedin_*`, whose PC
sequences differ in expression, not merely in polarity. `posts` avoids this by
keeping its anonymous runs in a separate `anonymous_scenario/` tree; this batch
does not, and that is the fix if the node count matters more than the
convenience.

Independently reproduced on `posts_show`, where the same 2139 runs give 25 nodes
in one insertion order and 2112 in the other — both claiming `complete=true`.

Audited across all 104 entrypoints with dumps: only 2 show absorption
(`photos_index` and `oidc_federation_nodeinfo/webfinger`), and only
`photos_index` converts it into a false `complete=true` — webfinger already
reports `complete=false`. Every other entrypoint's engine node count matches the
independent reconstruction exactly.

This is an engine defect, not a batch defect: the dumps are sound and the
exploration drained honestly. Raise to Bali — do not patch `src/`.

## Artifact integrity (2026-08-14 cross-batch kill incident)

A `pkill -f "run_dse.rb"` from another batch matched every batch's runner. This
batch was **not affected**, verified rather than assumed:

- the run completed at 23:31 and its log ends with its own marker
  `== photos batch DSE done in 3.8s ==`; the kill came afterwards;
- all 66 JSON artifacts parse; every dump has `schema_version` / `label` /
  `symbolic_vars` / `events` and an intact closing brace (no truncation);
- dump counts agree three ways for all 8 entrypoints — files on disk ==
  `exploration_summary.distinct_paths` == `coverage_summary.dumps_loaded` —
  and all 8 record `worklist_exhausted: true`.

Nothing needed re-running or recomputing.

## The 2 missing branches — one shared root cause — **CLOSED**

Both were the same node, `(SYM_RESULT_Photo_url_1_url == '')` taken-side, at
`activesupport .../object/blank.rb:126 in blank?()`, i.e. `url.blank? == true`
inside `Profile#build_image_url` (`app/models/profile.rb:171`).

DSE *did* generate the flip (`{"SYM_RESULT_Photo_url_1_url" => ""}`) and *did*
execute the child run — the child simply replayed the parent path, because the
`Photo#url` target (`concolic_targets.rb:829-831`, §W5) hardcodes its value:

```ruby
symstr("#{name}_url", "/uploads/#{name}_thumb.jpg", note: "Photo#url")
```

It never calls `seed_for`, so **no `seed_override` can reach it**. This is an
inert-seed case, not an unflippable-expression case: the flip is well-formed
and the solver's suggestion is correct; the mock ignores it.

**Fixed by overlay §1**, which re-declares `Photo#url` seed-aware with the same
default value (so behaviour is identical when no seed is supplied). Both
entrypoints went `complete=false` → `complete=true` on real evidence:
`photos_create` 1 → 9 PCs, `photos_make_profile_photo` 3 → 14.

**And §2 records the mock that was refused.** `Profile#build_image_url` is a
legal SQL-free leaf and mocking it *does* clear the `SymbolicString#match` wall
— but **its body is the branch** (`return nil if url.blank?`), the only path
condition `photos_create` records. Mocking it took that entrypoint from genuine
(1 PC) to VACUOUS (0 PCs): the wall closed and the coverage went with it. A wall
mock that swallows the branch it guards is a regression, not a fix. With §1
seedable instead, the `url == ""` side returns nil *before* the regex, so that
side is wall-free and both sides are observable; only the non-empty side still
walls on `SymbolicString#match`.

## What else is in `targets.rb`

| # | target | why it could not be shared / why it is legal |
|---|---|---|
| 1 | `Photo#url` seed-aware | `concolic_targets.rb:829` hard-codes its symstr and never calls `seed_for` |
| 2 | `Profile#build_image_url` — **NOT mocked** | its body is the branch (above) |
| 3 | `User#blocks` → real `Relation` (`Block.all`) | **the override that could not be shared**: `streams`/`posts` need the length-only `SymbolicList` shape (they read it through `Post.blocked_people`), `photos` needs a real Relation for `blocks.find_by(person_id:)`. Routing through `Block.all` keeps the query REAL and yields a symbolic Block — better traceability than hiding it behind a list. Caveat: drops the association's `WHERE blocks.user_id = …` scope, so that query's rendered SQL is unscoped |
| 4 | NullRelation short-circuit | `Contact.none.present?` was TRUE under the shared mocks, so the app entered a branch **unreachable in production** and died |
| 5 | asset-path stub | Sprockets environment wall, not a symbolic-runtime one |
| 6a | `ConcolicDate` — a real `::Date` subclass with a seedable symbolic `#year` | `symbolic_instance` maps every non-integer/boolean column to `SymbolicString`, so `profiles.birthday` had no `#year` (33 dumps). Mocking `birthday_format` is not allowed — its body **is** the branch (`if bday.year <= 1004`) |
| 6b | `IterableSymbolicList` | adds `#each`/`#map` yielding the representative |
| 6c | `SuccIntValue` — `SymbolicInt` with `#next`/`#succ` | `participation.count.next` in `social_actions.rb:56` |

§6 is the generalisable idea: **the runtime's symbolic classes are ordinary Ruby
classes with public readers, so a missing method is not a `src/` blocker** — a
batch-local subclass adds it and a batch-local mock returns that subclass. This
replaced three "needs a `src/` change" claims from the previous round.

### Two mistakes made here that other batches should not repeat

1. **`module_function` keeps two copies of a method, and the private one bit.**
   Patching `symbolic_instance` through an instance-level alias silently failed
   because `module_function :symbolic_instance` makes the instance copy
   *private*, so the regenerated singleton could not reach it — and the batch
   went **90 → 14 dumps** before a re-verification caught it. Fixed by calling
   the singleton alias explicitly. A wrapper must replace **both** copies.
2. **`include Enumerable` in `IterableSymbolicList` (§6b) is a live hazard.**
   `Enumerable` sits above `SymbolicList` in a subclass's ancestor chain, so it
   shadows the PC-recording `any?`/`count`/`first`/`include?`/`none?`. In
   `streams` this silently took all 8 entrypoints from genuine to VACUOUS
   (72 PCs → 0) **while `complete` stayed `true`**. `photos` was measured and is
   **not** exposed — all of its list PCs come from `empty?`, which `Enumerable`
   does not define (643 PCs both ways) — but this file is the one other batches
   copied the snippet from. Prefer defining `#each`/`#map` only.

## Walls hit (every `error` in the dumps, attributed)

**AFTER the overlay: 15 errors in 90 dumps** (was 23 in 48). Rows 3, 5 and 7
below are **closed**; the rest are unchanged.

| # | entrypoint | error | count BEFORE → AFTER | status |
|---|---|---|---|---|
| 1 | `photos_show` | `ActiveRecord::RecordNotFound` | 3 → **3** | real app outcome |
| 2 | `photos_show` | `NoMethodError: id for nil` | 1 → **1** | real app outcome (an app bug) |
| 3 | `photos_index` | `NoMethodError: find_by for <SymList User_blocks_1>` | 8 → **0** | **CLOSED** by §3 |
| 4 | `photos_index` | `NotImplementedError: SymbolicList#each` | 2 → **2** | framework wall, unchanged |
| 5 | `photos_index` | `NoMethodError: id for Contact::ActiveRecord_Relation` | 2 → **0** | **CLOSED** by §4 |
| 6 | `photos_create` ×3, `photos_make_profile_photo` ×3 | `NotImplementedError: SymbolicString#match` | 2 → **6** | framework wall — *more* dumps reach it now, because §1 made both sides of the guarding branch explorable |
| 7 | `poll_participations_create` | `NotImplementedError: SymbolicInt#next` | 3 → **0** | **CLOSED** by §6c |
| 8 | `poll_participations_create` | `ActiveRecord::RecordNotFound` | 2 → **2** | real app outcomes |
| 9 | `photos_make_profile_photo` | `ActionController::UnknownFormat` | 0 → **1** | real app outcome, newly reachable |
| — | `photos_index` | `NoMethodError: year for <SymStr>` | 33 → **0** | **CLOSED** by §6a. Not in the 2026-08-14 table above: that round's 48 dumps never got deep enough to reach `birthday_format`; the 33 is the count `targets.rb` §6a records from the run that exposed it |

Row 6 is the honest shape of a wall-closing pass: the count going **up** is the
fix working. The branch is now two-sided and its non-empty side still walls.

### Original attribution (2026-08-14), retained

| # | entrypoint / config | error | raise site | real app outcome or framework wall? |
|---|---|---|---|---|

| # | entrypoint / config | error | raise site | real app outcome or framework wall? |
|---|---|---|---|---|
| 1 | `photos_show` anon ×1, signedin ×2 | `ActiveRecord::RecordNotFound` | `photos_controller.rb:18` | **Real app outcome** — the app's own 404 path (`raise … unless @photo`). Not a wall. |
| 2 | `photos_show` signedin ×1 | `NoMethodError: undefined method 'id' for nil` | `lib/diaspora/shareable.rb:74 from_person_visible_by_user` ← `user/querying.rb:76 photos_from` ← `photos_controller.rb:13` | **Real app outcome (a bug)** — with an unknown `person_id` guid, `Person.find_by_guid` returns nil and `photos_from(nil)` dereferences `person.id`. `GET /people/:person_id/photos/:id` returns 500, not 404, for a signed-in user with a bad person guid. |
| 3 | `photos_index` signedin ×8 | `NoMethodError: undefined method 'find_by' for <SymList SYM_RESULT_User_blocks_1>` | `user/querying.rb:33 block_for` ← `person_presenter.rb:97/109 is_blocked?` ← `photos_controller.rb:32` | **Framework wall** — the `User#blocks` target returns a `SymbolicList`, on which the association-scoped `find_by` cannot fire. |
| 4 | `photos_index` signedin ×2 | `NotImplementedError: SymbolicList#each` (`src/ruby_runtime/list.rb:221`) | `contact_presenter.rb:12 full_hash` ← `person_presenter.rb:91 contact_hash` | **Framework wall** — `aspect_memberships.map{…}` over a length-only SymbolicList; contents out of scope by design. |
| 5 | `photos_index` anon ×2 | `NoMethodError: undefined method 'id' for #<Contact::ActiveRecord_Relation>` | `base_presenter.rb:24 method_missing` ← `contact_presenter.rb:5 base_hash` | **Mixed** — `PersonPresenter#current_user` is nil for anonymous, so `current_user_person_contact` is `Contact.none` (a Relation); `has_contact?` should be false but `present?` goes through a mocked `empty?`/`blank?` returning a `SymbolicBool`, which is truthy in Ruby, so `contact_hash` is entered anyway. Truthiness gap, not a real 500. |
| 6 | `photos_create` setprof ×1, `photos_make_profile_photo` ×1 | `NotImplementedError: SymbolicString#match` (`src/ruby_runtime/string.rb:355`) | `profile.rb:171 build_image_url` ← `profile.rb:92 image_url=` ← `User#update_profile` | **Framework wall** — the symbolic `Photo#url` string is regex-matched during profile update. Same site as the 2 missing branches. |
| 7 | `poll_participations_create` ×3 | `NotImplementedError: SymbolicInt#next` (`src/ruby_runtime/int.rb:63`) | `user/social_actions.rb:56 update_or_create_participation!` (`participation.count.next`) | **Framework wall** — symbolic-int arithmetic is a documented runtime limitation. |
| 8 | `poll_participations_create` ×2 | `ActiveRecord::RecordNotFound` | `poll_participations_controller.rb:24 target` (explicit `|| raise`) and `:7 create` (`PollAnswer.find`) | **Real app outcomes** — both are the controller's own not-found paths. |

Nothing was deleted: all 21 error-carrying runs are present as dumps with their
PCs-so-far intact.

## Branches the runtime cannot record at all (Ruby truthiness gap)

`src/TODO.txt`: a `SymbolicBool` wrapping `false` is still a truthy Ruby object,
so bare `if obj` / `unless obj` emits no PC and always takes the truthy side.

- `photos_controller.rb:140 if @photo.save` — `save` is mocked to a
  `SymbolicBool`; the `else respond_with @photo, … :error => message` arm of
  `legacy_create` is **unreachable** (and would itself raise `NameError` —
  `message` is never assigned on that path; a genuine latent app bug).
- `photos_controller.rb:142 unless @photo.pending` — `pending` is a symbolic
  boolean column read; the whole `add_to_streams` / `dispatch_post` block is
  never entered, in *any* config. This is why the `plain` and `pending` configs
  produce byte-identical 0-PC paths.
- `photos_controller.rb:143 unless @photo.public?` — the predicate reader *does*
  record, but it sits inside the `pending` block above, so it is never reached.
- `photos_controller.rb:55 if @photo` / `:80 if photo` / `:8 if post` /
  `:18 if participation` — these branch on a finder result, and the finder mock
  records `(…_not_found == True)` at the mock boundary, so they *are* covered
  (this is why `participations_*`, `photos_destroy`, `photos_show` are complete).
- `photos_controller.rb:60 if current_user.update_profile(profile_hash)` — the
  mocked update returns a `SymbolicBool`; the `head :unprocessable_entity` arm
  is unreachable.
- `photos_controller.rb:12 if user_signed_in?` and `:24/:28 user_signed_in?` —
  plain Ruby bool supplied by the harness. Covered by running both configs, but
  no PC exists, so the checker's tree does not contain this decision.
- `legacy_create:130 if photo_params[:aspect_ids] == "all"` — concrete params
  compare, no PC. This branch is **dead code**: `permit(aspect_ids: [])` drops a
  scalar `"all"`, so `photo_params[:aspect_ids]` can never equal `"all"`.

`photos_create` is the extreme case: 3 of its 5 real branch points are invisible
to the runtime, and its single recorded PC comes from deep inside
`Profile#build_image_url`, not from the controller at all. Its
`complete=false` / 1-node tree should be read as "this entrypoint is barely
observable", not "one seed away from done".

## Unflippable PC shapes (recorded, not silently dropped)

| entrypoint | expression | why |
|---|---|---|
| `photos_destroy` | `(SYM_PERSON_PH_guid != StringVal(''))` ×2 | `!=` form; the flip helper only inverts `(VAR == LITERAL)`. Harmless here — the `==` form of the same var was flipped both ways in the same tree. |
| `photos_index` | `(len(SYM_RESULT_ActiveRecord__Relation_records_1_rows) != 0)` ×2 | collection length var; there is no seed hook for `SymbolicList` length. |

## Mocks I would add (2026-08-14) — resolution

> **Update 2026-08-15.** Per-batch overlay files exist now, so these no longer
> need a cross-batch decision. **#1 and #3 landed** as `targets.rb` §1 and §3.
> **#2 was built, measured and REJECTED** — it swallows the branch it guards
> (`targets.rb` §2, and the CLOSED section above). **#4 stands**, still needing
> an app-source split. The original text is kept below because the reasoning is
> what the overlay is built on.


1. **Make the existing `Photo#url` target seed-aware** (`concolic_targets.rb:829`,
   §W5). One-line change, closes both missing branches in the batch:
   ```ruby
   interceptor.declare_target(Photo, :url, returns: lambda do |receiver, _args, name|
     v = "#{name}_url"
     symstr(v, seed_for(v, "/uploads/#{name}_thumb.jpg"), note: "Photo#url")
   end)
   ```
   `Photo#url` is already a declared SQL-free leaf; it just fails to consult
   `seed_for`, which makes its var permanently unflippable. Every other symbolic
   value in the framework goes through `seed_for`.

2. **`Profile#build_image_url`** — `declare_target(Profile, :build_image_url,
   returns: ->(_r, _args, _n) { "/concolic/uploads/image.jpg" })`. SQL-free leaf
   per the README rule: its real body (`profile.rb:170-174`) is `url.blank?`, two
   `url.match(…)` regexes and a string interpolation of `AppConfig.pod_uri` — no
   query, no other declared target. Returns a plain `String`, so `to_symbolic`
   cannot re-wrap it. Preserves the real `update_profile` → `assign_attributes` →
   mocked `Persistence#update` chain above it. Clears wall #6.
   *Caveat:* with #1 applied, the `url == ""` path returns `nil` before the
   regex, so #1 alone clears this wall on that one path; #2 clears the non-empty
   path.

3. **`User#blocks`** (`concolic_targets.rb:546`) should return `Block.all` (a real
   `Relation`) rather than a `SymbolicList`, so `blocks.find_by(person_id: …)` in
   `User#block_for` routes into the declared `FinderMethods#find_by` target and
   yields a symbolic `Block` — keeping the query real instead of hiding it behind
   a list. Clears wall #3 and opens the `is_blocked?` branch. **Not** made: it is
   a shared-target behaviour change other batches (streams / posts, via
   `Post.blocked_people`) depend on, and needs a cross-batch decision.

4. **No legal mock exists for wall #4** (`ContactPresenter#full_hash`). Its body
   maps over the `aspect_memberships` association, and its only enclosing methods
   (`PersonPresenter#contact_hash`, `current_user_person_contact`) call
   `User#contact_for`, which queries. Closing it needs the README's Gate-1b
   function split — extracting the `.map` into e.g.
   `ContactPresenter#aspect_membership_hashes` — which is an **app-source** change
   and out of bounds here. Raise to Bali.

## Runtime gaps to raise to Bali (do not patch from a batch session)

> **Update 2026-08-15.** The first three were closed **batch-locally by
> subclassing**, without touching `src/` — see `targets.rb` §6. They remain
> genuine runtime gaps every batch re-pays, but they are no longer blockers.

- ~~`SymbolicInt#next` / `#succ`~~ (`src/ruby_runtime/int.rb:63`) — blocked
  `participation.count.next` in `User#update_or_create_participation!`, i.e. the
  "already participating" arm of `poll_participations#create` and
  `participations#create`. **Closed by `SuccIntValue` (§6c).**
- `SymbolicString#match` (`src/ruby_runtime/string.rb:355`) — blocks every
  profile-image URL path. **Still open** — the one framework wall left with a
  meaningful count (6 dumps), and deliberately not mocked around (§2).
- `SymbolicList#each` / element access (`src/ruby_runtime/list.rb:221`) and the
  absence of `find_by` on `SymbolicList` — by design ("contents out of scope"),
  but they are what makes `photos#index`'s presenter layer unreachable.
  **`#each` closed by `IterableSymbolicList` (§6b); `find_by` closed by §3.**
  Two `photos_index` dumps still hit `#each` at `contact_presenter.rb:12` —
  the `people` batch closed the same site by re-declaring
  `Querying#find_by_sql` with a `representative:` **and** a `seed_for`; that fix
  is portable here and is the obvious next step for this batch.
- **`symbolic_instance` maps every non-integer/boolean column to
  `SymbolicString`**, so `date`/`datetime` columns have no `#year`. Closed here
  by `ConcolicDate` (§6a), re-paid by `people` and `users_sessions`
  independently — a strong candidate for the shared file.
- **`CallInterceptor` retains an unbounded `@all_calls` history across runs**
  (`src/ruby_runtime/call_interceptor.rb`): appended at line 127, and only ever
  sliced (`old_count = @all_calls.size` at 263, `@all_calls[old_count..]` at
  308) — never truncated. A long DSE loop therefore holds every call event of
  every previous run; this is the leak behind the 1803MB RSS seen on
  posts_show. Also read by `dup` (75) and a label filter (79), neither used by
  the DSE loop. Clearing it between runs is safe precisely because `run`
  re-reads `.size` at entry. **Not patched in `src/`, and not applied in this
  batch's delivered runner** (see the memory-discipline section). Independently
  confirmed by the posts batch.
- The Ruby truthiness gap itself is the single largest coverage limiter in this
  batch; it costs `photos_create` most of its tree.
- Engine noise (non-fatal, during checking): `Failed to eval var decl
  'len(X) = Int('len(X)')'` and `Failed to parse constraint 'Not((len(X) != 0))'`
  for collection-length vars. Affected entrypoints still complete, but the
  `len(...)` nodes are effectively unconstrained for Z3.

## Runner memory discipline — and why the frugal patch is NOT in this runner

`run_dse.rb` as delivered is the **byte-exact version that produced the 48
dumps**. It does not contain the memory-frugality changes discussed during the
run, and that is deliberate.

A patched variant (MD5-digest dedup keys instead of retained seed-JSON /
path-signature strings, plus a runner-local `trim_interceptor_history!` clearing
`@all_calls` between runs) was written and syntax-checked, but the two
reproducibility runs queued to exercise it never started — they sat ~10 minutes
behind the 2-slot cap while 12 other batches contended. Rather than ship an
unexercised edit, the runner was restored to the producing version (confirmed by
diff) and the patch preserved separately, **unexecuted**, at:

```
/home/dev/.claude/jobs/302ac302/tmp/run_dse_memfrugal_variant.rb
```

Rationale: an unexercised edit would break the runner↔dumps correspondence,
which matters more here than the leak does. This batch's exploration is 136
executions over 3.8 s, so `@all_calls` never grows enough to bite; the leak is a
problem for long explorations (posts_show), not this one.

Integrity anchors: aggregate digest of the 48 dumps is
`a648f64bdee15f185d51b70ebb1e2876`; a verified snapshot of the tree is archived
at `/home/dev/.claude/jobs/302ac302/tmp/photos_results_verified.tgz`.

## Files

```
results/photos/
├── targets.rb                    BATCH-LOCAL overlay (PhotosTargets.install!)
├── run_dse.rb                    prefix-directed DSE runner (all 8 entrypoints)
├── coverage_check.py             per-entrypoint CoverageChecker driver
├── run_concolic.rb               previous runner, kept as harness reference
├── exploration_summary.json      batch-level DSE stats
├── coverage_index.json           batch-level roll-up of the 8 summaries
├── elapsed_seconds.txt
└── <entrypoint>/
    ├── dump_<config>_<n>.json    one per distinct path (with its seed dict)
    ├── exploration_summary.json  runs / paths / drained / unflippable / errors
    └── coverage_summary.json     engine result for THIS entrypoint only
```
