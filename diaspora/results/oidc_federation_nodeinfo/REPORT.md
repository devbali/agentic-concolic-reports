# oidc_federation_nodeinfo — concolic re-run (batch-local targets)

**Updated 2026-08-15 after the batch-local `targets.rb` round.** The AFTER
numbers below supersede the BEFORE table further down, which is retained for the
method write-up and the vacuous-entrypoint analysis (both still accurate).

## AFTER — all 4 genuine entrypoints branch-coverage-complete

Re-ran in 8.1 s, 225 executions, 20 dumps, **0 `error` keys**, every worklist
drained. `assumptions: []` and `assumptions_used: 0` everywhere.

| entrypoint | dumps | PCs | nodes | missing | complete | kind |
|---|---|---|---|---|---|---|
| `access_tokens_create` | 4→4 | 9→9 | 3→3 | 0→0 | true→true | genuine |
| `authorizations_create` | 8→8 | 25→25 | 7→7 | 0→0 | true→true | genuine |
| **`webfinger`** | 5→**3** | 17→**6** | 5→**3** | **2→0** | **false→true** | genuine |
| `host_meta` | 1→1 | 0→0 | 0→0 | 0→0 | true* | VACUOUS |
| `node_info_show` | 1→1 | 0→0 | 0→0 | 0→0 | true* | VACUOUS |
| `federation_receive_public` | 1→1 | 0→0 | 0→0 | 0→0 | true* | VACUOUS |
| `federation_receive_private` | 2→2 | 2→2 | 1→1 | 0→0 | true→true | genuine |

`webfinger`'s counts went **down** because 11 of its 17 "PCs" were never
decisions. Judge this row by missing/complete, not by PC count.

## How `webfinger` was closed — a subclass, not a mock

`targets.rb` defines **`MarkerFreeSymbolicString < SymbolicString`** whose
`MarkerFreeSplitAccessor#[]` reproduces `src/ruby_runtime/string.rb:256-298`
exactly — same offsets, same bounds errors, same `SymbolicSubstring` results with
the same `SubString(parent, start, len)` Z3 expressions — **minus the three
`record!` calls** that pushed non-decisions into the tree. A batch-local wrapper
around `ConcolicTargets.symbolic_instance` re-wraps string columns in it,
preserving name / seed / note.

`declare_target` is **not used in this file at all.** `Person#username` still
runs for real (verified: `Entity.validate` still fires, the JRD still renders),
and `username` is still `SubString(<handle>, …)` of the same variable — the
symbolic dependency survives.

**A `Person#username` mock was tried first, then removed.** It is legal (the body
has no `if`; `||=` is ivar memoisation) and gave the identical 3-node / 0-missing
result — but it silently dropped the `username == substring(diaspora_handle)`
dependency. The subclass gets the same coverage without that loss.

**Trap worth propagating:** `SymbolicString#to_s` is **identity**
(`string.rb:65-76`, returns `self`). A first attempt computed
`handle.to_s.split("@")`, which re-entered the *symbolic* split and re-emitted
the very markers — `webfinger` went from 5 PCs/run to 9. Use `.value`.

## UntrackedPathAssumption — evaluated with numbers, then declined

Re-ran the checker over the preserved BEFORE dumps:

| | nodes | missing | blocking | complete | used |
|---|---|---|---|---|---|
| BEFORE strict | 5 | 2 | 2 | **false** | 0 |
| BEFORE + `UntrackedPath(person.rb:270 username)` | 5 | 2 | **0** | **true** | 2 |

It **would have worked**, and targets exactly the right source line (that line
holds nothing but the split). It was **not shipped**: it is strictly weaker than
the fix — strict gives complete with *0* missing rather than *2 excused*, it
leaves the distorted 5-node tree in place, and it is a standing claim where a
subclass that provably never calls `record!` is checkable in 20 lines.
Completeness here rests on observation, not on a declared assumption. Zero
assumptions still stands across all 13 batches.

## Findings for Bali (`src/` untouched — `string.rb` verified unmodified)

1. **`string.rb:275/284/291`** — split markers pushed as `PathCondition`s with
   `taken: true` hard-coded. An unclosable false-incomplete on *any* symbolic
   string split.
