# REPORT — `notifications_tags` batch (re-run with per-batch targets overlay)

Date: 2026-08-15 · JRuby 9.3 + Java 21 · `ruby_examples/dse-apps/apps/diaspora`
(Rails 5.2.4.3) · `RAILS_ENV=concolic` · Runner: `run_dse.rb` · Overlay:
`targets.rb` · Checker: `coverage_report.py` (engine `CoverageChecker`, one
check per entrypoint directory, never merged across the batch).

Controllers driven: `notifications_controller.rb`, `tags_controller.rb`,
`tag_followings_controller.rb`.

## Headline — BEFORE vs AFTER the overlay

| | BEFORE | AFTER |
|---|---|---|
| Entrypoints | 9 | 9 |
| Dumps | 27 | **28** |
| Total path conditions | 16 | **20** |
| Tree nodes (checker) | 5 | 5 |
| Missing branches | 0 | 0 |
| Entrypoints `complete=true` | 9 / 9 | 9 / 9 |
| **Genuine (≥1 PC)** | **5 / 9** | **5 / 9** |
| **Vacuous (0 PCs — NOT covered)** | **4 / 9** | **4 / 9** |
| Dumps carrying an `error` | 7 | **0** |
| Crash families | 3 (A, B, C) | **0** |
| DSE worklists drained | 9 / 9 | 9 / 9 (no cap hit anywhere) |
| Wall-clock (exploration) | 1.9 s | 2.1 s |

**Every wall in this batch is closed. 28 dumps, zero errors, zero
`NotImplementedError`, zero `TypeError`.** All three crash families (A, B, C)
are gone, and none of them needed a change to `src/`.

Coverage moved where a wall was actually hiding a branch and did not move where
it was not:

- **tags#show: 4 → 8 path conditions, 5 → 6 dumps.** Closing wall C let the tag
  stream query execute for real, which reached `Post.excluding_blocks` and
  exposed a genuinely new branch (`people.any?`) that the DSE now flips both
  ways. This is the batch's one real coverage gain.
- **notifications#index: still 0 PCs.** Walls A, `pager.replace` and `group_by`
  are all cleared and the action now runs end-to-end through
  `NotificationSerializer` to `render` — but it records **no path condition**,
  because it genuinely has no branch on a symbolic value (see below). It is
  wall-free and still **VACUOUS**. Stated plainly, as instructed: clearing the
  wall did not make this entrypoint covered.
- Everything else is unchanged.

### Retraction

An earlier draft of this report concluded that walls A and C "need a `src/`
change" (a `SymbolicList` contents implementation and a
`value_for_database`/`quoted_id` hook on `SymbolicInt`). **That conclusion was
wrong and is withdrawn.** Both are fixable batch-locally: the runtime's symbolic
classes are ordinary Ruby classes with public readers, so a subclass in
`targets.rb` can add the missing method and a batch-local mock can return it.
Sections §3 and §4 of `targets.rb` are kept for their measurements, not their
verdicts; §5 supersedes them.

## Per-entrypoint results (AFTER; BEFORE shown where it differs)

| # | entrypoint | dumps | PCs | nodes | missing | complete | genuine / vacuous | drained | BEFORE → AFTER |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `GET /notifications` — notifications#index | 3 | **0** | 0 | 0 | true* | **VACUOUS** | yes | `NotImplementedError`×3 → **clean**, PCs 0 → 0 |
| 2 | `PUT /notifications/:id` — notifications#update | 4 | 4 | 1 | 0 | true | genuine | yes | `ActiveRecordError`×2 → **clean** |
| 3 | `GET /notifications/read_all` — notifications#read_all | 4 | 4 | 1 | 0 | true | genuine | yes | unchanged |
| 4 | `GET /tags` — tags#index | 3 | **0** | 0 | 0 | true* | **VACUOUS** | yes | unchanged |
| 5 | `GET /tags/:name` — tags#show | **6** | **8** | 1 | 0 | true | genuine | yes | `TypeError`×2 → **clean**, PCs **4 → 8**, dumps 5 → 6 |
| 6 | `GET /tag_followings` — tag_followings#index | 1 | **0** | 0 | 0 | true* | **VACUOUS** | yes | unchanged |
| 7 | `POST /tag_followings` — tag_followings#create | 3 | 2 | 1 | 0 | true | genuine | yes | unchanged |
| 8 | `DELETE /tag_followings/:id` — tag_followings#destroy | 2 | 2 | 1 | 0 | true | genuine | yes | unchanged |
| 9 | `GET /tag_followings/manage` — tag_followings#manage | 2 | **0** | 0 | 0 | true* | **VACUOUS** | yes | unchanged |

