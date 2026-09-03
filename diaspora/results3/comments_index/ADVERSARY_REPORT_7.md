# ADVERSARY ROUND 7 — comments_index (CommentsController#index, GET /posts/:post_id/comments)

Date 2026-08-29. Corpus under attack: cycle 8 — `complete: true`, 64 nodes,
14 010 dumps / 11 368 runs / 236 896 PCs, 0 missing, assumptions 2 152/2 152 PASS,
shims 19 PASS / 11 PROTOCOL, hardening lint clean.

**Ops.** 7 manifests, 7 JRuby processes (`adversary7/G01…G07`), **104 real HTTP
requests + 19 in-process probes, 770 real SQL statements, 0 JVM aborts**. Every
process: `unset JAVA_TOOL_OPTIONS`, `flock /tmp/concolic-slot.lock
scripts/diaspora-concolic …/concrete_run_probe.rb <manifest>` inside
`systemd-run --user --pipe --wait -p MemoryMax=4000M -p MemorySwapMax=0`, chained
by `chain7.sh` with DONE lines in `adversary7/runs/_done.log`. No mocks, stubs or
monkey-patches; only fixture rows, session/user, params, headers and format.
The batch's own instruments were copied nowhere and are byte-identical after the
round — `md5sum -c adversary7/runs/_batch_md5_before.txt`: 7/7 **OK**
(`concrete_run.json` and the six `concrete_run_*.json`).

**Result: 2 wins (W7-1, W7-2 — both TARGET-LEVEL, both inside the cycle-8
Rule-D model), 7 near-misses.** Both judges are EXACT on every endpoint
statement in all 7 runs, and all three named audits pass over the full corpus —
which is the point: neither win is a new SQL shape, both are states.

---

## 1. Re-verification at projection level (`=`/`IN`, LIMIT, ORDER BY)

Judges: `mock_note_check` + `note_fidelity_audit` per run
(`adversary7/runs/*.judge.txt`). Endpoint statements: **MISSING 0, STAR-OVER 0,
PROJ-DIFF 0, PRED-OP-DIFF 0, LIMIT-DIFF 0, ORDER-DIFF 0, PRED-DIFF 0, EXACT 55**
across G01/G02/G04/G05/G07 (G03 5 and G06 11 more) (the two non-zero verdicts, G03 STAR-OVER×2 and G06
ORDER-DIFF×1, are my own `pluck` / `Comment.find` **probes**, not endpoint
statements — see §5, near-miss N7-7).

