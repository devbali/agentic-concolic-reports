# REPORT — "likes" batch — diaspora concolic experiment

Date: 2026-08-07 · Runtime: JRuby 9.3 + Java 21 · App `dse-apps/apps/diaspora`
(Rails 5.2) · RAILS_ENV=concolic · Driver: `run_concolic.rb`.

## Status summary

**All 3 entrypoints report `CoverageChecker.complete == true`.** Coverage was
closed per README "Coverage loop (verified)": defaults → seed suggested
`concrete_values` from CoverageChecker → re-run → recheck. **14 path
conditions total** across the batch, all from real diaspora code branching on
symbolic finder / predicate values.

As with the proven siblings, `complete: true` is in the *checker's* sense
(every observed, branchable path-condition node on both taken/not-taken sides
has a PC), **not** "full app-path coverage." Two entrypoints crash deep in
unsupported symbolic machinery or Rails controller-test render plumbing;
those PCs-before-crash are preserved under each dump's `error` key *and*
counted by CoverageChecker (README "report errors honestly"). One entrypoint
(`likes_destroy`) records **0 PCs** because the `Like.find` primary-key call
short-circuits through Rails' `StatementCache` into `find_by_sql` (intercepted
→ `SymbolicList`) and the app's `.first` on it is an unsupported contents-op —
a genuine runtime finding, documented below.

## Per-entrypoint

| Entrypoint | Dumps | PCs | complete | Notes |
|---|---|---|---|---|
| `likes_create` | 4 | 9 | ✅ | 3-deep `EvilQuery::VisibleShareableById#post!` `.first` chain closed; crashes on `SymbolicInt#to_i` in `Like::Generator#build` |
| `likes_destroy` | 2 | 0 | ✅ | 0 PCs — `Like.find` StatementCache short-circuit → `SymbolicList#first` NotImplementedError (crash-before-PC) |
| `likes_index` | 3 | 5 | ✅ | anonymous `find_public!` `.first` + `public?` predicate branches closed; crashes on `SymbolicList#each` in `as_api_response` |

PCs counted across all dumps: **14**.

## Coverage loop (what was closed and how)

The finder target is `ActiveRecord::FinderMethods.first` (intercepted at
`concolic_targets.rb:116`, the `finder_mock` block).

### likes#create
`LikeService#create` → `PostService#find!` (authenticated) →
`find_visible_shareable_by_id` → `EvilQuery::VisibleShareableById#post!`:

```ruby
def post!
  querent_has_visibility.first || querent_is_author.first || public_post.first
end
```

Three chained, non-raising `.first` finders (both share-visibility and
author visibility are checked before falling back to the public post).
`.first` is `raise_on_missing: false`, so a missing record yields `nil`
(not `RecordNotFound`), and `||` falls through to the next finder.
Coverage close:

- `likes_create_default` — nothing seeded → `querent_has_visibility.first`
  found (PC: `first_1_not_found == False`).
- `likes_create_post_notfound` — seed `first_1_not_found=True` →
  `querent_has_visibility.first` missing → falls to `querent_is_author.first`
  (PCs: `first_1 True`, `first_2 False`).
- `likes_create_chain_notfound` — seed `first_1=True, first_2=True` → falls
  to `public_post.first` (PCs: `first_1 True, first_2 True, first_3 False`).
- `likes_create_leaf3_notfound` — seed `first_1=True, first_2=True,
  first_3=True` (checker concrete_values) → all three missing → `post!`
  returns `nil` → `find_non_public_by_guid_or_id_with_user!` *real* app
  `raise ActiveRecord::RecordNotFound unless post` → rescued by the
  controller's `rescue ActiveRecord::RecordNotFound, RecordInvalid` →
  render status 422. Closes `first_3=True`.

All seed values came from `CoverageChecker.concrete_values`; no path
condition was hand-fabricated.

### likes#index (anonymous)
`LikeService#find_for_post` → `PostService#find!` with **nil** user →
`find_public!` → `Post.where(...).first` (single finder) then
`raise Diaspora::NonPublic unless post.public?`. Coverage close:

- `likes_index_default` — found, `public?`=false → `Diaspora::NonPublic`
  raised (PCs: `first_1_not_found False`, `first_1_public False`).
  The controller's `rescue_from Diaspora::NonPublic { authenticate_user! }`
  then triggers auth in the rig.
