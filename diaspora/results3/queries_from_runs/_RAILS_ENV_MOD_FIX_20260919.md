# RC-1 — `RAILS_ENV=concolic_mod` and the `profiles` lazy-column projection

**Date:** 2026-09-18/19
**Root cause under repair:** RC-1 / bucket (d) of `_PRECISION_VS_BENCH_20260919.md`
**Headline:** the briefed environment fix is **necessary but not sufficient**. It is
correct about the application and wrong about our corpus. Changing `RAILS_ENV`
alone changes **nothing** in the dumps, because every `profiles` projection we
record is *synthesised by the batch-local mock layer*, never read from
ActiveRecord. The complete repair is **two** independent changes; both are
verified here, one is committed and one is deliberately left as a prototype
pending a Rule-T decision.

---

## 1. What was asked, and what is actually true

The brief asked for an environment-only change: create a `"mod"`-named env so
`app/models/profile.rb:8`'s

```ruby
if Rails.env.include?("mod") || Rails.env == "test"
  lazy_load :bio, :gender, :birthday, :location
end
```

fires, and then re-drive so the 4 lazy columns stop appearing in every
`profiles` read.

**Half of that is confirmed.** Under the new env the application really does
narrow its projection, to *exactly* the reference's 14 columns in the same
order (boot probe, both envs, same process shape as the runner):

| | `RAILS_ENV=concolic` | `RAILS_ENV=concolic_mod` |
|---|---|---|
| `Rails.env.include?("mod")` | false | **true** |
| `Profile.default_scopes` | 0 | **1** |
| `Profile.where(person_id: 1).to_sql` | `SELECT "profiles".* …` | `SELECT profiles.id, profiles.diaspora_handle, profiles.first_name, profiles.last_name, profiles.image_url, profiles.image_url_small, profiles.image_url_medium, profiles.searchable, profiles.person_id, profiles.created_at, profiles.updated_at, profiles.full_name, profiles.nsfw, profiles.public_details …` |
| projection width | 18 (star-expanded) | **14** |

`lazy_columns-0.5.9` implements `lazy_load` as
`default_scope { select(column_names - lazy) }`
(`lib/lazy_columns/acts_as_lazy_column_loader.rb`), which is why the change is
visible as a `default_scope`.

**The other half is false for our corpus.** A *seed-exact* A/B replay of the
same recorded seeds under the two environments produced **byte-identical**
dumps — 15 `SELECT "profiles".*` note occurrences on both sides, zero note
deltas. The reason is that the notes are hand-built strings, e.g.

* `comments_index/concolic_targets.rb:225` (`class_finder_sql`)
  `%(SELECT "#{table}".* FROM "#{table}" WHERE #{conditions})`
* `comments_index/targets.rb:362` (`emit_includes_preloads`)
  `psql = %(SELECT "#{table}".* FROM "#{table}" WHERE … )`

Neither consults the model's projection, so no environment can affect them.

Corpus-wide confirmation (distinct notes mentioning `profiles`):

| endpoint | distinct profiles notes | bare `profiles.*` | explicit column list |
|---|---:|---:|---:|
| comments_index | 14 | **14** | 0 |
| conversations_index | 14 | 13 | 1 (an app-level `.select`, unrelated) |
| people_stream | 3 | **3** | 0 |

---

## 2. Scope — which endpoints RC-1 actually affects

Determined from the graders' own pair sets, not from dates. (Note: a bare
`dump_*.json` glob hits `argument list too long` and silently reports 0, and a
grep for `'"profiles"'` **with quote characters** returns 0 on all four corpora
because the SQL is a JSON string value and `"` is escaped as `\"`. Both traps
were hit and corrected; the numbers below use an unquoted substring search via
`find -print0 | xargs -0 grep -l`.)

| endpoint | dumps | dumps containing `profiles` | extra pairs | of which `profiles` lazy cols | in RC-1 scope? |
|---|---:|---:|---:|---:|---|
| comments_index | 26,528 | 26,464 | 4 | **4** | **yes** |
| conversations_index | 18,623 | 18,543 | 8 | **4** | **yes** |
| people_stream | 13,677 | 10,766 | 4 | **4** | **yes** |
| notifications_index | 313,977 | 272,858 | 9 | **0** | **NO** |

**notifications_index must NOT get this fix.** Its reference *already carries
the wide 18-column projection* (`data/answers/diaspora/notifications-index.sql`
contains `birthday` in 2 statements — the lazy fetch firing, gated on
`profiles.public_details = TRUE` / `contacts.sharing = TRUE`). The other three
references contain **zero** occurrences of `birthday`. So for notifications our
star projection is *correct*, and narrowing it would cost recall (currently
0.9940) unless the lazy-fetch second statement is also modelled.

