# ADVERSARY REPORT — comments_index (CommentsController#index, GET /posts/:post_id/comments, anonymous AND signed-in)

Adversary run 2026-08-27 against the batch's `complete: true` claim
(25 PC nodes, 1 608 dumps, 15 corpus targets, anon + auth scenarios,
format `:json` only — `run_dse.rb` `CFG[:format] = :json`). Real app
only: `concrete_env.rb` sqlite, raw fixture rows, real Devise
`serialize_from_session` (the batch's own warden pattern), real
`ActionController::TestCase#process` (every before_action runs), real
templates. No mocks, no stubs, nothing under `src/`, the app, or the
batch's runner/targets/manifests touched. The batch's own
`concrete_run.json` was never overwritten (md5 `bcd03505…` before and
after). Manifests, per-scenario run JSONs, logs, bodies and judge
outputs: `adversary/` (`_common.rb` = shared harness, `C*.rb` = one
scenario per process, `run_scenario.sh`, `runs/C*.json|.log|.judge.txt`,
`runs/_last_body_*.txt`, `runs/C08b_sql_trail.txt`).

Judges: `mock_note_check.py` (real per-frame statements vs corpus notes,
aliases applied) and `note_fidelity_audit.py` (projection / predicate /
aggregate fidelity); the depth-0 `target_calls` of every run were compared
against the corpus's `symbolic_call` target set by hand.

## Verdict

**2 wins.** Both are reachable from the batch's OWN fixture state by
changing only comment text or the response format:

- **W1 — `Post.exists?(guid:)`** (`SELECT 1 AS one FROM "posts" WHERE
  "posts"."guid" = ? LIMIT ?`) from `Diaspora::MessageRenderer::Processor#diaspora_links`
  whenever a comment's text carries a `diaspora://<handle>/post/<guid>`
  link — on the JSON path (`plain_text_for_json`) AND the mobile path
  (`markdownified`), anonymous and signed-in. The corpus has no `exists?`
  target, no note with a `1 AS one` projection, no PC on "text contains a
  diaspora link". Both judges RED in C01, C02, C03.
- **W2 — the `:mobile` format family** (declared: `respond_to :html,
  :mobile, :json`; reachable by `session[:mobile_view]`, by the
  `X_MOBILE_DEVICE` header, or explicitly) is never explored. Its
  materialization is a depth-0 `ActiveRecord::Relation#to_a`
  (ActionView collection rendering) — a target the batch declares but the
  corpus has zero events for — and every conditional in
  `index.mobile.haml` / `_comment.mobile.haml` / `PeopleHelper` /
  `MessageRenderer#markdownified` (`render_mentions`, `render_tags`,
  `person_link_class` self/hovercardable, `profile.nil?` guards, the
  delete-link `comment.author == current_user.person`) is invisible to
  DSE. Class B by construction; its statement multiset is the JSON one
  plus W1's `exists?`.

`complete: true` is void until (a) the diaspora-link decision and the
`exists?` shape are in the corpus and (b) a mobile variant is explored,
AND the concrete note check runs over every declared format.

Everything else on the attack list (guid vs id keys, private / shared /
hidden-visibility / own / public / missing posts, NonPublic → 401,
templateless html, Reshare with and without root, 0/1/12 comments,
closed-account and remote authors, mentions of local / remote / closed /
nonexistent people, a mentions row pointing at a missing person, likes on
comments, a blocked author, inflected locale, odd `post_id` shapes)
produced only shapes the corpus already carries — see near-misses for the
bind-level and return-kind defects those runs exposed.

## Scenarios

| # | manifest | fixtures / request | status | mock_note_check | note_fidelity | result |
|---|----------|--------------------|--------|-----------------|---------------|--------|
| C01 | `C01_anon_links.rb` | batch post 100 + comment 302 with `diaspora://…/post/<existing guid>` x2, `web+diaspora://…/post/<missing guid>`, `diaspora://…/comment/<guid>`; comment 303 with `#tag`, markdown, URL, `<3`, mention markup of a ghost and of alice (no mentions rows); anon json | 200 | **RED** NOTE-MISSING `exists?` | **RED** STAR-OVER | **WIN W1** |
| C02 | `C02_anon_mobile.rb` | C01 fixtures; html + `session[:mobile_view]=true`; html + `X_MOBILE_DEVICE`/iPhone UA; explicit `format: :mobile` | 200 x3 | RED (W1) | RED (W1) | **WIN W2** (+W1 via `markdownified`) |
| C03 | `C03_auth_mobile.rb` | alice signed in; post 101 (bob, private, share_visibilities `hidden: 1`) with a comment mentioning alice + diaspora link, alice's own comment mentioning bob + `#tag`, a closed-account author; post 102 alice's own private post; mobile via session, explicit mobile, json | 200 x3 | RED (W1) | RED (W1) | W1 + W2 signed-in; `self` / delete-link branches rendered |
| C04 | `C04_controls.rb` | anon: html; private post 106 by id and by guid; missing id; guid hit; guid miss; `""`; `"abc"`; 16-digit numeric string; array `["100","101"]` | MissingTemplate; 401 (`throw :warden`) x2; 404 x5; 200 x2 | green | green | no new shape (near-miss N1 array key) |
| C05 | `C05_sti.rb` | public Reshare 110 with a MISSING root, Reshare 111 with a root; comments on both (one mention); anon json, anon mobile, auth json | 200, 200, 200, **404** | green | green | no new shape; auth 404 is the JDBC boolean artefact (below) |
| C06 | `C06_cardinality.rb` | posts with 0 / 1 / 12+2 comments; one comment with three mentions (local, remote, closed); one with mention markup and no rows; post 123 with a mentions row whose `person_id` = 999 (no such person); a like on a comment | 200 x6, mobile 123 → `ActionView::Template::Error` (nil.diaspora_handle) | green | green | no new shape; blind nil-person branch (N3) |
| C07 | `C07_auth_edges.rb` | alice `language: "pl"`; `blocks` row alice→bob; likes; own public post 103 by id and guid; bob's public post 100 by id and guid; hidden-visibility post 104; missing id; guid miss; html; mobile | 404 x2 (public-branch JDBC artefact), 200 x5, 404 x2 | green | green | no new shape; pre-action profile read (N4) |
| C08 | `C08_noprofile_author.rb` | comment author dave has NO `profiles` row; anon json | JVM SIGSEGV exit 134 | — | — | blocked (see Unreachable) |
| C08b | `C08b_noprofile_author_interp.rb` | same, `JRUBY_OPTS=-X-C` + manifest-local incremental SQL trail | SIGSEGV in `__libc_free` under an FFI call, exit 134; trail shows the full preload chain then nothing from `fix_profile` | — | — | blocked; trail in `runs/C08b_sql_trail.txt` |
| C09 | `C09_noprofile_mention.rb` | mentions row → dave (no profile); anon json | SIGSEGV exit 134 | — | — | blocked |
| C10 | `C10_noprofile_mobile.rb` | dave (no profile) as author; mobile | SIGSEGV exit 134 | — | — | blocked |

12 process runs (C04 twice: the first aborted at fixture load on
`posts.public NOT NULL`), 8 with judged output, 37 requests.

## WINS (blocking)

### W1 — `Post.exists?(guid:)` from `diaspora_links` (json, mobile; anon and signed-in)
- Scenario: C01 (anon json). Batch fixtures unchanged except one extra
  comment whose text is
  `see diaspora://bob@remote.example/post/postguid100000001 and diaspora://alice@localhost/post/alicepostguid0105 and web+diaspora://bob@remote.example/post/nosuchguid0000000 and diaspora://bob@remote.example/comment/cguid300 ok`.
  Reproduced in C02 (mobile x3) and C03 (signed-in, mobile and json).
- Novel shape (verbatim, frame `ActiveRecord::FinderMethods#exists?`, depth 0, once per `post` link — 3 in C01, 2 per mobile render in C02):
  `SELECT  1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?`
- Issuing code: `lib/diaspora/message_renderer.rb:118-123`
  ```ruby
  def diaspora_links
    @message = @message.gsub(DiasporaFederation::Federation::DiasporaUrlParser::DIASPORA_URL_REGEX) {|match_str|
      guid = Regexp.last_match(3)
      Regexp.last_match(2) == "post" && Post.exists?(guid: guid) ? AppConfig.url_to("/posts/#{guid}") : match_str
  ```
  reached from `plain_text_for_json` (`message_renderer.rb:189`, via
  `CommentPresenter#as_json` `text: @comment.message.plain_text_for_json`)
  and from `markdownified` (`message_renderer.rb:210`, via
  `_comment.mobile.haml:22`). The rewrite is visible in the body
  (`runs/_last_body_json_100.txt`: both existing guids became
  `https://diaspora.internal/posts/<guid>`; the missing one and the
  `comment` link stayed verbatim — the `exists?` result decides output).
- Judges: `mock_note_check` NOTE-MISSING RED ("issues real SQL, zero
  SQL-shaped corpus notes"); `note_fidelity_audit` STAR-OVER (nearest
  note is the anon post finder `SELECT "posts".* … WHERE "posts"."id" = $$(SYM_PARAM_post_id)`).
- Class: **B + S.** B: the comment's `text` is a pinned concrete String in
  the corpus (`text_has_mention` is the only text decision; AGENT_RUN.md
  §B says "`text` is already a concrete String (the §4a has_mention pin),
  so the real pipe runs with no wall" — it runs, but the
  `DIASPORA_URL_REGEX` match never fires on the pinned text, so the
  `exists?` call and the `"post"` / `exists?` decisions are invisible).
  S: `FinderMethods#exists?` is not a declared target on this batch
  (TARGET_FUNCTIONS §1 lists it as a policy-bearing existence target); had
  the branch been reached, no note would have been minted. Note the
  predicate column: `posts.guid` bound to a value parsed out of
  `comments.text` — a bind the fold has no producer for (a data-flow the
  policy must express as "any guid literal in a comment text").

### W2 — the `:mobile` format is never explored (depth-0 `Relation#to_a`; every mobile-partial branch blind)
- Scenario: C02 — batch fixtures, format switched by (a)
  `session[:mobile_view]=true` + html (`ApplicationController#mobile_switch`,
  `application_controller.rb:158-162`), (b) `X_MOBILE_DEVICE` header +
  html (mobile-fu `set_mobile_format`), (c) `format: :mobile`. All three
  render `comments/index.mobile.haml` (`render layout: false, locals:`),
  200, identical 3 802-byte bodies. C03 = signed-in variants.
- Novel depth-0 target call: `ActiveRecord::Relation#to_a` (3 at depth 0
  in C02, 2 in C03, 1 in C05/C07) — `render partial: "comments/comment",
  collection: comments` (`index.mobile.haml:3`) materializes the relation
  through `to_a` (ActionView `PartialRenderer#collection_from_object`),
  where the json path goes through `Relation#records` (`Array#map` via
  `BasePresenter.as_collection`). The batch declares `to_a` as a target
  (`targets.rb` rows_mock on `%i[to_a to_ary records]`) but the corpus has
  **0** `Relation.to_a` events; `targets_from_corpus` therefore does not
  even trace it — it appeared only because this harness adds it
  explicitly. Statement shape is the same `comments` SELECT (judge-neutral).
- What the corpus cannot see on this path (all data-dependent, no PC, no
  pin-ledger entry): `person_image_link` `person.nil? || person.profile.nil?`
  (`people_helper.rb:43`), `person_link_class`'s `current_user.person == person`
  (`people_helper.rb:80`), `_comment.mobile.haml:17`
  `user_signed_in? && comment.author == current_user.person` (rendered
  `class=' self'` + delete link in C03), `render_mentions`'
  `options[:mentioned_people].empty?` / `link_all_mentions`
  (`message_renderer.rb:64-71`), `Mentionable.format`'s
  `people.find {|p| p.diaspora_handle == diaspora_id }` (`mentionable.rb:35`;
  the 500 in C06 is its nil branch), `MentionsInternal.mention_link`'s
  `person.present?` / `display_name || person.name`, `format_tags`'s
  `&lt;3` special case, `direction_for(comment.text)`, `timeago(created_at ? … : Time.now)`.
- Class: **B** (a whole declared response format unexplored; same root
  cause the conversations_index adversary found), with W1 as its
  statement-level consequence on the `markdownified` pipe.

Repair direction (for the batch agent, not done here): a text decision
family for `DIASPORA_URL_REGEX` matches (`post` vs other entity, existing
vs missing guid) with `FinderMethods#exists?` declared as a target whose
note is the real `SELECT 1 AS one … WHERE posts.guid = $$(<text-derived guid>)`
shape; a mobile variant in `run_dse.rb`'s scenario set (session flag or
explicit format) so `to_a` and the partial's conditionals enter the PC
universe; the concrete note check run over html/mobile/json.