| finding | re-verified how (round-7 evidence) | verdict |
|---|---|---|
| **M-1 / W1** `Post.exists?` link family (`SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?`) | G05 913 (3 links) / 914 (**7 links**) / G07 965; json + mobile; `mock_note_check` NOTE-OK on `exists?`, fidelity EXACT incl. `LIMIT 1` | **verified** |
| **M-2 / W2** `:mobile` is a corpus format | G01/G02/G04/G05/G06/G07 mobile requests; G04 exercised all three entry points — explicit `format: :mobile`, `session[:mobile_view]`, and `X_MOBILE_DEVICE` (see N7-5) | **verified** |
| **M-3** dangling `mentions.person_id` | G05 917 json/mobile plain text → `people.id = ?` and **no** `profiles` read, 200 both ways; G01 853 mobile → `IN (?, ?)`, no `profiles`, `Template::Error ← NoMethodError` | **verified** (and extended — W7-1) |
| **M-4** nothing is emitted for an empty relation | G04 905, G05 921 → exactly `{posts finder, comments SELECT}` on json (body `[]`, 2 bytes) and mobile (68 bytes); `empty_relation_emission_audit`: 14 010 dumps, 2 599 empty-list states, **pass** | **verified** |
| **M-5** invalid `users.language` | G05 uid 21 (`"xx"`) → **exactly one** statement `SELECT "users".* … ORDER BY "users"."id" ASC LIMIT ?`, then `I18n::InvalidLocale` | **verified** |
| **M-6** out-of-tree `posts.type` | G05 911 json + mobile → `SubclassNotFound`, statement multiset `{posts:1}` and nothing else | **verified** |
| **M-7** preload op follows the DISTINCT KEY count | G02 871 (10 comments, 1 author) → `people.id = ?`; G02 873 (4 authors) → `IN (?, ?, ?, ?)`; G06 932/937 (2 comments 1 author, anon + signed-in) → `= ?` | **verified** (and see W7-2) |
| **M-8** nested step follows the parents actually loaded | G06 934, G01 851/852, G07 962/963/964: `people.id IN (?, ?)` → `profiles.person_id = ?`; G07 962 `IN (?, ?, ?)` → `= ?` | **verified** (and extended — W7-1) |
| **M-9 / B-8** a finder that finds nothing keeps its statement | G04 999999 / 15-char / 17-char / empty `post_id` → 404 with the `posts` finder recorded; G04 903 signed-in 404 → all three visibility finders recorded; `noteless_call_audit` over 14 010 dumps: **0** non-wall note-less events | **verified** |
| **M-10** nested key count derived from the loaded parents | G06 933 (2 live mentions) → `IN (?, ?)` then `IN (?, ?)`; G01 854/855 (3 mentions) → `IN (?, ?, ?)` then `IN (?, ?)`; corpus `IN`→`=` 1 013, every one a partial load | **verified** |
| **M-11** mentions key count IS the row count | G03 probes: the UNIQUE index exists in the live DB; a duplicate `(person_id, container_id, container_type)` raises `ActiveRecord::RecordNotUnique`; `person_id` is `NOT NULL` (see §2b) | **verified** |
| **M-12** one fact, one variable at key position 2 | corpus: all 16 928 `IN` binds use the one shared `…_row2_…` variable; real G06 931/936 `people.id IN (…)` / `profiles.person_id IN (…)` bind the same values on both levels | **verified** |
| **D1** array `post_id` / `post_key` branch | G04: 15-char keys → `WHERE "posts"."id" = ?` (`'g04guid9000000'`), 17-char → `WHERE "posts"."guid" = ?`, empty → `id = ''`; `Length(SYM_PARAM_post_id) < 16` models exactly this | **verified** |
| **D2** principal's `profiles` read | G04 901/904 signed-in → `SELECT "people".* … "owner_id" = ? LIMIT ?` present; corpus `find_target` notes EXACT | **verified** |
| **D3** `mention_lookup_*` over-emission | 104 requests, `Mentionable.people_from_string` fired **0** times; no `people.diaspora_handle` predicate in any real statement | **verified** |
| **D4** `guid == ''` phantom branch | absent from the 64-node PC universe (checked directly) | **verified absent** |
| **D5** `User has_one :person` pin | G05 uid 22 (user with no `people` row) → `{users, posts⋈share_visibilities, people.owner_id}` then `NoMethodError`; corpus has that path | **verified** |
| **D6** `Post.exists?` per-render cardinality | G05 914 → **7** probes in one render; corpus tops out at 4 | **declared limit, re-measured** (N7-4) |
| **D7** `ConcreteEnv` boolean quoting | G04 904 signed-in reached `ci_public_first` (`"posts"."public" = ?`) and returned rows | **verified** |
| **D8** `find_target` in addition to the bulk preload | in 104 requests the only `find_target` statements are the principal's `people.owner_id … LIMIT ?` (G04 seg 13/22, G05 seg 18/25) — none for comment authors, author profiles or mentioned people | **verified** |
| **D9a** comment-collection length is a decision | **REGRESSED** — see W7-2. `(len(comments) != 0)` survives (json 8 495 T / 35 F, mobile 10 680 T / 26 F) but `(len(comments) > 1)` is gone from the whole corpus | **win** |
| **D9b** blank / whitespace comment text | G05 918 json + mobile → both comments render, all statements unchanged | **verified (harmless)** |
| **B-2** `escape_segment` is a shim | 34 depth-0 calls in G06 alone, 0 SQL, 0 corpus events | **verified** |

