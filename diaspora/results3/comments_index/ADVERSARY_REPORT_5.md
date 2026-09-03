# ADVERSARY REPORT — ROUND 5 — comments_index
`CommentsController#index`, `GET /posts/:post_id/comments`, anonymous AND signed-in.
Adversary run 2026-08-28/29 against the corpus **regenerated from scratch** by cycle 6 after
round 4's two wins (M-5 `users.language`, M-6 `posts.type`) and N4-3 (the cardinality /
preload-operator model, boundary item B-7) were closed.

Engine state under attack: `complete: true`, **0 missing**, **55 PC nodes**, **14 982 dumps**
(11 756 runs), assumptions **1 558/1 558 PASS**, shims **19 PASS / 11 PROTOCOL / 0 red**, note
check green; six SQL-consumer audits green; `hardening_lint` H1–H6 clean; the upgraded
projection judge (`PRED-OP-DIFF` / `LIMIT-DIFF` / `ORDER-DIFF`) **22 EXACT, 0 defects** over the
batch's runs and rounds 3–4.

Real app only: `concrete_env.rb` sqlite/JDBC + the app schema, fixture ROWS by raw `INSERT`,
real Devise `serialize_from_session`, real `ActionController::TestCase#process` (every
`before_action` runs), real templates. **No mocks, no stubs, no monkey-patches; nothing under
`src/`, the app, or the batch's runner / targets / mocks / manifests was touched.** Only fixture
rows, session, params, headers and format are under adversary control. The batch's six
`concrete_run*.json` are byte-identical before and after (`adversary5/runs/_batch_md5_before.txt`,
`md5sum -c` → 6/6 OK).

Manifests, run JSONs, logs, response bodies and judge outputs: `adversary5/` (`_common5.rb`
harness — round 4's `_common4.rb` with the tag changed and nothing else; `D01…D05.rb`, one
scenario per JRuby process; `run5.sh` / `chain5.sh`; `an5.py`; `runs/*.json|.log|.judge.txt|_body_*.txt`;
`runs/_progress.log`).

**5 manifests / 5 JRuby processes / 96 completed requests + 13 non-request probes.** No process
aborted the JVM this round (no scenario reaches `fix_profile` → Discovery — see §6).

---

## Verdict

**3 wins.** All three live in the shared association / finder boundary, so all three are
**TARGET-LEVEL** and belong in the PROPAGATION MATRIX.

* **W5-1 = ledger M-7 (Class B, S consequence)** — the preload predicate operator is driven by the OWNER
  LIST LENGTH; ActiveRecord drives it by the number of **DISTINCT** foreign-key values. Two
  comments by the SAME author is a length-2 list whose real preload is
  `SELECT "people".* … WHERE "people"."id" = ?` (and `"profiles"."person_id" = ?`); the corpus
  emits `IN (…)` for **every** state with `len > 1`, in 9 335 / 8 579 note events, and has
  **zero** states pairing `len > 1` with `=`. Worse, the corpus's MANY list is N copies of ONE
  representative row, so its own model of that state has exactly one distinct `author_id` — the
  operator it emits is the opposite of the one its own row model implies.
* **W5-2 = ledger M-8 (Class B, S consequence)** — the NESTED preload step inherits the outer step's `many`
  instead of following the number of PARENTS ACTUALLY LOADED. A comment with two mentions, one
  of them dangling (`mentions` has no FK — M-3), really issues
  `people.id IN (?, ?)` **then** `profiles.person_id = ?`. Corpus: **0** dumps pair an `IN`
  outer step with an `=` nested step (22 429 `=`/`=`, 8 579 `IN`/`IN`, **0** mixed).
* **W5-3 = ledger M-9 (Class S)** — **a finder that returns nothing loses its statement.**
  `finder_mock_faithful` does `next nil` on the `_not_found == True` arm; the interceptor takes
  a target's note from `#concolic_note` on the RETURNED value, and `nil` has none, so the
  `symbolic_call` event is written with **no note** — 3 210 finder calls plus 341
  `find_target` calls — 3 551 in all, in **2 960 of 14 982 dumps**. The SQL survives only on the
  `_not_found` decision VARIABLE, which the policy extractor explicitly skips as an outcome
  flag. Consequences, measured: the anon **404** run extracts to `n_queries_raw = 0` —
  "no SELECT queries recorded for this endpoint" — while the real request issues
  `SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? ORDER BY "posts"."id" ASC LIMIT 1`; and
  every signed-in read that ends on the PUBLIC arm extracts **without** the
  `posts INNER JOIN share_visibilities` read and **without** the `posts … author_id = <my
  person>` read that the real request issues first. This is exactly boundary item **B-6**, on
  the arm the `UninstantiableRow` repair did not cover.

Items **2a** (the three-valued language chain) and **2b** (the two-valued `posts.type`
decision) are **VERIFIED COMPLETE** — with positive evidence, not absence of evidence. Every
round-1..4 finding re-verifies clean on this corpus at projection level.

All five judged run files are green: `mock_note_check` `NOTE-OK`/`NOTE-OK*` only,
`note_fidelity_audit` **0 MISSING / STAR-OVER / AGG-COLLAPSE / PROJ-DIFF / PRED-OP-DIFF /
LIMIT-DIFF / ORDER-DIFF / PRED-DIFF**. None of the three wins is visible to either judge, and
that is part of each finding.

---

## 1. Re-verification of rounds 1–4, at projection level (incl. `=` vs `IN`, LIMIT, ORDER BY)

