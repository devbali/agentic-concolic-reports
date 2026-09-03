# ADVERSARY REPORT — ROUND 2 — comments_index
`CommentsController#index`, `GET /posts/:post_id/comments`, anonymous AND signed-in.
Adversary run 2026-08-28 against the corpus **regenerated from scratch** after
cycle 3 closed round 1's wins and applied the coordinator's B-1/B-2 boundary
harvest (`complete: true`, 0 missing, 59 nodes, 12 407 dumps, assumptions
1 826/1 826 PASS, shims 18 PASS / 11 PROTOCOL / 0 red, note check green).

Real app only: `concrete_env.rb` sqlite/JDBC + the app schema, fixture ROWS by
raw `INSERT`, real Devise `serialize_from_session`, real
`ActionController::TestCase#process` (every `before_action` runs), real
templates. **No mocks, no stubs, no monkey-patches; nothing under `src/`, the
app, or the batch's runner / targets / mocks / manifests was touched.** Only
fixture rows, session, params, headers and format are under adversary control.
The batch's own `concrete_run*.json` are byte-identical before and after
(md5s in `adversary2/runs/_batch_md5_before.txt`; re-checked at the end).

Manifests, run JSONs, logs, response bodies and judge outputs:
`adversary2/` (`_common2.rb` shared harness, `A01…A10.rb` one scenario per
process, `run2.sh` / `chain2.sh`, `runs/*.json|.log|.judge.txt|_body_*.txt`,
`runs/_ALL_note_fidelity.txt`, `runs/_progress.log`).

Judges: `mock_note_check.py` (real per-frame statements vs corpus notes, with
`concrete_aliases.json`) and `note_fidelity_audit.py` (projection / predicate /
aggregate fidelity), plus a by-hand comparison of every run's depth-0
`target_calls` against the corpus's `symbolic_call` target set.

---

## Verdict

**No wins.** 10 manifests / 10 JRuby processes / 60 requests. Every real
statement this round issued has a projection-faithful corpus note, and every
depth-0 target call the real endpoint made is a target the corpus has events
for. The combined audit over all six judged run files:

```
== note_fidelity_audit: 6 run file(s), 21 distinct real SELECTs under 3 frames
-- MISSING: 0 -- STAR-OVER: 0 -- AGG-COLLAPSE: 0 -- PROJ-DIFF: 0 -- PRED-DIFF: 0 -- EXACT: 21 --
RESULT: every real statement has a projection-faithful note.
```

Both round-1 wins (W1 `Post.exists?` on `diaspora://…/post/<guid>`; W2 the
`:mobile` format with its depth-0 `Relation#to_a`) are **verified closed by a
real run**, on json AND mobile, anonymous AND signed-in. Round-1 near-miss
**N8** (the signed-in *public* branch had only ever been observed missing) is
**closed** this round — and its cause turned out to be an instrument defect,
not the app (finding D7).

`complete: true` therefore survives round 2 **at the statement level**. What it
does not survive untouched is the *shape of the explored universe*: seven of
the nine defects below are the corpus asserting states the application cannot
reach (phantom branches, unreachable param family, unreachable lookup family)
or reaching states it pins away. Per `ADVERSARY_WINS.md` cross-endpoint rule 6
("over-emission counts too"), those are defects, not safe slack.

---

## 1. Re-verification of every round-1 finding

