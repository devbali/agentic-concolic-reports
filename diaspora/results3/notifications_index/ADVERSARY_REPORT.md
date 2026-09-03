# ADVERSARY REPORT — notifications_index (NotificationsController#index, signed-in only)

Adversary run 2026-08-27 against the batch's `complete: true` claim
(`coverage_summary.json`: 94 PC nodes, 14 951 dumps, 20 corpus targets,
7 variants html/json/mobile × plain/typed + xml_plain, 4321/4321
assumptions PASS, `coverage_complete: true`, BLOCKING 0).

Real app only: `concrete_env.rb` sqlite via JDBC + the app schema, raw
fixture ROWS by `insert`, real Devise `User.serialize_from_session` (salt
primed OUTSIDE the capture window), real `ActionController::TestCase#process`
(every `before_action` runs), real templates, `NotificationsController.layout(false)`
parity with the batch runner. **No mocks, no stubs, no monkey-patches; nothing
under `src/`, the app, or the batch's runner/targets/mocks/manifests touched.**
The batch's own concrete runs were never overwritten — md5 of
`concrete_run.json` / `concrete_run_auth.json` / `concrete_run_mobile.json`
identical before and after (`3c0b6ca1…`, `a5df3ffb…`, `6510cd24…`); the probe
writes next to the manifest, i.e. into `adversary/`, and each run was moved to
`adversary/runs/<TAG>.json`.

Files: `adversary/_common.rb` (shared harness), `adversary/A0*.rb` (one
scenario per process), `adversary/run_chain.sh`, `adversary/analyze.py`,
`adversary/runs/` (`A0*.json|.log|.judge.txt|.fidelity.txt|.sqlite3`,
`_body_*`, `_note_fidelity_all.txt`, `_progress.log`).

Judges: `mock/mock_note_check.py` (per-frame real statements vs corpus notes,
aliases applied), `tools/note_fidelity_audit.py` (projection / predicate /
aggregate fidelity), and a depth-0 `target_calls` vs corpus-target comparison
done in `analyze.py` + a corpus-target grep over all 14 951 dumps.

**Instrument note.** The harness traces the batch's own resolved target list
(the 20 corpus target names minus the unresolvable batch-local aliases
`devise_user_first` / `Anonymous.*`, minus the batch's own documented waiver
`ActionController::Rendering._set_rendered_content_type`, plus the batch's own
`extra:` list) **plus `ActiveRecord::FinderMethods#exists?`**, so an existence
probe is attributed to its own frame instead of being silently absorbed by the
enclosing target frame. See near-miss N9: without that extra trace the W1
statement is attributed to `Diaspora::MessageRenderer#title`, and it is still RED.

---

## Verdict

**3 wins** (2 blocking + 1 conditional on legacy data), all judged RED by both
instruments:

- **W1 — `Post.exists?(guid:)` swallowed inside the `Diaspora::MessageRenderer#title`
  TARGET.** Any notification whose rendered post/comment text contains a
  `diaspora://<handle>/post/<guid>` link issues
  `SELECT  1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?`.
  The corpus has **0** `exists?` events and **0** occurrences of the string
  `1 AS one` in any of its 14 951 dumps. `title` is a declared target whose
  mock comment says "Pure string heading extraction, no SQL" — it is not.
- **W2 — a notification whose polymorphic target is a `Photo`** (created by
  `Notifications::CommentOnPost.notify` whenever the comment's commentable is a
  photo) reads two tables/predicates the corpus has no note for:
  `SELECT "photos".* FROM "photos" WHERE "photos"."id" = ?` (the `includes(:target)`
  preload) and
  `SELECT  "posts".* FROM "posts" WHERE "posts"."type" IN ('StatusMessage') AND "posts"."guid" = ? LIMIT ?`
  (`Photo#status_message`, keyed by GUID).