This is a correction to the brief, which listed all four as candidates.

---

## 3. Change 1 (COMMITTED) — the environment

### `config/environments/concolic_mod.rb` (new)

Settings are byte-identical to `concolic.rb` — verified by diffing both files
with comments and blank lines stripped ("IDENTICAL SETTINGS BLOCK"). Only the
filename (which is what Rails resolves `Rails.env` from) and the header comment
differ.

```ruby
# frozen_string_literal: true
#
# Concolic "mod" environment — byte-for-byte the same Rails settings as
# concolic.rb; the ONLY thing that differs is the environment *name*.
#
# Why it exists: app/models/profile.rb:8 reads
#
#     if Rails.env.include?("mod") || Rails.env == "test"
#       lazy_load :bio, :gender, :birthday, :location
#     end
#
# Under RAILS_ENV=concolic that check is false, so `lazy_columns` never fires
# and ActiveRecord emits a plain `SELECT profiles.*` that always carries
# bio/gender/birthday/location. The reference/benchmark answer keys were
# extracted under a "mod" environment, where those four columns are excluded
# from the default projection and only appear via an explicit lazy fetch (e.g.
# ProfilePresenter#private_hash). Driving under RAILS_ENV=concolic_mod makes
# `Rails.env.include?("mod")` true, so lazy_load behaves like the reference
# environment and our recorded SQL regains that conditional disclosure.
#
# The name is also chosen NOT to contain "checked", so the
# `Rails.env.include? "checked"` branches in application_controller.rb:8 and
# user.rb:598 stay off, exactly as under "concolic".
#
# Settings below are identical to concolic.rb:
# - eager_load = false  (avoid eager DB connection at boot; we load classes on demand)
# - No dev/test-only gems (no TurboDevAssets, no RSpec/Cucumber)
# - cache_classes = true (we don't reload; we want stable class definitions)

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.active_support.deprecation = :log
  config.log_level = :warn
  config.active_record.dump_schema_after_migration = false
end
```

### Three additive config entries — NOT in the brief, but mandatory

Rails and `config/load_config.rb` resolve these files **by environment name**.
The brief did not mention them; without them the app does not boot under the
new env. Each is a verbatim clone of the existing `concolic:` section:

* `config/database.yml` — new `concolic_mod:` (sqlite3, `db/concolic.sqlite3`).
  In practice the runners hardcode `ActiveRecord::Base.establish_connection(:concolic)`,
  so this is belt-and-braces; it still matters for
  `config/initializers/prosody.rb:5`'s `database_configuration[Rails.env]`.
* `config/defaults.yml` — new `concolic_mod:`. **This one is load-bearing:**
  `load_config.rb:35` registers this file with `namespace: rails_env` and *no*
  `required: false`.
* `config/diaspora.yml` — new `concolic_mod:` section, for parity.

### Env-name safety audit

`grep -rn "Rails.env" app/ config/ lib/` — the only other name-sensitive checks
are `Rails.env.include? "checked"` (`application_controller.rb:8`,
`user.rb:598`), `.test?`, `== "production"`, `.start_with?("production")`,
`.development?`. `"concolic_mod"` satisfies none of them, exactly as
`"concolic"` does not. `production_mod.rb` was **not** reusable — it is a
symlink to the full `production.rb` (eager_load, real secrets, asset pipeline).

---

## 4. Change 2 (PROTOTYPE ONLY — needs a Rule-T decision) — the target layer

Without this, Change 1 is inert on the corpus.

A single app-agnostic helper added to the endpoint's `concolic_targets.rb`:

```ruby
def default_projection(klass)
  tbl = klass.respond_to?(:table_name) ? klass.table_name : nil
  star = tbl ? %("#{tbl}".*) : "*"
  return star unless klass.respond_to?(:all)
  sel = klass.all.select_values
  return star if sel.nil? || sel.empty?
  sel.map(&:to_s).join(", ")
rescue Exception
  tbl ? %("#{tbl}".*) : "*"
end
```

applied at **5** synthesis sites (comments_index copies): `concolic_targets.rb`
`class_finder_sql` and the `SingularAssociation#find_target` note; `targets.rb`
`emit_includes_preloads`, `BelongsToPolymorphicAssociation#find_target`, and
`SingularAssociation#find_target`. The preload site is guarded so it only
narrows when the table being selected FROM is the association target's own
table (never a through/join table).