2. **NEW — same lines: `Contains` arguments are reversed.** Z3's `Contains(a,b)`
   means "a contains b"; the runtime emits `Contains(<separator>, <string>)`.
   That is why the checker's witness for the missing side was
   `diaspora_handle = ""`. It does not affect completeness (taken is hard-coded
   anyway), but the solver's witnesses for those nodes were nonsense.
3. **`CoverageChecker._insert_run` absorption is no longer exhibited here.**
   BEFORE: independent tree 9 nodes / 7 one-sided vs engine 5 / 2 — the divergent
   marker sequences were the cause. AFTER: independent reconstruction matches the
   engine exactly on all 7 entrypoints. The engine bug still stands; this batch
   simply stopped triggering it.
4. `CallInterceptor#@all_calls` unbounded growth — still worked around
   runner-locally.

`unflippable_pcs` is now empty for every entrypoint (was 6 × `IndexOf(…)==0`).
The one remaining one-sided node (`guid != ''` under a `guid == ''` prefix) is
correctly UNSAT-pruned by Z3, not missing.

The session-seeding harness fix is in-tree at `run_dse.rb:250-262`, and the
checker is now in-tree as `coverage_report.py`, so the batch dir reproduces
itself standalone.

---

# BEFORE record (pre-overlay) — retained for method + vacuous analysis

Runner: `run_dse.rb` + batch-local overlay `targets.rb` (this directory),
launched via `concolic-slot`. Batch wall time **8.1 s**, 225 controller
executions across 7 entrypoints, **0 crashed runs, 0 `error` keys in all 20
dumps**.

Coverage is checked **per entrypoint** over that entrypoint's own dumps only
(`coverage_report.py`, this directory), with **zero assumptions** — every
`complete=true` below is strict per-node observation. The `assumptions` field of
each `coverage_summary.json` is now serialized from the engine itself rather
than hard-coded, so it cannot silently disagree with what the checker applied.

Nothing under `src/`, `concolic_targets.rb`, or the diaspora app was modified.

## 1. Results — BEFORE vs AFTER

BEFORE = previous round, shared targets only. AFTER = with `targets.rb`.

| entrypoint | dumps | PCs | nodes | missing | complete | kind | worklist |
|---|---|---|---|---|---|---|---|
| `access_tokens_create` | 4 → **4** | 9 → **9** | 3 → **3** | 0 → **0** | true → **true** | genuine | drained (21 runs) |
| `authorizations_create` | 8 → **8** | 25 → **25** | 7 → **7** | 0 → **0** | true → **true** | genuine | drained (189 runs) |
| `webfinger` | 5 → **3** | 17 → **6** | 5 → **3** | **2 → 0** | **false → true** | genuine | drained (9 runs) |
| `host_meta` | 1 → **1** | 0 → **0** | 0 → **0** | 0 → **0** | true* → true* | **VACUOUS** | drained (1 run) |
| `node_info_show` | 1 → **1** | 0 → **0** | 0 → **0** | 0 → **0** | true* → true* | **VACUOUS** | drained (1 run) |
| `federation_receive_public` | 1 → **1** | 0 → **0** | 0 → **0** | 0 → **0** | true* → true* | **VACUOUS** | drained (1 run) |
| `federation_receive_private` | 2 → **2** | 2 → **2** | 1 → **1** | 0 → **0** | true → **true** | genuine | drained (3 runs) |

`*` complete only because the tree is empty — a vacuous entrypoint is NOT
covered, whatever the checker says.

**4/7 genuine, 3/7 vacuous. All 4 genuine entrypoints are now
branch-coverage-complete (was 3/4).** Every worklist drained
(`worklist_exhausted: true` for all 7); no cap was hit. Total runs 243 → 225.
**Zero `error` keys** — no walls were hit anywhere in this batch, so `targets.rb`
adds no wall mocks; it contains exactly one item (§3.3.2).

`webfinger`'s raw PC and node counts went **down** while its coverage went
**up**. That is the point: 11 of its 17 "path conditions" were never decisions
(§3.3.1), and removing them collapsed 5 tree nodes into the 3 real ones. Judge
that row by `missing`/`complete`, not by volume. Also gone: `unflippable_pcs` is
now empty for every entrypoint (was 6 occurrences of `IndexOf(…) == 0`).

### The engine's sibling-absorption discrepancy is gone from this batch

