# ACTION PLAN & BRAINSTORM — Fix the Crashes & Unimplemented Errors

**Date:** 2026-08-08
**Scope:** Diaspora concolic experiment — close the gap between "engine says
`complete=true`" and "the entrypoint is genuinely explored."
**Constraint:** NO code changes yet. This is design/brainstorm only. Items are
tagged with the layer they touch so the source-discipline rule is respected
before any edit.

---

## 1. The problem, precisely

The engine reports **113/113 entrypoints `complete=true`**, but only **40 are
genuinely covered** (≥1 real path condition) and **73 are vacuous** (0 PCs —
the run crashed before reaching its first branchable point). Across the
**216 dumps**, **193 carry an `error` key**. So "complete" currently means
"every PC we managed to record has both taken/not-taken sides covered" — not
"the action fully executed." The crashes are the wall.

The error budget (exact, from the dumps):

| Error class | count | Root layer |
|---|---|---|
| `NotImplementedError` (unsupported symbolic op) | 69 | runtime / target-mock |
| `NoMethodError` (mostly nil deref / assoc) | 59 | harness / runtime assoc-cache |
| `ActiveRecord::RecordNotFound` / `Diaspora::NotMine/NonPublic` | 21 | intentional app branches (OK) |
| `Module::DelegationError` (`@_response` nil) | 13 | harness (unbuilt response) |
| `ActionController::UrlGenerationError` | 9 | harness (no route) |
| `Redis::CannotConnectError` | 4 | env (Redis down) |
| `ActiveRecord::StatementInvalid` (missing table) | 4 | env (DB schema) |
| `ActionView::MissingTemplate` / `Template::Error` | 7 | render plumbing |
| `AbstractController::ActionNotFound` (devise) | 4 | harness (devise/warden) |
| Other (TypeError, NameError, ParameterMissing) | 3+ | harness |

**Key insight:** the biggest clusters are (a) view/render plumbing, (b)
collection iteration (`SymbolicList#first/#each`), and (c) coercions
(`SymbolicInt#to_i`, `SymbolicString#to_s/empty?`, `SymbolicInt#hash`).
These are concentrated and fixable with a small number of targeted changes.

---

## 2. A strategic decision up front (please read / decide first)

**What should "completeness" mean?**

Two viable philosophies:

- **(A) Controller-action boundary (recommended).** The concolic loop's job is
  to explore branches in controllers, services, and models — not in view
  templates. Treat **`render` / `respond_with` as the terminal boundary**: the
  harness stubs rendering and records "action reached render." This deletes a
  whole class of crashes (`SymbolicList#each` inside views, `MissingTemplate`,
  404 template lookup, `status=` on a nil `@_response`) because view code never
  runs. It is also *sound*: view rendering is not where concolic value lives
  (AR query results were already consumed by the controller to build the view's
  assigns).

- **(B) Push fully through views.** Requires making views runnable with
  symbolic data — iterating SymbolicLists, rendering partials, all the
  plumbing. High effort, low concolic value. Only worth it if a specific
  branch genuinely lives in a helper/presenter.

**Recommendation: adopt (A).** It is the lowest-effort, highest-yield decision
and matches the "controller-action-level entrypoints" framing of the README.
Implementation is runner/harness-local (free to write). If we adopt (A), most
of the 73 vacuous entrypoints become genuinely reachable: the action executes,
its controller/service branch on symbolic query results, then hits the stubbed
render boundary and completes.

This decision also *unblocks* the hard list-iteration question (§4), because a
lot of the `SymbolicList#each` crashes are in view templates we'd no longer
run.

---

## 3. Fixes by mechanism (the meat)

Each item below is tagged:
- **[mock]** — new/changed concolic *target declaration* (concolic_targets.rb
  or runner-local). Runner layer → free to write, no sign-off.
- **[runtime]** — enhancement to `src/ruby_runtime`. Needs Bali sign-off
  (source-discipline).
- **[engine]** — enhancement to `src/concolic_engine`. Needs Bali sign-off.
- **[verify/harness]** — runner/bench harness or DB/env. Runner-local is free;
  DB/env edits need a check-in.

### 3.1 Declare the `Core::ClassMethods` class-level finder overrides — the single biggest mock win  [mock]

**Root cause (verified against Rails 5.2.4.3 source):** there are *two*
distinct `find` methods in Rails:

