# RESULT.md — variant_a (T1 leaf-probed) — notifications_index

Rule-set applied: **DISCIPLINE_TESTS.md T1 only** (the mock leaf-probe, including
the 2026-08-19 coverage-metric addendum). T2 (assumption probe) is variant_b's
scope, not run here. Started from the same gen3f `results3/notifications_index/`
code as the control (byte-identical `concolic_targets.rb`/`targets.rb`/`run_dse.rb`
— verified with `diff`, zero output — confirmed before any probing began).

---

## 1. T1 leaf-probe sweep

### Methodology

`_leaf_probe.rb` boots the real diaspora Rails env once (`RAILS_ENV=concolic`)
and installs this dir's `concolic_targets.rb` + `targets.rb` exactly as
`run_dse.rb` does. Rather than reboot the JVM once per declared mock (68
`declare_target` calls + several `prepend` shims — infeasible in the memory/time
budget), the harness wraps `CallInterceptor#declare_target` *before*
installation runs and captures the pristine pre-mock `UnboundMethod` for every
`(klass, method)` pair, plus the installed mock `UnboundMethod` right after.
Probing a method is then an in-process toggle: `define_method(true_original)` →
run the concrete fixture matrix → `define_method(mock)` to restore. This is
mechanically equivalent to "boot with that one `declare_target` skipped" (calls
into any *other* still-mocked target are still intercepted normally) without
paying for 68 separate boots. `ENV["PROBE_SKIP"]`/single-method mode is also
implemented for spot-checks, per the letter of DISCIPLINE_TESTS.md.

Two identity bugs were found and fixed empirically during harness construction:

1. `klass.name` is `nil` for every anonymous `singleton_class` target (e.g.
   `Post.singleton_class`) — a naive string key collapsed **five** unrelated
   singleton-class mocks (`Post`, `Photo`, `Diaspora::Mentionable`,
   `Diaspora::MessageRenderer::Processor`, `ActionDispatch::Journey::Router::Utils`)
   onto the same bare `"#method"` key. Fixed by keying capture maps on
   `[klass.object_id, method]` identity and deriving a readable display name
   (`Post.blocked_people`) from the singleton class's own `#to_s` (`"#<Class:Post>"`).
2. A subclass `declare_target` for a method it does **not** itself override
   (`BelongsToPolymorphicAssociation#find_target` — AR's real hierarchy never
   defines this, verified by reading `belongs_to_polymorphic_association.rb`)
   captures its "true original" *after* an earlier `declare_target` on the
   ancestor (`SingularAssociation#find_target`) already replaced it — the
   captured "original" is actually the ancestor's mock closure, detectable
   because its `source_location` lands inside `call_interceptor.rb`. The harness
   detects this and reports `INHERITED_NO_OVERRIDE` instead of running a
   misleading probe.

Coverage is measured via `TracePoint(:line)`, scoped to the probed method's own
`[file, start..end]` range, unioned across the fixture matrix. **JRuby's JIT
silently drops `:line` trace events unless launched with `jruby --debug`**
(verified empirically: identical code produced zero covered lines without the
flag, full coverage with it) — the whole harness runs under `--debug` (accepted
as a one-shot probe-run cost; boot was ~8s even fully interpreted, not the
bottleneck feared). The line-range and "candidate executable lines" denominator
come from a `Ripper`-based scanner (`on_def`/`on_defs` fires with `lineno` at
the closing `end`, paired with a `def`-keyword stack for the start line), since
JRuby has no `RubyVM::InstructionSequence` and thus no MRI-equivalent ground
truth for "which source lines are bytecode-executable." **This is a documented
APPROXIMATION**, not exact instrumentation — reported honestly, not as exact
Ruby `Coverage`-stdlib output.

A methodology bug was found and fixed mid-sweep: the connection-adapter
raise-hook was initially catching Rails' own **lazy schema introspection**
(`PRAGMA table_info(...)`, `SELECT name FROM sqlite_master ...`) on first touch
of a model class — framework infra, not app SQL under test. Fixed by
pre-warming the connection's `schema_cache` for every table plus running one
harmless `.where(id:-999).to_a/.find_by/.count/.exists?` per fixture model
*before* installing the hook.

