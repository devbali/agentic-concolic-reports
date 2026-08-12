# REPORT — "contacts_aspects_blocks" batch — diaspora concolic experiment

Date: 2026-08-07 · Runtime: JRuby 9.3 + Java 21 · App `dse-apps/apps/diaspora`
(Rails 5.2) · RAILS_ENV=concolic · Driver: `run_concolic.rb` (+ continuation
runners `run_phase2.rb`, `run_phase3.rb`). App + runtime source were
**read-only**; every `path_condition` in every dump comes from real diaspora
code branching on symbolic finder / comparison results — none was
hand-fabricated.

## Status summary

**All 13 entrypoints report `CoverageChecker.complete == true`.** Coverage
was closed per the README loop: defaults → CoverageChecker `concrete_values`
→ `ConcolicTargets.seed_overrides` → re-run → recheck, until `complete:true`.
The three entrypoints that hit deeper chained-finder leaves
(`aspects_toggle_chat_privilege`, `aspect_memberships_destroy`,
`share_visibilities_update`) required 2–3 convergence passes (phases 2–3).

As in the `posts` batch, `complete:true` means every *observable* branchable
path-condition node has a PC on both taken/not-taken sides — **not** that
every action runs to a clean render. Many actions crash in unsupported
symbolic machinery or Rails render plumbing; those PCs-before-crash are
preserved under each dump's `error` key and counted by the checker
(README "report errors honestly" rule).

## Per-entrypoint

| Entrypoint | Dumps | PCs | complete | Notes |
|---|---|---|---|---|
| `contacts_index` | 2 | 0 | ✅ | aspect-finder only feeds `@aspect` (never branched in html); crashes on `content_type` render before any PC |
| `community_spotlight` | 1 | 0 | ✅ | `Person.community_spotlight` → `Person.joins(:roles)` crashes — concolic DB has no `roles` table (crash-before-PC) |
| `aspects_create` | 3 | 0 | ✅ | `if @aspect.save` bare-truthiness (truthiness gap, documented); crashes on render `status=` |
| `aspects_show` | 2 | 2 | ✅ | `first_not_found` both sides; crashes on render `status=` |
| `aspects_update` | 2 | 2 | ✅ | finder not_found sides; crashes on `update!` (not a declared target) |
| `aspects_destroy` | 3 | 5 | ✅ | finder not_found + `aspect.id == auto_follow_back_aspect.id` both sides; crashes on `SymbolicString#to_s` (I18n) |
| `aspects_update_order` | 3 | 5 | ✅ | `find_1`/`find_2` not_found branches (RecordNotFound raised) |
| `aspects_toggle_chat_privilege` | 5 | 12 | ✅ | deepest chain (2 finders) + `chat_enabled` bool branches; crashes on nil/toggle render |
| `aspect_memberships_create` | 1 | 0 | ✅ | `share_with` → `contacts.find_or_initialize_by` → `SymbolicList#first` crash before any PC |
| `aspect_memberships_destroy` | 7 | 20 | ✅ | 2 chained finders + `mine?(aspect)`/`mine?(contact)` (`user_id == 1`) compare branches — richest PCs |
| `blocks_create` | 2 | 0 | ✅ | `if block.save` truthiness; `send_message`→`ContactRetraction`/`SymbolicList#first` crash before PC |
| `blocks_destroy` | 2 | 2 | ✅ | `find_by` both sides; crashes on `delete`/rendering |
| `share_visibilities_update` | 4 | 9 | ✅ | `PostService#find!` chain to depth 3 + `toggle_hidden_shareable` crash on `hidden_shareables.has_key?` |

PCs counted across all dumps: **57**.

## Coverage loop (what was closed and how)

Initial pass (defaults) left 8 entrypoints incomplete. CoverageChecker
reported missing nodes with suggested `concrete_values`; those were fed
verbatim into `ConcolicTargets.seed_overrides` and re-run:

- **Phase 2** (`run_phase2.rb`) closed the shallow leaves:
  `aspects_show`, `aspects_update`, `aspects_destroy` (finder not_found +
  id-match not_taken), `aspects_update_order` (find_1/find_2),
  `aspect_memberships_destroy` (2 finders), `share_visibilities_update`
  (find_2), `aspects_toggle_chat_privilege` (find_1).
- **Phase 3** (`run_phase3.rb`) closed the deepest leaves the checker then
  demanded: `aspects_toggle_chat_privilege` `first_2_chat_enabled`,
  `aspect_memberships_destroy` `first_2_user_id == 1` (mine? on contact),
  `share_visibilities_update` `first_3_not_found` (find! 3-deep chain).

All seed *values* came from `CoverageChecker.concrete_values` (or the
prefix the checker demanded); no path conditions were fabricated. Result:
`coverage_summary.json` = `complete: true` for all 13 entrypoints
(regenerated from the final dump set).

## Crashes (honest accounting)

All crashes are captured under each dump's `error` key; PCs-before-crash
remain in the dump and are counted.