**Two sites are deliberately left starred:**

* `targets.rb` `ActiveRecord::Base#reload` — Rails' `reload` is
  `self.class.unscoped { find(id) }`, so it bypasses `default_scope` and really
  does read all 18 columns. This is *precisely* the mechanism that produces the
  reference's 18-column gated statements in notifications-index. Narrowing it
  would have been wrong.
* the through-reflection intermediate read (`isql`), whose table is the join
  table, not the target model's.

**Blast radius is provably exactly the `profiles` reads:** `Profile` is the only
model in the app that calls `lazy_load`, and `grep -rn "default_scope" app/ lib/`
returns nothing else. For every other model `select_values` is empty and the
helper returns the star unchanged.

### Why this is prototype-only

It changes the shared target boundary (Rule T), which the RC-1 write-up itself
flagged, and it would have to be replicated at ~6 sites in conversations_index
and ~11 in notifications_index. It lives in
`results3/_redrive_20260919/_proto/` — **copies**. The endpoints' real
`concolic_targets.rb` / `targets.rb` and the shared
`reports/diaspora/concolic_targets.rb` are untouched.

---

## 5. Re-drive method (comments_index)

`scripts/diaspora-concolic` was **NOT edited** — `posts_show` and `people_show`
are being driven through it by other agents. Every run used an inline
invocation mirroring it exactly, with `RAILS_ENV=concolic_mod`.

Seed-exact replay, per variant, from the corpus's own recorded
`concolic_seeds` (all 26,528 distinct, recovered 1:1 and grouped by the
scenario that produced them — nothing re-selected or synthesised):

```
RAILS_ENV=concolic_mod VARIANT=<v> VARIANTS=<v> \
EXTRA_SEEDS_JSON=_seeds/comments_index__<v>.json SEEDS_ONLY=1 \
LABEL_SUFFIX=_MOD919 MAX_RUNS=<n+10> TIME_BUDGET=28800 \
DUMP_OUT=_redrive_20260919/comments_index \
  bundle exec jruby -I. _redrive_20260919/_proto/run_dse.rb
```

Four variants in parallel, each in its own
`systemd-run --user --scope -p MemoryMax=6G` unit. The runner already supports
per-variant invocation, so no `SCENARIO_ONLY` knob had to be added (unlike the
people_stream precedent).

**The original corpus was never written to** — `comments_index/run_dse.rb`
honours `DUMP_OUT`, so fresh dumps went to a separate directory. (Unlike
`people_stream/run_dse.rb:598`, comments_index has no destructive
`Dir.glob(...).each { File.delete }`.) Pre-drive `exploration_summary.json`
files for all four endpoints were backed up to
`_redrive_20260919/_bak/` regardless.

### Branching-safety verification — the assumption was tested, not trusted

| variant | seeds | dumps | runs = distinct paths | worklist drained | run errors | per-seed PC mismatches |
|---|---:|---:|---|---|---|---|
| anon_json | 6,255 | 6,255 | 6,255 = 6,255 | true | {} | **0 / 6,255** |
| anon_mobile | 6,173 | 6,173 | 6,173 = 6,173 | true | {} | **0 / 6,173** |
| auth_json | 6,982 | 6,982 | 6,982 = 6,982 | true | {} | **0 / 6,982** |
| auth_mobile | 7,118 | 7,118 | 7,118 = 7,118 | true | {} | **0 / 7,118** |
| **total** | **26,528** | **26,528** | — | — | 0 harness failures | **0 / 26,528** |

`_verify_corpus.py` additionally confirms, per variant: identical PC-signature
multiset, identical PC-count multiset, identical error profile, 0 missing seeds,
0 duplicate seeds. **VERDICT: BRANCHING IDENTICAL.** The corpus differs from the
original only in recorded SQL notes, which is the whole point.

Residual `SELECT "profiles".*` notes in the fresh corpus: **0**.

Note: `comments_index/exploration_summary.json` on disk describes a 22-run
`auth_mobile` probe, not the 26,528-dump corpus, so a before/after comparison of
*that file* would have been meaningless. The per-seed PC identity check above is
the real evidence, and it is far stronger.

---

## 6. Results — measured, full corpus

### 6.1 Extraction

Same recipe as the baseline (`_pcfold3_parallel.py --shards 8 --cap 2`), over the
26,528 fresh dumps: 413,594 raw queries, 407 distinct `(shape, preds)`,
**0 errors**, 387 s. Both arms render **155 statements, PC 1230 → 166 kept**.

