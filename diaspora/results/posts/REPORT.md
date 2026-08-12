# REPORT — "posts" batch — diaspora concolic experiment

Date: 2026-08-07 · Runtime: JRuby 9.3 + Java 21 · App `dse-apps/apps/diaspora`
(Rails 5.2) · RAILS_ENV=concolic · Driver: `run_concolic.rb` (+ continuation
runners `run_phase4.rb`, `run_phase5.rb`).

## Status summary

**All 9 entrypoints report `CoverageChecker.complete == true`.** Coverage was
closed per README "Coverage loop (verified)": defaults → seed suggested
`concrete_values` → re-run → recheck. The deep chain not-found leaves
(`first_3_not_found` under prefix `first_1=True, first_2=True`) are genuinely
reachable and were closed with seeds (see "Coverage loop" below).

This does NOT mean every entrypoint runs to a clean render — see
**Crashes** below. Several actions crash deep in unsupported symbolic
machinery or Rails render plumbing; those PCs-before-crash are preserved
under each dump's `error` key *and* counted by CoverageChecker, per the
README's "report errors honestly" rule. Coverage is "complete" in the
checker's sense (every observed, branchable path-condition node on both
taken/not-taken sides has a PC), not "full app-path coverage."

## Per-entrypoint

| Entrypoint | Dumps | PCs (all dumps) | complete | Notes |
|---|---|---|---|---|
| `posts_show` | 7 | 16 | ✅ | finder chain (evil_query `post!`) closed to depth 3 + public? branches |
| `posts_oembed` | 6 | 15 | ✅ | finder chain closed; render crashes (see crashes) |
| `posts_mentionable` | 1 | 0 | ✅ | 0 PCs — no branchable query; crashes on render |
| `posts_destroy` | 5 | 12 | ✅ | finder chain closed; crashes in service/controller |
| `reshares_create` | 5 | 12 | ✅ | finder chain closed; crashes on `SymbolicInt#to_i` |
| `reshares_index` | 6 | 15 | ✅ | finder chain closed; crashes on render |
| `status_messages_new` | 3 | 5 | ✅ | person-finder + find_by branches; crashes on response |
| `status_messages_create` | 1 | 0 | ✅ | 0 PCs — crashes on `SymbolicInt#to_i` before any PC |
| `status_messages_bookmarklet` | 1 | 0 | ✅ | 0 PCs — crashes on gon/render before any PC |

PCs counted across all dumps: **75**.

## Coverage loop (what was closed and how)

Initial state: 5 entrypoints incomplete, each missing the deepest chain
not-found leaf. The finder target is `ActiveRecord::FinderMethods.first`
(intercepted at `concolic_targets.rb:116`, the `finder_mock` block; the
real call site is `lib/evil_query.rb` `post!`). The previously-run phase-2
`_deep` dumps seeded only the first 2 finders, producing `first_3_not_found
= False` under prefix `(1=True, 2=True)` — the `not_taken` side of the
leaf. The chain is **3 finders deep**, so:

- `run_phase4.rb` seeded `first_1..N_not_found = True` for N=3,4,5 →
  recorded `first_1=True, first_2=True, first_3=True` (the `taken` side).
  This closed **posts_show, posts_oembed, reshares_index**.
- `run_phase5.rb` seeded `first_1=True, first_2=True, first_3=False` →
  recorded `first_1=True, first_2=True, first_3=False` (the `not_taken`
  side under that exact prefix). This closed **posts_destroy,
  reshares_create** (initially `complete: False` was stale; recheck after
  the leaf run flips them to `True`).

All seed *values* came from `CoverageChecker`'s `concrete_values` (or the
prefix the checker demanded); no path conditions were hand-fabricated. Every
PC in every dump comes from app code branching on the symbolic finder result.

Result: `coverage_summary.json` = `complete: true` for all 9 entrypoints
(regenerated from the final dump set).

## Crashes (honest accounting)

All crashes are captured under each dump's `error` key; the PCs recorded
before the crash remain in that dump and are counted. Types:

### `NotImplementedError` (unsupported symbolic op — strict-runtime by design)
- **`SymbolicInt#hash`** — `posts_show` (all 4 base dumps).
  Source location app frame:
  `app/services/post_service.rb:71` `mark_comment_reshare_like_notifications_read`
  (post id is a symbolic `SymInt`, used as a Hash key while normalizing
  unread-notification state → `hash` on symbolic unsupported). Op: `hash`.