| Call form | Method | Owner | Currently mocked? |
|---|---|---|---|
| `current_user.aspects.find(...)`, `Post.all.find(1)` | `FinderMethods#find` (relation instance method) | `ActiveRecord::FinderMethods` | ✅ Yes (returns symbolic record) |
| `Post.find(1)`, `User.find(id)`, `Person.find(...)` | `Core::ClassMethods#find` (class method on the model) | `ActiveRecord::Core::ClassMethods` | ❌ No |

`ActiveRecord::Base` includes `Core`, and `Core::ClassMethods#find` is a **real
method** (not the `Querying` delegate). Every other class-level finder
(`take`, `first`, `last`, `exists?`, `count`, `sum`, `pluck`, `find_each`, …)
is just `Querying`-delegated to `:all`, so `Model.first` literally becomes
`Model.all.first` → `FinderMethods#first`, which **already routes through our
mock**. The `Core` overrides are the only ones that bypass the relation mocks.

I inspected `Core::ClassMethods` and it overrides exactly **three** of our
mocked operations: **`find`, `find_by`, `find_by!`**. Everything else already
funnels through the relation/calculation mocks via the `:all` delegation.

Today `Post.find(1)` runs `Core::ClassMethods#find` → `cached_find_by_statement`
→ `statement.execute(...).first`, and that `.first` on a SymbolicList raises
`NotImplementedError` (the **18** `SymbolicList#first` crashes). It also
blocks devise `current_user`, `comments_destroy`, `messages_create`,
`likes_destroy`, admin users, and many session paths (the app uses the
class-level `Model.find(...)` form in ~39 places).

**Fix (generalized):** declare all three `Core::ClassMethods` overrides with
the **existing `finder_mock`** — same behavior as the relation form, so class
and relation calls stay symmetric:

```ruby
core = ActiveRecord::Core::ClassMethods
interceptor.declare_target(core, :find,     returns: finder_mock(raise_on_missing: true))
interceptor.declare_target(core, :find_by,  returns: finder_mock(raise_on_missing: false))
interceptor.declare_target(core, :find_by!, returns: finder_mock(raise_on_missing: true))
```

- `find` / `find_by!` raise `RecordNotFound` on the not-found branch (as the
  real methods do); `find_by` returns `nil`. The existing `finder_mock` already
  models both sides and records a PC at the boundary.
- **Array-of-ids** overload (`Post.find([1,2])`) is out of single-record scope;
  route it to the collection mock (a length-only `SymbolicList`) rather than
  raising.

**Why "this generalized" is the right rule:** don't add a class-level mock for
*every* target — only for methods `Core::ClassMethods` actually overrides
(`find`, `find_by`, `find_by!`). The rest already reach our mocks through
`Querying`'s `delegate ... to: :all`. (Audit rule: *for each target, check
whether a class-level module defines a real method of that name; if yes, mock
it; if it just delegates to `:all`, it's already covered.*)

Estimated impact: closes the `first` crashes and most of the devise
`current_user` nil-deref `NoMethodError`s.

### 3.2 Adopt the render boundary + stub render  [verify/harness]  (decision A)

Declare `ActionController::Rendering#render` / `#render_to_string` and
`respond_with` as terminal targets whose return value is a sentinel, or prepend
a harness module that records "render reached" and returns without running
templates. This removes:
- `SymbolicList#each` inside view templates,
- `ActionView::MissingTemplate` / 404 template lookups,
- `ActionView::Template::Error` (underscore/JS asset gaps),
- `Module::DelegationError` (`@_response` nil) — because the harness also
  builds the controller's response/status plumbing up to the render call.

**Caveat / honesty:** if we stub render, the "action completed" signal is
"reached render," not "rendered a page." The dumps/reports must say so (they
already carry the caveat language). This is fine and arguably *more* correct
for concolic coverage of app logic.

### 3.3 SymbolicString#empty? — trivial runtime add  [runtime]

**9** crashes (`SymbolicString#empty? is not supported`). All string ops that
track a PC are already implemented (`==`, `!=`, `start_with?`, `end_with?`,
`include?`, `[]`); `empty?` is a one-liner recording `(s == "")` (or
`Length(s) == 0`) with taken = current emptiness. Mirrors the Python runtime.
Small, clearly within the intended design (string SMT is already opted into for
the other comparable ops). **Should be an easy approval.**