`CoverageChecker._insert_run` reuses a `taken`/`not_taken` child without
checking the child's constraint matches the next PC's expression, so runs whose
PC *sequences* diverge get silently absorbed into whichever shape was inserted
first. BEFORE, rebuilding `webfinger`'s prefix tree independently of the engine
gave **9 nodes with 7 one-sided** against the engine's **5 / 2 missing**.

AFTER, I re-ran the same independent reconstruction for all 7 entrypoints: the
node counts now match the engine **exactly** everywhere. The absorption was
caused precisely by the divergent split-marker sequences (§3.1). The engine bug
itself is unfixed and still worth raising; this batch no longer exhibits it.

## 2. Method

Prefix-directed DSE per the briefing: from an observed path `[c0 … cn]`, emit
one child per `k` inheriting the parent's seeds plus exactly one flip for `c_k`;
dedup on path signature; expand until drained.

This batch reproduces the ordinal-instability directly. In
`authorizations_create`, `SYM_RESULT_..._find_by_1` is the `OAuthApplication`
lookup in `Endpoint#build_client` — but once the `redirect_uris` check fails,
the rescue path fires a **second** `OAuthApplication.find_by`
(`find_by_2`, `authorizations_controller.rb:184`), and in the
`find_by_1_not_found = true` runs (`dse0021`–`dse0023`) `find_by_2` denotes a
different call site again. Feeding `concrete_values` back wholesale would mix
those.

`flip_seed` had to be generalised well beyond the reference runner's
`(VAR == LITERAL)` regex — this batch's PCs are string-heavy:

| shape | source | flippable |
|---|---|---|
| `(VAR == True/False)` | `finder_mock` not-found bool | yes |
| `(VAR == StringVal('x'))`, `(VAR == 'x')` | `SymbolicString#==` | yes |
| `(VAR != StringVal('x'))` | `SymbolicString#!=` | yes |
| `Contains(StringVal('x'), VAR)` | `SymbolicString#include?` | yes |
| `Not(Contains(StringVal('x'), VAR))` | `String#split` marker (BEFORE only) | yes (recursed) |
| `IndexOf(VAR, StringVal('@')) == 0` | `String#split` marker (BEFORE only) | **no** (§3.3.1) |

Unflippable shapes are counted in `exploration_summary.json → unflippable_pcs`,
never dropped. BEFORE, one shape occurred 6 times in `webfinger`; AFTER, the
map is **empty for every entrypoint** — the two `String#split` rows no longer
occur at all (§3.3.2), so every PC this batch records is now flippable.

### Runner-local workaround for a `src/` leak (reported, not patched)

`CallInterceptor` appends every intercepted call to `@all_calls`
(`src/ruby_runtime/call_interceptor.rb:69`, appended at `:127`) and `run` only
*slices* `@all_calls[old_count..]` for the dump (`:308`) — nothing is ever
released, so a long DSE loop grows the JVM heap monotonically. `run_dse.rb`
clears the array after each run (safe: `run` re-reads `@all_calls.size` as its
base offset each time). **`src/` was not modified.**

## 3. Per-entrypoint findings

### 3.1 `access_tokens_create` — POST /api/openid_connect/access_tokens — genuine, complete

`TokenEndpointController#create` → the real `Rack::OAuth2::Server::Token` app.
Driven with a realistic `authorization_code` grant so it gets past rack-oauth2's
own validation and reaches the database. 3 nodes, all two-sided:

1. `find_by_1_not_found` — `OAuthApplication.find_by client_id:`
   (`token_endpoint.rb:51`). True ⇒ `req.invalid_client!`.
2. `find_by_1_client_secret == StringVal('concolic_secret')` — `app_valid?`
   (`token_endpoint.rb:55`). A real symbolic-string comparison of a DB column
   against the request secret; both outcomes exercised.
3. `find_by_2_not_found` — `Authorization…use_code(req.code)`
   (`authorization.rb:79`). True ⇒ `req.invalid_grant!`; false ⇒
   `create_access_token` (mocked persistence fires at `authorization.rb:82`).

`req.grant_type` is a Rack parameter, so the `refresh_token` /
unsupported-grant arms are separate concrete scenarios, not symbolic branches.
`auth.accessible? "openid"` is not reached on any explored path.

### 3.2 `authorizations_create` — POST /api/openid_connect/authorization — genuine, complete

7 nodes, 8 distinct paths, 189 executions to drain.

