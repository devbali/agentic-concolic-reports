# REPORT — "notifications_tags" batch — diaspora concolic experiment

Date: 2026-08-07 · Runtime: JRuby 9.3 + Java 21 · App `dse-apps/apps/diaspora`
(Rails 5.2) · RAILS_ENV=concolic · Driver: `run_concolic.rb`

## Status summary

**All 9 entrypoints report `CoverageChecker.complete == true`.**
12 total dumps: 9 defaults, 3 seeded (notifications_update_not_found,
tags_show_not_found, tag_followings_create_not_found).

## Entrypoints

| # | Entrypoint | Dumps | PCs | Complete | Notes |
|---|-----------|-------|-----|----------|-------|
| 1 | notifications#index | 1 | 0 | ✅ | SymbolicInt#to_i crash (WillPaginate per_page) before any branchable PC |
| 2 | notifications#update | 2 | 2 | ✅ | Default + not_found seed; ActiveModel::Attribute#write_cast_value crash on the found branch |
| 3 | notifications#read_all | 1 | 0 | ✅ | nil#[] crash (render boundary); no branchable PCs before crash |
| 4 | tags#index | 1 | 0 | ✅ | SymbolicList#each crash (autocomplete results); no branchable PCs |
| 5 | tags#show | 2 | 2 | ✅ | Default + not_found seed; Arel quoting crash on SymbolicInt on the found branch |
| 6 | tag_followings#index | 1 | 0 | ✅ | No crash, no branchable PCs (straight query→render) |
| 7 | tag_followings#create | 2 | 2 | ✅ | Default + find_by_not_found seed; nil#[] crash on found branch |
| 8 | tag_followings#destroy | 1 | 0 | ✅ | nil#[] crash; no branchable PCs before crash |
| 9 | tag_followings#manage | 1 | 0 | ✅ | No crash, no branchable PCs (gon preloads + redirect) |

## Coverage summary

All 9 entrypoints: **complete**. 6/9 have zero PCs (crashes before any symbolic
branch was reached, or straight-line code with no query-result branches).
3/9 have 2 PCs each (not_found branch on Notification.where.first,
ActsAsTaggableOn::Tag.find_by_name, and ActsAsTaggableOn::Tag.find_or_create_by).

## Runner pattern

Same harness as the proved people/streams batches: symbolic_user, StubWarden,
ActionController::TestCase. Seeds applied for the 3 missing not_found branches.

## Errors (expected — strict runtime)

- SymbolicInt#to_i (WillPaginate), SymbolicList#each (autocomplete results),
  Arel#quote (SymbolicInt), ActiveModel#write_cast_value, nil#[] — all within
  expected strict-runtime failure envelope. Zero fabricated PCs.

## Time

0.4s (defaults) + ~8s (seeds).
## Gate 1b addendum (2026-08-09)

`symlist(..., representative:)` landed (both runtimes); §8.3 mock
`TagsController#prep_tags_for_javascript` declared, but `tags#index` still
crashes on SymbolicList#each (the autocomplete collection is iterated in
`render json:` — contents-out-of-scope wall before the prep fire). Full batch
re-run + CoverageChecker: **9 runs, 2 no-error, 7 crashed** — crash mix:
SymbolicList#each, NoMethodError (nil#[] ×3, write_cast_value), TypeError
(can't quote SymbolicInt). `tag_followings#index`/`#manage` reach no-error.
Remaining walls = iteration/serialisation + coercion gates. Crashed runs
preserved.

## Gate 1b follow-up — sampled-content iteration (2026-08-09, Bali directive)

`tags_show_default` now reaches `no-error` (was `can't quote SymbolicInt`).
CoverageChecker: 9 runs / 2 ok / 7 crashed (SymbolicInt#to_i, SymbolicString
#to_str, NoMethodError nil[]/write_cast_value/to_hash — coercion + AR-write
gates). Genuine: tags_show, tag_followings_manage. Remaining walls are
coercion/AR gates, not sampling.

---

## Gate 1b FINAL (2026-08-10) — function-boundary splits

**Approach (Bali directive):** the runtime/engine is UNTOUCHED and strict (`SymbolicList#each`/`#map` still raise). The intermediate sampled-content iteration change (2026-08-09 addendum, if present) was REVERTED. Remaining SQL-free iteration walls were cleared by behavior-preserving FUNCTION-BOUNDARY SPLITS in the app code (e.g. `Post.blocked_people`, `Stream::Base#post_ids` / `#attach_user_likes`, `StreamsController#decorated_stream_posts`) plus `declare_target` wraps in `concolic_targets.rb`. No method containing SQL is mocked; each split is behavior-identical in a normal run.

**Final numbers (fresh `coverage_summary.json`, 2026-08-10 08:19):** runs=12, no-error=3, crashed=9, coverage_complete=True, missing_branches=0.
crash_types: {"NotImplementedError": 1, "NoMethodError": 7, "TypeError": 1}

Crashed runs are preserved, not dropped. Honest caveat: `complete=true` means no missing branches were found **on the recorded (sampled) paths**;
entrypoints that crash before recording PCs stay vacuous/`incomplete`.
