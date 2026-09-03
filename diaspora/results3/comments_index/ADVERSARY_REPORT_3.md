# ADVERSARY REPORT — ROUND 3 — comments_index
`CommentsController#index`, `GET /posts/:post_id/comments`, anonymous AND signed-in.
Adversary run 2026-08-28 against the corpus **regenerated from scratch** after cycle 4
closed the nine defects of round 2 and applied the coordinator's B-1/B-2 harvest.
Engine state under attack: `complete: true`, **0 missing**, **31 PC nodes** (was 59),
**4 965 dumps**, assumptions **489/489 PASS**, shims **19 PASS / 11 PROTOCOL / 0 red**,
note check green, and five SQL audits passing including the new DERIVED-MISBOUND check
and `pc_visibility --gate public,diaspora_handle,author_id,person_id`.

Real app only: `concrete_env.rb` sqlite/JDBC + the app schema, fixture ROWS by raw
`INSERT`, real Devise `serialize_from_session`, real `ActionController::TestCase#process`
(every `before_action` runs), real templates. **No mocks, no stubs, no monkey-patches;
nothing under `src/`, the app, or the batch's runner / targets / mocks / manifests was
touched.** Only fixture rows, session, params, headers and format are under adversary
control. The batch's own `concrete_run*.json` are byte-identical before and after
(`adversary3/runs/_batch_md5_before.txt`, re-diffed at the end: **BATCH RUNS UNCHANGED**).

Manifests, run JSONs, logs, response bodies and judge outputs: `adversary3/`
(`_common3.rb` harness, `B01…B11.rb` one scenario per process, `run3.sh` / `chain3.sh`,
`summarize.py`, `runs/*.json|.log|.judge.txt|_body_*.txt`, `runs/_ALL_note_fidelity.txt`,
`runs/_progress.log`).

**11 manifests / 11 JRuby processes / 68 completed requests** (3 processes aborted the
JVM before their first response — see §6).

---

## Verdict

**2 wins.**

* **W3-1 (Class B, with an S consequence)** — the `Mention belongs_to :person`
  *not-found* decision **disappeared from the corpus** when the cycle-4 **D8** repair
  routed the read through the preload. A dangling `mentions.person_id` is a real
  database state (`mentions` has **no** foreign key at all, `db/schema.rb:202-209`); it
  renders `"mentioned_people":[null]` with **200** on json and a **500**
  (`ActionView::Template::Error ← NoMethodError: undefined method 'diaspora_handle' for
  nil:NilClass`) on mobile. Neither the decision nor the terminal exists in any of the
  4 965 dumps. This is a **regression**: round 1 found it (N3), round 2 verified it
  CLEAN, cycle 4 removed it as a side effect of a different fix. Exactly the failure
  mode brief item **2d** asks about — the opposite of the double emission D8 fixed.
* **W3-2 (Class S — over-emission)** — the two `includes` preload notes are minted
  **unconditionally, before the list length is known**, so the corpus asserts a `people`
  read and a `profiles` read in **2 619** states where the producing relation is EMPTY
  and the real endpoint issues **nothing at all**. 2 353 dumps (47 % of the corpus) carry
  at least one such statement; 5 238 note events plus 3 080 decisions describe rows that
  do not exist. Both judges score the runs EXACT — **the check that catches this class
  does not exist**.

Both round-1 wins (W1 `Post.exists?` on `diaspora://…/post/<guid>`; W2 the `:mobile`
format with its depth-0 `Relation#to_a`) remain **closed by real runs on this corpus**,
and seven of the nine round-2 defects (D1, D3, D4, D5, D7, D8, D9) are **verified
repaired at projection level**. D2 and D6 are **verified NOT fully repaired**.

Combined judge over all eight judged run files:

```
== note_fidelity_audit: 8 run file(s), 21 distinct real SELECTs under 3 frames; 11 targets carry notes ==
-- MISSING: 0 --   -- STAR-OVER: 0 --   -- AGG-COLLAPSE: 0 --
-- PROJ-DIFF: 0 -- -- PRED-DIFF: 0 --   -- EXACT: 21 --
RESULT: every real statement has a projection-faithful note.
```

`mock_note_check` is green on all eight (`NOTE-OK` / `NOTE-OK*` only). So `complete: true`
survives round 3 **at the statement level for the states the corpus models**; what it
does not survive is the *shape of the explored universe* — one real state is missing from
it entirely (W3-1) and half of it describes reads the application does not perform (W3-2).

---

## 1. Re-verification of rounds 1 and 2, at projection level

Projection level = for each item: the statement's **projection** (named columns vs
`t.*` vs an existence bit vs an aggregate), its **predicate columns**, its **ordering**,
and the **mock's return kind**.

