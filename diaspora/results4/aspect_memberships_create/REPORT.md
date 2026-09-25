# aspect_memberships_create — REPORT

## 1. What was produced

`/home/dev/project/reports/diaspora/results4/aspect_memberships_create/`

| set | dir | runs | distinct paths | run errors | genuine (≥1 PC) | vacuous | unflippable | worklist |
|---|---|---|---|---|---|---|---|---|
| main (budget) | `./` | 6 | 6 | **0** | 6 | 0 | **0** | **not drained** — 50 seeds queued at `MAX_RUNS` |
| write path (seeded replay) | `./write_path/` | 4 | 4 | **0** | 4 | 0 | 0 | drained (`SEEDS_ONLY`) |

*(Numbers as regenerated 2026-09-25 after the D8 fix, §8. The pre-fix main
set had the same 6/6/0 with 45 seeds queued.)*

Launched exactly as specified: `MAX_RUNS=6 TIME_BUDGET=600 scripts/diaspora-concolic .../run_dse.rb`. Both `exploration_summary.json` files report `run_errors: {}`; no dump carries an `error`. One dump carries a `concolic_terminal` — `I18n::InvalidLocale` on `dump_auth_json_dse0003.json` — a real app outcome (`set_locale` 500s on an unavailable `users.language`), not a framework wall.

The six main paths **after the D8 fix**: (1) full validation chain passes → `contact.aspects << aspect` → **the `aspect_memberships` INSERT** → the presenter read; (2) same + the `language="pl"` inflected-locale `profiles` read; (3) `language="xx"` → `I18n::InvalidLocale`; (4) `Person.find` misses → the controller's own `rescue_from` → 404; (5) aspect finder misses; (6) `blocks.exists?` true → blocked → 409.

Before the fix, (1) and (2) ended in `not_contact_for_self` → 409 instead, and (5) recorded fewer decisions. That 409 is not lost — it is now the FLIPPED side of the same decision, and the explorer's own flip seed reproduces the old path exactly (§8.5).

## 2. Does the insert show up? Yes — with a full producer chain

All four `write_path` dumps carry real DML. The defining statement:

```sql
INSERT INTO "aspect_memberships" ("aspect_id", "contact_id")
VALUES ($$(SYM_RESULT_ActiveRecord__FinderMethods_first_1_id),
        $$(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_id))
```

`first_1` is `current_user.aspects.where(id: params[:aspect_id]).first`; `find_by_1` is `contacts.find_or_initialize_by(person_id: person.id)`. Also recorded: the `contacts` UPDATE (`SET "receiving" = true`), the `contacts` INSERT on the contact-missing arm, and the `notifications` UPDATE (`SET "unread" = false WHERE "type" IN ('Notifications::StartedSharing') AND …`). Both entrypoint parameters reach SQL as genuine binds: `$$(SYM_PARAM_aspect_id)` and `$$(SYM_PARAM_person_id)`.

**Superseded 2026-09-25 (§8): the write IS now in the main 6-run set**, on run 1, with an empty seed dict. The paragraph below describes the pre-fix state.

