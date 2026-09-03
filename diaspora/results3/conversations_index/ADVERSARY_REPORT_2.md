# ADVERSARY REPORT — ROUND 2 — conversations_index (ConversationsController#index, signed-in only)

Adversary round 2, run 2026-08-27 00:58–01:10 against the cycle-3 corpus
(`coverage_summary.json`: 61 PC nodes, 13 569 dumps over six variants
html/json/mobile x plain/withcid, `complete: true`). Real app only:
`concrete_env.rb` sqlite, raw fixture rows, real Devise
`serialize_from_session` (salt primed OUTSIDE the capture window — the
round-1 harness artefact is gone), real `ActionController::TestCase#process`,
real templates, `layout(false)` parity with the batch. No mocks, no stubs,
nothing under `src/`, the app, or the batch's runner/targets/mocks touched.
The batch's own `concrete_run.json` was never overwritten (md5
`4292f4d6…` before and after; the probe writes next to the manifest, i.e.
into `adversary2/`, and each run was moved to `adversary2/runs/<name>.json`).

Files: `adversary2/_common.rb` (shared harness, copy of round 1's plus
`ActiveRecord::FinderMethods#exists?` traced as a frame), `adversary2/R*.rb`
(round-1 re-runs), `adversary2/N*.rb` (new scenarios), `adversary2/runs/`
(`<name>.json|.log|.judge.txt|.sqlite3`, `_last_body_<tag>.html`,
`_rejudge_round1_*.txt` = round-1 run JSONs re-judged against the NEW
corpus), `adversary2/run_scenario.sh`, `adversary2/_depth0_check.py`
(depth-0 target list vs corpus targets; `concrete_checker.py` no longer
exists in `src/`), `adversary2/_summarize.sh`.

