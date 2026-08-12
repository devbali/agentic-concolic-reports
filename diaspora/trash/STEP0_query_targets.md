# Step 0 — ActiveRecord framework-level query targets (AR 5.2.4.3)

Deliverable for `PLAN_symbolic_query_ops.md` §2. Verified against the installed
gem source: `~/.gem/jruby/2.6.0/gems/activerecord-5.2.4.3/lib/active_record/`.

## Dispatch architecture (why these are the right layer)

- **Model class methods are pure delegation.** `Querying` (querying.rb:5-16)
  does `delegate :find, :take, :first, ..., :count, :update_all, ... to: :all`.
  `Post.find(1)` ≡ `Post.all.find(1)` — every class-level query call lands on a
  `Relation` instance method. Intercepting the Relation-side module methods
  therefore catches BOTH `Post.find(1)` and `Post.where(...).find(1)`.
- These modules are framework code, identical for every model and every Rails
  app → application-agnostic targets (Bali's requirement).
- Their return values flow **directly to app code** (unlike adapter
  `select_all`, whose return is consumed by `find_by_sql` plumbing —
  `column_types`, `.length`, `.map { instantiate }` — before the app sees it).
- **Intercept `records` too** (revised 2026-08-05): enumeration (`posts.each`,
  `.map`) routes through `records` via `Delegation`, NOT through `to_a` —
  without this, iteration silently executes real SQL. With the public finders
  (`find`, `first`, `exists?`, `count`…) all mocked, no internal framework
  caller reaches `records` in practice; if one does, iterating the returned
  SymbolicList raises `NotImplementedError` loudly (contents are out of scope
  by design — correct behavior). Still do NOT intercept `exec_queries` /
  `find_take` / `find_nth` (never called once the outer methods are mocked).

## Target table

Legend: return shape = what the mock must return. PCs then come from the app
branching on that value.

### A. Single-record finders → symbolic model instance (§4 of plan, redesigned: real klass via `allocate` + singleton symbolic attr readers from `klass.columns_hash`; absence handled at mock boundary, not via null flag)

Module: `ActiveRecord::FinderMethods` (relation/finder_methods.rb)

| Method | Signature | Real return | Mock return | Notes |
|---|---|---|---|---|
| `find` | `find(*args)` | model or raises `RecordNotFound` | `SymbolicObject` | null branch semantics = raise, not nil — see "find vs find_by" below |
| `find_by` | `find_by(arg, *args)` | model or `nil` | `SymbolicObject` (null flag encodes absence; never bare nil) | |
| `find_by!` | `find_by!(arg, *args)` | model or raises | `SymbolicObject` | raise semantics |
| `take` / `first` / `last` | `(limit = nil)` | model or nil (array if limit given) | `SymbolicObject`; `limit` variant → unimplemented | `take(n)`/`first(n)` return arrays — raise `NotImplementedError` for the arg form |
| `take!` / `first!` / `last!` | | model or raises | `SymbolicObject` | raise semantics |
| `second`…`forty_two`, `*_to_last` (+ `!` variants) | | model or nil/raise | `SymbolicObject` | rare; can raise unimplemented if not needed by diaspora |

### B. Existence / emptiness → `SymbolicBool`

| Method | Module | Real return | Mock return |
|---|---|---|---|
| `exists?` | FinderMethods (finder_methods.rb:305) | true/false | `SymbolicBool` |
| `empty?` | Relation (relation.rb:215) | true/false (COUNT if unloaded) | `SymbolicBool` (or route through SymbolicList length) |
| `any?` / `none?` / `one?` / `many?` | Relation (relation.rb:221-244) | true/false | `SymbolicBool` |

⚠️ Ruby truthiness gap applies: `if Post.exists?(...)` on the returned
`SymbolicBool` records NO PC (src/TODO.txt). Only `== true/false`, `!`, `!=`
compares record. Decision (Bali 2026-08-05): still return the SymbolicBool —
useful for explicit compares, harms nothing. Proper fix = intercepting the
interpreter's truthiness evaluation; queued in TODO.txt as future work.

### C. Collection materialization → `SymbolicList` (symbolic length only)

Module: `ActiveRecord::Relation` (relation.rb) + Enumerable via `Delegation`

| Method | Real return | Mock return | Notes |
|---|---|---|---|
| `to_a` / `to_ary` | Array of models | `SymbolicList` | |
| `records` | Array (nodoc) | `SymbolicList` | **required** — `each`/`map` route here via Delegation, not `to_a` |
| `size` / `length` | Integer (COUNT or loaded size) | `SymbolicInt` (the list length) | |
| `each` / `map` / other Enumerable | iteration | **`NotImplementedError`** | contents are out of scope by design (count dimension only) |
| `find_each` / `find_in_batches` / `in_batches` (Batches) | iteration | **`NotImplementedError`** | |

### D. Calculations → `SymbolicInt` (or unimplemented)

Module: `ActiveRecord::Calculations` (relation/calculations.rb)

| Method | Real return | Mock return |
|---|---|---|
| `count` | Integer | `SymbolicInt` |
| `sum` | numeric | `SymbolicInt` |
| `average` / `minimum` / `maximum` / `calculate` | varies | `NotImplementedError` (until needed) |
| `pluck` / `ids` | Array | `NotImplementedError` (returns contents — out of scope) or `SymbolicList` if only length is used |

### E. Relation-level DML → `SymbolicInt` (rowcount)

Module: `ActiveRecord::Relation`

| Method | Line | Real return | Mock return |
|---|---|---|---|
| `update_all(updates)` | relation.rb:315 | Integer rowcount | `SymbolicInt` |
| `delete_all` | relation.rb:386 | Integer rowcount | `SymbolicInt` |
| `destroy_all` | relation.rb:364 | Array of destroyed records | `SymbolicList` (length = destroyed count) |

### F. Instance persistence → `SymbolicBool` / `SymbolicObject`

Module: `ActiveRecord::Persistence` (persistence.rb)

| Method | Real return | Mock return | Notes |
|---|---|---|---|
| `save` / `update` / `update_attribute` / `update_columns` / `touch` / `increment!` / `decrement!` / `toggle!` | true/false | `SymbolicBool` | |
| `save!` / `update!` / `destroy!` | self or raises | `SymbolicObject` or raise semantics | |
| `destroy` / `delete` | self (frozen) | pass-through or `SymbolicBool` | |
| `reload` | self re-fetched | `SymbolicObject` | |
| class `create` / `create!` | new model | `SymbolicObject` | |
| class `update(id, attrs)` / `destroy(id)` / `delete(id)` | model / count | per shape above | |

Note: these fire on model *instances*. In the symbolic design the app usually
holds a `SymbolicObject`, not a real model — so `post.save` hits the
SymbolicObject allowlist first. Decide: either add `save`/`destroy` etc. to the
SymbolicObject allowlist (returning SymbolicBool), or accept
`NotImplementedError` there. Only relevant for write-path experiments.

### G. Raw SQL entry points → intercept and raise (or map)

Module: `ActiveRecord::Querying`

| Method | Notes |
|---|---|
| `find_by_sql(sql, binds)` | returns Array of models → `SymbolicList` if hit by app code |
| `count_by_sql(sql)` | → `SymbolicInt` |

### H. Associations (flagged, phase 2)

`post.comments` (CollectionProxy ≈ Relation → categories B/C/D/E apply),
`post.author` (singular reader → model-or-nil → `SymbolicObject`). In the
symbolic design the receiver is already a `SymbolicObject`, so association
reads surface as *attribute/method access on SymbolicObject* — they never
reach AR. Handle by declaring association names in the fixed attrs map
(e.g. `attrs["author"] => SymbolicObject`) if a scenario needs them. No AR
interception required.

## `find` vs `find_by` semantics (decided with Bali, 2026-08-05)

`find` raises `RecordNotFound` on absence; `find_by`/`take`/`first` return nil.

**Decided pattern:** the `find` mock lambda inline-declares a symbolic bool and
branches on it — raise if true, return the record if false. The branch is
ordinary harness code on a symbolic value, so the PC is recorded by normal
comparison interception (no special raise machinery in the runtime), and the
engine negates it to produce the not-found run:

```ruby
ConcolicHarness.declare_target(FinderMethods, :find) do |receiver, args, name|
  # No SQL string exists at the framework layer, but the Relation can render
  # one without executing: receiver.to_sql (relation.rb:445). The SQL goes in
  # the var's `note` (dumped to run records; NOT part of the Z3 name) and in
  # the raise message, so a not-found trace shows exactly WHICH query came
  # back empty — while the Z3 name stays short and clean.
  sql = receiver.to_sql rescue "#{receiver.klass.name}.find(#{args.inspect})"
  not_found = symbool("#{name}_not_found", false, note: sql)  # concrete seed: found
  if not_found == true                                # explicit compare — records PC
    raise ActiveRecord::RecordNotFound, "concolic: empty result for: #{sql}"
  else
    SymbolicObject.new(..., name: name, attrs: { ... }, note: sql)
  end
end
```

⚠️ Must be the explicit `not_found == true` compare in Ruby — bare
`if not_found` hits the truthiness gap (src/TODO.txt) and records nothing.
The Python mirror may use plain `if not_found:` (`__bool__` is hookable).

**`note` attribute (decided 2026-08-05):** symbolic vars gain an optional
`note: String` — arbitrary human-facing context dumped into run records
(`{name, sort, value, note}`) but never part of the Z3 name or exprs. No
sanitization needed; solver and path signatures unaffected. Engine only needs
to tolerate the extra optional field.

**Universal rule:** every mock in this table sets `note` on **every** symbolic
var it creates — null flags, all SymbolicObject attr vars, SymbolicList length
vars, and scalar returns (count/exists?/rowcounts). For SELECT-backed ops the
note is `receiver.to_sql`; for instance DML (`save`, `update`) it's an
operation description (e.g. `"post.save → UPDATE posts"`). `SymbolicObject.new`
and `SymbolicList.new` take `note:` and propagate to their internal vars so
harness lambdas pass it once.

**Remaining caveats:**
- `to_sql` on a bare `find(id)` reflects the relation *before* the id
  predicate is merged; include `args` in the message/note so the id is visible.
- Var names still need per-dump uniqueness (e.g. `post_not_found` firing twice
  in one run) — suffix with an occurrence counter if the same target fires
  multiple times.

The same pattern generalizes: `find_by` uses the inline symbolic bool to set
the null flag on the returned `SymbolicObject` (no raise); `exists?`/`save`
mocks return the `SymbolicBool` directly.

## Which diaspora call sites hit which target

| App call | Delegation path | Target that fires |
|---|---|---|
| `Post.find(id)` | Querying#find → all.find | A: FinderMethods#find |
| `Post.find_by(guid: g)` | → all.find_by | A: find_by |
| `Post.where(public: true).exists?` | Relation#exists? | B |
| `EvilQuery...post!` (`.first` on relations) | FinderMethods#first | A |
| `user.contacts.count` | Calculations#count | D (via H) |
| `Post.where(...).destroy_all` | Relation#destroy_all | E |
| `post.save` | Persistence#save | F (see SymbolicObject note) |

## Interception mechanics note

`declare_target(Module, :method)` must prepend/wrap on the **module**
(`FinderMethods`, `Relation`, `Calculations`, `Persistence`) or on
`ActiveRecord::Relation` directly, so it catches every model uniformly.
Class-level delegated calls arrive via `all` → same Relation methods → one
interception point covers both spellings.
