# REPORT — "streams" batch — diaspora concolic experiment

Date: 2026-08-07 · Runtime: JRuby 9.3 + Java 21 · App `dse-apps/apps/diaspora`
(Rails 5.2) · RAILS_ENV=concolic · Driver: `run_concolic.rb`

## Status summary

**All 8 entrypoints report `CoverageChecker.complete == true`.**
18 default dumps (html + json per entrypoint) produced 6/8 complete on first
pass. 2 entrypoints needed seeded follow-up runs (`run_concolic_seeds.rb`).

## Entrypoints

| # | Entrypoint | Dumps | Complete | Notes |
|---|-----------|-------|----------|-------|
| 1 | `streams#activity` | 2 | ✅ | EvilQuery::Participation; 2 PCs, crashes on SymbolicList#each (render) |
| 2 | `streams#aspects` | 3 | ✅ | save_selected_aspects + Stream::Aspect; sizes-equal branch needed seed |
| 3 | `streams#commented` | 2 | ✅ | EvilQuery::CommentedPosts; 2 PCs, crashes on SymbolicList#each |
| 4 | `streams#followed_tags` | 2 | ✅ | Stream::FollowedTag; 2 PCs |
| 5 | `streams#liked` | 2 | ✅ | EvilQuery::LikedPosts; 2 PCs |
| 6 | `streams#mentioned` | 2 | ✅ | Stream::Mention; 2 PCs |
| 7 | `streams#multi` | 3 | ✅ | getting_started truthiness gap + MultiStream; seed needed for size-0 branch |
| 8 | `streams#public` | 2 | ✅ | Stream::Public; 2 PCs, anonymous (no auth) |

## Coverage summary

All 8 entrypoints: **complete**. 20 total dumps across the batch.

- **Defaults (18 dumps):** 6 entrypoints were already complete after html +
  json runs; `aspects` and `multi` had 1 missing branch each.
- **Seeded (2 dumps):** `aspects` needed `sizes_not_equal` branch;
  `multi` needed `size_not_gt_0` branch. Applied via `ConcolicTargets.seed_overrides`.

## Errors (expected — strict runtime)

All entrypoints crash during or after the render phase (SymbolicList#each /
SymbolicList#map) — the stream_posts collection can't be iterated. PCs
recorded before the crash are preserved in the dumps' pre-error events.
The crashes are:
- **SymbolicList#each** (N=7): `activity`, `aspects`, `commented`,
  `followed_tags`, `liked`, `mentioned`, `public` — render `@stream.stream_posts.each`
- **NoMethodError nil#[]** (N=1): `multi` seeded run — `gon.preloads` nil
  when `getting_started` is falsy (Rails controller-test boundary)

## Runner pattern

Same harness pattern as the proved `people` batch: symbolic_user with
concrete identity (id=1), StubWarden for Devise authenticate_user!,
FinderMethods-target-managed query results. `streams#public` is anonymous
(omits authenticate_user! via `except: :public`); all others are
authenticated. `streams#multi`'s `getting_started` truthiness gap driven via
seed_overrides.

## Time

0.8s (defaults) + ~10s (seeds run).
## Gate 1b addendum (2026-08-09)

`symlist(..., representative:)` representative landed in both runtimes; §8.3 mocks
(`Stream::Multi#publisher_prefill`, `Stream::Aspect#aspect_ids`,
`Stream::FollowedTag#tag_ids`, `User#blocks`) declared in `concolic_targets.rb`
and confirmed firing (`symbolic_call` events). Re-run of the batch: **16 runs,
0 no-error, 16 crashed** — crash mix: UnknownFormat×8 (html/render format gate),
SymbolicList#each×3, SymbolicList#map×2, NoMethodError×2, + misc. The mocks
advance execution past the mocked transform (aspect_ids/tag_ids/publisher_prefill
fire) but the terminal `@stream.stream_posts.map{...}` in each json `format.json`
block still raises on SymbolicList#map/#each — the approved iteration-stays-
unimplemented wall (design §5 limit). `aspect_ids`/`tag_ids` fed into
`visible_shareables(:by_members_of=>...)` / `StatusMessage.where("IN (?)",...)`
make Arel `.map` the SymbolicList during bind sanitization (documented cascade).
Crashed runs preserved (not dropped).

## Gate 1b follow-up — sampled-content iteration (2026-08-09, Bali directive)

Bali directed wrapping the SQL-free display methods ("just to display something
as a table"). `map`/`each` now iterate the single representative; collection
materialization (`to_a`/`records`) attaches a rep; the consuming boundary
(`Stream::Base#stream_posts`, `StatusMessage#tag_stream`/`user_tag_stream`)
returns rep-carrying Post lists. **Result: all 8 json entrypoints reach
`no-error`** (aspects, activity, commented, liked, mentioned, multi, public,
followed_tags). The 8 html strips remain `ActionController::UnknownFormat`
(render/format gate, separate). CoverageChecker: 16 runs / 8 ok / 8 crashed
(all UnknownFormat), complete=true. Sampled-content caveat: iteration models
only the representative row (design §5); crashed runs preserved.

---

## Gate 1b FINAL (2026-08-10) — function-boundary splits

**Approach (Bali directive):** the runtime/engine is UNTOUCHED and strict (`SymbolicList#each`/`#map` still raise). The intermediate sampled-content iteration change (2026-08-09 addendum, if present) was REVERTED. Remaining SQL-free iteration walls were cleared by behavior-preserving FUNCTION-BOUNDARY SPLITS in the app code (e.g. `Post.blocked_people`, `Stream::Base#post_ids` / `#attach_user_likes`, `StreamsController#decorated_stream_posts`) plus `declare_target` wraps in `concolic_targets.rb`. No method containing SQL is mocked; each split is behavior-identical in a normal run.

**Final numbers (fresh `coverage_summary.json`, 2026-08-10 08:19):** runs=18, no-error=7, crashed=11, coverage_complete=True, missing_branches=0.
crash_types: {"NoMethodError": 3, "ActionController::UnknownFormat": 8}
**Streams entrypoint breakdown:**
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

Crashed runs are preserved, not dropped. Honest caveat: `complete=true` means no missing branches were found **on the recorded (sampled) paths**;
entrypoints that crash before recording PCs stay vacuous/`incomplete`.
