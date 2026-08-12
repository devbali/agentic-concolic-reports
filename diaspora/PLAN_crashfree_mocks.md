# PLAN — Crash-Free Concolic Execution via Mocking / Symbolic Targets

Status: 2026-08-11 (Bali directive: crash-free concolic via mocking; strict runtime kept;
iteration stays unimplemented; no DB-schema / no runtime `src/` edits in this pass).

## 1. Mechanism: target functions (one concept)

The harness records/concretizes intercepted calls through a single mechanism:

- **`declare_target(klass, method, returns: ...)`** (`src/ruby_runtime/call_interceptor.rb`)
  — the only mechanism the harness uses (`concolic_targets.rb`, 35 declarations).
  Two forms:
  1. **Body-execute** (no `returns:`): the real method body runs, and its return
     value is turned symbolic (`to_symbolic`). Used when the real body is worth
     executing for coverable path conditions.
  2. **Body-skip / mock** (`returns: ->(receiver, args, name) { ... }`): the body is
     skipped; the lambda supplies the result directly. The lambda can return a
     symbolic value (`symint`, `symstr`, `symbool`, `symlist`, `symbolic_instance`)
     or a concrete value. Rules of the interceptor:
     - `Symbol` and `nil` pass through unchanged.
     - `Integer`/`Float` → re-wrapped as `SymbolicInt`; `String` → `SymbolicString`;
       `Array` → `SymbolicList`; `Hash` → `SymbolicDict`.
     - To return a *concrete* passthrough, return `nil` or a `Symbol` (these are the
       two interrupts the interceptor leaves alone).

- **`symbolic_func!(target, method)`** (`src/ruby_runtime/symbolic_func.rb`) — a
  separate, older helper that executes the body and auto-records a
  `SymbolicCallRecord`. It is **dead code today**: never called from the harness and
  never referenced by `call_interceptor.rb`. The plan treats it as out of scope
  (legacy); all work uses `declare_target`.

## 2. Goal

Every batch entrypoint reaches either `error=none`, a recorded path-condition marker,
or an explicitly documented **intentional control-flow exception** (a seeded not-found
or permission branch — genuine coverage, distinct from a real crash). No `NotImplementedError`
from an avoidable symbolic op; no crash-before-PC.

## 3. Ground truth

Full dump scan of `results/*/*/dump_*.json`: **217 dumps, 171 error, 46 clean**,
across 13 error families. Per-family plan below. (Re-scan after each batch re-run —
the tally shifts as generic fixes land.)

## 4. Already-landed generic framework fixes (verified fire)

These are in `concolic_targets.rb`, section Y, plus edits in `symbolic_instance`:

| Fix | Crush family | Verified on `users_sessions` |
|---|---|---|
| `@association_cache={}` init in `symbolic_instance` | many `nil#[]` on AR association readers | — |
| `ActionController::Metal#status=` → nil | `status=` on nil `@_response` (Module::DelegationError) | — |
| `ActionController::ImplicitRender#default_render` → `:render_reached` | UnknownFormat (implicit render) | `users_auth_token`, privacy sttings, … → error=none |
| `ActionController::Redirecting#redirect_to` → `:redirect_reached` | redirect terminal | — |
| `ActionDispatch::Routing::UrlFor#url_for` → `"/concolic_url"` | url_for (partial) | — |
| `DeviseController#assert_is_devise_resource!` → true + eager-load Devise engine controllers | Devise ActionNotFound | sessions/registrations pass the assert step |
| `Sidekiq::Client#push`/`#push_bulk` → nil (section H, Layer 3) | Redis::CannotConnectError | `users_export_photos` → error=none |
| **Section W (round-2 chokepoints, crashfree-mocking session):** `ActiveRecord::Associations::SingularAssociation#writer` → returns record unchanged (kills ~8 `SymbolicInt#to_i` from `comment.author = person` → `replace_keys` → `cast_value`); `ActionController::Metal#head` → `:head_reached` (kills `head :not_found` → `status=` on nil `@_response`) | to_i via assoc writers; head/status= | verify via photos/posts re-run |

## 5. Families still needing per-site mocks — action items

For each crash, the working target must be an **app/service/controller method**,
declared via `declare_target` in `concolic_targets.rb` or a runner-local prepend
(then re-run the batch to confirm the flip).

### 5.1 `SymbolicInt#to_i` through `ActiveModel::Type::Integer#cast_value` (~16)
Sites: `posts_show`, `status_messages_create`, `reshares_create`, `photos_create`,
`poll_participations_create`, `participations_create`, `messages_create`,
`comments_create`, `likes_create`, `notifications_index`, `report_update`,
`aspect_memberships_create`.
Traceback: `active_model/type/integer.rb:47 #cast_value → value.to_i` when a symbolic
int is assigned into an AR attribute.
**Cannot** mock `cast_value` to a concrete Integer (the interceptor re-symbolizes
Integers → same crash). **Plan:** mock the **app-level writer** (the service/controller
create/update that performs the AR write) to return a symbolic record/CUD outcome —
mirror the existing `Persistence#create`/`#update` mocks in section F. So `cast_value`
is never reached with a symbolic int.

### 5.2 `SymbolicString#to_s` display paths (~6)
Sites: `Person#name_from_attrs` (`people_show`), `PhotosController#destroy` /
`AspectsController#destroy` (gsub/flash), `Photo#url` (`photos_mkprof`, `+`).
**Plan:** declare `Person#name_from_attrs` → symstr built from name components;
`Photo#url` → symstr; mock the destroy flash-message construction / gsub site.