| # | prior finding | round-5 verdict on THIS corpus | evidence |
|---|---|---|---|
| **W1 / M-1** | `Post.exists?(guid:)` from `diaspora_links` — `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?` | **CLEAN (still closed)** | D04: 11 real `exists?` over 8 link-bearing renders (0/1/2/3 links, hit and miss, `web+diaspora://`, a `comment`-entity link, json + mobile + signed-in). Every one the single existence-probe shape, under frame `ActiveRecord::FinderMethods#exists?`; judge `NOTE-OK` + EXACT. Corpus: 8 `Anonymous.exists_probe` notes, `cols=8` (the existence bit, never `posts.*`), predicate `posts.guid`, `LIMIT 1`, four link positions `dlink_guid0..3` × `records`/`to_a`. |
| **W2 / M-2** | `:mobile` never explored | **CLEAN (still closed)** | Mobile driven in all five manifests by explicit format, by `session[:mobile_view]` + `format: :html` and by `X_MOBILE_DEVICE` + a mobile UA (D05). Corpus notes for the mobile comment relation: projection `comments.*`, predicates `commentable_id`/`commentable_type`, `ORDER BY created_at ASC` — EXACT. |
| **D1** | array-`post_id` / wrong `post_key` branch | **CLOSED** | D04: `post_id` of length 15 → `posts.id = ?` → 404; length 19 → `posts.guid = ?` → 200, exactly as `(Length(SYM_PARAM_post_id) < 16)` models. All six real post-finder predicate shapes seen again (`id`, `guid`, `id+author_id`, `guid+author_id`, `id+public`, `guid+public`), each with `ORDER BY "posts"."id" ASC LIMIT ?`. No `IN (…)` post predicate anywhere in 96 requests. |
| **D2 / M-5 (locale read)** | the principal `profiles` read of `set_grammatical_gender` | **CLEAN** | D02: the four available-locale principals (`pt-BR`, `de_formal`, `en-US`, `art-nvi`) and the `en` control issue **10 statements** and **no** principal `profiles` read; the `pl` arm (R4 C03, corpus 3 505 T) issues it. `pl` is the **only** available inflected locale — measured, see 2a. |
| **D3** | `people.diaspora_handle` over-emission | **CLOSED** | `Diaspora::Mentionable.people_from_string` traced in all five manifests: **0 calls** in 96 requests. No `people.diaspora_handle` predicate in any real statement. |
| **D4** | the `guid == ''` phantom decision | **CLOSED** | No `…_guid ==` path condition in the 55-node universe (full PC census over 14 982 dumps). |
| **D5** | `User has_one :person` pinned FOUND | **CLOSED** | Corpus carries `devise_user_first_1_person_not_found` in both polarities (341 True). NOTE: on that arm the read itself is now unrecorded — that is W5-3, not a regression of D5. |
| **D6 / N4-2** | `Post.exists?` per-render cardinality capped at 4 | **unchanged declared limit** | D04 reproduces 0/1/2/3; R4 measured up to 6. Corpus notes carry four link positions. |
| **D7** | `ConcreteEnv.insert` boolean quoting | **FIXED, re-verified** | D01/D02/D03/D04 all exercise the signed-in **public** arm for real (`posts.id = ? AND posts.public = ?` returns the row and the full render follows), on json and mobile, by id and by guid. |
| **D8** | `find_target` emitted in addition to the bulk preload | **CLOSED** | Across 96 requests the only real `find_target` statements are the principal's `people.owner_id … LIMIT ?` and (under `pl`) `profiles.person_id … LIMIT ?`. Zero `find_target` for comment authors, author profiles or mentioned people, at collection sizes 1, 2, 3 and 10. |
| **D9** | json variants had no collection-length decision | **CLOSED** | D04: empty json body `[]` (2 bytes) and empty mobile (68 bytes), **two statements each**; corpus records the length decision on both the `records` and the `to_a` reps. |
| **M-3** | dangling `mentions.person_id` → `[null]` json, **no** `profiles` read | **CLOSED — re-verified at projection level** | D04 `620`: json 200 with `"mentioned_people":[null]`; statement sequence `mentions …` → `SELECT "people".* WHERE "people"."id" = ?` → **STOP** (no `profiles`), twice (once per `mentioned_people` call); mobile identical. Live control `621` issues `people` **and** `profiles`. D01 `408`/`409` add the partially-dangling shapes. *Refinement:* the mobile **500** needs mention MARKUP in the text — a dangling mention with plain text renders 200 on mobile (D04 `620_mobile`, 865 bytes). The statement half — which is what the corpus carries — is unchanged. |
| **M-4** | preload notes over EMPTY relations | **CLOSED — re-verified at projection level** | D04: a post with zero comments issues **exactly two** statements (`posts … LIMIT ?`, `comments … ORDER BY created_at ASC`) on anon json, anon mobile, by guid, and on a private post shared with the principal (signed-in mobile). A comment with zero mentions issues the author preload and then two `mentions` SELECTs with **no** preload after either. |
| **M-5** | `users.language` third arm (`I18n::InvalidLocale`, one statement) | **CLOSED — re-verified, and the domain is now proved complete** | D02: five distinct invalid values (`"all"`, `"PL"`, `"pl-PL"`, `" pl"`, 250×`"z"`) each produce `I18n::InvalidLocale` and **exactly one statement** (`SELECT "users".* … LIMIT ?`). See 2a for why there is no fourth arm. |
| **M-6** | `posts.type` out-of-tree → finder, then stop | **CLOSED — re-verified through ALL FOUR finder arms** | D03: `Photo` reached through the anon `first` (public **and** private), through `querent_has_visibility` (share row), through `querent_is_author` (own private) and through `public_post`; json, mobile and by guid; 12 `SubclassNotFound`. Statement truncation exact: anon → 1 `posts` statement; auth-via-join → the join only; auth-own → join + author finder; auth-public → join + author + public finder. The corpus carries the decision on all four finder reps (71 True / 14 856 False) with matching truncated note multisets. |
| **B-2** | `escape_segment` demoted to a shim | **re-verified** | Traced in all five manifests; issued **0** SQL under its own frame. |
| **N3-5** | `Diaspora::NonPublic` | unchanged | D04: anon + private post → `401 (throw :warden)` with the post finder as the only statement, json and mobile. Out-of-tree + private + anon is `SubclassNotFound`, **not** 401 (D03 `431`) — the instantiation raise wins. |

