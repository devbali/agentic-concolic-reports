# The auto-lab shakedown, run 2 — 161 of 161 scaffolded endpoints,
# against the FIXED target library

Run 2026-09-26 01:40 → 04:31 UTC, under `RAILS_ENV=concolic_mod`.
Spec: `src_new/README.md` §"The shakedown". Machine-readable: `SUMMARY.json`.
Per-endpoint checkpoint: `manifest.jsonl` (161 rows — 161 endpoints, no
re-drive). Before/after data: `BEFORE_AFTER.json`.

**Run 1 is preserved intact at
`_trash/autolab_history_20260930/shakedown/_run1_20260925/`** (relative to the
project root) — its `REPORT.md`, `SUMMARY.json`, `manifest.jsonl`, `runs/`,
`logs/`, `results/`, `sweep.out` and `_env_concolic/` are all there,
unmodified. Nothing was deleted.

> **Moved 2026-09-30, repointed 2026-10-03.** This paragraph said
> `_run1_20260925/`, i.e. a sibling of this file, until the retirement sweep
> moved it to the trash tree; see `_trash/autolab_history_20260930/_RETIRED.md`.
> Two agents read the dangling path as data loss, which is why the pointer is
> now absolute-from-root and why the emptied source directory carries a
> pointer file of its own.

**Why this re-run.** The shared target library was repaired for the D1–D8
write-note defects plus N1/N4/N5/N6, and two declarations changed `kind:`
`SHIM` → `TARGET_FUNCTION`
(`ActiveRecord::Associations::CollectionProxy#create`,
`PostService#mark_user_notifications`), so run 1's 286 dumps recorded kind
values that no longer matched the library.

## 0. The comparison in one paragraph

**Nothing regressed, and almost nothing moved.** Every bucket, every set and
every failure message is identical to run 1. Four things changed, all of them
expected: the 322 kind conflicts are gone; every endpoint's declared
target-function count rose by exactly 2; one endpoint gained a real `DELETE`
where it had carried prose; and one endpoint gained one recorded write access
and timestamp columns on three statements. Target-function **reach did not move
at all** — not one endpoint, not one target, not one dump.

---

## 1. The counts, kept separate

| outcome | run 2 | of 161 | run 1 |
|---|---:|---:|---:|
| **ran clean** — every stage ran, checker returned a verdict | **154** | 95.7 % | 154 |
| **ran but produced no paths** — no dump written | **0** | 0 % | 0 |
| **failed** — a named stage failed | **7** | 4.3 % | 7 |
| harness error | 0 | 0 % | 0 |
| not attempted | 0 | 0 % | 0 |

**All 161 checker runs returned `complete: false`. Zero returned `true`** — the
result the spec asks for. A `true` on two dumps would itself have been the
defect.

The buckets are identical *as sets*, not merely as counts: the same 154
endpoints ran clean and the same 7 failed. Measured by comparing the two
manifests endpoint-by-endpoint (`tools/compare_runs.py`).

Two sub-counts inside *ran clean*, deliberately not folded in:

* **36 of 154 wrote a dump carrying ZERO path conditions** — the same 36
  endpoints as run 1. Every stage passed, but no branch exists for the verdict
  to be about. Full list in `SUMMARY.json`.
* **39 of 161 reached zero declared target functions** (§5) — the same 39.

PC distribution in the chosen dump: `0:36, 1:7, 2:113, 3:2, 4:1, 6:1, 16:1` —
identical to run 1, and `path_condition` events across the whole corpus are
**411 in both runs**. The fixes changed no control flow.

Dump IR: **286 dumps written, 286 accepted** by `Run.from_dict` +
`validate_provenance` (R1–R4). No `MissingKind`/`MissingType` at install
anywhere. No undefined name in a note's `refs` anywhere. Same 286 as run 1,
and the same number of dumps per endpoint for every endpoint.

### What this run does NOT establish — unchanged, and stated deliberately

Only the **coverage layer** ran. `run_complete` was called **with no config**
(`tools/pipeline.py:359`), so the mocks/shims, declared, confinement,
conjunction and §16b-foreclosure gates did not run. Every endpoint's `blocking`
list says so verbatim, all 161 identical:

```
no config given: mocks/shims and every gate
(declared/confinement/conjunction/§16b-foreclosure) were not run
```

