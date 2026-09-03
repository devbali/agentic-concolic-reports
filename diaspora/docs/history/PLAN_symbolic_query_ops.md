# Diamond Implementation Plan: Symbolic Query Operations for the Diaspora Concolic Experiment

**Status:** Plan only — no implementation yet. Owned by Bali Sahab; to be executed by a coding agent.

**Context:** Extend the concolic runtime (both `ruby_runtime/` and `py_runtime/`) so that a real Rails app's query operations can be declared as interceptor targets returning **symbolic objects/lists**. The app branches on these symbolic values at the query boundary, producing real path conditions — without fighting ActiveRecord's attribute coercion.

---

## 1. Background & goal

The Diaspora experiment drives a real Rails 5.2 app (JRuby) through a stubbed DB connection. `ConcolicHarness::Adapter#execute` is currently the single SQL target. Problems:

- Rows returned are concrete hashes; `select_all` explicitly runs `to_native` on every cell → symbolic values never survive.
- Even if they did, AR's type casters would collapse `SymbolicInt`/`SymbolicString` to concrete at attribute reads (`post.public?`).
- So real-app runs emit `call`/`symbolic_call` events but **zero `path_condition` events**.

**The fix (confirmed with Bali):** Declare the query operations themselves (`select_all`, `select_one`, `insert`, `update`, `delete`, …) as **separate interceptor targets**, each returning a **symbolic** value. The app branches *on that returned value* (`if post.nil?`, `rows.empty?`, `row[:public] == 1`), so the symbolic values are the interface — AR never materializes a model from them, so there is no coercion wall.

### Coverage model
- **`select_one` / `find` → one `SymbolicObject`**: symbolic **null flag** + **all attributes symbolic**. Deep per-object branching.
- **`select_all` → `SymbolicList`**: symbolic **length / count / emptiness**. Items present but **indexing and attribute access are unimplemented** (raise our unimplemented error). Branching is on how many rows, not what's inside.

### Hard constraints
- **All runtime additions must be mirrored in BOTH `ruby_runtime/` and `py_runtime/`.**
- **No structural change to the `concolic_engine`** (Python CoverageChecker / `Run.from_dict` / solver). Rationale: the new types only add more `path_condition` events (null-checks, length-checks, attr-compares) with Z3-parseable exprs, plus more declared symbolic vars in `symbolic_results`. The IR boundary already handles those. **If an engine change seems needed, stop and re-check — it probably means the runtime is emitting something the IR wasn't designed for.**
- Follow the existing "source discipline": shared runtime files stay generic mirrors; task-specific logic (query-op mocks) lives in the harness / runner scripts, not in `ruby_runtime/` base types.

---

## 2. Step 0 — locate the real query-op methods (do this first)

Before writing any type, enumerate the concrete ActiveRecord methods that constitute the query boundary. These are the functions to declare as targets.

**⚠️ Layer constraint (verified against activerecord-5.2.4.3 source):** the adapter layer (`select_all` etc.) is the WRONG place to return symbolic objects. `Querying#find_by_sql` immediately calls `.column_types`, `.length`, and `.map { instantiate(...) }` on `select_all`'s return — AR plumbing consumes it before app code ever sees it, hitting the allowlist `NotImplementedError` (or rebuilding concrete models). The targets must instead be the **generic ActiveRecord public query API** — e.g. `FinderMethods#find` / `#find_by` / `#take`, `Relation#exists?` / `#count` / `#to_a`, `Persistence` methods for DML. These are framework modules (application-agnostic, per Bali — they work for any model in any Rails app); their return values flow directly to app code. Step 0's job is to pin down this exact method set.

**Files:** `~/.gem/jruby/2.6.0/gems/activerecord-5.2.*/lib/active_record/finder_methods.rb`, `relation.rb`, `querying.rb`, `persistence.rb` (adapter files `abstract_adapter.rb` / `abstract/database_statements.rb` only for reference on how dispatch bottoms out).