---

## 2. The new rule under attack (brief items 2a–2d)

| item | question | evidence | verdict |
|---|---|---|---|
| **2a** | is `Comment#author` the ONLY free key count? | The endpoint has exactly two `includes` trees (G06 probe: `includes_values == [{:author=>:profile}]`, and `mentions.includes(person: :profile)`). Steps: `Comment belongs_to :author` (no unique index over `(commentable_id, commentable_type, author_id)`; `db/schema.rb:115-127` has none) — **genuinely free**, confirmed real at 1/2/3/4 distinct keys with 1…10 rows. `Mention belongs_to :person` — determined (2b). `Person has_one :profile` — binds the owner PK, determined. Nested steps — determined by the loaded parents (M-10 re-verified). | **no free step is modelled as determined** |
| **2a (converse)** | is anything determined that is actually free? | **YES.** Not a *step* but the quantity cycle 8 derived from one: `preload_rows_driven?` stops recording the comments relation's `(len > 1)` and sets its length to `[len, keys].max`. `keys ≤ rows` is a BOUND, not a determination. Real: `people.id = ?` with **10** comment rows (G02 871). | **W7-2** |
| **2b** | can a comment's mentions repeat a person? | G03, six attacks against the live DB: (i) duplicate `(5, 940, 'Comment')` → `ActiveRecord::RecordNotUnique … UNIQUE constraint failed: mentions.person_id, mentions.mentions_container_id, mentions.mentions_container_type`; (ii) `person_id = NULL` → `ActiveRecord::NotNullViolation` (so Rails 5.2's `owners_by_key`'s `h[key] = owner if key` nil-drop is unreachable and `people.id IS NULL` can never be emitted); (iii) case-differing `mentions_container_type = 'comment'` — the ROW inserts (raw rows 993+994) but `Comment#mentions` returns **only** `[[993, 5, "Comment"]]`; (iv) padded `'Comment '` — same; (v) the same person mentioned on the POST as well — the comment's relation still returns one row; (vi) `PRAGMA index_list/index_info` confirm `index_mentions_on_person_and_mc_id_and_mc_type` is UNIQUE over exactly those three columns and `mentions.person_id` is `NOT NULL`. Also `connection.in_clause_length == nil`, so no `IN`-splitting can manufacture a second statement. | **the UNIQUE-index argument HOLDS** |
| **2c** | partial loads: 1st missing rather than 2nd; middle of 3 missing; person without profile | G07 963 (first dangling) and G07 964 (second dangling) issue **byte-identical** statement sets (`mentions`, `people.id IN (?, ?)`, `profiles.person_id = ?`) on json and on mobile — the batch's claim "which physical row is key 1 is not observable, only the COUNT reaches a statement" is TRUE **at the statement level**. G01 855 (3 mentions, middle dangling) → `IN (?, ?, ?)` then `IN (?, ?)`; G07 962 (3 mentions, 2 dangling) → `IN (?, ?, ?)` then `= ?`. **But the LIST CONTENTS are observable** and that is W7-1. Third item: G01 856 — a mentioned person that exists with **no** `profiles` row, mobile, named markup → `people.id = ?` then `profiles.person_id = ?` (0 rows), **200** — the `…_profile_not_found == True` arm reached by a REAL run for the first time (see §5, N7-1). | **statement level OK; list level is W7-1** |
| **2d** | does the shared `_row2_` variable hold when row 2's author IS row 1's author? | In that state the model mints **no** `_row2_` variable at all (one distinct key ⇒ `pred_for` renders `= $(…_row_author_id)`), and the real statement is `SELECT "people".* … "people"."id" = ?` — G06 932 (anon json + mobile) and G06 937 (signed-in). With two distinct keys, outer and nested bind the same `…_row_author_id` / `…_row2_author_id` pair (G06 931/936). | **holds** |

---

## 3. New scenarios (going wider than rounds 1–6)

