# How Rails/Ruby Is Mocked & Concolified (Diaspora Experiment)

Reference document for the diaspora concolic setup: what runs for real, what is
mocked, which functions are declared as interceptor targets, and what each mock
returns. Companion to `PLAN_symbolic_query_ops.md` (design rationale); the
framework-level target table that preceded this was archived to `trash/`. Sections marked **[current]**
describe what exists today; **[planned]** describes the framework-level design
about to be implemented.

---

## 1. The stack

| Layer | What | Real or mocked |
|---|---|---|
| Interpreter | JRuby 9.3.0.0 on Java 21 (`/home/dev/tools/`) | real |
| Framework | Rails 5.2.4.3 + ActiveRecord (198 gems, `Gemfile.minimal`) | real |
| App | diaspora (git submodule, branch `dse-v0.7.14.0`) | real — models, `EvilQuery`, services, controllers all execute their actual code |
| Query API boundary | `Relation` / `FinderMethods` / `Calculations` / `Persistence` | **[planned]** mocked via `declare_target` — returns symbolic values |
| DB connection | `ConcolicHarness::Adapter < AbstractAdapter` | stubbed — **[current]** the interception point; **[planned]** backstop only (see §6) |
| Database | SQLite at `db/concolic.sqlite3` | real file, but never reached during a concolic run |
| Runtime | `src/ruby_runtime/` (SymbolicInt/String/Bool/List, CallInterceptor) | the concolic machinery; mirrors `src/py_runtime/` |
| Engine | `src/concolic_engine/` (Python, Z3) | consumes JSON RunDumps; **unchanged** by this work |

Principle: **the boundary between "real" and "symbolic" is the ActiveRecord
public query API.** Everything above it (app logic) runs for real and is where
path conditions come from. Everything below it (SQL, DB) never executes.

## 2. Interception mechanism

`CallInterceptor#declare_target(klass, :method, returns: lambda)`
(`src/ruby_runtime/call_interceptor.rb`) redefines the method via
`define_method`. On every call it:

1. Snapshots the current path-condition stack.
2. Records a `call` event (args, call site, PC snapshot) into the RunDump.
3. **Skips the original body** and invokes the mock lambda, whose return value
   flows back to the caller as if the framework had produced it.
4. Registers returned symbolic values as `SYM_RESULT_<Class.method>_<idx>` in
   `symbolic_results`.

Because model class methods are pure delegation (`Querying` does
`delegate :find, :take, :count, ... to: :all`), `Post.find(1)` ≡
`Post.all.find(1)` — intercepting the Relation-side module methods catches
every spelling for every model. The targets are framework modules, so nothing
here is diaspora-specific.

**[planned] Required interceptor change:** the mock lambda signature becomes
`(receiver, call_args, result_name)` — mocks need the receiver for
`receiver.to_sql` (the query string) and `receiver.klass.columns_hash` (the
attribute schema). Small generic change in both runtimes' interceptors
(inside the wrapper, `self` is the receiver; pass it through).

## 3. Declared target functions and what their mocks return **[planned]**

The rule for target selection: **any framework method that could downstream
issue a SQL query is a target.**

**Ruby has no decorators, so the target declarations live in a single config
file: [`concolic_targets.rb`](./concolic_targets.rb)** (the Ruby equivalent of
the Python `@target` annotations). It contains every `declare_target` call
with its mock lambda — load order: Rails env → runtime →
`ConcolicTargets.install!`. That file is the executable spec; the table below
is its summary:

| Target (module#method) | Real behavior | Mock returns |
|---|---|---|
| `FinderMethods#find` | model or raises `RecordNotFound` | inline `symbool` branch: raise `RecordNotFound` (with SQL in message) if not-found, else **symbolic model instance** |
| `FinderMethods#find_by`, `#take`, `#first`, `#last` (+ `!` variants) | model or nil | same pattern; nil case returns concrete `nil` (PC recorded at boundary first) |
| `FinderMethods#exists?`, `Relation#any?/#none?/#one?/#many?/#empty?` | true/false | `SymbolicBool` |
| `Relation#to_a`, `#to_ary`, `#records` | Array of models | `SymbolicList` (symbolic length only) |
| `Calculations#count`, `#sum` | Integer | `SymbolicInt` |
| `Calculations#pluck`, `#ids`, `#average`, … | contents | `NotImplementedError` (contents out of scope) |
| `Batches#find_each`, `#find_in_batches`, `#in_batches` | iteration | `NotImplementedError` |
| `Relation#update_all`, `#delete_all` | Integer rowcount | `SymbolicInt` |
| `Relation#destroy_all` | Array of destroyed | `SymbolicList` |
| `Persistence#save`, `#update`, etc. | true/false | `SymbolicBool` |
| `Querying#find_by_sql`, `#count_by_sql` | Array / Integer | `SymbolicList` / `SymbolicInt` |

Notes:
- `records` **must** be intercepted: `posts.each`/`.map` route through it via
  `Delegation`, not `to_a`. Iteration over the result then raises loudly —
  correct, since row contents are out of scope by design.
- Internal funnels (`exec_queries`, `find_take`, `find_nth`) are **not**
  intercepted; they're unreachable once the outer methods are mocked.
- Every symbolic var a mock creates carries `note:` = the rendered query
  (`receiver.to_sql`) or an operation description for DML. `note` is dumped in
  run records but never enters Z3 names/exprs.

## 4. The symbolic model instance (single-record results) **[planned]**

`find`-family mocks return an instance of the **real model class**:

```ruby
obj = receiver.klass.allocate          # skips initialize/callbacks/DB
receiver.klass.columns_hash.each do |col, meta|
  sym = case meta.type                  # :integer/:boolean/:string/...
        when :integer then symint("#{name}_#{col}", seed, note: sql)
        when :boolean then symbool("#{name}_#{col}", seed, note: sql)
        else               symstr("#{name}_#{col}", seed, note: sql)
        end
  obj.define_singleton_method(col) { sym }      # reader
  # plus []/read_attribute/_read_attribute overrides → same symbolic values
end
```

Consequences:
- **Real behavior methods run.** `post.visible_to?(user)`, enum helpers, etc.
  execute their actual bodies and branch on symbolic attrs → genuine PCs.
  This defeats the AR type-casting wall that killed the adapter-level attempt
  (attribute reads no longer go through AR's coercion pipeline at all).
- **No null flag on the object.** A real instance can't be nil-like. Absence
  is decided *inside the mock* (inline `symbool`, explicit compare records the
  PC, then raise/return-nil). App code then branches concretely but
  consistently with the recorded PC.
- Attr vars are registered into `symbolic_results` at construction.
- Associations (`post.author`) hit real AR association readers, which issue
  queries through the mocked framework targets → covered, loudly if not.

## 5. Known gaps & rules

- **Ruby truthiness is not interceptable** (`src/TODO.txt`): bare `if obj` on
  any symbolic value records no PC and can silently take the wrong branch for
  wrapped `false`. App code must branch via `!`, `==`/`!=`, `.nil?`,
  `.empty?`. Interpreter-level interception is future work. (Python mirror
  does not have this gap — `__bool__` is hookable.)
- **Row/collection contents are out of scope.** `SymbolicList` wraps a
  symbolic length and nothing else; all element access/iteration raises the
  standard `NotImplementedError`. Coverage over collections = count/emptiness
  dimension only.
- **Unsupported symbolic ops fail loudly.** `CallInterceptor.run` catches
  exceptions and records them under the RunDump `error` key, with PCs
  collected up to the crash.
- **Engine unchanged.** New PCs (null/length/attr) and the optional `note`
  field are the only IR additions; `Run.from_dict` tolerates `note`. If an
  engine change ever seems necessary — stop and re-check with Bali.
- **Source discipline.** Generic pieces (SymbolicBool, note attribute,
  receiver-passing, list changes) go in `ruby_runtime/` + `py_runtime/` as
  mirrors. Rails-specific pieces (target declarations, symbolic-instance
  builder, adapter stub) live in the harness.

## 6. History: the adapter-level approach **[current, superseded]**

The first attempt intercepted a single low-level target —
`ConcolicHarness::Adapter#execute` — with `select_all` rebuilding
`ActiveRecord::Result` from the mock's rows and coercing every cell
`to_native`:

- `declare_sql_target { |sql, name| [rows, "Result"] }` returned concrete row
  hashes; symbolic cells were explicitly collapsed (`to_native`) because
  `ActiveRecord::Result` → `instantiate` → type casters would crash on (or
  concretize) symbolic values anyway.
- Result: real `EvilQuery::VisibleShareableById#post!` ran all 3 tiers and
  produced `call` events with real SQL strings — but **zero `path_condition`
  events**, since every app-visible value was concrete by the time the app
  branched on it.

That failure is what motivated the framework-level design: return symbolic
values from the methods whose results **app code consumes directly**, instead
of trying to push symbolic cells through AR's materialization pipeline. The
adapter stub remains installed as a backstop: any query that escapes the
framework-level mocks lands there and fails visibly rather than silently
hitting SQLite.
