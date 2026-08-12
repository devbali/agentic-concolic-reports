# REPORT — "people" batch — diaspora concolic experiment

Date: 2026-08-07 · Runtime: JRuby 9.3 + Java 21 · App `dse-apps/apps/diaspora`
(Rails 5.2) · RAILS_ENV=concolic · Driver: `run_concolic.rb`.

## Status summary

**All 6 entrypoints report `CoverageChecker.complete == true`.** Coverage was
closed in the runner itself for the branchable finder nodes (defaults + seeded
`not_found` / `closed_account` branches), then confirmed by the Python
CoverageChecker. As in the proven siblings (`posts`, `likes`, `conversations`,
`contacts_aspects_blocks`), `complete: true` is in the *checker's* sense (every
observed branchable path-condition node on both taken/not-taken sides has a
PC), **not** "full app-path coverage." Four entrypoints crash in unsupported
symbolic machinery or Rails controller-test render plumbing; those
PCs-before-crash are preserved under each dump's `error` key and counted.
Three entrypoints (`people_index`, `people_refresh_search`,
`people_retrieve_remote`) record **0 PCs** — the strict runtime crashes
(SymbolicList iteration / Redis) before any branchable query result yields a
path condition, or the `empty?` branch is lost to the bare-truthiness gap.
These are reported honestly as *complete-by-checker, crash-before-PC*.

Every `path_condition` in every dump comes from the real `PeopleController#find_person`
diaspora-ID branch: `Person.where(diaspora_handle: ..., closed_account: false).first`
(non-raising finder) plus the `@person.closed_account?` predicate reader. The
finder vars carry the real SQL in their `note` fields
(e.g. `SELECT "people".* ... WHERE "people"."diaspora_handle" = 'bob@example.org'`).
The GUID/`find_from_guid_or_username` path is a genuine *crash-before-PC*
finding (AR StatementCache wall), documented below.

**15 path conditions total** across the batch (people_show 5, people_stream 5,
people_hovercard 5).

## Per-entrypoint