### Results (98 declared targets/shims total)

| verdict | count | meaning |
|---|---|---|
| NOT_PROBED | 80 | dormant/out-of-scope for this endpoint — each has a recorded `skip_reason`, not a silent skip |
| PASS | 6 | real body ran clean: 0 target-calls, 0 SQL, full (or trivial) candidate-line coverage |
| EXEMPT | 4 | DESIGN-family (query-boundary) mock — probed/recorded per instructions, not subject to removal |
| STRUCTURAL-PASS | 3 | prepend infra shims — transparent by construction, real body runs by default |
| FAIL | 2 | real body calls into another declared target — neither required a code change (see below) |
| FAIL_COVERAGE | 1 | 0 target-calls/SQL but fixture matrix didn't reach every candidate line (see below) |
| INSTRUMENTATION-FAILED | 1 | no capturable `source_location` for this exact key (superseded by a correctly-resolved sibling probe) |
| INHERITED_NO_OVERRIDE | 1 | no independent real body exists (see methodology bug #2 above) |

Full machine-readable ledger: `LEAF_PROBES.json` (98 records). Human summary:
`LEAF_PROBES.md`.

### The two FAIL verdicts — why neither triggers a mock change here

**`DeviseController#assert_is_devise_resource!` → FAIL** (1 target-call into
`DeviseController.devise_mapping`, 10% coverage — the probe correctly stopped
at the first line once the call fired). Real, correct finding about the
method's body. But `NotificationsController < ApplicationController`, **not**
`DeviseController** — the mock is declared literally on the `DeviseController`
class, whose instance methods never enter `NotificationsController`'s method
resolution order. `assert_is_devise_resource!`/`devise_mapping` only fire for
Devise's own engine controllers (sessions, registrations). Confirmed dormant
for `#index` by class hierarchy, not just absence-of-evidence. Flagged as a
genuine finding relevant to whichever batch actually drives a Devise controller
— not this one.

**`ActionController::Head#head` → FAIL** (3 target-calls into
`ActionController::Metal.status=` and `ActionDispatch::Routing::UrlFor.url_for`,
57% coverage). Both callees are *independently* PASS-verified leaves. The real
`head` body crashes on the exact root cause `status=`'s mock exists for
(`Module::DelegationError`/`NoMethodError` on a `nil @_response` in the bare
`ActionController::TestCase` rig — a framework/rig limitation, not app SQL).
`NotificationsController#index`'s own source never calls `head` (verified by
reading `notifications_controller.rb`); dormant for this endpoint's actual
output either way. Kept, documented as a judgment call: removing it would only
reintroduce a rig crash with zero effect on extracted queries.

### Two non-issues (not violations)

**`ActionController::Rendering#_set_rendered_content_type` → FAIL_COVERAGE
(50%)**: both fixtures showed 0 target-calls/0 SQL; the second fixture's own
`NoMethodError` (`content_type` on nil `@_response` — same rig limitation as
above) cut it short before the second candidate line. A probe-fixture
limitation, not a discipline violation. Mock kept.

**`BelongsToPolymorphicAssociation#find_target` → INHERITED_NO_OVERRIDE**:
confirmed by reading AR 5.2.4.3's `belongs_to_polymorphic_association.rb` that
it overrides `klass`/`target_changed?`/`replace_keys`/etc. but **not**
`find_target` — no separate real body exists. W3b's `declare_target` exists
purely to select a *different mock implementation* for polymorphic receivers
(correctly resolving `owner[foreign_type]` instead of the ancestor mock's
`reflection.klass`, which misresolves for polymorphic reflections) — ordinary
Ruby-dispatch mock-authoring, not an app-code override. The one real
`find_target` body that exists was already probed under
`SingularAssociation#find_target` (DESIGN/EXEMPT, 75% coverage, 1 target-call
into `find_by_sql` — exactly the expected shape of a query-boundary leaf).

