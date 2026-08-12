# DESIGN — Class-level finder mocks (`find` / `find_by` / `find_by!`)
## Run-list edition: which entrypoints to re-run with this fix

**Status:** design/implementation spec — no code changed yet.
**Layer:** [mock] only (`reports/diaspora/concolic_targets.rb` + batch runners).
No `src/`, app source, or DB edits.
**Basis:** measured from the 216 dumps (2026-08-08). Companion docs:
`ACTION_PLAN_fix_crashes.md` (§3.1), `IMPLEMENTATION_find_class_mocks.md`.

---

## 1. The change (recap)

Add class-level targets for the three `ActiveRecord::Core::ClassMethods`
overrides that currently bypass our relation mocks and crash on the
`find_by_sql → SymbolicList#first` path:

```ruby
core = ActiveRecord::Core::ClassMethods
interceptor.declare_target(core, :find,     returns: finder_mock(raise_on_missing: true))
interceptor.declare_target(core, :find_by,  returns: finder_mock(raise_on_missing: false))
interceptor.declare_target(core, :find_by!, returns: finder_mock(raise_on_missing: true))
```

Why only these three: `Core::ClassMethods` overrides exactly `find`, `find_by`,
`find_by!` as real cached-statement methods. Every other class-level finder is
delegated to `:all` by `Querying`, so it already reaches our relation mocks.

---

## 2. Affected entrypoints (measured) — re-run these

### 2a. Fully vacuous today → expect to become reachable (13)

For each: today all its dumps have **0 path conditions** and crash with
`NotImplementedError: SymbolicList#first`, traceable to
`ActiveRecord::Querying.find_by_sql` firing immediately before the crash.

| Batch / Entrypoint | Root `find` call site (app code) | What the fix should expose |
|---|---|---|
| comments / `comments_destroy` | `comment_service.rb:14` `Comment.find(comment_id)` | found→delete; not-found→RecordNotFound. Symbolic Comment instance. |
| contacts_aspects_blocks / `aspect_memberships_create` | `aspect_memberships_controller.rb:42` `Person.find(params[:person_id])` | found→attach; not-found→RecordNotFound. |
| contacts_aspects_blocks / `blocks_create` | (block target via person/association find) | symbolic instance; branch on presence. |
| conversations / `messages_create` | `messages_controller.rb:14` `Conversation.find(params[:conversation_id])` | found→post message; not-found→RecordNotFound. |
| likes / `likes_destroy` | `like_service.rb:14` `Like.find(like_id)` | found→delete; not-found→RecordNotFound. |
| photos / `photos_index` | (photo/person finder chain) | symbolic Photo/Person instance. |
| photos / `poll_participations_create` | `poll_participations_controller.rb:7` `PollAnswer.find(params[:poll_answer_id])` | found→record vote; not-found→RecordNotFound. |
| search_links_reports_profiles / `profiles_show` | (profile/person find) | symbolic Profile instance. |
| services_admin / `admin_add_invites` | `admin/users_controller.rb:8/14/20` `User.find(params[:id])` | symbolic target user. |
| services_admin / `admin_close_account` | `admin/users_controller.rb` `User.find` | symbolic user; close-account branches. |
| services_admin / `admin_lock_account` | `admin/users_controller.rb` `User.find` | symbolic user; lock branches. |
| services_admin / `admin_unlock_account` | `admin/users_controller.rb` `User.find` | symbolic user; unlock branches. |
| users_sessions / `users_public` | (public-profile user find) | symbolic user/public view. |

**Expected result:** each of these 13 should now record ≥1 genuine path
condition (the found/not-found branch) and no longer crash on `#first`.

### 2b. Already has PCs but also crashed on class-find → expect improvement (1)

| Batch / Entrypoint | Note |
|---|---|
| people / `people_show` | already recorded some PCs; the class-find crash cut it short. Re-run → should record more branches (found/not-found on the person find) before any render-stage issue. |

So **14 entrypoints** are directly affected, **13 of them fully vacuous today**.
That is ~18% of the 73-entrypoint vacuous gap.

---