---

## 2. The four NEW-WORK checks (brief items 2a–2d)

| # | check | verdict | evidence |
|---|---|---|---|
| **2a** | is the three-valued `users.language` chain complete — a locale that is available but not inflected, a malformed value, a very long value? | **COMPLETE — no fourth outcome. Verified positively, not by absence** | D02, 10 probes + 10 signed-in principals (one uid per arm — the warden memo is per-uid) + 9 anonymous header shapes. (i) `I18n.enforce_available_locales == true`, `I18n.available_locales.size == 138`, `AVAILABLE_LANGUAGE_CODES.size == 77`. (ii) **`I18n.available_locales.select { inflected_locale? } == ["pl"]`** — `pl` is not merely a witness, it is the whole inflected set for the callback that actually runs (`set_grammatical_gender` calls `inflected_locale?`, not `inflected_locales(:gender)`; the latter is `["all","pl"]` but **`:all` is not an available locale** — probe `all_is_available -> false` — so `language = "all"` raises rather than taking a fourth arm, confirmed live). (iii) Every malformed shape collapses onto the existing `xx` arm: `"all"`, `"PL"` (case), `"pl-PL"` (region-qualified), `" pl"` (whitespace), 250 characters — all `I18n::InvalidLocale`, all **one statement**. (iv) Every well-formed available value collapses onto the `en` arm: `"pt-BR"`, `"de_formal"`, `"art-nvi"` (offered) and `"en-US"` (available but NOT offered — the 61-element `available − offered` set) — all 200 with 10 statements and no principal `profiles` read. (v) **The ANONYMOUS arm of `set_locale`, which the corpus does not model at all, cannot raise**: `AVAILABLE_LANGUAGE_CODES − I18n.available_locales == []` (probe `OFFERED_MINUS_AVAILABLE -> []`), so `http_accept_language.language_region_compatible_from AVAILABLE_LANGUAGE_CODES` can only return a code `I18n.locale=` accepts. Driven for real with `Accept-Language` = `pl`, `xx`, `de_formal`, `art-nvi;q=1.0,en;q=0.5`, `*`, `,,,;q=`, `""`, a 5 200-byte header and `zh-TW,zh;q=0.9`: **all nine 200**, identical statement sets. |
| **2b** | is the two-valued `posts.type` decision enough — do in-tree subclasses produce evidence-identical runs, and does a Reshare with a missing root behave? | **ENOUGH — the real domain has exactly two evidence classes, and the whole in-tree set is enumerated** | D03, 20 requests + 3 probes. `Post.descendants == ["Reshare", "StatusMessage"]` and `Photo.superclass == ApplicationRecord` (probes), so the in-tree set is exactly `{Post, StatusMessage, Reshare}`. Real runs: `StatusMessage`, the literal base class `"Post"`, a `Reshare` with a **dangling** `root_guid` and a `StatusMessage` control — all 200 with **identical statement sets and identical response byte counts** at collection size 2 (665 bytes each), anon json and signed-in mobile; `#index` never touches the post beyond `public?` and `comments`. **A third real value class exists and is benign:** `type = ""` and `type = "   "` are NOT NULL-legal, and `using_single_table_inheritance?` tests `record[inheritance_column].present?`, so ActiveRecord instantiates the **base `Post`** — 200, statement-identical (probe `blank_type_class -> "Post"`). Out-of-tree stays one class regardless of message: `"Photo"` / `"Comment"` give "is not a subclass of Post", `"StatusMessage "` / `"statusmessage"` give "failed to locate the subclass" — same exception class, same truncation. |
| **2c** | does the `UninstantiableRow` poison hold for methods the batch did NOT enumerate — is there a call path that touches the row some other way? | **HOLDS on every real path of this endpoint (all four finder arms driven); the poison is nevertheless INCOMPLETE by construction — recorded as near-miss N5-1** | D03 drives an out-of-tree row through **every** finder the endpoint has — anon `first` on a public post (`post.public?`) and on a **private** post (same, the raise beats `Diaspora::NonPublic`), and all three `EvilQuery::VisibleShareableById` finders (`querent_has_visibility` via a `share_visibilities` row, `querent_is_author` via an own private post, `public_post`) whose consumer is `post.comments` — json, mobile, by id and by guid: **12 `SubclassNotFound`, no other outcome, and the truncation point matches the real app exactly in all four arms.** The residual risk is structural, not reachable here: `UninstantiableRow` raises only from `method_missing`, so every method **`Object`/`ActiveSupport` already defines** silently returns instead — `try` (→ `nil`, because `respond_to_missing?` is `false`), `present?`/`blank?`/`presence`, `in?`, `is_a?`/`instance_of?`, `nil?`, `==`/`eql?`/`hash`, `tap`, `then`, `itself`, `frozen?`, `dup`, `Kernel#Array()`. `find_public!` already routes the row through `Object#tap` (`post_service.rb:52`) — benign here only because the block immediately calls `post.public?`. See N5-1. |
| **2d** | does the 0/1/many cardinality hold at the boundary — exactly 2 authors, 2 mentions, and a list whose preload target REPEATS? | **NO — two wins, W5-1 and W5-2** | D01, 13 requests, purpose-built. See §4. Controls in the same process behave: 2 distinct authors → `IN (?, ?)`; 3 comments / 2 distinct authors → `IN (?, ?)` (the bind count follows the DISTINCT set, not the list); 1 comment → `= ?`; 2 live mentions → `IN (?, ?)` / `IN (?, ?)`. |