| # | round-1 finding | round-2 verdict | evidence |
|---|-----------------|-----------------|----------|
| **W1** | `Post.exists?(guid:)` from `diaspora_links` — `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?`, json (`plain_text_for_json`) and mobile (`markdownified`), anon and signed-in | **CLEAN** | A01 (anon, json + mobile×2, **12** real `exists?` calls from a comment carrying 3 `post` links + 1 `comment` link + a `web+diaspora://` link), A02 (signed-in, json + mobile, 9 calls), A10 (signed-in public branch, 2 calls). `mock_note_check`: `NOTE-OK ActiveRecord::FinderMethods.exists?`. `note_fidelity_audit`: EXACT against `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = $$(SYM_PARAM_dlink_guid_…) LIMIT 1` (the only `cols=` note in the corpus — no `posts.*` STAR-OVER). Both link decisions are in the PC universe (`_text_has_dlink`, `_text_dlink_is_post`, `exists__1_exists` 3 511 dumps, both polarities). Residual: cardinality — see D6. |
| **W2** | the `:mobile` format never explored; depth-0 `Relation#to_a` with zero corpus events | **CLEAN** | mobile reached three ways: explicit `format: :mobile`, the app's own `session[:mobile_view]` switch (`application_controller.rb:144-148`), and (negative) the `X_MOBILE_DEVICE` header. Depth-0 `ActiveRecord::Relation#to_a` observed in A01 (2), A02 (3), A03 (3), A06 (3), A10 (2); corpus has 789 `Relation.to_a` events with 4 distinct comment-relation notes, all EXACT. `index.mobile.haml` / `_comment.mobile.haml` render for real (delete link, `self` class, `render_mentions`, `format_tags`). Residual: the `X_MOBILE_DEVICE` header did **not** switch the format on this rig (the request fell through to `html` → `MissingTemplate`), so that entry point is still unexercised — see "Unreachable". |
| **N1** | array `post_id` → `posts.id IN (?, ?)`; corpus `SYM_PARAM_post_id` is a scalar | **STILL OPEN — and mis-repaired** | see finding **D1** |
| **N2** | preload notes per-row `= $$(…)` for a bulk `IN (…)`; the load probe returned a count for a row list | **CLEAN** | A03: three distinct comment authors → `SELECT "people".* FROM "people" WHERE "people"."id" IN (?, ?, ?)` and `SELECT "profiles".* … WHERE "profiles"."person_id" IN (?, ?, ?)`; one mention → the singular `= ?` form Rails uses for a single id. Both match the corpus's bulk `… IN ($$(…))` notes EXACT. Return kind: `targets.rb:340/371` returns an `IterableSymbolicList` (row list), not `symint("…_row_count")`. |
| **N3** | a `mentions` row whose `person_id` has no `people` row: `[null]` in json, a 500 on mobile, and no nil decision | **CLEAN at the decision level; the states themselves are still real and now modelled** | A03 (post 113, json) → `"mentioned_people":[null]`, 200; A06 (post 131, mobile) → `ActionView::Template::Error: undefined method 'diaspora_handle' for nil:NilClass` (`mentionable.rb:35`). Corpus: `records_2_row_person_not_found` / `records_3_row_person_not_found` are recorded decisions (2 996 / 2 848 dumps) and the 500 is recorded as an outcome — `concolic_terminal {ActionView::Template::Error ← NoMethodError}` in 294 dumps. `mentions` has **no** foreign key in `schema.rb` (confirmed: no `add_foreign_key "mentions"` row), so the state is a database state. |
| **N4** | inflected locale (`language: "pl"`) reads the *principal's* profile BEFORE the action | **STILL OPEN (bind level)** | see finding **D2** |
| **N5** | four `mention_lookup_*` targets emit `people.diaspora_handle = …` that no real path issues | **PARTLY repaired, STILL OPEN** | the literal pin is gone (notes now bind `$$(SYM_PARAM_mention_handle_…)`), but the branch is still unreachable — see **D3** |
| **N6** | `Discovery#fetch_and_save` mock returned `nil`; the real call returns a `Person` or raises | **repaired in the mock, UNVERIFIABLE by a real run** | the mock now carries a `_discovery_failed` decision (False ⇒ Person rep, True ⇒ `DiscoveryError`), and both terminals appear in the corpus (`DiscoveryError` 1 059 dumps; `Template::Error ← DiscoveryError` 338). But every real attempt to reach it aborts the JVM — see "Unreachable" and **B-1** below. |
| **N7** | finder statements attributed to a nested `Relation#records` frame; notes lacked `ORDER BY "posts"."id" ASC LIMIT 1` | **CLEAN** | all four finder notes now carry `ORDER BY "posts"."id" ASC LIMIT 1`; every finder statement in A01/A02/A04/A10 matches EXACT. The `NOTE-OK*` "matched under a DIFFERENT target — frame nesting" annotation persists and is correct/expected (the SELECT is issued inside `Relation#records`, the note lives on the `first` alias that intercepted the call). |
| **N8** | the signed-in **public** branch had only ever been observed MISSING on this rig ("JDBC boolean artefact") | **CLOSED** | A10: `SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? AND "posts"."public" = ? ORDER BY "posts"."id" ASC LIMIT ?` returns the post; the full render follows (comments, preloads, mentions, `exists?`), json and mobile, both 200, judge EXACT against `ci_public_first`. Root cause of the old miss: an **instrument** defect, finding **D7** — not the JDBC driver and not the app. |
| **N9** | `Relation#to_a` vs `records` (same statement) | **CLEAN** — both are declared, both carry the comment-relation note, both observed at depth 0 |
| **C08–C10** | a comment author / mentioned person with no `profiles` row → `Person#fix_profile` → `Discovery` → JVM SIGSEGV | **STILL BLOCKED** | A07 and A08, each isolated to its own process: both exit **134** (`free(): invalid pointer`; `hs_err_pid4062253.log` records `SIGSEGV (0xb)` under OpenJDK 21.0.5). Unchanged from round 1. |

