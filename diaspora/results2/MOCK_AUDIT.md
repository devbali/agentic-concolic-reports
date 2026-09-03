# MOCK_AUDIT — Phase B leaf audit ledger (MOCK_FIDELITY campaign)

Produced during the MOCK_FIDELITY opening stage (Phase A code + Phase B audit
only — no descents, no corpus regeneration in this stage; one permitted smoke
run on comments_index, reported in REPORT_MOCK_FIDELITY_PHASE_A.md text
below). Classification per `results2/README.md` §THE DISCIPLINE:

- **CLEAN LEAF** — real body has no SQL and calls no other declared target.
  For the DESIGN #1-#11 query-interception mocks this means "this IS the
  accepted query-boundary substitution point," not "nothing is skipped
  beneath it" — that's the whole design (see README's tool #1).
- **VIOLATION** — real body reaches SQL directly, or calls another declared
  target (so that target's own note/PC never fires along this path).
- **DEAD** — not reachable on results2's 6 entrypoints today, verified
  against the current dump corpus or the entrypoint's real call graph.

Audited by: direct reading (shared design mocks #1-11, `find_target`,
`User#blocks`, `Post.blocked_people`, all 6 `targets.rb` batch-local files,
`PostService#mark_user_notifications`'s full call chain, the 3 items two
audit forks left ambiguous) + two parallel fork audits (Gate1b/X6/X7/X8 app
mocks; W/X/Y/Z framework/gem-boundary mocks). Every VIOLATION below is
cited to a real file:line.

## Headline counts

**Shared layer (`concolic_targets.rb`, 64 `declare_target` source statements —
counting each `.each`-block declaration once, matching how `grep -c
declare_target` counts the file; byte-identical across all 6 copies except
the documented collect_binds bind-order fix). Exact tally, verified by
walking all 64 statements against the classification tables below:**

| classification | count |
|---|---|
| CLEAN LEAF (incl. design query-boundary families #1,#2,#3,#4,#5,#7,#8,#9,#11 — 9 statements covering find/find_by/exists?/records/count/update_all/save/find_by_sql/Sidekiq, plus the app-specific and framework leaves) | 41 |
| VIOLATION | 18 |
| DEAD (on these 6 entrypoints specifically) | 3 |
| N/A — explicit `UNSUPPORTED` raise, not a value-mock (design #5b `pluck`/`ids`/etc., #6 Batches) — loud by design, out of scope for leaf/note audit | 2 |
| **Total shared declares** | **64** |

(An earlier draft of this table underestimated VIOLATION as 15 by
undercounting — corrected here after a full line-by-line recount against the
tables below; the per-mock rows were always accurate, only this summary
tally was off.)

**Batch-local (`targets.rb` × 6 files, ~53 `declare_target`/`prepend` sites):**

| classification | count |
|---|---|
| CLEAN LEAF (query-boundary shape-fixes, ordinal-naming layers, association-scoping prepends, boundary-decision mocks) | ~47 |
| VIOLATION (found this audit: `btpa#find_target` junk-note — fixed in Phase A, not a leaf violation) | 0 new |
| Shape-only overrides of an ALREADY-classified shared mock (inherit that classification) | ~6 |

**Worst violations by covered-up query surface (descending):**

1. `ActionController::Rendering#render`/`#render_to_string`/`#render_to_body`
   (+ `ImplicitRender#default_render`, same surface) — the entire view/partial
   render pipeline for every HTML/JSON-via-template response on all 6
   entrypoints. Explicitly the brief's named "deep descent," not fixed here.
2. `ActsAsApi::Collection#as_api_response` — every `api_accessible` field
   accessor across every serialized model (Post, Comment, Person, ...),
   recursively. The brief's other named "deep descent."
3. `PostService#mark_user_notifications` — confirmed via direct source read
   to skip **4 real queries**, not the 1 the code comment claims:
   `Notification.where(...).update_all`, `Mention.where(...).ids`,
   `mentions_in_comments_for_post` (a joined `Mention` query), and a
   `.pluck(:id)` on it. See row below.
4. `Diaspora::Mentionable.people_from_string` — `find_or_fetch_person_by_identifier`
   → `Person.find_or_fetch_by_identifier`, a real lookup that can also hit
   federation discovery I/O.
5. `Post.singleton_class.blocked_people` — genuinely new finding, see row
   below: an app-source Gate-1b split whose own body calls `user.blocks`
   (itself a separately-declared, now-correctly-noted target) — the extra
   outer mock means that inner mock's note never fires for this call path.
6. `Stream::Multi#publisher_prefill`, `Stream::Aspect#aspect_ids`,
   `Stream::FollowedTag#tag_ids`, `Stream::Base#attach_user_likes`,
   `StatusMessageCreationService#add_to_streams`, `User#add_to_streams`,
   `User#retract`, `User#confirm_email`, `ApplicationController#after_sign_in_path_for`,
   `Person#name`, `PostPresenter#build_mentioned_people_json` — each skips one
   or two association loads / persistence-mock calls whose notes never fire.

---

## Shared layer — design mocks #1-#11 (query-interception boundary)

These ARE the accepted substitution for real SQL (README tool #1's
corollary: "every mock standing in for a query must render the real SQL...
in its note"). Classified CLEAN LEAF as a category; Phase A audited/fixed
their note fidelity specifically (rows marked "FIXED").

| # | Mock(s) | real body location | classification | note fidelity |
|---|---|---|---|---|
| 1 | `FinderMethods` `find/take!/first!/last!/find_by!/find_by/take/first/last` | activerecord `relation/finder_methods.rb` | CLEAN LEAF (query boundary) | already real SQL via `render_relation_sql` |
| 2 | `Core::ClassMethods` `find/find_by/find_by!` | activerecord `core.rb:157-218` | CLEAN LEAF (query boundary) | **FIXED this stage** — was `args=nil` on 44/44 observed calls (see Phase A report); now real SQL when the interceptor captures usable args, else an honest labeled fallback (documented interceptor gap, not fixable from results2) |
| 3 | `exists?/any?/none?/one?/many?/empty?` | activerecord `finder_methods.rb`/`relation.rb` | CLEAN LEAF (query boundary) | real SQL via `sql_for` |
| 4 | `Relation#to_a/to_ary/records/size` | activerecord `relation/delegation.rb`,`calculations.rb` | CLEAN LEAF (query boundary) | real SQL via `sql_for`; **gap found+fixed this stage**: `CollectionProxy` (a `Relation` subclass) overrides `records` itself (collection_proxy.rb:1003 → `load_target`), so bare collection-association reads (`post.comments`, `user.aspects`) never hit this mock at all — see Phase A item 2 below |
| 5 | `Calculations#count/sum` | activerecord `calculations.rb` | CLEAN LEAF (query boundary) | real SQL via `sql_for` |
| 5b | `pluck/ids/average/minimum/maximum/calculate` | — | N/A (explicit `UNSUPPORTED` raise, not a value-mock) | loud by design, not a note-fidelity target |
| 6 | `Batches#find_each/find_in_batches/in_batches` | — | N/A (explicit raise) | — |
| 7 | `Relation#update_all/delete_all/destroy_all` | activerecord `relation.rb` | CLEAN LEAF (write-query boundary) | real SQL via `sql_for` |
| 8 | `Base#save/save!/update/update!/update_attribute/touch/destroy/destroy!` | activerecord `persistence.rb` | CLEAN LEAF (persistence boundary) | note is a fixed description string, not SQL-shaped — writes (INSERT/UPDATE/DELETE), out of Phase A's stated "SELECT-shaped" scope; flagged as a minor future improvement, not fixed this stage |
| 9 | `Querying#find_by_sql/count_by_sql` | activerecord `querying.rb` | CLEAN LEAF (raw-SQL boundary) | already compliant — note = `args["sql"].to_s`, the real SQL text |
| 11 | `Sidekiq::Client#push/#push_bulk` | sidekiq-5.2.8 `client.rb:69` → Redis write | CLEAN LEAF (enqueue boundary, no app SQL) | N/A (not a query stand-in) |

## Shared layer — #10 Gate-1b call-site mocks + related app-specific splits

| Mock | real body file:line | classification | what it covers up | descent plan |
|---|---|---|---|---|
| `User#blocks` | app/models/block.rb (`belongs_to :user`, default FK) | CLEAN LEAF (association-read boundary) | — | **Phase A note FIXED this stage**: was junk `"User#blocks"`, now `SELECT "blocks".* FROM "blocks" WHERE "blocks"."user_id" = $$(...)` |
| `Post.singleton_class.blocked_people` | app/models/post.rb:105 (`user.blocks.map{...}`) | **VIOLATION — new finding** | Its real body calls `user.blocks`, itself a declared target (immediately above). Because `blocked_people` is *also* separately mocked, `user.blocks` never actually fires along this call path — the query note is lost even though the sibling mock exists. Contradicts the file's own adjacent comment ("DESIGN table targets `user.blocks`... NOT `excluding_blocks`") — this extra mock looks vestigial. | **Remove** the `Post.blocked_people` `declare_target`; let it run for real so it calls the (correctly-noted) `User#blocks` mock and a pure `.map`. Toolbox: none needed, this is a straight unmock. |
| `Stream::Aspect#aspect_ids` | lib/stream/aspect.rb:90 | VIOLATION | `aspects.map(&:id)` — `aspects` is an unloaded association Relation; `.map` triggers real enumeration via `Relation#records` (declared target), skipped by returning concrete `[1]`. | Narrow/split: let `aspects` materialize via the (now CollectionProxy-aware) rows mock, mock only the id-extraction transform. Toolbox: IterableSymbolicList representative iteration. |
| `Stream::FollowedTag#tag_ids` | lib/stream/followed_tag.rb:27 | VIOLATION | Same pattern — `tags.map{...}` skips the `tags` association's `Relation#records` load. | Same as above. |
| `Stream::Base#post_ids(posts)` | lib/stream/base.rb:93 | CLEAN LEAF | — | `posts` arg is already materialized; pure `.map(&:id)`. |
| `Stream::Base#attach_user_likes(posts, likes)` | lib/stream/base.rb:100 | VIOLATION | `likes` arg is the unloaded `Like.where(...)` relation built by the caller; `.inject` here is what actually triggers its SQL load (`Relation#records`). The method's own comment ("SQL stays in like_posts_for_stream!") is inaccurate — `.where` alone issues no SQL, enumeration does, and enumeration is inside this mocked body. | Narrow: mock only the `post.user_like = ...` assignment loop; let `likes.inject` run for real (needs IterableSymbolicList's iteration ops). |
| `StreamsController#decorated_stream_posts` | app/controllers/streams_controller.rb:77 | CLEAN LEAF (`posts` already materialized) | — | pure `posts.map { presenter }`, matches its comment. |
| `Stream::Multi#publisher_prefill` | lib/stream/multi.rb:40 | VIOLATION | `user.followed_tags.size` + `.map` (Relation#size/#records, declared targets) and `user.invited_by.try(:person)` (`SingularAssociation#find_target`, declared target) — all skipped. | Split string-building from the two association reads; let the associations load for real via existing (now note-fixed) mocks. |
| `TagsController#prep_tags_for_javascript` | app/controllers/tags_controller.rb:68 | CLEAN LEAF | — | `@tags` already materialized; pure transform. |

## Shared layer — X6/X7/X8 wall-fixing mocks (app-specific)

| Mock | real body file:line | classification | what it covers up | descent plan |
|---|---|---|---|---|
| `Person#name` | app/models/person.rb:247 | VIOLATION | `profile.first_name`/`last_name` reads route through `SingularAssociation#find_target` (declared target, now note-fixed) — mocking the whole reader to a fixed string skips that association load. | Narrow: let `profile` load for real; mock only `Person.name_from_attrs`' string formatting. |
| `PostPresenter#build_mentioned_people_json` | app/presenters/post_presenter.rb:94 | VIOLATION (conditional) | `@post.mentioned_people.as_api_response(:backbone)` — `as_api_response` is a declared (violation) target; currently low-impact because upstream `people_from_string` seeds `mentioned_people` empty by default, but the mock unconditionally short-circuits regardless of that seed. | Remove; covered by the `as_api_response` deep descent once that's tackled. |
| `Diaspora::MessageRenderer#title` | lib/diaspora/message_renderer.rb:227 | CLEAN LEAF | — | `@text.lstrip` + regex + `truncate` — pure string ops, no SQL/target calls. |
| `Diaspora::MessageRenderer::Processor.process` | lib/diaspora/message_renderer.rb:12 | CLEAN LEAF | — | pure string pipeline (squish/truncate/escape/gsub). |
| `User#add_to_streams` | app/models/user.rb:258 | VIOLATION | `aspects_to_insert.each { |a| a << post }` — `CollectionProxy#<<`→`insert_record`→`record.save`, and `Base#save` IS a declared target whose PC/note is skipped per iteration. | Narrow to mock only the `<<` call sites; or document as an accepted low-value persistence no-op (side effects aren't branch-relevant here). |
| `StatusMessageCreationService#add_to_streams` | app/services/status_message_creation_service.rb:68 | VIOLATION | Calls `user.add_to_streams` (above) + `status_message.photos.each` (association load, now CollectionProxy-aware, declared target) — both skipped. | Split: keep photos load real, mock only the loop body. |
| `User#retract` | app/models/user.rb:369 (self-acknowledged in its own comment) | VIOLATION | `Retraction.for(target)` → `target.subscribers` (real query, not obviously mocked elsewhere) and `retraction.perform → target.destroy!` (`Base#destroy!`, declared target) — its PC/note is lost. | Narrow: let `retraction.perform` run for real; mock only federation entity construction/dispatch. |
| `Diaspora::Mentionable.people_from_string` | lib/diaspora/mentionable.rb:46-49 | VIOLATION | `find_or_fetch_person_by_identifier` (line 88) → `Person.find_or_fetch_by_identifier`, a real DB lookup that can also trigger federation-discovery network I/O on a miss. | Narrow: mock only `find_or_fetch_person_by_identifier`'s network-discovery branch (a boundary-decision shim), let the local `Person` lookup run for real through the existing finder mock. |
| `ActiveRecord::Associations::CollectionProxy#create` | activerecord `collection_proxy.rb:349` → `@association.create(...)` | VIOLATION (self-acknowledged in-code) | Real create builds+saves the child — `Base#save`-family target skipped, by design, because the parent isn't persisted under symbolic execution (framework precondition can't hold). | Keep as-is; log as a knowingly-accepted violation, not silently clean. |
| `User#mine?` | app/models/user.rb:489 | CLEAN LEAF | — | pure attribute compare (`self.id == target.user_id`). |
| `ApplicationController#after_sign_in_path_for` | app/controllers/application_controller.rb:154 | VIOLATION | `current_user.basic_profile_present?` → `tag_followings.any?` (declared `any?` target, DESIGN #3) — skipped. | Narrow: let `current_user_redirect_path` run for real; the original wall was only the nil-`current_user` case. |
| `ApplicationController#configure_permitted_parameters` | app/controllers/application_controller.rb:197 | CLEAN LEAF | — | Devise sanitizer construction is the actual wall, not app SQL/targets. |
| `User#confirm_email` | app/models/user.rb:232 | VIOLATION | `token != confirm_email_token` branch always short-circuits true; `self.email = ...; save` — `Base#save` target's PC/note never fires. | Narrow: mock only the token-comparison (boundary-decision symbool true/nil), let `save` run for real. |
| `ActionDispatch::Journey::Router::Utils.escape_segment` | actionpack `journey/router/utils.rb:84` (gem) | CLEAN LEAF | — | Pure percent-encoding. |

## Shared layer — W/X/Y/Z framework & gem-boundary crash-stoppers

| Mock | real body file:line | classification | what it covers up | descent plan |
|---|---|---|---|---|
| `ActionController::Rendering#render`/`#render_to_string`/`#render_to_body` | actionpack `metal/rendering.rb:34` → `super` → full ActionView template+partial pipeline | **VIOLATION (biggest in the file)** | The entire view/partial render pipeline for every entrypoint — e.g. `app/views/comments/_comment.mobile.haml`, `app/views/conversations/_conversation.haml`, `app/views/notifications/index.html.haml` invoke presenter/model methods that may themselves query. | **Not fixed this stage — the brief's named deep descent for the next stage.** Documented completion-boundary decision (README §Z's own comment already states this explicitly). |
| `ActionController::ImplicitRender#default_render` | actionpack `implicit_render.rb:32` → calls `render(*args)` | VIOLATION, same surface as render above (not additional) | same as render | subsumed by the render-boundary descent, no separate plan |
| `ActionController::Redirecting#redirect_to` | actionpack `redirecting.rb:58` | CLEAN LEAF | — | sets status/location only |
| `ActionController::Instrumentation#redirect_to` (X6g, the actual wrapper most controllers resolve to — separate declare from the row above) | actionpack `instrumentation.rb:64` → `super` (delegates to `Redirecting#redirect_to`, itself mocked) then instruments | CLEAN LEAF | — | terminal marker, same reasoning as `Redirecting#redirect_to`; kept as its own row since it's a distinct `declare_target` statement |
| `ActionDispatch::Routing::UrlFor#url_for` | actionpack `routing/url_for.rb:168` | CLEAN LEAF | — | pure route generation |
| `DeviseController#assert_is_devise_resource!` / `#devise_mapping` | devise-4.7.1 `devise_controller.rb:59,64` | CLEAN LEAF | — | mapping lookup + presence check only |
| `ActionController::Metal#status=`, `#head`, `ActionController::Head#head` | actionpack `head.rb:21` | CLEAN LEAF | — | header/status bookkeeping; internal calls (`status=`, `url_for`) are themselves mocked, no SQL |
| `ActionController::Rendering#_set_rendered_content_type` | actionpack `rendering.rb:75` | CLEAN LEAF | — | sets content_type if unset |
| `ActiveRecord::Associations::SingularAssociation#writer` | activerecord `singular_association.rb:16` → `replace(record)` | VIOLATION by real-body reading (belongs_to counter-cache UPDATE; has_one calls `load_target`+`record.save`, both declared targets) — **but confirmed DEAD**: `grep` across every existing corpus dump (all 6 entrypoints, all runs) finds **zero** `SingularAssociation.writer` symbolic_call events; all 6 entrypoints in results2 are read-only (index/show) actions that never do `record.assoc = x`. | dead code on these entrypoints (not the app generally) | Document as DEAD, not descended, unless a future entrypoint does an association write. |
| `Photo#url` | app/models/photo.rb:113 | CLEAN LEAF | — | string concat + camo URL helper, no SQL |
| `Photo.diaspora_initialize` | app/models/photo.rb:78 | CLEAN LEAF, but **DEAD** on these 6 entrypoints (all read-only; no photo-create action in results2's scope) | — | — |
| `Post.diaspora_initialize` | app/models/post.rb:153 | CLEAN LEAF, but **DEAD** on these 6 entrypoints (no post-create action in scope) | — | — |
| `ActsAsApi::Collection#as_api_response` | acts_as_api-1.0.1 `base.rb:53` → `api_template.rb:98-106`, calls every `api_accessible` field's accessor and recurses into any that themselves respond to `as_api_response` | **VIOLATION (2nd biggest)** | Every custom JSON-attribute accessor across every serialized model (Post/Comment/Person/...), recursively. | **Not fixed this stage — the brief's other named deep descent.** Per-attribute audit needed before narrowing. |
| `Diaspora::Taggable#build_tags` | lib/diaspora/taggable.rb:36 | CLEAN LEAF | — | regex scan of an in-memory string attribute |
| `StatusMessage#tag_name_max_length` | lib/diaspora/taggable.rb:17 | CLEAN LEAF | — | iterates in-memory `tag_list` |
| `DiasporaFederation::Entity#validate` | diaspora_federation gem `entity.rb:248` | CLEAN LEAF | — | in-memory attribute validators, no DB access found |
| `DiasporaFederation::Entity#normalize_property` | diaspora_federation gem | CLEAN LEAF | — | string/type coercion only, mirrors real branches per its own comment |
| `PostService#mark_user_notifications` | app/services/post_service.rb:24-90, **directly re-verified this audit** | **VIOLATION — worse than documented** | Real body chains **4** queries, not the 1 the existing code comment claims: `mark_comment_reshare_like_notifications_read` → `Notification.where(recipient_id:, target_type:, target_id:, unread: true).update_all(unread: false)`; `mark_mention_notifications_read` → `Mention.where(...).ids` **and** `mentions_in_comments_for_post(post_id)` → a joined `Mention` query **and** `.pluck(:id)` on it. All 4 silently skipped. | Descend: these are write/id-only queries whose results aren't branched on by posts_show; likely safe to split (extract the 4 query calls as their own no-op-return mocks preserving `sql_for`-rendered notes) rather than let the whole real chain run, since none of it affects downstream branching — but each must get its own real-SQL note, not the current blanket nil no-op. |
| `Gon::ControllerHelpers#gon` | gon-6.3.2 `helpers.rb:30` | CLEAN LEAF | — | RequestStore bookkeeping only |
| `Sidekiq::Client#push`/`#push_bulk` | sidekiq-5.2.8 `client.rb:69` | CLEAN LEAF | — | Redis write, not app DB (also listed under design #11 above) |

---

## Batch-local — `targets.rb` × 6 (query-boundary shape-fixes, association-scoping shims, and app-specific additions)

Most batch-local declarations are **shape-only overrides** of an already-classified
shared design mock (same query, different return type — e.g. `IterableSymbolicList`/
`SampledList` instead of the shared file's plain `SymbolicList`, so `.each`/`.map`
stop raising) or **ordinal-naming layers** (alias a finder to a dedicated method
name so its `SYM_RESULT` counter doesn't collide with an unrelated call to the
same shared method). Both patterns inherit the classification of the shared mock
they reshape and are CLEAN LEAF by the same reasoning — listed here for
completeness per the brief's "one row per... batch-local mock" instruction.

| File | Mock / prepend | classification | notes |
|---|---|---|---|
| comments_index | `BelongsToPolymorphicAssociation#klass` | CLEAN LEAF | pure type-string→Class resolution (AR's own `type.presence` check, no app branch, no SQL) |
| comments_index | `BelongsToPolymorphicAssociation#find_target` | CLEAN LEAF (association-read boundary) | **Phase A note FIXED this stage** — was junk `"BelongsToPolymorphicAssociation#name (...)"`, now real `SELECT ... WHERE ... = $$(...)` (same fix pattern as shared `SingularAssociation#find_target`, applied to the polymorphic subclass that shadows it) |
| comments_index | `Relation#to_a/to_ary/records` (IterableSymbolicList shape) | = shared design #4 | shape-only |
| comments_index | `CollectionProxy#to_a/to_ary/records/load_target` | = shared design #4 | **Phase A item 2 FIXED this stage** — added so bare `post.comments.for_a_stream`-style collection-association reads get a real recorded query note instead of bypassing the mock layer entirely (see Phase A report; confirmed inert-but-harmless in the comments_index smoke run since `for_a_stream`'s chain there resolves to a plain `Relation`, not `CollectionProxy`, on this specific path) |
| comments_index | `Diaspora::Mentionable.people_from_string` (shape override → `Person.none`) | = shared `Mentionable.people_from_string` (VIOLATION, see above) | shape-only; underlying violation unchanged |
| conversations_index | `ConvoSymAssociations#conversation_visibilities/#messages/#conversation/#participants` (prepend, not `declare_target`) | CLEAN LEAF | manually reconstructs the scoped relation the real association would build (`Model.where(fk: self.id)`), off the symbolic receiver's own attribute — the query still flows through the (correctly-noted) design-#4 mock; this is exactly the results2/README §5 "scope the mock relation manually" pattern, not a violation |
| conversations_index | `Relation#convidx_conv_lookup` (aliased `:first`, dedicated ordinal) | = shared design #1 (`finder_mock`) | ordinal-naming layer only |
| conversations_index | `Calculations#pluck` (+ `PluckArgs` prepend recovering real column list) | CLEAN LEAF (query boundary) | real SQL via `sql_for`; `PluckArgs` works around a separate, documented `call_args` capture gap (out of scope, same family as the class-finder kwargs gap found in Phase A) |
| conversations_index | `Relation#to_a/to_ary/records` (SampledList shape) | = shared design #4 | shape-only; **no CollectionProxy addition here** — verified conversations#index's own query paths (`ConversationVisibility.includes(...)`, `Conversation.joins(...)`) are class-level Relations, never a bare collection-association read, so the CollectionProxy gap doesn't apply to this entrypoint (confirmed via app/controllers/conversations_controller.rb, not spec­ulative) |
| notifications_index | `Relation#to_a/records` (IterableSymbolicList), `#to_ary` (SampledRowsArray), `Calculations#count` (ConcolicIntValue) | = shared design #4/#5 | shape-only value fixes (WillPaginate coercibility); `symbolic_instance` wrapper adds `ConcolicDate`/`ConcolicIntValue` column typing, not a new query mock |
| notifications_index | — | — | **no CollectionProxy addition** — verified `notifications_controller.rb`'s only collection reads are `Notification.where(...)` (class-level) and `current_user.unread_notifications` = `notifications.where(unread: true)` (an `AssociationRelation`, which does NOT override `records` — confirmed in activerecord source — so the existing design-#4 mock already covers it) |
| people_show | `Relation#to_a/to_ary/records` (IterableSymbolicList), `CollectionProxy#to_a/to_ary/records/load_target`, `Querying#find_by_sql` (IterableSymbolicList shape) | = shared design #4/#9 | **CollectionProxy addition Phase A item 2 FIXED this stage**, same rationale as comments_index; `find_by_sql` shape-only (already real-SQL noted upstream) |
| people_stream | same as people_show, plus `PeopleController#diaspora_id?` boundary mock | `diaspora_id?`: CLEAN LEAF | pure string-validation boundary decision (`lstrip`/`downcase`/regex, no SQL) — correct use of the "boundary-decision symbool" toolbox pattern for a `src/` SymbolicString-transform gap |
| posts_show | `Relation#to_a/to_ary/records`, `CollectionProxy#to_a/to_ary/records/load_target` (rows_mock, IterableSymbolicList) | = shared design #4 | **this is the ORIGINAL, already-landed fix that Phase A item 2 ported into comments_index/people_show/people_stream this stage** |
| posts_show | `Calculations#pluck`/`#ids` (iterable rep) | = shared design #5 | shape-only, real SQL via `sql_for` |
| posts_show | `Diaspora::Mentionable.people_from_string` (shape, seedable length) | = shared `Mentionable.people_from_string` (VIOLATION, see above) | shape-only |
| posts_show | `ActsAsApi::Collection#as_api_response` (shape, seedable length) | = shared `as_api_response` (VIOLATION, see above) | shape-only; underlying violation unchanged |
| posts_show | `Relation#evilq_{ctx}_{attempt}` / `#findpublic_{ctx}` (aliased `:first`, dedicated ordinals) + `EvilQueryAttemptRouting`/`FindPublicRouting`/`LikeServiceContextTag` prepends | = shared design #1 | ordinal-naming/context-routing layer only, same pattern as conversations_index's `convidx_conv_lookup` |

---

## Ambiguous items / needs a ruling

1. **`PostService#mark_user_notifications`** — the 4-query finding above is
   more severe than the file's own comment claims. Since none of those 4
   queries' results are branched on (all feed either `update_all`'s discarded
   return or a Sidekiq dispatch), the descent is low-risk but still real work
   for the next stage — flagging for prioritization rather than assuming it's
   low-value just because it's a write path.
2. **`Base#save`-family notes** (design #8) are description strings, not
   SQL-shaped — they're writes (INSERT/UPDATE/DELETE), so they fall outside
   Phase A's literal "SELECT-shaped" acceptance criterion, but arguably
   deserve the same `$$()`-bind treatment for consistency. Left unfixed this
   stage; ruling requested on whether that's in scope for a future Phase A
   follow-up or deliberately out of scope (writes' concrete side effects
   aren't queried back, so the argument for fixing is weaker).
3. **`SingularAssociation#writer`** — classified VIOLATION on real-body
   grounds but confirmed DEAD on all 6 entrypoints today (zero occurrences in
   the existing corpus). Listed as DEAD; will need re-classification the
   moment any write-action entrypoint (create/update) is added to results2.
4. **`ActiveRecord::Associations::CollectionProxy#create`** — a
   self-acknowledged, deliberate violation (parent record isn't persisted
   under symbolic execution, so the real framework precondition can't hold).
   Recommend accepting as a permanent, documented exception rather than
   pursuing a descent, since there's no legal way to satisfy the real
   precondition symbolically — ruling requested.