- **W3 (conditional) — a `Notifications::PrivateMessage` row reads the
  `conversations` table**: `SELECT "conversations".* FROM "conversations" WHERE "conversations"."id" = ?`.
  The string `conversations` appears **0** times in the whole corpus. Reachability
  caveat below.

`complete: true` is void at least until W1 and W2 are in the corpus and the
check that catches their class exists.

Everything else on the attack list — pagination page 2 / beyond the last page /
`per_page`, invalid `page`, `show=unread` × `type`, invalid `type`, missing /
NULL polymorphic targets, actor-less notifications, an actor row pointing at a
missing person, `ContactsBirthday`, a `Reshare` target, blank-text + photos
posts, 1/3/4/5 actors, closed-account / remote / blank-name actors, multi-day
and multi-year grouping, html vs json vs mobile vs xml — produced only shapes
the corpus already carries. The near-misses section records what those runs
exposed anyway (two large over-emission families, a never-seeded list length,
and a mis-modelled `target_type`).

---

## Scenarios

| # | manifest | fixtures / request | status | mock_note_check | note_fidelity | result |
|---|----------|--------------------|--------|-----------------|---------------|--------|
| A01 | `A01_diaspora_links.rb` | posts 100/101/102 + comment 300 whose texts carry `diaspora://…/post/<existing guid>`, `web+diaspora://…/post/<missing guid>`, `diaspora://…/comment/<guid>`; notifications Liked→Post, MentionedInPost→Mention(Post), MentionedInComment→Mention(Comment), AlsoCommented→Post, Reshared→Post. html plain, json plain, mobile (session switch), html `type=liked`, xml | 200 ×5 | **RED** NOTE-MISSING `FinderMethods.exists?` | **RED** STAR-OVER | **WIN W1** |
| A02 | `A02_photo_target.rb` | photo 200 owned by status message 101 (`status_message_guid`), comment 300 on the photo; notifications CommentOnPost→`target_type "Photo"`, AlsoCommented→Photo, Liked→Post (control). html, json, mobile, xml; then an ORPHAN photo (nil `status_message_guid`) inserted and one more html | 200 ×4, orphan → `ActionView::Template::Error` (`status_message is nil`) | **RED** NOTE-MISMATCH ×3 shapes | **RED** PRED-DIFF ×3 | **WIN W2** |
| A03 | `A03_pagination.rb` | 30 notifications (5 unread). html `page=2`, `page=3` (beyond the end), `per_page=2`, json `page=2&per_page=2`, mobile `page=2`, `page=0`, `page=abc`, `show=unread&type=liked`, `type=bogus`, `show=Unread` | 200 ×8; `page=0` `RangeError: invalid page: 0`; `page=abc` `ArgumentError: invalid value for Integer()` (both before any statement) | green | EXACT | no new shape (near-misses N1, N5) |
| A04 | `A04_missing_targets.rb` | Liked→missing post 999999; Liked→NULL `target_type`/`target_id`; StartedSharing→missing person; a notification with ZERO `notification_actors`; an actor row pointing at person 9999 (no row); ContactsBirthday→Person; Liked→a **Reshare** post. html, json, mobile, xml | 200 ×4 | green | EXACT | no new shape |
| A05 | `A05_sharing_and_pm.rb` | StartedSharing from carol with **no `contacts` row**; then a `Notifications::PrivateMessage` row → `target_type "Conversation"`. html `type=liked`, html/json `type=started_sharing`, html plain, json plain | 200 ×4; html-with-PM → `ActionView::Template::Error: undefined method '[]' for nil` (i18n) | **RED** NOTE-MISMATCH `conversations` | **RED** MISSING | **WIN W3 (conditional)** |
| A06 | `A06_photos_blank_text.rb` | post 110 with NULL `text` + 2 photos (the `post_page_title` photos branch); post 111 with NULL text and NO photos (title → nil); MentionedInPost whose container is post 110. html, json, mobile | 200 ×3 | green | EXACT | no new shape (near-miss N4) |
| A07 | `A07_actors_cardinality.rb` | notifications with 4 / 5 / 3 / 1 actors (the `< 4` and `>= 4`, `others.count == 1` branches), one closed-account actor, one blank-name profile, one remote `image_url`, `updated_at` spanning 3 days incl. **last year** (`display_year?`). html, mobile, json, xml | 200 ×4 | green | EXACT | no new shape (near-miss N2) |
| A08 | `A08_actor_no_profile.rb` | an ACTOR person with no `profiles` row (`person_link` → `Person#name` → `fix_profile` → federation Discovery). html, json | **JVM SIGSEGV in `__libc_free`, exit 134**, no `concrete_run.json` | — | — | blocked (see Unreachable) |