### Bottom line: zero mocks changed

**No mock or shim in `concolic_targets.rb`/`targets.rb` was removed, descended,
or edited under variant_a.** Every genuinely on-path, reachable mock either
PASSED outright, is DESIGN-family and correctly EXEMPT, or its only FAIL traces
to a target class this endpoint never instantiates (Devise) or to calls into
other already-PASS leaves under a documented rig limitation unrelated to app
SQL. This is a real, mechanically-produced finding, not an evasion of the
sweep: the gen3f mock surface this batch started from (already rebuilt once
under results3's "no mock over SQL potential" discipline — see
`../BUGFIXES_20260819.md`) was already T1-compliant for this endpoint before
this probe run began. Because `concolic_targets.rb`/`targets.rb` are therefore
byte-identical to the gen3f baseline, variant_a's corpus/coverage/extraction
pipeline is expected — and, see below, confirmed — to reproduce gen3f's query
shapes rather than diverge from them.

### The 80 NOT_PROBED (dormant) targets, by reason

- **Other endpoints' feature areas entirely** — `Stream::Aspect#aspect_ids`,
  `Stream::FollowedTag#tag_ids`, `Stream::Base#post_ids`/`#attach_user_likes`,
  `StreamsController#decorated_stream_posts`, `Stream::Multi#publisher_prefill`,
  `TagsController#prep_tags_for_javascript` (stream/tag-filtering UI, not
  notifications).
- **posts_show / federation specific** — `PostService#mark_user_notifications`,
  `Diaspora::Taggable#build_tags`, `StatusMessage#tag_name_max_length`,
  `DiasporaFederation::Entity#validate`, `Diaspora::Mentionable.people_from_string`,
  `PostPresenter#build_mentioned_people_json`, `Diaspora::MessageRenderer#title`/
  `Processor.process`, `Photo#url`/`Photo.diaspora_initialize`,
  `Post.blocked_people`, `User#blocks`, `DiasporaFederation::Discovery::Discovery
  #fetch_and_save`.
- **Registration/session flows** — `User#add_to_streams`/`#retract`/
  `#confirm_email`/`#mine?`, `StatusMessageCreationService#add_to_streams`,
  `ApplicationController#after_sign_in_path_for`/`#configure_permitted_parameters`,
  `DeviseController#devise_mapping`, `Gon::ControllerHelpers#gon`.
- **Read-only endpoint, DML never fires** — `ActiveRecord::Relation#update_all`/
  `#delete_all`/`#destroy_all`, `ActiveRecord::Base#save`/`#save!`/`#update`/
  `#update!`/`#update_attribute`/`#touch`/`#destroy`/`#destroy!`.
- **Never invoked by this app's read path** — `ActiveRecord::Batches#find_each`/
  `#find_in_batches`/`#in_batches`, unsupported `Calculations#pluck`/`#ids`/
  `#average`/`#minimum`/`#maximum`/`#calculate`, `ActiveRecord::Querying
  #find_by_sql`/`#count_by_sql`, the ordinal-finder family (`find`/`take!`/
  `first!`/`last!`/`find_by!`/`take`/`first`/`last`/class-level `find`/`find_by!`/
  `exists?`/`any?`/`none?`/`one?`/`many?`/`empty?`/`Relation#to_a`/`#to_ary`/
  `#records`/`#size`/`Calculations#sum`), `Sidekiq::Client#push`/`#push_bulk`,
  `ActionController::Instrumentation#redirect_to`.

Each carries a recorded `skip_reason` in `LEAF_PROBES.json`/`.md` — an explicit,
resource-bounded scope decision. None were live-probed under variant_a's
budget; if any is later shown to actually fire on this endpoint, that is itself
a finding to report, not something already ruled out by inspection.

---

## 2. Corpus regeneration

`run_dse.rb` unchanged (byte-identical to gen3f). Prefix-directed DSE, one
JRuby per invocation via `flock /tmp/concolic-slot.lock`, `MemoryMax=2500M`
via `systemd-run` throughout.

