# TARGET FUNCTIONS — diaspora concolic batches (results3)

A **target function** is a method the interceptor `declare_target`s: its
real body is SKIPPED, the call is recorded as a `symbolic_call` event
(target name, argument shapes, a NOTE carrying the statement it stands
for with `$(VAR)` binds), and its return becomes the next symbolic
variable. Everything the engine "knows" about the app's data access is
the set of these calls. Source: `comments_index/concolic_targets.rb`
(shared base, ported per batch) + each batch's `targets.rb` overrides.

## 1. The ActiveRecord query boundary (the policy-bearing targets)

| family | owner | methods | mock result |
|---|---|---|---|
| finders, raising | `ActiveRecord::FinderMethods` | `find take! first! last! find_by!` | symbolic row (`<name>_not_found` decision raises) |
| finders, nil-able | `ActiveRecord::FinderMethods` | `find_by take first last` | symbolic row or nil (`<name>_not_found` decision) |
| class-level finders | `ActiveRecord::Core::ClassMethods` | `find find_by find_by!` | same as above |
| existence | `FinderMethods#exists?`, `Relation#any? none? one? many? empty?` | — | symbolic bool `<name>_<pred>` with the relation's SQL note |
| materialization | `ActiveRecord::Relation` | `to_a to_ary records`, `size` | symbolic row list (`SYM_LEN_*` length, per-row symbolic columns); note = relation SQL incl. `.includes` preloads and through-tables (violation 3) |
| calculations | `ActiveRecord::Calculations` | `count sum` | symbolic int with COUNT/SUM note |
| calculations, projected | `ActiveRecord::Calculations` | `pluck` (batch override: real projection + order columns, violation 4); `ids average minimum maximum calculate` UNSUPPORTED (raise) | list |
| batches | `ActiveRecord::Batches` | `find_each find_in_batches in_batches` | UNSUPPORTED (raise = wall to model if hit) |
| writes | `ActiveRecord::Relation` | `update_all delete_all destroy_all` | recorded, no rows |
| writes | `ActiveRecord::Base` | `save save! update update! update_attribute touch destroy destroy!` | recorded |
| raw SQL | `ActiveRecord::Querying` | `find_by_sql count_by_sql` | recorded with the literal SQL |

Batch-local, call-site-stable ALIASES of these (so ordinals don't collide
across scenarios) are also targets, e.g. `ci_vis_first / ci_author_first /
ci_public_first` (comments: the three `.first` finders inside
`EvilQuery::VisibleShareableById#post!`), `devise_user_first` (the users
lookup inside `OrmAdapter::ActiveRecord#get`), `convidx_conv_lookup`,
`mention_lookup_msg_first / _retry` (people-by-handle lookups in the
mention parser). Every alias is byte-faithful: the real method body is
copied onto a new name so only the NAME differs.

## 2. App-level targets (data access that is not a plain AR call)

| target | why it is a target |
|---|---|
| `User#blocks` | blocked-people set (a query the stream filters by) |
| `Stream::Aspect#aspect_ids`, `Stream::FollowedTag#tag_ids`, `Stream::Base#post_ids`, `Stream::Base#attach_user_likes`, `Stream::Multi#publisher_prefill`, `StreamsController#decorated_stream_posts` | stream building — each is a query family with its own SQL |
| `PostService#mark_user_notifications`, `User#add_to_streams`, `StatusMessageCreationService#add_to_streams`, `User#retract`, `Diaspora::Taggable#build_tags`, `StatusMessage.tag_name_max_length` | write/side-effect paths on create/destroy endpoints |
| `PostPresenter#build_mentioned_people_json`, `Diaspora::MessageRenderer#title`, `Photo#url` | presenter-level reads that would otherwise re-enter AR from inside rendering |
| `Sidekiq::Client.push / push_bulk` | job enqueue boundary (no DB, but a side effect the policy must not depend on) |

Per-batch additions live in each batch's `targets.rb` (e.g. conversations:
`Relation#to_ary` over the loaded `messages` association, `Calculations#count`
with the eager-load COUNT(*) shape; comments: finders with preloads).

## 3. Framework walls declared as targets (terminal markers, NOT data access)

`ActionController::Metal#status= / head`, `ActionController::Head#head`,
`ActionController::ImplicitRender#default_render`,
`ActionController::Redirecting#redirect_to`,
`ActionController::Instrumentation#redirect_to`,
`ActionDispatch::Routing::UrlFor#url_for`,
`ActionController::Rendering#render / render_to_string / _set_rendered_content_type`
(only where a batch cannot run the real template pipeline — comments and
conversations run render for REAL), `DeviseController#assert_is_devise_resource! /
devise_mapping`, `DiasporaFederation::Entity#validate`,
`DiasporaFederation::Discovery::Discovery.fetch_and_save` (network).
Their notes are junk by design (the lint lists them as documented walls);
they carry no policy.