| # | round-1/2 finding | round-3 verdict on THIS corpus | evidence |
|---|---|---|---|
| **W1** | `Post.exists?(guid:)` from `diaspora_links` — `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?` | **CLEAN (still closed)** | B03: **26** real `exists?` statements over 12 requests, all `SELECT 1 AS one …`. Corpus: 3 probe notes (`Anonymous.exists_probe`, `cols=` — projection is the existence bit, **not** `posts.*`), predicate `posts.guid`, `LIMIT 1`; return kind is a **concrete bool** (`targets.rb:759`), matching the real `exists?`. Decisions `exists__1/2/3_exists` present in both polarities (1 288/2 515, 1 284/2 519, 956/1 817). `mock_note_check`: `NOTE-OK ActiveRecord::FinderMethods.exists?`. Residual: **cardinality**, see D6. |
| **W2** | `:mobile` never explored; depth-0 `Relation#to_a` with zero corpus events | **CLEAN (still closed)** | Depth-0 `ActiveRecord::Relation#to_a` observed in every mobile run (B01 4, B02 3, B03, B07, B10 3, B11 2 — **25** across the round). Mobile reached both by explicit `format: :mobile` and by the app's own `session[:mobile_view]` switch (`application_controller.rb:144-148`, B10: byte-identical 4 202-byte body to the explicit render). Corpus: 2 056 `Relation.to_a` events, 4 comment-relation notes, projection `comments.*`, predicates `commentable_id`/`commentable_type`, ordering `ORDER BY created_at ASC` — EXACT against the real statement. |
| **D1** | array-`post_id` family modelled the wrong `post_key` branch and is unreachable through the route | **CLOSED** | The string `posts"."id" IN` / `posts"."guid" IN` occurs in **0** of the 43 distinct corpus notes; `SYM_PARAM_post_id` is a scalar. `(Length(SYM_PARAM_post_id) < 16)` is now recorded in **all 4 965** dumps, both polarities (2 646 T / 2 319 F), and each of the four post finders carries **both** the `posts.id = $$(…)` and the `posts.guid = $$(…)` note with `ORDER BY "posts"."id" ASC LIMIT 1`. Real: B02 (`postguid2100000001`), B08 (`postguid2400000001` on all three visibility arms) — `posts.guid = ?` EXACT; numeric ids give `posts.id = ?` EXACT. |
| **D2** | the profiles read on the DEVISE PRINCIPAL has no note bound to it | **STILL OPEN — reconfirmed by a real differential** | B09 (`users.language = "pl"`) issues, under `SingularAssociation#find_target` and **before the action body**, `SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ? LIMIT ?`. B11 (same alice, `language = "en"`) issues **only** `people.owner_id`. The corpus's four `find_target` profiles notes bind comment authors and mentioned people, never `$$(SYM_RESULT_…devise_user_first_1_person_id)`. See **N3-1**. |
| **D3** | 9 219 `people.diaspora_handle` events for the `persisted? == false` arm | **CLOSED** | No `mention_lookup_*` target and no `people.diaspora_handle = …` note survives in the corpus (43 distinct notes checked). `Diaspora::Mentionable.people_from_string` was traced in all 11 manifests and fired **zero** times in the 8 completed runs. Rule G: `persisted` left the gate list and has a ledger entry. |
| **D4** | the `guid == ''` decision family | **CLOSED** | No `…_guid ==` path condition anywhere in the 31-node universe; `symbolic_instance` pins every `guid` / `*_guid` column concrete (`concolic_targets.rb:374-379`) and no query on this endpoint binds a rep's guid column — the post finders bind `SYM_PARAM_post_id`, the link probes bind `SYM_PARAM_dlink_guid*`. Ledger entry present, gate excludes `guid`. |
| **D5** | `User has_one :person` pinned FOUND over a reachable 500 | **CLOSED** | See **§2 (2c)** — B11 reproduces both arms exactly as modelled. |
| **D6** | `Post.exists?` capped at one probe per dump | **PARTIALLY repaired — see N3-2** | Corpus per-dump probe counts are now `{0: 1 162, 2: 1 030, 3: 2 773}`. Real per-render counts observed: **0, 1, 2, 3 and 5**. Cardinality **1** and **≥ 4** are still not expressible. |
| **D7** | INSTRUMENT: `ConcreteEnv.insert` wrote booleans as `1`/`0` | **FIXED and verified** | `ConcreteEnv.quote` now delegates to `c.quoted_true/quoted_false`. B08 reaches the signed-in **public** arm from a plain `public: true` fixture row for the first time on any batch — `SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? AND "posts"."public" = ? ORDER BY "posts"."id" ASC LIMIT ?` returns the post and the full render follows (json 200, mobile 200, and by 18-char guid). B07 reproduces it independently on a public `Reshare`. |
| **D8** | `find_target` emitted *in addition to* the bulk preload | **CLOSED for the double emission; it CAUSED W3-1** | Across the 8 completed runs the **only** real `find_target` statements are `SELECT "people".* … WHERE "people"."owner_id" = ? LIMIT ?` (the principal) and, under `pl`, the principal's `profiles`. Zero for comment authors, author profiles or mentioned people — B10 with 4 comments / 4 distinct authors / 3 mentions issues `people.id IN (?, ?, ?, ?)` + `profiles.person_id IN (?, ?, ?, ?)` once each and **no** `find_target`. See §2 (2d) for the read-loss check, and W3-1 for what the attach removed. |
| **D9** | json variants had no comment-collection length decision | **CLOSED** | `(len(SYM_RESULT_…records_1_rows) != 0)` is now recorded in both polarities on **anon_json** (1 161 T / 24 F) and **auth_json** (1 646 T / 62 F) as well as on both mobile variants. Real empty-json state confirmed in B02: body `[]`, 200, **only** the post finder and the comments SELECT. |
| **N8 / C08-C10** | signed-in public branch; the no-profile → discovery path | public branch **closed** (D7 above); discovery path **still unjudgeable**, see §6 |