---

## 2. New scenarios (round 2)

| # | manifest | fixtures / request | status | mock_note_check | note_fidelity |
|---|----------|--------------------|--------|-----------------|---------------|
| A01 | `A01_links_anon.rb` | public post 100 + 4 comments: one with **three** `post` links (2 hit, 1 miss) + a `comment` link + a `web+diaspora://` link, one with mention markup + `#tag` + markdown + a bare URL + `<3`, one by a closed account. Requests: anon json (by id), anon html + `session[:mobile_view]`, anon explicit `:mobile`, anon html + `X_MOBILE_DEVICE`, anon json by 18-char guid | 200 ×4, MissingTemplate ×1 | **green** | **green** (9 EXACT) |
| A02 | `A02_links_auth.rb` | alice signed in; bob's private post 100 shared to her (`share_visibilities`) with a link-bearing comment and her own comment (delete link + `self`); her own private post 103. Requests: json, `:mobile`, html+session switch, own-post json/mobile, own-post by guid | 200 ×6 | **green** | **green** (13 EXACT) |
| A03 | `A03_preload_cardinality.rb` | post with 3 comments by **3 distinct authors**; post with **0** comments; a comment with **3 mentions**; a comment whose `mentions.person_id` = 999 (no such person). anon json + mobile | 200 ×7 (`[]` for the empty post) | **green** | **green** (7 EXACT) |
| A04 | `A04_param_shapes.rb` | `post_key` boundary: 15-char guid, exactly-16-char guid, 18-char guid, an **array** whose `to_s` is short (→ `:id`) and one whose `to_s` is long (→ `:guid`), a Hash param, `""`, a missing id — plus a real-`ActionDispatch` probe of param precedence | 200 ×5, 404 ×3 | **green** | **green** (8 EXACT) |
| A05 | `A05_auth_edges.rb` | first attempt at the signed-in edges — **invalidated by two harness defects of mine** (a shared warden memo and a `User.find` inside the body); superseded by A09/A10 | 404 ×7 | RED (3 statements of *mine* outside a target frame) | green |
| A06 | `A06_text_edges.rb` | comments with **blank** text, whitespace-only text, a setext heading + bare URL + `#tag`, a `comment`-only diaspora link, mention markup with no `mentions` row; a dangling mention on **mobile**; a comment author whose `people.guid` is `''` | 200 ×4, mobile 500 ×1 | **green** | **green** (5 EXACT) |
| A07 | `A07_noprofile_author.rb` | comment author `dave` with no `profiles` row; anon json. Isolated process | **JVM abort, exit 134** | — | — |
| A08 | `A08_noprofile_mention.rb` | mentioned person `dave` with no `profiles` row; anon json. Isolated process | **JVM abort, exit 134** | — | — |
| A09 | `A09_auth_edges2.rb` | A05 with the harness fixed, **plus** an explicit probe of the `posts.public = ?` bind | 200 ×5, 3 real 500s | RED (only from my `pluck`/`count` probe statements) | RED (same) |
| A10 | `A10_auth_edges3.rb` | A09 minus the probe statements: signed-in **public** branch (json+mobile), a `Reshare` with a dangling `root_guid` (json+mobile), a `Photo`-typed `posts` row, a `hidden: true` share visibility, `html`, `xml`, and a signed-in user with **no `people` row** (visible post and non-visible post) | 200 ×6, `SubclassNotFound`, `MissingTemplate`, `UnknownFormat`, `NoMethodError` | **green** | **green** (11 EXACT) |

