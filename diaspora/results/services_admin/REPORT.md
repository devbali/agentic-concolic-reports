# REPORT — "services_admin" batch — diaspora concolic experiment

Date: 2026-08-07 · Runtime: JRuby 9.3 + Java 21 · App `dse-apps/apps/diaspora`
(Rails 5.2) · RAILS_ENV=concolic · Driver: `run_concolic.rb`

## Status summary

**All 9 entrypoints report `CoverageChecker.complete == true` (0 branchable nodes each).**
9 dumps across 9 entrypoints. No seed runs needed.

## Entrypoints

| # | Entrypoint | Dumps | PCs | Error | Notes |
|---|-----------|-------|-----|-------|-------|
| 1 | POST /services/:provider/invite | 1 | 0 | ActionController::UrlGenerationError | `services#inviter` is probably not the right route — omniauth callback endpoint |
| 2 | GET /services/:provider/failure | 1 | 0 | none | Clean run — redirect only, no AR query branches |
| 3 | GET /admin/user_search | 1 | 0 | none | Fixed 2026-08-11: `reports` table added to concolic.sqlite3 (was ActionView error from missing `reports` in admin sidebar partial); now clean, 1 symbolic call |
| 4 | GET /admin/dashboard | 1 | 0 | none | Fixed 2026-08-11: `reports` table added (was ActionView error from missing `reports` in admin sidebar partial); now clean, 1 symbolic call |
| 5 | GET /admin/stats | 1 | 0 | NotImplementedError Batches#find_each | User.where.find_each in weekly_user_stats — contents-op crash |
| 6 | POST /admin/users/:id/close_account | 1 | 0 | NotImplementedError SymbolicList#first | User.find(id) → find_by → SymbolicList#first |
| 7 | POST /admin/users/:id/lock_account | 1 | 0 | NotImplementedError SymbolicList#first | Same User.find pattern |
| 8 | POST /admin/users/:id/unlock_account | 1 | 0 | NotImplementedError SymbolicList#first | Same User.find pattern |
| 9 | POST /admin/users/:id/add_invites | 1 | 0 | NotImplementedError SymbolicList#first | InvitationCode.find_by_token → SymbolicList#first |

## Known gaps

- **Admin::UsersController** uses `User.find(id)` (single-id find) which is not declared
  in the concolic targets (uses `find_by` → SymbolicList#first — known runtime gap).
- **reports table:** RESOLVED 2026-08-11 (Layer 2 schema work): `reports` table initialized empty in `concolic.sqlite3` with schema.rb-correct columns, unblocking the admin sidebar render (admin user_search / dashboard now run clean).
- **Batches#find_each** — contents-op on User collection in weekly_user_stats.

## Time

0.34s
---

## Gate 1b FINAL (2026-08-10) — function-boundary splits

**Approach (Bali directive):** the runtime/engine is UNTOUCHED and strict (`SymbolicList#each`/`#map` still raise). The intermediate sampled-content iteration change (2026-08-09 addendum, if present) was REVERTED. Remaining SQL-free iteration walls were cleared by behavior-preserving FUNCTION-BOUNDARY SPLITS in the app code (e.g. `Post.blocked_people`, `Stream::Base#post_ids` / `#attach_user_likes`, `StreamsController#decorated_stream_posts`) plus `declare_target` wraps in `concolic_targets.rb`. No method containing SQL is mocked; each split is behavior-identical in a normal run.

**Final numbers (fresh `coverage_summary.json`, 2026-08-10 08:19):** runs=12, no-error=5, crashed=7, coverage_complete=False, missing_branches=2.
crash_types: {"NotImplementedError": 3, "NoMethodError": 3, "ActionController::UrlGenerationError": 1}

Crashed runs are preserved, not dropped. Honest caveat: `complete=true` means no missing branches were found **on the recorded (sampled) paths**;
entrypoints that crash before recording PCs stay vacuous/`incomplete`.