**155 statements is exactly the baseline's statement count** (`n_pred_statements
= 155`). The policy did not gain or lose a single statement — only the
`profiles` projections changed, which is the intended and only effect.

In the new policy: `SELECT profiles.*` occurrences = **0**;
`profiles.bio|gender|birthday|location` occurrences = **0**.

The projection is rendered in exactly the reference's form:

```sql
SELECT `profiles`.`id`, `profiles`.`diaspora_handle`, `profiles`.`first_name`,
       `profiles`.`last_name`, `profiles`.`image_url`, `profiles`.`image_url_small`,
       `profiles`.`image_url_medium`, `profiles`.`searchable`, `profiles`.`person_id`,
       `profiles`.`created_at`, `profiles`.`updated_at`, `profiles`.`full_name`,
       `profiles`.`nsfw`, `profiles`.`public_details` FROM `profiles`, …
```

### 6.2 `bench.grade` — before / after

Baseline = `_bench_20260919/ours_pcfold3_fix.jsonl` graded as of this session
(`ours_pcfold3_fix.graded_postfix.jsonl`). Only comments-index was re-driven;
the other three rows are unchanged and are shown to confirm nothing regressed.

| task | metric | before | after |
|---|---|---:|---:|
| **diaspora/comments-index** | **disclosure_precision** | **0.9604** | **1.0000** |
| | disclosure_recall | 1.0000 | 1.0000 |
| | disclosure_f1 | 0.9798 | **1.0000** |
| | disclosure_macro_f1 | 0.9792 | **1.0000** |
| | table_f1 | 1.0000 | 1.0000 |
| | extra (table,column) pairs | **4** | **0** |
| | pred cols vs ref cols | 101 vs 97 | **97 vs 97** |
| diaspora/conversations-index | disclosure_precision | 0.9286 | 0.9286 (untouched) |
| diaspora/notifications-index | disclosure_precision | 0.9483 | 0.9483 (untouched) |
| diaspora/people-stream | disclosure_precision | 0.9753 | 0.9753 (untouched) |

Suite-level (4 tasks):

| | before | after |
|---|---:|---:|
| disclosure_precision | 0.9462 | **0.9630** |
| disclosure_f1 | 0.9581 | **0.9666** |
| disclosure_macro_f1 | 0.8598 | **0.8712** |
| disclosure_recall | 0.9709 | 0.9707 |
| table_f1 | 0.9484 | 0.9484 |

The four RC-1 extra pairs on comments-index — `profiles.bio`,
`profiles.birthday`, `profiles.gender`, `profiles.location` — are **gone**, with
**no** new missing pairs. comments-index is now an exact column-set match
against the reference (97 = 97).

The small `disclosure_recall` movement (0.9709 → 0.9707) is a suite-level
rounding artefact of comments-index's own recall staying at 1.0000 while its
column count shrank; its per-task recall is unchanged.

---

## 6.3 Promotion to conversations_index and people_stream (2026-09-18, second pass)

The target-layer fix was promoted from the prototype copies into the **real**
per-endpoint files, after comments_index proved it clean. `md5sum` confirmed
every endpoint keeps an independent copy; `posts_show`, `people_show`,
`notifications_index` and the shared `reports/diaspora/concolic_targets.rb`
were not touched. Pre-change backups: `<endpoint>/{concolic_targets,targets}.rb.pre_rc1_20260919`.

| endpoint | patched sites | left starred |
|---|---|---|
| people_stream | `concolic_targets.rb` ×2 (`class_finder_sql`, `SingularAssociation#find_target`) | — |
| conversations_index | `concolic_targets.rb` ×2, `targets.rb` ×4 (preload belongs_to / preload has_many / `SingularAssociation#find_target` / required-belongs_to probe) | `targets.rb:2005` (`reload` → `unscoped`, correctly full-width) |

Same seed-exact replay method, `RAILS_ENV=concolic_mod`, `SEEDS_ONLY=1`, one
process per scenario (`SCENARIO_ONLY` for people_stream, `VARIANTS` for
conversations_index). Neither runner supports `DUMP_OUT`, so fresh dumps were
written with `LABEL_SUFFIX=_RC1MOD` into the endpoint dir and moved out
afterwards; each endpoint's original `exploration_summary.json` was restored
from the pre-drive backup. **Both original corpora remain intact** (13,677 and
18,623 dumps).