8 process runs (7 judged, A08 aborted), 37 requests.
Combined fidelity over all 7 judged runs: `adversary/runs/_note_fidelity_all.txt`
— 41 distinct real SELECTs under 6 frames, **36 EXACT, 1 MISSING, 1 STAR-OVER,
3 PRED-DIFF, 0 AGG-COLLAPSE, 0 PROJ-DIFF**.

Depth-0 target comparison (all runs, `#`→`.` normalised, aliases both ways):
every depth-0 target the real runs reached is in the corpus. Three targets
appear at depth ≥ 1 that the corpus has **no events for at all**:
`ActiveRecord::FinderMethods.exists?` (29 — W1), `ActiveRecord::Relation.to_a`
(7) and `ActiveRecord::FinderMethods.take` (2) (both alias-covered, N7).

---

## WINS (blocking)

### W1 — `Post.exists?(guid:)` from `diaspora_links`, swallowed by the `MessageRenderer#title` TARGET MOCK

- **Scenario:** A01. Any notification whose rendered post or comment text
  contains a `diaspora://<diaspora-id>/post/<guid>` (or `web+diaspora://…`)
  link. Reached on **html, json and mobile** — `notification_message_for(note)`
  → `object_link` → `opts_for_post` / `opts_for_mentioned` → `post_page_title(post)`
  → `post.message.title` — 29 depth-1 calls over 5 requests (html 6, json 6,
  mobile 6, html-typed 3, xml 0 — xml serialises attributes only).
- **Novel shape (verbatim, frame `ActiveRecord::FinderMethods#exists?`,
  depth 1, args `{:guid=>"advpostguid000000000001"}` / `{:guid=>"advmissingguid0000000009"}`):**

  ```
  SELECT  1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?
  ```

- **Issuing code:** `lib/diaspora/message_renderer.rb:100-105`

  ```ruby
  def diaspora_links
    @message = @message.gsub(DiasporaFederation::Federation::DiasporaUrlParser::DIASPORA_URL_REGEX) {|match_str|
      guid = Regexp.last_match(3)
      Regexp.last_match(2) == "post" && Post.exists?(guid: guid) ? AppConfig.url_to("/posts/#{guid}") : match_str
    }
  end
  ```

  reached from `message_renderer.rb:227` `title` → `:241`
  `plain_text_without_markdown` (`:176-183`), driven by `app/helpers/posts_helper.rb:15`
  `post.message.title opts` inside `app/helpers/notifications_helper.rb:33`
  `opts_for_post` / `:43` `opts_for_mentioned`. The rewrite is visible in the
  body (`runs/_body_A01_html.txt`: the existing guid became
  `https://diaspora.internal/posts/advpostguid000000000001`; the missing guid
  and the `comment`-type link stayed verbatim — the `exists?` result decides
  output, and the `Regexp.last_match(2) == "post"` compare is a real branch too:
  the `comment` link issued nothing).