**Identify and record for each op:**
- Exact method name + signature.
- Which framework module/class it lands on (`FinderMethods` vs `Relation` vs `Persistence` vs model class methods).
- Return shape as seen by APP code: `find`/`take` → model-or-nil (→ `SymbolicObject`); `to_a`/`records` → array (→ `SymbolicList`); `exists?` → bool; `destroy_all`/`update_all`/`save` → count/bool.
- **Crucially:** confirm for each that the return value reaches app code untouched (no AR plumbing calls methods on it in between). That is the selection criterion for the target layer.
- How `Post.find`, `Post.where`, `Post.destroy_all`, `post.save` dispatch to these (so we know which target fires per call site).

**Deliverable:** an annotated table (op → method → signature → return shape → which app calls hit it). This table drives the `declare_target` calls in Step 5.

**✅ DONE (2026-08-05):** the annotated target table (formerly `STEP0_query_targets.md`, now archived to `trash/`). Summary: model class methods are pure `delegate ... to: :all` → intercept the Relation-side framework modules (`FinderMethods` for find/take/first → symbolic model instance; `Relation`/`FinderMethods` exists?/any?/empty? → SymbolicBool; `Relation#to_a` AND `Relation#records` → SymbolicList; `Calculations#count/#sum` → SymbolicInt; `Relation#update_all/#delete_all/#destroy_all` DML; `Persistence` for save/update). `records` MUST be intercepted — enumeration (`each`/`map`) routes through it via Delegation, not `to_a`; with the public finders also mocked, no internal framework caller reaches it, and any framework iteration over the SymbolicList fails loudly (contents out of scope by design). Still do not intercept `exec_queries`/`find_take`/`find_nth`.

---

## 2b. `note` attribute on symbolic variables (both runtimes)

Add an optional `note: String` attribute to the symbolic-variable base
(`SymbolicVar` in Ruby, base class in Python) and factories
(`symbool(name, value, note: nil)` etc.):

- **Purpose:** arbitrary human-facing context (e.g. the SQL query a mock is
  standing in for). Dumped into the run record alongside the var
  (`{name, sort, value, note}`) but **never** part of the Z3 name or any expr —
  so no sanitization concerns and no effect on solving or path signatures.
- **Universal rule: EVERY query-op mock sets `note` on EVERY symbolic var it
  creates** — the rendered query (`receiver.to_sql`, or an operation
  description for DML like `save`) that the var stands in for. That includes:
  the `not_found`/null `SymbolicBool`, **each attr var** of a returned
  `SymbolicObject` (`post_id`, `post_public`, …), the length var of a
  `SymbolicList`, and scalar returns (`count`, `exists?`, `update_all`
  rowcounts). A coverage report saying "flip `post_public`" must be traceable
  to the query whose result row carried that attribute. Var names stay short
  and Z3-clean (`post_not_found`, `rows_len`, `post_null`).
- To avoid per-lambda plumbing, `SymbolicObject.new` and `SymbolicList.new`
  accept `note:` and **propagate it to every var they create internally**
  (null flag, attrs, length). Harness lambdas pass `note: sql` once.
- Engine: `Run.from_dict` must **tolerate** the extra optional field (ignore or
  carry it through for reporting). This is additive/optional — if it requires
  more than accepting an extra key, stop and surface to Bali per §1.

## 3. `SymbolicBool`

Mirror the `SymbolicInt` / `SymbolicString` pattern exactly. Both runtimes.

- Ruby: `ruby_runtime/bool.rb` — `class SymbolicBool` (include `SymbolicVar`), wraps a concrete `true`/`false` in `@value`, records PCs on `==`, `!=`, `!`.
  **⚠️ Ruby truthiness gap:** bare `if obj` calls no method in Ruby — it cannot be intercepted, records no PC, and a wrapper around `false` is still truthy. Known soundness gap, documented in `src/TODO.txt`. Ruby app code must branch via `!`, `==`/`!=`, `.nil?`, `.empty?` for tracking; do NOT claim truthiness PCs in the Ruby runtime.