| manifest / post | scenario | outcome | new? |
|---|---|---|---|
| G01 850–857 | partial mention loads with markup naming the live vs the missing person, dangling first vs last, 3 mentions middle-dangling, person-without-profile | 200 / **500** / 200 / 500 / 200 / 200 / **200** / 500 | **W7-1**, N7-1 |
| G02 870–877 | 5 and **10** comments by ONE author; 3c/2a; 4c/4a; 6c/2a; 2 comments both mentioning the same person; own comments signed-in | all 200 | **W7-2** |
| G03 | UNIQUE-index attacks (duplicate / NULL / case / padding / second container), `in_clause_length`, reflections | see 2b | closes 2b |
| G04 900–905 | `format:` json, mobile, **html, xml, js, atom**; `session[:mobile_view]`; `X_MOBILE_DEVICE`; mobile UA alone; header alone; visibility matrix (share-visible / own / public arm / not shared); anon on a non-public post; 15/16/17-char and empty `post_id` | 200 ×15, `MissingTemplate` ×3, **`UnknownFormat` ×4**, 401 ×3, 404 ×5 | N7-2, N7-5 |
| G05 910–921 | **`Reshare` STI commentable**; `diaspora://…/comment/<guid>`; 3 and **7** post links; markdown + bare URLs + `<img src>` (camo) + `#tag` + `#<3` + RTL text; **pod-bearing remote author** + closed-account author; dangling mention plain text; empty/whitespace text; blank `guid`; blocked+contact rows signed-in; invalid locale; user without a person; out-of-tree `posts.type` | 200 ×19, 3 truncating exceptions | N7-3, N7-4, positives |
| G06 930–937 | the M-7/M-8/M-10/M-11/M-12 matrix at 1/2/3/4 keys and 1/2/3 rows, anon + signed-in | all 200 | re-verification |
| G07 960–965 | **truncation differential**: identical fixtures, only the mention markup differs; 3→1 nested shrink; first-vs-second dangling; two comments each carrying a dlink | 200 / **500** / 200 ×8 | **W7-1** |

Positives worth recording: a **`Reshare`** commentable changes no statement (G05 910: `SELECT "posts".* WHERE "posts"."id" = ?`, no STI condition, no `root` read); a **pod-bearing** remote author and a **closed_account** author change no statement (G05 916 — no `pods`, `blocks`, `contacts` read); markdown, bare URLs, `<img src>`, hashtags, `#<3` and RTL text change no statement (G05 915); `diaspora://…/**comment**/<guid>` issues **no** `Post.exists?` (G05 912) — the corpus's `_text_dlink_is_post != True` arm, now confirmed by a real run.

---

## 4. WINS

### W7-1 — a PARTIALLY loaded FK-less `belongs_to` preload attaches a LOADED child, so the corpus's `mentioned_people` can never hold a nil beside a live Person — the one list shape that raises

**Class B (unexplored branch) with a Class S consequence (over-emission). TARGET-LEVEL** — the cause is in the shared association/preload toolkit (the B-4 / B-7 not-found modelling), not in this action's view.

**Scenario.** `adversary7/G07_truncation.rb`, posts 960 (novel) and 961 (control) —
identical fixtures, differing only in which handle the first comment's markup names:

```ruby
post 960/961: public StatusMessage
comment 970/972 (author 2): "first @{Erin; erin@other.example} [@{Ghost; ghost@nowhere.example}]"
  mention -> person 5 (live, has a profile)
  mention -> person 995 (NO people row; `mentions` has no FK, db/schema.rb:202-209)
comment 971/973 (author 5): "second @{Frank; frank@third.example} diaspora://alice@localhost/post/<live guid>"
  mention -> person 6 (live)
request: GET /posts/96x/comments  format: :mobile  anonymous
```

**The real runs, verbatim** (`adversary7/runs/G07_truncation.json`):