**Withdrawn from the wall list 2026-08-30 (conversations adversary R4, C-10 /
C-12 — BOUNDARY CHANGES under Rule T):**

- `Gon::ControllerHelpers#gon` is NOT a wall. The shared stub
  (`concolic_targets.rb:978`, "pure JS-var accumulation, no SQL") swallows the
  push that `include_gon` serialises, so a real layout render issued NONE of
  the presenter's seven reads. It is declared with the gem's own four-line
  body (register the per-request store, return `Gon`) — still no SQL of its
  own, but it must let the layout's reads through.
- The write family `save save! update update! update_attribute touch destroy
  destroy!` (`concolic_targets.rb:503`) may NOT be a body-skipping `_ok`
  declaration. Rails' `update_attribute` is `public_send("#{name}=", v);
  save(validate: false)` and the save must DERIVE its statement from dirtiness
  (T-v / C-5): an unchanged record issues nothing, a changed one issues the
  `UPDATE`. With the skip, the authentication boundary's only write —
  `devise_lastseenable`'s `last_seen` stamp on every signed-in request — was
  an event with no statement on every batch.
- The principal is resolved by a REAL `Warden::Proxy` (`Devise.warden_config`),
  never a stub `Object`: `after_set_user` hooks (`lastseenable`, `lockable`,
  `rememberable`) are part of the boundary. Three one-variable decisions on
  the fixture principal drive them: `_last_seen_stale`, `_locked`, and (R5,
  C-14) session-vs-cookie: a remember-me cookie login is an AUTHENTICATION
  event, not a fetch — the `except: :fetch` hooks run and `trackable` writes
  `sign_in_count / current_sign_in_at / last_sign_in_at / *_ip` before the
  action. The rig's Warden must be the app's own manager from the built
  middleware stack (INSTR-11: `Warden::Manager.new(nil, config.dup)` drops the
  `:user` scope strategies). A `_remembered` variable nothing reads is a
  phantom decision, not a decision.

Known `src/` gap (not fixed — source discipline): the interceptor's
`splat_args` capture keeps `update_attribute`'s NAME and drops its VALUE
(`call_interceptor.rb`; keys `[splat_args, kwargs, block]`). The conversations
mock marks the record dirty explicitly when the value is lost and says so in
its note. The shared boundary assembly (pending) inherits that workaround
until the capture is fixed.

## 4. What is NOT a target (shim mocks)

Pure leaves whose real body reaches ZERO targets — `Person.name_from_attrs`,
`Profile#image_url`, `image_path`, `User#authenticatable_salt`, `to_param`,
`Message#plain_text_without_markdown`, etc. They are verified by the mock
checker (T1 zero-target + 100% line coverage) and are listed per batch in
`_shims_extracted.json` / `shim_tests.rb`. See CHECKS.md terminology.

## Per-endpoint hit lists
The targets a corpus actually exercised are in each batch's
`coverage_summary.json` (`symbolic_call` events → `target`), and the
concrete probe's `targets_from_corpus` derives its interception list from
exactly that set — so the concrete checker intercepts the same functions
the engine did, plus anything the adversary's real run reaches at depth 0.

**Planned factoring (Bali, 2026-08-31):** the endpoint proper should begin
AFTER authentication, with the logged-in principal symbolic; the login stages'
own queries (principal SELECT, trackable/lastseenable/rememberable writes)
belong to a SHARED auth-boundary policy computed once app-wide and unioned
into every endpoint's policy. That removes the boundary × content
cross-product from every batch (conversations paid ~345 demanded
combinations for it). Adopt at the shared-boundary assembly: conversations'
explored boundary corpus becomes the shared artifact; later endpoints import
it and model only a symbolic principal plus any endpoint-specific
boundary interaction. ADOPTED 2026-08-31 (user decision): retrofitted onto conversations mid-cycle — the auth-inclusive corpus work becomes `results3/_auth_boundary/BOUNDARY_POLICY.md`; every endpoint's entrypoint is the post-auth action with a symbolic principal.

## REQUIRED BOUNDARY WORK — DONE 2026-09-03, applied + verified