- Python: `py_runtime/bool_.py` — `class SymbolicBool` (`bool` is not subclassable; make it a plain wrapper with `SymbolicVar`, confirmed OK with Bali), recording PCs on `==`, `!=`, and `__bool__` (truthiness IS interceptable in Python).
- Export from both `__init__` / package.
- Factory helpers `symbool(name, value)` in both.
- Everything else raises the standard `NotImplementedError` (unimplemented concolic operation).

Used for: `SymbolicObject` null flag, boolean row attributes (e.g. `public`).

---

## 4. `SymbolicObject` — REDESIGNED (2026-08-05): symbolic-attribute instance of the real model class

**Superseding decision (Bali):** instead of an opaque allowlisted wrapper, the
symbolic object **inherits/embodies the original class** with symbolic
attributes. This lets real behavior methods (`post.visible_to?(user)`, enum
helpers, scopes on self) execute their actual code and branch on symbolic
attrs → genuine PCs from real app logic, instead of `NotImplementedError`.

### Mechanism
- **Ruby:** in the mock, `obj = receiver.klass.allocate` (skips `initialize`,
  AR callbacks, DB). Define **singleton attribute readers** for each column
  returning the symbolic value; also override `[]`, `read_attribute`,
  `_read_attribute`, and `fetch`-style access so every access path bypasses
  AR's type-casting wall. Attrs + sorts come from `receiver.klass.columns_hash`
  (column type → SymbolicInt / SymbolicString / SymbolicBool) — no
  hand-maintained schema map.
- **Python mirror:** generic helper `make_symbolic_instance(cls, attrs)` —
  `object.__new__(cls)` + set attributes to symbolic values. (Generic runtime
  helper; Rails-specific reader overrides live in the harness.)
- Methods that would hit the DB (associations, reload) route back into the
  mocked framework targets — loud, covered. Operations unsupported on the
  symbolic attr types raise the standard `NotImplementedError` — loud.

### Null handling — no null flag on the object
A real model-class instance can never be nil-like (`obj.nil?` is concretely
false). Absence is decided **at the mock boundary** with the inline-symbool
pattern (§6): record the PC via explicit compare, then raise `RecordNotFound`
(find) or return concrete `nil` (find_by/take/first). The app then branches
concretely but consistently with the recorded PC.

### Serialization
The object is no longer a `Symbolic` type with its own `to_dict`; the
constructor/harness **registers each attr var** (with `note:` = SQL) into
`symbolic_results` at creation time.

### Truthiness caveat
Predicate readers (`post.public?` → SymbolicBool) still face the Ruby
truthiness gap in `if post.public?` (src/TODO.txt; interpreter-level
interception is future work).

---

The original allowlisted-wrapper design below is kept for reference; the
attr-symbolic-types idea and "unsupported ops raise" principle carry over.
The null-flag-on-object design is superseded by the section above.

### Shape
```ruby
SymbolicObject.new(
  value_or_nil,                 # concrete wrapped value (an object/hash or nil)
  name: "post",                 # Z3-friendly base name
  null: SymbolicBool,           # symbolic "is null" flag (like list length)
  attrs: {                      # ALL attributes symbolic
    "id"      => SymbolicInt.new(1,    name: "post_id"),
    "public"  => SymbolicBool.new(1,   name: "post_public"),
    "guid"    => SymbolicString.new("g-1", name: "post_guid"),
  }
)
```
- `value` is `nil` when the null flag is true; the wrapped concrete object otherwise.

### Allowlist — the ONLY supported concolic operations
Per Bali: *"The exact allowlist should be all we can do with a fixed attribute list and symbolic objects for them."* So `SymbolicObject` supports exactly:

| Operation | Behavior | PC recorded |
|-----------|----------|-------------|
| `obj.nil?` | branch on the null flag | `(post_null == true)` / `Not(...)` |
| `obj == nil` / `obj != nil` (and Python `if obj` via `__bool__`) | null-check branching | same null PC |
| Ruby bare `if obj` | **NOT interceptable** — always truthy, no PC (see `src/TODO.txt`) | none (gap) |
| `obj == other` / `obj != other` | identity/equality on the null flag + wrapped value | null PC (+ value compare for non-null) |
| `obj["attr"]` / `obj[:attr]` / `obj.fetch("attr")` | return the symbolic attribute value | none (return, no branch) |
| `obj.attr` (declared attr only) | return the symbolic attribute value | none |
| `obj.attrs` | return the attrs hash | none |
| `obj.null` | return the null `SymbolicBool` | none |
| `to_dict` / serialization | emit null + per-attr symbolic vars | — |

