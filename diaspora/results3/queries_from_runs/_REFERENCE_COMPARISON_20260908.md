# Reference comparison — conversations_index, comments_index, people_show (2026-09-08/09)

Blockaid coverage mode (`src/queries_from_runs/subsume/check_subsumed.sh`; z3 4.8.12; diaspora
schema + PK/FK/deps from the harness resources), BOTH directions per endpoint:

- **WAY 1 (soundness)** — views = REFERENCE policy, queries = OURS. `true`: the statement we
  extracted is answerable from the reference; `false`: z3 built a counterexample (we read something
  the reference does not permit); `null`: error or timeout.
- **WAY 2 (completeness)** — views = OURS, queries = REFERENCE. `true`: the reference statement is
  answerable from our policy; `false`: proven not answerable; `null`: error or timeout.

Timeouts are `null`, separated from errors below, and are never counted as not-covered. Every run:
`SUBSUME_TIMEOUT_MS=60000`, 3 solver threads, its own `systemd-run --user -p MemoryMax=6300M`
unit, `JAVA_TOOL_OPTIONS` unset. All artefacts (12 result JSONs, usability probes, the Tier C
rewrite + per-view audit trail, driver/summariser) are in
`queries_from_runs/_reference_comparison_20260908/`.

References: `ruby_examples/dse-apps/policies/extracted/diaspora/per-endpoint/{conversations-index,
comments-index,people-show}.sql` — 16 / 23 / 30 views, **100 % usable** by blockaid (all parse,
type and are plain PSJ). The handwritten whole-app `policies.sql` was not used as a target.

Two tiers were run and are labelled on every row:

- **raw** — the extracted policy file exactly as on disk (`queries_from_runs/<endpoint>.sql`).
- **Tier C** — a SCRATCH, join-substituted, blockaid-convention rewrite of the same file
  (`_reference_comparison_20260908/scratch_tierC/tierC_<endpoint>.sql`, rules in §2, per-view
  audit trail in `map_<endpoint>.json`). **A Tier C result is a statement about the rewritten
  policy, not the extracted one.** The canonical `.sql` files were never modified.

## 0. Provenance — the three extracted files are current (verified during this task)

| endpoint | provenance header | `dump_*.json` on disk | coverage_summary.json | .sql mtime vs newest dump | verdict |
|---|---|---|---|---|---|
| conversations_index | 18,623 dumps / 18,623 runs / 58 views | 18,623 | total_runs 18,623, `complete: true` | 09-01 03:35 > 08-31 21:59 | **current** |
| comments_index | 26,528 dumps / 26,528 runs / 79 views | 26,528 | total_runs 25,408 + 1,120 duplicate outcome maps = 26,528 `corpus_dumps`, `complete: true` | 09-01 11:07 > 09-01 09:43 | **current** |
| people_show | 12,997 dumps / 12,997 runs / 58 views | 12,997 | total_runs 12,997, `coverage_complete: true`, no `complete` key (milestone) | 09-07 07:45 > 09-05 01:43 | **current** |

No staleness signal exists, so no canonical re-extraction was warranted or performed. (A
normalised-extraction run was started on the user's mid-task request and stopped by the
coordinator before writing anything; the three canonical `.sql` files are byte-identical to the
`*.sql.canonical_pre20260908` backups — see §6.)

## 1. Eval table — every run, with its denominator