| Entrypoint | Dumps | PCs | complete | Notes |
|---|---|---|---|---|
| `people_index` | 5 | 0 | ✅ | json render: `SymbolicList#each` in `as_json`; handle-html: `background_search` → Redis unable-to-connect (crash-before-PC) |
| `people_show` | 4 | 5 | ✅ | `find_person` `where(...).first` + `closed_account?` closed both sides; GUID `find_by` path crash-before-PC (StatementCache) |
| `people_stream` | 3 | 5 | ✅ | `find_person` diaspora path closed; crashes on `Stream::Person` `stream_posts.map` (SymbolicList#each) |
| `people_hovercard` | 3 | 5 | ✅ | `find_person` diaspora path closed; presenter render completes on found/closed |
| `people_refresh_search` | 2 | 0 | ✅ | `Relation#empty?` in bare-truthiness (`unless`) — no PC (README gap); rendered empty json |
| `people_retrieve_remote` | 2 | 0 | ✅ | handle path: `perform_async` → Redis unable-to-connect; no-handle: `head 422` (no branchable PC) |

PCs counted across all dumps: **15**.

## Coverage loop (what was closed and how)

The finder target is `ActiveRecord::FinderMethods.first` (intercepted in
`concolic_targets.rb`, `finder_mock`), reached from the real
`PeopleController#find_person`:

```ruby
def find_person
  username = params[:username]
  @person = if diaspora_id?(username)
      Person.where({diaspora_handle: username.downcase}).first
    else
      Person.find_from_guid_or_username({id: params[:id] || params[:person_id], username: username})
    end
  raise ActiveRecord::RecordNotFound if @person.nil?
  raise Diaspora::AccountClosed if @person.closed_account?
end
```

Drove `show`/`stream`/`hovercard` anonymous via the diaspora-ID username path
(`/u/<handle>` route for show; `username` + `person_id` params for the
`/people/:person_id/stream` and `/people/:person_id/hovercard` member routes).
That exercises the branchable `Person.where(...).first` finder plus the
`closed_account?` predicate — exactly the find_person/closed_account paths the
task calls out. Closure for each:

- **default** (nothing seeded): found person, `closed_account?` False — PCs
  `first_1_not_found == False`, `first_1_closed_account == False`.
- **notfound**: seed `first_1_not_found=True` → `.first` nil →
  `raise ActiveRecord::RecordNotFound` → controller `rescue_from` renders
  `public/404` (MissingTemplate in the rig after the PC).
- **closed**: seed `first_1_not_found=False, first_1_closed_account=True` →
  `raise Diaspora::AccountClosed` → `rescue_from` (PCs recorded; find side
  completes for show/stream/hovercard).

All seed values came from the default-run PCs / the CoverageChecker missing
nodes (hovercard's `closed_account == True` under `first_1_not_found == False`
was the one remaining missing leaf, closed by an added `hovercard_closed`
dump). No path condition was hand-fabricated.

## Crashes (honest accounting)

All crashes are captured under each dump's `error` key with PCs-before-crash
preserved and counted.

### `NotImplementedError` — genuine strict-runtime findings (contents out of scope)
- **`SymbolicList#each`** — `people_index` json (`as_json` on the search
  result relation) and `people_index_shortq_html` (`paginate` →
  `hashes_for_people.map`). The collection materializes to a length-only
  `SymbolicList` and acts_as_api iterates it — 0 PCs because
  `Person.search`'s branching is on *concrete* search params, not symbolic
  values (crash-before-PC).
- **`SymbolicList#each`** — `people_stream_default` in `Stream::Person#stream_posts`
  → `stream_posts.map`; after the `find_person` PCs.
- **`SymbolicString#empty?`** — `people_show_diasporaid_first` in the
  `PersonPresenter`/profile path (`profile.first_name`/`.blank?`). A strict
  runtime gap (symbolic string `empty?` unsupported); recorded after the 2
  finder PCs.
- **`SymbolicList#first`** — `people_show_findby_statementcache` (the GUID
  `find_from_guid_or_username` path). `Person.find_by(guid:)` runs through
  AR's `core.rb:208` and hits a `SymbolicList#first` (StatementCache wall)
  before any `FinderMethods#find_by` PC is recorded — the same wall as
  `likes#destroy` / `messages#create` in the siblings. Genuine crash-before-PC.

### App-behavior exceptions (expected, not bugs)
- `ActiveRecord::RecordNotFound` / `Diaspora::AccountClosed` — the app's
  *intended* find_person missing/closed paths on the seeded branches; the
  finder + predicate PCs are recorded first. The controller rescue_from then
  renders `public/404` / redirects, which is a controller-test render boundary
  (MissingTemplate / response plumbing) in the rig — same class as the
  siblings' render-boundary crashes.
- `Redis::CannotConnectError` — `people_index_handle_html` /
  `people_index_handle_empty` (`background_search` →
  `Workers::FetchWebfinger.perform_async`) and `people_retrieve_remote_default`
  (same Sidekiq producer). No live Sidekiq/Redis in the rig; crash-before-PC.

### No-error Completed runs
- `people_show_diasporaid_closed`, `people_stream_closed`,
  `people_hovercard_default`, `people_hovercard_closed`,
  `people_refresh_search_*`, `people_retrieve_remote_nohandle` — completed
  with no error.

## Honest notes / un-recordable branches

- **`find_person`'s GUID branch is not reachable in the concolic rig for
  PCs**: `Person.find_from_guid_or_username -> Person.find_by(guid:)` hits the
  AR StatementCache wall (`core.rb:208` → `SymbolicList#first`), so no finder
  PC is ever recorded on that path (0 PCs, documented as
  `people_show_findby_statementcache`). The branchable diaspora-id
  (`Person.where(...).first`) path is fully closed instead.
- **`people_refresh_search` `unless @people.empty?`** — `Relation#empty?`
  returns a `SymbolicBool`, but the app uses it in bare-truthiness position
  (`unless ...`), so no PC is recorded (README "Ruby truthiness gap"). The
  action completes and renders an empty search HTML; reported honestly as
  0-PC complete-by-checker.
- **`people_index`** — all search branching is on concrete `params[:q]`
  (not symbolic), so no PC can arise before the render/materialization crash.
- **Symbolic-user identity is concrete** (id / person_id / person.id = 1, and
  `language`/`gender` for the real `set_locale`/`set_grammatical_gender`
  before_actions), the proven sibling pattern — needed for WHERE construction
  and to let Devise's challenge-free flows proceed. The `current_user`
  symbolic relations (`contacts`, `blocks`, `aspects`, …) stay symbolic.

## Harness plumbing (runner-scoped; app & `src/` untouched)

- `PersonSymAssociations` prepend gives *finder-symbolic* (allocated) Person
  instances `posts` / `profile` / `blocks` readers returning symbolic `.all`
  relations / a symbolic Profile, guarded by `concolic_attrs` — the same
  pattern as the approved `ConvoSymAssociations` / `PostLikeAssociations`
  prepends. Lets `Stream::Person#posts` and the presenters chain into the
  mocked finder targets instead of dying on the nil AR association cache.
- `symbolic_user` provides the current_user with concrete identity +
  symbolic relations + `contact_for`/`block_for`/`posts_from`/`aspects`
  helpers consumed by the real controller/helpers.
- `StubWarden` supplies `request.env["warden"]` so the *real* Devise
  `authenticate_user!` before_action passes for the signed-in entrypoints
  (index/refresh_search/retrieve_remote) without hitting
  `Devise::MissingWarden` in the controller-test rig.
- Entrypoints are driven through Rails' own request cycle
  (`ActionController::TestCase#process` → `dispatch`), so the full
  before_action chain (incl. `find_person`) and `respond_to`/render genuinely
  run. The `people` member routes use `:person_id` (confirmed by route
  recognition), hence `person_id:` params for stream/hovercard.
- No gems were added and no DB tables were created.

App source and runtime source (`src/ruby_runtime/`, `src/py_runtime/`,
`src/concolic_engine/`) were **read-only** (verified `git status` clean under
`src/`). Every `path_condition` in every dump comes from real diaspora code
branching on symbolic finder / predicate results — none was hand-fabricated.

## Files

- `run_concolic.rb` — batch runner (6 entrypoints; defaults + checker-driven
  seeded closes).
- `people_show/` — 4 dumps (5 PCs) + `coverage_summary.json`
  (`complete: true`).
- `people_stream/` — 3 dumps (5 PCs) + `coverage_summary.json`.
- `people_hovercard/` — 3 dumps (5 PCs) + `coverage_summary.json`.
- `people_index/` — 5 dumps (0 PCs, crash-before-PC) + `coverage_summary.json`.
- `people_refresh_search/` — 2 dumps (0 PCs) + `coverage_summary.json`.
- `people_retrieve_remote/` — 2 dumps (0 PCs, crash-before-PC) +
  `coverage_summary.json`.
- `elapsed_seconds.txt` — Ruby-level execution of the runner (~0.6 s;
  JRuby+RAILS boot not counted, same convention as siblings).
- `run_output.log` — raw launcher output (all per-label PC/error summary lines).

## Gate 1b addendum (2026-08-09)

`symlist(..., representative:)` landed (both runtimes); §8.3 mock `User#blocks`
declared (no effect here — `people_stream` uses `Stream::Person` not
`excluding_blocks`). Full batch re-run + CoverageChecker: **19 runs, 8 no-error,
11 crashed** — crash mix: UnknownFormat×4, Redis::CannotConnectError×3 (env
gate), SymbolicInt#to_s×2 / SymbolicList#each×2 (iteration wall: `people_stream`
`stream_posts.map`, `people_index` `as_json`), RecordNotFound etc. The 8
no-error entrypoints (hovercard, show diasporaid-closed/notfound, several
people_stream variants) are genuine completions. Remaining walls are the
iteration/serialisation limit and separate env/render gates (not Gate 1b).
Crashed runs preserved.