## 3. What this fix does NOT touch (explicitly out of scope here)

These look adjacent but are **separate root causes** — do not expect them to
change from this fix:

- **users_sessions devise/warden nil-derefs** (`users_edit`, `users_update`,
  `users_getting_started`, `registrations_new`, `users_destroy`, …): crash
  *before any finder fires* (`last_call=None`), in Warden/devise plumbing.
  → handled by the devise/Warden harness work (§3.10 of the main plan), not here.
- **`SymbolicList#each` view iteration** (`people_index`, `tags_index`,
  `streams/public`, `streams/*`): crash inside view templates iterating a
  collection. → handled by the render-boundary decision (§3.2), not here.
- **`SymbolicInt#to_i`** (`notifications_index`, `photos_create`,
  `status_messages_create`): separate coercion issue (§3.5).
- **`SymbolicString#empty?`** (`users_auth_token`, `streams`): runtime add (§3.3).
- **`Calculations#pluck`** (`conversations_create`, `conversations_index`) and
  **`Batches#find_each`** (`admin_stats`): separate mock gaps (§3.9).

---

## 4. Re-run procedure (per affected entrypoint)

For each entrypoint in §2a/§2b:

1. **Reinstall targets** (the 3 new `Core::ClassMethods` lines are added in
   `concolic_targets.rb#install!`, so every runner picks them up automatically).
2. **Run defaults** → assert: no `SymbolicList#first` error; a `symbolic_call`
   targets `ActiveRecord::Core::ClassMethods.find` (check the `target` field of
   the `symbolic_call` event); ≥1 `path_condition` recorded.
3. **Seed loop** (CoverageChecker): feed suggested `concrete_values` — note var
   names now carry the new prefix
   `SYM_RESULT_ActiveRecord__Core__ClassMethods_find_<n>[_not_found]` — re-run
   until complete or no new suggestions.
4. **Close the not-found branch:** seed `..._Core__ClassMethods_find_1_not_found
   => true` (find/find_by!) to drive RecordNotFound, or false (find_by) for the
   nil branch; confirm both sides of the find PC are covered.
5. **Regression guard:** re-run the `posts` batch + `scripts/test_framework_targets.rb`
   to confirm relation-form `find` still works (the change must not alter
   `FinderMethods` behavior, and both forms must coexist).

---

## 5. Acceptance criteria

- The **13 vacuous** entrypoints in §2a each produce a dump with **≥1 genuine
  path condition** and no `SymbolicList#first` error.
- `people_people_show` records more PCs than before.
- **No** previously-passing entrypoint regresses (re-verify all touched batches
  with `Run.from_dict` + `CoverageChecker`).
- The "genuinely covered" count rises by **≥13** (from 40 toward 53+), with
  "vacuous" dropping correspondingly.

---

## 6. Effort / risk

- **Effort:** tiny — 3 `declare_target` lines + per-runner seed-name touch-ups.
- **Risk:** low. Reuses proven `finder_mock`; the only behavioral surface is the
  new target names / seed-override prefix. The one open item is the multi-id
  `find` overload (route to a `SymbolicList` or punt — see
  `IMPLEMENTATION_find_class_mocks.md` §2.1).
- **Verification cost:** 14 entrypoints re-run + 1 regression check — well
  within one runner session.

---

## 7. Decisions

1. **RESOLVED — Multi-id `find`: punt.** Verified against the current dumps:
   **0** of the actual errors use the multi-id/splat/array form. All 14 affected
   entrypoints crash on single-id lookups (`WHERE "<pk>" = ? LIMIT 1`), and
   there is **no `IN (...)` query** anywhere in the 216 dumps. So we implement
   only the single-id `Core::ClassMethods` targets (done in `concolic_targets.rb`,§A2).
   A future multi-id call would route to the collection `SymbolicList` mock —
   built only if/when a real call site needs it.

2. **OPEN — Run scope:** run just the 14 affected entrypoints first, or all
   entrypoints in their batches (for coherent `STATUS.md` numbers)?

---

*Plan-only. Awaiting go + decisions before any implementation.*
