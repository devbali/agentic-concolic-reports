# Why `bench.grade` disclosure precision is < 1.0 — root-cause trace, 2026-09-19

**Input graded:** `reports/diaspora/results3/_bench_20260919/ours_pcfold3_fix.jsonl`
(the `_pcfold3_fix.sql` arm of each endpoint).
**Reference:** `policy-extraction-bench/data/answers/diaspora/<endpoint>.sql`.
**Metric:** `bench/grade.py` → `analyse()` → `sqlnorm.expand_star()`; the compared
object is the set of `(table, column)` pairs, with `t.*` expanded against
`data/schemas/diaspora-schema.rb`. `bench/metrics/diff.py` is the *other* (Blockaid)
metric and plays no part in `disclosure_precision`.

**Headline:** there are **29 extra `(table, column)` pairs** across the four
endpoints. **Zero of them are bucket (a).** Every one traces to a real recorded
query in a real dump. They split three ways:

| bucket | pairs | cause |
|---|---:|---|
| (a) genuine over-disclosure / extraction bug | **0** | — |
| (b) reference is incomplete | **12** | the reference never drove diaspora's **mobile layout**; `reports`, `tag_followings`, `tags`-via-`tag_followings` appear in no diaspora answer key at all |
| (c) representation / normalization mismatch | **5** | `SELECT 1 AS one` parsed as a column named `1`; our `aggregate-as-rows` PK convention |
| (d) app/environment version mismatch | **12** | the app fork's `lazy_load :bio, :gender, :birthday, :location` is **inactive** under `RAILS_ENV=concolic`, active under `production_mod` — the env the reference was extracted in |

Removing all three buckets yields **disclosure_precision = 1.0000 on all four
endpoints**, which is the arithmetic confirmation that the classification is
exhaustive.

| endpoint | as graded | minus (c) | minus (c)+(d) | minus (c)+(d)+(b) |
|---|---:|---:|---:|---:|
| comments-index | 0.9510 | 0.9604 | **1.0000** | 1.0000 |
| conversations-index | 0.9211 | 0.9292 | 0.9633 | **1.0000** |
| notifications-index | 0.9432 | 0.9540 | 0.9540 | **1.0000** |
| people-stream | 0.9695 | 0.9755 | **1.0000** | 1.0000 |

---

## The four root causes

### RC-1 — (d) `lazy_columns` is switched off under `RAILS_ENV=concolic` → `profiles` is 4 columns wider

*12 pairs: `profiles.bio`, `profiles.birthday`, `profiles.gender`, `profiles.location`
on comments-index, conversations-index and people-stream.*