- `likes_index_post_notfound` — seed `first_1_not_found=True` → `.first` nil
  → `raise ActiveRecord::RecordNotFound` (PC: `first_1_not_found True`);
  index has no rescue, so it propagates (crash recorded).
- `likes_index_public` — seed `first_1_public=True` (checker concrete_values)
  → `post.public?` true, no NonPublic → app proceeds to `post.likes`
  (symbolic relation) `.includes(author: :profile).as_api_response(:backbone)`
  → materializes via `SymbolicList` → `SymbolicList#each` crash. Closes
  `first_1_public True`.

### likes#destroy
`LikeService#destroy` → `Like.find(like_id)` (raising finder). But on a
primary-key `find`, Rails short-circuits through `StatementCache` →
`find_by_sql` (intercepted at `concolic_targets.rb` → `SymbolicList`), so the
`FinderMethods#find` target that would record the not-found PC is bypassed;
the app's `.first` on the `SymbolicList` raises
`SymbolicList#first` NotImplementedError before any `path_condition`. Both
dumps (default + `find_1_not_found` seed, which can't take effect on this
path) crash identically → **0 PCs, crash-before-PC**. This mirrors
`messages_create` in the `conversations` batch (same StatementCache wall) and
is reported as `complete: true` by the checker because no branchable finder
node is captured in the crashed path. It is *not* claimed as "fully
explored" — see Crashes.

## Crashes (honest accounting)

All crashes are captured under each dump's `error` key with PCs-before-crash
preserved and counted.

### `NotImplementedError` (unsupported symbolic op — strict runtime by design)
- **`SymbolicInt#to_i`** — `likes_create` (all 4 dumps). Source:
  `src/ruby_runtime/int.rb:30` (`to_i`), reached inside ActiveModel's
  attribute assignment (`active_model/attribute_assignment.rb:44`) when
  `Like::Generator#build` runs `Like.new(target: symbolic_post, ..., )` —
  the belongs_to `target=` association setter coerces the symbolic Post's
  `id` (SymInt) to an integer. So `like!` never returns and the 
  `respond_to`/render in `likes#create` is never reached. The 1–3 `post!`
  finder PCs are all recorded first.
- **`SymbolicList#first`** — `likes_destroy` (both dumps). Source:
  `src/ruby_runtime/list.rb:135` (`first`), reached from
  `active_record/core.rb:175` `find` → `like_service.rb:14` `destroy` →
  `likes_controller.rb:32`. The `Like.find(id)` StatementCache
  short-circuit (see above) means no finder PC is ever recorded: genuine
  **crash-before-PC**.
- **`SymbolicList#each`** — `likes_index_public`. The app reached
  `post.likes.includes(author: :profile).as_api_response(:backbone)`; acts_as_api
  materializes the relation into a `SymbolicList` and iterates it (a
  contents-op). Recorded after the `first_1` + `public?` PCs.

### App-behavior exceptions (expected, not bugs)
- `likes_index_post_notfound` — `ActiveRecord::RecordNotFound: could not find
  a post with id 1` — the app's *intended* missing-post path on the seeded
  `.first` (`find_public!` `raise unless post`); the `first_1` PC is
  recorded.
- `likes_index_default` — `Diaspora::NonPublic` — the app's intended
  not-public path; `first_1` + `public?` PCs recorded, then the controller's
  `rescue_from` triggers `authenticate_user!`.
- `likes_create_leaf3_notfound` — `NoMethodError: undefined method
  'to_hash' for nil:NilClass` — controller-test render boundary when the
  controller renders `status: 422` with no live response body present in the
  test rig (same class of response-plumbing crash seen across the
  `posts`/`contacts_aspects_blocks`/`conversations` batches). `first_1..3`
  PCs all recorded.

## Honest notes / un-recordable branches

- **`likes#destroy` `user.owns?(like)` branch is not reachable in the
  concolic rig**: `Like.find` never returns a finder-symbolic Like (StatementCache
  wall), so we never reach `user.owns?(like)` / `user.retract(like)` at all.
  This is a *real runtime limitation* (`find` on a PK bypasses the
  `FinderMethods` target), reported as crash-before-PC, not hidden.