| endpoint | tier | direction | policy (views) | usable | quarantined (cause) | checked (stmts) | accepted (true) | rejected (false) | undecided (null: cause) | accepted / decided |
|---|---|---|---|---|---|---|---|---|---|---|
| conversations_index | raw | WAY 1 (soundness) | reference (16) | 16 | 0 | ours (58) | 8 | 2 | 48 (44 placeholder const; 3 relation alias; 1 timeout) | 8/10 |
| conversations_index | raw | WAY 2 (completeness) | ours (58) | **8** | 50 (40 placeholder const; 6 aggregate select; 3 relation alias; 1 LEFT join) | reference (16) | 5 | 5 | 6 (6 timeout) | 5/10 — **not a policy measurement, see §4** |
| conversations_index | Tier C | WAY 1 (soundness) | reference (16) | 16 | 0 | ours-rewritten (58) | 39 | 2 | 17 (17 timeout) | 39/41 |
| conversations_index | Tier C | WAY 2 (completeness) | ours-rewritten (58) | 58 | 0 | reference (16) | 12 | 1 | 3 (3 timeout) | 12/13 |
| comments_index | raw | WAY 1 (soundness) | reference (23) | 23 | 0 | ours (79) | 18 | 2 | 59 (53 placeholder const; 6 timeout) | 18/20 |
| comments_index | raw | WAY 2 (completeness) | ours (79) | **26** | 53 (53 placeholder const) | reference (23) | 2 | 0 | 21 (21 timeout) | 2/2 — **decides nothing** (21 of 23 undecided) |
| comments_index | Tier C | WAY 1 (soundness) | reference (23) | 23 | 0 | ours-rewritten (79) | 39 | 0 | 40 (27 timeout; 13 placeholder residue) | 39/39 |
| comments_index | Tier C | WAY 2 (completeness) | ours-rewritten (79) | 79 (probe) | 0 | reference (23) | — | — | **run OOM-killed** (rc=1, 4.2 GB peak while a re-extraction competed for memory; same 79-view full-set wall as 09-01) | no result |
| people_show | raw | WAY 1 (soundness) | reference (30) | 30 | 0 | ours (58) | 2 | 9 | 47 (13 placeholder const; 11 `'t'` vs bool; 5 identifier-as-literal; 4 relation alias; 2 LEFT join; 12 timeout) | 2/11 |
| people_show | raw | WAY 2 (completeness) | ours (58) | **14** | 44 (19 aggregate select; 11 placeholder const; 5 identifier-as-literal; 4 relation alias; 3 `'t'` vs bool; 2 LEFT join) | reference (30) | 6 | 7 | 17 (17 timeout) | 6/13 — **not a policy measurement** |
| people_show | Tier C | WAY 1 (soundness) | reference (30) | 30 | 0 | ours-rewritten (77) | 17 | 21 | 39 (37 timeout; 2 placeholder residue) | 17/38 |
| people_show | Tier C | WAY 2 (completeness) | ours-rewritten (77) | 75 | 2 (placeholder residue) | reference (30) | 14 | 2 | 14 (14 timeout) | 14/16 |

Reading rule: a raw WAY 2 row whose "usable" column is 8/58, 26/79 or 14/58 measures blockaid's
parser, not the policy. Timeouts are dominated by wide-row `profiles.*` / `people.*` queries over
5-6 relations (z3 MBQI needs a counterexample model; the 09-01 notes describe the same wall).

## 2. Why the raw files are mostly unusable, and what Tier C did

Usability probe (views = the file, queries = []):

| file | views | usable | quarantined by cause |
|---|---|---|---|
| ours conversations_index.sql | 58 | 8 | 40 `_SYM_RESULT_*` placeholder const; 6 aggregate select list; 3 relation alias (COUNT + INNER JOIN + alias, views 9-11); 1 LEFT join (view 40) |
| ours comments_index.sql | 79 | 26 | 53 `_SYM_RESULT_*` placeholder const |
| ours people_show.sql | 58 | 14 | 19 aggregate; 11 placeholder (`_assoc_*`, `_SYM_POSTS_GUID`, `_SYM_RESULT_..find_by_*`); 10 shape (identifier-as-literal `` = `Post` ``, relation alias, LEFT join); 4 solver-type (`'t'` on a boolean column, `roles.admin` column not found) |

### 2.1 Placeholder families and what they bind to (from the dumps' `symbolic_vars[].note`)