Any method NOT in this list → raise the standard `NotImplementedError` (unimplemented concolic operation). Specifically **no** generic `method_missing` forwarding (to avoid collisions with Ruby `Object` methods like `class`, `object_id`, `inspect`, `freeze`). Concrete `to_s`/`inspect`/`== nil` on the *wrapped value* are **not** auto-delegated unless explicitly allowlisted — decide and lock the explicit set during implementation; the default is: allowlist only, everything else raises.

### Attribute semantics
- The `attrs` hash is **fixed at construction** (the "fixed attribute list").
- Each attr value is a symbolic type (`SymbolicInt`, `SymbolicString`, `SymbolicBool`) — the per-cell symbolic values.
- Reading an attr returns the symbolic object **directly** (no coercion). `if obj["public"] == 1` branches on the `SymbolicBool`/`SymbolicInt` comparison → PC recorded.

### Serialization (`to_dict`)
Emit into `symbolic_results` / IR:
- The null flag as a `Bool` var (e.g. `name: "post_null", sort: "Bool", value: true/false`).
- Each attr as a var (`name: "post_id", sort: "Int", value: 1`, etc.).
- An object descriptor for the engine/debugger (name, attrs list).

---

## 5. `SymbolicList`

Confirm/extend the existing `SymbolicList` (the harness references it conditionally). Both runtimes, mirror each other.

### Shape (per Bali, 2026-08-05)
`SymbolicList` is **just a wrapper around a symbolic length** — nothing else. No concrete length, no items exposure.

```ruby
SymbolicList.new(
  concrete_length,      # used only to seed the symbolic length's concrete value
  name: "rows",
)                       # internally holds length: SymbolicInt ("rows_len")
```

### Allowlist
| Operation | Behavior | PC recorded |
|-----------|----------|-------------|
| `list.empty?` | branch on length == 0 | `(rows_len == 0)` / `Not(...)` |
| `list.length` / `list.size` | return the **symbolic** length (`SymbolicInt`) — never a concrete int | none (return; comparisons on it record PCs) |
| `to_dict` | emit the length var | — |

**Everything else raises `NotImplementedError`** — in particular ALL element access: `list[i]`, `list.first`, `list.last`, `list.each`, `list.map`, `list.items`, iteration of any kind. The engine sees the count dimension only.

**Note:** the existing `ruby_runtime/list.rb` violates this (concrete `length`/`size`, `items` accessor, `any?`) — bring it in line: drop the items array and concrete accessors, keep only symbolic-length semantics. Mirror in `py_runtime`.

Branching = **count/emptiness**, not contents.

---

## 6. Harness changes — declare query ops as separate targets

In `concolic_harness.rb` (task-specific, allowed to be task-specific):

- Replace the single `execute`-only interception with explicit per-op targets on the **framework query-API methods** from the Step-0 table (generic AR modules, NOT adapter methods — see §2 layer constraint):
  ```ruby
  # find: inline symbolic bool in the mock — raise on true, record on false (decided pattern,
  # see concolic_targets.rb "find vs find_by"). PC comes from the explicit == compare.
  # SQL goes in the var's `note` (dumped to run records, not part of the Z3 name)
  # and in the raise message, so a not-found trace shows WHICH query returned empty.
  ConcolicHarness.declare_target(FinderMethods, :find) do |receiver, args, name|
    sql = receiver.to_sql rescue "#{receiver.klass.name}.find(#{args.inspect})"
    not_found = symbool("#{name}_not_found", false, note: sql)
    raise ActiveRecord::RecordNotFound, "concolic: empty result for: #{sql}" if not_found == true
    SymbolicObject.new(..., name: name, attrs: { ... }, note: sql)
  end
  ConcolicHarness.declare_target(FinderMethods, :find_by) { |args, name| SymbolicObject.new(...) }  # null flag encodes absence — never bare nil
  ConcolicHarness.declare_target(Relation, :to_a)         { |args, name| SymbolicList.new(...) }
  ConcolicHarness.declare_target(FinderMethods, :exists?) { |args, name| SymbolicBool.new(...) }
  # DML (update_all / destroy_all / save paths) → SymbolicInt / SymbolicBool per Step-0 table
  ```
