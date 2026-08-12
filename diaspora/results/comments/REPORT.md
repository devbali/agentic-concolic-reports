# Batch report: `comments`

Drives the four `comments` entrypoints through the **real** diaspora
controller→service code (`CommentsController` → `CommentService` /
`PostService` / `User::Querying` / `Person#owns?` / AR finders). No app or
source code was modified; path conditions come only from real app branches on
symbolic query results. Runner: `run_concolic.rb` (writes
`results/comments/{entrypoint}/dump_*.json`). Coverage loop closed via the
`concolic_engine` `CoverageChecker` using `results/comments/seeds.json`.

## Per-entrypoint summary

| Entrypoint | dumps | PCs | symbolic calls | coverage | runs w/ crash |
|---|---|---|---|---|---|
| comments_create  | 4 | 9 | 7 | Complete (3 nodes) | 2 |
| comments_index   | 3 | 5 | 3 | Complete (2 nodes) | 1 |
| comments_new     | 1 | 0 | 0 | Complete (0 nodes, vacuous) | 0 |
| comments_destroy | 1 | 0 | 1 | Complete (0 nodes, vacuous) | 1 |

`CoverageChecker` returns `complete: true` for all four. For `comments_new`
and `comments_destroy` this is **vacuous** (0 branch nodes), because those
entrypoints record no path conditions — see findings below.

## Findings (all are honest limitations, not hidden failures)

### 1. `ActiveRecord::Core::ClassMethods#find` is not intercepted — blocks all `.find(id)` paths
`concolic_targets.rb` declares the single-record finders on
`ActiveRecord::FinderMethods`, but Rails 5.2 defines the single-id fast path
`Model.find(id)` on **`ActiveRecord::Core::ClassMethods`** (it delegates to a
cached `find_by_sql` statement). That cached call hits the declared
`Querying.find_by_sql` target, which returns a **length-only SymbolicList**,
and the statement cache then calls `.first` on it → `NotImplementedError:
SymbolicList#first`. 

Consequence: any app code that calls `.find(id)` (devise `current_user`,
`Comment.find`, `Post.find`, …) crashes at the framework layer before the
app's own branch. This blocks **comments_destroy** entirely (`Comment.find`)
and forces the runner's authenticated-user lookup to use `User.first`
(`FinderMethods#first`, which *is* intercepted) — see `run_concolic.rb`,
`current_user` doc comment.

### 2. Symbolic instance (`klass.allocate`) lacks ActiveRecord association state
The finder mock returns `klass.allocate`. Any association navigation on the
symbolic record (`post.comments` in `comments_index`; `user.person` /
`@querent.person` in the create path) hits a missing `@association_cache`
(`association_instance_get` on nil → `NoMethodError`). So the
comments-index collection materialization (`post.comments.for_a_stream` →
`CommentPresenter.as_collection`) is not reachable with this mock: the two
CPU branches are covered, then it crashes.

### 3. SymbolicInt as a Hash key crashes Arel (`where(user_id: <sym>)`)
`EvilQuery::VisibleShareableById` builds `where(share_visibilities:
{user_id: @querent.id})` where `@querent` is the symbolic User → `SymbolicInt`
reaches Arel's bind-param hash → `SymbolicInt#hash` NotImplementedError. This
caps the authenticated `comments_create` path at the current-user lookup (1
PC). Closing the loop via the user-not-found branch routes through the
anonymous `PostService#find_public!` path instead, which covers the
comment-domain branches (`Post.where(...).first` not_found + `post.public?`),
then crashes at `nil.comment!` (`NoMethodError`) because the owner is
unavailable.

## Per-entrypoint detail

### comments_index (`GET /posts/:id/comments` → comments#index, no auth)
Real code: `CommentService#find_for_post` → `PostService#find!` (anonymous) →
`Post.where(post_key => id).first.tap { raise RecordNotFound unless post;
raise NonPublic unless post.public? }`. 
- Branches covered: `FinderMethods.first` not_found (drives `RecordNotFound`)
  and `post.public?` (drives `Diaspora::NonPublic`). 5 PCs across 3 dumps.
- R2 (`public=true`) crashes at `post.comments` (finding #2). Reported in
  `coverage_summary.json` (`runs_with_errors`).

### comments_create (`POST /posts/:id/comments` → comments#create, auth)
Real code: `CommentService#create` → `post_service.find!` +
`user.comment!(post, text)`.
- R0 (default, authenticated): `User.first` PC then crash on EvilQuery SQL
  (finding #3).
- R1–R3 (user-lookup not found → anonymous `find_public!`): cover
  `Post.where(...).first` not_found and `post.public?` (finding #1/#2
  interplay), then crash at `nil.comment!`. 9 PCs across 4 dumps (some
  counted twice across paths).

### comments_new (`GET /posts/:id/comments/new` → comments#new, auth)
`respond_to { format.mobile { render layout: false } }` — a pure render,
no query and no symbolic branch. 0 PCs, 0 symbolic calls. Coverage
trivially "complete" (no branches exist). No crash.

### comments_destroy (`DELETE /comments/:id` → comments#destroy, auth)
Real code: `CommentService#destroy` → `Comment.find(id)` then
`user.owns?(comment) || user.owns?(comment.parent)` →
`user.retract(comment)`.
- Blocked at finding #1: `Comment.find` → cached `find_by_sql` → SymbolicList
  `.first` NotImplementedError before any app PC. The real
  `Person#owns?` (`id == author_id`) and `||` branches are unreachable in
  this framework configuration. Coverage "complete" is vacuous (0 nodes).
  Honest report: **no path conditions** for this entrypoint under the current
  shared `concolic_targets`.

## Suggested upstream fixes (raise to Bali; not made here)
1. Add a `ActiveRecord::Core::ClassMethods#find` target (or
   `StatementCache#execute`) so single-id `find` returns a symbolic instance
   instead of funnelling through the length-only `find_by_sql` mock.
2. Initialize `@association_cache` (empty hash) on the `symbolic_instance`
   so `post.comments` / `user.person` navigate to symbolic relations instead
   of a `NoMethodError`.
3. Either forbid/seed symbolic scalars before they reach Arel `where` hashes,
   or give `SymbolicInt` a stable hash (the Python mirror already defines one
   deliberately; the Ruby side raises by design).
---

## Gate 1b FINAL (2026-08-10) — function-boundary splits

**Approach (Bali directive):** the runtime/engine is UNTOUCHED and strict (`SymbolicList#each`/`#map` still raise). The intermediate sampled-content iteration change (2026-08-09 addendum, if present) was REVERTED. Remaining SQL-free iteration walls were cleared by behavior-preserving FUNCTION-BOUNDARY SPLITS in the app code (e.g. `Post.blocked_people`, `Stream::Base#post_ids` / `#attach_user_likes`, `StreamsController#decorated_stream_posts`) plus `declare_target` wraps in `concolic_targets.rb`. No method containing SQL is mocked; each split is behavior-identical in a normal run.

**Final numbers (fresh `coverage_summary.json`, 2026-08-10 08:19):** runs=9, no-error=5, crashed=4, coverage_complete=True, missing_branches=0.
crash_types: {"NotImplementedError": 1, "NoMethodError": 3}

Crashed runs are preserved, not dropped. Honest caveat: `complete=true` means no missing branches were found **on the recorded (sampled) paths**;
entrypoints that crash before recording PCs stay vacuous/`incomplete`.
