# IMPLEMENTATION PLAN — Class-level `find` / `find_by` / `find_by!` mocks

**Scope:** *only* this one change — mock `ActiveRecord::Core::ClassMethods#find`,
`#find_by`, `#find_by!` so class-level `Model.find(...)` / `Model.find_by(...)` /
`Model.find_by!(...)` return symbolic records (or the right not-found result)
instead of crashing through the StatementCache → `SymbolicList#first` path.

**Layered:** all edits are **[mock]** layer (`concolic_targets.rb`) — no
`src/` runtime or engine changes, no app/DB changes. Free to implement.

**Companion doc:** `ACTION_PLAN_fix_crashes.md` §3.1 (the generalized rationale).

---

## 0. Why only these three

Verified against Rails 5.2.4.3 (`activerecord-5.2.4.3/lib/active_record/core.rb`):
`Core::ClassMethods` overrides **only** `find`, `find_by`, `find_by!` as real
methods. All other class-level finders are `Querying`-delegated to `:all`, so
they already reach our relation mocks. Adding targets for anything else would
be redundant (harmless, but unnecessary).

---

## 1. Where to add

File: `/home/dev/project/reports/diaspora/concolic_targets.rb`, in
`ConcolicTargets.install!(interceptor)`, in the "A. Single-record finders"
section next to the existing `FinderMethods` declarations (lines ~135-143).

New code (sketch):

```ruby
# --- A2. Class-level finders (Core::ClassMethods overrides) ----------------
# Model.find(1) / Model.find_by(...) / Model.find_by!(...) are REAL methods on
# Core::ClassMethods (cached-statement), NOT Querying delegates — so they
# bypass the FinderMethods relation mocks above and would route through
# find_by_sql -> SymbolicList#first. Declare them with the same finder_mock.
core = ActiveRecord::Core::ClassMethods
interceptor.declare_target(core, :find,     returns: finder_mock(raise_on_missing: true))
interceptor.declare_target(core, :find_by,  returns: finder_mock(raise_on_missing: false))
interceptor.declare_target(core, :find_by!, returns: finder_mock(raise_on_missing: true))
```

That reuses the **existing** `finder_mock` — no new mock logic. Semantics:
- `find` / `find_by!` → raise `ActiveRecord::RecordNotFound` on the seeded
  not-found branch (matches real behavior).
- `find_by` → return `nil` on not-found (matches real behavior).
- Found branch → `symbolic_instance(klass, name, sql)` symbolic single record.

---

## 2. Gotchas to handle

1. **Array-of-ids overload** — `Post.find([1, 2])` / `Post.find(1, 2, 3)`.
   `Core::ClassMethods#find` accepts multiple ids. The `finder_mock` models a
   *single* record, so a multi-id call should be routed to the **collection
   mock** (a length-only `SymbolicList`) rather than the single-record mock.
   Implementation options:
   - (a) Add a guard inside `finder_mock` (or a small wrapper for `find`) that
     checks `args`/`receiver` for an array/multi-id and returns a
     `SymbolicList` instead.
   - (b) Declare `find` with a dedicated lambda that dispatches on whether the
     first arg is an Array.
   Prefer **(b)** for `find` only (find_by/find_by! never take multiple ids).
   **Decide which before writing code.** Note: app mostly uses single-id
   `find(id)`; multi-id is rare — do not over-engineer.

2. **Seed-override key namespacing.** `finder_mock` keys overrides off the
   generated result name, which is built from the *target's* class name:
   `SYM_RESULT_ActiveRecord__Core__ClassMethods_find_1`. That is a **different
   prefix** from the existing `FinderMethods` names
   (`SYM_RESULT_ActiveRecord__FinderMethods_*`). Consequences:
   - The CoverageChecker's suggested `concrete_values` will reference the new
     `..._Core__ClassMethods_...` names — the runner's seed loop must use those.
   - The **same app call** now produces a differently-named var than before
     (if it used to crash, it previously produced none anyway). Not a collision
     problem, just a naming change to be aware of.
   - Also note the existing interceptor already squashes non-alnum to `_`, so
     `Core::ClassMethods` → `Core__ClassMethods`. Keep this in mind when
     reading dump var names.

