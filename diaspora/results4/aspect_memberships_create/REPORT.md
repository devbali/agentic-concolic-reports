# aspect_memberships_create — REPORT

## 1. What was produced

`/home/dev/project/reports/diaspora/results4/aspect_memberships_create/`

| set | dir | runs | distinct paths | run errors | genuine (≥1 PC) | vacuous | unflippable | worklist |
|---|---|---|---|---|---|---|---|---|
| main (budget) | `./` | 6 | 6 | **0** | 6 | 0 | **0** | **not drained** — 45 seeds queued at `MAX_RUNS` |
| write path (seeded replay) | `./write_path/` | 4 | 4 | **0** | 4 | 0 | 0 | drained (`SEEDS_ONLY`) |

Launched exactly as specified: `MAX_RUNS=6 TIME_BUDGET=600 scripts/diaspora-concolic .../run_dse.rb`. Both `exploration_summary.json` files report `run_errors: {}`; no dump carries an `error`. One dump carries a `concolic_terminal` — `I18n::InvalidLocale` on `dump_auth_json_dse0003.json` — a real app outcome (`set_locale` 500s on an unavailable `users.language`), not a framework wall.

The six main paths: (1) full validation chain → `not_contact_for_self` → 409; (2) same + the `language="pl"` inflected-locale `profiles` read; (3) `language="xx"` → `I18n::InvalidLocale`; (4) `Person.find` misses → the controller's own `rescue_from` → 404; (5) aspect finder misses; (6) `blocks.exists?` true → blocked → 409.

## 2. Does the insert show up? Yes — with a full producer chain

All four `write_path` dumps carry real DML. The defining statement:

```sql
INSERT INTO "aspect_memberships" ("aspect_id", "contact_id")
VALUES ($$(SYM_RESULT_ActiveRecord__FinderMethods_first_1_id),
        $$(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_id))
```

`first_1` is `current_user.aspects.where(id: params[:aspect_id]).first`; `find_by_1` is `contacts.find_or_initialize_by(person_id: person.id)`. Also recorded: the `contacts` UPDATE (`SET "receiving" = true`), the `contacts` INSERT on the contact-missing arm, and the `notifications` UPDATE (`SET "unread" = false WHERE "type" IN ('Notifications::StartedSharing') AND …`). Both entrypoint parameters reach SQL as genuine binds: `$$(SYM_PARAM_aspect_id)` and `$$(SYM_PARAM_person_id)`.

**Honest qualification:** the write is not in the main 6-run set. It sits behind one branch flip the FIFO worklist had not reached. `write_path/` uses the same runner and targets with `EXTRA_SEEDS_JSON` + `SEEDS_ONLY` (RUNBOOK Phase 2's "construct runs from counterexamples"). A 40-run pass (not kept) ran clean with 32 distinct paths and 0 errors but also did not reach the write, for the reason in D8.

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

**D8 — cross-rep id collision forecloses `record_a == record_b`, and the flip is ineffective.** Every symbolic instance's default id is `1`, so any two independently-loaded records compare equal, making `not_contact_for_self` fire by default — the rare real state is presented as the default outcome. Worse, an association rep's id variable and the owner's FK column variable can render to the same name, so seeding one moves both together and the run is silently deduped. **This is why the write was never reached within budget** — a new instance of the naming-collision class `assoc_base_name` was introduced to fix.

**D9 — a raising finder's pending note lands on the next target call (Class S).** Not fixable from a mock; statement isn't lost, just mis-attributed.

**D10 — `UniquenessValidator` binds the CAST value, not the symbol (Class S).** `validates :person_id, uniqueness: {scope: :user_id}` reads its values through AR's type-cast pipeline — `record.read_attribute_for_validation(attribute)` for the validated column and `record._read_attribute(scope_item)` for each scope column — both of which run `ActiveModel::Type::Integer#cast` -> `CastableSymbolicInt#to_i` and hand back a bare Integer. The relation the probe is then rendered from carries concrete binds, and the note came out
`… "contacts"."person_id" = 1 AND "contacts"."user_id" = 1 …` on the write arm. The record still holds BOTH symbols in `attributes_before_type_cast` (probed); only the two readers drop them. Fixed batch-locally in `./targets.rb` §8 (`AmUniquenessSymbolicBinds`, a prepend that substitutes by COLUMN NAME — never by value: D8 makes a value lookup ambiguous by construction).

**D11 — `?` placeholders and collected binds are two different lists (Class S, silent mis-attribution).** `ConcolicTargets.render_relation_sql` renders the SQL with one pass (`visitor.accept` -> `"?"` per emitted bind) and collects the binds with another (`collect_binds` over the AST), then zips them positionally with `sql.gsub("?")`. The lists are not the same length: activerecord-5.2.4.3 wraps EVERY hash condition in a `BindParam`, nil ones included (`where.not(id: nil)`, which the uniqueness validator adds for a persisted record), while arel-9 short-circuits a bind whose `nil?` is true and emits `IS NULL` / `IS NOT NULL` with NO placeholder. Probed on the real relation: `qmarks = 2, collected = 3`, so the user_id placeholder consumed the nil `id` bind. **Every bind after the first nullable condition is shifted onto the wrong value** — here it happened to land on nil, but the same shift renders `$$(<wrong producer>)`. Two instances in these dumps: the uniqueness probe's `user_id`, and `AspectMembership.where(contact_id: <nil>, aspect_id: <sym>)` (14 notes/dump). Fixed batch-locally in `./targets.rb` §9: substitute at the single point that emits a placeholder (`Arel::Collectors::SQLString#add_bind`), which makes the mapping exact by construction and also removes a second latent bug (a literal `?` inside a quoted SQL string consumed a bind).

## 5. Open / not done

1. The write is not in the main 6-run set — cause is D8, not a wall. More runs alone won't fix it.
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