- **Never `SymbolicObject.new(...) or nil`** — returning bare `nil` for the empty case would defeat the symbolic null flag. The object is always returned; `null` carries absence.
- **Remove the `to_native` cell-collapse** in the old adapter stub — cells stay symbolic wherever the old path remains.
- Each op returns the shape that drives the app's branching (`SymbolicObject` for find/one, `SymbolicList` for all, `SymbolicInt`/`SymbolicBool` for DML).

---

## 7. Engine side — expected NO change (verify only)

- `Run.from_dict` already parses `path_condition`, `call`, `symbolic_call` events and declared symbolic vars. The new null/length/attr PCs are just more PCs.
- The solver gains nothing new: null → Bool, length → Int, attrs → existing Int/String/Bool sorts.
- **Action:** after runtime work, run the existing Python tests + a Ruby→Python roundtrip to confirm the engine is unchanged and still green. If anything in the engine must change, flag it to Bali before proceeding.

---

## 8. Verification

1. **Ruby:** extend `test_ruby_runtime.rb` (or add a section) asserting:
   - `select_one` returns a `SymbolicObject`; `obj.nil?` on a non-null object records `(x_null == false)`-style PC; on a null object records the true branch.
   - `obj["public"] == 1` records an attr PC.
   - list-returning ops return a `SymbolicList`; `rows.empty?` records a length PC; `rows.length` returns a `SymbolicInt` (comparisons on it record PCs); `rows[0]` / `rows.first` / `rows.each` raise `NotImplementedError`.
   - Unsupported `SymbolicObject`/`SymbolicList` methods raise `NotImplementedError`.
2. **Python:** mirror the same tests in `test_symbolic.py` (or new file), since both runtimes must stay in parity.
3. **Roundtrip:** Ruby produces RunDump with the new symbolic vars → Python `Run.from_dict` + `CoverageChecker` consume it, engine unchanged, and reports missing branches for the new null/length PCs.
4. **Diaspora smoke:** re-run `test_symbolic_rows.rb` and require it to now show **≥1 `path_condition`** (e.g. on `post.nil?` / attr compare), not just call/symbolic_call events.

---

## 9. Deliverables check

- [ ] Step 0: annotated table of real query-op methods (commit to plan or a `.md` in `reports/diaspora/`)
- [ ] `note` attribute on symbolic vars in both runtimes; dumped in run records, ignored by Z3 naming; engine tolerates the extra field
- [ ] `SymbolicBool` in `ruby_runtime/` + `py_runtime/`
- [ ] `SymbolicObject` in both runtimes (null flag + all-symbolic fixed attrs, allowlisted ops, rest raises)
- [ ] `SymbolicList` count/emptiness in both runtimes (items opaque for `select_all`)
- [ ] Harness: per-op targets, no `to_native` collapse
- [ ] Python engine verified unchanged + roundtrip green
- [ ] Ruby + Python test suites extended and passing
- [ ] Diaspora smoke test shows ≥1 PC

---

## 10. Notes / open decisions (lock during implementation)

- **Exact `SymbolicObject` allowlist** — the table in §4 is the proposal; finalize the explicit method set (esp. whether `to_s`/`inspect`/`to_h` are allowed or raise). Default: allowlist only, everything else raises.
- **`select_all` item serialization** — opaque placeholders vs. `SymbolicObject` items. Default: opaque (count dimension only), per Bali's spec.
- **Attribute naming** — ensure Z3-safe var names from attrs (`obj_null`, `obj_<attr>`); collision-check across runs in the same dump.
- If during implementation the engine genuinely needs a change, **pause and surface to Bali** — do not silently modify the shared engine.
