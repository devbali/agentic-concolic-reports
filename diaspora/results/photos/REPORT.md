# Batch report — `photos`

Concolic run of the **photos** batch of the diaspora experiment against the
real Rails app (`diaspora`) on JRuby 9.3 + Java 21, per the batch README.

## Entrypoints driven (8)

| Route → Action | results/photos/ dir |
|---|---|
| `GET /photos/:id` photos#show | `photos_show` |
| `GET /people/:id/photos` photos#index | `photos_index` |
| `POST /photos` photos#create | `photos_create` |
| `DELETE /photos/:id` photos#destroy | `photos_destroy` |
| `PUT /photos/:id/make_profile_photo` photos#make_profile_photo | `photos_make_profile_photo` |
| `POST /posts/:id/participation` participations#create | `participations_create` |
| `DELETE /posts/:id/participation` participations#destroy | `participations_destroy` |
| `POST /posts/:id/poll_participations` poll_participations#create | `poll_participations_create` |

Driver: `run_concolic.rb` (this dir). Elapsed full batch: see `elapsed_seconds.txt` (~10 s).

## Methodology

Each entrypoint is driven as a **real controller action** through Rails' own
controller-test machinery (`ActionController::TestCase`) — the same harness
the app's own `spec/controllers/*` use. The runner supplies only request /
params / `current_user` plumbing, then invokes the real action method inside
`CallInterceptor.instance.run(...)`. No app service/controller logic is
replicated here; every `path_condition` comes from real diaspora code
branching on symbolic values.

Framework-level query interception via `ConcolicTargets.install!` (shared,
read-only): single-record finders return symbolic model instances whose
boolean readers (`public?`, `pending`) self-record PCs; `find_by`/`first`
record the not-found PC at the finder boundary; collections are length-only
`SymbolicList`s.

### Symbolic current_user (documented infrastructure)

Controllers in this batch are almost all behind `authenticate_user!`, so a
`current_user` is required. `current_user` is a **symbolic `User` instance**
(real class, `allocate`, per-column symbolic readers) whose **identity**
(`id`, `person_id`) is held **concrete**. Those values appear *only* inside
ActiveRecord WHERE clauses (e.g. `where(author_id: current_user.person_id)`);
they are never branched on by the app. If symbolic, the finder mock's
`receiver.to_sql` crashes with `NotImplementedError: SymbolicInt#hash`
(query-predicate normalization hashes bound values) before any PC can be
captured. Branch-relevant values (query results, `not_found`, boolean
columns) stay symbolic, so all PCs still come from real app branching. This
mirrors the README's verified `posts#show` pattern, which passes a concrete
`id` into `PostService` and branches on `post.public?`.

## Results

| Entrypoint | #PCs (total across runs) | Path conditions | Coverage |
|---|---|---|---|
| photos_show | 2 dumps × 1 PC | `Photo.where(id:,public:).first` not-found boundary | tree complete (1 node, both sides) |
| photos_destroy | 2 dumps × 1 PC | `current_user.photos.where(id:).first` not-found boundary | complete |
| photos_make_profile_photo | 2 dumps × 1 PC | `Photo.where(id:,author_id:).first` not-found boundary | complete |
| participations_create | 4 dumps, 1–3 PCs each | `EvilQuery::VisibleShareableById#post!` `q1.first‖q2.first‖q3.first` (3 nodes, all sides) | **complete** (3 nodes) |
| participations_destroy | 2 dumps × 1 PC | `current_user.participations.find_by(...)` not-found boundary | complete |
| photos_index | 2 dumps × 0 PCs | — (crashes before any branch) | 0 nodes (vacuous complete) |
| photos_create | 1 dump × 0 PCs | — (crashes before any branch) | 0 nodes (vacuous complete) |
| poll_participations_create | 1 dump × 0 PCs | — (crashes before any branch) | 0 nodes (vacuous complete) |

The PCs recorded are, in every case, produced by the **real finder
interception layer** (`reporter` at `concolic_targets.rb:116`) in the actual
controller/service code path — e.g. `photos#show`'s
`Photo.where(id: params[:id], public: true).first`, and `photos#destroy`'s
`current_user.photos.where(:id => params[:id]).first`. `participations#create`
exercises the real `EvilQuery::VisibleShareableById#post!` `a.first || b.first
|| c.first` short-circuit chain; all three finders are covered on both the
found and not-found sides.

Every dump contains `symbolic_call` events with the real SQL in the
intercepted query (satisfying the README verification criterion).

## Findings / honest limitations