| placeholder | views | producer (dump note) | meaning | Tier C rule |
|---|---|---|---|---|
| `_SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id` | conv 40, cmt 16 | the principal fetch `users WHERE id = _MY_UID`; `.person_id` is the principal's Person (`users` has no such column, so `_bind_value` falls through) | **the principal's person id** | C1/M1: `people AS me`, `me.owner_id = _MY_UID`, placeholder -> `me.id` — the reference's own encoding |
| `_assoc_person_id` (people_show) | 12 | `SELECT people.* FROM people WHERE owner_id = $$(SYM_USER_PE_id) LIMIT 1` | the principal's person via `user.person` | P2: same as above |
| `_SYM_RESULT_ActiveRecord__Calculations_pluck_2_pluck_author_id` (conv) | 3 | views 33/34 (`messages.author_id` of my conversations) | author of a message in one of my conversations | C2: producer inlined (`messages AS m_p, conversation_visibilities AS cv_p`, `cv_p.person_id = me.id`) |
| `_SYM_RESULT_ActiveRecord__Relation_to_a_{1,2}_row_conversation_author_id` (conv) | 4 | view 41 (conversations of my cv rows) | author of one of my conversations | C3: producer inlined |
| `_SYM_RESULT_ActiveRecord__Relation_{records,to_a}_N_row2_{person_id,author_id}` inside `IN (join-col, ph)` (cmt) | 36 | row 2 of the same `mentions`/`comments` relation the join already ranges over | same set as the join column | M2: `IN (col, ph)` -> `= col` |
| `…_row2_id` as `mentions.mentions_container_id` (cmt 59-62, 65-68, 70, 71) and `profiles.person_id = …row2_person_id` (76-78) | 13 | comment / mention rows of the post whose own visibility arm the fold did not carry into these terminal views | mentions / people / profiles of the post's comments | **left as residue** (still quarantined); their content is exactly views 13/14/41/42, 1-12/29-40, 7-12/35-40, which are fully joined and ARE checked |
| `_assoc_profile_id` (people_show 37, 38) | 2 | `profiles WHERE person_id = <shown person>` | shown person's profile | P3: `profiles AS shown_pr, people AS shown`, `shown.closed_account = FALSE` |
| `_assoc_author_id` (people_show 56) | 1 | `people WHERE id = <stream post>.author_id`; stream posts are `posts.author_id = <shown person>` | the shown person again | residue (= view 35) |
| `_SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_{1,2}_id` (people_show 53, 54) | 2 | "User query (class-level finder; WHERE unavailable — interceptor drops kwargs …)" = `User.find_by(username:)` | the `/u/:username` user | P6: `users AS u_by`, `people.owner_id = u_by.id`, username param broadened |
| `_SYM_POSTS_GUID` (people_show 39) | 1 | "bio/location diasporalink guid" — parsed out of `profiles.bio` text | no SQL form | residue |

### 2.2 The other Tier C rules

