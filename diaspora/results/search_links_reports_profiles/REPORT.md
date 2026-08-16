# Batch 8 — `search_links_reports_profiles`

Controllers: `search_controller.rb`, `links_controller.rb`, `report_controller.rb`,
`profiles_controller.rb`.

Re-run **2026-08-15** with `run_dse.rb` + the batch-local overlay `targets.rb`,
superseding the 2026-08-14 round (which itself replaced the old seed-suggestion
loop in `run_concolic.rb`, kept as an input for reference).

- Prefix-directed DSE: from an observed path `[c0 … cn]`, one child per `k`
  inherits the parent's seed dict and flips exactly `c_k`, so the prefix replays
  identically and the interceptor's per-run call ordinals
  (`SYM_RESULT_<func>_<idx>`, `call_interceptor.rb:140`) stay valid. Dedup on the
  path signature; expand until the worklist drains.
- Coverage checked **per entrypoint** (`coverage_report.py`), never merged across
  the batch.
- **One entrypoint per JRuby process** (`drive_all.sh`) — `links_resolve` could
  abort the JVM (see §1/§2), and process isolation kept that from taking the
  other eight with it.
- `src/` untouched, shared `concolic_targets.rb` untouched, app source untouched.
- 22 dumps / 49 executions / 4.5 s of exploration across 9 processes (excluding
  JRuby+Rails boot); every dump parses.

> **Provenance.** This batch's agent was **killed at 01:12 on 2026-08-15**, mid
> `"Now the coverage check per entrypoint"`, when the coordinator session's
> pinned provider went away. It had finished the overlay and the runs;
> `search_search` was the one entrypoint left without a `coverage_summary.json`.
> That check has since been run (`coverage_report.py`, same tooling, no re-run of
> the dumps) and the batch index regenerated, so the batch is now complete. The
> numbers below are a fresh re-measurement of the dumps on disk
> (`reports/diaspora/batch_stats.py search_links_reports_profiles`).

## Results — BEFORE (2026-08-14) vs AFTER (this round)

| entrypoint | dumps | PCs | nodes | missing | complete | genuine | **both sides seen** | clean | runs | drained |
|---|---|---|---|---|---|---|---|---|---|---|
| `search_search` | 1 → **3** | 0 → **5** | 0 → **2** | 0 | true | **VACUOUS → genuine** | 2 / 2 | 3 / 3 | 7 | yes |
| `links_resolve` | 1 → **3** | 1 → **5** | 1 → **2** | 1 → **0** | **false → true** | genuine | 2 / 2 | 2 / 3 | 7 | yes |
| `report_create` | 1 → **2** | 0 → **2** | 0 → **1** | 0 | true | **VACUOUS → genuine** | 1 / 1 | 2 / 2 | 3 | yes |
| `report_destroy` | 3 → **4** | 5 → **8** | 2 | 0 | true | genuine | 2 / 2 | 3 / 4 | 15 | yes |
| `profiles_update` | 2 → **4** | 2 → **8** | 1 → **3** | 0 | true | genuine | 2 / 2 | 4 / 4 | 9 | yes |
| `report_update` | 2 | 2 | 1 | 0 | true | genuine | 1 / 1 | 2 / 2 | 3 | yes |
| `profiles_show` | 2 | 2 | 1 | 0 | true | genuine | 1 / 1 | 1 / 2 | 3 | yes |
| `report_index` | 1 | 0 | 0 | 0 | true* | **VACUOUS** | — | 1 / 1 | 1 | yes |
| `profiles_edit` | 1 | 0 | 0 | 0 | true* | **VACUOUS** | — | 1 / 1 | 1 | yes |
| **total** | 14 → **22** | 12 → **32** | 6 → **12** | 1 → **0** | 8/9 → **9/9** | 5 → **7 genuine, 2 vacuous** | **11 / 11** | **19 / 22** | 49 | 9/9 |

`*` complete only because the tree is empty. A vacuous entrypoint is **not
covered**, whatever the checker prints.

**5 genuine / 4 vacuous / 1 incomplete → 7 genuine / 2 vacuous / 0 incomplete.**
Every worklist drained to a fixpoint; `unflippable_pcs` and `suppressed_flips`
are **empty for every entrypoint** — the previous round's one deliberately
suppressed flip is gone, closed rather than worked around.