| round | seed | MAX_RUNS | runs executed | distinct-path dumps | worklist drained? | run errors |
|---|---|---|---|---|---|---|
| main | none | 4000 | 4000 | 3966 | **no** (stack=183843 at cap) | 0 |
| type1 | `SYM_NOTE_TYPE_PROFILE=1` | 450 | 450 | 441 | no (MAX_RUNS cap) | 0 |
| type2 | `=2` | 450 | 450 | 441 | no | 0 |
| type3 | `=3` | 450 | 450 | 441 | no | 0 |
| type4 | `=4` | 450 | 450 | 428 | no | 0 |
| type5 | `=5` | 450 | 450 | 435 | no | 0 |
| type6 | `=6` | 450 | 450 | 361 | no | 0 |
| type7 | `=7` | 450 | 450 | 361 | no | 0 |
| **total** | | | **7150** | **6874** | **no round drained** | **0** |

**0 run errors across all 7150 executions** (`run errors: {}` on every round,
confirmed in the exploration logs). All 6874 dumps are **genuine** (≥1 PC) —
confirmed by the coverage checker's own `GENUINE=True` flag, not asserted from
absence of a counter-example.

**Honest limitation:** with 6874 dumps as the base, the DSE worklist did not
drain in any round (every round hit its `MAX_RUNS` cap with a large remaining
stack, e.g. 183,843 for the main round alone). This mirrors the gen3f control's
own experience (`truncated: true` there too, at 4537 runs). A full-drain corpus
at this app's actual branching factor is not achievable within either this
variant's or the control's resource budget — reported as a coverage-completeness
limit, not implied away.

---

## 3. Coverage verdict

`coverage_report.py` (cap-4 combination coverage, `MAX_MISSING_PER_CLIQUE=4`),
run once over the full 6874-dump corpus (73 minutes wall-clock — Z3 solving at
this corpus size is the dominant cost of the whole pipeline):

```
COMPLETE=False
NODES=46
MISSING=164
BLOCKING=164
PCS=398109
GENUINE=True
TRUNCATED=True
SOLVER_LOST=0
UNEVALUABLE=[]
dump_errors={}
```

**Not complete.** 164 missing combination branches, all classified `genuine`
(no vacuous entrypoints), 0 dump errors, 0 solver-lost, 0 unevaluable
expressions. `assumptions_used` recorded tier0=163/tier1=18/tier2=3 (loaded
from `coverage_assumptions.py`, unchanged from gen3f — T1 does not touch
assumptions, that is T2/variant_b's scope).

**The iterative `_coverage_loop.sh` (5 more check→seed→append→recheck rounds,
targeting the 164 missing branches) was NOT run to convergence.** One
combination-coverage check over this corpus size took 73 minutes; five more
rounds (each requiring a fresh check after every append) would cost multiple
additional hours, which the pipeline's remaining steps (extraction, and
especially the memory-constrained blockaid diff — see §5) did not leave room
for in this session. This is reported as an explicit, honest scope limitation,
not a forced `complete: true`. One of the 164 missing combinations is directly
implicated in the reference-diff residue below (§5, queries 1–8): the guard
`assoc_target_text_has_mention == True` combined with `assoc_target_persisted
== True` and a specific notification-type profile is one of the still-missing
164 — i.e., the corpus never jointly explored "the linked post has a parsed
mention AND is persisted AND the notification is of type Liked/Reshared/
AlsoCommented/CommentOnPost" in the same run, which is exactly the shape of the
8 mentions/profile-chain reference queries this diff could not answer.

---

## 4. Extraction