A concurrent agent fixed the `CompletionConfig`/`extract_cmd` defect
(`src_new/concolic/checks/run.py:114-119` now skips a step whose keys are
absent, blockingly, spelling "did not run" as `None`) — but **that fix landed
at 02:32 UTC, while this sweep was running, and it does not change what this
run measured.** The caveat stands exactly as it stood for run 1: a clean result
here means the machinery runs end to end, **not** that these endpoints are
gate-clean. See §8 for how I verified the mid-run change was inert.

---

## 2. Every failure, named individually — the same 7, the same two classes

All seven failure messages are **byte-identical to run 1**. Both classes are
unfixed, and one of them has a new diagnosis.

### F1 — `opaque` reaches the policy (6 endpoints)

`devise_passwords_create`, `devise_passwords_edit`, `devise_passwords_new`,
`devise_passwords_update`, `registrations_new`, `sessions_new` — all at stage
`build_policy`, identical text:

> `opaque reached the policy at: sig DeviseController#devise_mapping->returns`

Origin: `reports/autolab/targets/core.rb:2001-2002` declares
`DeviseController#devise_mapping` with `kind: SHIM, type: "opaque"`.
*(Run 1's report cited `core.rb:1370-1372`; that citation has rotted — the live
file has the declaration at 2001-2002, verified by grep this run. Every line
number in this report was re-verified against the live files.)*

**Scope, measured:** all **161** endpoints *declare* this target — it is in the
shared core — and exactly **6** *call* it. Those 6 are the 6 failures.

#### This is a defect in the CHECK, not in the corpus and not in the builder

Run 1 reported F1 as an open question with two candidate fixes. One of those
candidates is now ruled out, and the diagnosis has moved:

* **Eliding no-atom signatures is not available.** It contradicts a documented,
  tested decision: `src_new/dumps_to_policy/normalize.py:341` reads "AN ELIDED
  TARGET KEEPS ITS `sig` LINE, deliberately … dropping it would leave the
  policy smaller with no trace of why — which is the failure §9 names."
* **The actual defect is a false sentence in the spec.**
  `src_new/README.md:333` asserts "**every `opaque` sits behind a `SHIM`**, so
  none of them can reach a policy." The first half is an invariant about
  *kinds*. The second half does not follow: a shim is never an *access*, so it
  contributes no ATOM — but it still contributes a SIGNATURE, and a signature
  carries its declared return type. All six policies have `atoms=0` and the
  `opaque` still reaches the policy through the signature table.
* **`tools/pipeline.py:218` (`has_opaque`) was built on that false sentence.**
  It treats any `opaque` reaching a policy as a defect, when reaching a policy
  through a signature is exactly what the design says should happen.

So F1 is reported here as **a harness/spec defect surfacing as 6 endpoint
failures**, not as 6 broken endpoints. I did not fix it — that is a `src_new`
and a shared-core question, and neither is mine to take unilaterally.

**The check's real blast radius is wider than the 6.** The library declares
**five** `opaque` targets, and `opaque?` (nullable) preserves the kind, so all
five are in scope. Measured across all 286 dumps:

| opaque target | declared | type | called |
|---|---:|---|---:|
| `DeviseController#devise_mapping` (`core.rb:2001`) | 161 eps | `opaque` | **6 eps** |
| `DiasporaFederation::Entity#validate` (`core.rb:2153`) | 161 eps | `opaque?` | **1 ep** |
| `Gon::ControllerHelpers#gon` (`core.rb:2196`) | 161 eps | `opaque` | 0 |
| `ApplicationController#configure_permitted_parameters` (`core.rb:2530`) | 161 eps | `opaque?` | 0 |
| `…BelongsToPolymorphicAssociation#klass` (`endpoints/comments_index.rb:607`) | 1 ep | `opaque` | 0 |

**7 of 161 endpoints call an opaque-typed target, not 6.** The seventh is
`diaspora_federation_h_card_hcard`, whose chosen dump calls
`DiasporaFederation::Entity#validate` — it would also have tripped `has_opaque`
had `build_policy` not refused the dump first (F2). **F2 masks a second
F1-class hit**, verified by reading the chosen dump's call events directly.
The other four core declarations are latent on all 161 endpoints and fire
wherever their path is taken.

### F2 — a path condition the builder cannot represent (1 endpoint)