`*` complete only because the tree is empty.

**A vacuous entrypoint is NOT covered**, whatever `coverage_complete` says: the
checker has an empty tree, so "no missing branches" is trivially true. Entries
1, 4, 6 and 9 must be read as *unexplored*.

**All four vacuous entrypoints are now the same case: no symbolic branch to
record.** Before the overlay, notifications#index was vacuous *because it
crashed*; now it runs to completion and is vacuous *because the action has no
decision on a query result*. That is a far better-characterised result — the
open question ("what would it do past the wall?") is answered — but it is still
zero coverage.

- **notifications#index** — clean end-to-end. The full traversal is visible in
  the dump: `Calculations.count` → `Relation.to_ary` (via
  `WillPaginate::Collection#replace`) → `Calculations.count` →
  `Relation.records` (via `group_by`'s `each`) →
  `NotificationSerializer#note_html` → `render`. Its only decisions are
  `params[:type] && types.has_key?(...)` and `params[:show] == "unread"`, both
  on concrete request params.
- **tags#index, tag_followings#index, tag_followings#manage** — materialise a
  relation and serialise it (`@tags.to_json`, `tags.to_json`,
  `gon.preloads[:tagFollowings] = tags`). No branch on a query result.

Zero PCs is the correct and complete answer for all four, and no mock can change
that, because there is nothing to mock.

### A caveat on `tree_nodes` and `missing` — the checker under-reports here

`tree_nodes` stays at 5 even though tags#show now explores genuinely 2-deep
paths with both sides of both branches observed. That is an artefact of the
reference checker, not of the search, and it bounds how much weight
`complete=true` can carry.

`CoverageChecker._insert_run` (`src/concolic_engine/coverage.py`) inserts a
path's **last** PC as a `<leaf>` rather than as a decision node, and it fills a
child slot only when that slot is still `None`. So:

- a branch that is terminal on every path never becomes a node, and its
  unexplored side is never reported missing;
- worse, a SHORTER run inserted first plants a `<leaf>` that a LONGER run can
  then no longer extend, so the deeper PCs are dropped from the tree entirely.

Introspecting the final tags#show tree shows exactly one root whose two children
are both `<leaf>` — the `(len(...) != 0)` branch never entered the tree at all,
despite appearing on 3 of the 6 dumps with both sides taken.

**Consequence: read `missing=0` in this batch as "the checker found nothing to
flag", not as "every branch is closed".** The real evidence of coverage is the
dumps and their path signatures. Reported, not patched — it is in
`src/concolic_engine/`.

The branches actually recorded, per genuine entrypoint (both sides observed in
every case):

| entrypoint | path condition | origin |
|---|---|---|
| notifications#update | `(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)` | `Notification.where(recipient_id:, id:).first` — `if note` |
| notifications#read_all | `(SYM_RESULT_ActiveRecord__Calculations_count_1_count > 0)` | `current_user.unread_notifications.count > 0` |
| tags#show | `(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)` | `ActsAsTaggableOn::Tag.named(tag_name).first` — `return [] unless tag` |
| tags#show **(NEW)** | `(len(SYM_RESULT_Anonymous_blocked_people_1) != 0)` | `Post.excluding_blocks` — `if people.any?`, reached only once wall C was closed |
| tag_followings#create | `(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found == True)` | `ActsAsTaggableOn::Tag.find_or_create_by(name:)` |
| tag_followings#destroy | `(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found == True)` | `current_user.tag_followings.find_by_tag_id(params['id'])` |

tags#show's deepest path is now
`first_not_found:False | blocked_people_len!=0:True | blocked_people_len!=0:True`
— 3 PCs, reached by seeding `len(SYM_RESULT_Anonymous_blocked_people_1) = 1`,
which drives the real `where("posts.author_id NOT IN (?)", people)` SQL.

## The overlay — `results/notifications_tags/targets.rb`

Installed after the shared targets (`declare_target` is last-one-wins) and
loaded from `run_dse.rb`. Three things in it, and two deliberate omissions.

### 1. `ActsAsTaggableOn::Tag` constant load (moved in from the runner)

`Tag` in this app is the gem's namespaced model and is not autoloaded in the
concolic env; without it TagsController, TagFollowingsController and
`Stream::Tag` all raise `NameError`. Previously a runner-local `begin/rescue`;
now §1 of the overlay, where the batch's environment fixes belong.
Behaviour-identical (`ActsAsTaggableOn::Tag loaded (tags)` in both runs).

### 2. `update_column` / `update_columns` → `SymbolicBool` — closes wall B, buys 0 PCs

Appended to the shared §F instance-persistence list
(`concolic_targets.rb:503`), which omits them. Same SQL-free-leaf status §F
already grants `save`/`update`/`destroy`; the producing query
(`Notification.where(...).first`) still runs for real through the finder mock.

**Measured effect, exactly as the scratch probe predicted: the crash is gone,
and it adds zero path conditions.** `notifications#update` goes from 2 error
dumps to 0 and stays at 4 dumps / 4 PCs / 1 node. The reason is visible in the
dump's own call event:

```json
{"type": "symbolic_call", "target": "ActiveRecord::Base.update_column",
 "args": {"name": "unread", "value": false}, "lineno": 22,
 "function": "set_read_state"}
```

`set_read_state(read_state)` is `update_column(:unread, !read_state)` —
straight-line, and its argument is `params[:set_unread] != "true"`, a **concrete
Ruby boolean**, so `value` is a plain `false`, not a symbolic value. There is no
branch behind this wall. Worth having for a crash-free batch; **do not read the
cleared error as coverage.**

### 3. `WillPaginate::Collection#total_entries=` → nil — still NOT added, and no longer needed

This was the only SQL-free leaf enclosing wall A, and it was probed in a
throwaway scratch process. **Measured: it does not unlock notifications#index,
it RELOCATES the wall one line**, to `TypeError: can't convert
Notification::ActiveRecord_Relation to Array` at
`notifications_controller.rb:41` (`pager.replace(result)`), with
`@notifications.group_by` at line 43 waiting behind that.

A mock that relocates a wall without closing a branch is churn: it adds a mocked
call site, discards the honest stack trace that names the real gap, and buys
0 PCs while making the rig look more "fixed" than it is. **That judgement
stands** — and §5 removed the need for it entirely by fixing the VALUE instead
of intercepting the call. `total_entries=` now runs for real.

### 4. Wall C — superseded by §5

The previous conclusion ("no legal mock exists; needs a `src/` hook") was half
right: no legal *mock* exists, because both candidate enclosures
(`Stream::Tag#tag`, `StatusMessage.tag_stream`) issue SQL, and mocking
`Stream::Tag#tag` would have deleted the one genuine branch tags#show had —
precisely the photos `Profile#build_image_url` regression. **But the fix was
never a mock.** See §5a: the VALUE gets the method, and no call is intercepted.

### 5. Symbolic-shaped value objects — the actual wall fix (no `src/` change)

The runtime's symbolic classes are ordinary Ruby classes with public readers, so
a missing method is not a `src/` blocker: subclass it batch-locally and have a
batch-local mock return the subclass.

**5a. `ConcolicIntValue < SymbolicInt`** — closes walls A and C with one class:

- `#to_i` returns the concrete `value`. This is the *explicit* coercion
  `will_paginate/collection.rb:109` calls. `#to_int` is deliberately left
  raising, so the *implicit* coercion channel the runtime is guarding
  (`Array#[]`, `String#*`) is still caught. That is the narrow hole the gem
  needs and nothing more.
- `#value_for_database` (and `#quoted_id`) closes wall C. AR's
  `Quoting#quote` (`connection_adapters/abstract/quoting.rb:11-19`) does
  `value = value.value_for_database if value.respond_to?(:value_for_database)`
  before `_quote`, so the bind quotes as a plain integer while the Ruby-side
  value stays symbolic.

Wired in via a batch-local wrapper around `ConcolicTargets.symbolic_instance`
(the shared file is untouched) that rewrites integer/bigint columns in the
`concolic_attrs` hash the singleton readers close over — same var name, same
seed, same note. That is what makes `tag.id` quotable, since the value
originates *inside* `symbolic_instance`, not at a mockable call boundary.

**5b. `IterableSymbolicList < SymbolicList`** — `#each` / `#map` yielding the
existing `representative` once. notifications#index needs this for
`unread_notifications.group_by(&:type)` and the serializer's `map`. Yielding the
representative is the same "one sampled row" semantics `#first`/`#last`/`#[0]`
already implement, so this is consistency with the existing Gate 1b contract,
not new modelling.

> **Trap found the hard way — do NOT `include Enumerable` in this subclass.** A
> module included into a *subclass* is inserted BEFORE the superclass in the
> ancestor chain, so `Enumerable#any?`/`#none?`/`#first`/`#count` shadow the
> **PC-recording** `SymbolicList#any?`/`#empty?`/`#first`. Measured: with
> `include Enumerable`, tags#show silently LOST the `(len(...) != 0)` path
> condition — a coverage-destroying regression dressed as a convenience. The
> methods are defined directly instead. `photos/targets.rb` §6b currently has
> `include Enumerable` and is exposed to this.

**5b-ii. `SampledRowsArray < ::Array` (including `SymbolicVar`)** — for
`Relation#to_ary` only, and the reason is worth recording because it defeats the
obvious fixes:

- `to_ary` is Ruby's *implicit* conversion protocol; the interpreter
  type-checks the result, so returning a `SymbolicList` raises
  `TypeError: … #to_ary gives SymbolicList`. `Array#replace` (reached via
  `WillPaginate::Collection#replace`) is what demands it.
- Returning a plain `Array` does not work either: `declare_target`
  post-processes every mock result and `to_symbolic`
  (`src/ruby_runtime/symbolic_func.rb:165`) maps `Array` → `SymbolicList`,
  converting it straight back into the failing value. The shared file records
  this same dead end twice (`concolic_targets.rb:565`, `:576`: "the interceptor
  re-symbolises any Array return into a SymbolicList", worked around there by
  returning `nil`).
- The pass-through branch immediately above that check keeps anything that
  `is_a?(SymbolicVar)` untouched, **and it is tested first**. So the value class
  has to be both at once: a real `::Array` subclass that includes `SymbolicVar`.
  `SymbolicVar` contributes only `#sym_name`, `#caller_frame` and `#record!`, so
  no Array method is shadowed. Length still comes from the seedable
  `len(<name>_rows)` var; name and note keep SQL traceability.

**This is a general escape hatch for the whole "mock must return a real Array"
family**, including the two `nil`-returning workarounds already in the shared
file.

**5c. `ConcolicDate < ::Date`** — `datetime`/`date` columns are mapped to
`SymbolicString` by `symbolic_instance`, so `notifications.updated_at` had no
`#strftime` and notifications#index would have died at
`@group_days = @notifications.group_by {|note| note.updated_at.strftime(..) }`
(line 43 — the wall behind the wall behind wall A). A real `::Date` subclass
keeps `Date === obj`, `I18n.l` and `strftime` working while `#year` stays a
seedable `SymbolicInt`, so any `date.year <op> N` records a flippable PC instead
of crashing. Same shape as `photos/targets.rb` §6a.

### 6. `Post.blocked_people` made seed-aware — the batch's one coverage gain

Closing wall C let `Stream::Tag#posts` reach `Post.excluding_blocks`, which
produced a brand-new path condition in tags#show:

```
(len(SYM_RESULT_Anonymous_blocked_people_1) != 0)     # from `if people.any?`
```

…which the DSE initially could not close, for exactly the reason the addendum
flags as the highest-value pattern: `concolic_targets.rb:560` hard-codes `[]`
and never calls `seed_for`, so the var is **inert** — DSE emits the flip, the
mock ignores it, the path repeats and is deduped away.

The batch-local override keeps the default at length 0 (so `people.any?` is
false and the NOT-IN SQL is skipped, exactly as before) but reads
`seed_for("len(...)")`, so the DSE can now drive it to 1 and enter
`where("posts.author_id NOT IN (?)", people)` for real.

**It does not swallow the branch:** `people.any?` is still evaluated by the app
on a `SymbolicList`, which is what records the PC. Only the value it branches on
became reachable — the addendum's prescribed fix.

The shared comment at `concolic_targets.rb:565` says a non-empty return here
"would crash on `SymbolicList#map`" during bind sanitisation. With §5a and §5b in
place it no longer does: `quote_bound_value` finds `#map` on
`IterableSymbolicList` and `#value_for_database` on the `ConcolicIntValue`
element. **Result: tags#show 4 → 8 PCs, 5 → 6 dumps, still zero errors.**

## The missing-`seed_for` question

The batch turned up **two** instances of the inert-mock anti-pattern. They came
out opposite ways, which is the useful part:

| mock | inert? | fixing it | why |
|---|---|---|---|
| §F persistence (`concolic_targets.rb:508`) | yes | **buys nothing** | the truthiness gap sits upstream — no PC is ever recorded, so no flip is ever generated |
| `Post.blocked_people` (`concolic_targets.rb:560`) | yes | **+4 PCs, +1 dump** | the app DOES record a PC (`people.any?` on a SymbolicList), so the flip had somewhere to land |

The discriminator is simple and worth reusing: **an inert mock is only worth
fixing if the value it returns reaches something that records a path
condition.** Check for the PC first, then the `seed_for`.

### Persistence mocks — confirmed anti-pattern, confirmed moot

`concolic_targets.rb:508` is `symbool("#{name}_#{m}_ok", true, note: ...)` — it
hard-codes `true` instead of routing through `seed_for`, so every §F persistence
var is **inert**: DSE emits a flip, runs the child, and the mock ignores the
seed. Structurally the same bug that made `Photo#url` unclosable for photos. The
overlay fixes the shape (`ct.seed_for(vn, true)`, default unchanged).

**It changes nothing here, and provably cannot, because the truthiness gap sits
upstream of the seed.** The two branches that would consume these values are
bare Ruby truthiness tests:

```ruby
if @tag_following.save                        # tag_followings#create
if tag_following && tag_following.destroy     # tag_followings#destroy
```

A `SymbolicBool` wrapping `false` is still a truthy Ruby object
(`src/ruby_runtime/bool.rb:11`), so the `if` records **no** path condition and
always takes the true arm. `SymbolicBool` records on `==`, `!=` and `!` only —
none of which the app uses here.

Verified against the AFTER dumps rather than argued:

- The vars are minted —
  `SYM_RESULT_ActiveRecord__Base_save_1_save_ok`,
  `SYM_RESULT_ActiveRecord__Base_update_column_1_update_column_ok` — and appear
  in the `symbolic_call` events.
- **Zero of them appear in any path condition**, in any of the 27 dumps.
- **Zero of them ever appear as a seed key.** The only seed keys the DSE
  generated across the whole batch are the four finder/count vars:
  `..._FinderMethods_first_1_not_found`, `..._FinderMethods_find_by_1_not_found`,
  `..._Core__ClassMethods_find_by_1_not_found`,
  `..._Calculations_count_1_count`.

That is the causal chain: no PC → no flip generated → the seed is never even
requested → seedability is unreachable. **Answer: seedable persistence does not
help this batch; truthiness makes it moot.** The `head :forbidden` arms of
`tag_followings#create` and `#destroy` remain unrecordable, and the fix is in
`src/` (a truthiness hook, per `src/TODO.txt`), not in any mock.

The seed-aware form is kept anyway: it is the correct shape, it is free, and the
next batch to consume a persistence result with an explicit `== true` / `!` will
need it.

## Method

Prefix-directed DSE — **not** the old `run_concolic.rb` →
`CoverageChecker.concrete_values` → `run_concolic_seeds.rb` loop. Those two
scripts are retained as inputs but were not used to produce any result here;
feeding suggestion dicts back wholesale is unsound because
`SYM_RESULT_<func>_<idx>` carries a per-run call ordinal, so a name harvested
from one run can denote a different query in another.

From an observed path `[c0 … cn]` the runner emits one child per `k` that
inherits the parent's seed dict (prefix `c0 … c_{k-1}` replays identically, so
its ordinals stay valid) and adds exactly one flip for `c_k`. Dedup is on the
path signature; expansion continues until the worklist drains. `flip_seed`
covers every PC shape this runtime emits — `(VAR == LIT)`, `(VAR != LIT)`
(including `(len(X) != 0)` from `SymbolicList#empty?/any?` and `(VAR != 0)` from
`SymbolicInt#zero?`), and the four integer orderings. **No PC in this batch was
unflippable** (`unflippable_pcs` empty in every `exploration_summary.json`).