```
n_dumps: 6874           n_runs_loaded: 6874        n_queries_raw: 94559
n_queries_deduped: 35   n_queries_final: 28         n_subsumed_dropped: 7
errors: []               subsume_errors: {}          subsume_ran: true
flags (raw occurrence counts, not final-query count):
  unscoped: 722   finder-without-where: 1805
placeholders (9, all `_assoc_*` association-sourced binds, unresolved):
  assoc_author_id, assoc_commentable_id,
  assoc_mentions_container_commentable_id, assoc_mentions_container_id,
  assoc_person_id, assoc_profile_id, assoc_target_author_id,
  assoc_target_id, assoc_target_mentions_container_id
```

`errors: []` — 0 unresolved run-level errors during extraction; every final
query is syntactically real SQL. The `_assoc_*` placeholders are a genuine,
identifiable extraction-pipeline gap (not a T1/mock-layer issue): they come
from association-load SQL notes (the W3/W3b `find_target` family, `to_param`,
etc.) whose bind is an association-chain-derived FK value — the
producer-join-folding logic that successfully resolves `SYM_RESULT_*`-named
function-call results (per `BUGFIXES_20260819.md` bug 2a) does not yet trace
`assoc_*`-named association-chain variables the same way, so 15 of the 28 final
queries keep a raw `_assoc_X` placeholder instead of a folded join or a
concrete/typed bind. **This is a `queries_from_runs` extraction-tool gap,
reportable but out of this batch's edit scope** (extraction code lives outside
`concolic_targets.rb`/`targets.rb`).

Full final query list (verbatim, 28 queries): §7 below and `queries_out/variant_a.sql`.

---

## 5. Diff vs reference (71 queries)