60 requests, 10 processes. `runs/_progress.log` has the per-manifest DONE lines.

---

## 3. WINS

**None.** No real statement shape and no depth-0 target call lacked a corpus
counterpart in any of the 8 successful runs.

---

## 4. Near-misses and defects (no novel shape, but a real defect)

### D1 — the array-`post_id` family models the WRONG `post_key` branch, and the family itself is unreachable through the route  (Class B, with an S consequence)
Cycle-3 repair #6 made `SYM_PARAM_post_id_is_array` a recorded decision. Two
things are wrong with it.

*(a) The `post_key` dispatch is blind whenever it is true.* Across the whole
corpus, `(Length(SYM_PARAM_post_id) < 16)` is recorded in **0 of the 3 639**
dumps where `(SYM_PARAM_post_id_is_array == True)` is taken (combination table:
`(False,True) 5 739 · (False,False) 3 029 · (True,None) 3 639`). The compare is
real app code —

```ruby
# app/services/post_service.rb:65-67
def post_key(id_or_guid)
  id_or_guid.to_s.length < 16 ? :id : :guid
end
```

— it executes on every request, it is data-dependent, and under the array
branch it is neither recorded as a PC nor entered in the pin ledger. **D2
violation.**

*(b) It resolves to the wrong side.* The corpus's array notes are all on the
**guid** column, e.g. (`FinderMethods.first`, 1 515 events)

```
SELECT "posts".* FROM "posts" WHERE "posts"."guid" IN ($$(SYM_PARAM_post_id), $$(SYM_PARAM_post_id_2)) ORDER BY "posts"."id" ASC LIMIT 1
```

and the string `posts"."id" IN` occurs in **0** of the 12 407 dumps. The
runner's own comment says the opposite ("`post_key` sees the Array's to_s
(always < 16 → `:id`) and the finder issue[s] `posts.id IN (?, ?)`",
`run_dse.rb:250-252`). A04 confirms the runner's comment, not the corpus:
`post_id = ["100","101"]` (`.to_s` = 14 chars) issues

```
SELECT "posts".* FROM "posts" WHERE "posts"."id" IN (?, ?) ORDER BY "posts"."id" ASC LIMIT ?
```

while `post_id = ["guid16chars00000","postguid1000000001"]` (`.to_s` = 40)
issues the `posts.guid IN (?, ?)` form the corpus does carry. The cause is
that a concolic Array of `SymbolicString`s renders `to_s` as the objects'
inspect strings — always ≥ 16 — so the modelled branch is an artefact of the
representation, not of the parameter.

*(c) …and none of it is reachable anyway.* A real-`ActionDispatch` probe in A04
(no mocks — `Rack::MockRequest.env_for` + `Rails.application.routes.recognize_path`
+ `ActionDispatch::Request#parameters`):

```
[adv2] ROUTER recognize_path={:controller=>"comments", :action=>"index", :post_id=>"100"}
[adv2] ROUTER query_parameters={"post_id"=>["1", "2"]}
[adv2] ROUTER parameters[:post_id]="100" (String)
```

`post_id` is a **path** parameter of `/posts/:post_id/comments`, and Rails
merges path parameters last, so `?post_id[]=…` can never reach the action as an
Array. The 3 639 array dumps (29 % of the corpus) and the ~3 627 `posts.guid
IN (…)` notes they mint across all four post finders are therefore **pure
over-emission of a parameter shape the endpoint cannot receive** — cross-endpoint
rule 6.