**Honest qualification (pre-fix):** the write is not in the main 6-run set. It sits behind one branch flip the FIFO worklist had not reached. `write_path/` uses the same runner and targets with `EXTRA_SEEDS_JSON` + `SEEDS_ONLY` (RUNBOOK Phase 2's "construct runs from counterexamples"). A 40-run pass (not kept) ran clean with 32 distinct paths and 0 errors but also did not reach the write, for the reason in D8.

## 3. Mocks added and `kind:` reasoning

All in `./targets.rb`. `./concolic_targets.rb` is a byte-identical copy of `../comments_index/concolic_targets.rb`; the shared app-wide `reports/diaspora/concolic_targets.rb` was not touched. Dumps declare 89 targets: 48 `target_function`, 41 `shim`.

**TARGET_FUNCTION** — `FinderMethods#first/last/take/find_by` (+`!` forms); `FinderMethods#exists?`; `FinderMethods#devise_user_first`; `Base#save/save!/update/update!/update_attribute/touch/destroy/destroy!` (the writes — redeclared to render real INSERT/UPDATE/DELETE); `Relation#update_all/delete_all`.

**SHIM** — `User#blocks` (returns the real association reader, since the shared mock's `SymbolicList` has no `#where`); `Dispatcher.defer_dispatch` and `User#deliver_profile_update` (federation walls); `SingularAssociation#writer` (in-memory assignment, no SQL, but FK-preserving — see D4).

**Not mocked, per D7 discipline:** `User#share_with` runs for real; every line is SQL or a call into a declared target. Same for `Contact`'s validations, `find_or_initialize_by`, and the presenters (SQL-free field reads).

## 4. Eleven defects found — all measured, none patched in `src_new/`

Per the "ask before `src/` changes" rule these are reported with batch-local workarounds only. D1, D2, D4, D5, D6, D7, D8 and D11 are not specific to this endpoint.

**D1 — a mock returning bare `false` is TRUTHY (Class B, foreclosed branch).** `to_symbolic(false)` is `SymbolicBool.new(false)`, a Ruby object, hence truthy. A mock meaning "no" makes every `if <mocked predicate>` take the TRUE branch unconditionally. Live effect here: `blocks.exists?`'s negative arm fired unconditionally, `share_with` always returned nil, every run took the 409 arm with no write. Workaround: return `nil` on the negative arm. **The shared `exists?/any?/none?/one?/many?/empty?` family needs a sweep for this.**

**D2 — the flip matchers cannot read the new structured PC terms (Class B).** PCs now record `expr` as a structured term Hash (DESIGN_IR §4.1.1c); every `results3`-lineage flip matcher is a regex over the old rendered string, so a Hash matches nothing, the PC is booked unflippable, and the worklist reports a false `worklist_exhausted: true`. Measured before a fix: 5 PCs, all 5 unflippable, exploration stopped after one run. After adding a term→string renderer: 14 PCs on the same root, 0 unflippable, 32 distinct paths over 40 runs. **This is live in `results4/comments_index` right now** — its dumps hold 26 structured-expr PCs and 11 string-expr PCs; only the 11 could ever be flipped, and its own exploration summary's completion signal is not trustworthy until this is fixed.

**D3 — `SymbolicInt#to_i` blocks every build-a-new-record path**, exactly the not-found arm of `find_or_initialize_by` this endpoint depends on. Workaround: a batch-local `CastableSymbolicInt`.

**D4 — the shared `SingularAssociation#writer` mock drops the foreign key (Class S).** It no-ops the belongs_to writer on the premise that the in-memory FK write doesn't matter for coverage — true for reads, false here, since AR attaches a through-association's join row via that exact writer. With it in force the join INSERT was missing its `aspect_id` column. D3's fix removes the original justification for this no-op.

**D5 — re-declaring an already-declared target loses the real parameter names**, because `declare_target` reads `original.parameters`, and on a second declaration "original" is the first mock's `|*splat, **kwargs, &block|` wrapper. Any mock reading `args["<name>"]` silently gets `nil`. The shared W1 writer mock is exactly this shape wherever it's re-declared.

**D6 — a class-level finder's id renders as a literal, not a bind (Class S).** `Person.find(params[:person_id])` rendered `"people"."id" = '5'` instead of a bind, while a sibling relation-based parameter rendered correctly. Relation notes render from Arel binds (symbolic preserved); class-finder notes render from the mock's already-native-converted `args`. Fixed batch-locally via the existing thread-local finder-conditions channel.

**D7 — `update_all(updates)` loses its SET list.** A required positional gets packed into `**kwargs` under Ruby 2.6, and the interceptor's existing repair for this only covers a named `*rest`, so it doesn't apply here.

**D8 — cross-rep id collision forecloses `record_a == record_b`.** Every symbolic instance's default id is `1` and every foreign key `0`, so any two independently-loaded records compare equal, making `not_contact_for_self` fire by default — the rare real state is presented as the default outcome. Worse, an association rep's id variable and the owner's FK column variable can render to the same name, so seeding one moves both together. **This is why the write was never reached within budget** — a new instance of the naming-collision class `assoc_base_name` was introduced to fix. **FIXED 2026-09-25 in `./concolic_targets.rb`; see §8.**

**D9 — a raising finder's pending note lands on the next target call (Class S).** Not fixable from a mock; statement isn't lost, just mis-attributed.

**D10 — `UniquenessValidator` binds the CAST value, not the symbol (Class S).** `validates :person_id, uniqueness: {scope: :user_id}` reads its values through AR's type-cast pipeline — `record.read_attribute_for_validation(attribute)` for the validated column and `record._read_attribute(scope_item)` for each scope column — both of which run `ActiveModel::Type::Integer#cast` -> `CastableSymbolicInt#to_i` and hand back a bare Integer. The relation the probe is then rendered from carries concrete binds, and the note came out
`… "contacts"."person_id" = 1 AND "contacts"."user_id" = 1 …` on the write arm. The record still holds BOTH symbols in `attributes_before_type_cast` (probed); only the two readers drop them. Fixed batch-locally in `./targets.rb` §8 (`AmUniquenessSymbolicBinds`, a prepend that substitutes by COLUMN NAME — never by value: D8 makes a value lookup ambiguous by construction).

**D11 — `?` placeholders and collected binds are two different lists (Class S, silent mis-attribution).** `ConcolicTargets.render_relation_sql` renders the SQL with one pass (`visitor.accept` -> `"?"` per emitted bind) and collects the binds with another (`collect_binds` over the AST), then zips them positionally with `sql.gsub("?")`. The lists are not the same length: activerecord-5.2.4.3 wraps EVERY hash condition in a `BindParam`, nil ones included (`where.not(id: nil)`, which the uniqueness validator adds for a persisted record), while arel-9 short-circuits a bind whose `nil?` is true and emits `IS NULL` / `IS NOT NULL` with NO placeholder. Probed on the real relation: `qmarks = 2, collected = 3`, so the user_id placeholder consumed the nil `id` bind. **Every bind after the first nullable condition is shifted onto the wrong value** — here it happened to land on nil, but the same shift renders `$$(<wrong producer>)`. Two instances in these dumps: the uniqueness probe's `user_id`, and `AspectMembership.where(contact_id: <nil>, aspect_id: <sym>)` (14 notes/dump). Fixed batch-locally in `./targets.rb` §9: substitute at the single point that emits a placeholder (`Arel::Collectors::SQLString#add_bind`), which makes the mapping exact by construction and also removes a second latent bug (a literal `?` inside a quoted SQL string consumed a bind).

## 5. Open / not done

1. ~~The write is not in the main 6-run set — cause is D8, not a wall. More runs alone won't fix it.~~ **CLOSED 2026-09-25 — see §8.** The main set's run 1, with an EMPTY seed dict, now carries `INSERT INTO "aspect_memberships"`.
2. `worklist_exhausted: false` (45 seeds queued). No completeness claim; no `CoverageChecker` pass was run — first pass, as scoped.
3. `User#deliver_profile_update` is shimmed, eliding an access that's dormant on every explored path but is a recorded cost.
4. ~~`"contacts"."user_id" = nil` appears in one uniqueness-probe note on some paths — undiagnosed.~~ **DIAGNOSED AND CLOSED (2026-09-25)** — it was not a nil value but a bind/placeholder misalignment; see D11. The probe now renders `"person_id" = $$(…) AND "id" IS NOT NULL AND "user_id" = $$(…)` on the persisted arm and `"person_id" = $$(…) AND "user_id" = $$(…)` on the build arm, in both the main and `write_path` sets.
5. ~~One key column in the corpus still renders against a non-`$$` right-hand side: `SELECT "blocks".* FROM "blocks" WHERE "blocks"."user_id" = ?`.~~ **CLOSED 2026-09-25 — see §7 below.** The third way was to stop treating D5 as a property of re-declaring and treat it as what it is: `declare_target` reading the wrong SIGNATURE. Restoring the signature first makes a second declaration name its real parameters, and the note is then rendered from `sql` AND `binds` together. `grep -cE '"(id|[a-z_]+_id)" = [^$]'` over both `policy_example.txt` files is now `0`.
6. **`concolic_targets.rb` divergence needs a ruling.** The canonical shared `/home/dev/project/reports/diaspora/concolic_targets.rb` has 71 `declare_target` calls and zero `kind:` arguments — it would raise `MissingKind` immediately under the current runtime. The `results4/comments_index` copy this batch cloned differs from it by ~800 diff lines in both directions. Someone should decide which is canonical before the next batch.

## 6. Files

- `run_dse.rb`, `targets.rb`, `concolic_targets.rb`
- `dump_auth_json_dse0001..0006.json`, `exploration_summary.json`
- `write_path_seeds.json`, `write_path/dump_auth_json_dse0001..0004.json`, `write_path/exploration_summary.json`

Nothing in `src/`, `src_new/`, the shared `reports/diaspora/concolic_targets.rb`, or the diaspora app source was modified.


## 7. Changes of 2026-09-25 (IR validation pass)

Three batch-local changes, all in `./targets.rb` (nothing in
`./concolic_targets.rb`, which stays byte-identical to
`../comments_index/concolic_targets.rb`; nothing in `src_new/`). The corpus
was regenerated with them: main set 6 runs / 6 distinct paths / 0 errors,
write path 4 runs / 4 distinct paths / 0 errors — the same numbers as §1,
and every dump's path-condition count is unchanged, which is the check that
these are metadata and not modelling.

### 7.1 `find_by_sql`'s note carries the binds (closes open item 5)

**§10 of `targets.rb`.** The 26 instances of the bare `?` template are gone
from the notes; what remains is 14 occurrences inside
`events[].args.sql`, which is the argument the caller really passed and is a
faithful record, not a lost value.

Two earlier attempts were rejected for good reasons and both rejections
stand:

* **re-declare `find_by_sql` → D5.** Measured again on a bare runtime
  (`ruby` + `src_new/runtimes/ruby_runtime`, no Rails): after a second
  `declare_target`, `args.keys` is `["block", "kwargs", "splat_args"]` and
  both `args["sql"]` and `args["binds"]` are `nil`.
* **rewrite the `sql` argument →** `$$(…)` inside a recorded string
  argument, the leak just removed from `comments_index`.

**The third way** is that D5 is not caused by re-declaring — it is caused by
`declare_target` reading `klass.instance_method(method).parameters`, which
on a second declaration is the first mock's `|*splat_args, **kwargs, &block|`
wrapper. So restore the signature first:

```ruby
querying.send(:define_method, :find_by_sql) do |sql, binds = [], preparable: nil, &blk|
  raise "unreachable: replaced by declare_target below"
end
interceptor.declare_target(querying, :find_by_sql, ...)
```

The stub body is never called (a declaration with `returns:` never invokes
the original), so this is a signature and nothing else. Measured on the same
bare runtime: with it in place the second declaration's `args` are
`["binds", "blk", "preparable", "sql"]` with the right values in them. This
is a **general workaround for D5**, not a trick for this one target.

The note is then rendered from both halves with the shared
`render_arg_value`, so a symbolic bind becomes `$$(<producer>)` and the
`$$(…)` lands in the NOTE — where every other mock in this file puts it —
never in an argument. Alignment is CHECKED, not assumed (D11 is what happens
when a placeholder list and a bind list are zipped without checking): the
substitution only happens when `sql.count("?") == binds.length`, and
otherwise the note says so rather than mis-attributing a value.

Result, e.g. `dump_auth_json_dse0001.json`:

```
SYM_RESULT_ActiveRecord__Querying_find_by_sql_1_rows
  {"refs": {"p0": "SYM_RESULT_..._devise_user_first_1_id"},
   "text": "SELECT \"blocks\".* FROM \"blocks\" WHERE \"blocks\".\"user_id\" = $$(p0)"}
```

### 7.2 A symbolic row is a NAMED value of a FIXED type

**§R of `targets.rb`** (and of `../comments_index/targets.rb`, identically).
`ConcolicTargets.symbolic_instance` already built a row's attribute set out
of `klass.columns_hash`; it never said so, and three facts were lost:
`concolic_name` (so a row that is a list ELEMENT had no symbol for the
`elem` relation to point at — `src_new/TODO.txt` measured this),
`concolic_type_name` (so a row the runtime can enumerate every attribute of
still typed as `obj<?>`), and `SymbolicFunc.register_type` (so the per-dump
type table §5.2 calls a CONTRACT was never written). Added as a wrapper in
`targets.rb`, the technique §9 already uses — NOT edited into
`concolic_targets.rb`, which is the 2026-09-09 re-sync hazard.

Measured, `results4/comments_index`, five dumps, before → after:

| | before | after |
|---|---|---|
| origins | 36 `attr` | 45 `attr`, 2 `elem` |
| `attr` origins whose parent is a FIXED `obj<Name>` | **0** | **9** (`obj<Comment>` ×5, `obj<Mention>` ×4) |
| per-dump `types` table | absent | `Post`, `Comment`, `Mention`, `Person`, `Profile` |
| path conditions per dump | 4, 4, 2, 3, 17 | 4, 4, 2, 3, 17 |

This is what `concolic/model/tests/test_dump_ir_corpus.py
::test_every_attr_origin_names_a_field_inside_its_fixed_set` was skipping
for ("no fixed-object attribute origin in any corpus"). It now runs on real
corpus data.

On `aspect_memberships_create` the same change writes a `types` table
(`Aspect`, `Contact`, `Person`, `User`, `Profile`) but binds no `attr`
contract: every row here is a DIRECT call result, and a direct result takes
the target's DECLARED type (`result_type_for`: "the declaration is the
answer"), which for a generic finder is honestly `obj<?>`. Only a row
reached as a list ELEMENT takes the OBSERVED type.

### 7.3 Artefacts rebuilt

**STALE since 2026-09-25 — rebuilt from the PRE-D8-fix dumps; see §8.8.**

`policy_example.txt` (84 atoms), `policy_example_main.txt` (36 atoms),
`../comments_index/policy_example.txt` (11 atoms), and all three
`dump_examples/` trees (each `.run.txt` re-checked with
`parse_run(print_run(to_text_domain(r))) == to_text_domain(r)`). All ten
main+write-path dumps and all five `comments_index` dumps still load and
build with `provenance=True`.

Incidental: `policy_example.txt` had been built WITHOUT the `--header` its
own `POLICY_EXAMPLE.md` documents. It now has it.

Three acceptance checks, both endpoints: no undefined name (0), no `opaque`
in the IR (0 — two occurrences remain in the header's historical prose), no
id column compared to a non-bind (0, was 97 lines).

### 7.4 Reproducibility of these artefacts, measured

The batch was run TWICE with the final `targets.rb` (the second time after
the §10 stub's block parameter was renamed `&blk` -> `&block` to match
`ActiveRecord::Querying#find_by_sql` exactly). Both runs: main 6/6/0, write
path 4/4/0. Normalising Ruby object addresses (`:0x…>`), **all ten dumps of
the two runs are byte-identical** — so the rename is observationally a
no-op (no dump contains either parameter name; the block is never supplied,
so the slot is ABSENT) and the exploration is deterministic.

WITHOUT that normalisation nothing here is reproducible, and that is a
finding in its own right, not a property of this change: a dump records
`"result_value": "#<User:0xac570e0>"`, and the address differs every run.
340 such values across `results4`, in 8 classes. They reach
`policy_example.txt` verbatim. Logged in `src_new/TODO.txt`; the fix is in
the runtimes' native-rendering path (`#<User>` says exactly as much and is
deterministic) and was not made here per the ask-before-`src/` rule.

The artefacts committed in this directory are the FIRST run's, and the
second run's were discarded: re-installing them would have changed only the
addresses and forced a rebuild of both policies and all three
`dump_examples/` trees for no semantic difference.


## 8. D8 closed — distinct default identities (2026-09-25)

One change, in `./concolic_targets.rb` (and the byte-identical
`../comments_index/concolic_targets.rb`). Nothing in `src/`, `src_new/`, the
shared `reports/diaspora/concolic_targets.rb`, or the app.

### 8.1 What was actually wrong

`default_int` gave EVERY row's `id` the value `1` and every other integer
column `0`. `ActiveRecord::Core#==` is `other.instance_of?(self.class) &&
other.id == id`, so any two reps of the same class were equal by
construction. `Contact#not_contact_for_self` (`person.owner == user`) fired
on the default run; `contact.valid?` was false; `share_with` returned false;
the action rendered its 409. The INSERT sat behind one flip that MAX_RUNS=6
never reached.

The dumps show the mechanism is slightly different from the original
write-up, and the difference matters. The two operands did not collide at
`1`, they collided at **`0`** — because of D8's own second half. The
association rep for `contact.user` is named `<contact>_user`
(`assoc_base_name`), so its `id` column mints the variable
`..._find_by_1_user_id`, which is EXACTLY the variable
`symbolic_instance` already minted for `contacts.user_id`. Whichever
`symint` registers first wins, and that is the FK's, whose default is `0`.
Measured on the pre-fix `dump_auth_json_dse0001.json`: **21 id variables
took 4 distinct values — 14 of them `0`, 5 of them `1`.**

### 8.2 The scheme, and why it is deterministic

```ruby
ID_SEED_MIN  = 10_000_000
ID_SEED_SPAN = 990_000_000
def name_derived_id(var_name)
  ID_SEED_MIN + (Digest::MD5.hexdigest(var_name.to_s)[0, 15].to_i(16) % ID_SEED_SPAN)
end
def default_int(col, var_name = nil)
  return 0 unless col == "id" || col.end_with?("_id")
  var_name.nil? ? 1 : name_derived_id(var_name)
end
```

**The seed is a pure function of the variable's own name.** A per-symbol
counter — the obvious alternative — is order-dependent: the same symbol
would get a different id depending on which decisions ran before it was
minted, so two runs over the same seeds could disagree and the corpus would
stop being reproducible. `Digest::MD5` needs no state, no counter and no
clock, so the same name yields the same id in every run, in every process,
in any order. `String#hash` is deliberately not used: Ruby and JRuby seed it
per process, which is the very non-determinism being avoided. A collision
between two distinct names is detected and warned about rather than silent
(none occurred; ~5e-5 expected over this corpus's name count).

Only `id` and `*_id` columns move. Counts, counter caches and numeric flags
keep their `0`, because they carry no identity and moving them would change
app behaviour (`if x.n > 0`) for nothing.

**What stays equal.** Keying on the FULL variable name means the belongs_to
aliasing above keeps both spellings on ONE value — and
`contact.user_id == contact.user.id` is a true ActiveRecord invariant, so
that identification is correct and is now consistent by construction rather
than a race between two `symint` calls.

After: **26 id variables, 26 distinct values.**

### 8.3 Is the naming collision still live? Yes — and it is benign HERE

`assoc_base_name` was introduced (2026-08-21, `DISCIPLINE.md` violation 5)
to stop `assoc_profile` colliding ACROSS OWNERS. It does that, and in doing
it creates this second aliasing: `<owner>_<refl>` + `_<col>` reproduces
`<owner>_<refl>_id`, the owner's own FK column variable. Eight aliased pairs
occur on this endpoint (`contacts.user_id`/`person_id`,
`people.owner_id`/`pod_id`, `aspects.user_id`,
`aspect_memberships.aspect_id`/`contact_id`, `profiles.person_id`,
`users.invited_by_id`/`auto_follow_back_aspect_id`) and **all eight are
belongs_to**, where `owner.<fk>_id == owner.<refl>.id` is true of the real
database. So the aliasing is not a defect here; it is an accidentally
correct identification, and name-derived seeding makes it consistent.

It is NOT correct in general. The shape that breaks it is a has_one or
has_many named `X` on a table that also has a column `X_id`; then
`owner.X.id` and `owner.X_id` are different rows and this welds them into
one symbol. It does not arise here (`users` has no `person_id` column, so
`user.person`'s id aliases nothing), but nothing excludes it. Not renamed:
a rename churns every variable name in the corpus AND would drop a true
invariant to fix a case that does not occur. Documented at
`assoc_base_name` in `./concolic_targets.rb`.

### 8.4 Before / after, measured

Both sets run as specified, `MAX_RUNS=6 TIME_BUDGET=600`, back to back on
the same machine and the same `src_new` runtime.

| | before | after |
|---|---|---|
| runs / distinct paths | 6 / 6 | 6 / 6 |
| `run_errors` | `{}` | `{}` |
| `unflippable_pcs` | `{}` (0 shapes) | `{}` (0 shapes) |
| worklist | not drained, 45 queued | not drained, 50 queued |
| id variables / distinct values (run 1) | 21 / **4** | 26 / **26** |
| path conditions on run 1 | 14 | 16 |
| **`INSERT INTO "aspect_memberships"` in the main set** | **no** | **YES, run 1, seeds `{}`** |
| distinct SQL statement shapes across the main set | 10 | **15** |
| statement shapes LOST | — | **0** |

The five gained shapes are the whole write chain:

```
INSERT INTO "aspect_memberships" ("aspect_id", "contact_id") VALUES (?, ?)
UPDATE "contacts" SET "contacts"."receiving" = true WHERE "contacts"."id" = ?
UPDATE "notifications" SET "notifications"."unread" = false WHERE … 'Notifications::StartedSharing' …
SELECT "aspect_memberships".* … WHERE "contact_id" = ? AND "aspect_id" = ? … LIMIT 1   (the presenter read)
SELECT "aspects".* FROM "aspects" WHERE "aspects"."id" = ?
```

Runs 2 and 5 also change tails; runs 3, 4 and 6 (locale `xx`, `Person.find`
miss, `blocks.exists?`) are bit-for-bit the same decisions as before. The
self-contact 409 is **no longer the default outcome** — it is now the
flipped one.

### 8.5 Nothing is lost — the 409 is recovered by the explorer's own flip

The concern is that the fix trades one branch for another. It does not: the
decision `(<contact>_user_id == <contact>_person_owner_id)` is still
recorded, still flippable, and the explorer's own `flip_seed` produces the
seed for it. Replayed (`EXTRA_SEEDS_JSON` + `SEEDS_ONLY`) with exactly that
one seed —
`{"SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_user_id": 760954875}`,
the other operand's value, which is what `flip_seed` emits for
`want_taken = true` — the run's path signature is **identical to the pre-fix
default run's**, all 14 decisions, same values. The two outcomes have
swapped default and flip roles; neither has been foreclosed.

### 8.6 Reproducibility, measured

The main set was run twice with the final file. Both: 6 runs / 6 distinct
paths / 0 errors, identical `exploration_summary.json`. Comparing all six
dumps line by line after normalising Ruby object addresses, **the only
differing field is `lineno`** (the two runs straddled a comment-only edit to
`concolic_targets.rb`, which moved line numbers; 0 differences of any other
kind, across all six dumps). Every derived id matches the value computed by
a standalone `Digest::MD5` outside the harness.

### 8.7 `comments_index` — the control

`comments_index` records no id-equality decision at all, so it is the clean
control for "does this change only what it should". Before and after, on the
same runner:

* `exploration_summary.json` **identical** (6 runs, 5 distinct paths,
  25 seeds queued, `run_errors: {}`, `unflippable_pcs: {}`);
* 5 path signatures before, 5 after, **0 lost, 0 gained**;
* per dump, identical variable sets and identical event counts;
* the ONLY differences are id VALUES (e.g. `first_1_id` 1 → 24642315,
  `first_1_author_id` 0 → 41408718) and `file`/`lineno`.

Worth noting what the control also shows: before the fix
`..._records_1_row_author_profile_id` and `..._first_1_id` were both `1` —
a Profile and a Post compared equal. No code on that endpoint asks, so
nothing was foreclosed there; the same latent collision on the write
endpoint is what cost the INSERT.

### 8.8 Regenerated, and what was deliberately NOT regenerated

Regenerated with the fixed file: the main set (6 dumps +
`exploration_summary.json`), `write_path/` (4 dumps, unchanged
`write_path_seeds.json` — every one of its four seed sets still reaches the
write, since each pins at least one operand to a value the other's hash does
not equal), and `../comments_index/` (5 dumps).

NOT regenerated, by instruction: `policy_example.txt`,
`policy_example_main.txt`, `POLICY_EXAMPLE.md` and the three
`dump_examples/` trees. **They are now stale** — they were built from the
pre-fix dumps and still show the old id values. They need one rebuild pass
once the concurrent work settles.

### 8.9 A confound to be aware of

`src_new/runtimes/ruby_runtime` was being edited by other sessions during
this work (`term.rb` and `call_interceptor.rb` both changed this morning).
Re-running the PRE-FIX corpus reproduced its `exploration_summary.json`
exactly but NOT its dumps: the committed dumps carry
`"result_value": "#<User:0x…>"` fields that the current runtime no longer
emits, and some event keys are ordered differently. That difference is not
from this change — both the before and the after measurements above were
taken on the same current runtime, minutes apart, so the comparison isolates
the seeding change. But the newly installed dumps differ from the committed
ones in that respect too, and that part is somebody else's edit, not this
one.

A backup of the whole pre-change `results4` is at
`/home/dev/project/_trash/results4_backup_d8_20260925_1027`.
