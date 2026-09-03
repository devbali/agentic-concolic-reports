# ADVERSARY REPORT — conversations_index (ConversationsController#index, signed-in only)

Adversary run 2026-08-26 against the batch's `complete: true` claim
(42 PC nodes, 10 262 dumps, 40 distinct notes). Real app only:
`concrete_env.rb` sqlite, raw fixture rows, real Devise
`serialize_from_session`, real `ActionController::TestCase#process`,
real templates, `layout(false)` parity with the batch. No mocks, no
stubs, nothing under `src/`, the app, or the batch's runner/targets
touched. The batch's own `concrete_run.json` was never overwritten
(md5 `2e58609f…` before and after). Manifests, per-scenario run JSONs,
logs and judge outputs: `adversary/` (`_common.rb` = shared harness,
`A*.rb` = one scenario each, `runs/A*.json|.log|.judge.txt`,
`runs/_note_fidelity_audit.txt`).

Judges: `mock_note_check.py` (per-frame statement shape vs corpus notes,
aliases applied), `concrete_checker.py` (depth-0 target calls vs corpus
events), and the projection-level `note_fidelity_audit.py` added by the
coordinator during the run.

## Verdict

**3 wins, one root cause: the `:mobile` format is a declared response
format of this action (`respond_to :html, :mobile, :json, :js`) that the
corpus never explored.** The mobile templates take a different read
order through the same associations and issue two statement shapes the
corpus has no note for, plus one join chain the corpus never binds.
`complete: true` is void until the mobile variant is in the corpus.

Everything else on the attack list (0/1/many messages and participants,
unread 0/1/n and unread > messages, no-profile participants, closed/
remote/blocked/non-contact participants, non-participant author, mention
text, NULL/blank subject, 18 participants, pagination pages 1/2/beyond,
every `conversation_id` shape, zero conversations, inflected locale, js
format) produced only shapes the corpus already carries — see the
near-miss section for the bind/projection-level defects those runs
exposed in existing notes.

## Scenarios