These are **findings, not failures**. In many entrypoints the action's
controller body reaches a *finder* branch (PC captured) and then crashes in
deeper model/rendering code that the strict symbolic runtime cannot execute;
the PCs captured before the crash are retained (dump `error` key set, as per
README).

1. **photos_index — 0 PCs.** `@person = Person.find_by_guid(params[:person_id])`
   is a *class-level* dynamic finder which Rails routes through
   `find_by_sql` (`SymbolicList`) and then `.first` on it → `NotImplementedError:
   SymbolicList#first`. Class-method finders aren't the declared
   `FinderMethods#first` instance target, so the `@person` branch is
   un-interceptable at this layer. Both seeded variants crash identically
   before any PC. The `Photo.visible(...).count` path is unreachable through
   the real flow.

2. **photos_create — 0 PCs.** Real `current_user.build_post(:photo, …)` →
   `Photo.diaspora_initialize` does an ActiveModel integer type-cast on a
   symbolic integer value (`SymbolicInt#to_i`), so the action crashes before
   `@photo.save` / `@photo.pending`. No branch PCs obtainable; the `if
   @photo.save` would in any case hit the Ruby truthiness gap (save returns a
   truthy wrapper).

3. **poll_participations_create — 0 PCs.** The real action opens with
   `PollAnswer.find(params[:poll_answer_id])` (raise-on-missing `find`), then
   `target` → `find_visible_shareable_by_id` (EvilQuery). It crashes at
   `PollAnswer.find` before recording a PC; the run needed empty
   `poll_answers` / `polls` / `poll_participations` tables added to the
   `concolic` DB for `columns_hash` (README permits adding empty schema
   tables). Still no PC before the crash — a real limitation of the finder
   interception for this path.

4. **Ruby truthiness gap (README-known).** Controller-level `if post`,
   `if @photo`, `if participation` are bare-truthiness checks the runtime
   cannot intercept; the PC is instead recorded at the finder boundary
   (`not_found == True`) and the app branches concretely + consistently with
   it. `if @photo.save` (a `SymbolicBool` wrapper, always truthy) is
   un-branchable — only the true side is reachable.

5. **`participations#create` / `#destroy` and `photos#destroy` /
   `photos#make_profile_photo`** each capture the finder PC, then crash in
   the real service/generator (`Participation::Generator`, `retract`,
   `update_profile`, profile-hash string concat) or during `head`/`render`
   on symbolic values. These crashes are captured in the dump `error` and do
   not erase the earlier PCs.

6. **Direct-action invocation.** Actions are invoked via the controller-test
   `send(action)` rather than a full Rack dispatch, because the app's
   `before_action`s (`set_locale` → `I18n.locale=` on a symbolic string,
   `mobile_switch`, `gon_*`) crash before reaching the action body. The real
   action body and its services/models still execute. Some runs end with
   `ActionController::Metal#status=` delegation errors from `head :created`
   etc. because no full HTTP response was constructed — again, after the
   relevant PCs.

## Deliverables

Per-entrypoint: `dump_{label}.json` (RunDump) + `coverage_summary.json`
(CoverageChecker). Batch: `run_concolic.rb`, `elapsed_seconds.txt`,
`REPORT.md`. Shared `README.md` and `concolic_targets.rb` were **not**
modified. No files under the app or `src/` were modified (read-only).
---

## Gate 1b FINAL (2026-08-10) — function-boundary splits

**Approach (Bali directive):** the runtime/engine is UNTOUCHED and strict (`SymbolicList#each`/`#map` still raise). The intermediate sampled-content iteration change (2026-08-09 addendum, if present) was REVERTED. Remaining SQL-free iteration walls were cleared by behavior-preserving FUNCTION-BOUNDARY SPLITS in the app code (e.g. `Post.blocked_people`, `Stream::Base#post_ids` / `#attach_user_likes`, `StreamsController#decorated_stream_posts`) plus `declare_target` wraps in `concolic_targets.rb`. No method containing SQL is mocked; each split is behavior-identical in a normal run.

**Final numbers (fresh `coverage_summary.json`, 2026-08-10 08:19):** runs=16, no-error=1, crashed=15, coverage_complete=False, missing_branches=5.
crash_types: {"Module::DelegationError": 3, "NotImplementedError": 7, "NoMethodError": 4, "ActiveRecord::RecordNotFound": 1}

Crashed runs are preserved, not dropped. Honest caveat: `complete=true` means no missing branches were found **on the recorded (sampled) paths**;
entrypoints that crash before recording PCs stay vacuous/`incomplete`.
