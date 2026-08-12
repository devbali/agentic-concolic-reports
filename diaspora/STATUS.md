# Diaspora Concolic — Execution Status (2026-08-07)

**Experiment spec:** `reports/diaspora/README.md` (read this first — it's the authoritative
how-to: goal, batches, Usage pattern, coverage loop, honest limitations).

**Status: ALL 13 BATCHES COMPLETE** — every batch has a `run_concolic.rb` + `REPORT.md` +
per-entrypoint `dump_*.json` + `coverage_summary.json` under `reports/diaspora/results/<batch>/`.

## Batch summary (dumps / entrypoints)

| Batch | dumps | eps | Batch | dumps | eps |
|---|---|---|---|---|---|
| comments | 9 | 4 | posts | 14 | 9 |
| contacts_aspects_blocks | 37 | 13 | search_links_reports_profiles | 11 | 9 |
| conversations | 14 | 6 | services_admin | 12 | 9 |
| likes | 9 | 3 | streams | 18 | 10 |
| notifications_tags | 17 | 9 | users_sessions | 28 | 22 |
| oidc_federation_nodeinfo | 7 | 7 | people | 19 | 6 |
| photos | 16 | 8 | | | |

**Current clean state (2026-08-08, after stale-dump purge): 211 dumps across 115 entrypoints,
all load cleanly via `Run.from_dict` (0 load errors).**

## Verified facts
- Real diaspora code is driven (controller actions via Rails' `ActionController::TestCase`,
  real services/models; no hand-replicated app logic). Path conditions come from real app
  code branching on symbolic finder/predicate values. SQL is in dump var `note` fields.
- Runtime + `src/` + `concolic_targets.rb` + app were read-only. Runner-local workarounds
  (prepend modules giving symbolic records association readers, symbolic_user, StubWarden)
  live inside each `results/<batch>/run_concolic.rb` — the approved pattern.