Both judges score the real `posts.id IN (?, ?)` **EXACT**: `statement_diff.normalize`
reduces an `IN` list to its predicate *column*, so `posts.id IN (?, ?)` and the
corpus's `posts.id = $$(SYM_PARAM_post_id)` are indistinguishable to them. **The
check that catches this class does not exist yet** — that is the reportable part.

### D2 — the profiles read on the DEVISE PRINCIPAL still has no note bound to it  (round-1 N4; Class B pin with an S/fold consequence)
```ruby
# app/controllers/application_controller.rb:120-122  (before_action :set_grammatical_gender)
if (user_signed_in? && I18n.inflector.inflected_locale?)
  gender = current_user.gender.to_s...
```
`current_user.gender` delegates to `Person#profile`. A09/A10 with
`users.language = "pl"` (the response's `:locale=>[:pl, "en", :en]` proves the
locale took effect) issue, under `SingularAssociation#find_target`, **before the
action body**:

```
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ? LIMIT ?
```

The corpus's twelve `find_target` notes bind `profiles.person_id` to comment
authors, mentioned people, and handle-lookup results — **never** to
`$$(SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id)`. The
auth corpus pins `language` to `"en"`, so `inflected_locale?` is false and the
branch never runs. Judge-invisible (the audit matches it EXACT against an
author-bound note), but at fold level the principal's profile read is chained
onto the comment-author chain — the violation-5 class (`DISCIPLINE.md §1 #5`),
Class S in fold-space.

### D3 — the `mention_lookup_*` family is 9 219 note events for a branch no database can produce  (round-1 N5, second half still open)
```ruby
# lib/diaspora/mentions_container.rb:17-23
def mentioned_people
  if persisted?
    mentions.includes(person: :profile).map(&:person)
  else
    Diaspora::Mentionable.people_from_string(text)
  end
end
```
Every comment on this endpoint comes out of `Relation#records`/`#to_a`, so
`persisted?` is always true; `people_from_string` is otherwise reachable only
through `Mentionable.filter_people`, which needs `:disable_hovercards` or
`:link_all_mentions` — options no caller on this endpoint passes. Across **14**
real runs (8 mine + 6 from round 1) the traced targets
`Diaspora::Mentionable.people_from_string`, `Person#fix_profile` and every
`find_by(diaspora_handle:)` fired **zero** times. The corpus nevertheless
carries 9 219 events over the four `mention_lookup_*` aliases, all rendering

```
SELECT "people".* FROM "people" WHERE "people"."diaspora_handle" = $$(SYM_PARAM_mention_handle_…)
```

The cycle-3 repair fixed the *literal* (it is now a `SYM_PARAM_*` bind, Rule V)
but not the reachability: the policy still inherits a `people.diaspora_handle`
equality predicate — a predicate **column** that appears in no real statement of
this endpoint — plus everything chained below it (`profiles.person_id =
$$(mention_lookup_*_id)`, `reload`, the discovery wall). `_persisted == False`
is a state no database produces; it is the same class as the conversations
near-miss "`count > 0` with zero rows".

### D4 — the `guid == ''` decision family explores a state the model makes impossible  (new; phantom branch)
```ruby
# lib/diaspora/fields/guid.rb:6-17
def self.included(model)
  model.class_eval { after_initialize :set_guid; ... }
end
def set_guid
  self.guid = UUID.generate(:compact) if guid.blank?
end
```
`Person`, `Post` and `Comment` all include it, so **no record loaded from the
database can have a blank guid**. A06 proves it with a real row: person 7 was
inserted with `guid = ''`, and both the json and the mobile render returned
**200** with the link `href='/people/34f946e084da013f7799518ff3a98bad'` — a
freshly generated guid, not the `UrlGenerationError` the corpus's true branch
stands for. The corpus nevertheless takes `…_guid == ''` **True** in 3 376
(comment author) + 77 + 80 + 14 = **3 547** dumps. Both polarities emit similar
note sets (12.7 vs 13.4 symbolic calls/dump), so no statement is fabricated —
but 3 547 dumps and the corresponding tree nodes/assumptions describe a state
the application forbids, which inflates the "59 nodes, 0 missing" universe with
fiction.

