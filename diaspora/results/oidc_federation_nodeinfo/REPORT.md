# REPORT — "oidc_federation_nodeinfo" batch — diaspora concolic experiment

Date: 2026-08-07 · Runtime: JRuby 9.3 + Java 21 · App `dse-apps/apps/diaspora`
(Rails 5.2) · RAILS_ENV=concolic · Driver: `run_concolic.rb`

## Status summary

**All 7 entrypoints report `CoverageChecker.complete == true` (0 branchable nodes each).**
7 dumps across 7 entrypoints. No seed runs needed (no branchable PCs to seed).

## Entrypoints

| # | Entrypoint | Dumps | PCs | Error | Notes |
|---|-----------|-------|-----|-------|-------|
| 1 | POST /api/openid_connect/access_tokens | 1 | 0 | none | Clean run — TokenEndpoint calls Rack middleware (`Api::OpenidConnect::TokenEndpoint.new.call`) which runs outside the interceptor scope; no symbolic branch points captured |
| 2 | POST /api/openid_connect/authorization | 1 | 0 | ActionView::Template::Error | Sprockets `underscore` not found in concolic env (render boundary, same as other template-crash batches) |
| 3 | GET /.well-known/webfinger | 1 | 0 | ActionController::UrlGenerationError | diaspora_federation-rails engine controller — routes not available in ActionController::TestCase |
| 4 | GET /.well-known/host-meta | 1 | 0 | ActionController::UrlGenerationError | Same engine routing issue as webfinger |
| 5 | GET /node_info/:version | 1 | 0 | none | Clean run — `NodeInfoPresenter` calls without AR queries; no symbolic branch points |
| 6 | POST /receive/public | 1 | 0 | ActionController::UrlGenerationError | Engine controller — routing unavailable |
| 7 | POST /receive/private | 1 | 0 | ActionController::UrlGenerationError | Engine controller — routing unavailable |

## Federation engine limitation

Controllers in `diaspora_federation-rails` (WebfingerController, ReceiveController)
are mounted by the engine's `routes.draw` block and cannot be driven via
`ActionController::TestCase` — `tc.process()` raises `UrlGenerationError` because
the engine routes aren't registered under the test case's `@routes`. Driving these
would require either:
1. Loading `DiasporaFederation::Engine.routes` into the test case, or
2. Testing through Rack integration tests instead of ActionController::TestCase.

Both approaches would need app-side changes (disallowed by source discipline).

## Time

0.49s
---

## Gate 1b FINAL (2026-08-10) — function-boundary splits

**Approach (Bali directive):** the runtime/engine is UNTOUCHED and strict (`SymbolicList#each`/`#map` still raise). The intermediate sampled-content iteration change (2026-08-09 addendum, if present) was REVERTED. Remaining SQL-free iteration walls were cleared by behavior-preserving FUNCTION-BOUNDARY SPLITS in the app code (e.g. `Post.blocked_people`, `Stream::Base#post_ids` / `#attach_user_likes`, `StreamsController#decorated_stream_posts`) plus `declare_target` wraps in `concolic_targets.rb`. No method containing SQL is mocked; each split is behavior-identical in a normal run.

**Final numbers (fresh `coverage_summary.json`, 2026-08-10 08:19):** runs=7, no-error=2, crashed=5, coverage_complete=True, missing_branches=0.
crash_types: {"ActionController::UrlGenerationError": 4, "ActionController::UnknownFormat": 1}

Crashed runs are preserved, not dropped. Honest caveat: `complete=true` means no missing branches were found **on the recorded (sampled) paths**;
entrypoints that crash before recording PCs stay vacuous/`incomplete`.