| # | manifest | fixtures / request | status | mock_note_check | concrete_checker | result |
|---|----------|--------------------|--------|-----------------|------------------|--------|
| A01 | `A01_mobile_session.rb` | batch fixtures; html with `session[:mobile_view]=true` (ApplicationController#mobile_switch), plain + `conversation_id=1` | 200/200 | **RED** NOTE-MISMATCH pluck | all targets present | **WIN x3** |
| A02 | `A02_mobile_header.rb` | batch fixtures; html + `X_MOBILE_DEVICE`/iPhone UA header (mobile-fu `set_request_format`); explicit `format: :mobile` + cid=1 | 200/200 | **RED** (same) | present | reproduces A01 |
| A03 | `A03_noprofile_last_author.rb` | bob (last author of conv 1) has NO `profiles` row; html plain; extra depth-0 targets `Discovery#fetch_and_save`, `Person#fix_profile` | JVM abort `free(): invalid pointer`, exit 134 | — | — | blocked (see §Unreachable) |
| A03b | `A03b_noprofile_nocov.rb` | same, without `--debug`/Coverage | exit 134 again | — | — | crash is the path, not the instrumentation |
| A04 | `A04_noprofile_participant.rb` | carol (participant, never an author) has NO profile; html plain, html cid=1, json cid=1 | 200 x3 | green | present | no new shape; blind guard (near-miss N5) |
| A05 | `A05_solo_conversation.rb` | conv 3 alice-only/0 msgs, conv 4 alice-only/1 msg unread 2; html plain, cid=3, cid=4, json | 200 x4 | green | present | no new shape |
| A06 | `A06_pagination_16.rb` | 16 conversations; html page nil, page=2, page=3 (empty), json page=2 | 200 x4 | green (re-judged after a transient dump-glob race with the assumption checker) | present | no new shape (near-miss N6) |
| A07 | `A07_js_and_empty.rb` | zero conversations; html, json, **js** | 200, 200, js → `ActionView::Template::Error` (undefined `no_contacts`) | green | present | no new shape; `.js` is a real 500 |
| A08 | `A08_edge_control.rb` | bob closed_account; carol BLOCKED (blocks row); NULL subject; unread 5 > 2 msgs; 18 participants; message by non-participant dave (blank-name profile); mentions `@{Ghost Person; ghost@nowhere.example}`, `@{p7@…}`, `@{alice@localhost}`; conv 2 unread 3 / 0 msgs; html plain, cid=1, cid=2, json cid=1 | 200 x4 | green | present | no new shape |
| A09 | `A09_lang_pl.rb` | alice `language: "pl"` (inflected locale → `set_grammatical_gender` reads profile before the action); json plain, html plain | 200/200 | green | present | no new shape (bind-level only) |
| A10 | `A10_cid_variants.rb` | cid=5 (alice not a participant), 999, "abc", "", array | 200 x5 | green | present | no new shape |

12 process runs, 10 with judged output, 32 requests.

## WINS (blocking)

### W1 — `Conversation#last_author` pluck on an UNLOADED messages association (mobile)
- Scenario: A01 (also A02). Batch fixtures unchanged; the only change is
  the session flag `mobile_view=true` (or the mobile device header, or
  `format: :mobile`).
- Novel shape (verbatim, frame `ActiveRecord::Calculations#pluck`):
  `SELECT "messages"."author_id" FROM "messages" WHERE "messages"."conversation_id" = ? ORDER BY created_at ASC`
- Issuing code: `app/models/conversation.rb:56` `@last_author_id ||= messages.pluck(:author_id).last`,
  reached from `app/views/conversations/_conversation.mobile.haml:17`
  `conversation.last_author.present?`. In the HTML sidebar
  (`_conversation.haml:10`) `ordered_participants` loads `messages` first,
  so Rails 5.2's `pluck` on a loaded association answers from memory and no
  statement exists; the mobile partial never loads messages, so the pluck
  goes to the database.
- Judges: `mock_note_check` NOTE-MISMATCH (RED); `note_fidelity_audit`
  STAR-OVER (nearest note is the `messages.*` materialization).
- Class: **B** (a whole format family — `:mobile`, switched by session,
  device header or explicit format — never explored; every branch in
  `index.mobile.haml`, `_conversation.mobile.haml`, `_conversation_subject.haml`
  is invisible) with an **S** consequence (the corpus's `pluck` notes carry
  only the contacts projection; a `messages.author_id` projection exists
  nowhere).

### W2 — `messages.size` COUNT on an unloaded association (mobile)
- Scenario: A01 / A02, same fixtures.
- Novel shape (frame `ActiveRecord::Calculations#count`):
  `SELECT COUNT(*) FROM "messages" WHERE "messages"."conversation_id" = ?`
  (issued twice per conversation: once by the subject partial, once by
  `last_author`'s guard).
- Issuing code: `app/views/conversations/_conversation_subject.haml:3`
  `conversation.messages.size` and `app/models/conversation.rb:55`
  `messages.size > 0` — both before any messages load on the mobile path.
- Judges: `mock_note_check` matched it only "under a DIFFERENT target —
  frame nesting" because its normalizer collapses `COUNT(*)` to `*` and
  then finds the `messages.*` SELECT note; `note_fidelity_audit`
  AGG-COLLAPSE (RED). The corpus's two `count` notes are the
  visibilities LEFT-JOIN count and the participants count; there is no
  messages count.
- Class: **B** (same unexplored format) + **S** (a real aggregate with no
  note).

### W3 — `conversation.author` chain (`people.id = conversations.author_id`) (mobile)
- Scenario: A01 / A02.
- Shape (frame `SingularAssociation#find_target`):
  `SELECT "people".* FROM "people" WHERE "people"."id" = ? LIMIT ?` bound to
  `conversations.author_id`, followed by
  `SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ? LIMIT ?`.
- Issuing code: `_conversation.mobile.haml:6`
  `person_image_tag(conversation.author, size: :thumb_small)` (the HTML
  sidebar shows `other_participants.first`, never the author).
- Judges: shape-level judges pass (the corpus has `people.id = ?` notes
  bound to `messages.author_id`), so this is judge-invisible at shape level;
  it is a win under D1's bind rule — no corpus note chains through
  `conversations.author_id`, so the extracted policy can never contain
  the author join. Class: **B** (same root cause) with an S-in-bind-space
  consequence.

Repair direction (for the batch agent, not done here): add a mobile
variant (`session[:mobile_view]`, or `format: :mobile`) to `run_dse.rb`'s
scenario set; the `ConvoSymAssociations#messages` memoization must then
answer `size`/`pluck` BEFORE materialization with a COUNT note and a
projected pluck note respectively (Rails' `CollectionProxy#size` →
`count_records`, `pluck` on an unloaded relation → SQL), and the
`Conversation#author` belongs_to must mint a `people.id = <conv>_author_id`
note. The check that catches the class is the concrete note check run
over every declared format of the action, not only html/json.

## Near-misses (matched only via alias / nested frame / wildcard projection, or pre-existing defects the runs re-exposed)

- **N1 — `Relation.empty?` STAR-OVER.** Real
  `SELECT 1 AS one FROM "contacts" WHERE user_id = ? AND sharing = ? AND receiving = ? LIMIT ?`;
  note `SELECT "contacts".* FROM "contacts" WHERE …`. Issued at
  `conversations_controller.rb:29` `current_user.contacts.mutual.empty?`.
  Present in the batch's own run as well (its checker is shape-only).
  D1 projection defect (Class S, mis-shaped) but policy-neutral: an
  existence probe over the same predicate set. Near-miss, not a win.
- **N2 — visibilities COUNT PRED-DIFF.** Real
  `SELECT COUNT(*) FROM (SELECT DISTINCT "conversation_visibilities"."id" FROM … LEFT OUTER JOIN "conversations" … WHERE person_id = ?) subquery_for_count`;
  note `SELECT COUNT(*) FROM "conversation_visibilities" LEFT OUTER JOIN … WHERE person_id = ?`
  (R3 rebuilt the join but not will_paginate's DISTINCT-subquery form).
  Issued at `index.haml:16` / `index.mobile.haml:16` `@visibilities.count > 0`
  and again by `will_paginate`'s `total_entries` (A06: page 1 with a full
  page and page 3 beyond the end re-COUNT; page 1 with a short page does
  not). Same tables/predicates, different SQL form — Class S (shape),
  present in the batch's own run; near-miss.
- **N3 — `Conversation.joins(:conversation_visibilities)…first` frame attribution.**
  Real `SELECT "conversations".* … INNER JOIN "conversation_visibilities" … WHERE person_id = ? AND conversation_id = ? ORDER BY "conversations"."id" ASC LIMIT ?`
  is issued under `Relation#records` (nested in `first`); the corpus's note
  lives under `FinderMethods.first` (`convidx_conv_lookup`). Matched via
  frame nesting only (`conversations_controller.rb:13-17`). Also the
  real statement carries `ORDER BY conversations.id ASC LIMIT 1` the
  note lacks. Near-miss.
- **N4 — `set_read` → `visibility.save` validation SELECT.** Real, under
  `Base#save`: `SELECT "people".* FROM "people" WHERE "people"."id" = ? LIMIT ?`
  (the `belongs_to :person` required-presence validation, bound to the
  visibility's `person_id`), then `UPDATE "conversation_visibilities" SET "unread" = ?, "updated_at" = ? WHERE id = ?`
  (`conversation.rb:39-41`). The corpus's `save` note is
  `ConversationVisibility#save args={}` with no SQL; the people SELECT
  matched only because `find_target` has `people.id = ?` notes from the
  message-author chain (no corpus note binds `find_by_N_person_id`). The
  UPDATE is a write the SELECT-only judges do not examine. Class S
  (swallowed statements under a write target) — but present in the
  batch's own run and policy-neutral for a read endpoint; near-miss.
- **N5 — `person.profile.nil?` guards are blind.** A04 executed
  `people_helper.rb:37` and `:43` (`return "" if person.nil? || person.profile.nil?`)
  on the true side; the corpus's `has_one :profile` finder never returns
  nil (no `find_target_*_not_found` PC among the 42 nodes). No shape
  changes on the participant path, so no win — but D2 is violated (a
  data-dependent conditional with neither a PC nor a pin-ledger entry),
  and the same nil profile on the LAST-AUTHOR path is A03 (below).
- **N6 — pagination is a pinned input.** `params[:page]` is nil in every
  corpus run (pin ledger). A06 shows page 2 / page 3 change only
  `OFFSET ?` (wildcarded) and add a second COUNT (multiplicity, not
  shape). Shape-neutral; the pin's neutrality argument holds.
- **N7 — inflected locale (A09).** `set_grammatical_gender` issues
  `SELECT "profiles".* … WHERE person_id = ? LIMIT ?` for the principal
  BEFORE the action in the json variant; the corpus's json variants never
  read the principal's profile, but the shape+bind exist corpus-wide from
  `owner_image_tag`. Bind-level only; near-miss.
- **N8 — `Conversation#subject` blank branch.** `conversation.rb:64`
  `self[:subject].blank? ? I18n.t(…) : self[:subject]` runs on every row
  (html and json via `serializable_hash` → `send(:subject)`), and
  `direction_for(conversation.subject)`; no PC on `subject`, no pin-ledger
  entry. No statement consequence; D2 note only.
- **Harness artefact (not the app):** A01/A02 show one `SELECT "users".* … LIMIT ?`
  outside any target frame — my `install_real_warden` computed the
  Devise salt inside the capture window; fixed in `_common.rb` from A03
  onward (`REAL_SALT_CACHE`, primed at fixture load, as the batch does).

## Unreachable / blocked branches and why

- **`Person#name` with a missing profile → `fix_profile` → `DiasporaFederation::Discovery::Discovery#fetch_and_save` (A03/A03b).**
  `_conversation.haml:34` `conversation.last_author.name` (and
  `_message.html.haml:5` `person_link(message.author)`) call `Person#name`,
  which on `profile.nil?` runs `person.rb` `fix_profile` → federation
  discovery (network) → `reload`. This is a depth-0 call into a target
  family the corpus does not contain (TARGET_FUNCTIONS §3 lists
  `fetch_and_save` as a declared network wall in other batches; this
  corpus has no such event, and no `not_found` decision on the profile
  finder, so the branch is Class B by code reading). Both attempts to
  run it aborted the JVM natively (`free(): invalid pointer`, exit 134,
  with and without Coverage), the same crash class the probe header
  documents for the mention/discovery path on this JRuby — so no
  `concrete_run.json` exists for it and it is reported as a code-reading
  finding, not a judged win. The batch should model it (a `profile`
  not_found decision + the discovery wall) or pin it with a written
  data-integrity argument (`profiles.person_id` FK does not force a row
  to exist).
- **Visibility whose conversation row is missing** (the LEFT OUTER JOIN
  nil edge): `conversation_visibilities.conversation_id` NOT NULL +
  `add_foreign_key … on_delete: :cascade` (schema.rb:141, 626) — no
  database state produces it (R2's argument stands).
- **Message whose author is deleted / conversation whose author is deleted:**
  `messages.author_id` and `conversations.author_id` FKs cascade
  (schema.rb:628, 633); `Person has_many :messages, dependent: :destroy`.
  Unreachable through the schema; sqlite without FK enforcement could
  fake it but that is not an app state.
- **`.js` format:** declared on the controller but templateless;
  responders' `to_js` = `default_render` → `ActionView::Template::Error`
  (A07). A real 500, no data access beyond the html prefix.
- **`params[:page]` = "0"/"abc":** `WillPaginate::InvalidPage` before any
  statement; not run (no shape can result).
- **Site chrome (`layout(false)` pin):** with the real layout,
  `gon_set_current_user`'s `UserPresenter` serializes aspects, contact
  counts, unread notifications and `unread_message_count` — reads the
  corpus scopes out by the batch's standing layout decision. Not attacked
  (scope decision, not a fixture/param axis); flagged only.
- **Principal without a profile:** `owner_image_tag` in `_messages.haml:9`
  would raise `NoMethodError` on `nil.image_url` (a 500, no new shape);
  not run.

## Instrument notes
- `mock_note_check.py`'s normalizer treats `COUNT(*)` as projection `*`,
  so a real aggregate can be "matched" by a plain `table.*` note under a
  nested frame (W2). The coordinator's `note_fidelity_audit.py`
  (AGG-COLLAPSE / STAR-OVER / PRED-DIFF) closes that gap; its full output
  for all runs is `adversary/runs/_note_fidelity_audit.txt`.
- The assumption checker was writing/deleting transient `dump_*_achk_*`
  files in the batch dir during my runs; one judge pass (A06) failed on a
  mid-glob deletion and was re-run.