`diaspora_federation_h_card_hcard`, stage `build_policy`, message byte-identical
to run 1:

> `run 'anon_html_dse0001': path condition at idx 3 is not representable:`
> `"Not(Contains(StringVal('@'), SYM_RESULT_ActiveRecord__FinderMethods_take_1_diaspora_handle))"`
> `(Contains(...) is not in §7.2's sub-language: …)`

The Ruby runtime records a `String#include?` decision as `Contains(…)`; the
parser refuses it at `src_new/dumps_to_policy/pc_expr.py:222` and
`build.py:672-674` re-raises naming the run. A genuine runtime↔builder seam
gap, untouched by the library fixes. **Scope: 1 of 161.** Narrow, but a hard
refusal of the whole dump.

Post-hoc, unchanged from run 1: this endpoint wrote two dumps. The one the
reach rule chose (`dse0001`, reach 2, 6 PCs) is refused; the other (`dse0002`,
reach 1, 1 PC) builds cleanly. The *richer* dump exposes the gap — an argument
for the reach selection rule, not against it.

### Did the failure count change, and if so, who changed it?

**It did not.** 7 before, 7 after, same endpoints, byte-identical messages.
The concurrent `src_new` work fixed the `extract_cmd` defect and deliberately
did **not** fix F1 — so neither my re-run nor that agent's fix moved this
number, and there is nothing to attribute.

---

## 3. Are the 161 kind conflicts gone? — YES

`reports/autolab/tools/reconcile_with_app.py`, run over this run's 161 dumps.
(The brief located it at `targets/tools/`; it actually lives at
`reports/autolab/tools/reconcile_with_app.py`.)

**Before** — the same tool over run 1's dumps, captured before I moved them:

```
endpoints sampled          : 161 (159 core-only)
probe core declarations    : 87  (MAXIMAL)
observed table sizes       : {86: 159, 89: 1, 104: 1}
in probe, never in the app : {'ActionController::Metal#head': 161}
kind conflicts (dumps predate a kind change?):
    x161  ActiveRecord::Associations::CollectionProxy#create: app=shim probe=target_function
    x161  PostService#mark_user_notifications: app=shim probe=target_function
    x1    User#blocks: app=shim probe=target_function
verdict: the only difference is the pinned dormant set
```

**After** — this run's dumps:

```
endpoints sampled          : 161 (159 core-only)
probe core declarations    : 87  (MAXIMAL)
observed table sizes       : {86: 159, 89: 1, 104: 1}
in probe, never in the app : {'ActionController::Metal#head': 161}
kind conflicts (dumps predate a kind change?):
    x1    User#blocks: app=shim probe=target_function
verdict: the only difference is the pinned dormant set
```

**322 conflict instances → 0** on the two reclassified targets (161 each). Exit
code 0 both times.

The surviving `x1 User#blocks` is **not** a residue of the fix: it is the
documented C1 endpoint-override, where `aspect_memberships_create` restores the
real association reader so the call stops being an access. The tool's own
`kind_conflicts_note` names it as the expected case.

### A run-1 open question that this closes

Run 1's §4 recorded a "measured registry discrepancy": 86 observed declarations
against `registry.json`'s 87, "to be settled with `declaration_probe.rb`".
`reconcile_with_app.py` settles it — the missing one is
`ActionController::Metal#head`, whose guard
(`Metal.instance_methods.include?(:head)`) is **false in the booted app**
because `head` lives in `ActionController::Head` and that module is never mixed
into `Metal`. The probe's stub world answers every `include?` affirmatively,
which is why the probe sees 87 and the app installs 86. It is harmless: the
core declares `ActionController::Head#head` separately with the same SHIM kind
and marker, and that one is present in every real run. Reading (a) from run 1,
"the registry counts declaration CALLS", was the wrong one; reading (b), "one
conditional core site does not install", was right.

Declaration table totals are **unchanged at 86 / 89 / 104** — the two
reclassifications moved names between kinds without adding or removing any:

| per dump | run 1 | run 2 |
|---|---|---|
| `target_function` | 48 (×284), 63 (×2) | **50 (×284), 65 (×2)** |
| `shim` | 38 (×282), 41 (×4) | **36 (×282), 39 (×4)** |
| total | 86 / 89 / 104 | 86 / 89 / 104 |

---

## 4. Did the write-note fixes show up in real endpoint runs?