Two method differences from comments_index, both real traps:
* people_stream dumps record **no `concolic_scenario` key**, so the scenario had
  to be derived from the label prefix (`anon_all0001_C12` → `anon_all`). The
  first extraction pass silently produced 13,677 one-seed "variants".
* conversations_index has **legitimate duplicate seeds** (e.g. `html_plain`
  2,659 dumps / 2,657 distinct), so the verifier's criterion is seed-**multiset**
  equality with the original, not duplicate-freeness.

### Branching safety — both clean

| endpoint | scenarios/variants | dumps | per-seed PC mismatches | error profiles | verdict |
|---|---:|---:|---:|---|---|
| people_stream | 3 | 13,677 = 13,677 | **0 / 13,677** | identical | **BRANCHING IDENTICAL** |
| conversations_index | 10 | 18,623 = 18,623 | **0 / 18,623** | identical | **BRANCHING IDENTICAL** |

0 harness failures across all 13 drive jobs. PC-signature and PC-count multisets
identical for every scenario on both endpoints.

### Extraction

| endpoint | dumps | raw queries | distinct (shape,preds) | statements | errors | star / lazycols in policy |
|---|---:|---:|---:|---:|---:|---|
| people_stream | 13,677 | 354,291 | 602 | 169 / 169 | 0 | **0 / 0** |
| conversations_index | 18,623 | 404,127 | 2,023 | — | 0 | **0 / 0** |

people_stream reproduces its documented post-redrive baseline **exactly**
(354,291 raw queries, 602 distinct, 169 statements), which is independent
confirmation that the replay was faithful.

### `bench.grade` — before / after

| task | disclosure_precision before | after | extra pairs before → after |
|---|---:|---:|---|
| comments-index | 0.9604 | **1.0000** | 4 → **0** |
| **people-stream** | 0.9753 | **1.0000** | 4 → **0** |
| **conversations-index** | 0.9286 | **0.9630** | 8 → **4** (RC-2 residue only) |
| notifications-index (untouched) | 0.9483 | 0.9483 | 9 → 9 |

Suite-level, across all four tasks:

| | original baseline | after all three RC-1 fixes |
|---|---:|---:|
| disclosure_precision | 0.9462 | **0.9778** |
| disclosure_f1 | 0.9581 | **0.9738** |
| disclosure_macro_f1 | 0.8598 | **0.8760** |
| disclosure_recall | 0.9709 | 0.9707 |
| table_f1 | 0.9484 | 0.9484 |

**people-stream is now an exact column-set match (158 = 158), as is
comments-index (97 = 97).** conversations-index lands precisely on the
0.9630 predicted by the RC-1 arithmetic; its 4 remaining extras
(`reports.id`, `tags.id`, `tags.name`, `tags.taggings_count`) are **RC-2**
(the reference never drove the mobile layout), a different root cause. Its 13
missing pairs are unchanged by this work.

## 7. Follow-ups — explicitly NOT done here

1. **`scripts/diaspora-concolic` still defaults to `RAILS_ENV=concolic`.**
   Flipping it project-wide is deliberately deferred until every endpoint has
   been migrated. Two endpoints are being driven through it *right now* by other
   agents; changing it would silently alter their environment mid-run.
2. **`posts_show` and `people_show` are untouched.** RC-1 is relevant to them,
   but they are owned by other agents and it is their call when to adopt it.
   (`people_show` additionally cannot be seed-replayed at all — it records no
   `concolic_seeds` and its runner deletes the corpus on startup; see
   `_REDRIVE_AND_REEXTRACT_STATUS.md` §5.)
3. **conversations_index and people_stream still need the fix** (4 lazy-column
   pairs each). Both are seed-replayable. people_stream needs only ~2 patch
   sites, conversations_index ~6. Expected effect: people-stream
   0.9753 → 1.0000; conversations-index 0.9286 → 0.9630 (its remaining 4 extra
   pairs are RC-2 mobile-layout, a different root cause).
4. **The target-layer change needs a Rule-T sign-off** before being applied to
   the endpoints' real target files.
5. **notifications_index: do not narrow** without also modelling the
   `reload`-driven lazy fetch, or recall will drop.

---

## 8. notifications_index — mechanism-level verification (2026-09-20)