- **Frame nesting (the point of the finding):** all 29 calls are
  `Diaspora::MessageRenderer#title -> ActiveRecord::FinderMethods#exists?`, i.e.
  the SQL is issued **inside the body of a declared TARGET**. That target's
  corpus event is

  ```json
  {"type":"symbolic_call","target":"Diaspora::MessageRenderer.title",
   "args":{"opts":null},"result_value":"Concolic title","result_sort":"String",
   "file":".../app/helpers/posts_helper.rb","lineno":15,"function":"post_page_title",
   "note":"Diaspora::MessageRenderer#title"}
  ```

  20 258 such events in the corpus, every one with a **non-SQL note**. Under
  concolic interception the real body is skipped, so the `posts.guid` existence
  probe is swallowed on every single run. `concolic_targets.rb:1492-1494`
  states the contract it violates verbatim: *"Pure string heading extraction, no
  SQL."* The same is true of the sibling target `Processor.process`
  (`concolic_targets.rb:1508-1512`: *"the single SQL-free pipe entry"*) —
  `diaspora_links` runs inside the block that `Processor.process` executes.
- **Judges:** `mock_note_check` NOTE-MISSING (RED: "issues real SQL, zero
  SQL-shaped corpus notes"); `note_fidelity_audit` STAR-OVER (RED); corpus grep:
  `1 AS one` = **0** occurrences in 14 951 dumps, `FinderMethods.exists?` = **0**
  events.
- **Class: S with a B cause.**
  **S (swallowed):** `Diaspora::MessageRenderer#title` is a TARGET MOCK, so D1
  requires its note to carry the statements the real body issues; it carries a
  junk string instead. Every `posts.guid` existence read on this endpoint is
  invisible to the policy, for every format.
  **B (blinded branch):** `targets.rb` §5g pins `text` to one of three concrete
  strings (`"hello world, a concolic message with no mentions"` /
  `"hello @{Concolic Mention; concolic_mention@example.org} welcome"` /
  `"hello @{concolic_mention@example.org} welcome"`), none of which matches
  `DIASPORA_URL_REGEX`, so the regex match, the `== "post"` compare and the
  `exists?` true/false sides are never recorded — the same pin-forecloses-a-family
  pattern as DISCIPLINE violation #2, and the same root cause the
  `conversations_index` (round 2, W1) and `comments_index` (W1) adversaries found
  on their endpoints. Here it is strictly worse: those two batches at least had
  no target mock standing between the text and the query, so a scenario alone
  would have exposed it; on this endpoint the `title` mock would still swallow
  the statement even if the text pin were fixed.

### W2 — a `Photo` notification target: `photos.id` preload + `Photo#status_message`'s posts-by-GUID read

- **Scenario:** A02. `Comment#commentable` is polymorphic and `Photo` includes
  `Diaspora::Commentable` (`lib/diaspora/commentable.rb:11`
  `has_many :comments, as: :commentable`), so a comment on a photo runs
  `NotificationService::NOTIFICATION_TYPES[Comment]` →
  `Notifications::CommentOnPost.notify(comment)` →
  `app/models/notifications/comment_on_post.rb:22`
  `concatenate_or_create(commentable_author.owner, comment.commentable, actor)`
  — the notification's `target` is the **commentable**, i.e. a `Photo`, and
  `target_type` is `"Photo"`. Fixture: photo 200 with
  `status_message_guid` = status message 101's guid, comment 300 on the photo,
  notifications 510/511 with `target_type: "Photo"`. html, json, mobile, xml.
- **Novel shape 1 (verbatim, frame `ActiveRecord::Relation#records`, the
  `includes(:target)` polymorphic preload):**

  ```
  SELECT "photos".* FROM "photos" WHERE "photos"."id" = ?
  SELECT "photos".* FROM "photos" WHERE "photos"."id" IN (?, ?)
  ```

  Issued by `app/controllers/notifications_controller.rb:36`
  `.includes(:target, :actors => :profile)` (Rails' polymorphic Preloader
  groups by `target_type`). The corpus's ONLY `photos` notes are
  `SELECT "photos".* FROM "photos" WHERE "photos"."status_message_guid" = $$(…)`
  (36 066 occurrences) — a different predicate column entirely; there is no
  `photos.id` predicate anywhere in the corpus.
- **Novel shape 2 (verbatim, frame
  `ActiveRecord::Associations::SingularAssociation#find_target`):**

  ```
  SELECT  "posts".* FROM "posts" WHERE "posts"."type" IN ('StatusMessage') AND "posts"."guid" = ? LIMIT ?
  ```

  Issued by `app/helpers/posts_helper.rb:9-10`

  ```ruby
  if post.is_a?(Photo)
    I18n.t "posts.show.photos_by", :count => 1, :author => post.status_message_author_name
  ```

  → `app/models/photo.rb:45` `delegate :author_name, to: :status_message, prefix: true`
  → `photo.rb:43` `belongs_to :status_message, foreign_key: :status_message_guid, primary_key: :guid`.
  Two things the corpus's `posts` notes never carry: the predicate column
  `posts.guid` (every corpus `posts` note keys on `posts.id`) and the STI
  `posts.type IN (…)` scoping.
- **Judges:** `mock_note_check` NOTE-MISMATCH on both frames (RED: "real
  statement shape(s) with NO corpus note anywhere"); `note_fidelity_audit`
  PRED-DIFF ×3 (RED under the combined audit).
- **Class: B with an S consequence.** `targets.rb:118-143` `NOTE_TYPE_PROFILES`
  enumerates exactly 8 `(STI type, target_type)` pairs and pins `target_type`
  concretely per type (`targets.rb:418` `attrs["target_type"] = profile[:target_type]`).
  `"Photo"` is not among them, so `post_page_title`'s `post.is_a?(Photo)` branch
  (`posts_helper.rb:9`) and the whole `photos.id` / `posts.guid` family are
  invisible to DSE — not "unexplored" but unrecordable, because `target_type` is
  a pin with no seeded alternative. The S consequence is that no note for this
  endpoint can ever mention a `photos.id` read or a `posts.guid` read.
- **Same table, second defect (code-reading, no separate run needed):**
  `NOTE_TYPE_PROFILES` lines 134-135 pin
  `also_commented`/`comment_on_post` → `target_type: "Comment"`. That is wrong
  in the other direction: both `notify` implementations pass the **commentable**
  (`also_commented.rb:23`, `comment_on_post.rb:22`), never the comment. So the
  corpus's 52 834 `SELECT "comments".* … WHERE "comments"."id" = $$(…_target_id)`
  note occurrences model an access the app never makes for those two types,
  while the accesses it does make (a Post — or, per W2, a Photo) are attributed
  to the wrong branch. The correct fixture for those types is `target_type` =
  the commentable's base class.

### W3 (conditional) — `Notifications::PrivateMessage` reads the `conversations` table

- **Scenario:** A05, last two requests. A `notifications` row with
  `type = "Notifications::PrivateMessage"`, `target_type = "Conversation"`,
  `target_id = 1`.
- **Novel shape (verbatim, frame `ActiveRecord::Relation#records`):**

  ```
  SELECT "conversations".* FROM "conversations" WHERE "conversations"."id" = ?
  ```

  Issued by the same `.includes(:target, …)` preload
  (`notifications_controller.rb:36`). The token `conversations` occurs **0**
  times in the entire 14 951-dump corpus.
- **Judges:** `mock_note_check` NOTE-MISMATCH (RED); `note_fidelity_audit`
  MISSING (RED).
- **Reachability caveat (why "conditional"):**
  `NotificationService::NOTIFICATION_TYPES` does wire
  `Conversation => [Notifications::PrivateMessage]` and
  `Message => [Notifications::PrivateMessage]`
  (`app/services/notification_service.rb:8-9`), but
  `app/models/notifications/private_message.rb:22-28` only does
  `new(recipient: recipient).email_the_user(...)` — it never persists. So on a
  pod running *this* code no such row is created; the state is legacy/imported
  data, or any future caller of `create_notification` for that type. The
  batch already knows: `targets.rb:129-133` says PrivateMessage is
  *"DELIBERATELY not driven … documented residue instead"*. What A05 adds is
  that the residue is not shape-neutral — it is a whole table with no note —
  and that the html render of such a row is a real 500 (`undefined method '[]'
  for nil:NilClass` out of the i18n interpolation), while json returns 200.
  Class B (an un-driven dispatch value) with an S consequence.

---

## Near-misses (no new shape, or judge-invisible, or defects the runs re-exposed)

- **N1 — `len(…Relation_to_ary_1_rows)` is never seeded: the notification list
  is ALWAYS exactly one row.** A grep for `"len(` over all 14 951 dumps returns
  ten distinct length seeds — `CollectionProxy_records_{1,2,3}_rows`,
  `Relation_records_{1,2}_rows`, `load_target_1_rows`, `pluck_1_plucked`,
  `people_from_string_1`, the two `_set_rendered_content_type` ones — and
  **not** `len(SYM_RESULT_ActiveRecord__Relation_to_ary_1_rows)`, the length of
  `@notifications` itself. `targets.rb:459` builds it as
  `ct.seed_for("len(#{vn})", 1).to_i`, so it is a **concrete Integer 1** in
  every run and `index.html.haml:56` `@group_days.length > 0` is a concrete
  compare with no PC and no pin-ledger entry (D2). Consequences: the
  `.no-notifications` branch (`index.html.haml:76-79`) and the empty
  `@group_days.each` on mobile are never executed corpus-wide; the multi-row
  states are never expressed (A07's day/year grouping, `display_year?`,
  `the_year`/`the_day`/`the_month`, and the bulk-preload cardinality of N2 all
  live there). A03 `page=3` is the real `count > 0 ∧ rows = []` state (`COUNT`
  returns 30, the LIMIT/OFFSET query returns zero rows, body renders
  `.no-notifications` with 0 stream elements — `runs/_body_A03_p3.txt`), reached
  with nothing but a request parameter that `run_dse.rb`'s ledger pins to 1.
  No new statement shape, so not a win; a blind branch family, so a finding.
- **N2 — preload notes are per-row `= $$(…)`; real preloads are bulk `IN (…)`.**
  A07: `SELECT "people".* FROM "people" WHERE "people"."id" IN (?, ?, ?, ?, ?, ?)`,
  `SELECT "profiles".* … WHERE "profiles"."person_id" IN (?, ?, ?, ?, ?, ?)`,
  `SELECT "notification_actors".* … WHERE "notification_actors"."notification_id" IN (?, ?, ?, ?)`;
  A03 shows a 25-element IN list. The corpus notes are one-per-representative
  `= $$(…)`. Both judges wildcard the literal list and rate it EXACT.
  Column/predicate faithful, cardinality unfaithful — the same defect the
  `comments_index` adversary logged as its N2, and downstream of N1.
- **N3 — over-emission: the `people INNER JOIN notification_actors` family has
  NO real counterpart.** Corpus-wide grep: 494 850 note occurrences of
  `FROM "people" INNER JOIN "notification_actors" ON …`, of which 51 330 are
  `SELECT COUNT(*) FROM "people" INNER JOIN …`. Across all 7 judged adversary
  runs **and** the batch's own three concrete runs, that join is issued
  **zero** times: `notifications_controller.rb:36` `.includes(… :actors => :profile)`
  preloads the through-association, so `note.actors.first` / `.last`
  (`_notification.haml:12`, `index.mobile.haml:21`) and `note.actors.size`
  (`notifications_helper.rb:9`, `:55`) all answer from the loaded target. The
  real statements are the three preload SELECTs (`notification_actors`,
  `people`, `profiles`) which the corpus also carries. Warn-level per the brief
  ("note with no real counterpart"), but the extracted policy inherits both a
  row read and an aggregate over a join the endpoint cannot perform.
- **N4 — over-emission: `SELECT COUNT(*) FROM "photos" WHERE "photos"."status_message_guid" = $$(…)`
  (2 332 occurrences) has no real counterpart.** A06 drives exactly that branch
  (`posts_helper.rb:16-17` `post.respond_to?(:photos) && post.photos.present?`
  then `post.photos.size`) and issues **9 photos SELECTs and 0 photos COUNTs**:
  `present?` → `Relation#blank?` → `records` loads the association, so `.size`
  is in-memory. The row-read note (`photos.*`, 36 066) is correct; the COUNT
  note is an aggregate the endpoint never issues.
- **N5 — `params[:per_page]` is not in the pin ledger at all, and LIMIT/OFFSET
  are baked literals.** `notifications_controller.rb:33`
  `per_page = params[:per_page] || 25` is a request-controlled input;
  `run_dse.rb`'s `summary["params"]` documents only `show`, `type` and `page`.
  The corpus note is
  `SELECT  "notifications".* … ORDER BY updated_at desc LIMIT 25 OFFSET 0` — both
  numbers are literals for values the requester chooses (A03 exercised
  `per_page=2`, `page=2`, `page=2&per_page=2`). `mock_note_check._wildcard`
  rewrites every `\d+` to `?`, so this is judge-invisible; recorded because the
  ledger's pin set is incomplete.
- **N6 — `AlsoCommented` / `CommentOnPost` `target_type` is mis-modelled** — see
  the end of W2. Not a separate scenario; pure code reading against
  `targets.rb:134-135`.
- **N7 — `Relation.to_a` and `FinderMethods.take` are reached but absent from
  the corpus target set.** 7 and 2 calls respectively, always at depth ≥ 1
  under `FinderMethods#first` (`actors.first` on the loaded proxy). Both are
  declared in `concrete_aliases.json` as aliases of `Relation.records`, so the
  statements match; noted only because `targets_from_corpus` would not trace
  them (the corpus has zero events for either), exactly as the `comments_index`
  adversary observed for `to_a`.
- **N8 — STI type-scoping is absent from every corpus `posts` note.** The real
  `Photo#status_message` read carries `"posts"."type" IN ('StatusMessage')`
  (`belongs_to :status_message` resolves to the `StatusMessage` subclass). No
  corpus `posts` note carries a `posts.type` predicate. Folded into W2 because
  it is the same statement.
- **N9 — `exists?` frame attribution.** With the batch's own target list (which
  has no `exists?`), the W1 statement is attributed to the enclosing
  `Diaspora::MessageRenderer#title` frame and `mock_note_check` reports
  NOTE-MISMATCH there instead of NOTE-MISSING on `exists?`. Either way RED —
  but if the batch adds `FinderMethods#exists?` as a target,
  `concrete_aliases.json` will need the `exists? ↔ Relation.empty?/any?/none?`
  family the sibling batches already declare.
- **N10 — the no-contact `StartedSharing` path is fine.** A05 with a
  `StartedSharing` notification for a person alice has no `contacts` row for
  returned 200 on both html and json: `started_sharing.rb:19`
  `recipient.contact_for(target)` returns nil and `gon_load_contact(nil)` is
  tolerated. The real `SELECT "contacts".* … WHERE user_id = ? AND person_id = ? LIMIT ?`
  is issued and matches the corpus note. No finding — recorded because it was
  on the attack list.
- **N11 — the batch's own `skipped_pcs` RED** (200 009 `(VAR == VAR)` +
  3 377 `(VAR != VAR)` PCs dropped by the `src/queries_from_runs` fold,
  `AGENT_RUN.md` Phase-2 audits) is a pre-existing, self-reported fold-space
  Class B. Not re-derived here; flagged so it is not lost.

