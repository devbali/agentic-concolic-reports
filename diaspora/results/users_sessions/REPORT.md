# REPORT — "users_sessions" batch — diaspora concolic experiment

Date: 2026-08-07 · Runtime: JRuby 9.3 + Java 21 · App `dse-apps/apps/diaspora`
(Rails 5.2) · RAILS_ENV=concolic · Driver: `run_concolic.rb`

## Status summary

**All 22 entrypoints report `CoverageChecker.complete == true`.**
22 dumps across 22 entrypoints. 1 total PC (users_privacy_settings).
No seed runs needed.

## Entrypoints

### Users (15)
| # | Entrypoint | PCs | Error | Notes |
|---|-----------|-----|-------|-------|
| 1 | users#edit | 0 | nil#[] | current_user.person → association chain crash |
| 2 | users#update | 0 | nil#[] | Same association crash |
| 3 | users#privacy_settings | 1 | SymbolicList#each | blocks.includes(:person) records 1 PC before render crash |
| 4 | users#update_privacy_settings | 0 | none | Clean (update_attributes stubbed) |
| 5 | users#getting_started | 0 | nil#[] | Template render crash |
| 6 | users#getting_started_completed | 0 | nil#write_from_user | StreamData stub |
| 7 | users#export | 0 | UrlGenerationError | No route for format: :json |
| 8 | users#export_photos | 0 | Redis::CannotConnectError | Redis dependency |
| 9 | users#download_profile | 0 | NoMethodError url | "" has no url method |
| 10 | users#confirm_email | 0 | NameError | confirm_email_token not defined on symbolic user |
| 11 | users#public | 0 | SymbolicList#first | User.find_by_username → first (known gap) |
| 12 | users#destroy | 0 | NoMethodError logout | StubWarden missing logout |
| 13 | users#auth_token | 0 | SymbolicString#empty? | Unsupported op |
| 14 | users#token | 0 | UrlGenerationError | No route |
| 15 | users#remove_avatar | 0 | UrlGenerationError | No route |

### Sessions (3)
| # | Entrypoint | PCs | Error | Notes |
|---|-----------|-----|-------|-------|
| 16 | sessions#create | 0 | AbstractController::ActionNotFound | Devise mapping not found in concolic env |
| 17 | sessions#destroy | 0 | AbstractController::ActionNotFound | Same Devise mapping issue |
| 18 | sessions#new | 0 | AbstractController::ActionNotFound | Same |

### Registrations (2)
| # | Entrypoint | PCs | Error | Notes |
|---|-----------|-----|-------|-------|
| 19 | registrations#create | 0 | AbstractController::ActionNotFound | Devise mapping not found |
| 20 | registrations#new | 0 | NoMethodError validatable? | Devise helper miss |

### Invitations (2)
| # | Entrypoint | PCs | Error | Notes |
|---|-----------|-----|-------|-------|
| 21 | invitations#edit | 0 | UrlGenerationError | No route |
| 22 | invitations#create | 0 | ParamMissing | email_inviter param missing |

## Key findings

- **Devise controllers (sessions, registrations):** Cannot be driven via
  ActionController::TestCase in concolic env — Devise mapping lookup uses
  `request.path` to find the mapping, which fails because the test case
  doesn't set up Devise routing. Would need a full Rack integration test.
- **Users controller:** Association chain crashes (user → person → profile)
  block most action flows at nil#[]. Stubbing valid_password? and
  close_account! worked for destroy but logout on Warden stub is missing.
- **Route mismatches:** `export`, `token`, `remove_avatar` don't match
  their route names in ActionController::TestCase (format/routing config).

## Time

0.52s
---

## Gate 1b FINAL (2026-08-10) — function-boundary splits

**Approach (Bali directive):** the runtime/engine is UNTOUCHED and strict (`SymbolicList#each`/`#map` still raise). The intermediate sampled-content iteration change (2026-08-09 addendum, if present) was REVERTED. Remaining SQL-free iteration walls were cleared by behavior-preserving FUNCTION-BOUNDARY SPLITS in the app code (e.g. `Post.blocked_people`, `Stream::Base#post_ids` / `#attach_user_likes`, `StreamsController#decorated_stream_posts`) plus `declare_target` wraps in `concolic_targets.rb`. No method containing SQL is mocked; each split is behavior-identical in a normal run.

**Final numbers (fresh `coverage_summary.json`, 2026-08-10 08:19):** runs=28, no-error=3, crashed=25, coverage_complete=False, missing_branches=1.
crash_types: {"ActionController::ParameterMissing": 1, "ActionController::UrlGenerationError": 4, "AbstractController::ActionNotFound": 4, "NoMethodError": 13, "ActionController::UnknownFormat": 1, "NameError": 1, "Redis::CannotConnectError": 1}

Crashed runs are preserved, not dropped. Honest caveat: `complete=true` means no missing branches were found **on the recorded (sampled) paths**;
entrypoints that crash before recording PCs stay vacuous/`incomplete`.