## Near-misses (matched only via alias / nested frame / wildcard, or defects the runs re-exposed)

- **N1 — array `post_id` yields an IN-list post finder.** C04
  `post_id=["100","101"]`: `post_key` sees `'["100", "101"]'.length = 14`
  → `:id`, and `Post.where(id: [...])` issues
  `SELECT  "posts".* FROM "posts" WHERE "posts"."id" IN (?, ?) ORDER BY "posts"."id" ASC LIMIT ?`
  (200, comments of post 100 returned). The corpus's `SYM_PARAM_post_id`
  is a string; no note carries an IN-list predicate on `posts.id`. Both
  judges normalize `IN (?, ?)` to the equality note (EXACT), so this is
  judge-invisible; shape-level it is a real statement the corpus lacks.
  Reported as a near-miss because the policy-relevant predicate column set
  is unchanged (it is a disjunction of the modelled equality).
- **N2 — preload notes are per-row `= $$(…)`; real preloads are bulk
  `IN (…)`.** Every run: `SELECT "people".* FROM "people" WHERE "people"."id" IN (?, ?, ?)`
  and `SELECT "profiles".* … WHERE "profiles"."person_id" IN (?, ?, ?)`
  (the `including_author` Preloader, one statement per association per
  page) vs the corpus's `Anonymous.load_intermediate` notes
  `… WHERE "people"."id" = $$(SYM_RESULT_…records_1_row_author_id)` — one
  note per representative row. The judges wildcard the literal set and
  call it EXACT; the batch's own runs show the same. Column/predicate
  faithful, cardinality unfaithful; the mock returns a `symint row_count`
  (an aggregate kind) for what is really a row list — a **return-kind
  mismatch** (step 5), harmless here only because nothing reads the
  return.