### 5.3 Iteration walls — mock-around (never implement each/map) (~11)
Sites: `PeopleController#hashes_for_people` (each), `people#stream` (each),
`LikesController#index` (each), `ConversationsController#contacts_data` + `#create`
(pluck), `AdminsController#weekly_user_stats` (`Batches#find_each`),
`users_edit`/`users_update`/`set_email_preferences` (each), `users_getting_started` /
`users_public` (`SymbolicList#first`), `blocks_create` (singular_association
`find_target`→first).
**Plan:** mock the SQL-free transform/iteration methods to return
`symlist(count, representative:)` or a concrete benign value, following existing
patterns: `Stream::Aspect#aspect_ids→[1]`, `Stream::Base#post_ids→[1]`,
`Stream::FollowedTag#tag_ids→nil`. Never touch `SymbolicList#each/map`.

### 5.4 Association nil walls (current_user.person/profile, user.blocks, …)
Sites: `users_getting_started_completed` (`write_from_user`), `users_download_profile`
(`url` for `""`), `admin_unlock`/`admin_lock` (`write_from_user`), `aspects_toggle`
(`write_from_user`/`chat_enabled=`), `posts_destroy`/`PostService` (`nil#[]`),
`photos_index` (`User::Querying#photos_from`), `user.rb:370 retract`,
`reshares_index` (`ReshareService`), `status_messages_new` (`nil#[]`),
`participations_destroy` (`reverse_merge!`), `posts_oembed`/`mentionable`
(`to_hash`/`content_type`).
**Plan:** the `@association_cache={}` init fixes the AR-machinery path; for the
remaining, declare the **association reader** (e.g. `User#profile`, `User#person`,
`Post#status_message`) on a runner prepend to return a `symbolic_instance`, or mock
the consuming method. Follow the existing Person-prepend / symbolic-user pattern.

### 5.5 Warden / Devise deeper walls
Sites: `users_destroy` (`logout` for StubWarden), `registrations_*`
(`no_input_strategies`/`validatable?` for nil), `sessions_*`
(`no_input_strategies`/`to` for nil).
**Plan:** extend the runner's `StubWarden` with no-op `logout`/`clear_strategies_cache!`;
stub the warden nil in Devise sessions/registrations (`request.env['warden']` /
authenticate/no_input_strategies) to return concrete values.

### 5.6 Misc singleton app mocks
- `InvitationCode#add_invites!` (`SymbolicInt#+`) → return a symbolic count.
- `StatusMessage#tag_stream` / `#user_tag_stream` (`TypeError can't quote`) → return a
  chainable relation / symlist-with-rep so the consumer can `.for_a_stream`.
- `User#confirm_email` (`NameError confirm_email_token`) → return symbool.

### 5.7 Runner config fixes
- `invitations_create` `ParameterMissing: email_inviter` → supply the required param
  in the runner.
- `community_spotlight` stale `roles`-table `StatementInvalid` → re-run (roles table
  now exists, Layer 2); no schema work.

## 6. Intentional control-flow exceptions — documented, NOT mocked away

These are the **seeded not-found / permission branches firing correctly** (finder mock
`raise_on_missing` or app `find!`/`authorize!`). They are genuine coverage, distinct
from crashes:
- `ActiveRecord::RecordNotFound` (~13), `Diaspora::NotMine` (3), `Diaspora::NonPublic`
  (1).
**Plan:** leave them raising; **document** in the summary as "intentional coverage
branch (not-found/permission)" so the final tally distinguishes avoidable crashes from
expected control flow. Consider having runners treat these as covered markers.

## 7. Verification workflow (per change)

1. Edit `concolic_targets.rb` / runner prepend.
2. `jruby -c concolic_targets.rb` (syntax).
3. Re-run the affected batch: `~/project/scripts/diaspora-concolic results/<batch>/run_concolic.rb`.
4. Re-scan `results/<batch>/<ep>/dump_*.json` to confirm the crash flipped → `error=none`
   or lesser honest progress.
5. Update the per-batch `REPORT.md` where the pattern exists (no fabricated PCs).

## 8. Final deliverable

Re-run **all 13 batches**, re-scan **all** dumps, produce:
(a) per-batch before/after crash counts; (b) each mock added (target + reason);
(c) intentional-control-flow exceptions left raising (counts); (d) any crash not
mockable and why; (e) total clean / crash tally across all batches.

## 9. Hard constraints

- `src/` runtimes (ruby + py) **read-only** — no edits, ever.
- **No** implementing `SymbolicList#each`/`#map`/`pluck`/`find_each`.
- **No** DB-schema changes.
- **No** touching section H (Sidekiq/Redis) — already done.
- Only add/refine `declare_target` mocks + runner prepends + runner params.

## 10. App-source edits: function splits ONLY (Bali 2026-08-11)

The diaspora app source (`~/project/ruby_examples/dse-apps/apps/diaspora`) {"is" **not** open for general edits. The ONE sanctioned kind of app edit is a
**function split**: extracting a SQL-free sub-method from a larger method so that
the extracted method (the smallest possible surface) can be mocked via a single
`declare_target`, and the surrounding logic still runs for real.

Rules for a sanctioned split:
- Purpose: to **minimize the mock surface** — wrap/remove ONLY the tiny piece that
  holds the crashing symbolic op (a `.map`/`.each` transform, a `to_s` display
  build, a `to_i` AR write), never the surrounding SQL-bearing logic (SQL must stay
  real per D7).
- The extracted sub-method is SQL-free; the producer/consumer with SQL is NOT
  mocked (they run for real).
- Mirror nothing here — this is app-side, not runtime.
- Preferred order: try a pure `declare_target` on an existing method first; only
  split the app method when no clean existing target exists.

Beyond app splits, **`concolic_targets.rb` is the major/primary change location**;
runner-local prepends/params are secondary (batch-specific), not the default.