- Aggregates, blockaid's own convention (`StripCountStar` / the paper's SUM rule): `SELECT COUNT(*)
  FROM R1..Rn` -> `SELECT R1.id, …, Rn.id` (the pk projection reveals multiplicity and nothing
  else; generalised to every FROM table because a join's multiplicity needs every pk);
  `SELECT SUM(R.A)` -> `SELECT R.id, R.A`; `SELECT 1 AS one` kept; `DISTINCT` dropped.
- people_show only: P1 literal principal id `1` on `share_visibilities.user_id`, `contacts.user_id`,
  `blocks.user_id`, `notifications.recipient_id` -> `_MY_UID` (POLICY_HEADER F6 instructs exactly this
  reading); P7 parentheses restored — the raw dump SQL is `("share_visibilities"."user_id" = 1 OR
  "posts"."public" = 't')` but the extracted views carry `… AND sv.user_id = 1 OR posts.public = 't'
  AND …` (precedence changed, defect E5 in §6) — and each such view is split into its sv-arm and its
  public-arm (the public arm drops `share_visibilities`, which represents the app's LEFT OUTER JOIN
  exactly under set semantics); P8 `` = `Post` `` / `` = `admin` `` -> `'Post'` / `'admin'` (the
  app's own SQL has `"admin"` double-quoted; MySQL reads a string, the postgres-dialect fold an
  identifier); `'t'` -> `TRUE`.
- conversations only: C4 view 40's `LEFT OUTER JOIN conversations` -> INNER (FK-backed).

Tier C usability: conversations 58/58, comments 66/79 (13 residue), people_show 75/77 (77 views
from 58 because of the P7 arm split; 2 residue).

## 3. Every genuine mismatch, with SQL and classification

Legend: **REF-OMIT** = a read the app really issues (witnessed in the corpus) that the reference
lacks; **CONV** = an artefact of a rendering/encoding convention on one side; **F6** = artefact of
people_show's documented concrete-principal defect; **HARNESS** = blockaid limitation;
**SEMANTIC** = a real difference in what the two policies say.

### 3.1 conversations_index

| dir / tier | q | SQL | classification |
|---|---|---|---|
| WAY 1 raw + Tier C | 46 | `SELECT 1 AS one FROM `posts`` | **REF-OMIT** — the layout's `Post.exists?` nav-bar read; in the corpus, absent from the reference |
| WAY 1 raw (as 35 with `users` join) + Tier C | 35 | ``SELECT `tags`.* FROM `tags` INNER JOIN `tag_followings` ON `tags`.`id` = `tag_followings`.`tag_id`, `users` WHERE `tag_followings`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID`` | **REF-OMIT** — `current_user.followed_tags` (nav bar); the reference has no `tag_followings` view |
| WAY 1 raw | 49 | ``SELECT COUNT(*) FROM `reports` WHERE `reports`.`reviewed` = FALSE`` | **REF-OMIT** — admin/moderator badge count; proven FALSE raw, timed out in Tier C |
| WAY 2 Tier C | 15 | ``SELECT * FROM `notifications` WHERE `recipient_id` = _MY_UID AND `unread` = TRUE`` | **CONV** — the app issues `COUNT(*)` (our view 38); the reference's `.raw.sql` contains zero COUNTs, i.e. the reference renders the same count as a row-level `SELECT *`; our Tier C pk-projection cannot determine `*`. Statement present, rendering differs |
| WAY 2 raw | 7, 8, 9, 10, 15 | the 09-01 "five proven missing" | **HARNESS** — see §4; all five are present in the file and four are proven TRUE under Tier C |

WAY 1 Tier C: 39 true / 2 false / 17 timeout — no over-permission beyond the two nav-bar reads.
WAY 2 Tier C: 12 true / 1 false / 3 timeout (q1, q2 the double-cv participant joins; q12
`contacts … receiving = TRUE`, whose partner in our file is a COUNT).

### 3.2 comments_index

| dir / tier | q | SQL | classification |
|---|---|---|---|
| WAY 1 raw | 69 | `SELECT 1 AS one FROM `posts`` | **REF-OMIT** (the dlink `Post.exists?(guid:)` probe, request-param broadened) |
| WAY 1 raw | 72 | ``SELECT `posts`.* FROM `posts``` | **REF-OMIT / SEMANTIC** — the anonymous arm's `PostService#find!` really reads `SELECT "posts".* FROM "posts" WHERE "posts"."id" = <param>` BEFORE the public check (witnessed in every `anon_json`/`anon_mobile` dump); the reference only carries `posts WHERE public = TRUE`, i.e. it folds the *subsequent* PC into the lookup. Ours is the statement the app issues (the non-public post's existence is revealed by the 404 vs 200 either way); the reference is the reveal-level view. Same read-vs-reveal divergence as §5 |
| WAY 1 Tier C | — | 39 true / 0 false / 40 null | no over-permission decided against; 27 timeouts are all `profiles.*` wide-row queries, 13 are residue |
| WAY 2 raw | — | 2 true / 0 false / 21 timeout at 26/79 usable | **decides nothing** |
| WAY 2 Tier C | — | OOM-killed | **no result** |

Note on the `users.language` arms: our views split by `users.language <> 'pl' AND <> 'xx'` /
`= 'pl'` with no `= 'xx'` arm. That is the app's real behaviour (`I18n.locale=` raises before the
action body for a non-available locale; adversary C04) — but z3 does not know `'xx'` cannot exist
under `validates_inclusion_of :language`, so a completeness check of the reference's unconditional
views would report FALSE with a `language = 'xx'` counterexample. Any such FALSE (none was reached,
the run was killed) is a **CONV** artefact, not a gap.

### 3.3 people_show (milestone, not closed; read every mismatch through POLICY_HEADER F6 and the dropped Contains/IndexOf PCs)

WAY 1 raw (9 FALSE):