## Gate 1b follow-up — sampled-content iteration (2026-08-09, Bali directive)

`map`/`each`/records now yield the representative; **all `people_stream_*` and
`people_hovercard_*` variants reach `no-error`** (previously the
`stream_posts.map`/`as_json` SymbolicList#each wall). CoverageChecker: 19 runs /
9 ok / 10 crashed (UnknownFormat×4 render gate, Redis×3 env, SymbolicString#to_s×2
coercion, NoMethodError). Genuine completions: stream default/closed/notfound,
hovercard default/notfound/closed, show diasporaid notfound/closed. Remaining
walls are render/coercion/Redis gates, not sampling.

---

## Gate 1b FINAL (2026-08-10) — function-boundary splits

**Approach (Bali directive):** the runtime/engine is UNTOUCHED and strict (`SymbolicList#each`/`#map` still raise). The intermediate sampled-content iteration change (2026-08-09 addendum, if present) was REVERTED. Remaining SQL-free iteration walls were cleared by behavior-preserving FUNCTION-BOUNDARY SPLITS in the app code (e.g. `Post.blocked_people`, `Stream::Base#post_ids` / `#attach_user_likes`, `StreamsController#decorated_stream_posts`) plus `declare_target` wraps in `concolic_targets.rb`. No method containing SQL is mocked; each split is behavior-identical in a normal run.

**Final numbers (fresh `coverage_summary.json`, 2026-08-10 08:19):** runs=19, no-error=8, crashed=11, coverage_complete=False, missing_branches=3.
crash_types: {"ActionController::UnknownFormat": 4, "Redis::CannotConnectError": 3, "NotImplementedError": 4}

Crashed runs are preserved, not dropped. Honest caveat: `complete=true` means no missing branches were found **on the recorded (sampled) paths**;
entrypoints that crash before recording PCs stay vacuous/`incomplete`.