3. **Relation vs class call-site ambiguity.** Both
   `current_user.aspects.find(...)` (relation) and `Post.find(...)` (class) are
   legit. The relation form keeps using `FinderMethods#find`; the class form
   now uses `Core::ClassMethods#find`. Confirm in dumps via the `target` field
   of the `symbolic_call` event (should show which owner fired).

4. **`@target_name` / call-site attribution.** `declare_target` records
   `target_name` as `#{klass.name}.#{method}` — expect
   `ActiveRecord::Core::ClassMethods.find`. Fine.

5. **`find_by!` vs `find_by` return-shape** — both handled by
   `raise_on_missing`. Double-check `finder_mock`'s not-found branch: for
   `raise_on_missing: true` it must `raise ActiveRecord::RecordNotFound`; for
   `false` it returns `nil`. This already exists — no change needed.

---

## 3. Verification plan (must pass before calling it done)

Use the app's real code paths that hit class-level `find` today, e.g. the ones
that currently crash with `SymbolicList#first`:

- `Comment.find(comment_id)` — `comment_service.rb:14` (`comments_destroy`)
- `Like.find(like_id)` — `like_service.rb:14` (`likes_destroy`)
- `User.find(id)` — `sessions_controller` / devise `current_user`
  (`admin/users_controller.rb`, `messages_controller` `Conversation.find`)

Concrete steps:

1. **Smoke test first** (before full batches): a tiny standalone runner that
   calls `Comment.find(1)` and `Comment.find_by(id: 1)` through the app, with
   targets installed. Assert:
   - `dump` has a `symbolic_call` targeting `Core::ClassMethods#find`/`find_by`.
   - no `error` key (or only an intentional `RecordNotFound` on the not-found
     run).
   - the not-found seeded run raises `RecordNotFound` (find) / returns nil
     (find_by), and both record a PC.
2. **Seed loop sanity:** run defaults → feed CoverageChecker suggestion
   (`..._Core__ClassMethods_find_1_not_found => true`) → re-run → confirm the
   not-found branch now records with the *new* var name.
3. **Batch re-runs (targeted):** re-run the affected entrypoints:
   `comments_destroy`, `likes_destroy`, `messages_create`, `users_sessions`
   (devise current_user paths), `services_admin` (admin users), and any
   `posts`-adjacent path using class-level find. Confirm `SymbolicList#first`
   crashes drop and devises nil-deref `NoMethodError`s disappear.
4. **Regression check:** re-run the existing `posts` batch and the working
   smoke test (`scripts/test_framework_targets.rb`) — the new `Core` targets
   must NOT change relation-form behavior (both forms still work).
5. **Engine re-verify:** run `Run.from_dict` + `CoverageChecker` per touched
   entrypoint; confirm genuinely-covered count rises (fewer vacuous) and no
   entrypoint regresses from `complete`.

---

## 4. Changes summary

| File | Change | Layer |
|---|---|---|
| `reports/diaspora/concolic_targets.rb` | +3 `declare_target` (Core::ClassMethods find/find_by/find_by!) reusing `finder_mock`; optional multi-id dispatch for `find` (§2.1) | [mock] |
| `results/<batch>/run_concolic.rb` | update seed-override var names to new `..._Core__ClassMethods_...` prefix where referenced (§2.2) | [mock/harness] |
| `reports/diaspora/ACTION_PLAN_fix_crashes.md` / `STATUS.md` | refresh counts after reruns (§3) | docs |

No `src/`, no app source, no DB changes.

---

## 5. Open questions for you

1. **Multi-id `find`** — worth handling (`Post.find([1,2])`), or punt since the
   app mostly uses single-id `find(id)`? (Recommend: punt unless a real call
   site needs it — default to a `SymbolicList` if it ever fires.)
2. **Confirm the exact `finder_mock` not-found contract** matches (raise vs
   nil) before I write the code — I'm reading it as raise-for-`find`/`find_by!`,
   nil-for-`find_by`. Confirm that's the intended behavior for class-level too.
3. **Scope of the verification re-runs** — want me to limit to the currently
   crashing entrypoints first, or re-run all affected batches up front?

Everything here remains plan-only until you say go.