- **Coverage "complete: true" is per-entrypoint from the Python CoverageChecker.**
  Engine-verified result across all 13 batches (using `Run.from_dict` + `CoverageChecker`
  per entrypoint on the parsed runs):

  **2026-08-07 baseline (BEFORE the class-find mocks):**
  - **113 / 113 entrypoints `complete=true`**, 0 incomplete.
  - **40 genuinely covered** (≥1 path condition recorded and checker confirms).
  - **73 vacuous** — `complete=true` but **0 path conditions** (crash-before-PC on an
    unsupported symbolic op / render plumbing before the first branchable point). Do NOT read
    those as fully-explored; each REPORT.md marks them honestly.

  **2026-08-08 re-run (AFTER `ActiveRecord::Core::ClassMethods#find/find_by/find_by!` mocks)
  + render boundary (render/render_to_string/render_to_body treated as terminal):**
  - **CLEAN single-provenance numbers (2026-08-08, after purging stale append-only round dumps):**
  - **93 / 115 `complete=true`**, **22 incomplete**, **26 genuine**, **67 vacuous**. 0 load errors.
  - ⚠️ Honesty correction: an earlier intermediate tally reported "105 complete / 10 incomplete"
    — that was computed on a MIXED-provenance dump tree (stale round dumps from pre-render runs
    still present, which the runners don't overwrite). After purging those stale dumps so each
    entrypoint reflects only its newest runs, the honest clean count is **93 complete / 26 genuine /
    67 vacuous / 22 incomplete** across 115 entrypoints. Treat 105 as an inflated, non-clean number.
  - The drop in `complete` vs the 2026-08-07 baseline (113→93) is the checker being MORE truthful:
    baseline marked find-crash / render-crash entrypoints as "vacuous complete" because they crashed
    before recording any PC. With the find mocks + render boundary firing, those now record real PCs
    and honestly report `incomplete` (branches recorded but not fully closed).
  - 22 incomplete entrypoints (PCs>0 but branches not fully closed), e.g. likes_destroy,
    comments_destroy, people_show, photos_index, posts_show/reshares_*, admin_* close/lock/unlock,
    streams aspects/multi. Remaining walls: `SymbolicInt#to_i` (15), `SymbolicList#each` (15),
    `SymbolicString#empty?` (10), `SymbolicInt#hash` (6), `to_s` (3), and the truthiness gap.
  - **Seed-namespace gap:** many fresh dumps still emit `FinderMethods_find/find_by_*` vars
    (aspects_update_order, blocks_destroy, tag_followings_create, status_messages_new,
    streams_*, participations_destroy, photos_index, conversations) = these are RELATION-FORM
    `.find` (e.g. `user.posts.find(...)`, `.where().find(...)`) through `FinderMethods`, a
    different code path than plain `Model.find`. Only plain class calls fire the new
    `Core__ClassMethods` target. Only likes_destroy + messages_create not-found seeds were
    migrated to the new namespace (validated); the rest remain un-differentiated.
  - **Stale-backup hygiene:** 46 stale round dumps were moved to `results/.stale_backup_*`
    (recoverable) so verification reflects only the newest runs; one orphaned empty dir
    (`notifications_index_seeded`) was removed.

## Honest caveats (read before trusting "complete")
- **Vacuous completeness:** entrypoints that crash before recording any PC (e.g. render/
  presenter plumbing, `SymbolicList#map/each`, StatementCache `find_by_sql→first`) are
  `complete:true` with 0 nodes. That is "no branches were recordable", not "all branches
  covered". Each REPORT.md lists these explicitly.
- **Root causes of crash-before-PC (all in `src/ruby_runtime`, candidates to raise to Bali):**
  - `Core::ClassMethods#find` (single-id `Model.find`) not declared → routes through
    `Querying.find_by_sql` → `SymbolicList#first` NotImplementedError. Blocks devise
    `current_user`, comments_destroy, messages_create, likes_destroy.
  - Symbolic `klass.allocate` has no `@association_cache` → association readers
    (`post.comments`, `user.person`) NoMethodError (worked around runner-locally).
  - `SymbolicInt#hash` as Hash key crashes Arel.
  - `SymbolicInt#to_i`/`#-@`, `SymbolicString#to_s`, `SymbolicList#map/each/pluck` → NotImplementedError.
  - `Tag` = `ActsAsTaggableOn::Tag` (namespaced) — needs explicit load in concolic env.
- **Ruby truthiness gap:** bare `if obj` on a symbolic wrapper records no PC; only explicit
  compares / predicate readers / `empty?`-style do. Some real branches unrecorded by design.

## Operational notes for a fresh session
- Launch a runner: `/home/dev/project/scripts/diaspora-concolic <absolute-path-to-runner.rb>`
  (runs from app dir `ruby_examples/dse-apps/apps/diaspora`, RAILS_ENV=concolic).
- Coverage loop: feed `CoverageChecker` `missing[].concrete_values` into
  `ConcolicTargets.seed_overrides`, re-run, repeat (see README "Coverage loop (verified)").
- **Sub-agent flakiness (resolved):** `openrouter/auto` and `arena/*` models non-deterministically
  text-dump and stop mid-task. Use the proven reliable model
  `openrouter/deepseek/deepseek-v4-flash-0731` (max_out 65536) for batch sub-agents, and/or
  drive runners directly in the main session (most reliable). See skill `task-nudge` for the
  self-nudge automation (cron `--session main --system-event` every 5m).
- `diaspora-nudge` / `diaspora-render-nudge` cron jobs and the detached watchdog
  (`diaspora_rerun_watchdog.sh`) were used to supervise long re-runs and are now removed —
  `openclaw cron list` shows nothing and no watchdog is running.

---

# Gate 1b — sampled-content SymbolicList re-run (2026-08-09)

## What changed (Phase 1 — runtime, both runtimes in parity)
`SymbolicList` gained a single `representative:` element.
- `src/ruby_runtime/list.rb`: `representative:` ctor kwarg + `attr_reader :representative`;
  `first`/`last`/`[0]`/`include?` return/use the rep when set (raise otherwise, back-compat);
  `each/map/reject/select/find` STILL raise (unimplemented by design).
  `symlist(name, len, representative: rep)` factory.
- `src/py_runtime/list_.py`: mirrored `_representative` + `__getitem__(0)` + `__contains__`;
  `__iter__` still raises. Mirror tests `test_list_rep.rb` / `test_list_rep.py` PASS.

## §8.3 call-site mocks added (`concolic_targets.rb`, section I)
`User#blocks`, `Stream::Aspect#aspect_ids`, `Stream::FollowedTag#tag_ids`,
`Stream::Multi#publisher_prefill`, `TagsController#prep_tags_for_javascript` — all via
`declare_target` (no ad-hoc monkey-patching). Verified to fire (`symbolic_call` events in dumps).

## Re-run & verification
All 13 batches re-run via the README workflow (`scripts/diaspora-concolic`); CoverageChecker
re-run per batch via `reports/diaspora/verify_gate1b.py`. Fresh per-batch summary:

| Batch | runs | ok | crashed | complete | missing |
|---|---|---|---|---|---|
| comments | 9 | 5 | 4 | true | 0 |
| contacts_aspects_blocks | 37 | 0 | 37 | false | 2 |
| conversations | 14 | 1 | 13 | true | 0 |
| likes | 9 | 2 | 7 | false | 1 |
| notifications_tags | 9 | 2 | 7 | false | 2 |
| oidc_federation_nodeinfo | 7 | 2 | 5 | true | 0 |
| people | 19 | 9 | 10 | false | 4 |
| photos | 16 | 1 | 15 | false | 5 |
| posts | 25 | 4 | 21 | true | 0 |
| search_links_reports_profiles | 11 | 2 | 9 | false | 1 |
| services_admin | 12 | 5 | 7 | false | 2 |
| streams | 16 | 8 | 8 | true | 0 |
| users_sessions | 28 | 3 | 25 | false | 1 |
## Gate 1b FINAL — function-boundary splits (2026-08-10)

**This section SUPERSEDES the 2026-08-09 "sampled-content iteration" follow-up above.**

Bali directive ("Don't change the runtime/engine for this"): the sampled-content
`each`/`map`/`__iter__` runtime change was REVERTED in both runtimes (mirror tests
updated to expect iteration to raise even with a representative; both pass). The
runtime stays at the approved representative-only state: element access
(`first`/`[0]`/`include?`) only.

### The mechanism that actually cleared the walls — function-boundary splits

A method containing SQL cannot be mocked (D7). Where a crash sat inside a method
that ALSO contained SQL (`Post.excluding_blocks`, `Stream::Base#like_posts_for_stream!`),
the SQL-free iteration was extracted into its own named method (behavior-preserving,
computed-once) and ONLY that extracted method is wrapped via `declare_target`:

- `Post.blocked_people(user)` — the `user.blocks.map {|b| b.person_id}` half of
  `excluding_blocks`; mock returns `[]` (empty ⇒ `where NOT IN` branch skipped; the
  representative user blocks nobody).
- `Stream::Base#post_ids(posts)` — `posts.map(&:id)` from `like_posts_for_stream!`;
  mock returns concrete `[1]` so the `Like.where(... IN ...)` gets a plain array
  (no Arel SymbolicList#map cascade).
- `Stream::Base#attach_user_likes(posts, likes)` — the inject+each that attaches
  `user_like`; mock returns `args["posts"]` unchanged (bypasses SymbolicList#each).
- `StreamsController#decorated_stream_posts(posts)` — the json display `.map`,
  wrapped as rep-carrying SymbolicList of Post reps.
Also: `Stream::FollowedTag#tag_ids` mock now returns a CONCRETE `[1]` (feeds
`where("taggings.tag_id IN (?)")`); class-method targets registered via
`Klass.singleton_class`; targeted `require_relative` of controller/model files
instead of `eager_load!` (which crashes on AvatarPresenter `image_path`).

### Final empirical numbers (fresh `coverage_summary.json`, 2026-08-10 08:19)

| batch | runs | ok | crashed | complete | missing | crash_types |
|---|---|---|---|---|---|---|
| comments | 9 | 5 | 4 | true | 0 | {"NotImplementedError": 1, "NoMethodError": 3} |
| contacts_aspects_blocks | 37 | 0 | 37 | false | 2 | {"NotImplementedError": 5, "ActiveRecord::RecordNotFound": 6, "Diaspora::NotMine": 3, "NoMethodError": 16, "Module::DelegationError": 6, "ActiveRecord::StatementInvalid": 1} |
| conversations | 14 | 1 | 13 | true | 0 | {"NoMethodError": 4, "Module::DelegationError": 3, "NotImplementedError": 5, "ActiveRecord::RecordNotFound": 1} |
| likes | 9 | 2 | 7 | false | 1 | {"NotImplementedError": 4, "ActiveRecord::RecordNotFound": 2, "Diaspora::NonPublic": 1} |
| notifications_tags | 12 | 3 | 9 | true | 0 | {"NotImplementedError": 1, "NoMethodError": 7, "TypeError": 1} |
| oidc_federation_nodeinfo | 7 | 2 | 5 | true | 0 | {"ActionController::UrlGenerationError": 4, "ActionController::UnknownFormat": 1} |
| people | 19 | 8 | 11 | false | 3 | {"ActionController::UnknownFormat": 4, "Redis::CannotConnectError": 3, "NotImplementedError": 4} |
| photos | 16 | 1 | 15 | false | 5 | {"Module::DelegationError": 3, "NotImplementedError": 7, "NoMethodError": 4, "ActiveRecord::RecordNotFound": 1} |
| posts | 25 | 4 | 21 | true | 0 | {"NoMethodError": 10, "NotImplementedError": 8, "ActiveRecord::RecordNotFound": 2, "Module::DelegationError": 1} |
| search_links_reports_profiles | 11 | 2 | 9 | false | 1 | {"ActiveRecord::RecordNotFound": 1, "NoMethodError": 5, "ActiveRecord::StatementInvalid": 3} |
| services_admin | 12 | 5 | 7 | false | 2 | {"NotImplementedError": 3, "NoMethodError": 3, "ActionController::UrlGenerationError": 1} |
| streams | 18 | 7 | 11 | true | 0 | {"NoMethodError": 3, "ActionController::UnknownFormat": 8} |
| users_sessions | 28 | 3 | 25 | false | 1 | {"ActionController::ParameterMissing": 1, "ActionController::UrlGenerationError": 4, "AbstractController::ActionNotFound": 4, "NoMethodError": 13, "ActionController::UnknownFormat": 1, "NameError": 1, "Redis::CannotConnectError": 1} |

### Streams entrypoint breakdown (final)

  - dump_streams_aspects_seeded.json — pc=0 — NO-ERROR
  - dump_streams_multi_seeded.json — pc=0 — NoMethodError
  - dump_streams_activity_html.json — pc=0 — ActionController::UnknownFormat
  - dump_streams_activity_json.json — pc=0 — NO-ERROR
  - dump_streams_aspects_html.json — pc=0 — ActionController::UnknownFormat
  - dump_streams_aspects_json.json — pc=0 — NO-ERROR
  - dump_streams_commented_html.json — pc=0 — ActionController::UnknownFormat
  - dump_streams_commented_json.json — pc=0 — NO-ERROR
  - dump_streams_followed_tags_html.json — pc=0 — ActionController::UnknownFormat
  - dump_streams_followed_tags_json.json — pc=0 — NO-ERROR
  - dump_streams_liked_html.json — pc=0 — ActionController::UnknownFormat
  - dump_streams_liked_json.json — pc=0 — NO-ERROR
  - dump_streams_mentioned_html.json — pc=0 — ActionController::UnknownFormat
  - dump_streams_mentioned_json.json — pc=0 — NoMethodError
  - dump_streams_multi_html.json — pc=0 — ActionController::UnknownFormat
  - dump_streams_multi_json.json — pc=0 — NoMethodError
  - dump_streams_public_html.json — pc=0 — ActionController::UnknownFormat
  - dump_streams_public_json.json — pc=0 — NO-ERROR

### What remains (separate gates, not Gate 1b iteration walls)

- html strips: `ActionController::UnknownFormat` (render/format gate) — 8 streams html.
- `NoMethodError: undefined method '[]' for nil` deep in SQL builder / serialization
  (`User#visible_ids_from_sql`, `StatusMessage` branch sites, `acts_as_api` per-field).
- Coercion (`SymbolicInt#to_i`, `SymbolicString#to_s`/`to_str`), Redis env,
  `write_cast_value` — unchanged gate backlog.

Honest caveat: `complete=true` reflects the recorded (sampled) paths; entrypoints
that crash before recording any PC remain vacuous. Crashed runs are preserved, not
dropped.