> **APPLIED 2026-09-03** from `docs/_BOUNDARY_FIX_DRAFT_20260903.md` (the four
> fixes below), as one git commit on the shared `concolic_targets.rb`. The
> before/after code and the post-apply verification sequence are in the draft.
> Verification after apply (JRuby probe `_verify_boundary_fixes.rb`, 14/14
> checks PASS, plus corpus censuses):
> - `sum` → `SELECT SUM("tbl"."col")`, `count`/`size` → `SELECT COUNT(*)`
>   (probe asserted all three note shapes against real relations).
> - gon runs the real gon-6.3.2 body: returns the Gon module, populates
>   `RequestStore[:gon]`, interceptor still records the call.
> - find_target memo: two reads of one association in a run → ONE event, same
>   symbolic instance; a second run mints fresh (run-label keyed, cleared per
>   run with the interceptor's run state).
> - conversations corpus: 18 306/18 306 `sum` events carry `SELECT SUM(…)`
>   (its batch-local override already had it; the shared boundary now matches).
> - comments corpus: 0 `sum`, 0 `size`, 0 find_target repetitions.

Two defects in the shared boundary (`concolic_targets.rb`), found by
notifications_index C7 (2026-09-01) while un-pinning its layout. Both were
REPORTED, not patched (Rule T3), and worked around batch-locally. **Neither has
an instance on a closed endpoint — verified, not assumed** — so this was
planned work, not a Rule T2 reopening. Both are now patched in the shared
boundary (above); the text below records what the old shapes were and the
closed-endpoint measurements that kept this non-urgent.

**1. `Calculations#sum` emits a ROW projection.** The shared `%i[count sum]`
mock renders the row projection for both members; `count` survives only because
batches override it locally. Un-pinned, notifications' `sum` note came out
`SELECT "conversation_visibilities".* FROM …` against a real
`SELECT SUM("conversation_visibilities"."unread") FROM …`. Any batch that calls
`sum` without a local override emits a note that claims FULL-ROW access where
the app reads an aggregate — an over-claim in the policy, and exactly the
"a row-read note over an aggregate misstates it" class in CONCRETE_CHECKER's
evidence-fidelity duty. Fix: render the aggregate projection in the shared mock,
in the AGG-COLLAPSE style `count` already uses locally.
*Verified clear on closed endpoints:* conversations' 18 306 `sum` events all
carry the correct `SELECT SUM(…)` shape and its policy view projects the
aggregate; comments never calls `sum`.

**2. The gon stub's justification is stale.** X6b declares
`Gon::ControllerHelpers#gon` with a NO-OP `push`, justified in its own comment
by "gon is out of scope there by the standing `layout(false)` decision". That
decision has been withdrawn on notifications and never applied on conversations,
so the justification no longer holds where it matters. The real body
(gon-6.3.2 `helpers.rb:29-37`) is four lines and issues no SQL; its stated
blocker — "needs a RequestStore dump missing in the rig" — is a `request.uuid`
that `ActionController::TestCase` supplies. The `AUTH_CHAIN` branch is NOT the
fix either: it evaluates `to_json` at PUSH time, relocating the presenter's
reads out of render order. Fix: run the real body; delete the stale rationale.
*Verified clear on closed endpoints:* conversations renders the real layout and
invokes `gon` 23 975 times, with `services`/`contacts`/`roles`/`aspects` views
in its policy; comments renders no layout at all (`render layout: false` is the
app's own code, `comments_controller.rb:52-53`), so the stub has no instance.

**Rule for both:** when the shared boundary is changed, re-run the closed
endpoints' note checks before trusting that "behaviour-neutral" — a mock whose
projection changes can move a policy view even where the note count does not.

**3. `Relation#size` renders a ROW projection too** (notifications C7). The
shared calculations family renders the row projection for `count`, `sum` AND
`size`; `count` survives only because batches override it locally. `size` on an
UNLOADED relation issues `SELECT COUNT(*)`, but the mock notes it with
`sql_for(receiver, args)` — so a corpus records a row SELECT where the app
issues a COUNT. On notifications this ONE bug produced BOTH matrix rows: the
OVER on the row SELECT (3× per mobile dump, `_header.mobile.haml` reads
`current_user.unread_notifications.size` twice) and the UNDER on
`COUNT(*) … unread`. Fix with the aggregate projection, in the same
AGG-COLLAPSE style as `count`.
*Verified clear on closed endpoints:* `size` is invoked **0 times** on both
conversations_index and comments_index — it appears in the exercise census's
declared-but-never-invoked list for both. notifications is the first corpus
that could see it, which is precisely why the exercise census was worth adding.

**4. `SingularAssociation#find_target` has no loaded-target memo.** A second
read of the same `has_one`/`belongs_to` in one request re-issues the statement;
the real app loads once. This is T-z / C-13 extended from `CollectionProxy` to
singular associations. Fix belongs in the shared `find_target` mock as a
per-run memo keyed on (owner, reflection) — by PREPEND, never a second
`declare_target`, which would capture the first wrapper as its "original" and
nest it.
*Measured on closed endpoints:* comments **0** occurrences. conversations
**696** in 6 000 dumps — but across exactly **ONE** distinct shape
(`SELECT "profiles".* … "person_id" = @ LIMIT`), which is already a view in its
policy. So the effect there is on MULTIPLICITY only; **no view is added or
removed and the extracted policy is unchanged**. Same conclusion as M-18, by a
different mechanism: over-emission of an existing shape costs the policy
nothing but its count.
