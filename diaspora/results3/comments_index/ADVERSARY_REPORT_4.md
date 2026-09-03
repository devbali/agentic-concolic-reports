# ADVERSARY REPORT — ROUND 4 — comments_index
`CommentsController#index`, `GET /posts/:post_id/comments`, anonymous AND signed-in.
Adversary run 2026-08-28 against the corpus **regenerated from scratch** by cycle 5 (+5b)
after round 3's two wins (M-3, M-4) and four near-misses were closed.

Engine state under attack: `complete: true`, **0 missing**, **46 PC nodes**, **8 840 dumps**
(6 872 runs, 120 309 PCs), assumptions **1 095/1 095 PASS**, shims **19 PASS / 11 PROTOCOL /
0 red**, note check green; six SQL-consumer audits green (identity, statement-note lint,
bind resolution UNRESOLVABLE 0 / DERIVED-MISBOUND 0 / AMBIGUOUS 0, skipped PCs 0 dropped,
`pc_visibility --gate public,diaspora_handle,author_id,person_id,language` all VISIBLE,
`empty_relation_emission` 2 392 empty-list states / 0 findings); `hardening_lint` H1–H6 clean.

Real app only: `concrete_env.rb` sqlite/JDBC + the app schema, fixture ROWS by raw `INSERT`,
real Devise `serialize_from_session`, real `ActionController::TestCase#process` (every
`before_action` runs), real templates. **No mocks, no stubs, no monkey-patches; nothing under
`src/`, the app, or the batch's runner / targets / mocks / manifests was touched.** Only
fixture rows, session, params, headers and format are under adversary control. The batch's
own `concrete_run*.json` are byte-identical before and after
(`adversary4/runs/_batch_md5_before.txt`, re-checked at the end: **5/5 OK**).

Manifests, run JSONs, logs, response bodies and judge outputs: `adversary4/`
(`_common4.rb` harness, `C01…C12.rb` one scenario per process, `run4.sh` / `chain4.sh`,
`an4.py` per-request statement segmenter, `runs/*.json|.log|.judge.txt|_body_*.txt`,
`runs/_progress.log`, `runs/_hs_err_pid4193938.log`).

**12 manifests / 12 JRuby processes / 132 completed requests + 14 non-request probes**
(3 processes aborted the JVM — see §6, where the cause is finally diagnosed).

---

## Verdict

**2 wins.**

* **W4-1 (Class B)** — `users.language` has a **third** outcome the corpus's two-valued
  decision cannot express. `set_locale` does `I18n.locale = current_user.language` with
  `I18n.enforce_available_locales == true`, so a language that is not an available locale
  raises `I18n::InvalidLocale` **before the action body**: the real run issues **exactly one
  statement** (the `users` SELECT) and 500s. In 8 840 dumps the statement multiset `{users}`
  occurs **zero** times — the shortest signed-in path in the corpus is `{users, people.owner_id}`.
* **W4-2 (Class B, with an S consequence)** — `posts.type` is minted as a placeholder string
  and is in **neither** `pc_gate_columns` **nor** `pc_pin_ledger`, so the STI dispatch is
  outside the explored universe. A `posts.type` outside the Post STI tree (`Photo`,
  `ActivityStreams::Photo`, any legacy value) makes the finder's row raise
  `ActiveRecord::SubclassNotFound` **during instantiation**, so the real run issues the post
  finder and **nothing else** — no comments SELECT, no author/profile preloads, no mention
  loads, no `exists?` probes. Every corpus dump in which a post finder returns a row goes on
  to read the comments. Round 3 saw this and filed it as "a limitation, not a defect, because
  no statement is lost"; that criterion is the wrong one — M-3 and M-4 both established that a
  statement the corpus asserts and the real endpoint does **not** issue is a defect.

Both round-3 wins (M-3 dangling mention, M-4 empty relation) are **closed by real runs on this
corpus**, as are W1, W2 and all nine round-2 defects at projection level. All 12 judged run
files are green: `mock_note_check` `NOTE-OK`/`NOTE-OK*` only, `note_fidelity_audit`
**0 MISSING / 0 STAR-OVER / 0 AGG-COLLAPSE / 0 PROJ-DIFF / 0 PRED-DIFF**.

---

## 1. Re-verification of rounds 1–3, at projection level

Projection level = the statement's **projection** (named columns vs `t.*` vs an existence bit
vs an aggregate), its **predicate columns**, its **ordering**, and the mock's **return kind**.