---

## 2. The four NEW-MODELLING checks (brief items 2a–2d)

| # | check | verdict | evidence |
|---|---|---|---|
| **2a** | `Discovery.new` demoted from TARGET to SHIM: a real run must mint **no note** for it, while `fetch_and_save` still carries its decision | **CORPUS-VERIFIED; NOT verified by a real run** | Corpus target census over all 4 965 dumps: no `Discovery.new`, no `Anonymous.new`, **0 notes** — the old opaque `Anonymous.new` note is gone (H3 green). `CommentsInertDiscovery.fetch_and_save` survives as the wall: **2 236** events, note `DiasporaFederation::Discovery#fetch_and_save (discovered person; network wall, no SQL)`, `_discovery_failed` decision in both polarities on three reps (195/920, 262/567, 72/749) and both terminals recorded (`DiscoveryError` 457, `Template::Error ← DiscoveryError` 72). Return kind matches the real gem: a `Person` or a raise (`discovery.rb:19-30`). **Real-run part is missing**: `DiasporaFederation::Discovery::Discovery.new` and `#fetch_and_save` were explicitly traced in all 11 manifests and fired at depth 0 in **none** of the 8 completed runs (no missing-profile fixture in them); the three manifests built to reach them (B04/B05/B06) all abort the JVM (§6). The shim claim therefore still rests on the batch's shim test plus code reading, exactly as B-1 `reload` does. |
| **2b** | the three `exists?` probes must match the real cardinality for one, two and three `post` links, plus a `comment` link that issues nothing | **PARTIAL — see N3-2** | B03, anon, json + mobile. 1 link → **1** probe; 2 links → **2**; 3 links → **3**; `comment`-entity link only → **0** probes and the link is left unrewritten in the body (`diaspora://bob@remote.example/comment/existsguid00000001`); 4 `post` links + a `web+diaspora://…/post/…` → **5**; two comments each carrying one link → **2** per render. 26 real `exists?` statements in total, all `NOTE-OK` / EXACT. The corpus models `{0, 2, 3}` only. |
| **2c** | `User has_one :person` decision — a signed-in user with no `people` row | **VERIFIED** | B11, user 8 `gina` (no `people` row; `people.owner_id` has no FK to `users`). Post 280 visible through `share_visibilities` → **200**, `person` never read. Posts 281 (not visible) and 282 (public, not hers) → `NoMethodError: undefined method 'id' for nil:NilClass` at `lib/evil_query.rb:116-118`, on **json and mobile**, with only the share-visibility join issued and the author/public SELECTs **never** issued. Corpus matches exactly: `devise_user_first_1_person_not_found` 240 T / 2 016 F, the `find_target` note `SELECT "people".* FROM "people" WHERE "people"."owner_id" = $$(…) LIMIT 1` (projection `people.*`, predicate `people.owner_id`, `LIMIT 1`, return kind row-or-nil), and the `NoMethodError` terminal on **both** `auth_json` (2) and `auth_mobile` (2). |
| **2d** | the preload/`find_target` change — check **no read is lost** now that the loaded target is attached | **VERIFIED for reads; a DECISION was lost — W3-1** | Reads: in every completed run the statement multiset after `includes(author: :profile)` / `mentions.includes(person: :profile)` is exactly one `people` SELECT and one `profiles` SELECT per preload step, with **no** follow-up `find_target` for `comment.author`, `author.profile`, `mention.person` or `person.profile` — which is what real AR does. The one place real AR *does* re-read (after `Person#reload` clears the association cache) is still modelled by `find_target` (2 236 corpus events, exactly matching the 2 236 `reload` events). So no read is lost. **But** the attach also bypassed the `Mention belongs_to :person` not-found decision at `targets.rb:806`, which is now dead code — W3-1. |

---

## 3. New scenarios (round 3)