**Harness note (setup, not app logic):** `#create` starts with
`restore_request_parameters`, which overwrites every OAuth param from the
session that `#new` wrote. With an empty session, `response_type` becomes `""`
and `Endpoint` hits `req.unsupported_response_type!` immediately — the entire
consent path is dead. That is what the previous `run_concolic.rb` measured.
`run_dse.rb` seeds the session with exactly what `save_request_parameters` would
store. PC count went 2 → 4 max; distinct paths 3 → 8.

**Durability (checked, per the coordinator's item 3):** this fix is not a
scratch artifact. It lives in **`run_dse.rb:250-262`** — the `session:` argument
to `drive`, preceded by an 8-line comment stating that it is harness setup and
not app logic — so it is exercised by every re-run of the batch, survives
`ONLY=` runs, and is described here and in §1. The two other reusable inputs are
likewise in-tree: `targets.rb` (the split-marker subclass) and
`coverage_report.py` (the per-entrypoint checker, previously only in the job tmp
dir). `reports/diaspora/results/oidc_federation_nodeinfo/` now reproduces the
whole batch on its own.

Branch points: `find_by_1_not_found` (`build_client`);
`find_by_1_redirect_uris == StringVal('http://localhost:3000/cb')` — inside
**rack-oauth2 itself** (`authorize.rb:58`, `verify_redirect_uri!`);
`find_by_2_not_found` + `Contains(…, find_by_2_redirect_uris)` — the rescue path
`handle_params_error_when_client_id_and_redirect_uri_exists`
(`authorizations_controller.rb:184`/`:192`); and
`FinderMethods.find_by_1_not_found` — `Authorization.find_or_create_by!` in
`EndpointConfirmationPoint#find_or_build_auth`, both sides (`dse0008` found ⇒
`create_code`/`update!`; `dse0009` not found ⇒ `create!`).

### 3.3 `webfinger` — GET /.well-known/webfinger — genuine, **complete** (was incomplete)

Reaches the real query with real SQL in the note:

```
SELECT "people".* FROM "people" WHERE "people"."diaspora_handle" = 'alice@example.org'
  AND "people"."closed_account" = 0 AND "people"."owner_id" IS NOT NULL ...
```

(`config/initializers/diaspora_federation.rb:17`, `fetch_person_for_webfinger`).
Both controller outcomes are reached: `head :not_found` on finder miss
(`dse0004`), and the JRD render on hit — with the
`DiasporaFederation::Entity#validate` §X mock firing on the constructed
`WebFinger` entity.

#### 3.3.1 The defect that made this entrypoint permanently incomplete

`webfinger` reaches `Person#username` (`app/models/person.rb:270`) through
`person.profile_url` / `person.atom_url` while building the JRD entity:

```ruby
@username ||= diaspora_handle.split("@")[0]
```

`SymbolicString`'s split accessor (`src/ruby_runtime/string.rb:256-298`) records
three **structural markers** as `PathCondition`s with **`taken: true`
hard-coded**:

```
Contains(StringVal('@'), <suffix>)        # separator found
IndexOf(<suffix>, StringVal('@')) == n    # ...at this offset
Not(Contains(StringVal('@'), <suffix>))   # no separator
```

They are *assertions about a concrete value*, not evaluated decisions. No
execution can ever observe their other side, so strict per-node coverage
demanded a `taken: false` that **cannot exist** — permanently, on *any*
entrypoint that splits a symbolic string. Here it was 2 unclosable missing
branches, one per `guid` prefix.

Flipping did not help and could not: the DSE *did* generate a handle containing
`@`, but that run recorded the syntactically **different** node
`Contains(StringVal('@'), …)`, also only ever `taken: true`. Path signatures
compare as strings, so the two never unified — they just doubled the tree, which
is what triggered the engine's sibling absorption (§1). `IndexOf(…) == 0` was
additionally unflippable (its LHS is a function application, not a bare
variable): the batch's only unflippable shape, 6 occurrences.

**Aside, raised not worked around:** the marker's arguments are also *reversed*.
Z3's `Contains(a, b)` means "a contains b", so `Contains(StringVal('@'), handle)`
asserts that `"@"` contains the handle — which is why the checker's witness for
the missing side was `diaspora_handle = ""`. Correcting the direction would not
make the node two-sided (`taken: true` is still hard-coded), so it is irrelevant
to completeness, but it is a real defect in
`src/ruby_runtime/string.rb:275/284/291`.

#### 3.3.2 The fix: a subclass, not a mock

`targets.rb` defines `MarkerFreeSymbolicString < SymbolicString`, whose
`MarkerFreeSplitAccessor#[]` reproduces the shared accessor's logic exactly —
same offsets, same bounds errors, same `SymbolicSubstring` results carrying the
same `SubString(parent, start, len)` z3 expressions — **minus the three
`record!` calls**. A batch-local wrapper around
`ConcolicTargets.symbolic_instance` re-wraps every plain-`SymbolicString` column
value in the subclass, preserving name, seeded value and note, so seeding and
flipping are unchanged.

`declare_target` is not used anywhere in `targets.rb`. No app method is
replaced, no query is hidden, and `Person#username` still **runs for real** —
verified in the dumps: `DiasporaFederation::Entity.validate` still fires on the
constructed `WebFinger` entity and the JRD still renders.

Two properties this preserves that the obvious alternative destroys:

- **The branch is not swallowed.** `username`'s body still executes, so if it
  ever grew a conditional that branch would still be observed. (The photos
  batch's `Profile#build_image_url` lesson: a mock that swallows the branch it
  guards is a regression, not a fix.)
- **The symbolic dependency survives.** `username` is still
  `SubString(<handle>, 0, …)` of the same variable, so a future branch on a
  username is solved together with the handle's constraints.

**Rejected intermediate attempt, recorded because it is instructive.** I first
mocked `Person#username` with a seed-aware `symstr`. That is legal by the
addendum's most-important rule — the body contains no `if`; `||=` is ivar
memoisation and emits nothing, so there is no branch to swallow — and it
produced the identical 3-node / 0-missing result. But it silently dropped the
`username == substring(diaspora_handle)` dependency. The subclass gives the same
coverage without that loss, so the mock was removed. Per the coordinator's
"don't add mocks you don't need": this batch adds none.

That attempt also produced a trap worth recording: **`SymbolicString#to_s` is
identity** (`string.rb:65-76` — it returns `self` so interpolation keeps tracking
alive). A mock body computing `handle.to_s.split("@")` therefore re-enters the
*symbolic* split and re-emits the very markers it is meant to remove; the first
version of `targets.rb` took `webfinger` from 5 PCs/run to 9. Use `.value` when
a mock needs a concrete string.

#### 3.3.3 The resulting tree — three real nodes, all accounted for

```
(finder first_1_not_found == True)      taken ✓ / not_taken ✓   concolic_targets.rb:331
└─ not_taken:
   (first_1_guid == '')                 taken ✓ / not_taken ✓   activesupport blank.rb:126
   └─ taken:
      (first_1_guid != StringVal(''))   not_taken ✓ only        Journey formatter.rb:41
```

The third node is one-sided **and that is correct**: its prefix already asserts
`guid == ''`, so `guid != ''` is unsatisfiable there. Z3 confirms UNSAT, which
is why it is not reported missing (`solver_lost: 0`).

#### 3.3.4 The `UntrackedPathAssumption` — evaluated, and deliberately not used

I was asked to evaluate this properly rather than refuse it reflexively, so I
measured it. Re-running the checker over the **BEFORE** dumps with

```python
UntrackedPathAssumption(source=PathSource(file=".../app/models/person.rb",
                                          lineno=270, function="username"))
```

gives:

| | nodes | missing | blocking | complete | assumptions_used |
|---|---|---|---|---|---|
| BEFORE, strict | 5 | 2 | 2 | **false** | 0 |
| BEFORE + UntrackedPath | 5 | 2 | **0** | **true** | 2 |

So the assumption **would have worked**; it targets exactly the right source
(`person.rb:270` holds nothing but the split, so untracking it untracks the
markers and nothing else); and the engine serializes it with file/line for
audit. It would have been the one legitimate assumption in the whole experiment
— its justification is a checkable fact about the instrumentation, not a guess
about program behaviour.

**It is nevertheless not used, because it became unnecessary and is strictly
weaker.** Closing a node honestly beats declaring it untracked:

- The strict route reports `complete=true` with **0 missing branches**; the
  assumption route reports `complete=true` with 2 missing branches excused.
- The assumption leaves the distorted 5-node tree (and the engine's absorption
  artifact) in place; removing the markers yields the 3 real nodes.
- An assumption is a standing claim every future reader must re-verify. A
  subclass that provably does not call `record!` is checkable by reading 20
  lines.

**For the record: this entrypoint's completeness does NOT rest on any declared
assumption.** All seven `coverage_summary.json` files carry `"assumptions": []`
and `"assumptions_used": 0`; every green number in this batch is strict
per-node observation. The evaluation script is kept at
`/home/dev/.claude/jobs/302ac302/tmp/oidc_assumption_probe.py`, with the BEFORE
dumps preserved at `/home/dev/.claude/jobs/302ac302/tmp/oidc_before/`.

The general defect is unchanged and still belongs in `src/`: split markers
should not be pushed as `PathCondition`s at all. Every batch that splits a
symbolic string will hit this; only this one carries a batch-local subclass
around it.

### 3.4 `federation_receive_private` — POST /receive/users/:guid — genuine, complete

1 node, both sides. `queue_private_receive`
(`initializers/diaspora_federation.rb:97`) does `Person.find_by_guid(guid)`; the
finder PC decides `head :accepted` vs `head :not_found`. Found ⇒ the `owner`
singular association fires and `Workers::ReceivePrivate.perform_async` hits the
mocked `Sidekiq::Client.push`.

**Two real app branches cannot be recorded** (Ruby truthiness gap,
`src/TODO.txt`): `person.present? && person.owner_id.present?`.
`Object#present?` is `!blank?`, and `blank?` on a `SymbolicInt` reduces to
`!self` — bare truthiness, no PC. So the "person exists but has no owner" 404
arm is invisible to the tree. The `head success ? :accepted : :not_found`
decision is likewise made on a concrete boolean produced by `.tap`.

## 4. The three vacuous entrypoints — why, precisely

None is a crash or a wall; all three completed normally and reached their
terminal render/head.

**`host_meta` — vacuous by construction.** `render xml:
WebfingerController.host_meta_xml`, where `host_meta_xml` is a class-level
`@host_meta_xml ||=` memo built from static config. No DB, no
request-dependent value, no conditional. The trace is exactly two events:
`render` and `default_render`. There is nothing here to cover.

**`node_info_show` — config-gated.** `NodeInfo.supported_version?(params[:version])`
compares a routed Rack parameter (a plain `String`) against a literal list — not
symbolic. The presenter *is* fully built during argument evaluation
(`document.content_type` is evaluated before `render`; confirmed by trace
ordering), but issues **zero queries**: all DB counts (`User.active.count`,
`monthly_actives`, `halfyear_actives`, `Post…count`, `Comment…count`) sit behind
`AppConfig.privacy.statistics.{user,post,comment}_counts?`, which
`config/defaults.yml:79-82` sets `false` and `config/diaspora.yml` leaves
commented out. Even enabled, the counts are only serialised into JSON, never
compared — `symbolic_call` events but still no PC.

**`federation_receive_public` — no data-dependent branch.** Touches no database
at all: unescapes `params[:xml]`, fires `Workers::ReceivePublic.perform_async`
(mocked `Sidekiq::Client.push`, visible in the trace with the real job payload),
`head :accepted`. Its two real branches read Rack request attributes the harness
supplies concretely (`request.content_type != "application/magic-envelope+xml"`;
`params[:xml].nil? && legacy_request`) — the interceptor's symbolic kwargs
cannot reach inside `ActionDispatch::Request`. Driving them means extra
**concrete scenarios** that would still contribute 0 PCs, so no dumps were
manufactured for them.

## 5. Branches the runtime cannot record

| where | branch | why invisible |
|---|---|---|
| `initializers/diaspora_federation.rb:100` | `person.present? && person.owner_id.present?` | truthiness gap — `blank?` → `!self` on `SymbolicInt` |
| `receive_controller.rb:19` | `legacy = request.content_type != …` | Rack request attribute |
| `receive_controller.rb:40` | `params[:xml].nil? && legacy_request` | ditto |
| `node_info_controller.rb:9` | `NodeInfo.supported_version?(params[:version])` | routed param is a plain `String` |
| `token_endpoint.rb:22` | `case req.grant_type` | Rack request parameter |
| `webfinger_controller.rb:78` | `if person_wf.nil?` | bare truthiness — but equivalent to the finder's `not_found` PC, which IS recorded, so no coverage is lost |

`person.rb:270`'s split markers used to sit in this table. They are no longer
recorded at all (§3.3.2), and they were never a branch to begin with — no app
decision was lost by removing them.

## 6. Errors, and mocks

**Errors: none.** All 20 dumps across all 7 entrypoints have no `error` key — no
real app exception (no `ActiveRecord::RecordNotFound` etc.), no environment
wall, no `src/` gap reached at runtime. Nothing in this batch needed a wall
mock, and `targets.rb` adds none: its only content is the
`MarkerFreeSymbolicString` subclass plus the `symbolic_instance` wrapper that
routes string columns through it (§3.3.2), and a written record of what was
deliberately *not* mocked and why.

Shared mocks this batch exercises unchanged:
`ActionController::Rendering.render` / `ImplicitRender.default_render` /
`Head.head` / `Metal.status=` (§Z), `Sidekiq::Client.push` (#11),
`Gon::ControllerHelpers.gon`, `Rendering._set_rendered_content_type`, and
`DiasporaFederation::Entity#validate` (§X, firing on the real `WebFinger`
entity).

Checked per the addendum: no shared mock this batch depends on is missing a
`seed_for` call (the `Photo#url` inert-mock failure mode does not occur here) —
every PC observed in these dumps was successfully flipped by the DSE, and
`unflippable_pcs` is empty for all 7 entrypoints.

## 7. Raised to `src/`, not patched

1. **`src/ruby_runtime/string.rb:275/284/291` — split markers pushed as
   `PathCondition`s with `taken: true` hard-coded.** Facts about a concrete
   value, not decisions, so strict per-node coverage reports an unclosable
   missing branch on *any* entrypoint that splits a symbolic string. Worked
   around batch-locally by a `SymbolicString` subclass (§3.3.2); the general fix
   is to stop recording them (or to record them as untracked).
2. **Same lines — the `Contains` arguments are reversed.** Z3's `Contains(a, b)`
   is "a contains b"; the runtime emits `Contains(<separator>, <string>)`, which
   made the solver's witnesses for those nodes nonsense (`diaspora_handle = ""`).
3. **`CallInterceptor#@all_calls` grows without bound.** Every intercepted call
   is appended (`call_interceptor.rb:69`, appended at `:127`) and `run` only
   *slices* `@all_calls[old_count..]` for the dump (`:308`) — nothing is ever
   released, so a long DSE loop grows the JVM heap monotonically. `run_dse.rb`
   clears the array after each run (safe: `run` re-reads `@all_calls.size` as
   its base offset each time). **`src/` was not modified.**
4. **`CoverageChecker._insert_run` sibling absorption** (coordinator's finding):
   it reuses a `taken`/`not_taken` child without checking that the child's
   constraint matches the next PC's expression. This batch no longer triggers it
   (§1), but the bug stands.

Also worth knowing for anyone writing a `targets.rb`: **`SymbolicString#to_s`
returns `self`** (`string.rb:65-76`). Use `.value` when a mock needs a concrete
string, or the mock body silently re-enters symbolic operations (§3.3.2).

## 8. Reproduce

```bash
/home/dev/.claude/jobs/302ac302/tmp/concolic-slot \
  /home/dev/project/reports/diaspora/results/oidc_federation_nodeinfo/run_dse.rb
# env: MAX_RUNS (default 400), TIME_BUDGET (default 420s, per entrypoint), ONLY=<names>

cd /home/dev/project && PYTHONPATH=src python3 \
  reports/diaspora/results/oidc_federation_nodeinfo/coverage_report.py
```

The checker prints `Failed to eval var decl 'len(SYM_RESULT_…) = Int(…)'`
warnings for `SymbolicList` length vars — a known engine warning; it does not
affect the results.

## 9. Verification

- The batch was re-run end to end with the overlay (RC=0, 8.1 s) and every
  `coverage_summary.json` recomputed over the fresh dumps. All 20 dumps parse
  (`dumps_unparseable: []`), all runs reached a terminal state, no dump was
  deleted, no dump carries an `error` key.
- Independent prefix-tree reconstruction (outside the engine) agrees with the
  engine's node count for all 7 entrypoints.
- The `assumptions` field is serialized from the engine's own
  `assumptions_to_dict()`, and is `[]` with `assumptions_used: 0` everywhere.
- Unaffected by the earlier cross-batch `pkill -f run_dse.rb` incident; `pkill`
  was never used by this agent.
- All runs went through `concolic-slot`; `diaspora-concolic` was never called
  directly.