### D5 — `User has_one :person` is pinned FOUND over a reachable DB state that 500s the endpoint  (new; Class B, false neutrality argument)
`targets.rb:713-718` pins the `User has_one :person` load found, with the
argument "sign-up creates both rows". `schema.rb` has **no** foreign key from
`people.owner_id` to `users` (only `index_people_on_owner_id`, unique), and
`Person#destroy` does not destroy its owner — so a user row without a person
row is a database state. A10, signed in as user 8 (`gina`, no `people` row):

* post 123, visible through `share_visibilities` → 200 (the first finder never
  touches `person`);
* post 124, not visible → `NoMethodError: undefined method 'id' for nil:NilClass`
  at `lib/evil_query.rb:116-118`
  ```ruby
  def querent_is_author
    @class.where(@key => @id, :author_id => @querent.person.id).where(@conditions)
  end
  ```

The corpus asserts that a `ci_vis_first` miss is always followed by the
`ci_author_first` SELECT and then the `ci_public_first` SELECT; in this state
neither is ever issued, and no comments read happens either. A control-dependence
over-approximation with no corresponding terminal in `concolic_terminal`
(the three recorded terminals are the two discovery ones and the mention
`NoMethodError`). The pin's written neutrality argument is factually wrong.

### D6 — `Post.exists?` cardinality: the corpus caps at one probe per run, the real endpoint issues one per `post` link per comment  (new; D1 multiset)
Max `Anonymous.exists_probe` events in any of the 12 407 dumps: **1**. A01's
single link-bearing comment produced **3** `exists?` calls per json render and
2 per mobile render (12 in the manifest); A02 produced 9. This is the
one-representative-row list model (`H4` answer in `AGENT_RUN.md`), applied one
level deeper — one representative *link per comment*. Statement-shape neutral,
multiset-unfaithful (D1 says "as a multiset").

### D7 — INSTRUMENT DEFECT: `ConcreteEnv.insert` writes booleans in a representation ActiveRecord does not query with  (new; this is why N8 stood for two rounds)
`src/ruby_runtime/completion_checker/concrete_env.rb:44-46` quotes `true` as
`"1"`. For this adapter ActiveRecord quotes booleans as `'t'`. A09 measured it
directly (real AR, fixture data only):

```
[adv2] Post.where(public: true) SQL: SELECT "posts".* FROM "posts" WHERE "posts"."public" = 't'
[adv2] BEFORE update_all: where(id:120, public:true).count = 0
[adv2] AFTER  update_all: where(id:120, public:true).count = 1     # after Post.where(id:120).update_all(public: true)
```

So every `WHERE "posts"."public" = ?` in every batch's concrete scenarios has
been silently matching nothing. `AGENT_RUN.md` cycle 1 §F records this as a
"JDBC sqlite boolean bind artefact" and the batch worked around it by giving
alice a `share_visibilities` row; round 1 recorded it as N8. It is neither the
driver nor the app: it is the fixture writer. Consequence: the signed-in
`public_post` branch — one of the three arms of
`EvilQuery::VisibleShareableById#post!` — had **never** been concretely
exercised on any batch until A10. (I did not touch `concrete_env.rb`; A10 works
around it by re-writing the column through AR's own quoting,
`Post.where(id: 120).update_all(public: true)`.)