Our policy statement (conversations-index, statement #58, one of 62 carrying it):

```sql
SELECT `profiles`.* FROM `profiles`, `people` AS `people190`,
  `conversation_visibilities` AS `conversation_visibilities143`, ...
WHERE `profiles`.`person_id` = `people190`.`id` AND ...
```

The reference's counterpart (`conversations-index.sql:1`) is the same join with an
**explicit 14-column** projection:

```sql
SELECT `profiles`.`id`, `profiles`.`diaspora_handle`, `profiles`.`first_name`,
       `profiles`.`last_name`, `profiles`.`image_url`, `profiles`.`image_url_small`,
       `profiles`.`image_url_medium`, `profiles`.`searchable`, `profiles`.`person_id`,
       `profiles`.`created_at`, `profiles`.`updated_at`, `profiles`.`full_name`,
       `profiles`.`nsfw`, `profiles`.`public_details`, ...
```

That list is *exactly* `profiles`' schema order minus `birthday`, `gender`, `bio`,
`location` — i.e. a deliberate, column-accurate omission, not a shortfall.

**The cause, found in the app fork itself.** `ruby_examples/dse-apps/apps/diaspora/app/models/profile.rb:8-11`:

```ruby
if Rails.env.include?("mod") || Rails.env == "test"
  lazy_load :bio, :gender, :birthday, :location
end
```

* `lazy_load` comes from the `lazy_columns` gem (`Gemfile:101`, `Gemfile.lock:257`,
  `lazy_columns (0.5.9)`). It rewrites the model's default projection to
  `column_names - lazy`, and fetches the lazy columns only on first attribute read.
* This block **does not exist in the vendored upstream** the bench ships
  (`policy-extraction-bench/repos/diaspora/app/models/profile.rb`) — `diff` shows it
  as the only difference between the two files. It is the DSE/Blockaid fork's
  instrumentation, i.e. precisely the instrumentation the answer keys were extracted
  under.
* `config/environments/` contains `production_mod.rb` and `production_mod_checked.rb`
  — the `"mod"` envs — alongside this project's own `concolic.rb`.
* **We run as `RAILS_ENV=concolic`** (`scripts/diaspora-concolic:17`).
  `"concolic".include?("mod")` is false and `"concolic" == "test"` is false, so
  `lazy_load` never fires and ActiveRecord emits a plain `SELECT profiles.*`.

The real recorded query, from `results3/comments_index/dump_auth_json_dse0004.json`
(`note` field of a `symbolic_result`):

```
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = $$(SYM_RESULT_ActiveRecord__Relation_records_1_row_author_id)
```

So the four columns really are read from the database on our runs. This is not
fabrication and not a defect in the extractor — it is a *driving-environment*
difference that makes the real SQL genuinely wider than the SQL the reference
observed.

**Corroboration that this is the mechanism, not a coincidence:** the reference's
own `notifications-index.sql:93,101` contains the **full 18-column** `profiles`
projection — including `birthday`, `gender`, `bio`, `location` — and both
statements are gated on `profiles.public_details = TRUE` or `contacts.sharing = TRUE`:

```sql
SELECT `profiles`.`id` AS `id1`, ..., `profiles`.`birthday`, `profiles`.`gender`,
       `profiles`.`bio`, ..., `profiles`.`location`, ...
FROM `notifications`, `contacts`, `profiles`
WHERE `notifications`.`type` = 'Notifications::StartedSharing'
  AND (`profiles`.`public_details` = TRUE AND `profiles`.`person_id` = `notifications`.`target_id`) ...
```

That is the *lazy fetch* firing, and its gate matches
`app/presenters/profile_presenter.rb#private_hash` (`bio`, `birthday`, `gender`,
`location` — the same four, and only those four) reached via
`PersonPresenter#full_hash`'s `show_profile_info: public_details? || own_profile? || person_is_following_current_user`.
`profile_presenter.rb` is byte-identical between our fork and the vendored upstream.
This is also why notifications-index has **no** `profiles` extras: the reference
already carries the wide read there.

**Fix location (not applied):** either drive the app under an env whose name
satisfies `Rails.env.include?("mod")`, or make `config/environments/concolic.rb`
declare the same lazy set. The decision is a *shared target-boundary* question
(Rule T) because it changes the recorded SQL for every endpoint, and it is
governed by the app-code discipline in `CLAUDE.md` — do not change
`app/models/profile.rb`.

---

### RC-2 — (b) the reference never drove the **mobile layout**

*12 pairs: `reports.id` ×2, `tag_followings.*` ×5, `tags.id`/`tags.name`/`tags.taggings_count` ×5.*

Our statements (conversations-index #450 and #463; identical pair in notifications-index):

```sql
SELECT `tags`.* FROM `tags` INNER JOIN `tag_followings` ON `tags`.`id` = `tag_followings`.`tag_id`,
       `users` AS `users926`
WHERE `tag_followings`.`user_id` = `users926`.`id` AND `users926`.`id` = _MY_UID;

SELECT `reports`.`id` FROM `reports` WHERE `reports`.`reviewed` = FALSE;
```

**Both are real.** From `results3/conversations_index/dump_mobile_plain_dse0001_n1r22.json`,
three consecutive `symbolic_results` with their `note` (the verbatim SQL):

```
SELECT "tags".* FROM "tags" INNER JOIN "tag_followings" ON "tags"."id" = "tag_followings"."tag_id"
  WHERE "tag_followings"."user_id" = $$(SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_id)
  ORDER BY tags.name

SELECT 1 AS one FROM "roles" WHERE "roles"."name" IN ('moderator', 'admin')
  AND "roles"."person_id" = $$(...devise_user_first_1_person_id) LIMIT 1          -- value: true

SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" = false
```

and from `results3/notifications_index/dump_mobile_typed_dse0064_C20Rmobt0000r0.json`:

```
SELECT "tag_followings".* FROM "tag_followings" WHERE "tag_followings"."user_id" = $$(...devise_user_first_1_id)
```

**The code path.** `app/views/layouts/_drawer.mobile.haml` is rendered only from
`app/views/layouts/application.mobile.haml:24` (`render "layouts/drawer"`); there is
no drawer in `application.html.haml`. The drawer does:

* `_drawer.mobile.haml:26` — `current_user.followed_tags.each do |tag|`, and
  `app/models/user.rb:79` declares
  `has_many :followed_tags, -> { order('tags.name') }, through: :tag_followings, source: :tag`
  → exactly the `tags ⋈ tag_followings` query above.
* `_drawer.mobile.haml:49-60` — `unreviewed_reports_count`, defined at
  `app/helpers/report_helper.rb:22-24` as `Report.where(reviewed: false).size`, gated
  by `current_user.admin?` / `current_user.moderator?` → the `roles` exists? probe,
  then the `reports` COUNT. Its only other call sites are `admins/_admin_bar.haml`
  and `admins/_dashboard.haml`, i.e. admin pages, never the desktop layout of these
  endpoints.

**Format census over our dumps** (`grep -l` by dump-name format prefix):

| endpoint | query | html | js | json | xml | mobile |
|---|---|---:|---:|---:|---:|---:|
| conversations_index (18 623 dumps) | `tag_followings` | 0 | 0 | 0 | 0 | **5 857** |
| conversations_index | `FROM "reports"` | 0 | 0 | 0 | 0 | **1 347** |
| notifications_index (3 000-dump sample) | `tag_followings` | 0 | — | 0 | 0 | **415** |
| notifications_index (same sample) | `FROM "reports"` | 0 | — | 0 | 0 | **84** |

Strictly mobile-only, exactly as the view code predicts.

**The reference has none of it.** `grep -c '`reports`\|`tag_followings`'` over
*every* file in `data/answers/diaspora/` (including the `.raw.sql`
pre-minimization variants and `all.sql`) returns **0** for all 13 files. The
reference's only `tags` statement, `notifications-index.sql:17`, reaches `tags`
through `taggings` on a `Profile` — the profile-tag path, not the followed-tag path:

```sql
SELECT `tags`.`name`, `taggings`.`id` FROM `notifications`, `contacts`, `profiles`, `tags`, `taggings`
WHERE `tags`.`id` = `taggings`.`tag_id` AND `taggings`.`taggable_id` = `profiles`.`id` ...
```

which is why `tags.name` is *not* an extra there but `tags.id` and
`tags.taggings_count` are.

Notably the reference **did** explore the gate and stop short of the query behind
it: `conversations-index.sql:15,17` contain

```sql
SELECT 1 AS `one` FROM `people`, `roles` WHERE `roles`.`name` IN ('admin', 'moderator')
  AND `roles`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;
```

— the moderator probe — with no `reports` statement following it. That is the
signature of a run that rendered the desktop layout only.

**Verdict: (b).** These are real disclosures the external reference does not
record. They are also the entirety of the `table_precision` gap: 4 extra tables on
conversations-index (`posts`, `reports`, `tag_followings`, `tags`) → 11/15 = 0.733,
and 2 on notifications-index (`reports`, `tag_followings`) → 18/20 = 0.900.

---

### RC-3 — (c) `SELECT 1 AS one` is parsed as a column literally named `1`

*4 pairs: `posts.1` on all four endpoints.*

Our statements:

```sql
SELECT 1 AS one FROM `posts`;                                                        -- comments, conversations, notifications
SELECT 1 AS one FROM `posts` WHERE `posts`.`guid` = 'abcdef0123456789abcdef0123456789'; -- people-stream
```

Real, recorded, from `results3/comments_index/dump_anon_json_dse0001.json`:

```
SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = $$(SYM_PARAM_dlink_guid0_Relation_records_1_row2) LIMIT 1
```

(diaspora's `diaspora://` d-link resolution — `Post.exists?(guid: …)` — reached from
rendered message/comment text; it also appears in
`results3/conversations_index/dump_html_plain_dse0002_n1r22.json` and
`results3/people_stream/dump_anon_json0009_LEN.json`.)

**This is a bench-side parser artifact.** `bench/sqlnorm.py:229`:

```python
if not item or item in ("1", "*") and not tables:
    continue
```

Python binds this as `not item or (item in ("1","*") and not tables)`, so the
literal `1` is dropped **only when the statement has no FROM tables**. With a FROM
list it falls through and is recorded as a column. Then at line 240-246: with
exactly one table it is attributed to that table → `("posts", "1")`; with two or
more it lands on the sentinel → `("?", "1")`.

The reference is hit by the same bug, which is why it cancels there and not here:
every `SELECT 1 AS one` in the diaspora answer keys ranges over **two or more**
tables (e.g. `conversations-index.sql:15` over `people, roles`; `people-stream.sql`'s
ten `SELECT 1 AS one, people.guid FROM people, people0, posts, …`), so the reference
contributes `("?", "1")` — and indeed both sides carry `("?", "1")` on
conversations-index, notifications-index and people-stream, where it cancels
harmlessly. Ours is single-table, so it lands on `posts`.

A correctly-parsed `SELECT 1 AS one` discloses **no column at all**, so this pair is
not a claim about data. **Verdict: (c).**

*Caveat, stated honestly:* on **conversations-index** this statement is also the
sole reason `posts` counts as an extra *table*, and the reference's
conversations-index genuinely has no `posts` statement (it does have one on
comments-index and people-stream) — so at the *table* level this one has a (b)
component as well. At the `(table, column)` level, which is what
`disclosure_precision` scores, it is (c).

---

### RC-4 — (c) `aggregate-as-rows`: we add the primary key to an aggregate

*1 pair: `conversation_visibilities.id` on notifications-index.*

Our statement (#27, and 3 more):

```sql
SELECT `conversation_visibilities`.`id`, `conversation_visibilities`.`unread`
FROM `conversation_visibilities`, `people` AS `people522`, `users` AS `users926`, ...
WHERE `conversation_visibilities`.`person_id` = `people522`.`id`
  AND `people522`.`owner_id` = `users926`.`id` AND `users926`.`id` = _MY_UID ...
```

The reference (`notifications-index.sql:103`) is the same read without the key:

```sql
SELECT `conversation_visibilities`.`unread` FROM `people`, `conversation_visibilities`
WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;
```

The real recorded query
(`results3/notifications_index/dump_mobile_typed_dse0064_C20Rmobt0000r0.json`) is an
aggregate:

```
SELECT SUM("conversation_visibilities"."unread") FROM "conversation_visibilities"
  WHERE "conversation_visibilities"."person_id" = $$(...devise_user_first_1_person_id)
```

`src/queries_from_runs/transform.py:692-717` (`aggregate-as-rows`) deliberately
rewrites `SUM(t.c)` to *primary key + the summed column*, and `COUNT(*)` to the
primary key of every relation it ranges over — because "`COUNT(*)` does not say
which rows the endpoint read, and a consumer cannot expand it itself once the FROM
list carries an alias". The reference keeps only the aggregated column. Same
underlying read, different factoring. **Verdict: (c).**

The same convention is why the `reports` statement in RC-2 reads `SELECT reports.id`
while the recorded query is `SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" = false`
— there the *table* is absent from the reference regardless, so it is counted under
(b), but the column name `id` is this convention's product, not a claim that
`reports.id` values reach the user.

---

## Per-endpoint summary

### comments-index — 5 extra pairs, precision 0.9510
| pair(s) | bucket | cause |
|---|---|---|
| `posts.1` | (c) | RC-3 |
| `profiles.bio`, `.birthday`, `.gender`, `.location` | (d) | RC-1 |

No extra tables (`table_precision` 1.000); no missed pairs (`disclosure_recall` 1.0000).
With (c)+(d) removed: **1.0000**.

### conversations-index — 9 extra pairs, precision 0.9211, table_precision 0.733
| pair(s) | bucket | cause |
|---|---|---|
| `posts.1` | (c) (+(b) at table level) | RC-3 |
| `profiles.bio`, `.birthday`, `.gender`, `.location` | (d) | RC-1 |
| `reports.id` | (b) | RC-2 |
| `tags.id`, `tags.name`, `tags.taggings_count` | (b) | RC-2 |

Extra tables: `posts`, `reports`, `tag_followings`, `tags` — all (b), all traced to
real mobile-layout / d-link queries above. `tag_followings` contributes no extra
*pair* because it only appears in the JOIN `ON`, not the select list.

Separately (not precision, noted for completeness): this is the one endpoint with a
real recall gap (0.8898) — 13 missed pairs, all of `notifications.*` (7) and most of
`contacts.*` (6). That is a coverage question, not in this document's scope.

With (c)+(d) removed: 0.9633. With (b) too: **1.0000**.

### notifications-index — 10 extra pairs, precision 0.9432, table_precision 0.900
| pair(s) | bucket | cause |
|---|---|---|
| `conversation_visibilities.id` | (c) | RC-4 |
| `posts.1` | (c) | RC-3 |
| `reports.id` | (b) | RC-2 |
| `tag_followings.id`, `.tag_id`, `.user_id`, `.created_at`, `.updated_at` | (b) | RC-2 |
| `tags.id`, `tags.taggings_count` | (b) | RC-2 |

No `profiles` extras — the reference's own answer key already carries the wide,
lazy-fetched `profiles` projection here (RC-1 corroboration). One missed pair,
`taggings.id`.

With (c) removed: 0.9540. With (b) too: **1.0000**.

### people-stream — 5 extra pairs, precision 0.9695
| pair(s) | bucket | cause |
|---|---|---|
| `posts.1` | (c) | RC-3 |
| `profiles.bio`, `.birthday`, `.gender`, `.location` | (d) | RC-1 |

No extra tables; no missed pairs. With (c)+(d) removed: **1.0000**.

---

## Bucket totals

| endpoint | extra pairs | (a) bug | (b) reference incomplete | (c) representation | (d) env mismatch |
|---|---:|---:|---:|---:|---:|
| comments-index | 5 | 0 | 0 | 1 | 4 |
| conversations-index | 9 | 0 | 4 | 1 | 4 |
| notifications-index | 10 | 0 | 8 | 2 | 0 |
| people-stream | 5 | 0 | 0 | 1 | 4 |
| **total** | **29** | **0** | **12 (41 %)** | **5 (17 %)** | **12 (41 %)** |

---

## Verdict

**None of the disclosure-precision gap is a genuine over-disclosure defect in our
extraction.** Every one of the 29 extra `(table, column)` pairs was traced to a
verbatim SQL string recorded in a named dump file, and to the diaspora view/helper
code that issues it. Bucket (a) is empty. The project's own claim — that nothing
admitted is fabricated — survives the comparison intact.

The gap is a **roughly even three-way mix, and it is a mix in a specific sense:
two of the three parts are not our extractor's doing, and the third is a driving
choice rather than an extraction bug.**

* **41 % (12 pairs) — bucket (b), the reference is incomplete.** The external
  answer keys never drove diaspora's mobile layout. `reports`, `tag_followings` and
  the followed-tags `tags` join appear in *zero* of the 13 diaspora answer-key
  files, while our mobile dumps record them thousands of times, and
  `_drawer.mobile.haml` / `report_helper.rb` show exactly why they fire. The
  reference even records the moderator `roles` probe and then stops before the
  `reports` COUNT behind it. This is the same class of finding as the
  `as_api_response` / `people_from_string` / `Person#name` mocks in
  `_COMMENTS_PRECISION_FIX_20260917.md`, only on the other side of the comparison.
  This is also **100 % of the `table_precision` gap** on both affected endpoints.

* **41 % (12 pairs) — bucket (d), an environment mismatch that is ours to
  decide.** `lazy_columns`' `lazy_load :bio, :gender, :birthday, :location` is
  gated on `Rails.env.include?("mod") || Rails.env == "test"`; we drive under
  `RAILS_ENV=concolic`, so the app really does issue the wider `SELECT profiles.*`.
  Our record of it is accurate. But it is fair to say the reference and we are
  running *different configurations of the same app*, and the reference's is the
  one the answer keys were written against. This is the only part of the gap that
  is worth changing something about — and the change belongs in the run
  environment (`config/environments/concolic.rb` or the `RAILS_ENV` in
  `scripts/diaspora-concolic:17`), **not** in `app/models/profile.rb` and not in
  the extractor. Because it moves the recorded SQL for every endpoint, it is a
  Rule-T shared-boundary decision, not a local fix.

* **17 % (5 pairs) — bucket (c), pure metric artifact.** Four are a literal `1`
  from `SELECT 1 AS one` that `bench/sqlnorm.py:229` misreads as a column name (a
  bug in the bench, which bites the reference too but cancels there because its
  `SELECT 1` statements are multi-table); one is our documented `aggregate-as-rows`
  primary-key convention meeting the reference's bare-aggregate-column convention.
  Neither names any real data.

Nothing here is evidence against `_COMMENTS_PRECISION_FIX_20260917.md`'s
"100 % precision by this project's definition". On comments-index specifically the
entire 4.9-point gap is one bench parser artifact plus four columns the app
genuinely reads under our run environment. Recall — not precision — remains the
only place where a real coverage question is open, and only on
conversations-index.

### Not fixed here (investigation only)

| # | what | where |
|---|---|---|
| D-1 | `lazy_load` inactive under `RAILS_ENV=concolic`; widens every `profiles` read by 4 columns | `scripts/diaspora-concolic:17` / `ruby_examples/dse-apps/apps/diaspora/config/environments/concolic.rb`; the gate is `app/models/profile.rb:8-11` (**do not edit**) |
| C-1 | `SELECT 1 AS one` yields a column named `1` | `policy-extraction-bench/bench/sqlnorm.py:229` — precedence: `not item or (item in ("1","*") and not tables)` |
| B-1 | reference answer keys carry no mobile-layout disclosures | upstream defect in `data/answers/diaspora/*.sql`; see `PROVENANCE.md` (engine `zhangwen0411/concolic_driver` @ `560a1903`, runs written 2024-04-13/14) — nothing to fix on our side |

### Method note

The diff was computed by importing `bench.sqlnorm` / `bench.tasks` directly and
replicating `grade.py`'s `analyse()` exactly (same `split_statements` → `parse` →
`expand_star` → set difference), rather than re-running `bench.grade`; the
per-endpoint totals reproduce the graded table to 4 decimal places, and the
bucket-removal counterfactuals land on exactly 1.0000, so the accounting is
complete. `bench.grade`/`bench.containment` were not re-run — a
`benchcontain-smoke-20260919.scope` containment smoke test was live throughout.