- **N3 — a mentions row whose `person_id` has no `people` row is blind.**
  C06 post 123: the preload finds nothing, `mentions.map(&:person)` yields
  `[nil]`; JSON renders `"mentioned_people":[null]` (200); mobile 500s in
  `Mentionable.format` (`undefined method diaspora_handle for nil`). The
  corpus's `records_3_row_person_persisted` decision exists but no
  `person`-nil / not_found decision does (`mentions.person_id` carries no
  FK in `schema.rb`, so the state is reachable). No statement consequence
  (the preload shapes are identical); D2 finding only.
- **N4 — inflected locale reads the principal's profile BEFORE the
  action.** C07 alice `language: "pl"`: `set_grammatical_gender` →
  `current_user.gender` → `Person#profile` delegate →
  `SELECT  "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ? LIMIT ?`
  under `SingularAssociation#find_target`, bound to the principal's
  person. The corpus's `find_target` profile notes are bound to comment
  authors / mentioned people (`records_*_row_*`), never to
  `devise_user_first_1_person_id`; the batch's auth corpus resolves
  `language` as a pin (`"en"`). Bind-level only; shape exists.
- **N5 — mention-lookup notes are over-emission with a literal pin.** All
  four `mention_lookup_{msg,json}_{first,retry}` targets (1 280 / 768 /
  1 280 / 640 events) render
  `SELECT "people".* FROM "people" WHERE "people"."diaspora_handle" = 'concolic_mention@example.org'`
  — a concrete literal, not a `$$()` bind — and NO real run ever issues a
  `diaspora_handle` lookup: `MentionsContainer#mentioned_people` takes the
  `persisted?` branch for every query-returned comment, and the mobile
  renderer's `render_mentions` never calls `people_from_string`
  (`link_all_mentions`/`disable_hovercards` are default-false). The
  unpersisted branch the corpus explores (`*_persisted == False`) is not a
  state of this endpoint. Not a win (no real shape lacks a note), but the
  policy inherits a handle-equality predicate with a fabricated literal
  from a branch the endpoint cannot take.