---

## 3. Scenarios (round 5)

| # | manifest | fixtures / request | status | mock_note_check | note_fidelity |
|---|---|---|---|---|---|
| D01 | `D01_preload_cardinality.rb` | 2 and 3 comments by the SAME author; 2 and 3 comments by 2 distinct authors; 1 comment; 1 comment with 2 live mentions; with 1 live + 1 dangling; with 1 live + 2 dangling; 2 comments with 1 mention each; signed-in json and signed-in mobile on a 2-comment one-author post whose author is the principal — 13 requests | 200 x13 | green | green (13 EXACT) |
| D02 | `D02_locale_domain.rb` | 10 non-request locale probes; 9 signed-in principals, one uid each, `language` = `all` / `PL` / `pl-PL` / `pt-BR` / `de_formal` / `en-US` / `" pl"` / 250 chars / `art-nvi`, plus an `en` control; 9 anonymous requests with `Accept-Language` = `pl`, `xx`, `de_formal`, `art-nvi;q=1.0,en;q=0.5`, `*`, `,,,;q=`, empty, a 5 200-byte header, `zh-TW,zh;q=0.9` — 19 requests + 10 probes | 200 x14, **`I18n::InvalidLocale` x5** | green | green (10 EXACT) |
| D03 | `D03_sti_poison.rb` | `posts.type` in {StatusMessage, `Post`, `""`, `"   "`, Reshare with a dangling root (2 comments), StatusMessage control (2 comments), Photo, Comment, `"StatusMessage "`, `"statusmessage"`}; the out-of-tree row reached through the anon finder on a PUBLIC and on a PRIVATE post and through all three `EvilQuery` finders (share-visibility, own, public); json + mobile + by guid; 3 STI probes — 20 requests + 3 probes | 200 x8, **`SubclassNotFound` x12** | green | green (11 EXACT) |
| D04 | `D04_reverify.rb` | re-verification: 0/1/2/3 `diaspora://…/post/<guid>` links (hits and misses), a `comment`-entity link, `web+diaspora://`, json + mobile + signed-in; a dangling mention and a live control; posts with 0 comments (anon json, anon mobile, by guid, private-shared signed-in mobile); a comment with 0 mentions; signed-in public arm; signed-in own arm; anon private (401); missing id (404); `post_id` length 15 vs 19; `format: :html` — 25 requests | 200 x20, 404 x2, `401(throw :warden)` x2, MissingTemplate x1 | green | green (12 EXACT) |
| D05 | `D05_wider.rb` | 10 comments / 4 distinct authors and 10 comments / 1 author (json + mobile); a post that is PUBLIC **and** share-visible; a share row with `hidden = true`; a post shared with ANOTHER user (auth 404, anon 401); a 3-comment mobile render mixing the principal's own person, a closed remote account and a third-pod author with 2 mentions, markdown, a setext heading, a bare URL, `#tag`, `<3` and a `diaspora://…/comment/<guid>` link; `format: :xml` and `:js`; `Accept: */*`; `session[:mobile_view]` + `format: :html` signed-in; `X_MOBILE_DEVICE` + a mobile User-Agent + `format: :html` signed-in; `post_id` = `""`, with a trailing newline, and a guid with a trailing space — 19 requests | 200 x13, 404 x3, `401(throw :warden)` x1, `UnknownFormat` x2 | green | green (17 EXACT) |

Depth-0 target calls across all five runs (2 232 total):
`Relation#records 1 234 · Relation#to_a 300 · FinderMethods#first 270 · escape_segment 267 ·
_set_rendered_content_type 68 · Metal#status= 58 · FinderMethods#exists? 26 ·
SingularAssociation#find_target 9`.
**No other target name fired at any depth** — in particular no `Person#fix_profile`,
`Mentionable.people_from_string`, `Discovery.new`, `Discovery#fetch_and_save`, `Base#reload`,
`Calculations#count`, `#pluck`, `Persistence#save`, or `CollectionProxy#records/#load_target`.
Every name that fired except `escape_segment` is a corpus target; `escape_segment` issued 0 SQL
under its own frame.

---

## 4. WINS (blocking)

### W5-1 — the preload predicate operator follows the LIST LENGTH; ActiveRecord follows the DISTINCT KEY COUNT  (Class B, S consequence) — **TARGET-LEVEL**

**Scenario.** `D01_preload_cardinality.rb`. Public post `401` with **two** comments **by the same
author** (person 2); post `402` with three comments by that one author; controls `403`
(two comments, two distinct authors), `404` (three comments, two distinct authors) and `405`
(one comment). anon json, anon mobile, and signed-in json + mobile (`406`, `411`).

**Real behaviour — the novel shape, verbatim.** For post `401` (list length 2, one distinct
author), on json, on mobile and signed-in:

```sql
SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? ORDER BY "posts"."id" ASC LIMIT ?
SELECT "comments".* FROM "comments" WHERE "comments"."commentable_id" = ? AND "comments"."commentable_type" = ? ORDER BY created_at ASC
SELECT "people".* FROM "people" WHERE "people"."id" = ?
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ?
```