| q | SQL | classification |
|---|---|---|
| 22 | ``SELECT `people`.* FROM `people`, `contacts`, `people` AS `people0` WHERE `people`.`id` = `contacts`.`person_id` AND `contacts`.`user_id` = 1 AND `contacts`.`person_id` = `people0`.`id` AND `people0`.`closed_account` = FALSE`` | **F6** — literal principal; TRUE under Tier C (q41) |
| 32 | ``SELECT `contacts`.* FROM `contacts`, `people` WHERE `contacts`.`user_id` = 1 AND `contacts`.`person_id` = `people`.`id` AND `people`.`closed_account` = FALSE`` | **F6**; TRUE under Tier C (q51) |
| 33 | ``SELECT `notifications`.* FROM `notifications`, `people` WHERE `notifications`.`recipient_id` = 1 AND `notifications`.`target_type` = 'Person' AND `notifications`.`target_id` = `people`.`id` AND `notifications`.`unread` = TRUE AND `people`.`closed_account` = FALSE`` | **F6**; TRUE under Tier C (q52) |
| 30 | ``SELECT SUM(`conversation_visibilities`.`unread`) FROM `conversation_visibilities`, `people` WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID`` | **CONV** — the reference joins every people-show view to the SHOWN `people` row (`… AND people.closed_account = FALSE`, projecting `people.guid`); z3's counterexample is a DB with no such person, under which the header read is undetermined. Still FALSE under Tier C (q49) for the same reason |
| 42 | ``SELECT COUNT(*) FROM `contacts` WHERE `contacts`.`user_id` = _MY_UID AND `contacts`.`receiving` = TRUE`` | **CONV** (same); timeout under Tier C |
| 43 | ``SELECT COUNT(*) FROM `notifications` WHERE `notifications`.`recipient_id` = _MY_UID AND `notifications`.`unread` = TRUE`` | **CONV** (same); FALSE under Tier C (q62) |
| 27 | ``SELECT COUNT(*) FROM `photos`, `people` WHERE `photos`.`author_id` = `people`.`id` AND `photos`.`public` = TRUE AND `photos`.`pending` = FALSE AND `people`.`closed_account` = FALSE`` | **REF-OMIT** — the app's anonymous-arm SQL is exactly `COUNT(*) FROM "photos" WHERE "author_id" = ? AND "public" = true AND "pending" = false` (no `created_at`, witnessed in `dump_anon_handle_0001`); every reference photo view carries `created_at < _NOW`. Also FALSE under Tier C (q46) |
| 36 | ``SELECT `tags`.* FROM `tags` INNER JOIN `tag_followings` ON `tags`.`id` = `tag_followings`.`tag_id` WHERE `tag_followings`.`user_id` = _MY_UID`` | **REF-OMIT** (nav bar, as conversations) |
| 35 | ``SELECT `profiles`.* FROM `profiles`, `people` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`closed_account` = FALSE`` | **SEMANTIC** — see §5 |

WAY 1 Tier C (21 FALSE): 17 true / 21 false / 39 null. Eighteen of the 21 are ONE family — the
mobile/json STREAM reads (`posts.*` of the shown person incl. reshares, `SELECT 1 AS one FROM likes`
exists-probes, comment/like COUNTs as pk projections, `people.*` of stream-post authors), e.g.

```
SELECT 1 AS one FROM `likes`, `posts`, `share_visibilities`, `people`, `people` AS `me`
 WHERE `likes`.`author_id` = `me`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`target_id` = `posts`.`id`
   AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post'
   AND `posts`.`author_id` = `people`.`id` AND `share_visibilities`.`user_id` = _MY_UID
   AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare')
   AND `people`.`closed_account` = FALSE AND `posts`.`provider_display_name` <> 'mobile'
   AND `posts`.`public` = FALSE AND `me`.`owner_id` = _MY_UID
SELECT `comments`.`id`, `posts`.`id`, `share_visibilities`.`id`, `people`.`id` FROM `comments`, `posts`, `share_visibilities`, `people`
 WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id`
   AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `share_visibilities`.`user_id` = _MY_UID
   AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE
   AND `posts`.`provider_display_name` <> 'mobile' AND `posts`.`public` = FALSE
SELECT `people`.* FROM `people`, `posts`, `people` AS `people0` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`author_id` = `people0`.`id`
   AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`closed_account` = FALSE
