# ADVERSARY REPORT — people_show R1 (2026-09-04)

Batch: `reports/diaspora/results3/people_show/` · commit b194618 ·
claimed `coverage_complete=true` (62 tree nodes, 7 673 dumps, 226 084 PCs,
`dump_errors = {ActionView::Template::Error}`).
Round R1 — first adversary round on this endpoint.
All runs are REAL: real app via `ActionController::TestCase#process`, real
Devise-serialized principal (fixture user 9 / person 1 = concrete
instantiation of the symbolic declaration; no login flow), real templates,
real `sql.active_record` + target-frame capture via
`concrete_run_probe.rb` / `target_call_probe.rb`. No app code was mocked,
stubbed or patched; only fixture rows, session, warden and params were
supplied. One JRuby at a time under `flock /tmp/concolic-slot.lock` +
`systemd-run --user -p MemoryMax=4000M`.

## TL;DR

**10 wins (P-1 … P-10), 3 of them TARGET-LEVEL.** The corpus is anon-only BY
CONSTRUCTION — its harness hard-wires `current_user = nil`/`user_signed_in? =
false` on every scenario, and its `StubWarden` returns a user only for
`authenticate!`. Every signed-in branch of `show` (`mark_corresponding_
notifications_read`, `contact_for`, `block_for`, `Photo.visible` user arm,
`private_hash` bio/location rendering, publisher aspects, mobile stream
user-arm) is structurally absent from the corpus; the batch's own
`run_dse.rb` header admits it ("Both anonymous — the sourced people batch
never explored signed-in show…"). Seven of eight runs were judged **RED** by
`mock_note_check` (the anon control — the eighth — reproduces corpus shapes
exactly: NOTE-OK, which establishes harness fidelity).

## Headline structural defect

The corpus's 18 symbolic targets were witnessed exclusively on anon paths
(`anon_handle/html`, `anon_json`, `anon_mobile`). The signed-in `show` adds:

| surface | real SQL | corpus counterpart |
|---|---|---|
| notification read-state | `UPDATE "notifications" SET "unread" = ? WHERE id = ?` | **none — no write target exists** |
| notifications read | `SELECT "notifications".* WHERE recipient_id = ? AND target_type = ? AND target_id = ? AND unread = ?` | none (records notes are posts-stream only) |
| `contact_for` | `SELECT "contacts".* WHERE user_id = ? AND person_id = ? LIMIT ?` | none (find_by note is the non-SQL "User query") |
| `block_for` | `SELECT "blocks".* WHERE user_id = ? AND person_id = ? LIMIT ?` | none (no Block target/note) |
| `Photo.visible` other | `SELECT COUNT(*) FROM (SELECT DISTINCT photos.* LEFT OUTER JOIN share_visibilities … WHERE author_id = ? AND (user_id = ? OR public = ?))` | anon note only (`author_id = ? AND public = true`, no JOIN) |
| private-hash bio/location | `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?` (×2) | none (`exists?` target absent — H2) |
| publisher aspects | `SELECT "aspects".* … post_default = ? ORDER BY order_id` / `COUNT(*) FROM aspects` / `1 AS one FROM aspects` | none |
| mobile stream user-arm | `SELECT DISTINCT posts.* LEFT OUTER JOIN share_visibilities …`, `SELECT likes.* WHERE author_id = ? AND target_id IN (?, ?)`, `SELECT mentions.* … WHERE mentions_container_id IN (?, ?)`, `SELECT polls.*/locations.* WHERE status_message_id = ?`, `SELECT photos.* WHERE status_message_guid = ?` | stream notes are all anon `posts.public = true AND created_at < TS`; likes COUNT-only |
| principal resolution | `SELECT "people".* WHERE "people"."owner_id" = ? LIMIT ?` | find_target notes carry `people.id`/`profiles.person_id` only |
| tags | `SELECT "tags"."name" FROM "tags" INNER JOIN "taggings" ON … WHERE taggable_id = ? AND taggable_type = ? AND context = ? ORDER BY taggings.id` | exists under `CollectionProxy.records` only — `Calculations.pluck` frame has ZERO notes |

## Scenarios

All under `adversary/`; run outputs in `adversary/runs/`.

| # | manifest | request | status | judge | verdict |
|---|---|---|---|---|---|
| C01 | `C01_auth_self_html.rb` | alice@localhost html, signed-in (own profile; 2 unread + 1 read notification; diaspora:// bio+location; 3 photos; 2 aspects; tags) | 200 (render truncated at layout wall) | RED | **P-1, P-2, P-4, P-5, P-6, P-7, P-9, P-10** |
| C02 | `C02_auth_other_html.rb` | bob@remote.example html, signed-in (contact receiving-only, 1 aspect membership, bob public/private/shared photos + share_visibility) | render truncated | RED | **P-3, P-4, P-5, P-6, P-9, P-10** |
| C03 | `C03_auth_other_mutual_html.rb` | bob@remote.example html, signed-in (MUTUAL contact, bob bio with diaspora:// link, shared photo) | render truncated | RED | **P-2, P-3, P-4, P-5, P-6, P-9, P-10** |
| C04 | `C04_auth_blocked_json.rb` | bob@remote.example json, signed-in (alice BLOCKS bob; no contact; bob tags; bob blocked) | **200 (390 bytes)** full render | RED | **P-4, P-5, P-6, P-9, P-10** |
| C05 | `C05_auth_mobile.rb` | bob@remote.example mobile, signed-in (contact receiving; 2 posts: public + shared; 1 private-not-shared; like; 2 comments; photo; block row on carol; bob bio tags) | render truncated at mobile layout ("Nil location") | RED | **P-2 (likes exists?), P-4, P-5, P-6, P-8, P-9, P-10** |
| C06 | `C06_anon_self_html.rb` | alice@localhost html, ANON control (public bio, 3 photos, tags) | render truncated | NOTE-OK on anon shapes + **pluck RED** | control (fidelity); **P-9** |
| C07 | `C07_anon_remote_401.rb` | bob@remote.example html, ANON | **401 (throw :warden), 0 bytes** | all OK | boundary observation (near-miss NM-1) |
| C08 | `C08_closed_account.rb` | carol@remote.example html, signed-in (closed account) | EXC NoMethodError in rescue redirect | — | near-miss NM-2 (Test-Case redirect wall) |
| C09 | `C09_missing_person.rb` | nobody@nowhere.example html, ANON | **404 (241 bytes)** | corpus finder note faithful | control (404 arm = finder only, matches corpus) |
| DBG | `DBG_notification_bind*.rb` | direct query probes | n/a | n/a | instrument (boolean bind `'t'`/`'f'`) |

## Wins

### P-1 — WRITE family absent from the target boundary (Class S, TARGET-LEVEL, judge NOTE-MISSING)

```
UPDATE "notifications" SET "unread" = ? WHERE "notifications"."id" = ?   (×2)
```
- Issued by: `app/controllers/people_controller.rb:173-177
  mark_corresponding_notifications_read` → `app/models/notification.rb:59
  set_read_state(true)` → `ActiveRecord::Persistence#update_column`.
- Corpus: 18 targets, ZERO write family (no `ActiveRecord::Persistence`
  target, no UPDATE note anywhere in the dump set). The write is
  structurally unrepresentable — `mock_note_check`: NOTE-MISSING (RED).
- Entrypoint: frame chain inside `PeopleController#show`, after principal
  fetch; the two UPDATEs follow the notifications SELECT in the same request.
- Depth-0 target calls: `ActiveRecord::Persistence#update_column('unread',
  false)` ×2 — no corpus symbolic_call counterpart.
- Class: the boundary declares no write targets → every endpoint's writes
  are unobservable. Matrix row **T-af**, marks T-t/T-v people_show ⏳ (P-1).
  Fixture note: the notifications must be inserted with `unread: 't'` (AR
  binds `unread = 't'` on this adapter) or the WHERE matches nothing.

### P-2 — `exists?` family absent (Class S, TARGET-LEVEL, judge NOTE-MISSING)

```
SELECT  1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?
SELECT  1 AS one FROM "aspects" WHERE "aspects"."user_id" = ? LIMIT ?
SELECT  1 AS one FROM "likes" WHERE "likes"."author_id" = ? AND "likes"."target_type" = ? AND "likes"."target_id" = ? LIMIT ?
```
- bio/location `diaspora://…/post/<guid>` in `ProfilePresenter#private_hash`
  → `Diaspora::MessageRenderer#diaspora_links` → `Post.exists?(guid:)` (×2:
  bio + location, C01/C03); aspects (publisher aspect-exists ×3, C01);
  likes (mobile `like_posts_for_stream!`, C05).
- Corpus: 0 `1 AS one` notes; `FinderMethods.exists?` is not a corpus
  target. Same family as comments M-1 / conversations C-4 (matrix **T-a**),
  but the people_show route to it (signed-in private hash) was unreachable
  in the anon-only harness.

### P-3 — signed-in visibility COUNT (Class S, ENDPOINT-LEVEL, judge NOTE-MISMATCH / PRED-OP-DIFF)

```
SELECT COUNT(*) FROM (SELECT DISTINCT photos.* FROM "photos" LEFT OUTER JOIN share_visibilities
ON share_visibilities.shareable_id = photos.id AND share_visibilities.shareable_type = 'Photo'
WHERE "photos"."author_id" = ? AND (share_visibilities.user_id = ? OR photos.public = ?))
```
- `Photo.visible(current_user, @person).count(:all)` (people_controller
  :180) → `lib/diaspora/shareable.rb with_visibility/visible_by_user` —
  other-person arm (C02/C03).
- Corpus count note: anon `WHERE author_id = ? AND public = true AND
  pending = false` — no JOIN, no share_visibilities → PRED-OP-DIFF.

### P-4 — `contact_for` find_by (Class S, ENDPOINT-LEVEL, judge NOTE-MISMATCH)

```
SELECT  "contacts".* FROM "contacts" WHERE "contacts"."user_id" = ? AND "contacts"."person_id" = ? LIMIT ?
```
- `PersonPresenter#relationship` → `User#contact_for` →
  `Contact.includes(person: :profile).find_by(user_id:, person_id:)`
  (`app/models/user/querying.rb`). Fires on EVERY signed-in show.
- Corpus: the only find_by note is the non-SQL opaque "User query
  (class-level finder…)" — no `contacts` SQL anywhere.

### P-5 — `block_for` find_by (Class S, ENDPOINT-LEVEL, judge NOTE-MISMATCH)

```
SELECT  "blocks".* FROM "blocks" WHERE "blocks"."user_id" = ? AND "blocks"."person_id" = ? LIMIT ?
```
- `PersonPresenter#is_blocked?` → `User#block_for` → `blocks.find_by
  (person_id:)` (`app/models/user/querying.rb`). Fires even with no block
  row (C01 self, C02/C03 mutual) and with one (C04).
- Corpus: no Block target, no note.

### P-6 — notifications read (Class B→S, ENDPOINT-LEVEL, judge NOTE-MISMATCH)

```
SELECT "notifications".* FROM "notifications" WHERE "notifications"."recipient_id" = ?
AND "notifications"."target_type" = ? AND "notifications"."target_id" = ? AND "notifications"."unread" = ?
```
- `mark_corresponding_notifications_read` (people_controller :173-177).
- Corpus `Relation.records`/`to_a` notes are 100 % posts-stream shapes
  (`posts.public = true AND created_at < TS`); the notifications SELECT has
  no counterpart.

### P-7 — aspects family (Class B, ENDPOINT-LEVEL, judge RED)

```
SELECT "aspects".* FROM "aspects" WHERE "aspects"."user_id" = ? AND "aspects"."post_default" = ? ORDER BY order_id ASC
SELECT "aspects".* FROM "aspects" WHERE "aspects"."user_id" = ? ORDER BY order_id ASC
SELECT COUNT(*) FROM "aspects" WHERE "aspects"."user_id" = ?
SELECT 1 AS one FROM "aspects" WHERE "aspects"."user_id" = ? LIMIT ?
```
- publisher partial `current_user.post_default_aspects` (C01 self html) and
  aspect dropdown. No `aspects` SQL in any dump.

### P-8 — signed-in mobile stream surface (Class B→S, ENDPOINT-LEVEL, judge RED on `Relation.records` ×10)

```
SELECT  DISTINCT posts.* FROM "posts" LEFT OUTER JOIN share_visibilities … WHERE "posts"."author_id" = ? AND (share_visibilities.user_id = ? OR posts.public = ?)   (×2)
SELECT "likes".* FROM "likes" WHERE "likes"."author_id" = ? AND "likes"."target_id" IN (?, ?) AND "likes"."target_type" = ?
SELECT "mentions".* FROM "mentions" WHERE … "mentions_container_type" = ? AND "mentions_container_id" IN (?, ?)
SELECT  "polls".* FROM "polls" WHERE "polls"."status_message_id" = ? LIMIT ?
SELECT  "locations".* FROM "locations" WHERE "locations"."status_message_id" = ? LIMIT ?
SELECT  "photos".* FROM "photos" WHERE "photos"."status_message_guid" = ? ORDER BY … LIMIT ?
SELECT COUNT(*) FROM "photos" WHERE "photos"."status_message_guid" = ?
```
- `Stream::Person#posts` user-arm (`Post.from_person_visible_by_user`),
  `like_posts_for_stream!`, mentions eager-load, post poll/location
  associations, mobile photo_area — all signed-in mobile (C05).

### P-9 — `Calculations.pluck` frame has zero notes (Class S, TARGET-LEVEL, judge NOTE-MISSING)

```
SELECT "tags"."name" FROM "tags" INNER JOIN "taggings" ON "tags"."id" = "taggings"."tag_id"
WHERE "taggings"."taggable_id" = ? AND "taggings"."taggable_type" = ? AND "taggings"."context" = ? ORDER BY taggings.id
```
- `ProfilePresenter` `tags.pluck(:name)` (`Profile#tag_string`) — fires on
  EVERY show (anon public_hash AND signed-in private_hash; C01–C06 incl. the
  anon control).
- Corpus mints the tags statement under `CollectionProxy.records` only —
  the `Calculations.pluck` frame has zero symbolic_call events, so the judge
  reports NOTE-MISSING for the frame. Matrix row **T-ag**.

### P-10 — `people.owner_id` principal read (Class B, TARGET-LEVEL, judge PRED-OP-DIFF)

```
SELECT  "people".* FROM "people" WHERE "people"."owner_id" = ? LIMIT ?
```
- `current_user.person` (User → Person belongs_to; `app/models/user.rb`),
  fired on every signed-in show via devise→`current_user.person`.
- Corpus `SingularAssociation.find_target` notes carry `people.id =
  $(…row_author_id)` and `profiles.person_id = $(…)` — never `people.owner_id`.
  Matrix row **T-ah**.

## Near-misses

| # | finding | disposition |
|---|---|---|
| NM-1 | C07: anon + remote person → real `authenticate_if_remote_profile!` → `throw :warden` → **401 (0 bytes)**. The corpus's anon dumps using remote handles (bob@remote.example) show full profile pages — impossible in the real app. The StubWarden returned a user unconditionally | boundary-stage (auth), belongs in `_auth_boundary/BOUNDARY_POLICY.md`, NOT an endpoint win |
| NM-2 | C08: closed account → `Diaspora::AccountClosed` rescue → `redirect_back` → `NoMethodError: super: no superclass method 'redirect_to'` in the TestCase rig. The corpus models the decision (`…_closed_account == True` ×8 297) but the rescue OUTPUT (redirect/410) needs the full Rack stack (as conversations R6 used `Rails.application.call`) | harness limit; the decision is covered; the terminal is not verifiable in this rig |
| NM-3 | html/mobile layout asset wall: `couldn't find file 'underscore'` (html) / `Nil location provided` (mobile) truncate the RENDER below the endpoint — the batch's own `targets.rb` documents this wall and patched the helpers in THEIR harness; I chose not to patch app code | all endpoint SQL captured before the wall; full-layout render needs the vendor JS or the batch's helper patch (harness choice) |
| NM-4 | C09: anon missing person → 404, exactly ONE statement (people diaspora_handle finder) | faithful to the corpus's finder note + not-found decision (`FinderMethods_first_not_found == True` ×7 293); control, not a win |
| NM-5 | `SELECT "services".* FROM "services" WHERE user_id = ?` (C01, layout/additional-services surface) and `SELECT "aspect_memberships".* FROM aspect_memberships WHERE contact_id = ?` + `SELECT "aspects".* WHERE id = ?` (C02/C03/C05, ContactPresenter/contact-modal) | new shapes, layout/contact-hash-owned; folded into P-7/P-8's family entries in the ledger rather than separate rows |
| NM-6 | fixture boolean rule: `ConcreteEnv.quote` writes raw values; AR binds booleans as `'t'`/`'f'` on this adapter, so raw `1`/`0` fixtures make any boolean WHERE empty (the notifications UPDATE didn't fire until `'t'`). Confirms the existing instrument row on the rig | instrument (already recorded in the ledger); every future manifest must seed booleans as `'t'`/`'f'` |

## Branches I could not reach (and why)

- **Full html layout render** below the asset wall — needs the batch's
  helper patch (vendor JS absent from the checkout); treated as wall
  documented in targets.rb.
- **AccountClosed rescue output** (410/redirect body) — TestCase redirect
  super-chain break; needs full-stack dispatch.
- **Remote-person anon body** — the real app 401s (NM-1); only reachable
  signed-in, which is what C02/C03/C05 do.
- **`current_page?(person_photos_path)` true arm** (publisher suppressed) —
  needs the photos route; the view branch exists but the publisher-render
  arm is the one the corpus lacks anyway.
- **Mention modal / conversation modal full renders** below the html wall —
  their SQL (aspects.id, aspect_memberships) is captured pre-wall.

## Judge mechanics

- `mock_note_check.py` verdicts: NOTE-MISSING (frame issues real SQL, zero
  SQL-shaped notes) / NOTE-MISMATCH (notes exist but none match the real
  shape) / NOTE-OK (matches). `note_fidelity_audit.py` adds PRED-OP-DIFF /
  LIMIT-DIFF / PROJ-DIFF.
- `concrete_aliases.json` (new, batch-local) maps real frames ↔ corpus
  names; the batch had none.
- Runs are in `adversary/runs/C*.json` + `.judge.txt` + `.log`.

## Ledger

`docs/ADVERSARY_WINS.md`: people_show R1 section (P-1 … P-10, status
`open`), propagation-matrix marks (T-a ⏳(P-2) → people_show; T-t/T-v ⏳(P-1);
new rows T-af/T-ag/T-ah), round-log row R1 2026-09-04.
---

# R2 — 2026-09-05 (post-repair claim attack; zero-win round)

## Round summary

| | |
|---|---|
| Claim under attack | batch R1 repair `8776bf3` (shared boundary: 4 sanctioned families write/exists?/pluck/owner_id + signed-in harness) → drain `078f90c` (29,944 runs / 12,997 paths, COMPLETE=True, MISSING=0) → Option-A close-out `7f3858d` (P-7/P-8 declared open) |
| Verdict | **ZERO WINS — claim verified within the declared scope** (P-7/P-8 open, accepted) |
| Runs | 8 manifests / 8 processes / 8 real requests (R2C01–R2C07, R2C09), all EXIT=0, 0 JVM aborts; sqlite DBs + `.json`/`.judge.txt`/`.log` in `adversary/runs/` |
| Discipline | Step-0 `hardening_lint.py` run on the R2 scenarios first (5 advisory checks, none a shape gap beyond P-7/P-8); REAL runs only (ConcreteEnv sqlite via JDBC, fixture INSERTS, real Devise session via `User.serialize_from_session`, real `ActionController::TestCase#process`, real templates); no mocks/stubs/src/app edits. App checkout verified: the only app diffs vs HEAD are the batch's documented "Gate 1b split (function boundary only, NO functional change)" extractions in `lib/stream/base.rb` / `app/models/post.rb` / `streams_controller.rb` (P-8 family) + env config; `people_controller.rb` and the P-1/P-2/P-9/P-10 code paths are untouched |
| Batch files | `run_dse.rb`, `targets.rb`, `concrete_aliases.json` read-only (not edited) |

## 1. The 4 sanctioned families — corpus-faithful (both judges GREEN)

Real scenarios replicated the R1 shapes; judged against the 078f90c/7f3858d
corpus with `mock_note_check + note_fidelity_audit`:

| family | real shape (R2C01–R2C05) | corpus witnesses | judge |
|---|---|---|---|
| P-1 write | `UPDATE "notifications" SET "unread" = ? WHERE "notifications"."id" = ?` | **7 030** `update_column` notes (`SET "unread" = false`, auth dumps) | NOTE-OK (C01/C02/C03/C05) |
| P-2 exists? | `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT 1` + aspects `1 AS one` | **1 176** posts.guid + roles/likes variants | NOTE-OK ×2 (C01), C03 |
| P-9 pluck | `SELECT "tags"."name" FROM "tags" INNER JOIN "taggings" ON … WHERE taggable_id/type/context ORDER BY taggings.id` | **15 887** `Calculations.pluck` notes | NOTE-OK (C01–C06) |
| P-10 owner_id | `SELECT "people".* FROM "people" WHERE "people"."owner_id" = ? LIMIT 1` | **11 436** find_target notes (3 direction shapes) | NOTE-OK (C01–C05) |

Re-witness counts from AGENT_RUN (7 030 / 6 599+ / 12 964 / 9 946) all present
— two families grew further in the drain corpus (pluck 15 887, owner_id
11 436).

## 2. Signed-in harness shapes — all have corpus counterparts

- **R2C01 auth_self_html** (alice→alice): full signed-in self surface
  (notifications SELECT + write, contact_for, block_for, private_hash
  exists?, publisher aspects, photo count). Judge: NOTE-OK on every issuing
  frame except the two pre-adjudicated classes (warden `users` SELECT
  boundary exclusion; P-7 aspects `post_default` + aspects COUNT ORDER-DIFF —
  declared open). 4/5 anon-render shapes EXACT.
- **R2C02 auth_other_html** (alice→bob): OTHER arm — visibility COUNT with
  share_visibilities JOIN, contact_for/block_for, notifications, private_hash.
  Judge NOTE-OK everywhere except `users` (boundary); fidelity flags:
  preload LIMIT-DIFF ×2 (`people.id`/`profiles.person_id` no-LIMIT vs
  find_target LIMIT-1 — the documented P-4 nuance), P-3 COUNT ORDER-DIFF
  (subquery wrapper — documented nuance).
- **R2C03 auth_other_mutual_html**: identical shape set + mutual contact —
  same verdict (exists? NOTE-OK; only boundary/nuance REDs).
- **R2C04 auth_blocked_json**: blocked-other json — every shape EXACT except
  `users` (boundary); 7 EXACT / 0 MISSING.
- **R2C05 auth_mobile**: signed-in mobile stream. P-8 #1
  (`SELECT DISTINCT posts.* … LEFT OUTER JOIN share_visibilities … WHERE
  author_id = ? AND (share_visibilities.user_id = ? OR posts.public = ?)`)
  reproduced real ×4 and corpus-matched (25 462 auth_mobile dumps carry the
  note; listed EXACT by note_fidelity, 12 EXACT total). The 11 RED items are
  all P-8 declared-open families (likes IN, mentions ×2, polls, locations,
  photos status_message_guid count + records) + `users` (boundary) + the
  documented LIMIT-DIFFs. **No NEW shape.**
- Frame census across all 8 runs (170 `records`, 54 `to_a`, 37 `gon`, 34
  `find_by`, 30 `first`, 24 `count`, 24 `CollectionProxy.records`, 16
  `exists?`, 15 `find_target`, 12 `pluck`, 12 `load_target`, 9 `size`, 2
  `update_column` …): every SQL-issuing frame is one of the 14 corpus-note
  targets; `Person#first_name/last_name`, `Person#remote?`, `gon`,
  `_set_rendered_content_type`, `PersonPresenter#description`, `url_for`,
  `status=` are documented non-SQL leaves (H3). `Stream::Base#post_ids` /
  `#attach_user_likes` are the Gate-1b splits (P-8 open).

## 3. NM-1 auth boundary — verified

Real C07 (anon + bob@remote.example): exactly ONE statement — the people
finder — then `authenticate_if_remote_profile!` → `throw :warden` → 401
(0 bytes). mock_note_check EXIT=0 (finder matched). Cross-checked the 6
warden-401 dumps:

- `anon_handle_0094`, `anon_json_0011`, `anon_mobile_4951`,
  `anon_remote_401_0001` — exactly the real shape (1 finder note) ✓
- `anon_mobile_presenter_4951` — 6 SQL notes (full render + 401): the
  batch's documented `dual: true` two-request-in-one-run artifact, not a
  401 misrepresentation (note, boundary-stage)
- `anon_remote_401_0066` — `people.owner_id` find_target instead of the
  finder: symbolic alternate-path OVER-EMISSION the real pre-auth dispatch
  cannot produce (the real 401 never reads owner_id — no principal yet).
  Note, boundary-stage; consistent with R1's NM-1 adjudication that the
  auth boundary belongs in `_auth_boundary/BOUNDARY_POLICY.md`, not an
  endpoint win.

## 4. Controls — harness trustworthiness re-established

- **R2C06 anon control (C06 replication)**: `mock_note_check` EXIT=0, all 5
  real statements EXACT — the anon html render reproduces the corpus shapes
  exactly on the post-repair corpus.
- **R2C09 404 control**: `mock_note_check` EXIT=0, 1 EXACT — missing-person
  404 emits exactly the finder + not-found decision the corpus models.
- **R2C07 401**: EXIT=0 (above).

## 5. Fidelity notes (all pre-adjudicated; none a win)

1. **Warden `users` SELECT** (`SELECT "users".* FROM "users" WHERE id = ?
   ORDER BY id ASC LIMIT ?`, every signed-in request): the real Devise
   `serialize_from_session` reload. Corpus-wide **zero** users-table SQL
   notes (the batch's StubWarden assigns `current_user` directly; the
   repair's signed-in harness kept that model). R1's own ledger excludes it:
   "the only pre-entrypoint statement is the single warden `users` SELECT
   (boundary, excluded)". Boundary-stage; unchanged by the repair; recorded.
2. **P-3 COUNT subquery wrapper** (`COUNT(*) FROM (SELECT DISTINCT
   photos.* …)` vs corpus `COUNT(*) FROM photos LEFT OUTER JOIN …`):
   documented AGENT_RUN 722/858 ("visibility COUNT subquery wrapper = P-3");
   0 subquery-form notes corpus-wide; the mock normalizer accepts the JOIN
   form (NOTE-OK), semantics identical.
3. **P-4 eager-load LIMIT-DIFF** (`people.id`/`profiles.person_id`
   no-LIMIT preloads vs find_target LIMIT-1 notes): documented AGENT_RUN
   719/829-831; unchanged.
4. **P-7 aspects** (`post_default` + COUNT ORDER BY): declared open (7f3858d).
5. **P-8 mobile families** (likes IN, mentions, polls, locations, photos):
   declared open; 0 `IN (?, ?)` mentions notes corpus-wide confirms the
   open declaration is accurate.
6. **H4 hardening note**: 3 length decisions recorded with ONE polarity only
   (records len False-only etc.) — corpus-model caution, no real-run shape
   gap observed on people_show.

## Ledger

`docs/ADVERSARY_WINS.md`: people_show R2 section added (zero-win statement
with full cross-check) + propagation-matrix row `R2 2026-09-05 | people_show
| 0 wins — claim verified within the declared scope`.
**Milestone: CLOSED on this round (within the P-7/P-8 declared-open scope).**