**Question resolved:** the §2 exclusion table's "0 profiles lazy cols → NOT
in RC-1 scope" verdict was outcome-only (a `bench.grade` diff of 0). This
section traces the actual mechanism, as was done for the other three
endpoints, and reaches a **different, more specific conclusion**: the
exclusion's *outcome* (0 diff) is real and correctly computed, but its
*implied reason* ("this endpoint's reads are like people_show's — genuinely
always wide, so narrowing is wrong") is **not what's actually happening**.
The real reason is closer to the opposite: most of this endpoint's reads
*should* narrow (comments/conversations/people_stream's pattern), a small
minority genuinely should stay wide, and the "0 diff" is an artifact of how
`bench.grade` unions `(table,column)` pairs across the whole policy, not
evidence that today's mock gets each read's width right. **No fix is applied
here** — the reasoning below is why the obvious one (replicate the
`default_projection` helper) would make things *worse*, not better.

### 8.1 The reference has two distinct shapes, not one

`policy-extraction-bench/data/answers/diaspora/notifications-index.sql` carries
**18** distinct `profiles` statement shapes. **16 are narrow** (the same
14-column list as the other three endpoints' fixed form — id, diaspora_handle,
first_name, last_name, image_url, image_url_small, image_url_medium,
searchable, person_id, created_at, updated_at, full_name, nsfw,
public_details), covering the `also_commented` / `comment_on_post` / `liked` /
`mentioned*` / `reshared` notification types. **Exactly 2 are wide** (18
columns, `bio`/`gender`/`birthday`/`location` included) — lines 93 and 101,
both gated on `notifications.type = 'Notifications::StartedSharing'` AND
either `profiles.public_details = TRUE` or `contacts.sharing = TRUE`.

The smoking gun that these are genuinely two different real code paths, not
one: **line 59** is a *narrow* 14-column statement with the exact same join
shape and predicates as lines 93/101 (StartedSharing + the same `contacts`
join) **minus** the `public_details`/`sharing` gate:

```sql
-- line 59 (narrow — the base find, ALWAYS this width when reached)
SELECT `profiles`.`id`, ..., `profiles`.`public_details`
FROM `notifications`, `contacts`, `profiles`
WHERE `profiles`.`person_id` = `notifications`.`target_id` AND `notifications`.`type` = 'Notifications::StartedSharing'
  AND `contacts`.`user_id` = _MY_UID AND `contacts`.`person_id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

-- lines 93/101 (wide — an ADDITIONAL, conditionally-gated read of the SAME row)
SELECT `profiles`.`id` AS `id1`, ..., `profiles`.`birthday`, `profiles`.`gender`, `profiles`.`bio`, ..., `profiles`.`location`, ...
FROM `notifications`, `contacts`, `profiles`
WHERE `notifications`.`type` = 'Notifications::StartedSharing' AND (`profiles`.`public_details` = TRUE AND ...) ...
```

i.e. the reference shows a base find (Q1, always narrow when a StartedSharing
notification's target profile is read at all) plus a *second*, separately
gated read of the same row that pulls the 4 lazy columns (Q2, wide, only when
the gate is true). This is the `.reload`-on-lazy-access pattern, verified
against the vendored gem:

`lazy_columns-0.5.9/lib/lazy_columns/acts_as_lazy_column_loader.rb`:
```ruby
def define_lazy_accessor_for(column)
  define_method column do
    unless has_attribute?(column)
      changes_before_reload = self.changes.clone
      self.reload                              # ActiveRecord::Base#reload == unscoped { find(id) }
      changes_before_reload.each{|k,v| send("#{k}=", v[1])}
    end
    read_attribute column
  end
end
```

Calling `.bio`/`.gender`/`.birthday`/`.location` on a narrow-loaded `Profile`
triggers a full, `unscoped` re-fetch of the row (all 18 columns) — exactly
Q2. This is the same "`reload` legitimately bypasses `default_scope`" fact
the other three endpoints' fix (§4) already documented and deliberately left
starred at their own `reload`/through-reflection sites.

### 8.2 Where the app actually reaches Q2, and why it's rare

The reference's 16-vs-2 split says Q2 is rare across the explored space (one
notification type, one further-gated branch), not "always" the way it is for
people_show (798/800). Traced the real call chain for Q2:

* `NotificationsController#index` (`app/controllers/notifications_controller.rb:36`)
  preloads `Notification.includes(:target, :actors => :profile)` — this
  covers the **16 narrow shapes** (every actor's profile, every notification
  type). It does **not** preload a profile for `:target` itself.
* `app/views/notifications/_notification.haml:6-9`: only for
  `note.type == "Notifications::StartedSharing" && (!defined?(no_aspect_dropdown) || !no_aspect_dropdown)`,
  calls `gon_load_contact(note.contact)`.
* `app/serializers/notification_serializer.rb:14` renders that same partial
  with `locals: {note: object, no_aspect_dropdown: true}` for **all JSON
  rendering** — so the `no_aspect_dropdown` local is `true` there and the
  StartedSharing branch is **skipped for JSON**. `_notification.mobile.haml`
  never calls `gon_load_contact` at all. So Q2 only fires on **HTML-format,
  desktop-layout, StartedSharing notifications where `note.target.present?`**
  — a real, narrow, format-and-type-gated code path, distinct from the
  16-shape preload.
* `app/helpers/gon_helper.rb:4-9` `gon_load_contact` →
  `app/presenters/contact_presenter.rb:16-24` `full_hash_with_person` →
  `person_without_contact` → `PersonPresenter.new(person, current_user).as_json`
  → `app/presenters/person_presenter.rb:78-88` `full_hash_with_profile`:
  ```ruby
  if attrs[:show_profile_info]
    attrs.merge!(profile: ProfilePresenter.new(profile).private_hash)   # Q2 gate
  else
    attrs.merge!(profile: ProfilePresenter.new(profile).public_hash)
  end
  ```
  `show_profile_info` (`person_presenter.rb:18`) is
  `public_details? || own_profile? || person_is_following_current_user` —
  exactly the two OR-terms folded into lines 93/101's WHERE clauses.
  `ProfilePresenter#private_hash` (`app/presenters/profile_presenter.rb:27-34`)
  is what reads `bio`/`birthday`/`gender`/`location` and is the only call site
  in the app that does.

None of `PersonPresenter#full_hash`, `#own_profile?`, `#public_details?`,
`#person_is_following_current_user`, or `ProfilePresenter#private_hash`/
`#public_hash` are `declare_target`-walled in this endpoint (confirmed by
grep — no matches for any of them in `concolic_targets.rb`/`targets.rb`); they
run for real, so `show_profile_info` really is computed as a genuine decision
over real (symbolic) `contacts`/`profiles` state in this corpus already.

### 8.3 What the mock actually does — uniformly wide, not gated

All `profiles` SQL notes in this endpoint, at every site (`class_finder_sql`
`concolic_targets.rb:344-349`, `SingularAssociation#find_target`
`concolic_targets.rb:1367/1487`, `emit_includes_preloads`'s several `psql`/
`tsql`/`isql` sites `targets.rb:688,713,726,728,770,1124,1182,1184`), are the
same generic, class-agnostic bare-star formatter —
`%(SELECT "#{table}".* FROM "#{table}" WHERE ...)` — with no
`default_projection`-style narrowing and no awareness of `show_profile_info`.
Separately, `symbolic_instance` (`concolic_targets.rb:632-652`) builds a
mock's `attrs` from `klass.columns_hash` — **all physical columns,
unconditionally** — so a mocked `Profile` always carries `bio`/`gender`/
`birthday`/`location` in `attrs` regardless of which site produced it, and
`obj.define_singleton_method(col) { attrs[col] }` (`concolic_targets.rb:645`)
means `.bio` etc. read straight from that hash.

This has a specific, checked consequence for `ActiveRecord::Base#reload`
(`targets.rb:1237-1289`, a real `declare_target` — not a no-op — that mints a
genuine `SELECT "#{table}".* FROM "#{table}" WHERE "#{table}"."#{pk}" = ...`
note keyed to whichever class actually calls it): a **singleton** method
defined via `define_singleton_method` always wins Ruby's method-resolution
order over a method the class defines with `define_method` — so
`lazy_columns`' generated `bio` accessor (a class-level `define_method`,
installed only under `Rails.env.include?("mod")`) is **shadowed** by
`symbolic_instance`'s per-instance `bio` reader and is never actually invoked,
so `self.reload` inside it never fires **for a mocked `Profile`**. The one
`.reload` call this endpoint's corpus does exercise runs on **`Person`**, not
`Profile`: the comment at `targets.rb:1237-1240` documents it as
`Person#name -> fix_profile -> (Discovery wall) -> reload` — the federation
re-fetch-after-save path, unrelated to lazy columns.

Put together: because we drive under **plain `RAILS_ENV=concolic`** (not
`concolic_mod`), `Profile.lazy_load` never installs its `default_scope` in
the *real* app either, so every real `profiles` read the app issues today
really is 18-column-wide — Q1 and Q2 are indistinguishable in our current
corpus not because the mock special-cases anything, but because **under this
env there is nothing to distinguish them by**: the bare-star mock and the
real (mis-configured relative to the reference) app both emit `profiles.*`
uniformly. That is exactly RC-1's root cause, present at this endpoint too,
not absent from it.

### 8.4 Why "0 diff" is real but doesn't mean "no defect"

`bench.grade`'s `disclosure_precision` compares **sets** of `(table,column)`
pairs (`sqlnorm.expand_star`), unioned across every statement in the policy —
not per-statement. Our policy's `profiles` reads are uniformly wide (18
cols, per §8.3); their union is the full 18-column set. The reference's union
is *also* the full 18-column set, because it has at least one wide shape
(lines 93/101, from the genuinely-gated Q2) even though 16 of its 18 shapes
are narrow. Two sets that both equal "all 18 columns" diff to zero, **no
matter how many of the 16 narrow-should-be shapes our side gets wrong**,
because the wide shape's presence — on both sides — already saturates the
set. This is a proof, not a supposition: it is the direct algebraic
consequence of §8.1's shape count (16 narrow + 2 wide on the reference side)
and §8.3's uniformity (18-wide everywhere on our side).