### 3.4 SymbolicInt#hash → stable concrete hash  [runtime]

**5** crashes (`posts_show` + Arel internals). A symbolic Int is being used as
a Hash/Set/assoc key; `hash` currently raises. `hash` is a **bucket function,
not a branchable condition** — returning `@value.hash` (the concrete value's
hash) does *not* lose path tracking: equality (`==`) still records the PC, and
hash only determines which Hash bucket is used. Returning a concrete hash is
sound because two concretely-equal symbolic values must land in the same bucket
as their concrete selves. **Recommend approving this one — it is safe and
unblocks Arel + Hash-key paths broadly.**

### 3.5 Coercion decision: `to_i`, `to_s`, `to_str`, `-@`, `+`, arithmetic  [runtime]

These were deliberately made to raise to prevent *silent concretization*. But
real Rails code legitimately calls `to_i`/`to_s` on values it then uses
concretely (building URLs, WHERE fragments, logging). Right now that is a hard
crash. Two defensible policies:

- **(i) Concrete fallback for non-branch coercions.** Let `to_i` → `@value`,
  `to_s`/`to_str` → concrete string, `-@`/`+` → concrete numeric result, on the
  grounds that these ops are *not comparisons* and therefore cannot record
  meaningful PCs anyway. The value is used concretely downstream. **Risk:** this
  is exactly the silent-concretization channel previously closed — a later
  *comparison* on a concretized value would not be tracked. So this must be
  scoped: only allow these as "terminal" coercion into native types, never into
  a re-wrapped symbolic that keeps flowing.
- **(ii) Symbolic algebra for arithmetic.** Implement `-@`, `+`, etc. to
  produce a *new* `SymbolicInt` (e.g. `SymbolicInt.new(@value + other)`) and
  record PCs on the derived value. Proper but expands the runtime and needs Z3
  expression composition (the runtime currently renders exprs as strings like
  `(x > 5)`; arithmetic would need `(x + 1 > 5)`).

**Recommendation:** poll which real call sites need this (reshares_create /
status_messages_create hit `to_i`; a few hit `to_s`). If they're all terminal —
the value is only used to look something up or build a string — policy (i)
scoped to terminal use is the pragmatic fix. If any value is later compared,
we need (ii). Decide per call-site, don't blanket-enable.

### 3.6 Association cache / association readers  [mock + runtime]

`klass.allocate` produces a symbolic instance with **no `@association_cache`**,
so association readers (`post.comments`, `user.person`) raise `NoMethodError`
(part of the 59). The runner already works around this per-model
(`user.define_singleton_method(:person)`). **Systematize it:** enhance
`concolic_targets.rb#symbolic_instance` to (a) initialize an empty
`@association_cache` so association memoization doesn't blow up, and (b) accept
a map of association-name → (symbolic finder / SymbolicList / symbolic
instance) and define readers for the associations each model actually uses.
This centralizes what post/posts, users_sessions, etc. currently hand-write.
[mock — free]. If deeper AR association machinery is needed, that's a runtime
enhancement [runtime — sign-off].

### 3.7 `len(...)` engine var-decl — the one clear engine bug  [engine]