*961, control, 200, **11** statements*
```
SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? ORDER BY "posts"."id" ASC LIMIT ?
SELECT "comments".* FROM "comments" WHERE "comments"."commentable_id" = ? AND "comments"."commentable_type" = ? ORDER BY created_at ASC
SELECT "people".* FROM "people" WHERE "people"."id" IN (?, ?)
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" IN (?, ?)
SELECT "mentions".* FROM "mentions" WHERE "mentions"."mentions_container_id" = ? AND "mentions"."mentions_container_type" = ?
SELECT "people".* FROM "people" WHERE "people"."id" IN (?, ?)
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ?
SELECT "mentions".* FROM "mentions" WHERE "mentions"."mentions_container_id" = ? AND "mentions"."mentions_container_type" = ?
SELECT "people".* FROM "people" WHERE "people"."id" = ?
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ?
SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?
```

*960, novel, `ActionView::Template::Error ← NoMethodError: undefined method 'diaspora_handle' for nil:NilClass`, **7** statements — it stops dead on the partial load:*
```
SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? ORDER BY "posts"."id" ASC LIMIT ?
SELECT "comments".* FROM "comments" WHERE "comments"."commentable_id" = ? AND "comments"."commentable_type" = ? ORDER BY created_at ASC
SELECT "people".* FROM "people" WHERE "people"."id" IN (?, ?)
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" IN (?, ?)
SELECT "mentions".* FROM "mentions" WHERE "mentions"."mentions_container_id" = ? AND "mentions"."mentions_container_type" = ?
SELECT "people".* FROM "people" WHERE "people"."id" IN (?, ?)
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ?
```
Four statements — the second comment's `mentions` read, its `people`/`profiles`
preload and its `Post.exists?` probe — are never issued. Reproduced three more
times in G01: 851 (markup names the missing person), 852 (the dangling mention
is FIRST, so the nil is at index 0 and any markup raises), 857.

**The code that issues it.**
`lib/diaspora/mentions_container.rb:19  mentions.includes(person: :profile).map(&:person)`
returns `[#<Person 5>, nil]` — Rails 5.2 `Preloader::Association#associate_records_to_owner`
leaves `association.target` unset for the owner whose key returned no row — and
`lib/diaspora/mentionable.rb:35  person = people.find {|p| p.diaspora_handle == diaspora_id }`
walks that list from index 0, so the nil is reached (and raises) as soon as the
markup names a handle that is not an earlier element. Rendered from
`app/views/comments/_comment.mobile.haml:23  comment.message.markdownified`.

**What the corpus lacks.** `targets.rb:238-258`:

```ruby
missing = (symbool(nf, ct.seed_for(nf, false), note: psql) == true)
child   = missing ? nil : ct.symbolic_instance(r2.klass, base, psql)
if missing
  loaded_keys = []
else
  loaded_keys = [keys[0]]
  if keys.length > 1
    k2nf = "#{base}_k2_not_found"
    loaded_keys << keys[1] unless symbool(k2nf, ct.seed_for(k2nf, false), note: psql) == true
  end
end
mark_loaded(owner_rep, r2.name, child)
```

The relation carries ONE representative row, so `child` is the ONE person every
mention resolves to. `_not_found == True` ⇒ `child = nil` **and** `loaded_keys = []`
⇒ no nested `profiles` statement. `_k2_not_found == True` ⇒ `child` is a live
Person ⇒ the list has no nil ⇒ **no raise**. The two facts the state needs — "a
parent is missing" and "a parent loaded" — are welded to the same variable.

Measured over the full 14 010-dump corpus:

| corpus state | dumps | mentions-tree `profiles` note | `Template::Error ← NoMethodError` |
|---|---|---|---|
| `_person_not_found == True` (key 1 missing) | 2 167 json / 1 057 mobile | **0 of 318** of the 500-dumps carry one | 324 mobile / 9 json |
| `_person_k2_not_found == True` (partial load) | 499 json / 540 mobile | always present | **0** |

and **209 of the 540 mobile partial-load dumps go on to emit a
`SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT 1`** that the real
request in that state never issues. That is the Class-S half, in the same sense
as M-4 and M-6.