Judges: `mock/mock_note_check.py` (per-frame statement shape vs corpus notes,
aliases applied), `tools/note_fidelity_audit.py` (projection / predicate /
aggregate fidelity), `_depth0_check.py` (depth-0 target-call names vs the
corpus's `symbolic_call` targets).

**Instrument note (applies to every judge line below).** Round 2 traces
`ActiveRecord::FinderMethods#exists?` as its own frame. `Relation#empty?`
delegates to `exists?` (relation.rb `empty?` -> `!exists?`), so the
`current_user.contacts.mutual.empty?` probe
(`SELECT 1 AS one FROM "contacts" WHERE user_id = ? AND sharing = ? AND receiving = ? LIMIT ?`)
is now attributed to the nested `exists?` frame, and `mock_note_check`
prints `NOTE-MISSING ActiveRecord::FinderMethods.exists?` for it in every
run. That statement IS the corpus's `Relation.empty?` note byte-for-byte
(the fidelity audit rates it EXACT under the `empty?` alias); the RED line
is an artefact of my extra frame, not a finding. The ONLY `exists?`
statement that has no note anywhere is the `posts` one (W1).

## Verdict

**1 win (new), 0 of round 1's findings still open.**

All three round-1 wins (mobile `messages.pluck(:author_id)`, mobile
`COUNT(*) FROM messages`, `conversation.author` chain) and every round-1
near-miss that a judge can see (N1 `empty?` existence projection, N2
DISTINCT-subquery COUNT, N3 INNER-JOIN finder attribution + ORDER/LIMIT,
N4 `set_read` save SELECT/UPDATE, N7 inflected-locale profile read) are
clean against the new corpus — re-run for real (R01–R10) AND the round-1
run JSONs re-judged (`runs/_rejudge_round1_*`): 0 MISSING / STAR-OVER /
AGG-COLLAPSE / PROJ-DIFF / PRED-DIFF across 9 round-1 runs and 14 round-2
runs, except W1 below.

The new win is a whole branch family the corpus structurally cannot
reach: message text is a PINNED concrete string in the corpus
(`targets.rb` `symbolic_instance`: `"hello world, a concolic message with
no mentions"` / one mention string; pin ledger: "Message `text` … never a
query argument on this endpoint"). That pin is false: `Diaspora::
MessageRenderer#diaspora_links` parses `diaspora://<id>/post/<guid>` out of
the text and issues `Post.exists?(guid: guid)` — a query whose predicate
value comes from the text. `complete: true` is void until that shape is in
the corpus and the check that catches the class (a text-derived query
argument foreclosed by a pin) exists.

## 1. Round-1 re-verification

| round-1 finding | round-2 scenario | verdict | evidence |
|---|---|---|---|
| W1 mobile `messages.pluck(:author_id)` on an unloaded association (`SELECT "messages"."author_id" … ORDER BY created_at ASC`) | R01 (session switch), R02 (device header / `format: :mobile`) | **clean** | `mock_note_check` NOTE-OK pluck (2 shapes); fidelity EXACT — corpus note `SELECT "messages"."author_id" FROM "messages" WHERE conversation_id = $B ORDER BY created_at ASC` (3 458 events, mobile variants) |
| W2 mobile `messages.size` -> `SELECT COUNT(*) FROM "messages" WHERE conversation_id = ?` | R01, R02, R04/R05/R08/R09/R10 mobile requests | **clean** | count NOTE-OK (3 shapes: visibilities DISTINCT-subquery, participants join, messages); fidelity EXACT; corpus note present (5 360 events). The two `messages.size` calls per row and will_paginate's re-COUNT are multiplicity only |
| W3 `conversation.author` chain (`people.id = conversations.author_id`, then `profiles.person_id`) | R01, R02, N04 (author = profile-less principal) | **clean** | find_target NOTE-OK, EXACT; corpus PCs `…_row_conversation_author_persisted`, `…_conversation_author_profile_not_found` (2 680 each) prove the chain is bound to the conversation rep |
| N1 `contacts.mutual.empty?` STAR-OVER | every run | **clean** | corpus note is now `SELECT 1 AS one FROM "contacts" … LIMIT 1` (10 846 events); fidelity EXACT (see instrument note) |
| N2 visibilities COUNT PRED-DIFF (DISTINCT subquery) | every run; R06/N05 re-COUNT on full/empty pages | **clean** | corpus note is will_paginate's `SELECT COUNT(*) FROM (SELECT DISTINCT "conversation_visibilities"."id" … LEFT OUTER JOIN …) subquery_for_count` (27 090 events); EXACT |
| N3 INNER-JOIN finder matched only by nesting; no ORDER/LIMIT | R10, N03, every withcid request | **clean** | `concrete_aliases.json` maps `Relation.records` -> the finder targets; corpus `first` note carries `ORDER BY "conversations"."id" ASC LIMIT 1`; fidelity EXACT (was PRED-DIFF in round 1) |
| N4 `set_read` -> `save` validation SELECT + UPDATE | every withcid request | **clean** | corpus `save` note `UPDATE "conversation_visibilities" SET "unread" = ?, "updated_at" = ? WHERE id = $B` (8 266); the `people.id = ?` validation SELECT is a `load_intermediate` note (11 202); the UPDATE is a write the SELECT-only judges do not examine — matched by reading |
| N5 `person.profile.nil?` blind guard | R04 (carol no profile), N04 (principal no profile, author image + owner_image_tag) | **clean (modelled)** | corpus PCs `*_profile_not_found == True` on every has_one load (8 414 / 8 068 / 5 217 / 2 680 / 2 570 / 2 477 …); no shape change, 200s |
| N6 pagination pin | R06 (16 convs: page nil/2/3, json 2, mobile 3), N05 (15 convs: page nil/1/2, mobile 2, json 2) | **clean at shape level; pin re-flagged** | only `OFFSET ?` (wildcarded) and COUNT multiplicity change; but see near-miss NM-2: page 2 of 15 is a real `count > 0 ∧ rows = []` state the cardinality link excludes |
| N7 inflected locale profile read | R09 (pl: json, html, mobile) | **clean** | `profiles.person_id = ? LIMIT ?` under find_target, EXACT; bind-level as before |
| N8 `Conversation#subject` blank branch | N04 (subject `"   "`, NULL, `""`), R08 (NULL) | **clean (modelled, with the documented pin)** | corpus PC `…_subject == ''` (25 990 + 16 828 + 24); whitespace-only (`blank?` true, `== ''` false) is the batch's written pin; no shape consequence |
| A03 no-profile LAST AUTHOR -> `Person#name` -> `fix_profile` -> Discovery (JVM abort) | R03 (Coverage OFF, `Discovery#fetch_and_save`, `Person#fix_profile`, `Persistence#reload` traced) | **still not runnable** | JVM `SIGSEGV` in `MixedModeIRMethod.call`, exit 134, no `concrete_run.json` (round 1: `free(): invalid pointer`, exit 134). The batch models it (Discovery.new / fetch_and_save walls + reload note + profile-pinned-found; `Anonymous.new` 2 936 corpus events). Not judged, not a win; see "unreachable" |
| harness artefact (users SELECT outside any frame) | R01/R02 | **gone** | 0 statements outside any frame in every round-2 run |

## 2. Scenarios (round 2)

| # | manifest | fixtures / request | status | mock_note_check | note_fidelity | depth-0 targets | result |
|---|---|---|---|---|---|---|---|
| N01 | `N01_diaspora_post_links.rb` | posts row 500 (guid `postguid0123456789abcdef`, StatusMessage); conv 1 (bob, carol, alice unread 1): msg 31 by bob links the EXISTING post, msg 32 by carol (last) links a MISSING post guid + a `comment`-type link + a `web+diaspora://` post link; conv 2: bob's message links `bob@remote.example:3000/post/…`. html plain, html cid=1, html cid=2, mobile plain, mobile cid=1, json cid=1 | 200 x6 | **RED** NOTE-MISSING `FinderMethods.exists?` `posts` | **RED** MISSING x1 | `ActiveRecord::FinderMethods.exists?` top x13 **ABSENT FROM CORPUS** | **WIN W1** |
| N02 | `N02_many_messages_unread.rb` | conv 1: 4 msgs (bob, alice, carol, carol), unread 2; conv 2: 3 msgs, unread 3 (= size); conv 3: 2 msgs, unread 4 (> size); conv 4: 5 msgs by 3 authors. html plain, cid 1/2/3/4, json cid=2, mobile cid=1, mobile plain | 200 x8 | green (instrument artefact only) | EXACT | present | no new shape; near-miss NM-1 (first_unread = msg 33 / msg 41, indexes -2 / -3) |
| N03 | `N03_malformed_params.rb` | batch fixtures; `conversation_id[foo]=bar`, page `0`/`abc`/`-1`/`["2"]`, cid `1 OR 1=1`, cid `1.5`, json + `session[:mobile_view]`, explicit `format: :mobile` no cid, `Accept: application/json`, iPhone header + `mobile_view=false`, iPad UA | 200 x8; page 0/-1 `RangeError: invalid page`, `abc` `ArgumentError`, array `TypeError` (all raised inside `paginate`, before any statement) | green (artefact only) | EXACT | present | no new shape: hash / SQL-ish / fractional cid all render the corpus finder shape `conversation_id = ?`; json stays json under the mobile flag; tablet and `mobile_view=false` stay html |
| N04 | `N04_edge2_noprofile_principal.rb` | alice has NO profile and AUTHORS conv 2/3/4 (never a message author); bob closed + pods row 77 (`pod_id`), carol on the pod; dave with remote `image_url`/`image_url_small`; conv 1: 4 participants, last author carol; subjects `"   "`, NULL, `""`. html plain, html cid=1, html cid=3, mobile plain, mobile cid=1, json plain | 200 x6 | green (artefact only) | EXACT | present | no new shape (mobile `participants.size > 2` badge, `person_image_tag(conversation.author)` guard `""`, `owner_image_tag` guard, `person_link_class` self compare all took their other side) |
| N05 | `N05_pagination_15_boundary.rb` | exactly 15 conversations (`per_page`), distinct `updated_at`; html page nil, page `1`, page `2`, page `2` + cid 115, mobile page `2`, json page `2` | 200 x6 (page 2 bodies: html 953 B with NO `.no-conversations` and NO conversation element; json `[]`) | green (artefact only) | EXACT | present | no new shape; near-miss NM-2 |
| R01–R10 | see §1 | round-1 scenarios re-run (+ a mobile request added to R04/R05/R06/R07/R08/R09/R10) | 200 everywhere except R07 `.js` (real 500, `undefined local variable no_contacts`) and R03 (JVM abort) | green (artefact only) | EXACT | present | clean |

15 process runs (14 judged, R03 aborted), 74 requests.

## 3. WINS (blocking)

### W1 — `Post.exists?(guid:)` from message text (`diaspora_links`), foreclosed by the `text` pin
- **Scenario:** N01. Any message whose text contains a
  `diaspora://<diaspora-id>/post/<guid>` (or `web+diaspora://…`) link,
  rendered by the HTML format: the sidebar (`_conversation.haml:38`
  `conversation.messages.last.message.plain_text_without_markdown`) and,
  with `conversation_id`, every message of the selected conversation
  (`_message.html.haml:10` `message.message.markdownified`). Mobile never
  renders message text on this action (index.mobile.haml has no show
  partial) and json serializes conversations only — 0 calls there; html
  plain 3, html cid=1 6, html cid=2 4 = 13 depth-0 calls.
- **Novel shape (verbatim, frame `ActiveRecord::FinderMethods#exists?`, depth 0, args `{:guid=>"postguid0123456789abcdef"}` / `"missingguid0123456789xyz"` / `"anotherguid0123456789ab"`):**
  `SELECT  1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?`
- **Issuing code:** `lib/diaspora/message_renderer.rb:100-105`
  ```ruby
  def diaspora_links
    @message = @message.gsub(DiasporaFederation::Federation::DiasporaUrlParser::DIASPORA_URL_REGEX) {|match_str|
      guid = Regexp.last_match(3)
      Regexp.last_match(2) == "post" && Post.exists?(guid: guid) ? AppConfig.url_to("/posts/#{guid}") : match_str
    }
  end
  ```
  reached from `plain_text_without_markdown` (line 176-183) and
  `markdownified` (209-220); `Post.exists?` -> `ActiveRecord::FinderMethods#exists?`
  (finder_methods.rb:305). The `comment`-type link in msg 32 issued nothing
  (13 = exactly the post-type links), i.e. the `== "post"` compare is a real
  branch too.
- **Judges:** `mock_note_check` NOTE-MISSING (RED: "issues real SQL, zero
  SQL-shaped corpus notes"); `note_fidelity_audit` MISSING (RED);
  `_depth0_check` `ActiveRecord::FinderMethods.exists?` ABSENT FROM CORPUS
  (the corpus has no `exists?` events at all; its only existence probe is
  `Relation.empty?` over contacts). No corpus note mentions `posts`.
- **Class: B with an S consequence.** Class B: `targets.rb`
  `symbolic_instance` pins `text` to one of two concrete strings (a
  `_text_has_mention` boolean is the only decision), so
  `DIASPORA_URL_REGEX` can never match in any corpus run — the whole
  `diaspora_links` family (the regex match, `type == "post"`, the
  `exists?` true/false sides, `AppConfig.url_to` rewrite) is invisible,
  exactly violation #2's pattern (a pin foreclosing a branch family). The
  pin ledger's neutrality argument ("never a query argument on this
  endpoint") is refuted: the guid parsed from the text IS the query
  argument. Class S consequence: a real `posts` existence probe with no
  note; the extracted policy can never contain a `posts.guid` read for
  this endpoint.
- **Repair direction (batch agent, not done here):** the text pin must
  carry a seeded decision for the link family (e.g. a
  `_text_has_post_link` boolean with a concrete `diaspora://…/post/<guid>`
  string, mirroring `_text_has_mention`), and `exists?` must be answered by
  the existence-probe mock with the note `SELECT 1 AS one FROM "posts"
  WHERE "posts"."guid" = $$(…) LIMIT 1` bound to a symbolic guid derived
  from the text; the check that catches the class is a scan of every
  pinned string column for regex-driven query sites (`gsub`/`scan`/`=~`
  feeding a finder) in the code reachable from the endpoint.

## 4. Near-misses

- **NM-1 — `first_unread_message` index beyond the sampled list (N02).**
  `conversation.rb:34` `self.messages.to_a[-visibility.unread]` with
  unread 2 / 3 selects message 33 / 41 (`first_unread` ids in
  `runs/_last_body_html_cid1.html` / `_cid2.html`), a distinct NON-last row.
  The corpus's `SampledList#[]` (targets.rb) honours only indexes 0 and -1
  and RAISES `NotImplementedError` otherwise, and its only PC on the index
  is `((- unread) == 0)` (7 941) — the `raw == -1` test is a concrete
  compare, so there is no PC separating unread 1 from unread >= 2; the
  corpus reports `dump_errors {}`, which means the solver never proposed
  unread >= 2 (the assumption gate closes `unread > 0` on one side). Real
  statement shapes are identical (the messages relation is loaded once), so
  no shape win — but D2 is violated (a data-dependent index with neither a
  PC nor a pin-ledger entry) and the model's domain (one representative
  row) silently excludes a real app state (unread 2 with 2+ messages is
  the normal "two new replies" state).
- **NM-2 — page beyond the end: `count > 0` with an EMPTY row list (N05, R06).**
  `targets.rb` `SampledList.linked_to_count` declares "count > 0 with an
  empty row list — a state no database produces" and forces the row list's
  length onto the count's variable. N05 page 2 of exactly 15 conversations
  (and R06 page 3 of 16) is that state for real: will_paginate's
  `count` strips `OFFSET`/`LIMIT` (active_record.rb:81-84), so
  `@visibilities.count > 0` is true, the collection render gets zero rows,
  and neither branch of `if @visibilities.count > 0 … else .no-conversations`
  renders anything (html body 953 B). The pin ledger pins `params[:page]`
  nil, so the argument is internally consistent — but the sentence in
  `targets.rb` is false as written, and the pin is what hides the state.
  No new statement shape (OFFSET is wildcarded; the extra `total_entries`
  COUNT is multiplicity). Flagged for the pin-ledger wording and as the
  branch DSE cannot reach.
- **NM-3 — `exists?` frame attribution.** `Relation#empty?`'s real
  statement is issued inside `FinderMethods#exists?`; the corpus records it
  only under `Relation.empty?`. Matched via the alias/nesting rule (the
  fidelity audit rates it EXACT); if the batch ever traces `exists?`
  directly, `concrete_aliases.json` needs `FinderMethods.exists?` ->
  `Relation.empty?/any?/none?` (the same alias family the batch already
  declares for `records`).
- **NM-4 — over-emission: `find_by … "people"."id" = nil LIMIT 1` (1 308 corpus events).**
  `Conversation#last_author` (conversation.rb:55-57) runs
  `Person.includes(:profile).find_by(id: @last_author_id)` with a nil id
  only when `messages.pluck(:author_id).last` is nil while
  `messages.size > 0` — the pluck's SampledList length is a separate
  `len(...)` seed from the messages count, so the corpus contains a state no
  database produces (count > 0 but the pluck empty). Warn-level per the
  brief (note with no real counterpart), reported because it is the same
  cardinality-link gap as NM-2 in the other direction.
- **NM-5 — `Regexp.last_match(2) == "post"` and the `DIASPORA_URL_REGEX`
  match itself** are string compares on text-derived data with no PC (D2)
  — the branch half of W1; listed separately so the repair records them.

## 5. Unreachable / blocked branches and why

- **No-profile LAST AUTHOR (`Person#name` -> `fix_profile` -> Discovery -> `reload`), R03:**
  third native JVM abort on this path (`SIGSEGV` in
  `MixedModeIRMethod.call`, exit 134; round 1: `free(): invalid pointer`
  twice), with Coverage off and the discovery/fix_profile/reload targets
  traced. The batch's model (Discovery.new + fetch_and_save walls, reload
  note, profile pinned found after reload) is a code-reading model that
  the probe cannot confirm on this JRuby; it stays a pin-ledger item, not a
  judged finding.
- **`.js` format:** declared, templateless; responders' `to_js` ->
  `default_render` -> `ActionView::Template::Error` (undefined
  `no_contacts`) — a real 500 after the html prefix's statements (R07).
- **Invalid `page` values** (`0`, negative, non-numeric, array): raised
  inside `paginate` (`WillPaginate::PageNumber`) before Devise's user
  lookup; no statement can result (N03).
- **Visibility whose conversation is missing / message or conversation
  whose author is missing:** NOT NULL + `ON DELETE CASCADE` foreign keys
  (schema.rb 626-633); no app state. `conversations.updated_at` is NOT NULL
  so `timeago(nil)` is unreachable.
- **Camo image proxying** (`Profile#image_url` `proxy_remote_pod_images?`,
  `markdownified` `proxy_markdown_images?`): configuration, false in
  `config/defaults.yml`; dave's remote `image_url` (N04) takes the plain
  branch. A configuration axis, not a fixture/param axis.
- **Mentions** (`@{…}`) never query on this endpoint: both renderers pass
  `mentioned_people: []` and neither sets `link_all_mentions`/
  `disable_hovercards`, so `Mentionable.format` finds nobody and
  `people_from_string`/`find_or_fetch_by_identifier` are never called
  (R08 re-confirms: mention text, 0 people lookups). `diaspora_links` is the
  only text-driven query — hence W1.
- **Site chrome (`layout(false)` pin):** the batch's standing scope
  decision; not attacked.

## Instrument notes
- `src/end_to_end_completion_checker/concrete_checker.py` no longer exists;
  `adversary2/_depth0_check.py` does the depth-0 target comparison
  (`#` -> `.` normalisation, aliases both ways).
- The Monitor tool's DONE-line watch timed out silently after
  R08 (600 s cap); the chain itself finished at 01:10:23 with every run
  judged on disk.