### On `complete=true`

`COMPLETENESS_AUDIT.md` explains why it is not evidence on its own. This batch
happens to be the clean case: **11 of 11 branch expressions are two-sided**,
measured from the dumps independently of the solver, and every worklist drained
with no unflippable PCs. Here `complete=true` is corroboration rather than the
claim.

## What the overlay bought, per wall

The file draws a line between two mechanisms and applies each where it belongs:
**mocks** (`declare_target`) for "this leaf does I/O we cannot do here", and
**subclasses** of the runtime's symbolic types for "the runtime does not
implement operation X". The rule that shaped it: *a wall mock that swallows the
branch it guards is a regression, not a fix* — §4 documents the two places where
the obvious mock target was rejected for exactly that reason.

### §1 / §2 — the JVM-killing HTTP fetches (mocks)

`links#resolve`'s not-found side calls
`DiasporaFederation::Federation::Fetcher.fetch_public`, a real HTTP fetch through
typhoeus → libcurl over JRuby's FFI, which **SIGSEGVs the whole JVM**:

```
#  SIGSEGV (0xb) at pc=0x00007dd45c0a002f
#  C  [libcurl.so.4+0x6e3af]  curl_easy_setopt+0x9f
#  j  com.kenai.jffi.Foreign.invokeArrayReturnInt(JJ[B)I+0 org.jruby.dist
```

(`links_resolve/jvm_sigsegv_fetch_public_hs_err_head.txt`, reproduced twice.) A
JVM abort is not a dump — it destroys the process — so the **previous round had
to suppress that flip and report `complete=false`**. §1 mocks the fetcher to
`nil`; §2 does the same for
`DiasporaFederation::Discovery::Discovery#fetch_and_save`, which the bare-handle
input (`alice@example.org`) reaches one call later via
`Person.find_or_fetch_by_identifier`.

Legality: §2's body is `validate_diaspora_id` (a compare against the webfinger
response) plus a `save_person_after_webfinger` callback trigger — no SQL of its
own and no other declared target beneath it.

**Result: `links_resolve` went from 1 missing branch and `complete=false` to
3 dumps, 5 PCs, 0 missing, both sides on both expressions.** Its one remaining
error dump is a real `ActiveRecord::RecordNotFound` at
`links_controller.rb:6` — the genuine 404 outcome.

### §3 — symbolic-type subclasses, with an exactness rule

`ConcolicString < SymbolicString` adds operations **only for the case where the
answer is exact for the concrete witness, and raises loudly otherwise**. No
operation silently concretizes, and none invents a Z3 term the engine cannot
interpret:

| op | modelled when | otherwise |
|---|---|---|
| `strip` / `lstrip` / `rstrip` | witness has no surrounding whitespace → returns **self**, preserving `sym_name` and the whole constraint history exactly | raises |
| `split(multi-char)` | witness does not contain the separator → `[self]`, a provable one-element split that introduces **no new symbolic terms** | raises |
| `starts_with?` / `ends_with?` (§3b) | — | a silent-tracking-loss repair, not a missing operation |

A term like `Split(x, '::')[0]` would be unmodellable by the engine and would
only add unflippable path conditions — hence the deliberate refusal to invent
one.

`§3b` re-declares `Relation#to_a`/`#to_ary`/`#records` byte-for-byte as the
shared declaration (`concolic_targets.rb:448`) except for the list class
(`IterableSymbolicList`), so the representative row and the SQL note are
unchanged. Needed because `@profile.tags.map` in `profiles#edit` hits
`SymbolicList#each` once §6 makes the collection association actually load.

`§3c` fixes `SingularAssociation#find_target` for **polymorphic** targets: the
shared target (`concolic_targets.rb:793`) builds its symbolic instance from
`receiver.reflection.klass`, which for a polymorphic `belongs_to` is not a class
at all — so it raises, the rescue returns `nil`, and `report.item` comes back
NIL. `case item when Post / when Comment` in `Report#destroy_reported_item` then
matches nothing and the whole retract/destroy subtree is silently unreachable.