**Yes — on exactly one endpoint, which is exactly the ceiling this corpus
allows. The honest endpoint-level number is 1, not 323→82.**

### How I measured it

Every recorded note (`SymbolicVar.note` and `SymbolicCallEvent.note`) is either
a JSON envelope `{"refs":…, "text":…}` whose text is SQL, or prose. A note is
**DML-carrying** iff its text parses (sqlglot) to an Insert/Update/Delete, or —
when sqlglot refuses — begins with INSERT/UPDATE/DELETE. Bind markers `$$(p0)`
and Rails-inlined `Time`s are substituted before parsing so neither can be
mistaken for SQL. Counted three ways because they answer different questions:
notes (each occurrence; a statement is normally noted twice, once on the var
and once on the call event), distinct normalised statement texts, and
endpoints. Implemented in `tools/compare_runs.py`, run over both corpora.

### The measurement

| | run 1 | run 2 |
|---|---:|---:|
| endpoints with ≥1 DML statement | **1** | **2** |
| endpoints whose only persistence note was prose | **1** | **0** |
| DML-carrying notes, corpus-wide | 12 | **18** |
| distinct DML statements, corpus-wide | 3 | **4** |
| total SQL statements parsed (0 unparsed both runs) | 271 | 272 |

**The prose note is gone.** `api_openid_connect_authorizations_destroy` is the
endpoint the brief named. Run 1's note on `ActiveRecord::Base#destroy` read, in
full:

```
Api::OpenidConnect::Authorization#destroy args={}
```

Run 2's reads:

```json
{"refs": {"p0": "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id"},
 "text": "DELETE FROM \"authorizations\" WHERE \"authorizations\".\"id\" = $$(p0)"}
```

A real statement, with its bind resolved to the `find_by` that produced the id.
That is the D6/D7 repair landing in a driven endpoint.

**A second, unasked-for improvement on the other write endpoint.**
`aspect_memberships_create` already carried 3 DML statements before the fix, so
it does not move the "endpoints with DML" count — but all three got better, and
it gained an access it had been missing entirely:

| | run 1 | run 2 |
|---|---|---|
| INSERT | `("aspect_id", "contact_id")` | `("aspect_id", "contact_id", "created_at", "updated_at")` |
| UPDATE contacts | `SET "receiving" = true` | `SET "updated_at" = …, "receiving" = true` |
| UPDATE notifications | unchanged | unchanged |
| `Base#save` call events | 2 | **3** |

The third `save` — a previously **unrecorded write access**, not merely an
unnoted one — now appears as a `call`/`symbolic_call` pair emitting the INSERT.
Corpus-wide that is the only change to the event stream: `call` and
`symbolic_call` events go **329 → 331** (+2, being that one pair across two
dumps) while `path_condition` events stay at **411**.

### The scope, stated plainly

The AR-level differential measured **323 lost write statements falling to 82**
(54 genuinely absent, 28 with a wrong column set, 7 notes with no real
counterpart). **Those are not endpoint-level numbers and must not be quoted as
if they were.** That differential drove 46 models × 12 operations directly. This
corpus drives 161 HTTP endpoints, and:

> **Only 2 of 161 endpoints ever call an ActiveRecord write target at all** —
> `aspect_memberships_create` and `api_openid_connect_authorizations_destroy`.
> Of those two, only one was lossy. So the maximum possible movement in this
> corpus was **one endpoint gaining DML text**, and that is precisely what
> happened.

Measured by scanning all 286 dumps of run 1 for `call`/`symbolic_call` events
whose target is an AR write method (`save`, `save!`, `create`, `update*`,
`destroy*`, `delete*`, `touch`, `increment!`, …): 4 such call sites, on 2
endpoints. Run 2 has 5 such call sites, on the same 2 endpoints.

**A fix whose observable blast radius is 2 endpoints is a real result, and it
is a small one *in this corpus*.** It is not evidence the fix is unimportant.
These endpoints run at `MAX_RUNS=2` with a 120 s budget and most terminate at
an unmocked call site, a `ParameterMissing` or a `Diaspora::NonPublic` long
before any write is reached; 36 of them record no branch at all. "2 of 161" is
a **floor on the reachable write surface of this corpus**, not a measure of how
much of the app's write behaviour the repair corrected. Measuring that properly
needs endpoints driven deep enough to write — which is the same gap §5 names.