Why no check catches it: `cardinality_consistency_audit` (14 010 dumps, 19 466
decisions) **passes** — it compares a note's key shape against the run's own
cardinality decision, and the key shapes here are correct; it never looks at what
the loaded child *is*. `empty_relation_emission_audit` passes, `noteless_call_audit`
passes, and both judges score every one of the seven runs EXACT.

---

### W7-2 — cycle 8 derived the COMMENTS relation's ROW COUNT from its distinct-AUTHOR count; `keys ≤ rows` is a bound, not a determination

**Class B (a real branch deleted) with a Class S consequence (the corpus asserts
"one distinct author ⇒ one comment"). TARGET-LEVEL** — it is `rows_mock` /
`preload_rows_driven?` in the shared list-and-preload toolkit, and it is the exact
converse of DISCIPLINE §13 Rule D, so it must travel with Rule D to every batch.

**Scenario.** `adversary7/G02_rows_vs_keys.rb` post 871 — **ten comments, one
author**, anon, `format: :json`. Also 870 (5 comments/1 author, each with a
mention), 874, 877; G06 932 and 937 (2 comments/1 author, anon and signed-in).

**The real run, verbatim** (`adversary7/runs/G02_rows_vs_keys.json`, 24 statements):

```
SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? ORDER BY "posts"."id" ASC LIMIT ?
SELECT "comments".* FROM "comments" WHERE "comments"."commentable_id" = ? AND "comments"."commentable_type" = ? ORDER BY created_at ASC
SELECT "people".* FROM "people" WHERE "people"."id" = ?
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ?
SELECT "mentions".* FROM "mentions" WHERE "mentions"."mentions_container_id" = ? AND "mentions"."mentions_container_type" = ?     x20
```

One distinct key, **ten rows**, twenty per-row `mentions` reads
(`CommentPresenter#as_json` evaluates `mentioned_people` twice per comment).
The mobile run of the same post: one key, ten rows, **ten** `mentions` reads.

**The code that issues it.** `app/models/comment.rb:36-37`
`scope :including_author, -> { includes(author: :profile) }` /
`scope :for_a_stream, -> { including_author.merge(order('created_at ASC')) }`,
materialized by `CommentPresenter.as_collection` → `Relation#records`
(`app/presenters/base_presenter.rb:15`) and by
`app/views/comments/index.mobile.haml:3  render partial: "comments/comment", collection: comments`.
`comments.author_id` carries no unique index (`db/schema.rb:115-127`) — N comments
by one author is an ordinary state, and it is the very state M-7 was won on.

**What the corpus lacks.** `targets.rb:159-172` and `:775-795`:

```ruby
def preload_rows_driven?(ct, receiver)
  ...
  return false if key_count_free?(r2)      # the comments relation lands here
  ...
end
...
elsif preload_rows_driven?(ct, receiver)
  l.length > 1                             # the cardinality decision — mentions only
  ...
else
  keys = emit_includes_preloads(ct, receiver, rep, owner_rows: len)
  IterableSymbolicList.new([len, keys].max, name: vn, note: sql, representative: rep)
end
```

`len` is never seeded for the comments relation (measured: the `len(...)` seed is
absent in **all 13 835** dumps that record `…_row_author_keys_many`), so its length
is exactly `keys` — 1 when `_author_keys_many == False`, 2 when True. The
`(len > 1)` decision the endpoint's OWN result set used to carry is gone from the
whole corpus:

| relation | `(len(...) != 0)` | `(len(...) > 1)` |
|---|---|---|
| comments, json (`records_1`) | 8 495 T / 35 F | **absent** |
| comments, mobile (`to_a_1`) | 10 680 T / 26 F | **absent** |
| mentions, json (`records_2`) | 7 504 T / 991 F | 1 911 T / 5 593 F |
| mentions, json (`records_3`) | 7 362 T / 949 F | 1 861 T / 5 501 F |
| mentions, mobile (`records_1`) | 4 600 T / 598 F | 1 812 T / 2 788 F |

Dumps carrying BOTH the comments relation's `_author_keys_many` decision and a
`(len > 1)` for that same relation: **0 of 13 835**.