```
(Tier C q2, 4, 5, 7, 9, 11, 13, 16, 17, 19, 21, 23, 24, 25, 28, 34, 35, 44.) The reference
people-show policy contains **no `posts`, `likes` or `comments` view at all** — it was evidently
extracted from the html arm only, while our corpus carries 6,370 `auth_mobile` + 2,976
`anon_mobile` + 47 json dumps whose stream reads these are (declared in POLICY_HEADER P-8 as the
partially-walled mobile arm). Classification: **REF-OMIT** for the whole family. The remaining
three are q46 (photo COUNT, REF-OMIT as above), q49 and q62 (header reads, CONV as above).

WAY 2 raw (7 FALSE, 14/58 views): q3/4/5/8 (tags of the shown profile — our views 37/38 were
quarantined on `_assoc_profile_id`; TRUE-or-timeout under Tier C once resolved), q13 (roles admin —
quarantined on `_assoc_person_id`; **TRUE under Tier C**), q17 (pods), q27 (notifications). All but
pods/notifications are **HARNESS** artefacts of the discarded views.

WAY 2 Tier C (2 FALSE, 75/77 views):

| q | SQL | classification |
|---|---|---|
| 17 | ``SELECT `pods`.`id` AS `id0`, `pods`.`host`, … , `people`.`guid` FROM `people`, `pods` WHERE `pods`.`id` = `people`.`pod_id` AND `people`.`owner_id` IS NULL AND `people`.`closed_account` = FALSE`` | **reference-side** — `FROM "pods"` appears in 0 of 12,997 dumps; in this checkout `Person#remote?` is `owner_id.nil?` and no controller/view/presenter/helper on the people#show path touches `.pod` (grep over `app/`, `lib/`: only the federation dispatcher and the admin dashboard). Coverage is complete and adversary R2 was zero-win, so the read is not reachable here. If a later app revision reads `person.pod` on the profile page, this becomes a real gap |
| 27 | ``SELECT `notifications`.`id` AS `id0`, … , `people`.`guid` FROM `people`, `notifications` WHERE `notifications`.`recipient_id` = _MY_UID AND `notifications`.`unread` = TRUE AND `people`.`closed_account` = FALSE`` | **CONV** — the app's statement is `COUNT(*)` (our view 43), the reference renders it row-level; our pk projection cannot determine the row |

Note also that the 26,062 dropped Contains/IndexOf PCs (POLICY_HEADER, fold fidelity) make our
handle-parsing views BROADER than the app; that can only produce WAY 1 FALSEs, and none of the
decided WAY 1 FALSEs is on a handle-parsing arm — every one is accounted for above.

## 4. The 2026-09-01 "5 proven missing" finding for conversations_index is OVERTURNED

`results3/blockaid_new_vs_old/RESULTS.md` (2026-09-01) recorded, for conversations_index WAY 2 at
60 s: "NOT covered — proven missing from the new extraction (5): conversation_visibilities SELECT,
roles admin, roles admin/moderator, profiles SELECT, notifications unread".

**Mechanism.** That run — reproduced here bit-for-bit (raw WAY 2: 5 true / 5 false / 6 timeout) —
kept only **8 of 58 views**. The 50 discarded ones are the 40 views carrying
`_SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id` (the principal's person id,
rejected by the solver-type probe as an unrecognised constant), the 6 aggregates, 3 alias shapes
and 1 LEFT join. Every one of the five "missing" statements keys on the principal's person or is an
aggregate — i.e. they live exactly in the discarded views. The FALSE verdicts were about a policy
with those views removed.

**Ground truth from the SQL text** (no solver needed; `grep` on `conversations_index.sql`):

| 09-01 "proven missing" | present in the extracted file | why blockaid discarded it |
|---|---|---|
| conversation_visibilities of my conversations | view 29 ``SELECT `conversation_visibilities`.* … WHERE … `conversation_visibilities`.`person_id` = <principal>``, view 40 (eager-load `t0_r0…` form), view 41 ``SELECT `conversations`.* FROM `conversations` INNER JOIN `conversation_visibilities` … WHERE `conversation_visibilities`.`person_id` = <principal>`` | principal placeholder (29, 41); LEFT join (40) |
| roles admin | view 48 ``SELECT 1 AS one FROM `roles` WHERE `roles`.`person_id` = <principal> AND `roles`.`name` = 'admin'`` | principal placeholder |
| roles admin/moderator | view 47 ``SELECT 1 AS one FROM `roles` WHERE `roles`.`name` IN ('moderator', 'admin') AND `roles`.`person_id` = <principal>`` | principal placeholder |
| my profile | view 55 ``SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = <principal>`` | principal placeholder |
| unread notifications | view 38 ``SELECT COUNT(*) FROM `notifications`, `users` WHERE `notifications`.`recipient_id` = `users`.`id` AND `notifications`.`unread` = TRUE AND `users`.`id` = _MY_UID`` — the statement the app issues; the reference's `SELECT *` is its own row-level rendering (its `.raw.sql` has zero COUNTs) | aggregate in select list |