---

## Unreachable / blocked branches and why

- **An ACTOR (or any rendered person) with no `profiles` row (A08).**
  `profiles.person_id` carries an FK to `people` but nothing forces a profile
  to exist, so the state is a real database state; `people_helper` /
  `person_link` → `Person#name` → `fix_profile` →
  `DiasporaFederation::Discovery::Discovery` (network) → `reload`. The run
  aborted the JVM natively — **SIGSEGV in `__libc_free`, exit 134**, no
  `concrete_run.json` — the third batch in a row to hit this exact crash class
  on this JRuby (`conversations_index` A03/A03b/R03, `comments_index`
  C08/C08b/C09/C10). Code-reading finding only: the corpus has no
  `*_profile_not_found`-style decision on the ACTOR chain and no
  `fetch_and_save` wall event. The `hs_err`/core files this run left in the app
  directory were removed.
- **Invalid `page` values.** `page=0` → `RangeError: invalid page: 0`;
  `page=abc` → `ArgumentError: invalid value for Integer(): "abc"` — both raised
  inside `WillPaginate::Collection.create` before any statement (A03). No shape
  can result.
- **A `Photo` target whose `status_message_guid` matches nothing.**
  `ActionView::Template::Error: … status_message is nil` (A02, last request) —
  a real 500 after the `photos` preload; no statement beyond W2's shape 1.