Cycle 7 had it right and said so in the code it deleted
(`_bak_targets_cycle7.rb:704-713`: *"the LIST LENGTH decision stays (0 / 1 / many
is real, and it **BOUNDS** the distinct-key count)"*). Cycle 8's justification —
*"the row count FOLLOWS from it (a second distinct author implies a second
comment)"* — is a one-way implication used as an equality: two distinct authors do
imply two comments, but **one** distinct author implies nothing at all about the
row count.

Why no check catches it: `hardening_lint` H4 counts `len(...)` decisions
corpus-wide (it reports 4, all present with both polarities on the full corpus) and
cannot tell which relation lost one; `cardinality_consistency_audit` reads only the
19 466 relations that DO record a `(len > 1)`, so the one relation whose decision
was removed is invisible to it by construction; both judges compare shapes, and the
shape `people.id = ?` is correct in this state.

---

## 5. Near-misses

| # | finding | why it matters |
|---|---|---|
| **N7-1** | **the `…_profile_not_found == True` arm IS reachable by a real run**, contrary to DISCIPLINE §12's standing statement that the typhoeus/JFFI abort makes every such arm unreachable. G01 856: a MENTIONED person that exists with no `profiles` row, on **mobile**, with a NAMED markup `@{Heidi; heidi@remote.example}` → `SELECT "people".* … "id" = ?` then `SELECT "profiles".* … "person_id" = ?` returning nothing, **200**, 972 bytes. `Mentionable::MentionsInternal.mention_link` takes `display_name` and never calls `person.name`, so `Person#fix_profile` (`person.rb:371-375`) is never entered. The AUTHOR-side arm remains unreachable (`_comment.mobile.haml:11 person_link(comment.author)` has no display name → `person.name` → `fix_profile`). §12 should be narrowed from "every arm" to "every arm on the author and principal trees". |
| **N7-2** | `format: :xml`, `:js` and `:atom` raise `ActionController::UnknownFormat` from `respond_with` **after** the finders have run: anon → multiset `{posts:1}`; signed-in on a share-visible post → `{users:1, posts⋈share_visibilities:1}` and nothing else. Same family as R6's open html item, now measured for four more formats. The corpus has no dump in which a visibility finder SUCCEEDS and no `comments` read follows (the only comment-less successes are the 61 `SubclassNotFound` dumps). `format_coverage_audit` checks html/json/mobile only. |
| **N7-3** | **`Post.exists?` per-render multiplicity now measured across comments**: G07 965 (two comments, one `diaspora://…/post/<guid>` each) issues **2** probes on json and **2** on mobile, bound to two different `comments.text` values; the corpus's four `SYM_PARAM_dlink_guid0..3` parameters all belong to the ONE representative comment. Extends R5-N5-2 / R6-N6-3 from `mentions` to the link family. |
| **N7-4** | `Post.exists?` cardinality reaches **7** in a single comment (G05 914, seven links in one text). The corpus still tops out at 4 (`exists__1..4`). R4-N4-2 / R6's declared limit, re-measured, still open. |
| **N7-5** | **`X_MOBILE_DEVICE` ALONE switches the format** (G04: header only, `format: :html` → 200 / 1 695 bytes, byte-identical to the explicit mobile render), while a mobile `HTTP_USER_AGENT` alone does **not** (→ `MissingTemplate`). This is the opposite of the rule R4 recorded ("the header alone is not enough"), and R4's own quoted formula `!is_tablet_device? && !!headers['X_MOBILE_DEVICE']` implies the result measured here — `force_tablet_html` (`application_controller.rb:150-152`) pins `session[:tablet_view] = false`. No corpus consequence (mobile is a covered format); the ledger line should be corrected. |
| **N7-6** | the same key-1 welding as W7-1 exists on the **author-profile** `has_one` step (`_author_profile_not_found` / `_k2_not_found`): the state "author 1 has a profile, author 2 does not" is modelled as "all authors have one". Unreachable by a real run — `person_link(comment.author)` and `Person#as_api_response`'s `avatar`/`name` both enter `fix_profile`, i.e. the typhoeus/JFFI abort — so this is code-reading only, but it is the same defect class and the same repair. |
| **N7-7** | **INSTRUMENT**: `mock_note_check` and `note_fidelity_audit` judge every statement the traced frames issue, including ones the ADVERSARY's own probes make. G03's `Comment#mentions.pluck(...)` probes scored `NOTE-MISSING`/`STAR-OVER` on `Calculations.pluck` and G06's `Post.find(930)` probe scored `ORDER-DIFF`, none of which the endpoint ever issues. A round that reads a RED without separating probe frames from request frames will file three phantom findings. |