— `= ?`, not `IN (…)`. Post `402` (length 3, one author) is identical. The controls confirm the
rule: `403`/`404` give `"people"."id" IN (?, ?)` and `"profiles"."person_id" IN (?, ?)`, i.e.
**one bind per DISTINCT author**, never per row.

Reproduced at scale in a second process: D05 post `651` — **ten** comments, one author — issues
`"people"."id" = ?` and `"profiles"."person_id" = ?` on json and on mobile, while its control
`650` — ten comments, four distinct authors — issues `IN (?, ?, ?, ?)` for both. The bind count
tracks the distinct set (4), never the row count (10).

**Issuing code.**

```ruby
# app/models/comment.rb:36-37
scope :including_author, -> { includes(:author => :profile) }
scope :for_a_stream,  -> { including_author.merge(order('created_at ASC')) }
```
```ruby
# activerecord-5.2.4.3 lib/active_record/associations/preloader/association.rb
def owners_by_key; @owners_by_key ||= owners.group_by { |owner| convert_key(owner[owner_key_name]) }; end
#   -> records_for(owners_by_key.keys)          # group_by => the keys are UNIQUE
# activerecord-5.2.4.3 lib/active_record/relation/predicate_builder/array_handler.rb
case values.length
when 0 then NullPredicate
when 1 then predicate_builder.build(attribute, values.first)   # <- equality, no IN, no LIMIT
else        attribute.in(values)
end
```

**Where the corpus forecloses it.**

```ruby
# targets.rb:125-128
def pred_op(ct, bindv, many)
  v = ct.render_arg_value(bindv)
  many ? "IN (#{v})" : "= #{v}"
end
# targets.rb:583-584   (rows_mock)
many = (lst.length > 1)
emit_includes_preloads(ct, receiver, rep, many: many)
```

`many` is the LIST LENGTH decision `(len(X) > 1)`. Cross-tabulating every
`Anonymous.load_intermediate` note in the 14 982 dumps against the `(len > 1)` decision of the
list that owns its bind:

| step | `=` | `IN` |
|---|---|---|
| outer (`people.id`) with `len > 1` **False** | **25 232** | 0 |
| outer (`people.id`) with `len > 1` **True** | **0** | **9 335** |
| nested (`profiles.person_id`) with `len > 1` **False** | **22 429** | 0 |
| nested (`profiles.person_id`) with `len > 1` **True** | **0** | **8 579** |

The operator is a strict function of the list length: the state "length ≥ 2, one distinct
author" — the commonest multi-comment state a real thread has — cannot be represented.

**And the corpus's `IN` note is inconsistent with the corpus's own row model.** The sampled list
carries ONE representative row (Gate-1b, unchanged by cycle 6: `rep = ct.symbolic_instance(…)`
once, `IterableSymbolicList.new(len, …, representative: rep)`). Every row of a modelled MANY
list therefore has the SAME `author_id`, so the statement the modelled state implies is `= ?` —
and the note is, verbatim:

```
SELECT "people".* FROM "people" WHERE "people"."id" IN ($$(SYM_RESULT_ActiveRecord__Relation_records_1_row_author_id))
```

a bulk `IN` over a **single** bind, which ActiveRecord never emits for any cardinality. The
cycle-6 repair got the operator exactly backwards relative to the row model it kept.

**Class S/B hypothesis.** Class **B** — `PredicateBuilder::ArrayHandler`'s `when 1` branch is a
data-dependent conditional on a fact the corpus has no variable for (the distinct-key count);
one fact has one variable (cross-endpoint rule 7) and here two different facts share one.
Class **S** consequence — in every length-≥2 one-author state the corpus asserts a bulk
`people.id IN (…)` / `profiles.person_id IN (…)` read the application does not issue.

**Why no check catches it.** `note_fidelity_audit` asks "is there a note of this shape anywhere
in the corpus"; both operators now exist corpus-wide, so a real `= ?` matches the `=` note and a
real `IN (?, ?)` matches the `IN` note. D01's judge run is **13 EXACT, 0 defects** while
containing four statements the corpus's model of their state cannot produce. The same blindness
M-4 had.

---

### W5-2 — the NESTED preload step inherits the outer step's cardinality instead of following the parents actually loaded  (Class B, S consequence) — **TARGET-LEVEL**

**Scenario.** `D01_preload_cardinality.rb`, post `408`: one comment with **two** `mentions` rows,
one pointing at a live person (5) and one at a **missing** person id (998) — `mentions` carries
no foreign key (`db/schema.rb:202-209`), which is M-3's reachability argument. Post `409`: three
mentions, one live and two dangling. Control `407`: two live mentions.

**Real behaviour — the novel shape, verbatim** (post `408`, per `mentioned_people` call):

```sql
SELECT "mentions".* FROM "mentions" WHERE "mentions"."mentions_container_id" = ? AND "mentions"."mentions_container_type" = ?
SELECT "people".*   FROM "people"   WHERE "people"."id" IN (?, ?)
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ?
```

— the outer step is bulk over the two `mentions.person_id` values, the nested step is
**equality** over the ONE person that came back. Post `409` gives `people.id IN (?, ?, ?)` then
`profiles.person_id = ?`. The control `407` gives `IN (?, ?)` then `IN (?, ?)`.

**Issuing code.** `lib/diaspora/mentions_container.rb:19` —
`mentions.includes(person: :profile).map(&:person)`; the nested `profile` preload is built from
the records the `person` step returned (`Preloader#preload` recurses over loaded records), so a
dangling FK shrinks the key set one level down.