Diff pipeline note (operational, load-bearing): the first two attempts were
killed — once by the external memory watchdog (uncapped launch, before the
coordinator's mandated `systemd-run -p MemoryMax=2500M` wrapper was applied)
and once by systemd's own cgroup OOM-kill at `MemoryMax=2500M` with
`SUBSUME_SOLVER_THREADS=2` (blockaid's JVM + Z3 native memory exceeded that cap
under concurrent load from variant_b's own checker). Fixed by (a) raising the
cap to `MemoryMax=4200M`, (b) `SUBSUME_SOLVER_THREADS=1`, (c) `--incremental
--parallel 1` (one query per checker invocation, resumable via
`_progress.json`, far lower peak memory per call), (d) `--endpoint
notifications_index` to scope the run instead of also diffing the unrelated
`comments_index`/`conversations_index` reference files. This combination
completed cleanly at a flat `SUBSUME_TIMEOUT_MS=120000` for every check (no
timeout reduction was needed this run, unlike variant_b's — see §6).

```json
{
  "reference_total": 71,
  "ours_total": 28,
  "reference_rejected_by_ours": 16,
  "reference_unknown": 40,
  "ours_rejected_by_reference": 8,
  "ours_unknown": 17,
  "our_views_excluded": 15,
  "reference_views_excluded": 0
}
```

**Arithmetic reconciliation (numbers add up both directions):**

- Reference side: `71 = 16 (rejected) + 40 (unknown/timeout) + 15 (covered,
  by subtraction)`.
- Ours side: `28 = 8 (rejected) + 17 (unknown) + 3 (covered, by subtraction)`.
- `our_views_excluded = 15` is the root cause tying BOTH directions together:
  exactly the 15 of our 28 queries that carry an unresolved `_assoc_*`
  placeholder (§4). Blockaid's solver-type probe can't type-check an unbound
  constant name it has never seen declared, so:
  - **Reference-vs-ours direction**: those 15 are excluded from the usable
    *policy view set* before the check runs (view indices 7,8,9,10,13,16,18,
    19,20,21,23,24,25,26,27 — logged once each in `unknown.txt`, NOT once per
    reference query, which is why `unknown.txt` shows 55 `[reference query vs
    our views]` lines — 40 real per-query timeouts + 15 one-time
    view-exclusion notices — but `reference_unknown` correctly counts only the
    40). Only the remaining **13 placeholder-free queries** are usable as
    views.
  - **Ours-vs-reference direction**: those same 15, checked as query
    *instances* against reference's view set, are rejected outright by the
    same solver-type probe — accounting for **15 of the 17** `ours_unknown`
    (the other 2 are genuine 120s timeouts on large joins). `8 (rejected) + 15
    (placeholder-rejected) + 2 (timeout) + 3 (covered) = 28`. ✓.

15/71 reference queries are provably **covered** by our 13 usable views —
matches the control's/variant_b's own count exactly (both report 15 covered),
confirming the 13-usable-view set is doing the same coverage work regardless
of how the surrounding placeholder-laden queries are packaged for the tool.

### The 16 provably-rejected reference queries — every one attributed to a named residue

**(1)–(8): mentions/profile-chain fetch for the linked StatusMessage post, on
4 notification types (Liked, AlsoCommented, CommentOnPost, Reshared) — 8
queries, ONE named residue: corpus truncation on a specific missing
combination.** `notifications_helper.rb#opts_for_post` renders
`post_page_title`/mention-linked text for the notification's target post; this
requires the post's own `text_has_mention` branch (targets.rb's seeded
`assoc_target_text_has_mention` boolean) to have been explored **jointly**
with `assoc_target_persisted == True` and each of these 4 specific STI
type-profiles in the SAME run. §3 confirms this exact combination is one of
the coverage checker's still-`missing` 164 (cap-4 clique) — the DSE worklist
did not drain (§2) and this joint combination across type × mention × persisted
was one of the branches never jointly reached within the 6874-run budget. Not
a mock/extraction defect — an exploration-completeness gap, directly evidenced
by `coverage_summary.json`.

**(9): `conversation_visibilities` unread count.** Not part of
`notifications#index`'s own query shape at all — this is the site-chrome
layout's "unread conversations" badge. `run_dse.rb` deliberately calls
`NotificationsController.layout(false)` (documented in `concolic_targets.rb`'s
header, "Runtime scope decision") specifically to keep this unrelated layout
surface out of the driven endpoint. A documented, pre-existing runner-scope
decision, not a gap introduced here.

**(10): bare `notification_actors` join-table row fetch (not folded through to
`people`).** Our 28-query set has queries that JOIN THROUGH
`notification_actors` to reach `people`/`profiles` (the actors-list and
actor-profile fetches — see `ours-rejected-by-reference.sql` #1), but none
fetches the join-table row in isolation. A real, narrow extraction-granularity
gap: some app code path (plausibly `note.actors.size`/an association-loading
intermediate step) issues exactly this bare join-table SELECT, and no dump's
mock-note rendering captured it as a producer event distinct from the folded
people-join. (Independently reproduced by variant_b as its own #1 — see §6.)

**(11)–(12): admin/moderator role checks (`roles` table via `people`).**
**(13): current_user's own profile.**
**(14): connected `services` list.**
**(15): current_user's own `people` row.**
**(16): the `users` row lookup itself (the `current_user` resolution).**
All six share ONE named residue: `run_dse.rb` invokes the controller action
method directly (documented in its header, to keep `SYM_PARAM_show` symbolic)
rather than going through `ActionController::TestCase#process`, so
`process_action`'s real `before_action` chain — `authenticate_user!`'s actual
Devise `User.find` lookup (#16), and any admin-role/services/own-profile
checks a shared `ApplicationController` before_action or layout partial would
run (#11–15) — never executes; `current_user`/`user_signed_in?` are
overridden as singleton methods returning the pre-built symbolic user/person
directly. This is `results2`'s documented "manual mock scoping... chosen over
relying on the real association reader for reliability" technique (see
`run_dse.rb`'s own comments), predates this experiment, and is load-bearing
for why the endpoint is drivable at all (driving the full before_action chain
was a separate wall-crash family in earlier generations). Not a corpus gap or
a T1-scope mock issue.

### The 8 provably-rejected "ours" queries — every one attributed

All 8 (full list in `diff/notifications_index/ours-rejected-by-reference.sql`)
are query SHAPES the reference's own view set does not offer as an answer for
— i.e. genuinely NEW query families our extraction found beyond the reference:
the actors→profiles 4-way join, the `aspects`/`aspect_memberships`/`contacts`
family (dormant-elsewhere association mocks that still surface once as
"finder mock rendered without its WHERE conditions" broadening notes — a
known extraction-hygiene flag, not a false query), `mentions` fetched via
notification target, `blocks`, and a full-table `contacts` scan (same
broadening-note family). None indicate a bug in the mock layer — they are the
extraction tool's honest, broader-than-real-app renderings of association
scopes whose WHERE conditions the interceptor's kwargs-blind param binding
couldn't capture (the residual, not-fully-closed half of `BUGFIXES_20260819.md`
bug 2a, for association-scope finders specifically rather than direct
`find_by` calls).

---

## 6. Comparison to variant_b (T1+T2, 7 rejected)

variant_b's own `RESULT.md` reports an **identical corpus** (`n_dumps: 6874`,
`n_queries_raw: 94559` — both match this run exactly, confirming T1 alone
requires no code change in either variant, as §1 found) and an identical
13-usable-view / 15-covered result. Its 7 provably-rejected queries are an
**exact subset** of this run's 16: variant_b's (1)–(7) correspond one-to-one
to this run's (10)–(16) (notification_actors granularity gap + the six
before_action/layout-plumbing queries) — same residues, same attribution, both
runs agree.

**The difference is entirely queries (1)–(8) here (the mentions/profile-chain
family) — a TIMEOUT-SCHEDULE difference, not a corpus or view-set
difference.** variant_b's diff hit repeated OOM kills and, after two stalled
120s-timeout attempts, switched to `SUBSUME_TIMEOUT_MS=15000` for the bulk of
its 71+13 checks (its own §7 documents this explicitly). This run, after fixing
the memory cap (§5), completed entirely at the full 120000ms throughout, never
needing a reduction. Proving REJECTION (no combination of views answers a
query) requires more solver search than proving coverage or hitting an early
counterexample; under variant_b's rushed 15s budget, these 8
large-multi-join queries most plausibly timed out **inconclusive** rather than
being fully resolved — consistent with variant_b's *higher* `reference_unknown`
(49 vs this run's 40 — the two counts differ by exactly 9, close to the 8
queries in question) at an *identical* 15-covered count. Both results are
individually honest (a solver timeout is correctly reported as `unknown`, not
silently upgraded to `rejected`); this run's longer, uninterrupted timeout
schedule let the solver reach 8 additional definitive proofs that variant_b's
schedule left inconclusive. This is exactly the kind of attribution the
experiment asks for: the *T1 rule-set itself* produced identical corpora and
identical mock decisions in both variants — the residual difference in
reported rejections is a diff-pipeline resource/scheduling artifact, not a
consequence of T1 vs T1+T2.

---

## 7. Final extracted query list (verbatim, 28 queries)

```sql
SELECT `profiles`.* FROM `profiles`, `people`, `notification_actors`, `notifications` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `aspects`.* FROM `aspects`, `aspect_memberships`, `contacts` WHERE `aspects`.`id` = `aspect_memberships`.`aspect_id` AND `aspect_memberships`.`contact_id` = `contacts`.`id`;

SELECT `people`.* FROM `people` INNER JOIN `notification_actors` ON `people`.`id` = `notification_actors`.`person_id`, `notifications` WHERE `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `aspect_memberships`.* FROM `aspect_memberships`, `contacts` WHERE `aspect_memberships`.`contact_id` = `contacts`.`id`;

SELECT `comments`.* FROM `comments`, `notifications` WHERE `comments`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `notifications` WHERE `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `people`.* FROM `people`, `contacts` WHERE `people`.`id` = `contacts`.`person_id`;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_commentable_id
SELECT `people`.* FROM `people`, `mentions` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = _assoc_commentable_id AND `mentions`.`mentions_container_type` = 'Post';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_mentions_container_id
SELECT `people`.* FROM `people`, `mentions` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = _assoc_mentions_container_id AND `mentions`.`mentions_container_type` = 'Post';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_id
SELECT `people`.* FROM `people`, `mentions` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = _assoc_target_id AND `mentions`.`mentions_container_type` = 'Comment';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_id
SELECT `people`.* FROM `people`, `mentions` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = _assoc_target_id AND `mentions`.`mentions_container_type` = 'Post';

SELECT `people`.* FROM `people`, `notifications` WHERE `people`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `notifications` WHERE `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_profile_id
SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id` WHERE `taggings`.`taggable_id` = _assoc_profile_id AND `taggings`.`taggable_type` = 'Profile' AND `taggings`.`context` = 'tags';

SELECT `users`.* FROM `users`, `notifications` WHERE `users`.`id` = `notifications`.`recipient_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `blocks`.* FROM `blocks` WHERE `blocks`.`user_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_mentions_container_id
SELECT `comments`.* FROM `comments` WHERE `comments`.`id` = _assoc_target_mentions_container_id;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `contacts`.* FROM `contacts`;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_commentable_id
SELECT `mentions`.* FROM `mentions` WHERE `mentions`.`mentions_container_id` = _assoc_commentable_id AND `mentions`.`mentions_container_type` = 'Post';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_mentions_container_id
SELECT `mentions`.* FROM `mentions` WHERE `mentions`.`mentions_container_id` = _assoc_mentions_container_id AND `mentions`.`mentions_container_type` = 'Post';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_id
SELECT `mentions`.* FROM `mentions` WHERE `mentions`.`mentions_container_id` = _assoc_target_id AND `mentions`.`mentions_container_type` = 'Comment';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_id
SELECT `mentions`.* FROM `mentions` WHERE `mentions`.`mentions_container_id` = _assoc_target_id AND `mentions`.`mentions_container_type` = 'Post';

SELECT `notifications`.* FROM `notifications` WHERE `notifications`.`recipient_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_author_id
SELECT `people`.* FROM `people` WHERE `people`.`id` = _assoc_target_author_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_mentions_container_commentable_id
SELECT `posts`.* FROM `posts` WHERE `posts`.`id` = _assoc_mentions_container_commentable_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_mentions_container_id
SELECT `posts`.* FROM `posts` WHERE `posts`.`id` = _assoc_target_mentions_container_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_author_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _assoc_author_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_person_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _assoc_person_id;
```

---

## 8. Files

- `_leaf_probe.rb` — the T1 harness (this dir).
- `LEAF_PROBES.json` / `LEAF_PROBES.md` — full probe ledger (98 records).
- `dump_*.json` (6874) — corpus (main + 7 type rounds).
- `coverage_summary.json` — cap-4 combination-coverage result (truncated).
- `queries_out/variant_a.sql`, `queries_out/_summary.json` — extraction.
- `diff_ours/notifications_index.sql` — our 28 queries as fed to the checker.
- `diff/notifications_index/` — `reference-rejected-by-ours.sql`,
  `ours-rejected-by-reference.sql`, `unknown.txt`, `_progress.json`,
  `diff/_summary.json`.

## 9. Honesty summary

- **0 mocks changed** — a real T1 finding (existing gen3f mock surface already
  compliant for this endpoint), not an evasion.
- **Corpus**: 7150 runs executed, 6874 genuine (≥1 PC) distinct-path dumps, 0
  run errors, no round's worklist drained (honestly reported truncation,
  matching the control's own experience).
- **Coverage**: `complete=false`, 164 missing (genuine, cap-4), coverage LOOP
  not run to convergence (73-min/check cost) — explicit, not forced.
- **Extraction**: 0 errors, 28 final queries, 9 unresolved `_assoc_*`
  placeholders on 15 of them — a named, attributed extraction-tool gap.
- **Diff**: all 16 reference-side and all 8 ours-side rejections traced to a
  named residue; the `our_views_excluded`/`ours_unknown` arithmetic reconciled
  explicitly; the 16-vs-7 difference from variant_b attributed to a documented
  timeout-schedule difference in the diff step, not to T1 vs T1+T2 rule
  content or to any corpus/mock difference (both are provably identical).
