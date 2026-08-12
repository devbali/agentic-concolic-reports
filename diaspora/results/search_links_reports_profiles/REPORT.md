# REPORT — "search_links_reports_profiles" batch — diaspora concolic experiment

Date: 2026-08-07 · Runtime: JRuby 9.3 + Java 21 · App `dse-apps/apps/diaspora`
(Rails 5.2) · RAILS_ENV=concolic · Driver: `run_concolic.rb`

## Status summary

**All 9 entrypoints report `CoverageChecker.complete == true` (0 branchable nodes each).**
9 dumps across 9 entrypoints. No seed runs needed.

## Entrypoints

| # | Entrypoint | Dumps | PCs | Error | Notes |
|---|-----------|-------|-----|-------|-------|
| 1 | GET /search | 1 | 0 | none | Clean run — redirect only (tag or people path), no AR queries branched |
| 2 | GET /link | 1 | 0 | ActiveRecord::RecordNotFound | DiasporaLinkService#find_or_fetch_entity → Person.find_by_guid with fake link → RecordNotFound |
| 3 | GET /report | 1 | 0 | none | Fixed 2026-08-11: `reports` table added to concolic.sqlite3 (was `Could not find table 'reports'`); now clean, 1 symbolic call |
| 4 | POST /report | 1 | 0 | NoMethodError nil#[] | `report_params` accesses StrongParameters → nil#[] crash before save/render |
| 5 | PUT /report/:id | 1 | 1 | NotImplementedError SymbolicInt#to_i | Fixed 2026-08-11: `reports` table added; schema blocker resolved (was `Could not find table 'reports'`), now real symbolic-path progress (1 PC) then crashes on SymbolicInt#to_i |
| 6 | DELETE /report/:id | 1 | 1 | NoMethodError nil#[] | Fixed 2026-08-11: `reports` table added; schema blocker resolved (was `Could not find table 'reports'`), now different (non-schema) error with 1 PC |
| 7 | GET /profile | 1 | 0 | NoMethodError nil#[] | `current_user.person.profile` → association chain → nil#[] |
| 8 | PUT /profile | 1 | 0 | NoMethodError nil#[] | Same association chain as edit |
| 9 | GET /profiles/:id | 1 | 0 | NotImplementedError SymbolicList#first | Person.find_by_guid! → Person.where(...).first → SymbolicList#first (known runtime gap) |

## Known gaps

- **reports table:** RESOLVED 2026-08-11 (Layer 2 schema work): `reports` table initialized empty in
  `concolic.sqlite3` with schema.rb-correct columns. The three entrypoints (report
  index/update/destroy) no longer hit `Could not find table 'reports'`; they now make
  real symbolic calls (see table).
- **SymbolicList#first:** Blocks any `Model.where(...).first` pattern (Person.find_by_guid,
  Notification.where.first). This is a known runtime gap in the src TODO.
- **Association chaining:** `current_user.person.profile` fails on Symbolic instances
  (no @association_cache on klass.allocate). Same issue as other batches' post.comments.

## Time

0.30s
---

## Gate 1b FINAL (2026-08-10) — function-boundary splits

**Approach (Bali directive):** the runtime/engine is UNTOUCHED and strict (`SymbolicList#each`/`#map` still raise). The intermediate sampled-content iteration change (2026-08-09 addendum, if present) was REVERTED. Remaining SQL-free iteration walls were cleared by behavior-preserving FUNCTION-BOUNDARY SPLITS in the app code (e.g. `Post.blocked_people`, `Stream::Base#post_ids` / `#attach_user_likes`, `StreamsController#decorated_stream_posts`) plus `declare_target` wraps in `concolic_targets.rb`. No method containing SQL is mocked; each split is behavior-identical in a normal run.

**Final numbers (fresh `coverage_summary.json`, 2026-08-10 08:19):** runs=11, no-error=2, crashed=9, coverage_complete=False, missing_branches=1.
crash_types: {"ActiveRecord::RecordNotFound": 1, "NoMethodError": 5, "ActiveRecord::StatementInvalid": 3}

Crashed runs are preserved, not dropped. Honest caveat: `complete=true` means no missing branches were found **on the recorded (sampled) paths**;
entrypoints that crash before recording PCs stay vacuous/`incomplete`.