| # | manifest | fixtures / request | status | mock_note_check | note_fidelity |
|---|---|---|---|---|---|
| B01 | `B01_dangling_mention.rb` | `mentions.person_id = 999` (no such person): with no mention markup, with markup, an all-present control, and a mixed comment (one live + one dangling mention). anon json/mobile ×4 + auth json | 200 ×7, **500 ×2** | green | green (11 EXACT) |
| B02 | `B02_empty_collections.rb` | a post with **zero** comments (anon json/mobile, auth json, by guid), a comment with **zero** mentions, a private post shared with alice and zero comments | 200 ×8 | green | green (11 EXACT) |
| B03 | `B03_exists_cardinality.rb` | comments carrying 1 / 2 / 3 / 5 `diaspora://…/post/<guid>` links (hits and misses), a `comment`-entity link only, and two comments each with one link. anon json + mobile | 200 ×12 | green | green (6 EXACT) |
| B04 | `B04_fixprofile_ip.rb` | comment author with **no `profiles` row**, `diaspora_handle` domain = `127.0.0.1` (loopback, no DNS). Isolated process | **JVM abort, exit 134** (SIGSEGV, `MixedModeIRMethod.call`) | — | — |
| B05 | `B05_fixprofile_nodomain.rb` | same, handle `dave@` → `Discovery#domain` is `nil`, **no socket is possible**. Isolated process | **JVM abort, exit 134** (`free(): invalid pointer`) | — | — |
| B06 | `B06_mobile_mention_noprofile.rb` | mobile; mention markup with **no display name** (`@{dave@127.0.0.1}`) of a person with no profile → `person.name` → `fix_profile`. Isolated process | **JVM abort, exit 134** (SIGSEGV, `Klass::method_at_vtable`) | — | — |
| B07 | `B07_sti_posts.rb` | `posts.type` ∈ {StatusMessage, Reshare with dangling `root_guid`, Reshare with a real root, `Photo`, `Bogus`}, plus a comment whose `commentable_type` is the STI **subclass** name. anon json/mobile ×12 + auth json | 200 ×7, `SubclassNotFound` ×4, 200 (`[]`) ×2 | green | green (10 EXACT) |
| B08 | `B08_visibility_matrix.rb` | the full `VisibleShareableById#post!` matrix with the fixed boolean quoting: public / shared / own / none / missing, by id and by 18-char guid, signed-in and anon, json + mobile + html | 200 ×7, 404 ×3, `401(throw :warden)` ×2, MissingTemplate ×1 | green | green (13 EXACT) |
| B09 | `B09_locale_principal.rb` | `users.language = "pl"` (inflected locale) signed-in, json + mobile | 200 ×2 | green | green |
| B10 | `B10_wide_render.rb` | 4 comments by 4 authors (closed account with a blank-name profile; alice's own comment → delete link + `self`), markdown + setext heading + bare URL + `#tag` + `<3`, one comment with **3 mentions** incl. two other pods. anon/auth × json/mobile + the `session[:mobile_view]` switch | 200 ×5 | green | green (12 EXACT) |
| B11 | `B11_orphan_user.rb` | signed-in user 8 `gina` with **no `people` row**: visible post, non-visible post, public post; json + mobile; alice as control | 200 ×3, `NoMethodError` ×3 | green | green |

68 completed requests over 8 judged processes; `runs/_progress.log` has the per-manifest
DONE lines. Depth-0 target calls across all runs:
`escape_segment 213 · Relation#records 126 · FinderMethods#first 104 ·
_set_rendered_content_type 53 · Metal#status= 33 · FinderMethods#exists? 26 ·
Relation#to_a 25 · SingularAssociation#find_target 9`. Every one of them except
`escape_segment` is a corpus target; `escape_segment` is the cycle-3 B-2 demotion and
issued **zero** SQL under its own frame in all 8 runs (only three frames ever issued SQL:
`Relation#records` 383, `exists?` 26, `find_target` 9) — **B-2 re-verified on the new
corpus**.

---

## 4. WINS (blocking)

### W3-1 — the `Mention belongs_to :person` NOT-FOUND decision was removed by the D8 repair; the dangling-mention state is invisible again  (Class B, with an S consequence)

**Scenario.** `B01_dangling_mention.rb`. Fixtures: public post 201, one comment 301 with
`text = "hello @{Ghost; ghost@remote.example} goodbye"` and one `mentions` row
`(mentions_container_id: 301, mentions_container_type: "Comment", person_id: 999)` where
no `people` row 999 exists. Requests: anon `format: :json` and anon `format: :mobile`
(also post 200 with the same dangling mention but **no** markup, post 203 with one live
and one dangling mention, and the signed-in json variant).

**Real behaviour.**

```
[adv3] B01_markup_json   anon json   post_id="201" -> 200 (377 bytes)
[adv3] B01_markup_mobile anon mobile post_id="201" -> EXC ActionView::Template::Error:
                                     undefined method `diaspora_handle' for nil:NilClass
[adv3] B01_mixed_json    anon json   post_id="203" -> 200 (615 bytes)
[adv3] B01_mixed_mobile  anon mobile post_id="203" -> EXC ActionView::Template::Error: …
```

json body (verbatim, `runs/_body_B01_markup_json.txt`):

```json
[{"id":301,"guid":"cguid301","text":"hello @{Ghost; ghost@remote.example} goodbye",
  "author":{…},"created_at":"…","mentioned_people":[null]}]
```

and for the mixed comment: `"mentioned_people":[{…bob…},null]`.

**The novel call shape is an ABSENCE.** In this state the real run issues the mention
preload and then **stops**:

```sql
SELECT "people".* FROM "people" WHERE "people"."id" = ?          -- returns 0 rows
-- and NO  SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" IN (…)
```

(measured over B01's nine requests: **14** real `mentions` loads, of which **8** preload a
`person_id` with no `people` row — and not one of those 8 is followed by a `profiles`
read. The 11 single-id mention preloads issue `people.id = ?`; only the 3 that found a
person are followed by `profiles.person_id = ?`. The two mentions of post 203 give
`people.id IN (?, ?)` → 1 row → one `profiles` read.)
The corpus emits the `profiles` note **unconditionally** for every mention preload, because
`emit_includes_preloads` has no not-found arm on the `belongs_to` side.

**Issuing code.**

```ruby
# lib/diaspora/mentions_container.rb:17-23
def mentioned_people
  if persisted?
    mentions.includes(person: :profile).map(&:person)   # <- may contain nil
```
```ruby
# lib/diaspora/mentionable.rb:33-35            (mobile: markdownified -> render_mentions)
  msg_text.to_s.gsub(REGEX) {|match_str|
    name, diaspora_id = mention_attrs(match_str)
    person = people.find {|p| p.diaspora_handle == diaspora_id }   # <- 500 on nil
```
```ruby
# app/presenters/comment_presenter.rb:17       (json)
  mentioned_people: @comment.mentioned_people.as_api_response(:backbone)   # -> [null]
```

**Where the corpus lost it.** Round 2's corpus had `records_2_row_person_not_found` /
`records_3_row_person_not_found` (2 996 / 2 848 dumps) and a
`concolic_terminal {ActionView::Template::Error ← NoMethodError}` in 294 dumps. In the
regenerated corpus there is **no `…_row_person_not_found` path condition at all** — the
only `_not_found` families left are the finders, `…_profile_not_found` (the has_one step)
and `devise_user_first_1_person_not_found` — and the three recorded terminals are
`DiscoveryError` (457), `Template::Error ← DiscoveryError` (72) and `NoMethodError` (4,
the `gina` one). The cause is the D8 fix:

```ruby
# targets.rb:100-121  emit_includes_preloads
if r2.belongs_to? || r2.macro == :has_one
  if r2.macro == :has_one
    nf = "#{base}_not_found"
    child = (symbool(nf, ct.seed_for(nf, false), note: psql) == true) ? nil : ct.symbolic_instance(…)
  else
    child = ct.symbolic_instance(r2.klass, base, psql)   # belongs_to: ALWAYS FOUND
  end
  mark_loaded(owner_rep, r2.name, child)                 # <- and now it is attached,
end                                                      #    so find_target never runs
```

and the decision that used to model the state is now unreachable dead code:

```ruby
# targets.rb:806  (§8c SingularAssociation#find_target)
decided = owner.is_a?(Mention) && refl.name == :person # mentions.person_id: no FK
```

**Class S/B hypothesis.** Class **B** — a data-dependent conditional (`person.present?`
inside `Array#find`, and `as_api_response` on a nil element) executes in the real app and
no path condition is recorded for it, so DSE cannot flip it; the 500 outcome and the
`[null]` body are outside the explored universe. Class **S** consequence — in that state
the corpus mints a `profiles` preload statement the real run does not issue, and the fold
gets a producer edge for a row that does not exist. Both judges score B01 EXACT, so
**the check that catches this class does not exist**; the cheapest one is a rule that
every `belongs_to` preload step on a column with **no foreign key** must carry a
not-found decision, mirroring the has_one arm.

**Why it is blocking.** `complete: true` asserts every call the endpoint can make in
every shape is in the corpus. Here a real, FK-unconstrained database state produces a
different response body (json), a different terminal (mobile 500) and a *smaller*
statement set than any corpus dump — and it is a defect the batch had already fixed once.

---

### W3-2 — the `includes` preload notes are emitted over EMPTY relations: 5 238 note events for reads the endpoint never issues  (Class S, over-emission)

**Scenario.** `B02_empty_collections.rb` and `B10_wide_render.rb`.
B02 fixtures: post 210 public with **zero** comments; post 211 public with one comment and
**zero** mentions; post 212 private + `share_visibilities` for alice with zero comments.
Requests: anon json, anon mobile, auth json, auth mobile, and by 18-char guid — 8 in all.

**Real behaviour.** Eight requests, **27 statements total**. Six of the eight requests hit
an empty comments list; for those the entire data access is

```sql
SELECT "posts".*    FROM "posts" WHERE "posts"."id" = ? ORDER BY "posts"."id" ASC LIMIT ?
SELECT "comments".* FROM "comments" WHERE "comments"."commentable_id" = ?
                    AND "comments"."commentable_type" = ? ORDER BY created_at ASC
```

— body `[]` (2 bytes) on json, an empty `<ul>` (68 bytes) on mobile — and **no `people`
read, no `profiles` read, no `mentions` read**. The two requests with one comment and no
mentions issue the author preload (`people.id = ?`, `profiles.person_id = ?`) and then
three `mentions` SELECTs that return nothing and are followed by **no** preload at all.
B10 shows the same at scale: **28** real `mentions` loads, of which only **7** (the
3-mention comment) produce a preload; the other **21** produce zero statements.

**The over-emitted shapes, verbatim from the corpus** (e.g. `dump_anon_json_dse0014.json`,
whose `(len(SYM_RESULT_ActiveRecord__Relation_records_1_rows) != 0)` is **False**):

```
Anonymous.load_intermediate
  SELECT "people".*   FROM "people"   WHERE "people"."id"          IN ($$(SYM_RESULT_ActiveRecord__Relation_records_1_row_author_id))
Anonymous.load_intermediate
  SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" IN ($$(SYM_RESULT_ActiveRecord__Relation_records_1_row_author_id))
```

**Issuing code.**

```ruby
# targets.rb:388-415  rows_mock  (declared for Relation#to_a/#to_ary/#records
#                                and CollectionProxy#records/#load_target)
rep = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", sql)
emit_includes_preloads(ct, receiver, rep)     # <- unconditional; the length is only
…                                             #    decided by IterableSymbolicList below
IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn, note: sql, representative: rep)
```

The real counterpart (`activerecord-5.2.4.3` `Associations::Preloader#preload`) preloads
**from the loaded records**: zero records ⇒ zero statements. `emit_includes_preloads` runs
before the list length exists, so the preload is asserted in every state including the
empty one.

**Scale, measured over all 4 965 dumps.**

| empty relation | dumps | over-emitted note events |
|---|---|---|
| `records_1` (comments in json / mentions in mobile) | 732 | 1 464 |
| `records_2` (mentions, 1st `mentioned_people` in json) | 968 | 1 936 |
| `records_3` (mentions, 2nd `mentioned_people` in json) | 830 | 1 660 |
| `to_a_1` (comments in mobile) | 89 | 178 |
| **total** | **2 619 occurrences in 2 353 distinct dumps (47 % of the corpus)** | **5 238** |

and the same non-existent rows carry decisions:
`…_row_person_profile_not_found` 2 444, `…_row_author_profile_not_found` 175,
`…_row_text_has_mention` 175, `…_row_text_has_dlink` 175, `…_row_text_dlink_is_post` 111.

**Class S/B hypothesis.** Class **S** in the over-approximating direction: the policy
inherits a `people`/`profiles` read (and a producer edge into the fold) in states where
the application performs no read at all, and the fold sees attribute decisions on a row
that no query returned. Cross-endpoint rule 6 ("over-emission counts too") and rule 7
("one fact, one variable") both apply: the representative row and the list length are
seeded independently, so the corpus can hold `len(rows) == 0` **and** a fully-attributed
row at the same time — the same shape as the conversations `count > 0 ∧ rows = []`
near-miss. Both judges are EXACT on the real runs because they compare *shapes*, never
*multiplicities or reachability*; the missing check is "a note whose producing relation is
empty in the same dump".

---

## 5. Near-misses (real defects, no missing statement shape)

### N3-1 — `users.language` is neither PC-visible nor in the pin ledger, and the principal's profile read is chained onto the wrong producer  (round-2 D2, still open; Rule G violation)

```ruby
# app/controllers/application_controller.rb:118-122   (before_action :set_grammatical_gender)
if (user_signed_in? && I18n.inflector.inflected_locale?)
  gender = current_user.gender.to_s...       # Person#profile -> profiles SELECT
```

B09 (`users.language = "pl"`) vs B11 (`"en"`, same alice) is a clean differential: the
`pl` run issues, under `SingularAssociation#find_target` and **before the action body**,

```sql
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ? LIMIT ?
```

which the `en` run does not. In the corpus, `language` is minted as a symbolic string
(`_language`, 3 216 mints) whose concrete value is the placeholder
`SYM_RESULT_…_language_v` — not an inflected locale — so `inflected_locale?` is never
true and the branch is never recorded. `pc_visibility_audit`'s blind-vars census lists
`_language` among the never-referenced names.

Two consequences. (i) **Class B**: the branch is invisible, so the whole
`set_grammatical_gender` read is outside the universe. (ii) **Rule G (DISCIPLINE §11)**:
the gate list is `public, diaspora_handle, author_id, person_id` and the pin ledger covers
`persisted`, `guid`, `commentable_type`, `mentions_container_type`, `shareable_type`,
`text`. `users.language` — a column whose value the app branches on — is in **neither**,
which is exactly the case §11 calls "a decision quietly dropped from the gate list without
a ledger entry". (`run_dse.rb:103-104` still contains an explicit `language`/`gender` pin
in `symbolic_user_ci`, but that helper is **dead code** — the auth corpus resolves through
real Devise at `run_dse.rb:217-218` — so the pin comment does not license the gap either.)
At fold level the principal's profile read, when it happens, is chained onto the
comment-author chain (violation-5 class), because the four corpus `find_target` profiles
notes bind only `records_1/3_row_*_id` and `to_a_1_row_author_id`.

### N3-2 — `Post.exists?` cardinality is still `{0, 2, 3}`; the real endpoint issues 1, and 4+  (round-2 D6, half-repaired)

`targets.rb:566-598` builds the comment text with exactly **three** `post` links plus one
`comment` link, and the `_text_dlink_is_post` decision turns the *first* link into a
`comment` one — so the only per-dump probe counts the corpus can express are 0, 2 and 3
(measured over 4 965 dumps: `{0: 1 162, 2: 1 030, 3: 2 773}`). B03 observes 0, 1, 2, 3 and
5 per render:

```
post 220 (1 post link)                          -> 1 exists? per render
post 221 (2 post links, 1 hit 1 miss)           -> 2
post 222 (3 post links)                         -> 3
post 223 (comment-entity link only)             -> 0   (link left unrewritten in the body)
post 224 (4 post links + 1 web+diaspora post)   -> 5
post 225 (2 comments, one link each)            -> 2   (per-comment multiplicity)
```

Statement-shape neutral (all 26 are `NOTE-OK`/EXACT), multiset-unfaithful — the D1 sense
of "as a multiset". The cardinality-1 case matters most: it is the *commonest* real shape
and the corpus cannot produce it at all.

### N3-3 — the mention display name is pinned, so the mobile mention person's `profile_not_found == True` arm mints no consequence  (Class B, code-reading; unverifiable on this rig)

`targets.rb:562` always builds `@{Concolic Mention; <handle>}` — **with** a display name.
`MentionsInternal.mention_link` (`lib/diaspora/mentionable.rb:107-112`) then takes
`person_link(person, …, display_name: display_name)` and `PeopleHelper#person_link`
(`app/helpers/people_helper.rb:28-33`) uses `opts[:display_name] || person.name`, so
`Person#name` — and therefore `Person#fix_profile` — is **never** reached for a *mobile*
mention person. The corpus reflects this exactly: `records_1_row_person_profile_not_found`
is a recorded decision (739 T / 1 156 F) whose True arm emits **nothing**, while the json
side (`records_3`, where `as_api_response` calls `name` unconditionally) carries the full
`fetch_and_save` → `reload` → `find_target profiles` chain. A real comment with
`@{handle}` (no display name) and a profile-less mentioned person would issue
`SELECT "people".* … WHERE "people"."id" = $$(…records_1_row_person_id) LIMIT 1` and
`SELECT "profiles".* … WHERE "profiles"."person_id" = $$(…records_1_row_person_id) LIMIT 1`
— shapes the corpus has, but bound to a rep it never binds them to (a D2-class fold
defect). `B06_mobile_mention_noprofile.rb` was built to prove it and aborted the JVM (§6),
so this stays a near-miss, not a win.

### N3-4 — `concrete_aliases.json` still maps four targets the corpus no longer contains

`ActiveRecord::FinderMethods.find_by → [mention_lookup_msg_first, mention_lookup_json_first,
mention_lookup_msg_retry, mention_lookup_json_retry]`. The D3 repair removed that whole
family from the corpus (0 events, 0 notes); the alias file is stale. Harmless today —
the judges only widen matching — but a stale alias silently makes future NOTE-MISMATCH
verdicts weaker, and `note_fidelity_audit` still prints `notes=…` rows for targets with
no events in some judge outputs.

### N3-5 — the `Diaspora::NonPublic` outcome is modelled by four dumps that simply stop

For anon + non-public, `post_service.rb:54 raise Diaspora::NonPublic` is rescued into
`authenticate_user!` (`comments_controller.rb:16-18`). B08 confirms the real behaviour
(`401(throw :warden)`, zero statements beyond the post finder) and the corpus's four
dumps end after `(…first_1_public == True)` is taken False with no terminal and no
`Metal.status=`/`head` event — faithful for data access, but the outcome itself is
unlabelled, unlike the three terminals that are recorded. Recorded here so the asymmetry
is deliberate rather than accidental.

---

## 6. Unreachable / not attacked, and why

* **`Person#fix_profile` → `Discovery.new` → `fetch_and_save` → `reload`.** Three fresh
  isolated processes, three different fixture shapes, **three different JVM aborts**:
  B04 (`dave@127.0.0.1`, a literal loopback address — no DNS lookup) SIGSEGV in
  `MixedModeIRMethod.call`; B05 (`dave@`, `Discovery#domain` is `nil` so **no socket is
  reachable at all**) `free(): invalid pointer`; B06 (mobile mention path)
  SIGSEGV in `Klass::method_at_vtable`. All exit 134 before the first response.
  Two things follow. (i) B-1 `reload` and the `Discovery.new` shim demotion (2a) remain
  **unverified by any real run**, as round 2 already recorded. (ii) The standing
  explanation — "the network path aborts the JVM" — is **not established**: B05 cannot
  reach a socket and aborts anyway, so the abort is in the JRuby/JIT execution of that
  code path, not in I/O. (My two `hs_err_pid*.log` files were removed; no core dump was
  produced.)
* **`Reshare#root` / `absolute_root`.** B07 rendered a `Reshare` with a dangling
  `root_guid` and one with a real root, json and mobile, anon and signed-in: **identical**
  statement set to a `StatusMessage`, 200 in all cases. Nothing on `#index` touches
  `root`, `text`, `message` or `o_embed_cache` of the post. Unreachable by code.
* **`posts.type` outside the STI tree.** `Photo` → `ActiveRecord::SubclassNotFound —
  Invalid single-table inheritance type: Photo is not a subclass of Post`; `Bogus` →
  `SubclassNotFound — failed to locate the subclass`. Both are real unrescued 500s on
  rows the `NOT NULL` `type` column allows, and both raise during instantiation *after*
  the finder SELECT, so they add no read. No corpus decision or terminal covers them;
  recorded as a limitation, not a defect, because no statement is lost.
* **`comments.commentable_type = 'StatusMessage'`.** B07 post 235: the association scope
  binds the base class literal `'Post'`, so the row simply does not match — 200 with body
  `[]`. This is positive evidence for the H5 ledger entry (the polymorphic type is a
  constant of the call site, not row data).
* **`format: :html`** → `ActionView::MissingTemplate` after the complete visibility chain
  (B08, signed-in); **`format: :xml`** → `UnknownFormat` (round 2). Matches
  `format_coverage_audit`'s TEMPLATELESS classification; no data access beyond the finder.
* **`X_MOBILE_DEVICE`** — negative in round 2 on this rig; not re-attacked. The two
  working entry points (`session[:mobile_view]`, explicit format) are both exercised here.
* **blocks / likes / participations / `comments_count` / `closed_account` / `hidden`
  share visibilities** — B10 rendered a closed-account author with a blank-name profile
  and produced no statement change; nothing on this action reads those tables
  (`_post_stats.mobile.haml` is not rendered by `index`). Unreachable by code.
* **`gon_set_current_user` → `UserPresenter#to_json`** (a large query fan-out:
  `user.person`, `unread_notifications.count`, `unread_message_count`, `aspects`,
  `services`, `contacts.receiving.count`) — never serialized on this action, because both
  renderable formats bypass the layout (`render json:` and `render layout: false`), so
  `gon.push` stores the presenter and nothing calls it. Confirmed by the statement sets of
  all five signed-in manifests. Unreachable by code, worth recording because it is the
  largest unexercised read cluster behind a `before_action`.
* **`camo_urls` / `AppConfig.privacy.camo.*`, `link_all_mentions`, `disable_hovercards`** —
  configuration and renderer options, not fixture/param/header. Out of the adversary's
  remit; none of them reaches SQL.
* **`Processor.process`'s `return '' if message.blank?`** — `comments.text` is `NOT NULL`
  and `Comment validates :text, presence: true`; round 2 showed the legacy-row state
  renders `""` with no `diaspora_links`. Unchanged.

## 7. Harness notes

* Manifests live in `adversary3/`, so the probe writes `adversary3/concrete_run.json`;
  the batch's `concrete_run.json` and `concrete_run_{anon,auth,mobile}.json` are
  byte-identical before and after (md5s in `runs/_batch_md5_before.txt`, re-diffed at the
  end).
* `_common3.rb` carries round 2's A10 fix (a **per-uid** warden memo and salts primed at
  fixture-load time, so no `User.find` runs inside a scenario body) and writes booleans as
  Ruby `true`/`false` so the repaired `ConcreteEnv.quote` emits the adapter's own `'t'`/`'f'`.
* The traced set adds `DiasporaFederation::Discovery::Discovery.new` and `#fetch_and_save`
  to round 2's list (`escape_segment`, `fix_profile`, `people_from_string`, `reload`,
  `count`, `pluck`, `save`, …) — tracing only adds a frame label and never alters flow.
* Runs used `CONCRETE_COVERAGE=0`, `unset JAVA_TOOL_OPTIONS`, `flock /tmp/concolic-slot.lock`
  inside `systemd-run --user -p MemoryMax=4000M -p MemorySwapMax=0`, one scenario per
  process, with the three crash-risky manifests isolated so each abort names its own seed.