- **N6 — `Discovery#fetch_and_save` mock returns `nil`; the real method
  returns a `Person` or raises `DiscoveryError`.** `targets.rb:424-426`.
  The corpus's retry finder (`mention_lookup_*_retry`) fires after a nil
  return; for real, a failed discovery raises and `find_or_fetch_person_by_identifier`
  rescues to `nil` without the retry lookup, and a successful one makes
  the retry find the freshly saved row. Return-kind mismatch (step 5) on
  a branch the endpoint cannot reach (N5) — recorded, not a win.
- **N7 — auth `.first` frame attribution.** Every signed-in finder
  (`querent_has_visibility.first || querent_is_author.first || public_post.first`)
  and the anon `find_public!` finder issue their SELECT under
  `Relation#records` (nested in `first`); the corpus's notes live under
  `ci_*_first` / `first`. `mock_note_check` reports them as
  "matched under a DIFFERENT target — frame nesting" (NOTE-OK*), same as
  the batch's own run. Also the real statements carry
  `ORDER BY "posts"."id" ASC LIMIT ?` which the notes lack.
- **N8 — the public branch under signed-in returns 404 on this rig.** C05
  (public Reshare 111) and C07 (bob's public post 100, by id and by guid)
  all 404 for alice: the real `public_post.first` SELECT
  (`… WHERE "posts"."id" = ? AND "posts"."public" = ? …`) is issued and
  finds nothing under the JDBC sqlite boolean bind — the artefact
  AGENT_RUN.md §F already documents (the batch made post 102 vis-visible to
  dodge it). Not the app; the note shape is in the corpus. It does mean
  the signed-in public-branch SUCCESS path (comments of a public post the
  user neither shares nor owns) has never been concretely checked on this
  rig — only its miss.
- **N9 — `Relation#to_a` vs `records`** — see W2; listed here because the
  statement is identical.

## Unreachable / blocked branches and why

- **`Person#name` with a missing profile → `fix_profile` → `DiasporaFederation::Discovery::Discovery#fetch_and_save` → `reload`** (C08, C08b, C09, C10).
  `person.rb:247-252` / `371-375`: a comment author (`CommentPresenter#as_json`
  `author.as_api_response(:backbone)` → `t.add :name`; mobile `person_link`)
  or a mentioned person (`mentioned_people.as_api_response`) with no
  `profiles` row runs federation discovery (network) and then
  `SELECT "people".* … WHERE id = ?` (`reload`). The corpus has the
  `fetch_and_save` wall only on the mention-retry branch and no
  `profile`-nil decision (`find_target` never returns nil; the preload's
  representative always has a profile). Every attempt aborted the JVM
  natively — SIGSEGV in `__libc_free` under a jffi/FFI invocation, with and
  without JIT (`-X-C`) — the same crash class the probe header and the
  conversations_index adversary report. `runs/C08b_sql_trail.txt` proves
  the run reached the presenter (full comments/people/profiles/mentions
  chain issued, 13 statements) and died inside the discovery call before
  any `fix_profile` SQL. Code-reading finding, not a judged win. Schema:
  `profiles.person_id` has no FK, so the state is reachable.
- **`post.public?` on a NULL `public` column:** `posts.public` is
  `NOT NULL` (`schema.rb`; the first C04 attempt aborted on the INSERT) —
  unreachable by schema.
- **Comment whose author row is missing** (`comment.author` nil →
  `NoMethodError` in the presenter): `comments.author_id` has an FK to
  `people` with cascade in `schema.rb` — not a database state.
- **`html` format:** declared, templateless — `respond_with` falls to
  `default_render` → `ActionView::MissingTemplate` (C04, C07). A real
  500 after the post finder (anon) / after Devise resolution + the
  visibility chain (signed-in); no comments load, no new shape.
- **Anonymous private post:** `Diaspora::NonPublic` → `rescue_from` →
  `authenticate_user!` → `warden.authenticate!` → `throw :warden` (C04:
  by id and by guid). No data access after the finder; the corpus models
  the raise as `first_1_public == False`. The runner stubs
  `authenticate_user!` to a symbol — a wall, not a data decision; fine.
- **Likes on comments, blocked/ignored authors, `closed_account`,
  `comments_count`, the Reshare root:** nothing on this action reads
  them (C05, C06, C07 show no statement change) — the attack list's
  expectations for those axes are unreachable by code, not by rig.
- **`camo_urls` (`AppConfig.privacy.camo.proxy_markdown_images?`) and
  `Profile#image_url`'s camo branch:** configuration, not fixture/param —
  not attacked (defaults false).
- **`link_all_mentions` / `disable_hovercards` branches of
  `render_mentions` → `Mentionable.filter_people` → `people_from_string`
  → a REAL `diaspora_handle` lookup + discovery:** only reachable through
  renderer options no caller on this endpoint passes — unreachable by
  code.

## Harness notes
- Signed-in requests share one resolved `User` per manifest process
  (the `@concrete_user ||=` memo in the warden lambda, as in the batch's
  manifest), so the `users` lookup and `user.person` `owner_id` read
  appear once per process, not once per request. Multiplicity only.
- Runs use `CONCRETE_COVERAGE=0` (no `--debug`); C08b additionally
  `JRUBY_OPTS=-X-C`. The four JVM crash dumps my runs left in the app
  directory (`hs_err_pid358*.log`, `core.358*`) were removed; older ones
  from other sessions were left in place.
- `mock_note_check.py` attributes the diaspora-link `exists?` to the
  `FinderMethods#exists?` frame only because this harness traces it
  explicitly; `targets_from_corpus` alone would not (the corpus has no
  such target). Without the extra trace the statement would surface as
  "OUTSIDE any target frame" — still RED — so the note check catches W1
  either way once a scenario with a diaspora link exists; what was missing
  was the scenario (the batch's fixture texts never match
  `DIASPORA_URL_REGEX`), i.e. a per-path check needs the adversarial
  fixture, not a better judge.