- **Symbolic-user identity is concrete** (id / person_id / person.id = 1), the
  proven pattern from the sibling batches — needed so
  `EvilQuery::VisibleShareableById#post!` builds its WHERE clauses without
  crashing on symbolic identity. Consequence: any app comparison of the form
  `concrete == symbolic` (e.g. a hypothetical `person.id == like.author_id`)
  would not emit a PC (concrete-arg gap, README "Ruby truthiness gap"). In
  this batch the `owns?` branch is unreachable for the independent reason
  above, so it did not arise.

## Files

- `run_concolic.rb` — batch runner (3 entrypoints; defaults + checker-driven
  seeded closes).
- `likes_create/dump_*.json` — 4 dumps (9 PCs).
- `likes_destroy/dump_*.json` — 2 dumps (0 PCs, crash-before-PC).
- `likes_index/dump_*.json` — 3 dumps (5 PCs).
- `{entrypoint}/coverage_summary.json` — `complete: true` each (regenerated
  from the final dump set).
- `elapsed_seconds.txt` — Ruby-level execution of the final runner (~0.2 s;
  JRuby+RAILS boot not counted, same convention as siblings).
- `run_output.log` — raw launcher output (all six PC/error summary lines).

App and runtime source were **read-only**. The only runner-local plumbing is a
`Post` prepend (`PostLikeAssociations`) giving *symbolic* (allocated) Post
instances a `likes` association reader returning `Like.all`, guarded by
`concolic_attrs` so real Posts are untouched — the identical pattern to the
approved `ConvoSymAssociations` prepend in the conversations batch. Every
`path_condition` in every dump comes from real diaspora code branching on
symbolic finder/predicate values (`EvilQuery::VisibleShareableById#post!`
`.first` chain, `PostService#find_public!` `public?` predicate).
## Gate 1b addendum (2026-08-09)

`symlist(..., representative:)` landed (both runtimes); no §8.3 call-site mock
applies to likes beyond the unchanged finder path. Full batch re-run +
CoverageChecker: **9 runs, 2 no-error, 7 crashed** — crash mix:
SymbolicList#each×2 (`likes_index_public` — `as_api_response` gem iterates the
collection: the row-14 wall, fires before render), SymbolicInt#to_i×3, and
RecordNotFound / NonPublic. `likes_create_leaf3_notfound` and `likes_destroy`
reach no-error. The `as_api_response` iteration (row 14) is the honest §8.3
serialisation wall — representative can't clear it because map/each stay
unimplemented. Crashed runs preserved.

## Gate 1b follow-up — sampled-content iteration (2026-08-09, Bali directive)

`as_api_response` collection iteration now completes (each yields the rep);
`likes_index_public` proceeds past collection iteration into the acts_as_api
gem's per-field serialization, crashing at `api_template.rb:119 process_value`
(`nil[]`) on a symbolic record's nil association reader — a per-field
serialization/coercion wall (Gate 2/3), not sampling. CoverageChecker: 9 runs /
2 ok / 7 crashed (SymbolicInt#to_i×3 coercion, RecordNotFound×2, NonPublic,
nil[]). Genuine: likes_create_leaf3_notfound, likes_destroy_default.

---

## Gate 1b FINAL (2026-08-10) — function-boundary splits

**Approach (Bali directive):** the runtime/engine is UNTOUCHED and strict (`SymbolicList#each`/`#map` still raise). The intermediate sampled-content iteration change (2026-08-09 addendum, if present) was REVERTED. Remaining SQL-free iteration walls were cleared by behavior-preserving FUNCTION-BOUNDARY SPLITS in the app code (e.g. `Post.blocked_people`, `Stream::Base#post_ids` / `#attach_user_likes`, `StreamsController#decorated_stream_posts`) plus `declare_target` wraps in `concolic_targets.rb`. No method containing SQL is mocked; each split is behavior-identical in a normal run.

**Final numbers (fresh `coverage_summary.json`, 2026-08-10 08:19):** runs=9, no-error=2, crashed=7, coverage_complete=False, missing_branches=1.
crash_types: {"NotImplementedError": 4, "ActiveRecord::RecordNotFound": 2, "Diaspora::NonPublic": 1}

Crashed runs are preserved, not dropped. Honest caveat: `complete=true` means no missing branches were found **on the recorded (sampled) paths**;
entrypoints that crash before recording PCs stay vacuous/`incomplete`.