**Solver confirmation.** With the principal placeholder substituted by the reference's own encoding
(Tier C, 58/58 views usable), WAY 2 gives 12 true / 1 false / 3 timeout: the cv read (q7), both
roles checks (q8, q9) and my profile (q10) are **proven covered**; the notifications row is the
COUNT-vs-`SELECT *` rendering difference (§3.1). The 09-01 conclusion that our policy is missing
those statements was an artefact of the harness's constant handling, not a gap in the policy.
`RESULTS.md` / `RESULTS_REWRITTEN.md` should be annotated accordingly (not done here — outside
this task's write scope).

## 5. What q35 reveals about the METHOD: statement-level vs reveal-level policies

```
ours     : SELECT `profiles`.* FROM `profiles`, `people` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`closed_account` = FALSE
reference: SELECT `profiles`.`id`, `diaspora_handle`, `first_name`, `last_name`, `image_url`, `image_url_small`,
                  `image_url_medium`, `searchable`, `person_id`, `created_at`, `updated_at`, `full_name`, `nsfw`,
                  `public_details`, `people`.`guid` FROM `people`, `profiles` WHERE … `people`.`closed_account` = FALSE
           (the full row incl. birthday / gender / bio / location ONLY when people.owner_id = _MY_UID,
            or profiles.public_details = TRUE, or via a contacts.sharing = TRUE join)
```

The app issues `SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ? LIMIT 1` for
every shown person (witnessed in every dump) and then hides `birthday/gender/bio/location` in Ruby
(`PersonPresenter` / `Profile#public_details?`). Our extraction records **the statement the app
issues**; the reference records **the data that may reach the user**. Where an app over-fetches and
filters in application code, the two policies legitimately diverge and ours is the coarser one —
by construction, not by extraction error. The same divergence appears in comments_index q72
(`SELECT posts.* FROM posts`: the app fetches any post by id, then raises `NonPublic`).

Consequence, stated plainly: **a consumer that treats an extracted statement-level policy as an
access-control policy is over-permissive exactly at every over-fetch-then-filter site**, and this
applies to every endpoint, not only people_show — any `SELECT t.*` whose columns are pruned later in
Ruby has the same property. Closing that gap is not an extraction fix; it needs a second,
column-level artefact (which fields of a fetched row are rendered on which arm), or the checks in
Phases 3-5 must be re-scoped to say explicitly that they certify statements, not reveals.

## 6. Extraction defects found on the way (not fixed in the canonical files)

All measured on the shipped files; none changes the SET of statements, several change what a
statement says. A results3-local, opt-in normaliser (`queries_from_runs/_blockaid_fold.py`,
installed by the three drivers only when `BLOCKAID_NORMALISE=1`, writing to
`_rewritten/<endpoint>.blockaid.sql`, never to the canonical file) implements the repairs below and
produced zero non-blockaid residue and zero fold errors on 80-dump samples of each corpus; the full
run was started on the user's request and stopped by the coordinator before completion, so **no
normalised file exists on disk** and the Tier C scratch rewrite remains the only normalised input
used here. src/ was not touched.

| id | defect | evidence | effect |
|---|---|---|---|
| E1 | `_extract_people_show_streaming.py` calls `assoc_fold.install()` but instantiates the BASE `RunTransformer`, so `assoc_bind_map` is never built | in-process control run on `dump_auth_mobile_0007`: base class keeps `_assoc_person_id`, `AssocFoldingTransformer` resolves it to `people.owner_id = _MY_UID` | all 17 `_assoc_*` placeholder views in people_show.sql |
| E2 | `transform._Build._bind_value` cannot resolve `SYM_RESULT_<users producer>_person_id` (no such column on `users`) | 40 conv + 16 cmt views | the principal placeholder family |
| E3 | `pcs._suffix_candidates` strips `row_`/`item_` but not `row2_` | 36 `IN (col, …row2_…)` + 13 terminal views in comments | placeholder residue |
| E4 | `User.find_by(username:)` note is not a SELECT ("WHERE unavailable — interceptor drops kwargs") -> no producer | people_show views 53/54 | placeholder |
| E5 | `_Build.assemble_where` chains raw `exp.And`; an `exp.Or` conjunct renders without parentheses | 19 people_show views: `… AND sv.user_id = 1 OR posts.public = 't' AND …` vs raw dump `(… = 1 OR … = 't')` | **precedence changed — those 19 views state a different predicate than the app's** |
| E6 | app SQL string literals `"admin"`, `"Post"` parsed as identifiers by the postgres-dialect fold | people_show views 3-6, 40 (`` = `Post` ``, `` = `admin` ``) | unparseable for any consumer |
| E7 | `'t'` on boolean columns kept verbatim | 19 people_show views | solver-type rejection |
| E8 | COUNT/SUM/DISTINCT/LEFT JOIN emitted as-is | 6 conv + 19 people_show aggregates, 1+2 LEFT joins | not usable as views |
| E11 | will_paginate's `SELECT COUNT(*) FROM (SELECT DISTINCT cv.id … ) subquery_for_count` note is unparseable for the fold | `_summary_conversations_index.json`: 21,037 "unparseable note" errors on `..._Calculations_count_*` | **that statement is silently absent from conversations_index.sql** (summary-only); it is the pagination count over the user's own conversation_visibilities (semantically inside view 29/41) |
| F6 | concrete principal (documented) | 28 people_show views with `user_id = 1` / `recipient_id = 1` | literal where `_MY_UID` belongs |

Per RUNBOOK: residue found by a reference comparison means Phases 3-5 have a gap and the CHECK must
be fixed too. E5 and E11 are the ones with policy content: `hardening_lint` / `note_fidelity_audit`
did not catch a precedence change or a dropped pagination statement, so both need a check
(re-parse every emitted view and compare its conjunct set against the raw note; count unparseable
notes as red, not as a summary field).

## 7. Verdicts

**conversations_index (CLOSED, 58 views).** The reference comparison **supports** the completeness
claim. Under Tier C, 12 of 13 decided reference statements are answerable from our policy and the
13th is a rendering convention; the four statements 09-01 called missing are proven present (§4).
Soundness: 39 of 41 decided statements are permitted by the reference; the two exceptions are
nav-bar reads the reference omits. Residue traceable to the policy: **none**. Residue traceable to
extraction: E11 (a dropped pagination COUNT) — a real, previously unrecorded omission, though its
rows are already covered by views 29/41.

**comments_index (CLOSED, 79 views).** The comparison **cannot decide completeness**: raw WAY 2 is
2 true / 0 false / 21 timeouts at 26/79 usable views, and the Tier C WAY 2 run was OOM-killed — no
completeness verdict exists in either direction of evidence, and this deliverable does not
manufacture one. Soundness is supported: 39 true / 0 false under Tier C (27 timeouts, all wide-row
`profiles.*`), 18 true / 2 false raw where the 2 are reference omissions (q69) and the
statement-vs-reveal divergence on the anonymous post lookup (q72, §5). Nothing found contradicts the
closure; nothing solver-based confirms its completeness against the reference.

**people_show (MILESTONE, 58 views).** The comparison neither contradicts nor confirms the
milestone, and every decided mismatch is explained: WAY 2 Tier C 14 true / 2 false, both FALSE
reference-side or convention (pods: unreachable in this checkout, 0/12,997 dumps; notifications:
COUNT-vs-row rendering). WAY 1 raw's 9 FALSE decompose into 3 × F6 (all TRUE once the literal is
read as `_MY_UID`), 3 × reference parametrisation convention, 2 × reference omission, 1 × the
statement-vs-reveal divergence (§5). WAY 1 Tier C's 21 FALSE are the mobile/json stream family the
reference does not model at all, plus 3 already classified. The endpoint's own documented defects
(F6 literal principal; 26,062 dropped handle PCs) and the extraction defects E1/E5/E6/E7 are what
keep the raw file at 14/58 usable; the normaliser resolves all of them on samples.

**Cross-cutting.** (1) The 09-01 "5 proven missing" finding is an artefact and should be annotated
as overturned. (2) The extracted `.sql` files are not blockaid-consumable as shipped (8/58, 26/79,
14/58 usable); a comparison on them measures the parser. (3) Statement-level vs reveal-level is a
property of the method (§5), present on every endpoint, and must be stated wherever an extracted
policy is offered as an access-control artefact.