---

## 5. Target-function reach — did it move? NO, not at all

Measured from the dump: `declarations` is `name -> {"kind": …}`; reach =
`|{kind=="target_function"} ∩ {call-event targets}|`.

**Instrument re-validated against the known calibration before use**, on the
`results4` reference batches (whose dumps are pre-fix and therefore a stable
calibration): `comments_index` 63 declared / best 3 / worst 1 ✓;
`aspect_memberships_create` 48 / 10 / 1 ✓ — exact match, same as run 1.

| best-dump reach | run 1 | run 2 |
|---:|---:|---:|
| 0 | 39 | **39** |
| 1 | 118 | **118** |
| 2 | 3 | **3** |
| 10 | 1 | **1** |

Median 1, max 10 (`aspect_memberships_create`), 39 at zero — all unchanged, and
the zero-reach set is the *same 39 endpoints*. **Every endpoint's `reach_best`
is identical between the two runs.**

**Across all 161 endpoints and all 286 dumps, still only 14 distinct target
functions were ever called** — and not merely the same count, the same 14
targets with the same per-target dump counts:

| target function | dumps, run 1 | dumps, run 2 |
|---|---:|---:|
| `ActiveRecord::FinderMethods#first` | 234 | 234 |
| `ActiveRecord::Core::ClassMethods#find_by` | 6 | 6 |
| `ActiveRecord::Associations::SingularAssociation#find_target` | 4 | 4 |
| `ActiveRecord::Base#save` / `#save!` | 2 / 2 | 2 / 2 |
| `ActiveRecord::Core::ClassMethods#find` | 2 | 2 |
| `ActiveRecord::FinderMethods#devise_user_first` | 2 | 2 |
| `ActiveRecord::FinderMethods#exists?` / `#find_by` / `#take` | 2 / 2 / 2 | 2 / 2 / 2 |
| `ActiveRecord::Querying#find_by_sql` | 2 | 2 |
| `ActiveRecord::Relation#update_all` | 2 | 2 |
| `ActiveRecord::Relation#any?` | 1 | 1 |
| `ActiveRecord::Base#destroy` | 1 | 1 |

### Why the reclassification moved nothing, measured rather than assumed

**Neither reclassified target is called by any endpoint, in either run.**

| | run 1 | run 2 |
|---|---:|---:|
| `ActiveRecord::Associations::CollectionProxy#create` | declared 161 eps, **called 0 dumps** | declared 161 eps, **called 0 dumps** |
| `PostService#mark_user_notifications` | declared 161 eps, **called 0 dumps** | declared 161 eps, **called 0 dumps** |

So the reclassification could only ever move the *declared* counts, and that is
all it moved: `declared_target_functions` rose by exactly 2 on **all 161**
endpoints (48→50 on the 160 core-only ones, 63→65 on `comments_index`) with the
shim count falling by 2. It is the only field that changed on every endpoint.

This is consistent with the library's own note that `PostService#mark_user_notifications`
is `homeless` — no `results4` dump contains an event for it either.

**The machinery runs clean; the mock layer is still almost entirely
unexercised. 159 of 161 endpoints declare 50 target functions and touch at most
1.** That is unchanged from run 1 and remains the most useful result here.

---

## 6. RC-1 blast radius — confirmed unchanged, as expected

RC-1 was **not** part of this fix, so no movement was expected. Confirmed by
measurement rather than assumed.

Measured per endpoint from every note's SQL text, parsed with sqlglot rather
than grepped, bind markers substituted first. **272 SQL statements, 0
unparsed** (run 1: 271, 0 unparsed — the one extra is the new `DELETE`).

**2 of 161 endpoints record a `profiles` read** — `aspect_memberships_create`
and `diaspora_federation_h_card_hcard`, the same two as run 1, both uniformly:

```sql
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ?
```

Both WIDE (`select_star=True`, 1 wide shape, 0 narrow) in both runs. Under
`concolic_mod` that is the diagnostic signal, not the expected one: the app's
own default projection is the 14-column narrow one, so a recorded `profiles.*`
cannot have come from ActiveRecord's default scope.

**Mechanism still traced to a line, and the line still reads the same** —
`reports/autolab/targets/core.rb:836`, inside `class_finder_sql`
(`core.rb:831`):