### 8.5 Verdict: real defect, wrong fix available, no redrive done

This is **not** the people_show pattern. people_show is exempt because the
`reload`/`private_hash` path *dominates* its explored space (798/800 dumps)
— narrowing would be wrong almost everywhere there, so leaving it wide is the
right call regardless of the accessor-shadowing structural fact. Here the
reference's own shape count says the opposite: Q2 (wide) is the rare, tightly
gated exception (2/18 shapes, one notification type, one format, one further
boolean gate) and Q1 (narrow) is the common case (16/18 shapes, six
notification types). By the same standard applied to comments_index/
conversations_index/people_stream (their `profiles` reads should narrow
because their references show 0 wide shapes), notifications_index's 16 narrow
shapes are being genuinely over-disclosed today — a real RC-1-class defect —
it is just invisible to `bench.grade` per §8.4.

**But the standard fix does not apply cleanly.** Replicating the
`default_projection(klass)` helper (§4) at this endpoint's note-emission
sites would narrow **every** `profiles` note uniformly, including the two
Q2 shapes — because, per §8.3, there is no existing signal at note-synthesis
time (no working `reload` trigger, no `show_profile_info`-gated branch) that
distinguishes them. That would flip today's coincidentally-zero diff into a
**real recall regression**: bio/gender/birthday/location would disappear from
the policy's `profiles` pairs entirely, and lines 93/101 would go unmatched.
This is the concrete, mechanism-level confirmation of the caution already on
record in §7 item 5 — that caution was correct in outcome, not fully in its
stated reasoning (it read as "this endpoint doesn't need it," when the more
precise statement is "this endpoint needs a *different, harder* fix than the
other three, and doing the easy one would make it worse").

A correct fix would have to *add* a genuinely new, separately-gated statement
— wiring the already-real `show_profile_info` decision (§8.2) through to a
new SQL-note emission at (or near) the `disp_cols = %w[bio location] &
attrs.keys` site (`targets.rb:1627-1655`, which is precisely where the app's
real code already touches `bio`/`location` but today mints no note of its
own) — while narrowing the generic sites everywhere else. That is materially
more invasive than a projection-narrowing helper: it introduces a new emitted
statement conditioned on a decision whose PC-tree footprint hasn't been
audited (whether `show_profile_info`'s underlying comparisons already appear
as PCs elsewhere, whether adding a note here would change the tree rather
than just the SQL text), and any redrive of it could not lean on the cheap
"per-seed PC-signature multiset unchanged" proof the other three endpoints
used — it would need its own, harder branching-safety argument from scratch.

Given (a) the corpus size (313,977 dumps, largest of the four), (b) the box
was carrying a live 4-JVM-plus coverage-report load for
`comments_index` throughout this investigation (`uptime` load average ~49,
`free -h` ~25-29G available — headroom existed, but a redrive of this size
next to that load was not attempted), and (c) the fix itself needs design
work this task's scope doesn't cover, **no change was made to
`notifications_index/concolic_targets.rb` or `targets.rb`, and no redrive was
run.** The existing corpus, extraction, and `bench.grade` numbers for
notifications_index are unchanged (`disclosure_precision` stays at 0.9432 /
0.9483 as already on record above).

**Recommendation for a future task:** scope "notifications_index Q2
modelling" as its own follow-up, separate from RC-1's replication pattern —
narrow the generic sites via `default_projection`, add a new gated wide note
at the private_hash boundary, and treat its branching-safety proof as an
open design question rather than an assumed given.