**Where the corpus forecloses it.**

```ruby
# targets.rb:149  def emit_includes_preloads(ct, receiver, rep, many: false)
# targets.rb:194  emit.call(child, r2.klass, nested) if nested && child
```

`emit` is a closure over the method's `many:` argument; the nested call re-uses it. Over all
14 982 dumps, pairing each preload chain's outer and nested operator:

| outer → nested | dumps |
|---|---|
| `=` → `=` | 22 429 |
| `IN` → `IN` | 8 579 |
| **`IN` → `=`** | **0** |
| `IN` → (skipped, not-found) | present (756 dumps pair mentions-`many` with `person_not_found == True`) |

The corpus can express "all mentioned people found" and "none found", never "some found" — and
"some found" is the state whose nested statement differs. Round 4's C01 already recorded the real
pair (`people.id IN (?, ?)` → `profiles.person_id = ?`) in its M-3 row; nothing connected it to
the cardinality model, because the judge was blind to the operator at the time and is blind to
the *state* now.

**Class S/B hypothesis.** Class **B** — the number of loaded parents is a second data-dependent
fact with no corpus variable (it is the outer key count minus the not-found rows). Class **S**
consequence — the corpus asserts `profiles.person_id IN (…)` where the application issues
`profiles.person_id = ?`.

---

### W5-3 — a finder that returns nothing loses its statement: 3 551 noteless target calls, and the 404 run extracts to an EMPTY policy  (Class S) — **TARGET-LEVEL, boundary item B-6, nil arm**

**Scenario.** `D04_reverify.rb`: `post_id: "999999"` (anon json → 404) and
`post_id: "abcdefghijklmno"` (15 chars → `posts.id` key → 404); plus every signed-in request in
D01–D05 that ends on the PUBLIC arm.

**Real behaviour.** The 404 request's entire data access is

```sql
SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? ORDER BY "posts"."id" ASC LIMIT ?
```

and a signed-in read of a public post issues **three** post statements before the render
(D01 req 11, D02 segs 03/04/05/08, D03 seg 07, D04 segs 08–10):

```sql
SELECT posts.* FROM "posts" INNER JOIN "share_visibilities" ON "share_visibilities"."shareable_id" = "posts"."id" AND "share_visibilities"."shareable_type" = 'Post' WHERE "posts"."id" = ? AND "share_visibilities"."user_id" = ? ORDER BY "posts"."id" ASC LIMIT ?
SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? AND "posts"."author_id" = ? ORDER BY "posts"."id" ASC LIMIT ?
SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? AND "posts"."public"    = ? ORDER BY "posts"."id" ASC LIMIT ?
```

**The novel shape is an ABSENCE in the corpus's event stream.** The `symbolic_call` events for
the finders that returned nothing carry **no note at all** (raw dump,
`dump_anon_json_dse0003.json`):

```json
{"type": "symbolic_call", "target": "ActiveRecord::FinderMethods.first",
 "result_name": "SYM_RESULT_ActiveRecord__FinderMethods_first_1",
 "result_value": null, "result_sort": "Int", ... }        <-- no "note" key
```

Census over 14 982 dumps — noteless `symbolic_call` events whose statement the app really issues:

| target | noteless events |
|---|---|
| `ActiveRecord::FinderMethods.ci_vis_first` | **2 619** |
| `ActiveRecord::FinderMethods.ci_author_first` | **566** |
| `ActiveRecord::FinderMethods.ci_public_first` | 13 |
| `ActiveRecord::FinderMethods.first` | 12 |
| `ActiveRecord::Associations::SingularAssociation.find_target` | **341** |
| total | **3 551**, in **2 960 of 14 982 dumps** (2 382 dumps lose one statement, 565 lose two, 13 lose three) |

**Issuing code (the mock).**

```ruby
# targets.rb:258-267   finder_mock_faithful
not_found = symbool(nf_name, ct.seed_for(nf_name, false), note: sql)
if not_found == true
  raise ActiveRecord::RecordNotFound, "concolic: empty result for: #{sql}" if raise_on_missing
  next nil                      # <-- the note dies with the return value
end
```

The interceptor reads a target's note from `#concolic_note` on the RETURNED value (the
coordinator's own implementation note under "Boundary harvest"), and `nil` has none. The SQL
survives only on the `_not_found` decision **variable**.

**Why that is not enough.** The policy extractor is explicit
(`src/queries_from_runs/README.md`): *"For every `symbolic_call` event whose `note` is a
SELECT"*, and `transform.py:225` builds its producers from `run.symbolic_call_events` only;
`_not_found` is then classified as an **outcome flag** and skipped
(`skipped_pc_shapes` in the summary). Measured by running the real extractor:

```
$ build_endpoint_file(["dump_anon_json_dse0003.json"])          # the anon 404
EndpointSummary(n_queries_raw=0, n_queries_deduped=0, n_queries_final=0,
                skipped_pc_shapes={'(SYM_RESULT_..._first_N_not_found == True)': 1, ...})
-- no SELECT queries recorded for this endpoint
```

```
$ build_endpoint_file(["dump_auth_json_dse0059.json"])          # signed-in, public arm
9 queries; NEITHER a share_visibilities query NOR a posts…author_id query is among them
```

So for the 404 the extracted policy declares that the endpoint reads **nothing**, and for every
signed-in read that lands on the public arm it omits both the `share_visibilities` join and the
`posts.author_id = <my person>` read — two reads whose *predicates are the endpoint's entire
access-control logic*.