```ruby
%(SELECT "#{table}".* FROM "#{table}" WHERE #{conditions})
```

*(Run 1's report cited `core.rb:256`; that citation has rotted — the D1–D8 work
moved the function. It is at 831-836 in the live file, verified this run.)*

`grep` still finds **zero occurrences of `default_projection`** anywhere under
`reports/autolab/targets/`. RC-1's second part remains absent, and the
environment switch remains inert for the recorded SQL.

Scope this the same way run 1 did: **"2 of 161" is a floor, not the radius.**
The shared core has no profiles-synthesis mock of its own and 159 of 161
endpoints run on core targets alone, most stopping at an unmocked call site
before any profile is reached.

---

## 7. Environment and knobs — deliberately identical

Every knob is the one run 1 used. Nothing was changed; had anything been, it
would be stated loudly here.

| knob | value |
|---|---|
| launcher | `tools/diaspora-concolic-mod` (`RAILS_ENV=concolic_mod`) |
| `MAX_RUNS` | 2 |
| `TIME_BUDGET` | 120 |
| run timeout | 480 s |
| pipeline timeout | 420 s |
| concurrency | 3 |
| memory cage | `systemd-run --user --scope -p MemoryMax=4G -p MemorySwapMax=0` (6G for the Python stage) |
| process discipline | one OS process per endpoint, never reused |
| checkpointing | per endpoint, under a lock, with fsync |

**The harness files are byte-identical to run 1** — `tools/sweep.py`,
`tools/pipeline.py` and `tools/diaspora-concolic-mod` all carry mtimes from
before run 1 started (2026-09-25 20:55 and 21:12) and were not touched. The
only tool added is `tools/compare_runs.py`, which reads both corpora and drives
nothing.

`scripts/diaspora-concolic:17` still hard-codes `RAILS_ENV=concolic` and is used
by other jobs, so it was again **not** modified.

**Residual gap, recorded again:** `concolic_mod.rb:33` keeps
`consider_all_requests_local = true` where `production.rb:17` has `false`.
Unchanged. (`app/models/profile.rb:9` gates the `lazy_load` on the "mod"
substring, which is why `concolic_mod` is the right environment.)

Wall clock 2 h 51 m (run 1: 2 h 58 m); summed runner time 8.45 h (run 1:
8.56 h) — the box carried the same pre-existing load in both runs.

---

## 8. Box discipline, and harness faults

**Zero harness faults this run.** Run 1's three (the `run_complete` config, the
`Policy.signatures` tuple, the bind markers counted as columns) were fixed
before run 1's numbers were produced and did not recur.

* **Zero run timeouts, zero pipeline timeouts, zero non-zero runner exit
  codes**, across all 161 endpoints. `manifest.jsonl` has **161 rows, not 162**:
  no endpoint needed a second attempt. Run 1's one contention timeout
  (`active_storage_direct_uploads_create`, re-driven alone) did not recur — it
  ran clean on its first attempt in 188 s.
* **No endpoint was undriven or quietly dropped.** 161 scaffolded, 161
  attempted, 161 in the manifest, 161 result JSONs, 161 run directories.
* One OS process per endpoint, never reused — confirmed again by the
  zero-variance declaration set (86 on all 159 core-only endpoints, across 159
  independent processes). Never more than 3 in flight. No OOM kill.
* Pre-existing long-running `results3` jobs (`conversations_index/run_dse.rb`,
  `posts_show/v3/run_dse.rb`) were left alone and verified alive before and
  after. Nothing under `src/`, `src_new/` or `results3/` was modified by me;
  nothing committed; `entrypoints/scaffold/` not written to (`DUMP_OUT`
  redirects).

### One integrity caveat, found and measured rather than glossed

**`src_new` changed underneath this sweep.** A concurrent agent modified
`src_new/concolic/check.py` at 02:28:26 and `src_new/concolic/checks/run.py` at
02:32:19 — both while the sweep was running. By `finished_at`, **41 endpoints'
pipeline stages completed before the first change, 3 between the two, and 117
after**. Strictly, this run is not homogeneous in `src_new`.

I measured whether it mattered rather than assuming either way. Snapshotting all
352 `src_new/*.py` md5s before and after the sweep identifies exactly the files
above. Then, across all 161 results:

* the `blocking` string is **identical on all 161 endpoints**, on both sides of
  the cut;