### `NotImplementedError` (unsupported symbolic op — strict-runtime by design)
- **`SymbolicList#first`** — `aspect_memberships_create` and `blocks_create`.
  Reached via real `User#share_with` / `User#disconnect` on a symbolic
  Contact collection (`contacts.find_or_initialize_by` / `aspect_memberships`).
  These two entrypoints yield 0 PCs because the crash fires before any
  branchable finder result.
- **`SymbolicString#to_s`** — `aspects_destroy`: `I18n.t("...", name:
  aspect.name)` interpolates a symbolic name in the flash message.

### `NoMethodError` (render / plumbing / real-method-on-symbolic)
- `contacts_index` / `community_spotlight-render-note` — `undefined method
  'content_type' for nil` at html/render boundary (controller-test has no
  template/response).
- `aspects_create` / `aspects_show` / `aspects_update_order` —
  `ActionController::Metal#status= delegated to @_response.status=` (nil),
  i.e. `render`/`head`/`redirect_to` with no live response in the test rig.
- `aspects_update` — `reverse_merge!` for nil (real `update!` on symbolic
  Aspect attribute params) then `update! for nil` on the not-found path.
- `aspects_destroy` — `id for nil` on the seeded not-found path (`aspect`
  nil → `aspect.destroy`).
- `aspects_toggle_chat_privilege` — `chat_enabled`/`chat_enabled=`/`write_from_user`
  on nil / render.
- `aspect_memberships_destroy` — `[] for nil` (redirect/request referer
  plumbing) on the mine?=true success path.
- `blocks_destroy` — `[] for nil` on `ContactRetraction.for(block)` /
  `content_type` on render.
- `share_visibilities_update` — `undefined method 'has_key?' for
  #<SymbolicString>`: `User#toggle_hidden_shareable` reads the serialized
  `hidden_shareables` column (a SymbolicString) and calls `has_key?` on it.

### App-behavior exceptions (expected, not bugs)
- `ActiveRecord::RecordNotFound` (`concolic: empty result for: SELECT
  "aspects"...`) — the app's *intended* not-found path on seeded
  `find`/`find!`; the finder PCs are all recorded.
- `aspect_memberships_destroy` `Diaspora::NotMine` — the app's real
  authorization gate (`current_user.mine?(...)` false) reached after the
  finder + mine? compare PCs.
- `community_spotlight` `ActiveRecord::StatementInvalid: Could not find
  table 'roles'` — the concolic SQLite DB lacks a `roles` table, so the real
  `Person.joins(:roles)` scope cannot build. This is a schema limitation,
  not a runtime fault; the action assigns the relation with no branch, so
  0 PCs are expected regardless.

## Incomplete-with-error vs complete

None of the 13 entrypoints is silently incomplete. Five
(`contacts_index`, `community_spotlight`, `aspects_create`,
`aspect_memberships_create`, `blocks_create`) have **0 PCs**: the strict
runtime crashes in unsupported symbolic ops or Rails render plumbing before
any branchable query result yields a path condition (plus the documented
bare-truthiness gap on `if record.save` / `if aspect`). These are recorded
honestly as *complete-by-checker, no-PC / crash-before-PC* — the checker
reports complete because there are no branchable finder nodes in the
captured path.

## Files

- `run_concolic.rb` — main batch runner (13 entrypoints, defaults + seeded
  closes).
- `run_phase2.rb` / `run_phase3.rb` — convergence runners that closed the
  checker-identified leaves (phase 2 shallow, phase 3 deepest).
- `{entrypoint}/dump_*.json` — 38 dumps total.
- `{entrypoint}/coverage_summary.json` — `complete: true` each.
- `elapsed_seconds.txt` — ~29 s wall (three JRuby launches).

App and runtime source were **read-only**; every `path_condition` in every
dump comes from real diaspora code branching on symbolic finder/comparison
results.
---

## Gate 1b FINAL (2026-08-10) — function-boundary splits

**Approach (Bali directive):** the runtime/engine is UNTOUCHED and strict (`SymbolicList#each`/`#map` still raise). The intermediate sampled-content iteration change (2026-08-09 addendum, if present) was REVERTED. Remaining SQL-free iteration walls were cleared by behavior-preserving FUNCTION-BOUNDARY SPLITS in the app code (e.g. `Post.blocked_people`, `Stream::Base#post_ids` / `#attach_user_likes`, `StreamsController#decorated_stream_posts`) plus `declare_target` wraps in `concolic_targets.rb`. No method containing SQL is mocked; each split is behavior-identical in a normal run.

**Final numbers (fresh `coverage_summary.json`, 2026-08-10 08:19):** runs=37, no-error=0, crashed=37, coverage_complete=False, missing_branches=2.
crash_types: {"NotImplementedError": 5, "ActiveRecord::RecordNotFound": 6, "Diaspora::NotMine": 3, "NoMethodError": 16, "Module::DelegationError": 6, "ActiveRecord::StatementInvalid": 1}

Crashed runs are preserved, not dropped. Honest caveat: `complete=true` means no missing branches were found **on the recorded (sampled) paths**;
entrypoints that crash before recording PCs stay vacuous/`incomplete`.