**Class S/B hypothesis.** Class **S**, swallowed evidence, and it is exactly the mechanism the
coordinator wrote down as **B-6** — "a mock that RAISES inside its `returns` lambda loses its own
statement note … Fix: return a poisoned value whose `concolic_note` the interceptor reads". Cycle
6 applied that to the RAISE arm (`UninstantiableRow`) and left the NIL arm, which is 3 551 times
more frequent. The batch even states the correct rule for the sibling path, in `targets.rb:180`:
*"the step's own statement IS still emitted above (the real preload issues the SELECT and gets
zero rows back)"* — the preload does it with `ConcolicThroughLoadProbe.load_intermediate(psql)`
BEFORE deciding not-found; the finder mock does not.

**Why no check catches it.** `note_fidelity_audit.py:122` and `mock_note_check` read notes from
`symbolic_call` events only, so a noteless event is invisible to both; and because other dumps
DO carry each shape from the found arm, `MISSING` can never fire. The `bind_resolution`,
`empty_relation_emission`, `identity_symbolicity` and `pc_visibility` audits *do* read
`symbolic_vars` notes — which is precisely why they stayed green while the producer stream lost
the statement.

---

## 5. Near-misses (real defects or unverified claims, no missing statement shape)

### N5-1 — the `UninstantiableRow` poison is incomplete by construction: everything `Object` defines returns silently  (TARGET-LEVEL, B-6 follow-up)

`UninstantiableRow` (`targets.rb:403-421`) is `Class.new do … end`, i.e. a plain `Object`
subclass that raises only from `method_missing` and answers `respond_to_missing?` with `false`.
Every method already defined on `Object`/`Kernel`/`ActiveSupport::Object` therefore does NOT
raise, and several of them return a value that makes the app carry on where the real app has
already blown up:

| call | mock | real (out-of-tree row) |
|---|---|---|
| `post.try(:public?)` | **`nil`** (`try` short-circuits on `respond_to?`, which is false) | never reached — `.first` raised |
| `post.present?` / `post.blank?` | `true` / `false` | never reached |
| `post.is_a?(Post)` / `instance_of?` | **`false`** | `true` (it is a `Photo`-typed `posts` row that failed to instantiate) |
| `post.nil?`, `post == x`, `hash`, `frozen?`, `dup`, `itself`, `then`, `Array(post)` | all answer normally | never reached |
| `post.tap { … }` | yields self, returns self | never reached |

On THIS endpoint the poison is safe: `find_public!` routes the row through `Object#tap`
(`app/services/post_service.rb:52`) but the block's first statement is `post.public?`, and the
signed-in path's first use is `post.comments` — both `method_missing`. D03 drove all four finder
arms and got `SubclassNotFound` every time with the real truncation point. It is recorded as a
near-miss because the class is shared: any endpoint whose first use of a found post is
`try`/`present?`/`is_a?`/`==` would silently proceed past a state the real app 500s in — and
"poison every method rather than the two call sites you happen to know" is the rule cycle 6
wrote for itself. A `BasicObject` subclass, or an explicit `raise` from the handful of `Object`
methods that can be observed, would make the claim true rather than call-site-lucky.

### N5-2 — a MANY collection's PER-ROW statements are still modelled per-representative (declared limit, now measured on the `mentions` family)

The cardinality repair made the PRELOAD (one statement per level per page) follow the list
length, but every statement the app issues **once per row** is still emitted once per
representative. Corpus, cross-tabulated:

| comment-list `(len > 1)` | dumps with 0 `mentions` notes | 1 | 2 |
|---|---|---|---|
| False | 105 | 4 789 | 6 223 |
| True | 69 | 1 818 | 1 769 |

i.e. **at most two `mentions` statements per dump at any cardinality**, while a real 2-comment
render issues **four** (D01 `401`: two comments × two `mentioned_people` evaluations) and a
10-comment json render issues **twenty** (D05 `650` and `651`, measured; mobile evaluates
`mentioned_people` once per comment, so ten). Same family as N4-2 (the `Post.exists?`
per-render count). Not a new shape — every `mentions` statement is shape-identical — and the
one-representative-row limit is declared; recorded because the multiset under-count now scales
with a dimension the corpus *does* model.

### N5-3 — `note_fidelity_audit` and `mock_note_check` read notes from `symbolic_call` events only  (INSTRUMENT)

Both judges harvest the corpus side from `symbolic_call` events (`note_fidelity_audit.py:122`).
The four SQL-consumer audits (`bind_resolution`, `empty_relation_emission`,
`identity_symbolicity`, `pc_visibility`) additionally read `symbolic_vars` notes. The two views
of "the corpus's notes" therefore disagree by 3 551 statements (W5-3), and the disagreement is
invisible: the audits see the SQL and pass, the judges do not see it and cannot report it
missing. A judge that also read var notes would still not have caught W5-3 (the extractor is
the consumer that matters), but it would have surfaced the split.

### N5-4 — both judges are state-blind, which is what W5-1/W5-2 exploit  (INSTRUMENT, extends N4-3)

The round-4 upgrade taught `note_fidelity_audit` to compare `=` vs `IN`, `LIMIT` and `ORDER BY`
— per SHAPE. It still asks only "does SOME corpus note have this shape", never "does the
corpus's model of the state this statement was issued IN produce this shape". Since cycle 6 the
corpus contains both operators, so every judge run this round is EXACT while four of D01's
statements come from a state the corpus models with the other operator. A state-level check
would need the run's own decisions (list length, not-found arms) alongside its statements — the
information is in the dumps, and `empty_relation_emission_audit` is the existing precedent for a
state-level (rather than shape-level) audit.

### N5-5 — M-3's mobile 500 needs mention MARKUP, not just a dangling row