* the `completion` dict has **3 distinct shapes**, and **every one of them
  occurs on both sides of the cut** (they vary only by `truncated` and
  `coverage_complete`, which are properties of the dump, not of `src_new`);
* all 161 verdicts are `complete: false`.

**Conclusion: the mid-run change is inert for this run's code path**, which is
what the fix's own design predicts — it guards a config whose keys are absent,
and this harness passes no config at all. The caveat is recorded because it is
true, not because it moved a number. If any future re-run needs strict
homogeneity, it must pin or vendor `src_new`.

---

## 9. Before/after, at a glance

| measure | run 1 (2026-09-25) | run 2 (2026-09-26) | moved? |
|---|---:|---:|---|
| endpoints scaffolded / attempted | 161 / 161 | 161 / 161 | — |
| ran clean | 154 | 154 | — (same set) |
| no paths | 0 | 0 | — |
| failed | 7 | 7 | — (same set, same messages) |
| harness errors | 0 | 0 | — |
| manifest rows (re-drives) | 162 (1) | **161 (0)** | ✔ better |
| dumps written / accepted by dump IR | 286 / 286 | 286 / 286 | — |
| `complete: false` | 161 | 161 | — |
| PC-in-chosen-dump distribution | `0:36,1:7,2:113,3:2,4:1,6:1,16:1` | identical | — |
| `path_condition` events, corpus | 411 | 411 | — |
| `call` / `symbolic_call` events, corpus | 329 / 329 | **331 / 331** | ✔ +1 access |
| declared target functions per dump | 48 / 63 | **50 / 65** | ✔ the reclassification |
| declared shims per dump | 38 / 41 | **36 / 39** | ✔ the reclassification |
| declaration table size | 86 / 89 / 104 | 86 / 89 / 104 | — |
| kind conflicts (reconcile) | **322** (161 + 161) | **0** | ✔ fixed |
| kind conflicts (C1 `User#blocks`) | 1 | 1 | — expected |
| reach distribution | `0:39,1:118,2:3,10:1` | identical | — |
| distinct target functions ever called | 14 | 14 | — (same 14) |
| endpoints at zero reach | 39 | 39 | — (same set) |
| endpoints with ≥1 DML statement | 1 | **2** | ✔ the write-note fix |
| endpoints with prose-only persistence note | 1 | **0** | ✔ the write-note fix |
| DML-carrying notes | 12 | **18** | ✔ |
| distinct DML statements | 3 | **4** | ✔ |
| SQL statements parsed / unparsed | 271 / 0 | 272 / 0 | ✔ +1 |
| endpoints reading `profiles` | 2 | 2 | — (same 2, both `SELECT *`) |
| wall clock | 2 h 58 m | 2 h 51 m | — |

**Regressions: none.** No count worsened, no endpoint moved from clean to
failed, no dump became unacceptable, no reach was lost.

---

## 10. Open decisions

1. **F1's resolution has changed shape.** It is no longer "re-declare, or elide
   no-atom signatures" — eliding is ruled out by `normalize.py:341`. The live
   questions are (a) fix the false claim at `src_new/README.md:333`, and (b)
   decide what `tools/pipeline.py:218`'s `has_opaque` should actually assert,
   given that a shim's signature reaching a policy is by design. Not mine to
   take; not attempted.
2. **F2** — `Contains(…)` remains outside §7.2's sub-language
   (`pc_expr.py:222`). A genuine runtime↔builder seam gap, 1 of 161, untouched.
3. **RC-1's second part** — `default_projection` is still absent from the shared
   core, so the environment switch remains inert for recorded SQL.
4. **The gates still have not run.** Now that the `extract_cmd` defect is fixed
   in `src_new`, a third sweep *could* pass a partial `CompletionConfig` and
   have the absent steps reported blockingly rather than raising. That would
   turn this from a coverage-layer shakedown into a real gate run. It is the
   obvious next move and it was not done here, because changing it mid-comparison
   would have made this diff uninterpretable.
5. **Endpoint depth, not library breadth, is the binding constraint.** 14
   distinct target functions across 161 endpoints, 39 endpoints at zero reach,
   36 with no branch at all, and 2 endpoints that reach a write. Every finding
   in §4, §5 and §6 is floored by the same thing: these endpoints do not run
   deep enough to exercise what the library now models.