- **A `Notifications::PrivateMessage` row on html** — real 500 in the i18n
  interpolation (A05); json renders. See W3.
- **`Notification#update` / `read_all`** (the "mark all read" and per-notification
  read paths) are separate actions with their own routes; `#index` never writes.
  `set_read_state` / `update_all(unread: false)` are therefore out of this
  endpoint's scope, not gaps.
- **Site chrome under the real layout.** The batch pins
  `NotificationsController.layout(false)`, so `gon_set_current_user`'s
  `UserPresenter` (aspects, contact counts, unread counts) is never serialised —
  `Gon::ControllerHelpers#gon` is a declared wall. A standing scope decision of
  the batch, not a fixture/param axis; not attacked, flagged only (same
  treatment as both sibling reports).
- **Camo image proxying** (`AppConfig.privacy.camo.proxy_markdown_images?`,
  `Profile#image_url`'s camo branch): configuration, false by default — a
  config axis, not a fixture/param axis. A07's remote `image_url` actor took the
  plain branch.
- **`Notification#target` pointing at a deleted row is NOT protected by the
  schema** (`notifications.target_id`/`target_type` carry no FK, `target_id` and
  `target_type` are both nullable) — A04 exercised it and it produced no new
  shape (the preload simply returns fewer rows and `linked_object.nil?` selects
  `deleted_translation_key`). Likewise `notification_actors.person_id` has an FK
  only to `notifications`, so a dangling actor is reachable — also shape-neutral
  (A04).
- **`.js` / other formats:** `NotificationsController#index` declares only
  `format.html` / `format.xml` / `format.json` (plus `:mobile` via mobile-fu +
  `ApplicationController#mobile_switch`). All four are already corpus variants;
  `format_coverage_audit.py` enforces it. Nothing to attack there — and unlike
  both sibling endpoints, **the mobile-format class of win does not exist here**:
  this batch explores mobile.

## Harness notes

- Every request goes through a fresh `ActionController::TestCase` harness with
  the batch's own real-warden pattern; the Devise salt is computed once at
  fixture-load time, outside the capture window, so no `users` SELECT appears
  outside a target frame in any run.
- `adv_request` rescues per request (a 500 in one request must not hide the
  others); statuses and exceptions are printed into `runs/<TAG>.log`.
- Runs use `CONCRETE_COVERAGE` unset (no `--debug`), one scenario per JRuby
  process, `flock /tmp/concolic-slot.lock` inside
  `systemd-run --user -p MemoryMax=4000M -p MemorySwapMax=0`, with
  `JAVA_TOOL_OPTIONS` unset. Wall time 37-90 s per scenario.
- `_common.rb` resolves the target list statically instead of calling
  `targets_from_corpus` (which JSON-parses all 14 951 dumps, ~174 MB, per
  process). The list was derived by a grep for `"target": "…"` over every dump —
  20 distinct names, identical to what `targets_from_corpus` resolves — plus the
  batch's own `extra:` list and `FinderMethods#exists?`.