- **`SymbolicInt#to_i`** — `reshares_create` (all 3 base dumps) and
  `status_messages_create` (sole dump).
  Source: `src/ruby_runtime/int.rb:30` (`to_i`), reached deep in
  service logic (ReshareService / StatusMessageCreationService) where a
  symbolic count/id is coerced to an integer. App frame is beyond the
  captured trace boundary (only the runtime frame is captured). Op: `to_i`.
  These two entrypoints yield 0 or minimal PCs because the `to_i` fires
  before any branchable query in some paths.

### `NoMethodError` (render / plumbing on nil response — Rails controller-test boundary)
- `posts_oembed` — `undefined method 'to_hash' for nil:NilClass` at
  `app/controllers/posts_controller.rb:41` (`oembed`) — presenter/Html5
  rendering of the symbolic post hits nil.
- `posts_mentionable` — `undefined method 'content_type' for nil:NilClass`
  at `app/controllers/posts_controller.rb:45` (`mentionable`) — streaming
  render.
- `reshares_index` — `undefined method '[]' for nil:NilClass` at
  `app/services/reshare_service.rb:15` (`find_for_post`) /
  `app/controllers/reshares_controller.rb:16` (`index`).
- `posts_destroy` — `undefined method '[]' for nil:NilClass` at
  `app/services/post_service.rb:32` (`destroy`) /
  `app/controllers/posts_controller.rb:60` (`destroy`) — retraction path.
- `status_messages_new` (default) — `undefined method '[]' for nil:NilClass`
  at `app/controllers/status_messages_controller.rb:22` (`new`).
- `status_messages_bookmarklet` — `undefined method '[]=' for nil:NilClass`
  at `app/controllers/status_messages_controller.rb:42` (`bookmarklet`) —
  gon preload assignment on nil.

### `Module::DelegationError`
- `status_messages_new` (`noperson`) —
  `ActionController::Metal#status= delegated to @_response.status=, but
  @_response is nil` at `app/controllers/status_messages_controller.rb:31` —
  controller-test response plumbing when the seeded no-person branch calls
  render/redirect with no live `@_response`.

### `ActiveRecord::RecordNotFound` (app-behavior, not a bug)
- `posts_show`/`reshares_index`/`posts_destroy` chain3/4/5 dumps —
  `could not find a post with id 1 for user 1`. This is the app's *intended*
  not-found path on the seeded chain (`post!` raises); the `first_*` PCs are
  all still recorded. Expected and correct.

## Incomplete-with-error vs complete

None of the 9 entrypoints is silently incomplete. Three entrypoints
(`posts_mentionable`, `status_messages_create`, `status_messages_bookmarklet`)
have **0 PCs**: the strict runtime crashes in unsupported symbolic ops or
render plumbing before any branchable query result produces a path
condition. These are recorded honestly as *complete-by-checker, no-PC /
crash-before-PC* (see table "PCs = 0"). They are **not** marked complete in
a misleading "fully explored" sense; the checker reports complete because
there are simply no branchable finder nodes to cover in the captured path.

## Files

- `run_concolic.rb` — main batch runner (9 entrypoints, defaults + not-found
  + phase-2 deep runs).
- `run_phase4.rb` / `run_phase5.rb` — convergence runners that closed the
  remaining depth-3 chain leaves.
- `{entrypoint}/dump_*.json` — 35 dumps total.
- `{entrypoint}/coverage_summary.json` — `complete: true` each.

App and runtime source were **read-only**; every `path_condition` in every
dump comes from real diaspora code branching on symbolic finder results.
---

## Gate 1b FINAL (2026-08-10) — function-boundary splits

**Approach (Bali directive):** the runtime/engine is UNTOUCHED and strict (`SymbolicList#each`/`#map` still raise). The intermediate sampled-content iteration change (2026-08-09 addendum, if present) was REVERTED. Remaining SQL-free iteration walls were cleared by behavior-preserving FUNCTION-BOUNDARY SPLITS in the app code (e.g. `Post.blocked_people`, `Stream::Base#post_ids` / `#attach_user_likes`, `StreamsController#decorated_stream_posts`) plus `declare_target` wraps in `concolic_targets.rb`. No method containing SQL is mocked; each split is behavior-identical in a normal run.

**Final numbers (fresh `coverage_summary.json`, 2026-08-10 08:19):** runs=25, no-error=4, crashed=21, coverage_complete=True, missing_branches=0.
crash_types: {"NoMethodError": 10, "NotImplementedError": 8, "ActiveRecord::RecordNotFound": 2, "Module::DelegationError": 1}

Crashed runs are preserved, not dropped. Honest caveat: `complete=true` means no missing branches were found **on the recorded (sampled) paths**;
entrypoints that crash before recording PCs stay vacuous/`incomplete`.