**Request scenarios.** Several real branches in these three controllers test
request params, which ActionController parses into plain Strings — they are not
symbolic and no seed flip can reach them. Rather than leave those app paths
untouched, each entrypoint is driven from one DSE **root per concrete request
shape** (17 roots over 9 entrypoints: typed/unread notification filters,
`set_unread=true`, `q="ruby"` / `"#ruby"` / `"r"`, `name="TestTag"` (capitals
redirect), anonymous tags#show, `name=""` on create, mobile-format manage). Each
root is explored with the same flipping, so a symbolic branch reachable under
only one scenario still gets both sides. These runs record no fabricated PCs —
their value is showing which wall each concrete path hits.

Caps were `MAX_RUNS=400`, `TIME_BUDGET=400 s` per entrypoint. **No entrypoint
came close**: the largest was tags#show at 7 runs. All 9 worklists drained —
this is a true fixpoint, not a cap.

## Walls — all closed

**28 dumps, 0 errors.** For the record, the three families and how each died:

### A. `NotImplementedError: SymbolicInt#to_i` — notifications#index — CLOSED (§5a)

```
src/ruby_runtime/int.rb:30:in `to_i'
will_paginate-3.3.0/lib/will_paginate/collection.rb:109:in `total_entries='
app/controllers/notifications_controller.rb:34:in `index'
```

`Notification.where(conditions).count` was a `SymbolicInt` handed to
`WillPaginate::Collection.create`. Closed by returning a `ConcolicIntValue` from
the batch-local `Calculations#count` mock. Two further walls sat behind it and
were closed with it: `pager.replace(<SymbolicList>)` (§5b-ii) and
`note.updated_at.strftime` in `group_by` (§5c). **Coverage impact: none — the
entrypoint runs clean and still records 0 PCs.**

### B. `ActiveRecord::ActiveRecordError: cannot update a new record` — notifications#update — CLOSED (§2)

`update_column` was missing from the shared §F persistence list, so it ran for
real against a `klass.allocate` record with `@new_record == true`. **Coverage
impact: none** (the argument is a concrete boolean; `set_read_state` is
straight-line).

### C. `TypeError: can't quote SymbolicInt` — tags#show — CLOSED (§5a)

```
activerecord-5.2.4.3/connection_adapters/abstract/quoting.rb:179:in `_quote'
activerecord-5.2.4.3/sanitization.rb:211:in `quote_bound_value'
app/models/status_message.rb:57:in `tag_stream'
```

`Stream::Tag#posts` → `StatusMessage.user_tag_stream(user, tag.id)` →
`where("taggings.tag_id IN (?)", tag_ids)`, a string-condition `where` that
routes through AR's sanitizer. Closed by `#value_for_database` on the integer
column value — no call intercepted, no branch swallowed. **Coverage impact:
tags#show 4 → 8 PCs** (§6), the batch's one real gain.

## Branches the runtime cannot record at all

**Gap 1 — Ruby truthiness** (`src/TODO.txt`). Bare `if obj` on a symbolic
wrapper emits no PC. Two real branches in this batch are lost to it, and both
are the *only* remaining branch in their action:

- `tag_followings#create`: `if @tag_following.save` — the `head :forbidden` arm
  is unreachable for the search.
- `tag_followings#destroy`: `if tag_following && tag_following.destroy` — same
  shape, same loss.

Now MEASURED rather than asserted: with the overlay's seed-aware §F mock in
place, neither `_ok` var appears in a single path condition or a single seed key
across all 27 dumps. See §"The missing-`seed_for` question".

(`if note` in notifications#update and `unless tag` in `Stream::Tag` look like
the same gap but are *not*: the finder mock records `(…_not_found == True)`
itself at the mock boundary before returning nil, which is why those two
entrypoints are genuine. That is the general lesson for this app: **the
recordable branches are the ones a mock records at its own boundary**, not the
ones the app writes.)

**Gap 2 — concrete request params.** Driving through `ActionController::TestCase`
means `params[...]` and `request.format` are plain Ruby values, so every decision
on them is concrete and records no PC: `params[:type] && types.has_key?(...)`,
`params[:show] == "unread"`, `params[:set_unread] != "true"`,
`params[:q] && params[:q].length > 1`, `name_normalized.nil? || .empty?`,
`tag_has_capitals?`, `user_signed_in?`, `request.format == :mobile`. The
scenario roots exercise these paths so they appear in the dumps, but they are
**not** branch coverage in the concolic sense and are not counted as PCs above.

## Other findings (unchanged by the overlay)

- **`Tag` is `ActsAsTaggableOn::Tag`.** The namespaced model is not autoloaded in
  the concolic env. Now handled in `targets.rb` §1 (was runner-local). It loads
  fine and `tags`/`taggings` exist in `db/concolic.sqlite3`, so tag column vars
  are real. No app or shared-file change was needed.
- **`CallInterceptor` memory leak worked around runner-locally.** `@all_calls` is
  never trimmed across runs. `#run` only reads `@all_calls[old_count..]`, so
  `run_dse.rb` clears the array after each run — behaviour-neutral for the dumps.
  `src/` concern; reported, not patched.
- **SQL traceability is weaker on class-level finders.** Relation-level mocks
  render real SQL into `note`. The `Core::ClassMethods` path cannot —
  tag_followings#destroy's note is
  `TagFollowing query (class-level finder), args=args=nil`, with no SELECT. The
  doubled `args=args=` is a cosmetic bug in `ConcolicTargets.render_args` when
  the captured kwargs hash itself has an `args` key (dynamic matcher
  `find_by_tag_id`). Shared-file issue, not fixed here.
- **`TagsController#prep_tags_for_javascript` mock (shared §I rows 12-13) does not take
  effect.** Body-skip means `@tags = @tags.map {…}` never runs, so the ivar keeps
  the original relation and the mock's returned `SymbolicList` is discarded.
  `tags#index` then serialises the relation, which materialises via the `records`
  mock — no crash, but the mock is dead weight as written.
- No dump in this batch is an app-level outcome such as
  `ActiveRecord::RecordNotFound`; the not-found branches here are
  `find_by`/`first`-style, which return nil rather than raising.

## Findings worth escalating beyond this batch

1. **"The runtime is missing method X" is never a `src/` blocker.** Three walls
   here died to batch-local subclasses. The recipe: subclass the symbolic class,
   add the method, return it from a batch-local mock.
2. **A mock cannot return a plain `Array`** — `to_symbolic` converts it to
   `SymbolicList`. `SampledRowsArray < ::Array` + `include SymbolicVar` (§5b-ii)
   is a general escape hatch, and `SymbolicVar` shadows no Array method. The
   shared file works around this twice by returning `nil`
   (`concolic_targets.rb:565`, `:576`); both could now return real arrays.
3. **Never `include Enumerable` in a `SymbolicList` subclass** — it shadows the
   PC-recording `#any?`/`#empty?`/`#first` and silently destroys coverage
   (§5b). `photos/targets.rb` §6b is exposed.
4. **The reference checker under-reports** terminal branches, and a short run
   inserted first can block a longer run from extending the tree (see the
   caveat above `## The overlay`). `missing=0` is weaker evidence than it looks.
5. **Two more inert shared mocks** beyond the two analysed here:
   `Stream::Aspect#aspect_ids` → `[1]` and `Stream::FollowedTag#tag_ids` → `nil`
   are both hard-coded and unseedable, and the second exists only to dodge
   finding #2.

## Regressions

**None in the final state.** No entrypoint lost path conditions, dumps, or
genuine status, and no new error family appeared.

One regression WAS introduced and caught mid-round, and is worth recording
because it was invisible in the error counts: adding `include Enumerable` to
`IterableSymbolicList` (§5b) shadowed the PC-recording `SymbolicList#any?` and
silently dropped tags#show from 8 PCs to 4 — a clean, green, zero-error run that
had quietly lost a branch. It was caught by diffing PCs per dump, not by any
crash. `photos/targets.rb` §6b has the same `include Enumerable` and should be
checked.

## Reproduce

```bash
/home/dev/.claude/jobs/302ac302/tmp/concolic-slot \
  /home/dev/project/reports/diaspora/results/notifications_tags/run_dse.rb
# env: MAX_RUNS, TIME_BUDGET (per entrypoint), ONLY=<ep>[,<ep>...]

cd /home/dev/project && PYTHONPATH=src python3 \
  reports/diaspora/results/notifications_tags/coverage_report.py
```

All 28 dumps re-parse as JSON (`dumps_unparseable` is empty for every entrypoint)
and every run reached a normal terminal state — there is no captured `error`
anywhere in the batch. Nothing was truncated and no run was deleted. `src/`, the shared
`concolic_targets.rb` and the app source are untouched — every change in this
round is inside `results/notifications_tags/`.