### D8 — `find_target` is emitted *in addition to* the bulk preload for the same association and the same row  (new; D1 multiset)
`Comment.for_a_stream` is `includes(author: :profile)` and
`mentioned_people` is `mentions.includes(person: :profile)`, so in a real run
`comment.author` and `comment.author.profile` are already loaded and issue
nothing — every real `people`/`profiles` read on this endpoint comes from the
Preloader under `Relation#records` (A01/A02/A03/A06/A10: `find_target` fires
only for `User has_one :person` and, in D2, the principal's profile). The
corpus emits both: **13 626 dumps** contain a `profiles` preload note and a
`profiles` `find_target` note *with the identical bind*, e.g.

```
Anonymous.load_intermediate  SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" IN ($$(SYM_RESULT_ActiveRecord__Relation_records_1_row_author_id))
find_target                  SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" =   $$(SYM_RESULT_ActiveRecord__Relation_records_1_row_author_id) LIMIT 1
```

Of the 41 335 SQL-bearing `find_target` notes in the corpus, ~36 350 are of this
kind (or belong to the unreachable handle-lookup chain of D3); 4 985 —
`people.owner_id = $$(devise_user_first_1_id)` — are the only ones a real run
issues. Same column set, so judge-invisible; wrong as a multiset, and it gives
the fold a second producer edge for a read that happens once.

### D9 — two smaller items
* **The JSON variants have no comment-collection length decision.** `len(SYM_RESULT_…_to_a_1_rows) != 0` is recorded on `anon_mobile` (2 515 T / 118 F) and `auth_mobile` (3 877 T / 182 F) and **nowhere** on the 5 676 `anon_json`/`auth_json` dumps: the json path materializes through `Relation#records` inside `Array#map`, which never compares the length. A03 shows the real empty-json state is a plain 200 with body `[]` that issues **only** the post finder and the comments SELECT — no author preload, no mentions. `H4` ("collection length must be a decision, 0/1/many") holds for half the corpus.
* **`Processor.process`'s blank-message early return is invisible.**
  `lib/diaspora/message_renderer.rb:14  return '' if message.blank?` — the
  cycle-3 text shim always builds `"hello world…welcome"`, so `text` is never
  blank and the early return is never taken. A06 shows the real state (a
  `comments.text` of `""` or `"   "` renders `"text":""`, 200, and **no**
  `diaspora_links`, no `exists?`, no `render_mentions`). Reachability caveat:
  `Comment validates :text, presence: true`, so the app itself will not create
  one — it is a legacy/imported-row state, and the honest classification is
  "blind branch on a state the schema allows and the model forbids".
* **Fact error in `targets.rb` §8c**: the comment states "`profiles.person_id`
  has NO foreign key … (schema.rb)". `db/schema.rb:643` is
  `add_foreign_key "profiles", "people", name: "profiles_person_id_fk", on_delete: :cascade`.
  The *conclusion* (a person with no profile is a real state) is still right —
  the FK constrains profiles→people, not people→profiles — but the stated
  justification is wrong and should be corrected before it is reused.

---

## 5. The two cycle-3 boundary changes, verified

### B-1 — `ActiveRecord::Base#reload` is now a TARGET: note **shape correct**, but **unverifiable by any real run of this endpoint**
The corpus's four `reload` notes are
`SELECT "people".* FROM "people" WHERE "people"."id" = $$(<rep>_…_id) LIMIT 1`.
That is exactly the single-row re-read the real body performs —
`activerecord-5.2.4.3/lib/active_record/persistence.rb:602-615`:

```ruby
def reload(options = nil)
  self.class.connection.clear_query_cache
  fresh_object = ... self.class.unscoped { self.class.find(id) }
  @attributes = fresh_object.instance_variable_get("@attributes")
  @new_record = false
  self
end
```

`find(id)` on an unscoped `Person` is `SELECT "people".* FROM "people" WHERE
"people"."id" = ? LIMIT ?`; projection `people.*`, predicate `people.id`,
`LIMIT 1`; the `clear_query_cache` call issues nothing. The declared return
(the receiver) matches `reload`'s `self`. **No boundary finding on the shape.**

What I cannot confirm with a run: on this endpoint `reload` has exactly one
call site —

```ruby
# app/models/person.rb:371-375
def fix_profile
  logger.info "fix profile for account: #{diaspora_handle}"
  DiasporaFederation::Discovery::Discovery.new(diaspora_handle).fetch_and_save
  reload
end
```

— and it is reached only *after* `fetch_and_save` returns, i.e. only after a
**successful network discovery**. A07 and A08 (isolated, one scenario per
process) both abort the JVM at exit 134 inside that call, and `reload` fired
**zero** times across all 14 real runs. So the corpus's 3 741 `reload` notes
rest on a code-reading claim plus a branch that needs the network; the batch's
own pin (`<rep>_reload_not_found` pinned false) is likewise unexercised. Worth
recording as a limitation of the evidence, not as a defect of the declaration.

### B-2 — `escape_segment` is now a SHIM: **verified clean**
`ActionDispatch::Journey::Router::Utils.escape_segment` was traced explicitly in
every manifest (adding a frame label only observes). Across the 8 successful
runs it was called **163 times at depth 0**, with **zero** nested target calls
and **zero** SQL statements tagged to its frame — and it appears **0 times** as
a target in the 12 407 dumps, so it mints no note and no symbolic result. The
demotion is correct and the shim contract holds on real data.

---

## 6. Unreachable / not attacked, and why

* **`Person#fix_profile` → `Discovery` → `reload` (missing `profiles` row).**
  A07 (author) and A08 (mentioned person), isolated: both exit 134,
  `free(): invalid pointer` / `SIGSEGV (0xb)` (OpenJDK 21.0.5, JRuby). Identical
  to round 1's C08/C08b/C09/C10 and to the conversations_index report. The path
  is real and modelled; it cannot be judged on this rig. (My one `hs_err_pid*`
  dump was removed; older ones were left in place.)
* **`X_MOBILE_DEVICE` / mobile-fu format switching.** A01 sent
  `HTTP_X_MOBILE_DEVICE: iPhone` with an iPhone UA on an `html` request; the
  format stayed `html` and the request 500'd with `MissingTemplate`. The
  `session[:mobile_view]` switch and the explicit `:mobile` format both work, so
  the mobile *statements* are covered; only this entry point is unexercised.
* **`Reshare#root`.** A10 rendered a `Reshare` with a dangling `root_guid`
  (json and mobile, 200) and issued **no** extra statement: nothing on this
  action touches `root`. Unreachable by code, not by rig.
* **A `Photo`-typed `posts` row.** A10: `ActiveRecord::SubclassNotFound —
  Invalid single-table inheritance type: Photo is not a subclass of Post`
  (`Photo < ApplicationRecord` in this app, its own table). A real, unrescued
  500 on a row `posts.type` allows; no new statement (the finder SELECT is
  issued and instantiation then raises), and no corpus decision or terminal
  covers it. Recorded here rather than as a defect because it adds no read.
* **`format: :xml`** → `ActionController::UnknownFormat` (`respond_to :html,
  :mobile, :json`); **`format: :html`** → `MissingTemplate` after the full
  visibility chain (both anon and signed-in). No data access beyond the post
  finder; matches `format_coverage_audit`'s TEMPLATELESS classification.
* **`share_visibilities.hidden = true`** — A10, 200: `querent_has_visibility`
  does not filter `hidden`. Statement identical.
* **`blocks`, likes, participations, `comments_count`, `closed_account`** —
  nothing on this action reads them (A01's closed-account author and A05's
  `blocks` row produced no statement change). Unreachable by code.
* **`camo_urls` / `Profile#image_url`'s camo branch** — `AppConfig.privacy.camo.*`
  is configuration, not fixture or param; out of the adversary's remit.
* **`link_all_mentions` / `disable_hovercards`** — renderer options no caller on
  this endpoint passes (see D3).
* **`posts.public` NULL** — `NOT NULL` in `schema.rb`.
* **A comment with no author row** — `add_foreign_key "comments", "people",
  column: "author_id", on_delete: :cascade`; not a database state.

## 7. Harness notes
* Manifests are in `adversary2/`, so the probe writes `adversary2/concrete_run.json`;
  the batch's `concrete_run.json`, `concrete_run_{anon,auth,mobile}.json` are
  byte-identical before and after (md5 recorded both times).
* Runs use `CONCRETE_COVERAGE=0`, `unset JAVA_TOOL_OPTIONS`,
  `flock /tmp/concolic-slot.lock` inside `systemd-run --user -p MemoryMax=4000M
  -p MemorySwapMax=0`, one scenario per process.
* A05 is kept in the tree as the invalidated first attempt (a shared
  `@concolic_user` memo made every request in the process reuse the first
  resolved user, and a `User.find` inside the body produced the three
  "OUTSIDE any target frame" statements its judge flagged). A09/A10 supersede
  it; only A10's verdict should be read as an endpoint verdict.