Round 3/4 recorded "dangling `mentions.person_id` → `[null]` json / **500** mobile". The 500 is
`Diaspora::Mentionable.format`'s `people.find { |p| p.diaspora_handle == diaspora_id }` on a
list containing `nil`, and that runs only if the comment TEXT contains `@{…}` markup. D04 `620`
(dangling row, plain text) renders **200** on mobile (865 bytes) with the same statement
sequence. The statement half of M-3 — `people.id = ?` then STOP, no `profiles` — is unchanged
and re-verified; only the terminal half is conditional. Worth stating so a future round does not
read the 200 as a regression.

### N5-6 — the anon arm of `set_locale` is unmodelled but provably inert (positive result)

`set_locale`'s `else` branch (`application_controller.rb:103-106`) assigns `I18n.locale` from a
header the adversary fully controls, and the corpus has no variable for it at all. It cannot
raise, because `AVAILABLE_LANGUAGE_CODES − I18n.available_locales == []` (D02 probe) and
`language_region_compatible_from` can only return an element of that list; and it issues no
statement. Nine header shapes, including a 5 200-byte header and a malformed one, all 200 with
identical statement sets. Recorded as positive evidence so the propagation matrix's T-f row can
be closed for the anonymous half on this app rather than left unknown.

---

## 6. Unreachable / not attacked, and why

* **`Person#fix_profile` → `Discovery#fetch_and_save` → `reload`** — unreachable on this rig;
  cause diagnosed in round 4 (N4-1: `Faraday.default_adapter == :typhoeus` → Ethon → libcurl
  through JRuby's JFFI; the JVM dies on the first `HttpClient.get`, native heap corruption, not
  I/O). **No scenario this round was built to reach it, and no process aborted** — every
  fixture person that any render calls `.name` on has a `profiles` row. B-1's `reload` note and
  every `…_profile_not_found == True` arm therefore remain corpus- and code-verified only, for a
  stated reason.
* **`Reshare#root` / `absolute_root` / `o_embed_cache` / `open_graph_cache`** — D03 rendered a
  `Reshare` with a dangling `root_guid` at collection size 2, anon json and signed-in mobile,
  against a `StatusMessage` control: byte-identical bodies and identical statement sets.
  `#index` never touches the post beyond `public?` and `comments`. Unreachable by code.
* **`comments.commentable_type` naming the STI subclass** — the association scope binds the
  base-class literal `'Post'` (round 4, C06 post 376); nothing to add.
* **`comments.author_id` dangling** — `add_foreign_key "comments", "people", column:
  "author_id", on_delete: :cascade` (`db/schema.rb:624`) makes it not a database state, so the
  author preload's parent set can never shrink the way the mention preload's can (which is why
  W5-2 is reachable only through `mentions`).
* **Two `mentions` rows for the SAME person on one comment** — forbidden by
  `index_mentions_on_person_and_mc_id_and_mc_type` (UNIQUE on
  `person_id, mentions_container_id, mentions_container_type`, `db/schema.rb:207`), so the
  MENTION preload's owner keys are always distinct and W5-1's duplicate-key case is reachable
  only through `comments.author_id`, which has no such constraint. Stated because it is the
  reachability half of both wins.
* **`share_visibilities.hidden`** — `querent_has_visibility` joins on
  `shareable_id`/`shareable_type`/`user_id` only, so a row with `hidden = true` still grants
  access: D05 `653` (private post, hidden share row, signed in) renders 200 through the join
  finder. Positive evidence that the corpus's join note carries the right predicate set (it has
  no `hidden` conjunct). D05 `652` (a post that is public **and** share-visible) also confirms
  the short-circuit: the join finder matches, so the author and public finders are never issued.
* **`gon_set_current_user` → `UserPresenter`** — constructed on every signed-in request, never
  serialized (both renderable formats bypass the layout); no statement, confirmed again by the
  statement census of every signed-in request this round.
* **`format: :html`** → `ActionView::MissingTemplate` — and, newly measured, **after only the
  post finder**: `comment_service.find_for_post` returns an unmaterialized `Relation`, so the
  `comments` SELECT is never issued when no format block matches (D04 `610_html`: one statement).
* **`camo_urls` / `link_all_mentions` / `disable_hovercards` / `AppConfig.*`** — configuration,
  not fixture/param/header; out of the adversary's remit.
* **`params` other than `post_id`** — `CommentsController#index` reads no other parameter;
  `post_id` is a PATH segment, so array/hash shapes cannot reach the action (round 2, D1).

## 7. Harness notes

* Manifests live in `adversary5/`, so the probe writes `adversary5/concrete_run.json`; the
  batch's six `concrete_run*.json` are byte-identical before and after (`md5sum -c` → 6/6 OK,
  checked mid-round and at the end).
* `_common5.rb` is round 4's `_common4.rb` with the log tag changed and nothing else. It mocks,
  stubs and patches nothing; the only adversary-controlled inputs are fixture rows, session,
  params, headers and format.
* The per-uid warden memo caveat still applies: only the FIRST request per uid in a process is a
  clean principal differential, which is why D02 gives every language arm its own uid.
* Runs used `CONCRETE_COVERAGE=0`, `unset JAVA_TOOL_OPTIONS`, `flock /tmp/concolic-slot.lock`
  **inside** `systemd-run --user --pipe --wait -p MemoryMax=4000M -p MemorySwapMax=0`, one
  scenario per process, the chain itself inside a `systemd-run --user --unit=` service so a
  tool-call timeout cannot orphan it. Two other endpoints shared the machine-wide slot; every
  manifest's result was read from its own log and run JSON, never from the DONE marker.