---

## 6. Branches I could not reach, and why

* **`Person#fix_profile` → `DiasporaFederation::Discovery`** — the diagnosed
  typhoeus → Ethon → libcurl/JFFI JVM abort (DISCIPLINE §12). Every path that
  calls `Person#name` on a profile-less person is therefore off limits: the
  comment AUTHOR without a profile (json and mobile), the mentioned person
  without a profile when the markup carries **no** display name, and
  `ActiveRecord::Base#reload` (**B-1**) with it. N7-1 shows one arm of this family
  is in fact reachable; the rest are not.
* **`Mentionable.people_from_string` / `filter_people`** — `render_mentions`
  reaches them only when `disable_hovercards` or `link_all_mentions` is set, and
  neither is settable from a request. 0 calls in 104 requests. Config, not fixture.
* **`Diaspora::Camo`** — `camo_urls` is guarded by
  `AppConfig.privacy.camo.proxy_markdown_images?`; a fixture cannot flip it. It
  issues no SQL either way (G05 915 with `![img](…)` and `<img src=…>` changes no
  statement).
* **`UserPresenter#to_json`** (aspects, contacts, unread counts, services) — reached
  only when a layout renders `include_gon`; `index` renders `layout: false` on
  mobile and `render json:` otherwise, and the html arm dies on `MissingTemplate`
  first. `gon.push` stores the presenter without serialising it. 0 `aspects` /
  `contacts` / `notifications` statements in 104 requests.
* **`Notification`/`Photo`/`conversations` commentables** — the route is
  `/posts/:post_id/comments` and `PostService#find_for_post` queries `posts`
  only; a `Photo` id simply 404s.
* **`people.id IS NULL` in a preload** — Rails 5.2's `owners_by_key` keeps a nil
  key out of the `IN` list, and both FK columns on this endpoint
  (`comments.author_id`, `mentions.person_id`) are `NOT NULL` (G03 probe).
  Structurally unreachable; correctly absent from the corpus.

---

## 7. Files

`adversary7/_common7.rb` (round-6 harness, unchanged apart from paths) ·
`G01_partial_mentions.rb` · `G02_rows_vs_keys.rb` · `G03_unique_index.rb` ·
`G04_formats_auth.rb` · `G05_wider_text_sti.rb` · `G06_key_matrix.rb` ·
`G07_truncation.rb` · `run7.sh` · `chain7.sh` · `an7.py` ·
`runs/*.log`, `runs/*.json`, `runs/*.judge.txt`, `runs/_body_*.txt`,
`runs/_done.log`, `runs/_batch_md5_before.txt`.
Nothing outside `adversary7/` was written except this report and the ledger
appends in `reports/diaspora/docs/ADVERSARY_WINS.md` (2 wins, 7 near-misses,
matrix rows T-t / T-u, one round-log line).

**Concurrency note.** While this round ran, the batch agent independently touched
`completion_config.json` (adding `h6_answered` waivers for `reload` and
`ci_public_first`), `AGENT_RUN.md` and the `_audit_*.out` files, 06:21–06:24.
The corpus itself was untouched — `coverage_summary.json` 06:09, `targets.rb`
04:24, all 14 010 `dump_*.json` unchanged — so every figure above is against the
cycle-8 corpus this round was pointed at.