### §4 — the two mocks that were REFUSED

**(a) `BelongsToPolymorphicAssociation#klass`.** `report#destroy` walled at
`SymbolicString#split only supports single-character separators`
(`inflector/methods.rb:273 constantize` ← `belongs_to_polymorphic_association.rb:9
klass` ← `report.rb:37`). `klass` is a textbook SQL-free leaf:

```ruby
def klass
  type = owner[reflection.foreign_type]
  type.presence && type.constantize
end
```

and mocking it is **wrong**: `type.presence` → `present?` → `blank?` →
`String#empty?`, and `SymbolicString#empty?` **records** `(<item_type> == '')` —
the only path condition the polymorphic association produces, and the branch
separating "item resolves to nil" from "item resolves to a model". Mocking
`klass` swallows it — the `photos/build_image_url` regression, one method deeper.
Fixed instead by `ConcolicString#split` (§3) plus §6's attribute upgrade, so the
**real** `constantize` runs on the symbolic `item_type`.

**(b) `SearchController#search_query`.** It walled at `SymbolicString#strip`:

```ruby
def search_query
  @search_query ||= (params[:q] || params[:term] || '').strip
end
```

Mocking it is legal *by the letter* of the rule — its body holds no branch, and
all three of the action's branches are in the caller — but it is still second
best, because the value would then enter one frame **above** the code under test.
`ConcolicString#strip` lets the real method body run, and `run_dse.rb` injects
the symbolic value at the actual program input, `params[:q]`.

That injection is required regardless of `strip`:
`ActionController::TestCase#process` serialises params through `to_query` and
re-parses them, so **a symbolic value can never survive into `params` by
itself** — which is exactly why the previous round measured `search_search` as
irreducibly vacuous. It is now **genuine: 3 dumps, 5 PCs, 2 nodes, both sides on
both expressions.**

### §6 — the silent gap, and it is not local to this batch

Not a mock: a runner-local overlay that rebinds `ConcolicTargets.symbolic_instance`
**in-process only** (the shared file is untouched).

`concolic_targets.rb:317` ends `symbolic_instance` with
`obj.instance_variable_set(:@new_record, true)`. AR's
`CollectionAssociation#find_target?` is

```ruby
!loaded? && (!owner.new_record? || foreign_key_present?) && klass
```

and `foreign_key_present?` is false for a collection. **So every collection
association on every symbolic record in every batch short-circuits to `[]`** —
no query issued, no target intercepted, no symbolic list built, no path
condition recorded. `@profile.tags` in `profiles#edit` is silently empty; so are
`user.aspects`, `post.comments`, `user.contacts`, … wherever a batch has not
hand-stubbed them.

Singular associations are unaffected (they route through the declared
`SingularAssociation#find_target` target), which is exactly why the gap is easy
to miss: **the record looks fully wired up.**

The same wrapper upgrades every `SymbolicString` column value to
`ConcolicString`, which is what puts a working `split` under
`item_type.constantize`. Disable with `SLR_NEW_RECORD_FIX=0` to reproduce the
BEFORE column.

### §7 / §8 — boundary-recorded persistence and existence

**§7 (`save`/`update`/`update_attribute`)** repairs two defects in the shared §F
mock (`concolic_targets.rb:503`), the single biggest source of dead branches in
this batch:

- **no `seed_for`** — `symbool("#{name}_#{m}_ok", true, ...)` hard-codes `true`,
  so the var is permanently **inert**: DSE emits the flip, the mock ignores it,
  the branch can never close. The same defect the `photos` batch found in
  `Photo#url`, on a far more commonly-hit method.
- the returned `SymbolicBool` is **truthy in Ruby whatever it wraps**, so
  `if @profile.update(...)` always went left.

Fixed by recording the branch at the mock boundary and returning a **concrete**
truth value. This is what took `profiles_update` from 2 PCs to 8 and
`report_create` from vacuous to genuine.