| # | round-1/2/3 finding | round-4 verdict on THIS corpus | evidence |
|---|---|---|---|
| **W1 / M-1** | `Post.exists?(guid:)` from `diaspora_links` — `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?` | **CLEAN (still closed)** | C02: **47** real `exists?` statements over 20 requests, **all** the single shape `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?`, every one issued under frame `ActiveRecord::FinderMethods#exists?`. Corpus: 8 probe notes (`Anonymous.exists_probe`, `cols=8` — the existence bit, never `posts.*`), predicate `posts.guid`, `LIMIT 1`; return kind a concrete bool. `exists__1..4_exists` decisions all present in both polarities. Residual: cardinality only, N4-2. |
| **W2 / M-2** | `:mobile` never explored; depth-0 `Relation#to_a` with zero corpus events | **CLEAN (still closed), and the third entry point now works** | Depth-0 `ActiveRecord::Relation#to_a` **37** times across the round. Mobile reached by explicit format, by `session[:mobile_view]` (C07, byte-identical 4 079-byte body), **and — new — by `X_MOBILE_DEVICE` + a mobile User-Agent** (C07: `format: :html` → 3 848 / 4 079-byte mobile bodies, anon and signed-in). Corpus notes for the mobile comment relation: projection `comments.*`, predicates `commentable_id`/`commentable_type`, `ORDER BY created_at ASC` — EXACT. |
| **D1** | array-`post_id` family modelled the wrong `post_key` branch | **CLOSED** | C05 exercises all four post-finder key/predicate combinations for real: `posts.id = ?`, `posts.guid = ?`, `posts.id = ? AND author_id = ?`, `posts.guid = ? AND author_id = ?`, `posts.id = ? AND public = ?`, `posts.guid = ? AND public = ?` — every one with `ORDER BY "posts"."id" ASC LIMIT ?`, and every one has a corpus note. `post_id` boundary 15 vs 16 chars behaves exactly as `(Length(SYM_PARAM_post_id) < 16)` models (`C05_key_len15` → id key, `C05_key_len16` → guid key, both 404). No `IN (…)` post predicate anywhere. |
| **D2 / N3-1** | the `profiles` read on the DEVISE PRINCIPAL has no note bound to it; `users.language` blind | **CLOSED for the read and the decision** (a new third arm is W4-1) | C03: the `pl` principals issue, under `SingularAssociation#find_target` and **before the action body**, `SELECT "people".* … "owner_id" = ? LIMIT ?` then `SELECT "profiles".* … "person_id" = ? LIMIT ?`; the `en`, `de` and `fr` principals issue neither. Corpus: `(…devise_user_first_1_language == StringVal('pl'))` 1 824 T / 3 447 F, note `SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = $$(…devise_user_first_1_person_id) LIMIT 1` (1 814 events) — projection `profiles.*`, predicate `profiles.person_id`, `LIMIT 1`. `language` VISIBLE (5 271 refs) in `pc_visibility`. |
| **D3** | 9 219 `people.diaspora_handle` events for the `persisted? == false` arm | **CLOSED** | 44 distinct corpus notes, **none** carries a `people.diaspora_handle` predicate. `Diaspora::Mentionable.people_from_string` was traced in all 12 manifests and fired **zero** times in 132 requests, including the seven mention-markup shapes of C08. |
| **D4** | the `guid == ''` phantom decision family | **CLOSED** | No `…_guid ==` path condition in the 46-node universe (full PC census over 8 840 dumps); `guid`/`*_guid` in the pin ledger, out of the gate. |
| **D5** | `User has_one :person` pinned FOUND over a reachable 500 | **CLOSED, and both principal-shape arms reproduce** | C04: `en` + no `people` row → `{users, join, people.owner_id}` then `NoMethodError` at `evil_query.rb:116`; `pl` + no `people` row → `{users, people.owner_id}` then `Module::DelegationError` **before** the visibility join; `pl` + person but no `profiles` row → `{users, people.owner_id, profiles LIMIT 1}` then `DelegationError`. The corpus contains exactly these three short signed-in paths (10 / 5 / 5 dumps). |
| **D6 / N3-2** | `Post.exists?` cardinality capped | **repaired to the declared limit; the limit is real** | Corpus per-dump probe counts are now `{0: 3 415, 1: 2 316, 2: 1 312, 3: 817, 4: 980}`. Real counts observed in C02: **0, 1, 2, 3, 4, 5 and 6**. See N4-2. |
| **D7** | INSTRUMENT: `ConcreteEnv.insert` wrote booleans as `1`/`0` | **FIXED and re-verified** | C05: the signed-in **public** arm (`posts.id = ? AND posts.public = ?`) returns the row and the full render follows, on json, mobile and by 18-char guid — 9 `posts.id = ? AND posts.public = ?` statements in C05, plus 2 guid-keyed ones. |
| **D8** | `find_target` emitted *in addition to* the bulk preload | **CLOSED** | Across 132 requests the **only** real `find_target` statements are `people.owner_id … LIMIT ?` (18, the principal) and `profiles.person_id … LIMIT ?` (5, the principal under `pl`). **Zero** `find_target` for comment authors, author profiles or mentioned people, at any collection size (C12: 5 comments / 3 distinct authors → one `people.id IN (?, ?, ?)` and one `profiles.person_id IN (?, ?, ?)`, nothing else). |
| **D9** | json variants had no comment-collection length decision | **CLOSED** | Corpus records `(len(…records_1_rows) != 0)` 8 041 T / 581 F and `(len(…to_a_1_rows) != 0)` 6 426 T / 28 F. Real empty-json and empty-mobile states reproduced in C01 (bodies `[]` / 68 B, two statements each). |
| **M-3 / W3-1** | dangling `mentions.person_id`: `[null]` json / 500 mobile with **no** `profiles` read | **CLOSED — re-verified at projection level** | C01, 9 requests. Dangling mention → json **200** `"mentioned_people":[null]`, mobile **`ActionView::Template::Error ← NoMethodError: undefined method 'diaspora_handle' for nil:NilClass`**. Statement sequence in that state: `mentions …` → `SELECT "people".* WHERE "people"."id" = ?` → **STOP** (no `profiles`). Two dangling mentions → `people.id IN (?, ?)` → **STOP**. Live control → `people` **and** `profiles`. Mixed (1 live + 1 dangling) → `people.id IN (?, ?)` → `profiles.person_id = ?`. Corpus: `…row_person_not_found` decisions present on all three mention reps in both polarities. |
| **M-4 / W3-2** | preload notes emitted over EMPTY relations | **CLOSED — re-verified at projection level** | C01: a post with zero comments issues **exactly two** statements — `SELECT "posts".* … ORDER BY "posts"."id" ASC LIMIT ?` and `SELECT "comments".* … ORDER BY created_at ASC` — on anon json, anon mobile, signed-in json, by guid, and on a private post shared with the principal (mobile). A comment with zero mentions issues the author preload and then **two** `mentions` SELECTs with **no** preload after either. `empty_relation_emission_audit`: 2 392 empty-list states, 0 findings. |
| **B-2** | `escape_segment` demoted from target to shim | **re-verified** | **398** depth-0 `escape_segment` calls across the round; only **three** frames ever issued SQL (`Relation#records` 800, `exists?` 47, `find_target` 23) — `escape_segment` issued **0**. |
| **N3-3** | mobile mention display name pinned | **CLOSED in the corpus** (real-run half unreachable — §6) | C08 exercises `@{Name; handle}` and `@{handle}` for real on json and mobile (persons *with* profiles): identical statement sets, both render. Corpus: 29 mobile dumps carry `has_name == False ∧ mention person profile_not_found == True` and mint, in order, `mentions …` → `fetch_and_save` → `reload` (`people.id = $$(…records_1_row_person_id) LIMIT 1`) → `find_target` (`profiles.person_id = $$(…records_1_row_person_id) LIMIT 1`). |
| **N3-4** | stale `concrete_aliases.json` | **CLOSED** | `find_by → mention_lookup_*` is gone; the 12 judge runs print no note rows for absent targets. |
| **N3-5** | `Diaspora::NonPublic` outcome unlabelled | unchanged | C05: anon + private post → `401 (throw :warden)` with the post finder as the only statement, on json, mobile and html. |