Dumps declare collection vars named literally `len(SYM_RESULT_..._rows)`
(sort Int). The engine then executes `len(SYM_RESULT_..._rows) =
Int('len(SYM_RESULT_..._rows)')` — invalid Python (can't assign to a call) →
warning `Failed to eval var decl`. Two clean fixes:
- **(i)** In `run.py`/`solver.py`, detect the `len(NAME)` shape and emit the
  underlying var decl as `NAME = String('NAME')` plus use Z3's `Length(NAME)`
  for constraints (no `len(...)` standalone var needed).
- **(ii)** Or change the *runtime* to register the list's length under a plain
  Z3-safe name (e.g. `rows_len_1`) and render constraints as `Length(Name)`.

Currently non-blocking (entrypoints still complete per the checker) but it
produces spurious warnings and would matter the moment we track list contents
(§3.8). Worth fixing. [engine and/or runtime — sign-off].

### 3.8 Collection contents — the structural piece (only if decision (A) doesn't remove it)

`SymbolicList#first` (18) and `#each` (16) are the two biggest NotImplemented
clusters. Two paths:

- If we adopt decision (A) — render boundary — then **most `#each` in views
  vanish**. The remaining `#each`/`#first` in controllers/services are few.
- For the remaining first/each on SymbolicLists (e.g. `scoped.first` in a
  service, `Model.find` → `find_by_sql` → `first` which §3.1 already fixes):
  consider a **"sampled-content" SymbolicList** — a list whose length is
  symbolic but which carries one concrete *representative element* (itself
  symbolic) so `first`/`each`-once return that element and `each`'s block runs
  exactly once. This preserves the "how many rows" dimension while letting a
  single representative row flow through app code. This is a **design change to
  the SymbolicList contract** — explicitly the thing README §5 says is out of
  scope — so it needs your call. [runtime — sign-off; high effort]

**My take:** don't build sampled-content lists unless a real branch is
blocked. With §3.1 + decision (A), most list-content crashes disappear with far
less work.

### 3.9 Remaining higher-level target gaps  [mock]

- `Calculations#pluck` (2) — currently declared `UNSUPPORTED`. Return a
  length-only SymbolicList (or a SymbolicList of symbolic column values) like
  the other collection mocks. Low effort.
- `Batches#find_each` (1, admin_stats) — declared `UNSUPPORTED`. With decision
  (A)/render boundary or a sampled-list, admin_stats likely stops iterating; if
  not, mock find_each to yield exactly one symbolic instance (representative
  element) and return. Low effort.
- `SymbolicInt#-@` / `SymbolicString#+` — covered by the arithmetic decision
  (§3.5).

### 3.10 Harness / environment gaps  [verify/harness — flags]

These are *not* runtime bugs; the harness/app environment needs completing.
Some need your sign-off because they touch the app/env:
- **Missing tables:** `reports` (3 crashes + 2 template errors), `roles`
  (1). The concolic sqlite DB needs these tables added (they're referenced by
  models whose `columns_hash` comes back empty → nil). **This is a DB/app edit
  → ask first.**
- **Redis down** (4). Redis isn't running; export/export_photos etc. crash.
  Options: start a local redis-server, or mock the Redis client in the harness
  (free). Starting redis is probably easiest and most faithful.
- **Devise/Warden plumbing** (4 `ActionNotFound`, `StubWarden#logout`,
  `registrations validatable?` nil). The harness's StubWarden/current_user is
  too thin. Flesh out the warden/devise stubs the way real controller specs do
  (sign_in helper, request.env['warden'], reset_session, etc.). Runner-local
  [free].
- **`[]' for nil` (23) / `to_hash for nil` (9) / `write_from_user` nil (5) /
  `content_type` nil (5)** — mostly app code dereferencing a nil that the
  harness didn't populate (current_user/association/params). Many resolve
  automatically once `find` (§3.1), associations (§3.6), and devise/warden
  (§3.10) are in place. A few are genuine http-param gaps: the harness should
  supply the request params/body each action reads. Runner-local [free].
- **UrlGenerationError (9)** — harness invoking actions with no matching real
  route (e.g. `users#token`, `services#inviter`, federation receive). These are
  tests calling actions that aren't routable in this env; the harness should
  drive them directly via the controller instance (as other batches do) rather
  than route generation. [harness]

### 3.11 Make "vacuous" a first-class signal  [engine]

The checker returns `complete=true` with 0 nodes, which is honest in REPORTS.md
but not encoded in the tool. Consider adding a `genuine: bool` (or
`nodes: N` + `vacuous: bool`) to `CoverageResult`/`CoverageSummary` so the
engine itself distinguishes "fully explored" from "nothing to explore."
Optional but cheap and improves the audit story. [engine — sign-off]

---

## 4. Brainstorm: other mechanisms worth considering

1. **Render-boundary concolic semantics (decision A)** — already §3.2; restate:
   this is conceptually the *design* fix, not a hack. Concolic testing of app
   logic legitimately stops at the response boundary.

2. **Hybrid concrete identity + symbolic branch values.** Keep `id`,
   `guid`, `person_id` concrete (they only feed WHERE/to_sql), make query
   *results*, `not_found`, and boolean columns symbolic. The runner already does
   this manually (`symbolic_user`). Formalize it in `symbolic_instance` so every
   batch gets it by default. Reduces nil-deref crashes and sidesteps
   `to_sql`-on-symbolic crashes. [mock]

3. **`to_sql` interception to avoid symbolic-in-WHERE crashes.** Several
   crashes come from AR normalizing a WHERE with a symbolic value → `to_sql`
   raises. Intercepting/to_native-ing args at the query-builder boundary (in the
   finder mock, `.value` the symbolic predicates) would let real queries
   serialize. The runner notes this is exactly why identity fields are kept
   concrete. A relation-level target that snapshots `.to_sql` *before* symbolic
   normalization is worth exploring. [mock]

4. **Record-model (all-attributes) symbolic instance with column-type
   dispatch** — already partially in `symbolic_instance`. Extend to cover
   string columns with `empty?` once §3.3 exists, and boolean predicate readers
   returning concrete bool with PC recorded at the reader (already done). Keep
   as the single source for all models.

5. **JRuby truthiness interceptor (long-term, real fix).** The `src/TODO.txt`
   gap — bare `if obj` isn't hookable in Ruby. A JRuby extension that patches
   boolean coercion to record a PC would remove an entire class of unrecorded
   branches. High effort, high value, genuinely fixes a soundness hole rather
   than a crash. [runtime — far future, but the *right* way to close the
   truthiness gap if you ever want to.]

6. **Per-entrypoint "reachability harness" script.** A small verification
   pass that, for each entrypoint, asserts the action reached the render
   boundary (or recorded ≥1 PC) and flags the rest. Turns the qualitative
   "vacuous" tag into an automated check. [verify — free]

---

## 5. Suggested execution order (highest ROI first)

1. **Decide (A) render-boundary.** (You + philosophy.) — biggest lever.
2. **Add `Core::ClassMethods` class-level finder targets** (`find`, `find_by`,
   `find_by!` — §3.1). [mock, free]
3. **Stub render** (§3.2). [harness, free]
4. **Runtime trivials for approval:** `SymbolicString#empty?` (§3.3) and
   `SymbolicInt#hash` (§3.4). [runtime]
5. **Association cache + symbolic_instance systematization** (§3.6). [mock]
6. **Devise/warden + params harness** (§3.10). [harness]
7. **Coercion policy for to_i/to_s/-@/+** (§3.5) — decide per call-site. [runtime]
8. **`len()` engine decl + vacuous flag** (§3.7, §3.11). [engine]
9. **pluck / find_each targets** (§3.9). [mock]
10. **Env: reports/roles tables, Redis** (§3.10) — needs your sign-off.
11. **Sampled-content SymbolicList only if a real branch is still blocked**
    (§3.8). [runtime — high effort, park it]

---

## 6. What I need from you (decision gates)

- **Gate 0 (philosophy):** adopt controller-action render boundary (A)?
- **Gate 1 (runtime sign-off):** approve `empty?` + `hash` changes (§3.3/3.4)?
- **Gate 2 (coercion):** which policy for `to_i`/`to_s`/`-@`/`+` (§3.5)?
- **Gate 3 (engine sign-off):** approve `len()` var-decl fix + vacuous flag
  (§3.7/3.11)?
- **Gate 4 (env):** OK to add `reports`/`roles` tables to the concolic DB and
  start Redis (§3.10)?
- **Gate 5 (scope):** park `Sampled-content SymbolicList` unless a concrete
  branch is blocked (§3.8)?

Everything tagged **[mock]** or **[harness]** I can implement immediately on
your go-ahead without touching `src/` or the app. Everything tagged
**[runtime]** / **[engine]** needs the matching gate above.

---

*This is a plan — no files under `src/`, the app, or the DB were changed.*

---

## 7. DECISION UPDATE — 2026-08-09: Gate 0 answered → **(B) THROUGH VIEWS**

**Bali overrides the recommended (A).** The concolic loop must push fully through
view templates, not stop at a stubbed render boundary. Views are legitimate
concolic territory because **they branch on and consume query results** — e.g.
`@comments.any?`, `photo.owner?`, iterating a SymbolicList of rows, partial
guards — and some call SQL/query functions themselves, which must be targeted
(mocked) exactly like controller/service/model query calls.

### Consequences (this changes the plan)

1. **Render stubbing is NOT the terminal boundary anymore.** We must *undo* the
   2026-08-08 render-boundary behavior (render/render_to_string/render_to_body
   treated as terminal) and instead let rendering actually execute templates
   with symbolic data.
2. **`Sampled-content SymbolicList` (§3.8 / Gate 5) is now REQUIRED, not parked.**
   Views iterate SymbolicLists (`#each`, `#first`, `#any?`, `#map`) — the biggest
   NotImplemented cluster. With (B) these `#each`/`#first` crashes are back
   on the critical path, so the sampled/representative-element design is
   mandatory to get through views. (README §5's out-of-scope note is hereby
   explicitly waived.)
3. **Template machinery must run**: partials, helpers/presenters, `MissingTemplate`
   /404 lookups, `Template::Error`, and full `@_response`/status plumbing — all
   previously side-stepped by (A).
4. **SQL/query-from-view targeting (new, from Bali):** audit every view template
   for query/AR calls (`.where(...)`, `.find`, `.any?`, `.exists?`, associations)
   and extend `concolic_targets.rb` so those route through the same mocks as
   controller-level calls. Views become first-class branch sites.

### Revised execution order (supersedes §5 where they conflict)

1. **Runtime: `empty?` + `hash` trivials (§3.3/3.4)** — still the cheapest win,
   now even more important (helpers/views call these constantly). [runtime]
2. **Sampled-content SymbolicList (§3.8)** — NOW REQUIRED for (B); the design
   change to the SymbolicList contract (representative element + symbolic
   length) moves from Gate 5-parked to an explicit runtime change. [runtime]
3. **Un-stub render / enable template execution** — reverse decision (A); build
   `@_response`/status plumbing; make partials+helpers runnable. [harness]
4. **View query targeting** — audit templates, add targets for SQL/query calls
   made from views. [mock]
5. Association cache + symbolic_instance systematization (§3.6). [mock]
6. Devise/warden + params harness (§3.10). [harness]
7. Coercion policy for to_i/to_s/-@/+ (§3.5) — decide per call-site, still open. [runtime]
8. len() engine decl + vacuous flag (§3.7/3.11). [engine]
9. pluck/find_each targets (§3.9). [mock]
10. Env: reports/roles tables, Redis (§3.10) — sign-off.

### Decision gates (supersedes §6)

- **Gate 0 = B (through views)** — DECIDED ✓ by Bali 2026-08-09.
- **Gate 1 (runtime):** approve `empty?` + `hash` (§3.3/3.4).
  → **DONE 2026-08-09**: `SymbolicString#empty?` (records `(s == '')`);
  `SymbolicInt#hash` / `SymbolicString#hash` concretized to `@value.hash`
  (Ruby runtime + Python mirror). Verified: empty? records both taken
  branches; hash returns concrete Integer, no crash. `eql?` still raises
  (untrusted comparisons stay blocked).
  ⚠️ RISK ACCEPTED by Bali with TODO: concretized hash means a BRANCH on
  set/hash MEMBERSHIP (`set.include?(sym)`) is decided only by the concrete
  hash and will NOT be recorded as a PC. Current hash sites (Arel to_sql
  WHERE Set/Array minus) are pure bookkeeping, no branch — audited. TODO
  comments placed at both Ruby `hash` methods + Python `__hash__`.
  Root-cause of hashes: post_service.rb:71 mark_comment_reshare_like_...
  → to_sql → WhereClause Set-minus de-dupes on BindParam#hash.
- **Gate 1b (runtime, NEW, required by B):** approve Sampled-content
  SymbolicList design — representative (symbolic) element + symbolic length,
  `first`/`[0]`/`last`/`include?` return the rep; `each`/`map`/`reject`/`select`
  stay UNIMPLEMENTED on the list and are handled by caller-wrapping. README §5
  scope waiver noted.
  **MECHANISM (final, Bali 2026-08-09):** mock the SMALLEST enclosure that
  contains the `each` (NOT `each` itself — per-element logic is real). The
  mocked method's real body must do NO SQL — only lay out / present
  already-loaded data. No per-model mocks: targets are the shared AR framework
  modules (already declared), so per-`each` work is per CALL-SITE (choose which
  already-mocked association/query producer is the SQL-free enclosure and wire
  it to carry a symbolic representative). Full detail:
  `reports/diaspora/DESIGN_sampled_content_list.md` (D5/D6/D7).
- **Gate 2 (coercion):** policy for to_i/to_s/-@/+ (§3.5) — still open.
- **Gate 3 (engine):** len() var-decl + vacuous flag (§3.7/3.11).
- **Gate 4 (env):** reports/roles tables + Redis (§3.10).
- **Gate 5:** superseded by Gate 1b (Sampled SymbolicList no longer parked).
