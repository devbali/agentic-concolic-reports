# ADVERSARY ROUND 6 — comments_index (`CommentsController#index`, GET /posts/:post_id/comments)

Date 2026-08-29. Corpus under attack: the rebuild after round 5's three wins were
closed — engine `complete: true`, 73 PC nodes, **16 895 dumps** / 13 804 runs /
290 424 PCs, 0 missing, assumptions 2 806/2 806 PASS, shims 19 PASS / 11 PROTOCOL /
0 red, note check green, and all seven scripted checks green on this corpus.

**Verdict: 3 wins.** All three are TARGET-LEVEL and all three live in the *new*
machinery — the M-7/M-8 distinct-key model applied in cycle 7. All three are
**Class S (over-emission at the state level)**: the corpus asserts statement pairs
and statement/state combinations that ActiveRecord cannot emit against this schema.
6 609 of 16 895 dumps (39 %) carry at least one of them. **Both judges score every
one of them EXACT**, because both are shape-level and neither reads the run's own
decisions — exactly the instrument gap round 5 recorded as N5-4.

The four items the brief flagged as unproven (B-8's four falsy arms, the
`exists_probe` deletion, M-7/M-8's key model, the withdrawn engine rejection) were
all attacked with real runs. B-8 and the `exists_probe` deletion come back **clean**;
the key model does not.

## Ops

| | |
|---|---|
| manifests | `adversary6/E01_key_model.rb … E06_probes.rb` (+ `_common6.rb`, `run6.sh`, `chain6.sh`, `an6.py`) |
| JRuby processes | **7** (E03 ran twice — the first died on a fixture INSERT, `aspects` has no `contacts_visible` column on this schema; counted as a process) |
| requests | **97** HTTP requests + **10** non-request probes |
| JVM aborts | **0** (no scenario was built to reach `Person#fix_profile`; every person any render calls `.name` on has a `profiles` row) |
| invocation | `unset JAVA_TOOL_OPTIONS`; `flock /tmp/concolic-slot.lock scripts/diaspora-concolic …concrete_run_probe.rb <manifest>` **inside** `systemd-run --user --pipe --wait -p MemoryMax=4000M -p MemorySwapMax=0`; one scenario per process; chained by `chain6.sh` appending DONE lines to `runs/_done.log`, waited on with an until-loop and re-read directly |
| batch `concrete_run.json` | md5 `7a39dcea7e97030ec9a10fb77adfcdd1` **before and after** (`adversary6/runs/_batch_md5_before.txt`); the probe writes into `adversary6/` because the manifests live there |
| judges | `mock_note_check.py` and `tools/note_fidelity_audit.py` per run, with `concrete_aliases.json`; measurement SQL kept out of the judged manifests (E06 is probe-only) |
| rules | real app only — fixture ROWS, session/user, params, headers, format. Nothing under `src/`, the app, or the batch's runner/targets/mocks was read for a reference or edited. No REFERENCE/diff_*/OURS_/SUBSET_/_progress.json/unknown.txt was opened; `/home/dev/_reference_locked` untouched; no `git checkout`/`git show` under `ruby_examples/dse-apps/policies` |

Judges on all five judged runs:

```
### mock_note_check      RESULT: every SQL-issuing target's notes match its real statements.   (EXIT=0, all five)
### note_fidelity_audit  MISSING 0 · STAR-OVER 0 · AGG-COLLAPSE 0 · PROJ-DIFF 0 · PRED-OP-DIFF 0
                         LIMIT-DIFF 0 · ORDER-DIFF 0 · PRED-DIFF 0 · EXACT 13/15/13/12/15
                         RESULT: every real statement has a projection-faithful note.   (EXIT=0, all five)
```

Depth-0 target census over all 97 requests — every name is a corpus target except
`escape_segment`, which is the B-2 shim and issues 0 SQL under its own frame:

```
ActiveRecord::Relation#records                          1148
ActiveRecord::Relation#to_a                              318
ActionDispatch::Journey::Router::Utils.escape_segment    266   (shim, 0 SQL)
ActiveRecord::FinderMethods#first                        264
ActiveRecord::FinderMethods#exists?                       76
ActionController::Rendering#_set_rendered_content_type    73
ActionController::Metal#status=                           61
ActiveRecord::Associations::SingularAssociation#find_target 10
```

The 97 requests issued **26 distinct SELECT shapes** (30 statements including the
probes' own INSERT/DELETE/PRAGMA). **No new SQL shape**: the endpoint's statement
universe is closed and matches rounds 1–5's. Every win below is therefore about
*which corpus states* those shapes are asserted in, not about a missing shape.

---

## 1. Re-verification of EVERY prior finding, at projection level

`=`/`IN`, LIMIT and ORDER BY are the judge's new dimensions (DISCIPLINE §12); each
row says whether the closure was re-established by a REAL RUN this round or only by
reading the corpus.

| # | finding | how re-verified in round 6 | verdict |
|---|---|---|---|
| M-1 | `Post.exists?(guid:)` from `diaspora_links` | E04, 15 requests: **38** real `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?`, json (`plain_text_for_json`) and mobile (`markdownified`), anon and signed-in. Corpus note `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = $$(SYM_PARAM_dlink_guid<0..3>_…) LIMIT 1` — projection `1 AS one` ✓, pred-op `=` ✓, LIMIT ✓, no ORDER ✓ | **verified (real run)** |
| M-2 | `:mobile` format family | mobile reached three ways: explicit `format: :mobile` (E01/E02/E04/E05), `session[:mobile_view]=true`+html (E03, 850 bytes), `X_MOBILE_DEVICE`+iPhone UA+html (E03, byte-identical 850 bytes). `Relation#to_a` **318** depth-0 calls | **verified (real run)** |
| M-3 | `Mention belongs_to :person` not-found decision | E05 `742`/`743`/`744`. Dangling row, no markup → json 200 `"mentioned_people":[null]`, mobile **200**; dangling row **with** markup → mobile `ActionView::Template::Error: undefined method 'diaspora_handle' for nil:NilClass` (N5-5's refinement holds). Statement half verbatim: `SELECT "people".* … "id" = ?` **then STOP** — no `profiles` read (E05 segs 15/16/17). Corpus carries `…_row_person_not_found` on both arms (8 337 / 8 086 dumps) | **verified (real run)** |
| M-4 / B-5 | preload notes over an EMPTY relation | E05 `740` (0 comments) anon json / anon mobile / auth json: exactly **two** statements — the post finder and `SELECT "comments".* … ORDER BY created_at ASC` — and nothing else; bodies 2 bytes / 68 bytes. `741` (0 mentions): no `people`/`profiles` beyond the author preload. `empty_relation_emission_audit`: 145 empty-list states, 0 notes | **verified (real run)** |
| M-5 | `users.language` third arm (`I18n::InvalidLocale`) | E05, one uid per principal: `uid 41 language "xx"` and `uid 42 language ""` → `EXC I18n::InvalidLocale`, and the **entire** data access is one statement `SELECT "users".* FROM "users" WHERE "users"."id" = ? ORDER BY "users"."id" ASC LIMIT ?` (segs 01/02). Controls `nil` (uid 43) and `pl` (uid 44) → 200. Corpus: 7 dumps take `…_language == StringVal('xx')` True and contain **exactly one** `symbolic_call` | **verified (real run)** |
| M-6 | `posts.type` out of the STI tree | E03 `725` type `Photo`, by id and by 19-char guid → `ActiveRecord::SubclassNotFound: Invalid single-table inheritance type: Photo is not a subclass of Post`; whole access = the post finder. Corpus carries the decision on **all four** finder arms: `first_1_type` 7 829, `ci_vis_first_1_type` 6 683, `ci_author_first_1_type` 1 904, `ci_public_first_1_type` 422; `type` is in `pc_gate_columns` and VISIBLE (16 838 refs) | **verified (real run)** |
| M-7 / T-o | preload predicate follows the DISTINCT KEY COUNT | E01 `705` 2 comments / 1 author → `people.id = ?` then `profiles.person_id = ?`; `700` 3 comments / 2 authors → `IN (?, ?)` / `IN (?, ?)`; `704` 4 / 4 → `IN (?, ?, ?, ?)` twice; E06 probe 03/04 measured directly. Corpus mints `…_keys_many` per step | **verified for the `comments.author_id` step; NOT verified for the `mentions.person_id` step — see WIN 6-2** |
| M-8 / T-p | nested step follows the parents ACTUALLY LOADED | E01 `702` — one comment, three `mentions`, one dangling: `SELECT "people".* … "id" IN (?, ?, ?)` **then** `SELECT "profiles".* … "person_id" IN (?, ?)`. Corpus mints `…_person_k2_not_found` (1 133 / 792 / 645 dumps) and reaches loaded-counts 0/1/2 | **verified as a branch; the DERIVATION is only an upper bound — see WIN 6-1** |
| M-9 / B-8 | a falsy-returning mock loses its statement | see §2 below | **verified (real run) — closed** |
| B-1 | `reload` is a target | not reachable by a real run on this rig (`fix_profile` → Discovery → JVM abort, N4-1). Corpus: 5 383 `reload` events, note `SELECT "people".* … "id" = $$(…_row_author_id) LIMIT 1`, exactly matching the 5 383 `CommentsInertDiscovery.fetch_and_save` events and the 5 383 post-reload `profiles` `find_target` reads | corpus/code-verified only (unchanged, stated) |
| B-2 | `escape_segment` is a shim, not a target | **266** depth-0 calls across 97 requests, **0 SQL** under its own frame, **0** corpus events | **verified (real run)** |
| B-6 | never raise inside a `returns` lambda | on this batch every `finder_mock_faithful` is `raise_on_missing: false` (`targets.rb:1182, 1530, 1739`) and the STI arm returns the `UninstantiableRow` poison, so no target lambda raises. Latent defect remains — near-miss **NM-1** | verified inert here |
| B-7 | `=` vs `IN` follows cardinality; length domain 0/1/many | superseded by M-7/T-o; `(len(X) != 0)` and `(len(X) > 1)` both present for every list | verified (superseded) |
| R2 D1 | array `post_id` models the wrong `post_key` branch | corpus now carries **no** `IN` note on the post finders at all — `first` has exactly two notes, `posts.id = $$(SYM_PARAM_post_id)` and `posts.guid = $$(SYM_PARAM_post_id)`; and `post_id` is a path segment | **verified closed** |
| R2 D2 | the principal `profiles` read unbound | E05 `lang_pl` (uid 44): real `SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ? LIMIT ?` under `find_target`; corpus note binds `$$(…devise_user_first_1_person_id)` — projection ✓, LIMIT ✓ | **verified (real run)** |
| R2 D3 | `mention_lookup_*` over-emission | no `mention_lookup_*` target survives (the corpus has 15 target names); `Diaspora::Mentionable.people_from_string` and `Person.find_or_fetch_by_identifier` fired **0** times in 97 requests; `concrete_aliases.json` no longer lists them | **verified closed** |
| R2 D4 | `guid == ''` phantom branch | absent from the 73-shape PC universe | **verified closed** |
| R2 D5 | `User has_one :person` pinned found | E05 uid 45 (no `people` row): visible post → 200; non-visible → `NoMethodError: undefined method 'id' for nil:NilClass` after `SELECT posts.* … INNER JOIN share_visibilities …` and `SELECT "people".* … "owner_id" = ? LIMIT ?` and **nothing else** (`lib/evil_query.rb:116`). Corpus `…_person_not_found` 6 547 dumps | **verified (real run)** |
| R2 D6 | `Post.exists?` cardinality | corpus chain tops out at 4 (`exists__1..4`: 3 791 / 1 326 / 500 / 1 311 dumps at 1/2/3/4 calls, 802 dumps at 0 with a `comment`-entity link). E04 `733` renders **5** and `734` renders **7** per request | **still a declared limit** ("4 = four or more"), not closed |
| R2 D7 | boolean quoting (instrument) | signed-in public arm exercised for real: E02 `713` → `SELECT "posts".* … "id" = ? AND "posts"."public" = ? …` returns the row, 200 | **verified closed** |
| R2 D8 | `find_target` duplicating the bulk preload | census over 16 895 dumps: every `profiles` `find_target` note is either the principal's (`…devise_user_first_1_person_id`, the `set_grammatical_gender` read — real, E05 seg 05) or post-`reload`; **0 unexplained duplicates** (`profiles_find_target` counts 0/1/2/3 all matched by a reload or the principal) | **verified closed** |
| R2 D9 | json collection-length decision / blank text / FK fact | `(len(…_records_1_rows) != 0)` present on the json path (16 489 dumps); blank-text early return statement-neutral (N4-5); the `add_foreign_key "profiles", "people"` fact is stated correctly in `targets.rb §8c` | **verified closed** |
| N5-1 | `UninstantiableRow` poison incomplete | unchanged and still structural, not reachable here (`find_public!` routes through `tap`, the signed-in path through `post.comments`) | open (cross-endpoint) |
| N5-2 | per-row statement multiplicity | still open: a real 3-comment json render issues **six** `mentions` SELECTs (E01 seg 01), a 4-comment one **eight** (seg 08); the corpus carries at most two per dump | open, restated |
| N5-5 | M-3's mobile 500 needs mention MARKUP | re-confirmed: E05 `742` (dangling row, plain text) → mobile **200** (878 bytes); `743` (same row + markup) → mobile 500 | confirmed |
| N5-6 | anon `set_locale` inert | not re-attacked (round 5 proved `AVAILABLE_LANGUAGE_CODES − I18n.available_locales == []`); E06 probe 07 re-measured `I18n.enforce_available_locales == true` | confirmed |

---

## 2. The four items that were new since round 5

| item | what was verified | verdict |
|---|---|---|
| **B-8 — four falsy arms publish their note via `Thread.current[:concolic_pending_note]`** | **Real ground truth (E02, 25 requests).** Anon miss = exactly one statement `SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? ORDER BY "posts"."id" ASC LIMIT ?` then 404/0 bytes. Signed-in triple miss = `join`, `…author_id = ?`, `…public = ?` then 404. `exists?` false still issues `SELECT 1 AS one … guid = ? LIMIT ?`. Interleavings driven: miss→hit, hit→miss, miss→miss, false-`exists?`→hit, `exists?`→miss, guid-miss→guid-hit, and the same on mobile. **Corpus side:** (a) **0** note-less `symbolic_call` events outside the three documented walls (`_set_rendered_content_type` 15 063, `Metal.status=` 8 662, `Head.head` 24) — the 3 551 note-less events of M-9 are gone; (b) **recorded exactly once**: every finder appears 0 or 1 times per dump, never twice (`ci_vis_first` 9 005/1, `ci_author_first` 2 317/1, `ci_public_first` 422/1, `first` 7 829/1, `devise_user_first` 9 052/1); (c) **right shape on the miss arm**: `ci_vis_first` 2 348 miss events, `ci_author_first` 432, `ci_public_first` 10, `first` 14 — all carrying the finder's own SQL; (d) **no leak**: 0 pairs of adjacent `symbolic_call` events on different targets sharing a note, and every target's note set is semantically its own (`find_target` → people/profiles only, `records` → comments/mentions only, `exists?` → the `1 AS one` probe only). The anon-404 dump `dump_anon_json_dse0003.json` now carries `SELECT "posts".* … LIMIT 1` on the event | **clean — B-8 closed** |
| **`Anonymous.exists_probe` DELETED** | no such target in the corpus's 15 target names; **0** dumps mention `exists_probe`; 0 hits in `coverage_summary.json`, `_assumptions_declared.json`, `assumption_manifest.json`, `concrete_aliases.json`, `run_dse.rb`, `coverage_assumptions.py`, `shim_tests.rb`. The only surviving occurrence is a comment at `targets.rb:1200`. `FinderMethods#exists?` carries the existence probe itself: 14 026 events, 8 distinct notes, all `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = $$(…) LIMIT 1` — never `SELECT posts.*` | **clean — no phantom target, no producer edge, no alias** |
| **M-7/M-8 — per-step DISTINCT-KEY count** | all four shapes driven for real (E01): 3 comments / 2 authors, an author who is also the mentioned person, a nested step with 2 loaded + 1 missing parent, and 2 comments / 1 author. The key model **breaks in three places** | **BROKEN — WINS 6-1, 6-2, 6-3** |
| **withdrawn engine rejection: `Length(post_id) < 16` × `ci_vis_first_1_type == 'Photo'`** | `_never_declare` in `coverage_assumptions.py:483-490` now covers param × the STI decision only; the pair is explored, and both `ci_vis_first_1_type` (6 683) and `Length(SYM_PARAM_post_id) < 16` (16 874) are live. Real: E03 drove the out-of-tree row on both key branches (by id and by 19-char guid) and by both anon and signed-in entry (R5 D03 covered all four finder arms) | **clean — the pair is reachable and modelled** |

---

## 3. New scenarios (round 6)

| manifest | scenario | result |
|---|---|---|
| E01 | `700` 3 comments / 2 distinct authors, json + mobile | 200 — `people.id IN (?,?)` → `profiles.person_id IN (?,?)` |
| E01 | `701` two authors where one is also the mentioned person, json + mobile | 200 — author tree `IN(2)`→`IN(2)`, mention tree `= ?`→`= ?` |
| E01 | `702` one comment, three mentions, one dangling (2 loaded + 1 missing) | 200 — `people.id IN (?,?,?)` → `profiles.person_id IN (?,?)` |
| E01 | `703` one comment, two LIVE mentions, json + mobile | 200 — `IN (?,?)` → `IN (?,?)` (never `= ?`) |
| E01 | `704` 4 comments / 4 distinct authors | 200 — `IN (?,?,?,?)` twice |
| E01 | `705` 2 comments / 1 author (M-7 control) | 200 — `= ?` → `= ?` |
| E01 | `706` one mention (cardinality-1 control); `707` two comments, one mention each, SAME person | 200 — each relation has one row → `= ?` |
| E01 | `708` signed-in, share-visible, 3 comments / 2 authors, json + mobile | 200 — same key model on the signed-in path |
| E02 | anon finder miss → hit → miss → miss → hit (json), miss → hit (mobile) | 404/200 alternating; one statement per miss |
| E02 | anon, existing but NON-public post | 401 `throw :warden`; **one** statement (the id finder), then `Diaspora::NonPublic` → `authenticate_user!` |
| E02 | signed-in: vis hit / vis-miss + author hit / vis-miss + author-miss + public hit / three misses (×2) / hit after miss; mobile variants | 200/200/200/404/404/200/404/200 |
| E02 | `exists?` FALSE between two finders; false→true in one text; miss right after an `exists?` | `SELECT 1 AS one … guid = ? LIMIT ?` issued on the false arm too |
| E02 | guid-keyed miss (anon and signed-in) and guid-keyed hit | 404/404/200 |
| E03 | Reshare with a **missing** `root_guid`, json + mobile + signed-in | 200 — statement set identical to a `StatusMessage`; E06 probe 10 confirms `Reshare#root` is `nil` and nothing is issued at instantiation |
| E03 | Reshare with a live root; Reshare whose root is PRIVATE | 200, 200 — no `posts` read for the root |
| E03 | `posts.type = "Photo"` by id and by guid | `SubclassNotFound` ×2 (M-6) |
| E03 | key boundary: numeric id, 19-char guid, **16-char all-numeric guid**, **15-digit numeric id**, `"0000000000000726"` (16 chars → guid branch), `"726 "` (trailing space → id branch) | 200 / 200 / 200 / 200 / **404** / 200 |
| E03 | `728` remote closed-account author (blank-name profile) + other-pod author + local author + a mention of a third-pod person; anon json, anon mobile, signed-in mobile | 200 ×3 — no new statement |
| E03 | `729` signed-in, share-visible private post whose comments are by a **blocked** author (a real `blocks` row) and by a **contact** (real `contacts` + `aspects` + `aspect_memberships` rows) | 200 — **no `blocks`, `contacts`, `aspects`, `aspect_memberships` statement of any kind** |
| E03 | format × auth: html anon, html signed-in, xml, js, `session[:mobile_view]`+html, `X_MOBILE_DEVICE`+UA+html, `Accept: */*` | `MissingTemplate` ×2, `UnknownFormat` ×2, 200 (mobile) ×2, 200 (json) |
| E04 | `731` a `diaspora://…/comment/<guid>` link ONLY, json + mobile | 200 — **zero** `exists?` (the `&&` short-circuits) |
| E04 | `732` comment-link FIRST, post-link SECOND, json + mobile | 200 — exactly ONE `exists?`, on the second link's guid |
| E04 | `733` five post links (3 hit / 2 miss), json + mobile + signed-in; `734` seven links all miss | 200 — 5 and **7** `exists?` per render |
| E04 | `735` the same guid twice in one text | 200 — two `exists?` |
| E04 | `736` setext heading + bold/em/code + `<3` + `#tag` + two bare URLs + a markdown image + a markdown link + `web+diaspora://` + `diaspora://…/status_message/<guid>` + unicode; json + mobile + signed-in mobile | 200 ×3 — one `exists?` (the `web+diaspora://` post link); `status_message` entity issues none |
| E04 | `737` two comments, one link each; `738` a mention AND a link in one comment, json + mobile | 200 |
| E05 | five principals, one uid each: `language` `"xx"` / `""` / `nil` / `"pl"`(+gender) / a user with **no `people` row** | 500 / 500 / 200 / 200 / 200 + `NoMethodError` |
| E05 | 0 comments (anon json, anon mobile, auth json), 0 mentions (json + mobile) | 200 — two statements each on the empty-comments arm |
| E05 | dangling mention without markup / with markup / mixed live+dangling, json + mobile | 200 / mobile 500 / 200 |
| E06 | 10 non-request probes (unique index, index list, Preloader key model ×3, STI, locales, PRAGMA, the regex, Reshare root) | see §4 |

---

## 4. WINS

All three are **Class S** — the corpus asserts evidence the application cannot
produce — and all three are **TARGET-LEVEL**: the cause is
`emit_includes_preloads`, the shared association/preload emitter that every batch
inherits (this batch's copy is `targets.rb:178-266`). None of them is a missing
shape; each is a *state* in which a real shape is asserted although ActiveRecord
cannot reach it. Both judges score every affected run EXACT.

### WIN 6-1 (ledger **M-10**) — the NESTED preload step's key count is a FREE DECISION although the parents determine it

**Scenario.** E01 `703`: public post, one comment by person 2, whose text carries
two `mentions` rows pointing at two *live* people (5 and 6), both with `profiles`
rows. Anon, json and mobile. Control: E01 `700` (3 comments / 2 distinct authors),
`704` (4 / 4), `708` (the same signed-in). Probe: E06 `05-nested-after-IN`.

**The real statements, verbatim** (E01 seg 06, `runs/E01_key_model.json`):

```sql
SELECT "posts".*    FROM "posts" WHERE "posts"."id" = ? ORDER BY "posts"."id" ASC LIMIT ?
SELECT "comments".* FROM "comments" WHERE "comments"."commentable_id" = ? AND "comments"."commentable_type" = ? ORDER BY created_at ASC
SELECT "people".*   FROM "people"   WHERE "people"."id"        = ?
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ?
SELECT "mentions".* FROM "mentions" WHERE "mentions"."mentions_container_id" = ? AND "mentions"."mentions_container_type" = ?
SELECT "people".*   FROM "people"   WHERE "people"."id"        IN (?, ?)
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" IN (?, ?)
```

Two parents loaded ⇒ the nested step is `IN (?, ?)`. **`= ?` never follows an `IN`
whose keys all loaded** — measured over 97 requests / 26 distinct SELECT shapes:
`people.id IN (…)` is followed by `profiles.person_id IN (…)` with **exactly one
bind per LOADED parent**, in every one of the 21 `IN (?,?)` + 5 `IN (?,?,?)` +
1 `IN (?,?,?,?)` occurrences. E06 probe 05 isolates the mechanism: after
`DELETE FROM profiles WHERE person_id = 5`, the same preload still emits

```sql
SELECT "people".*   FROM "people"   WHERE "people"."id"        IN (?, ?)
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" IN (?, ?)
```

— the nested step keys on the loaded **parents**, never on which children exist.

**The corpus shape it contradicts, verbatim** (`dump_anon_json_dse0057_d1.json`,
`dump_anon_json_dse0090.json`, …):

```
Anonymous.load_intermediate
  SELECT "people".*   FROM "people"   WHERE "people"."id" IN ($$(SYM_RESULT_ActiveRecord__Relation_records_1_row_author_id), $$(SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id))
Anonymous.load_intermediate
  SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = $$(SYM_RESULT_ActiveRecord__Relation_records_1_row_author_id)

with, in the same dump:
  (len(SYM_RESULT_ActiveRecord__Relation_records_1_rows) > 1)                       True
  (SYM_RESULT_ActiveRecord__Relation_records_1_row_author_keys_many == True)        True
  (SYM_RESULT_ActiveRecord__Relation_records_1_row_author_profile_keys_many == True) False
  (SYM_RESULT_ActiveRecord__Relation_records_1_row_author_profile_not_found == True) False
```

and the same on the mentions tree with **both** parents loaded
(`dump_anon_json_dse0122.json`):

```
  SELECT "people".*   FROM "people"   WHERE "people"."id" IN ($$(…_records_2_row_person_id), $$(…_records_2_row2_person_id))
  SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = $$(…_records_2_row_person_id)
  (…_records_2_row_person_not_found    == True)  False
  (…_records_2_row_person_k2_not_found == True)  False        <- BOTH parents loaded
  (…_records_2_row_person_profile_keys_many == True) False
```

**Scale:** `comments.author_id → people → profiles` **1 032 dumps**;
`mentions.person_id → people → profiles` with both parents loaded **839 dumps**
(842 note-pairs). Cross-tab of outer→nested operator over all 16 895 dumps:

```
author  = → =   15 006     author  IN → IN     652     author  IN → =   1 032   <- impossible
person  = → =   16 513     person  IN → IN     412     person  IN → =   2 158
                                                       of which 839 have BOTH parents loaded  <- impossible
```

**Issuing code.** `targets.rb:262`
`emit.call(child, r2.klass, nested, n_loaded) if nested && child && n_loaded.positive?`
passes the loaded-parent count down, but `targets.rb:214-219` then treats it as a
mere upper bound and re-decides:

```ruby
keys = [bindv]
if n_keys > 1
  km = "#{base}_keys_many"
  if symbool(km, ct.seed_for(km, false), note: (owner_rep.concolic_note rescue nil)) == true
    k2 = second_key(ct, owner_rep, owner_col)
    keys << k2 if k2
  end
end
```

The nested step here is `Person has_one :profile` (`app/models/person.rb:25`),
which keys on the parent's **primary key**: `activerecord-5.2.4.3`
`preloader/association.rb` does `owners.group_by { |o| o[owner_key_name] }` and then
`predicate_builder/array_handler.rb` picks equality only for a ONE-element key set.
N loaded `Person` records have N pairwise-distinct `id`s, so the nested key count
**is** N. It is not a degree of freedom, and the `_..._profile_keys_many` decision
is a branch the database cannot take.

**Class S** (over-emission; no branch is missing — the correct `IN`→`IN` state is
also in the corpus — but 1 871 dumps additionally assert a pair AR cannot emit,
and the extracted policy inherits a single-row `profiles` read for a state whose
own people read was bulk). **TARGET-LEVEL.**

**Why no check caught it.** `note_fidelity_audit` compares each real statement
against the corpus's *set* of notes; both `profiles.person_id = ?` and
`… IN (?,?)` exist corpus-wide, so every real statement matches something —
EXACT, 0 PRED-OP-DIFF. This is precisely round 5's N5-4: the judge never asks "does
the corpus's model of the state this statement was issued IN produce this shape".

### WIN 6-2 (ledger **M-11**) — on the `mentions` tree the OUTER key count is determined too: a UNIQUE index makes it the row count

**Scenario.** E01 `702` (one comment, three `mentions` rows, three distinct people)
and `703` (two `mentions` rows, two distinct people), anon json/mobile; E06 probe 01.

**Real, verbatim** (E01 seg 05, post `702`):

```sql
SELECT "mentions".* FROM "mentions" WHERE "mentions"."mentions_container_id" = ? AND "mentions"."mentions_container_type" = ?
SELECT "people".*   FROM "people"   WHERE "people"."id" IN (?, ?, ?)
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" IN (?, ?)
```

and E06 probe `01-mentions-unique-index-dup`, inserting a second `mentions` row
with the same `(person_id, mentions_container_id, mentions_container_type)`:

```
[adv6] PROBE 01-mentions-unique-index-dup -> ActiveRecord::RecordNotUnique:
  org.sqlite.SQLiteException: [SQLITE_CONSTRAINT] Abort due to constraint violation
  (UNIQUE constraint failed: mentions.person_id, mentions.mentions_container_id, mentions.mentions_container_type)
[adv6] PROBE 02-mentions-index-list -> OK
  [["index_mentions_on_person_id", ["person_id"], false],
   ["index_mentions_on_person_and_mc_id_and_mc_type",
    ["person_id", "mentions_container_id", "mentions_container_type"], true], …]
```

`db/schema.rb:207` — `t.index ["person_id", "mentions_container_id",
"mentions_container_type"], name: "index_mentions_on_person_and_mc_id_and_mc_type",
unique: true`. A comment's `mentions` relation fixes `mentions_container_id` and
`mentions_container_type`, so its `person_id` values are **pairwise distinct**: the
distinct-key count of the `mentions → person` preload step IS the row count.

**The corpus state it contradicts, verbatim** (`dump_anon_json_dse0017_t1.json`,
`dump_anon_json_dse0021.json`, …):

```
  (len(SYM_RESULT_ActiveRecord__Relation_records_2_rows) > 1)                  True
  (SYM_RESULT_ActiveRecord__Relation_records_2_row_person_keys_many == True)   False
Anonymous.load_intermediate
  SELECT "people".* FROM "people" WHERE "people"."id" = $$(SYM_RESULT_ActiveRecord__Relation_records_2_row_person_id)
```

i.e. two-or-more `mentions` rows on ONE comment collapsing to ONE distinct
`person_id` — a state no database this schema allows.

**Scale: 4 081 dumps, 4 299 occurrences.** Cross-tab over 16 895 dumps:

```
mentions relation, len>1 :  keys_many=True  2 894      keys_many=False  4 299   <- impossible
comments relation, len>1 :  keys_many=True    758      keys_many=False  1 708   <- correct (M-7)
```

The 1 708 comment-tree dumps are the *right* answer (two comments may share an
author — `comments.author_id` carries no uniqueness constraint within a post). The
M-7 repair was applied to both trees although the fact that licenses it holds only
for one.

**Issuing code.** `targets.rb:265`
`iv.each { |spec| emit.call(rep, owner_klass, spec, owner_rows > 1 ? 2 : 1) }` —
the top-level key count is a free decision bounded by the row count, with no
notion of whether the bound column is unique within the owner set. Real
counterpart: `lib/diaspora/mentions_container.rb:19`
`mentions.includes(person: :profile).map(&:person)`.

**Class S** (over-emission). **TARGET-LEVEL** — every batch that preloads through a
uniquely-indexed association column inherits it.

### WIN 6-3 (ledger **M-12**) — the SECOND key is TWO variables for ONE fact

**Scenario.** E01 `700` / `704` / `708` (any state with two or more distinct
authors), and the mentions equivalent (`702`, `703`).

**Real.** ActiveRecord binds the nested `profiles` step to the primary keys of the
records the `people` step returned — by construction the same values, and in the
same order. E06 probe 03 shows the pair for two distinct authors:

```
SELECT "comments".* FROM "comments" WHERE "comments"."commentable_id" = ? AND "comments"."commentable_type" = ?
SELECT "people".*   FROM "people"   WHERE "people"."id"        IN (?, ?)
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" IN (?, ?)
```

**The corpus notes, verbatim** (`dump_anon_json_dse0009_d1.json`):

```
Anonymous.load_intermediate
  SELECT "people".*   FROM "people"   WHERE "people"."id" IN (
      $$(SYM_RESULT_ActiveRecord__Relation_records_1_row_author_id),
      $$(SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id))
Anonymous.load_intermediate
  SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" IN (
      $$(SYM_RESULT_ActiveRecord__Relation_records_1_row_author_id),
      $$(SYM_RESULT_ActiveRecord__Relation_records_1_row_author2_id))
```

The **first** key is ONE variable on both levels
(`…_records_1_row_author_id`) — which is exactly right: the person's `id` and the
comment's `author_id` are the same fact, and the fold therefore chains
`people.id = comments.author_id` for that row. The **second** key is two unrelated
names: `…_records_1_row2_author_id` (minted from the *comment* rep, note = the
comments SELECT, so the fold binds it to `comments.author_id`) at the outer level,
and `…_records_1_row_author2_id` (minted from the *person* rep, note = the people
preload, so the fold binds it to `people.id`) at the nested level. **No path
condition and no declared assumption links them** — `grep -c row_author2_id
_assumptions_declared.json` → `0`, and neither name appears in the 73-shape PC
universe.

Consequence: for the second row the extracted policy loses the
`people.id = comments.author_id` chain that it correctly records for the first, and
asserts a `profiles` read keyed on a value **no preceding query in the run
produced**. This is cross-endpoint pattern 7 ("one fact, one variable") — the same
class as the conversations_index `pluck`-with-its-own-length defect that made
`SELECT people.* WHERE id = nil` reachable.

**Scale: 1 064 dumps, 1 064 note-pairs** — `records_1` author 364, `to_a_1` author
288, `records_1` person 207, `records_3` person 113, `records_2` person 92.

**Issuing code.** `targets.rb:148-155`

```ruby
def second_key(ct, owner_rep, col)
  idv = owner_rep.concolic_attrs["id"]
  pre = (idv.sym_name.sub(/_id\z/, "") if idv.respond_to?(:sym_name) && idv.sym_name)
  return nil unless pre
  vn = "#{pre}2_#{col}"
  ...
```

the name is derived from **whichever rep is the owner at that level**, so the same
physical row gets one name as "the second comment's `author_id`" and another as
"the second person's `id`". The first key escapes this only because the belongs_to
rep is minted with base `<owner>_author`, which makes its `id` attribute *literally*
the owner's `author_id` variable.

**Class S.** **TARGET-LEVEL.**

---

## 5. Near-misses (real defects, no novel shape)

**NM-1 — the pending-note channel has no `ensure`; a raising mock both loses its
own event and poisons the next one.** `CallInterceptor.extract_note`
(`src/ruby_runtime/call_interceptor.rb:248-262`) clears
`Thread.current[:concolic_pending_note]` when it reads it, and it is only ever
called from `push_record` **after** the `returns` lambda returns
(`call_interceptor.rb:149-180`). `finder_mock_faithful` sets the pending note and
*then* may raise:

```ruby
Thread.current[:concolic_pending_note] = sql
raise ActiveRecord::RecordNotFound, "concolic: empty result for: #{sql}" if raise_on_missing
next nil
```

On that path no `symbolic_call` event is written (B-6) **and** the note stays on the
channel, so the *next* target call whose result carries no note of its own inherits
it. Inert on comments_index — every `finder_mock_faithful` / `finder_mock` here is
`raise_on_missing: false` (`targets.rb:1182, 1530, 1739`) and the STI arm returns
the `UninstantiableRow` poison — and the corpus is measurably clean (0 adjacent
same-note different-target pairs; every target's note set is semantically its own).
But it is a latent trap in the shared boundary for any batch that keeps a raising
finder (`find`, `find_by!`, `first!`, `take!`). Cheap fix: wrap the publish in
`begin … ensure Thread.current[:concolic_pending_note] = nil end`, or clear it at
the top of `declare_target`'s wrapper.

**NM-2 — `Post.exists?` cardinality still tops out at 4 while real renders reach 7.**
E04 `734` (seven post links in one comment) issues seven
`SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?` in one request;
`733` issues five. The corpus's chain is `exists__1..4`. Declared as "4 stands for
four or more" since R4-N4-2; restated because the *guids* are then four variables
standing for seven distinct text-derived parameters.

**NM-3 — per-row statement multiplicity (N5-2) is unchanged and is now measurable
against a bigger spread.** A 3-comment json render issues **six** `mentions`
SELECTs (E01 seg 01 — `mentioned_people` is *not* memoised, and
`CommentPresenter#as_json` evaluates it twice per comment: once through
`@comment.message` and once through `@comment.mentioned_people`); a 4-comment json
render issues **eight** (seg 08); a mobile render issues one per comment. The
corpus carries at most two `mentions` note events per dump at any cardinality.

**NM-4 — the `IN` arity is capped at 2 on both preload levels.** Real renders reach
`IN (?, ?, ?)` (E01 `702`, `704` mentions) and `IN (?, ?, ?, ?)` (E01 `704`
authors); the corpus's `keys` array holds at most two binds and the judges wildcard
literal lists, so this scores EXACT. Consistent with M-7's stated "2 stands for two
or more" convention, but it interacts with WIN 6-2: on the `mentions` tree the arity
is not a convention, it is the row count.

**NM-5 — the mention display name is still compared against a concrete literal.**
`(SYM_RESULT_…_records_1_row_person_diaspora_handle == StringVal('concolic_mention@example.org'))`,
2 853 dumps. The real comparison is `people.diaspora_handle == <handle parsed out of
comments.text>` (`lib/diaspora/mentionable.rb:35`). Both arms of the equality are
explored so the branch is visible, and `diaspora_handle` is a gated column, but the
right-hand side is a pin of a text-derived value where DISCIPLINE §10 Rule V asks
for a `SYM_PARAM_*`. Carried forward from R1-N5/R2-D3 in reduced form.

**NM-6 — `format: :html` and `format: :xml`/`:js` remain terminal, and the html arm
now stops even earlier than R5 measured.** E03: html anon and html signed-in both
raise `ActionView::MissingTemplate: Missing template comments/index, application/index …
:formats=>[:html]`; xml and js raise `ActionController::UnknownFormat`. On the html
arm the `comments` SELECT is never issued (`find_for_post` returns an unmaterialised
Relation), so the entire access is the post finder — a one-statement signed-in shape
that is the same multiset as M-5's `{users}`-only shape and is worth a ledger line
if it is ever pinned away.

---

## 6. Branches I could not reach, and why

| branch | why |
|---|---|
| `Person#fix_profile` → `Discovery.new` → `fetch_and_save` → `reload` (B-1, and every `…_profile_not_found == True` arm) | unchanged and deliberately not attacked: `Faraday.default_adapter == :typhoeus` → Ethon → libcurl through JFFI aborts the JVM on the first outbound request, reachable host or not (R4-N4-1). Every person any round-6 render calls `.name` on has a `profiles` row; **0 JVM aborts this round**. The corpus's 5 383 `reload` events and their post-reload `profiles` reads are corpus- and code-verified only |
| a `comments` row whose `author_id` has no `people` row | not a database state: `db/schema.rb:624 add_foreign_key "comments", "people", column: "author_id", on_delete: :cascade`, and E06 probe 08 measured `PRAGMA foreign_keys = 1` on this rig — FKs are enforced, so the rig cannot manufacture it either |
| two `mentions` rows for the same person on one comment | forbidden by the UNIQUE index — E06 probe 01 got `RecordNotUnique`. This is the *evidence* for WIN 6-2, not a gap |
| `Reshare#root` / `absolute_root` / `o_embed_cache` / `open_graph_cache` / `photos` / `poll` / `location` | unreachable by code on `#index`: the post is found and then only `post.comments` is read; it is never rendered. E03 `720` (missing root), `722` (live root), `724` (private root) are statement-identical to a `StatusMessage`, and E06 probe 10 shows `Post.find(751).root` is `nil` with no query issued at instantiation |
| `blocks`, `contacts`, `aspects`, `aspect_memberships`, `likes`, `participations`, `notifications`, `taggings`/`tags`, `pods`, `roles`, `conversations` | unreachable by code. E03 `729` seeded real `blocks`, `contacts`, `aspects` and `aspect_memberships` rows for the principal and rendered a share-visible post whose comments are by a blocked author and by a contact, signed-in, json and mobile: **not one statement against any of those tables**. `#index` filters comments by nothing but `commentable_id`/`commentable_type` |
| `gon_set_current_user` → `UserPresenter#to_json` | unreachable by code: both renderable formats bypass the layout (`render json:` and `render layout: false`), so `gon.push` stores the presenter and nothing serialises it |
| `Mentionable.filter_people` → `people_from_string` → `Person.find_or_fetch_by_identifier` | needs `disable_hovercards` or `link_all_mentions`; no caller on this endpoint passes either. `people_from_string` traced in all 6 manifests, **0** calls in 97 requests |
| `mentioned_people`'s `persisted? == false` arm | every comment comes out of `Relation#records`/`#to_a` |
| `camo_urls` / the `Profile#image_url` camo branch | configuration (`AppConfig.privacy.camo.*`), outside the adversary's remit; neither reaches SQL |
| `Post.descendants` beyond `{Reshare, StatusMessage}` | E06 probe 06 returns `[]` at probe time (lazy STI loading) and `Photo.superclass == ApplicationRecord`; the in-tree set is as R5 enumerated |
| array / hash `post_id` | `post_id` is a path segment; Rails merges path params last (R2 D1 router probe). Not re-probed |

---

## 7. What a check for these wins would have to look like

None of the three is visible to a shape-level judge. The missing instrument is the
one round 5 asked for (N5-4): a **state-level** audit that reads each dump's own
decisions alongside its notes and rejects combinations the schema forbids. The three
rules it would need are cheap and dump-side:

1. *(WIN 6-1)* for a nested preload step keyed on the parent's PRIMARY KEY, the
   bind count must equal the number of parents the step above loaded — so
   `outer IN(n) → nested =` is red unless exactly one parent loaded;
2. *(WIN 6-2)* for a preload step whose bound column is covered by a UNIQUE index
   together with the owner-relation's fixed columns, the key count must equal the
   row count — so `len(rel) > 1 ∧ keys_many == False` is red;
3. *(WIN 6-3)* two variables that the schema forces to be equal (a belongs_to FK
   and the target row's primary key) must be ONE variable, at every key position —
   not only at position 1.