---

## 2. The four NEW-MODELLING checks (brief items 2a–2d)

| # | check | verdict | evidence |
|---|---|---|---|
| **2a** | the `users.language` decision and the principal `profiles` read of `set_locale` / `set_grammatical_gender` — shape, bind, and whether `gender`'s pin is honest | **SHAPE, BIND and PIN all VERIFIED; the decision's DOMAIN is not — W4-1** | *Shape/bind:* C03, six principals. `pl` ⇒ `SELECT "people".* FROM "people" WHERE "people"."owner_id" = ? LIMIT ?` then `SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ? LIMIT ?`, both under `find_target`, both **before** the visibility join; `en`/`de`/`fr` ⇒ neither. Corpus note and bind match exactly (`$$(…devise_user_first_1_person_id)`, i.e. the principal person rep's own id, not a `users` column). *Witness completeness:* `I18n.inflector.inflected_locales(:gender)` is `["all", "pl"]` (C12 probe), so `pl` is the **only** real user language that is inflected — the two-valued abstraction is faithful for the inflected/not question. *Gender pin:* four `pl` principals with `gender` = `"male"` / SQL `NULL` / punctuation-only (`tr` strips it to `""`) / `"female"` produce **identical 11-statement sets**. The pin is honest: no arm of the gender compare changes data access, and the `profiles` read that is its evidence is issued before the compare on every arm. *What is not verified:* the decision's domain — see W4-1. |
| **2b** | the nested link-count chain (`ge2/ge3/ge4`, "4 = four or more") against real texts with 0…6 `diaspora://` post links plus comment-entity links | **VERIFIED where expressible; the declared limit is real and now measured at 6** | C02, 20 requests, 47 real `exists?`. Per render: 0 links → 0; 1 → 1; 2 → 2; 3 → 3; 4 → **4**; 5 → **5**; 6 → **6**. `comment`-entity link only → **0** (the link is left unrewritten in the body). First link a `comment` entity, then two `post` links → 2. **Middle** link a `comment` entity → 2 (the corpus can only make the FIRST link non-post, but the resulting count is what the statement multiset depends on, and the guids are free `SYM_PARAM_*` values, so this position difference is not observable in the evidence). `web+diaspora://…/post/…` → counted; `status_message` entity → not counted; the same guid twice → **two** probes for the same value. Corpus cardinality `{0,1,2,3,4}` — see N4-2. |
| **2c** | `_text_mention_has_name`, and the mobile `profile_not_found` arm that mints `fix_profile → Discovery → reload → profiles` | **display-name half VERIFIED by real runs; the `fix_profile` chain is UNREACHABLE on this rig (cause now diagnosed) and is corpus-verified only** | C08: seven mention shapes × json + mobile + signed-in. `@{Name; handle}`, `@{handle}`, both together, a unicode display name, a handle matching no `mentions` row (`mentioned_people` empty ⇒ `Mentionable.format` skipped, `make_mentions_plain_text` still runs), a markup handle that matches no loaded person (`people.find` → nil ⇒ `mention_link` returns the display name, 200), and a mention on a third pod — all 200, all statement-identical, mentions preloads `people.id IN (?, ?)` + `profiles.person_id IN (?, ?)`. The profile-less half (`@{handle}` of a person with no `profiles` row) reaches `PeopleHelper#person_link`'s `opts[:display_name] || person.name` → `Person#name` → `fix_profile`, and **C10 aborted the JVM** there. Corpus side verified instead: 29 mobile dumps carry exactly the chain, in that order, bound to the mobile mention rep (`…records_1_row_person_id`). |
| **2d** | `reload` as a target (B-1): its note must be exactly the single-row re-read; reaching its call site would be a win | **NOTE VERIFIED by code + corpus; CALL SITE UNREACHABLE — no win** | Corpus: 4 distinct `ActiveRecord::Base.reload` notes, 3 203 events, all of the form `SELECT "people".* FROM "people" WHERE "people"."id" = $$(<rep>_id) LIMIT 1` — projection `people.*`, predicate `people.id`, `LIMIT 1`, **no ORDER BY**, which is exactly what `reload`'s `self.class.unscoped { self.class.find(id) }` issues in activerecord-5.2.4.3 (`find` by pk adds `LIMIT 1` and no order). Return kind = the receiver (`reload` returns `self`). Event order in **every** dump that has one: `fetch_and_save` → `reload` → `find_target` (the `profiles` re-read after the association cache is cleared); the 3 203 `reload` events match the 3 203 `fetch_and_save` events one-for-one. **Reachability:** `reload` has exactly one caller on this endpoint — `Person#fix_profile` (`person.rb:371-375`) — and it runs **only if `Discovery#fetch_and_save` returns normally**, i.e. only after a successful WebFinger fetch. On this rig the first FFI call into the HTTP client aborts the JVM (N4-1), so no real run can reach it. Recorded as an unreachable branch with an established cause, not as a win. |

---

## 3. New scenarios (round 4)

| # | manifest | fixtures / request | status | mock_note_check | note_fidelity |
|---|---|---|---|---|---|
| C01 | `C01_dangling_and_empty.rb` | dangling `mentions.person_id`, live control, mixed (1 live + 1 dangling), **both** dangling; post with 0 comments, comment with 0 mentions, private-shared post with 0 comments. anon json/mobile + auth + by guid — 17 requests | 200 ×14, **500 ×3** | green | green (12 EXACT) |
| C02 | `C02_link_cardinality.rb` | comment texts with 0/1/2/3/4/5/6 `diaspora://…/post/<guid>` links (hits and misses), `comment`-entity only, comment-first, comment-in-the-middle, `web+diaspora://`, `status_message` entity, duplicate guid, two comments one link each. anon json + mobile — 20 requests | 200 ×20 | green | green (6 EXACT) |
| C03 | `C03_locale_gender.rb` | six principals: `en`, `pl`×4 (`gender` = male / SQL NULL / punctuation-only / female), `de`, `fr`. json + mobile — 9 requests | 200 ×9 | green | green (12 EXACT) |
| C04 | `C04_locale_edges.rb` | `users.language` = NULL / `"xx"` / `""`; `pl` principal with no `profiles` row; `pl` and `en` principals with no `people` row; alice control — 8 requests | 200 ×2, **`I18n::InvalidLocale` ×2**, `DelegationError` ×3, `NoMethodError` ×1 | green | green |
| C05 | `C05_visibility_matrix.rb` | public / private-not-shared / private-shared / own / public-and-shared / missing, × (anon, signed-in) × (json, mobile, html), by numeric id and by 18-char guid, plus `post_id` of length 15 and 16 — 34 requests | 200 ×16, 404 ×9, `401(throw :warden)` ×5, MissingTemplate ×4 | green | green (14 EXACT) |
| C06 | `C06_sti_reshare.rb` | `posts.type` ∈ {StatusMessage, Reshare (dangling `root_guid`), Reshare (real root), Photo, Bogus, ActivityStreams::Photo}; a comment whose `commentable_type` is the STI subclass. anon + auth, json + mobile, id + guid — 14 requests | 200 ×7, **`SubclassNotFound` ×7** | green | green (11 EXACT) |
| C07 | `C07_blocks_contacts.rb` | 4 comments / 4 authors (one blocked, one blocked+closed-account with a blank-name profile, alice's own, one with 2 mentions on other pods); `blocks` and `contacts` rows for the principal; markdown, setext heading, bare URL, `#tag`, `<3`; **all three mobile entry points**; `Accept: application/json` with no explicit format — 8 requests | 200 ×8 | green | green (12 EXACT) |
| C08 | `C08_mention_names.rb` | `@{Name; handle}`, `@{handle}`, both, markup matching no `mentions` row, markup whose handle matches no loaded person, a mention on a third pod, a unicode display name. anon + auth, json + mobile — 16 requests | 200 ×16 | green | green (12 EXACT) |
| C09 | `C09_discovery_bisect.rb` | ISOLATED, non-request bisect of the `fix_profile` → Discovery path in 14 ordered steps, each printing START before it runs | **JVM abort, exit 134** at step 07 (`HttpClient.get`) — steps 00–06 all OK | — | — |
| C10 | `C10_fixprofile_render.rb` | ISOLATED. mobile; `@{handle}` (no display name) of a person with **no `profiles` row** → `Person#name` → `fix_profile` | **JVM abort, exit 134** (`munmap_chunk(): invalid pointer`) | — | — |
| C11 | `C11_fixprofile_json.rb` | ISOLATED. json; a COMMENT AUTHOR with no `profiles` row → `as_api_response(:backbone)` → `Person#name` → `fix_profile` | **JVM abort, exit 134** | — | — |
| C12 | `C12_edges_and_probes.rb` | locale/inflector/adapter/STI introspection probes; comment `text = ''` and `'   '`; 5 comments / 3 distinct authors; a duplicate `profiles` row; `session[:mobile_view]` with an explicit json format — 6 requests + 6 probes | 200 ×6 | green | green (12 EXACT) |

Depth-0 target calls across all completed runs:
`escape_segment 398 · Relation#records 278 · FinderMethods#first 217 ·
_set_rendered_content_type 96 · Metal#status= 74 · FinderMethods#exists? 47 ·
Relation#to_a 37 · SingularAssociation#find_target 23`.
**No other target name fired at any depth** — in particular no `Person#fix_profile`,
`Mentionable.people_from_string`, `Discovery.new`, `Discovery#fetch_and_save`,
`Base#reload`, `Calculations#count`, `#pluck`, `Persistence#save`, or
`CollectionProxy#records/#load_target`. Every name that did fire except `escape_segment`
is a corpus target; `escape_segment` issued **0** SQL under its own frame.

---

## 4. WINS (blocking)

### W4-1 — `users.language` has a third outcome: `I18n::InvalidLocale` before the action body, one statement, no corpus path  (Class B)

**Scenario.** `C04_locale_edges.rb`. Fixtures: public post 350 (`author_id: 2`) with one
comment; principals `users(id: 31, language: "xx")` and `users(id: 32, language: "")`, each
with a `people` row and a `profiles` row so that nothing else can fail. Request: signed in as
31 (and 32), `format: :json`, `post_id: "350"`. Controls in the same process: `language: nil`
(200), and alice `language: "en"` (200).

**Real behaviour.**

```
[adv4] C04_lang_null  auth30 json post_id="350" -> 200 (344 bytes)
[adv4] C04_lang_xx    auth31 json post_id="350" -> EXC I18n::InvalidLocale: "xx" is not a valid locale
[adv4] C04_lang_empty auth32 json post_id="350" -> EXC I18n::InvalidLocale: ""   is not a valid locale
```

The whole data access of the two failing requests is, verbatim:

```sql
SELECT "users".* FROM "users" WHERE "users"."id" = ? ORDER BY "users"."id" ASC LIMIT ?
```

— and nothing else. No `people.owner_id`, no `share_visibilities` join, no post finder, no
comments SELECT. The control with `language = "en"` issues ten statements from the same
fixture; the control with `language = NULL` also issues ten (i18n treats `nil` as "use the
default", so NULL is *not* the third arm — only a non-nil unavailable code is).

**Issuing code.**

```ruby
# app/controllers/application_controller.rb:100-108   (before_action :set_locale)
def set_locale
  if user_signed_in?
    I18n.locale = current_user.language     # <- raises I18n::InvalidLocale
```

with `I18n.enforce_available_locales == true` (measured, C12 probe) and
`AVAILABLE_LANGUAGE_CODES.size == 77` vs `I18n.available_locales.size == 138`.

**Where the corpus forecloses it.**

```ruby
# targets.rb:760-761   (symbolic_instance, the identity-shim boundary)
if klass.name == "User" && attrs["language"].respond_to?(:value)
  attrs["language"] = ((attrs["language"] == "pl") ? "pl" : "en")
end
```

Both literals are available locales, so `set_locale` never raises in any dump and the run
always proceeds to `set_grammatical_gender` and then to the action body. Measured over the
whole corpus: the shortest signed-in statement multisets are
`{users, people.owner_id, profiles}` (5 dumps), `{users, people.owner_id}` (5 dumps) and
`{users, join, people.owner_id}` (10 dumps). The multiset **`{users}` occurs in 0 of 8 840
dumps**, and the string `InvalidLocale` occurs in **0** of the 8 840 dump files (raw grep).

**Class S/B hypothesis.** Class **B**: a data-dependent conditional inside `I18n.locale=`
(`locale_available?`) executes in the real app on a column the corpus has pinned to a
two-literal domain, so DSE cannot flip it; the resulting run — one statement, an unrecorded
terminal — is outside the explored universe. Consequence in the S direction: for every
request in that state the corpus asserts a post finder, a visibility chain and a comments
read that the application does not perform.

**Reachability.** `users.language` is `t.string "language"` — nullable, no default, no CHECK,
no FK (`db/schema.rb:573`). The only guard is `validates_inclusion_of :language, in:
AVAILABLE_LANGUAGE_CODES` (`app/models/user.rb:41`), and `AVAILABLE_LANGUAGE_CODES` is a
**boot-time constant read from `config/locale_settings.yml`** (`config/initializers/locale.rb:14`),
not a database constraint: a pod that drops a locale from that file — or any `update_column` /
`update_all` / import / restore that bypasses validation — leaves rows whose owners then 500
on every authenticated page. This is the same standing as ledger row **N-3** (a schema-legal
state the current code does not itself create), which was accepted as a win and closed as a
documented pin. The repair is accordingly either a third arm or a **PIN LEDGER entry with a
foreclosure argument** — DISCIPLINE §11's "a decision quietly dropped ... without a ledger
entry" applies to a decision's *domain*, not only to its column, and `language`'s domain is
pinned to two literals today with no entry.

---

### W4-2 — `posts.type` is a placeholder in the corpus and in neither the gate nor the ledger: an out-of-tree STI type reads the post and stops  (Class B, with an S consequence)

**Scenario.** `C06_sti_reshare.rb`. Fixtures: `posts(id: 373, type: "Photo")`,
`posts(id: 374, type: "Bogus")`, `posts(id: 375, type: "ActivityStreams::Photo")` — each
public, each with one comment by person 2 — alongside `StatusMessage` and two `Reshare`
controls. Requests: anon json, anon mobile, signed-in json, and by 18-char guid.

**Real behaviour.**

```
[adv4] C06_373_json      anon json post_id="373" -> EXC ActiveRecord::SubclassNotFound:
        Invalid single-table inheritance type: Photo is not a subclass of Post
[adv4] C06_374_json      anon json post_id="374" -> EXC ActiveRecord::SubclassNotFound:
        The single-table inheritance mechanism failed to locate the subclass: 'Bogus'
[adv4] C06_375_json      anon json post_id="375" -> EXC ActiveRecord::SubclassNotFound:
        ... failed to locate the subclass: 'ActivityStreams::Photo'
[adv4] C06_373_mobile    anon mobile   -> same
[adv4] C06_373_json_auth auth9  json   -> same
[adv4] C06_373_json_guid anon json by guid -> same
```

**The novel shape is an ABSENCE.** For each anon request the entire data access is

```sql
SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? ORDER BY "posts"."id" ASC LIMIT ?
```

and **nothing else** — the row is returned by the finder and the exception is raised while
instantiating it, before `.tap { … post.public? }` and before `post.comments.for_a_stream`.
For the signed-in request the access is `{join, people.owner_id, posts…author_id,
posts…public}` and then nothing: the third finder matches, instantiation raises, and the
comments SELECT is never issued. Measured over C06: the six out-of-tree requests contribute
exactly one post statement each (11 `posts.id = ?` statements for the 11 id-keyed anon requests, of which
the 5 out-of-tree ones stop there), and the whole 14-request manifest produces 7 `comments` SELECTs — one per
in-tree request.

**Issuing code.**

```ruby
# app/services/post_service.rb:52
Post.where(post_key(id_or_guid) => id_or_guid).first.tap do |post|   # <- raises here,
#                                                                        inside .first
# activerecord-5.2.4.3 lib/active_record/inheritance.rb  find_sti_class / subclass_from_attributes
```
```ruby
# app/services/comment_service.rb:23   — never reached
post_service.find!(post_id).comments.for_a_stream
```

**Where the corpus loses it.** `posts.type` is minted by `symbolic_instance` as an untracked
placeholder string (`SYM_RESULT_…_first_1_type` with concrete value `…_type_v`) and is
**never compared**: `pc_visibility_audit`'s blind-vars census lists `_type` at **29 087 mints
across 9 names, never referenced by any PC**. `completion_config.json` has
`pc_gate_columns = [public, diaspora_handle, author_id, person_id, language]` and
`pc_pin_ledger = [persisted, guid, commentable_type, mentions_container_type, shareable_type,
text, gender, reload_not_found]` — **`type` is in neither**, although its three sibling
polymorphic-type columns are in the ledger. This is exactly the shape that made `language`
invisible until round 3: a column the application branches on, minted as a placeholder value
that no real row can hold. The string `SubclassNotFound` likewise occurs in **0** of the 8 840 dump files (raw grep).

**Class S/B hypothesis.** Class **B** — the STI dispatch is a data-dependent conditional on a
real column that executes in the app and has no path condition, so DSE cannot flip it; the
`SubclassNotFound` terminal is in no dump. Class **S** consequence — in that state the corpus
asserts a `comments` SELECT (and, downstream, the author/profile preloads, the mention loads
and the `exists?` probes) for a request that performs **none** of them. Round 3 recorded the
same observation in its §6 and dismissed it because "no statement is lost"; that criterion is
the wrong one, and M-3 and M-4 are the precedents — both were wins whose novel shape was a
statement the corpus asserted and the real endpoint did not issue.

**Reachability.** `t.string "type", limit: 40, null: false` (`db/schema.rb:411`) — no CHECK,
no FK, no application-level validation of the STI column. `Photo` and `Post` **were the same
STI table** in older diaspora (`lib/diaspora/shareable.rb:7-8`: "centralize the similarities
of Photo and Post, *as they used to be the same class*"), and `ActivityStreams::Photo` was a
`Post` subclass that this version no longer defines — both are ordinary legacy-row states on
an upgraded pod, and both are unrescued 500s today. The repair is a decision over the real
subclass set (the N-2 pattern) or a `type` PIN LEDGER entry carrying the foreclosure argument;
either way Rule G requires `type` to appear in one of the two sets.

---

## 5. Near-misses (real defects or unverified claims, no missing statement shape)

### N4-1 — the `fix_profile` → Discovery JVM abort is **diagnosed**: `Faraday.default_adapter == :typhoeus` → Ethon → libcurl through JRuby's JFFI  (INSTRUMENT / RIG; closes an open three-batch ledger row)

Round 3 left this open: "the standing 'network wall' explanation is unestablished; three
fixture shapes gave three different JVM aborts, including one where no socket is reachable".
`C09_discovery_bisect.rb` bisects it in one isolated process, each step printing `START`
before it runs:

```
[adv4] PROBE 00-baseline-find          -> OK "dave@127.0.0.1"
[adv4] PROBE 01-profile-nil            -> OK "nil"
[adv4] PROBE 02-discovery-const        -> OK "DiasporaFederation::Discovery::Discovery"
[adv4] PROBE 03-discovery-new-ip       -> OK "dave@127.0.0.1"
[adv4] PROBE 04-discovery-new-nodomain -> OK "eve@"
[adv4] PROBE 05-faraday-adapter        -> OK ":typhoeus"
[adv4] PROBE 06-httpclient-connection  -> OK "Faraday::Connection"
[adv4] PROBE 07-httpclient-get-loopback START
#  SIGSEGV (0xb) ... Problematic frame: V [libjvm.so+0xb346c4] Klass::method_at_vtable(int)+0x4
```

So `Discovery.new` is **not** the crasher (steps 03/04 construct it for both a loopback handle
and a domain-less handle and return); `Person`, `profile`, and the whole gem constructor are
fine. The abort is the **first HTTP call**, and it is not I/O: the JVM's last JIT events before
the fault are `com.kenai.jffi.CallContextCache::getInstance` / `getCallContext` /
`Signature::<init>`, `libcurl.so.4.8.0` and `libjffi-1.2.so` are both mapped
(`runs/_hs_err_pid4193938.log`), and the two sibling processes died with glibc heap messages
(`munmap_chunk(): invalid pointer` in C10, `free(): invalid pointer` in round 3's B05) — the
signature of a native library corrupting the process heap through FFI, with the JVM dying at
the next unlucky allocation. `Faraday.default_adapter` is `:typhoeus` (measured twice, C09 and
C12), i.e. Ethon/libcurl via JFFI, which is what the app itself configures; on a real MRI pod
this works, on this JRuby it does not.

Three consequences. (i) The wall is real and its cause is now named: **any** code path that
performs an outbound HTTP request aborts the JVM here, for a reachable host, a loopback host
or no host at all — which is why round 3's three fixture shapes all died. (ii) `Person#name`
on a person with **no `profiles` row** is that path (`person.rb:247-250` → `fix_profile` →
`Discovery#fetch_and_save` → `HttpClient.get`), so the `…_profile_not_found == True` arm of
every rep — comment author (json and mobile), mentioned person (json and mobile), and the
principal's own person — is unjudgeable by any real run on this rig. That is three batches'
worth of `discovery_failed` / `reload` / post-discovery `profiles` modelling resting on code
reading. (iii) B-1 (`reload`) and the `Discovery.new` shim demotion stay unverified by a real
run **for a stated reason**, not an unknown one.

### N4-2 — `Post.exists?` cardinality: the corpus tops out at 4, real renders reach 6

C02 measured 0, 1, 2, 3, 4, 5 and 6 probes per render from real comment texts; the corpus's
per-dump distribution is `{0: 3 415, 1: 2 316, 2: 1 312, 3: 817, 4: 980}`. The batch declared
this honestly ("4 stands for four or more"), and every probe is statement-shape identical, so
this is a multiset under-count in the D1 sense, not a new shape. Recorded because the declared
limit is now *measured* rather than asserted, and because the same one-representative-row limit
means the per-render count is modelled as the per-comment count (C02's two-comments-one-link-each
render issues 2 probes and the corpus reaches 2 only through one rep carrying two links).

### N4-3 — both judges are blind to `=` vs `IN`, to `LIMIT`, and to `ORDER BY`, which are exactly three of Rule T4's projection requirements  (INSTRUMENT)

`note_fidelity_audit.classify` compares `normalize(real)` against `normalize(note)`, and
`tools/statement_diff.normalize` returns only `{tables, projection, predicates}` — where
`predicates` is the **set of column names** appearing in comparison nodes. The comparison
operator, the `LIMIT`, and the `ORDER BY` are not part of the comparison at all. Consequences
measured this round: the real preload of a **one-row** collection is
`SELECT "people".* FROM "people" WHERE "people"."id" = ?` with **no LIMIT** (19 such statements
in C01 alone, 31 in C08 — it is the commonest real shape, since AR only emits `IN (…)` for two
or more ids), and it is scored `EXACT` against *both* the corpus preload note
(`… "id" IN ($$(…))`) and the corpus `reload` / `find_target` note (`… "id" = $$(…) LIMIT 1`),
which stand for a different call. `mock_note_check` reports the same match as `NOTE-OK*`
("matched under a DIFFERENT target — frame nesting") in **every one of the 12 runs**.
Rule T4 requires "preload ⇒ one bulk `IN (…)`, not per-row `= $(…)`" and "finders carry
`ORDER BY pk` + `LIMIT 1`"; the checks that are supposed to enforce those cannot see them.
The corpus is in fact right on all three (verified by hand: finder notes carry
`ORDER BY "posts"."id" ASC LIMIT 1`, `reload` carries `LIMIT 1` with no ORDER BY matching
`find`, preload notes carry `IN`), but nothing would catch it if it were not.

### N4-4 — the third mobile entry point works after all; round 2's negative result is superseded

`X_MOBILE_DEVICE: iPhone` **together with** a mobile `HTTP_USER_AGENT`, on `format: :html`,
switches the format to `:mobile` for both anon and signed-in requests (C07: 3 848 / 4 079-byte
mobile bodies, byte-identical to the `session[:mobile_view]` and explicit-format renders).
`mobile-fu`'s `set_mobile_format` needs `is_mobile_device?` = `!is_tablet_device? &&
!!request.headers['X_MOBILE_DEVICE']`, so the header alone (round 2's test) is not enough — the
User-Agent decides the tablet half. No corpus consequence (the mobile variant is modelled), but
M-2's residual "entry point still unexercised" can be struck.

### N4-5 — `Processor.process`'s `return '' if message.blank?` is statement-neutral; the round-2 near-miss can be closed as harmless

A real comment row with `text = ''` and one with `text = '   '` (C12; the column is `NOT NULL`
but `''` is legal, and `validates :text, presence: true` forbids creating one through the app)
render `""` with **no** change to the statement set: `mentioned_people` is evaluated when
`Comment#message` is built, *before* `Processor.process` sees the blank text, so both `mentions`
SELECTs still fire; only the `diaspora_links` probes are foreclosed, which the corpus already
expresses as `_text_has_dlink == False`. The blind branch costs no evidence.

### N4-6 — `blocks` / `contacts` / `closed_account` confirmed to change nothing

C07 ran 8 requests (4 signed-in) against a post whose four comment authors include one the
principal **blocks**, one the principal blocks *and* whose account is closed with a blank-name
profile, the principal's own person, and one the principal has a `contacts` row for. Statement
census over the manifest: **no `blocks`, `contacts`, `aspects`, `likes`, `participations` or
`notifications` statement of any kind**. `#index` filters comments by nothing but
`commentable_id`/`commentable_type`, and the mobile partial's only signed-in branch is
`comment.author == current_user.person`, which the corpus models as
`(…to_a_1_row_author_id == …devise_user_first_1_person_id)` (2 135 T / 894 F). Positive
evidence for the existing "unreachable by code" entries.

---

## 6. Unreachable / not attacked, and why

* **`Person#fix_profile` → `Discovery#fetch_and_save` → `reload`** — unreachable by any real
  run on this rig; cause diagnosed in N4-1 (typhoeus/libcurl through JFFI aborts the JVM on the
  first FFI call). Three processes this round (C09 step 07, C10, C11) died there, in three
  places on the same path. Even with a working HTTP client, `reload` runs **only if
  `fetch_and_save` returns normally**, which requires a live WebFinger peer for the person's
  domain — so B-1's `reload` note is verifiable by code reading and by the corpus's event
  ordering, and not by a fixture.
* **`Reshare#root` / `absolute_root` / `o_embed_cache` / `open_graph_cache`** — C06 rendered a
  `Reshare` with a dangling `root_guid` and one with a real root, json and mobile, anon and
  signed-in: statement sets **identical** to a `StatusMessage` (200 in all cases). `#index`
  never touches the post beyond `public?` and `comments`. Unreachable by code.
* **`comments.commentable_type = 'StatusMessage'`** — C06 post 376: the association scope binds
  the base-class literal `'Post'`, so the row does not match and the body is `[]`. Positive
  evidence for the H5 ledger entry.
* **`gon_set_current_user` → `UserPresenter`** — constructed and pushed on every signed-in
  request, never serialized (both renderable formats bypass the layout), so its query fan-out
  (`aspects`, `contacts.count`, unread counts, `services`) issues nothing. Confirmed again by
  the statement census of all 51 signed-in requests this round.
* **`format: :html`** → `ActionView::MissingTemplate` after the complete visibility chain (4×
  in C05); **`format: :xml`** → `UnknownFormat` (round 2). `Accept: application/json` with no
  explicit format resolves to json with the same reads (C07).
* **`comments.author_id` dangling** — `add_foreign_key "comments", "people", column:
  "author_id", on_delete: :cascade` (`db/schema.rb:624`) makes it not a database state; the
  batch's pin is honest. (Contrast `mentions`, which carries no foreign key at all — M-3.)
* **A second `profiles` row for one person** (C12) — `has_one` attaches one of them; no extra
  statement, no new shape.
* **`camo_urls` / `link_all_mentions` / `disable_hovercards` / `AppConfig.*`** — configuration,
  not fixture/param/header. Out of the adversary's remit; none reaches SQL.

## 7. Harness notes

* Manifests live in `adversary4/`, so the probe writes `adversary4/concrete_run.json`; the
  batch's five `concrete_run*.json` are byte-identical before and after (`md5sum -c` → 5/5 OK).
* `_common4.rb` is round 3's `_common3.rb` with the tag changed and two additions of my own
  (`seed_user!` for extra principals, `adv_probe` for non-request bisect steps that print
  `START` before running, so a JVM abort names its own step). Nothing in it mocks, stubs or
  patches app code.
* **Caveat for reading these logs (and round 3's):** the warden memo is per-uid
  (`USERS[uid] ||= User.serialize_from_session(...)`), so the **second and later** requests
  for the same uid in one process reuse the same `User` object *with its association cache*,
  and therefore issue neither the `users` SELECT nor the principal's `people`/`profiles`
  reads. Only the FIRST request per uid is a clean principal differential — which is how C03
  and C04 are built (one uid per arm).
* Runs used `CONCRETE_COVERAGE=0`, `unset JAVA_TOOL_OPTIONS`, `flock /tmp/concolic-slot.lock`
  **inside** `systemd-run --user --pipe --wait -p MemoryMax=4000M -p MemorySwapMax=0`, one
  scenario per process, with the three crash-risky manifests isolated and run last.
* The JVM crash log this round was moved out of the app tree to
  `adversary4/runs/_hs_err_pid4193938.log`; no core dump was produced. Four older
  `hs_err_pid*.log` files predating this round were left untouched.