**§8 (`FinderMethods#exists?`)** gets the same boundary-record treatment. The
shared §B mock (`concolic_targets.rb:437`) seeds properly, and its own comment
concedes the problem: *"`if Post.exists?(...)` hits the Ruby truthiness gap —
only explicit compares record PCs. Returned anyway."* In this batch that one gap
made the **entire authorization guard invisible**:
`application_controller.rb:116` `return if current_user.moderator?` →
`user.rb:473` → `role.rb:27` → `Role.moderators.exists?`.

## Every `error` in every dump

19 of 22 dumps are clean. All 3 errors are **real app outcomes or a genuine app
defect**; no framework wall remains.

| error | dumps | where | classification |
|---|---|---|---|
| `ActiveRecord::RecordNotFound` | 1 (`links_resolve`) | `links_controller.rb:6` | real 404 path — the branch §1/§2 made reachable |
| `ActiveRecord::RecordNotFound` | 1 (`profiles_show`) | finder mock | real 404 path |
| `NameError` | 1 (`report_destroy`) | `inflector/methods.rb:283 const_get` | `uninitialized constant SYM_RESULT_..._item_type_v` — the **real** `constantize` running on the symbolic `item_type` witness. This is the intended consequence of refusing to mock `klass` (§4a): the branch is recorded, and the model-resolves side then fails on a witness that is not a real class name. Seeding `item_type` to `"Post"`/`"Comment"` would close it |

## Branches the runtime still cannot record

- The moderator guard (`return if current_user.moderator?`) is a bare `if` on a
  truthy object — §8 records the underlying `exists?` decision at the boundary,
  but the guard itself contributes no node.
- `report_index` — `Report.where(reviewed: false)` is lazy and the action body
  contains **no conditional at all**, so 0 PCs is the right answer for the
  action; it is still not "covered" in any useful sense. The authorization query
  does fire and is in the dump.
- `profiles_edit` — same shape: with §6 the collection association now loads and
  `@profile.tags.map` runs for real, but the action body has no branch of its
  own.

## `src/` gaps to raise to Bali (worked around batch-locally, NOT patched)

1. **`symbolic_instance` sets `@new_record = true`, which silently empties every
   collection association on every symbolic record, experiment-wide** (§6). The
   highest-value single fix on this list, and invisible from any dump.
2. Shared persistence mocks (`concolic_targets.rb:503`) have **no `seed_for`**
   and return a truthy `SymbolicBool` — inert *and* branch-swallowing.
3. `SingularAssociation#find_target` (`concolic_targets.rb:793`) cannot resolve a
   **polymorphic** `belongs_to`; it raises, the rescue nils, and whole subtrees
   go unreachable without any error surfacing.
4. `SymbolicString` lacks `#strip` and multi-character `#split`; `SymbolicList`
   lacks `#each`/`#map` even with a `representative:`.
5. `ActionController::TestCase#process` round-trips params through `to_query`, so
   symbolic request parameters cannot reach an action without direct injection —
   a harness limitation worth documenting in the README.
6. Ruby truthiness gap (`src/TODO.txt`).

## Files

```
results/search_links_reports_profiles/
├── targets.rb                  BATCH-LOCAL overlay (SearchLinksReportsProfilesTargets)
├── run_dse.rb                  runner (MAX_RUNS, TIME_BUDGET, ENTRYPOINTS)
├── drive_all.sh                one JRuby process per entrypoint
├── coverage_report.py          per-entrypoint checker
├── run_concolic.rb             previous-round runner, kept as input
├── batch_coverage_index.json   batch-level roll-up of the 9 coverage checks
├── elapsed_seconds.txt
├── logs/
└── <entrypoint>/
    ├── dump_*.json             one per DISTINCT path
    ├── exploration_summary.json
    └── coverage_summary.json   this entrypoint's runs ONLY
```

Reproduce:

```
reports/diaspora/results/search_links_reports_profiles/drive_all.sh
cd /home/dev/project && PYTHONPATH=src python3 \
    reports/diaspora/results/search_links_reports_profiles/coverage_report.py
PYTHONPATH=src python3 reports/diaspora/batch_stats.py search_links_reports_profiles
```

Switches: `SLR_NEW_RECORD_FIX=0` (disable §6), `SLR_INT_UPGRADE=0`, `MAX_RUNS`,
`TIME_BUDGET`, `ENTRYPOINTS`.
