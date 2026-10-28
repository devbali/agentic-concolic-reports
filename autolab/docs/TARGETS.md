# The targets half of the auto-lab

A loadable, measured, self-checking library of **target-function
declarations** — the mocks a concolic runner installs before it drives an
endpoint. `../README.md` is the map; this file is the library.

---

A loadable, measured, self-checking library of **target-function
declarations** — the mocks a concolic runner installs before it drives an
endpoint — so an automated sweep can drive many endpoints without anyone
hand-building the mocks for each one first.

The application it currently covers is diaspora, and every declaration in it is
a declaration about diaspora's code. Everything structural below — the layers,
the split rule, the defects, the tests — is about the library, not about that
application.

`entrypoints/` is the lab's **other** half (which endpoints exist and what they
cost) and is owned separately; nothing in this section touches it.

---

## Vocabulary

Three words are used throughout, and they mean exactly this:

* **the core** — `targets/core.rb`, the 87 declarations every endpoint installs
  first.
* **an endpoint layer** — `targets/endpoints/<id>.rb`, one endpoint's own
  declarations, installed after the core and winning ties. Two exist today.
* **a curated endpoint** — an endpoint whose declarations were written and run
  by hand until it closed, so real dumps exist against exactly those
  declarations. Both endpoint layers here are curated; `registry.json` records
  that as `tier: "gold"`, together with the file each was copied from and its
  md5. Everything else the sweep can reach is *scaffolded*, not curated.

Full sourcing is in [Sources and provenance](#sources-and-provenance) at the
end.

---

## The core/local split

The rule is the **`kind:` axis**:

> Every `kind: CallInterceptor::TARGET_FUNCTION` declaration belongs to the
> shared core — they are the app-wide access boundary. Every
> `kind: CallInterceptor::SHIM` is triaged: the genuinely app-wide ones join
> them in the core, the rest stay endpoint-local.

`inventory/partition.json` assigns **every** target in this library a tier and a
written reason, grouped so the reason is per-group rather than per-line:

| tier | n | meaning |
|---|---|---|
| `core` | 87 | in `targets/core.rb` today, and belongs there |
| `core-promoted` | 2 | lifted by this lab into `targets/shared_shims.rb` |
| `core-eligible` | 9 | app-wide in substance, still in an endpoint layer — each row names its blocker |
| `local` | 9 | endpoint-local by construction; promoting it would be wrong |

The declarations back the rule up. Measured across the two curated endpoints
(maximal counts — see [Two counts](#two-counts-maximal-and-observed)):

|  | aspect_memberships_create | comments_index |
|---|---|---|
| declared | 90 | 105 |
| `TARGET_FUNCTION` | 50 | 65 |
| `SHIM` | 40 | 40 |

* **Target functions: 50 shared, 0 unique to aspect_memberships_create, 14
  unique to comments_index.** One endpoint's set is a strict subset of the
  other's — no genuine conflict, one endpoint simply needs fewer. Of the 50
  shared, 49 are identical in kind *and* type.
* **Shims: 37 of 40 shared on each side, all 37 identical in kind and type**,
  leaving a local tail of 2 and 3.

### Two reclassifications, 2026-09-26 (D7a)

`ActiveRecord::Associations::CollectionProxy#create` and
`PostService#mark_user_notifications` moved `SHIM` → `TARGET_FUNCTION`. A `SHIM`
asserts the real body issues no SQL, and both bodies do — an INSERT into the
association's table, and four statements respectively — so the old declarations
were wrong twice over: a shim is not an access, and carrying no note there was
nothing to record even if it had been. Each now has its own group and written
reason in `partition.json`.

`PostService#mark_user_notifications` is worth calling out. It is now the **only
app-specific target function in the shared core** — diaspora's own service
object, not framework and not a shared model reader. It is there because the
ruling puts target functions in the core and because **no endpoint layer exists
to hold it**, not because anyone established it is app-wide; its partition row
carries `homeless` and `open_question` saying exactly that. Moving it into a
posts/notifications endpoint layer later would cost the two curated endpoints
nothing: no `results4` dump contains an event for it, and shims in that corpus
*do* emit events, so the absence is informative.

### The one exception to "target functions are standard"

7 of these target functions are **synthetic per-call-site aliases**
(`ci_vis_first`, `mention_lookup_msg_retry`, …). They are not methods the app
has: an endpoint layer aliases a real finder under an invented name and routes
**one** call site to it, so that call site gets its own symbolic variable name
instead of sharing `SYM_RESULT_..._first_N` with every other finder.

The `kind` is genuinely `TARGET_FUNCTION` — each issues real SQL — but the
**name** belongs to one endpoint's control-flow graph. Promoting them would put
another endpoint's call-site names into every run. So they stay local, and the
rule reads: *target functions are standard, except where the target is a
synthetic per-call-site alias.*

`ActiveRecord::FinderMethods#devise_user_first` is the one alias that is **not**
endpoint-specific — both endpoint layers invented it independently, for the
Devise session lookup every authenticated endpoint performs. It is rated
`core-eligible`; see CONFLICTS.md C3 for why it is not promoted yet.

---

## How a new endpoint picks up the library

1. Write `targets/endpoints/<endpoint>.rb`. It defines a module with
   `install!(interceptor)` and declares **only** what `partition.json` calls
   `local` for your endpoint — usually nothing but your own naming aliases and
   any wall specific to your action. Do not copy the core.
2. Add an entry to `targets/registry.json`:
   ```json
   "my_endpoint": {
     "file": "targets/endpoints/my_endpoint.rb",
     "modules": ["MyEndpointTargets"],
     "shared_shim_groups": ["federation_delivery"],
     "tier": "new"
   }
   ```
   A **new** endpoint should start with every group in
   `AutolabSharedShims::GROUPS`. The two curated endpoints have `[]` on purpose
   — see below.
3. Drive it:
   ```ruby
   require "./config/environment"
   require "/home/dev/project/reports/autolab/autolab_targets.rb"
   report = Autolab::Targets.install!("my_endpoint", interceptor: $interceptor)
   ```
   `report` names, per layer, exactly which targets that layer declared, plus
   `double_declared` — the targets more than one layer claims.
4. **Fork a process per endpoint.** `install!` is not idempotent — see below.
5. `./test/run_tests.sh` must stay green. It will fail loudly if any declaration
   in your file is missing `kind:` or `type:`, or puts `opaque` on a
   `TARGET_FUNCTION`.

Paths are absolute into `src_new`, the way the curated endpoints' own runners
do it (`reports/diaspora/results4/<endpoint>/run_dse.rb`). Note that
`scripts/diaspora-concolic` still exports a vestigial `RUBY_RUNTIME` pointing at
the **old** `src/` — nothing here reads it.

### Why the curated endpoints take no shared shim groups

`aspect_memberships_create` and `comments_index` are closed and their dumps
exist. Adding a group would make them declare a target they did not declare when
those dumps were made, and a **dormant declaration is not free** — it enters the
declared-target roster that completeness accounting reads. So their
`shared_shim_groups` is `[]`, `shared_shims` is a *measured* no-op for them
(asserted by test 6), and the groups exist for endpoints that come next.

---

## Two counts: maximal and observed

Every count in `inventory/` is **maximal** — what a config declares when every
`if defined?(...)` guard is true — because the probe forces them true so it can
see every declaration. A **booted app** installs one fewer:

| | core | aspect_memberships_create | comments_index |
|---|---|---|---|
| maximal (probe) | 87 | 90 | 105 |
| observed (real runs) | **86** | **89** | **104** |

Measured across **161 shakedown endpoints, 159 of them core-only, every one at
exactly 86 with zero variance**. The difference is always the *same one name*:

> **`ActionController::Metal#head`** (`targets/core.rb:1856`, section W2) never installs. Its
> guard is `ActionController::Metal.instance_methods.include?(:head)`, and `head`
> is defined in `ActionController::Head`
> (`actionpack-5.2.4.3/lib/action_controller/metal/head.rb:21`), a module never
> mixed into `Metal`. The guard is false in the app; the stub world answers every
> `include?` affirmatively, which is why the probe sees the site and the app
> does not.

**It is harmless, and the test suite pins why**: the core declares
`ActionController::Head#head` separately (`targets/core.rb:2169`) with the same `SHIM` kind and
the same `:head_reached` marker, and that one is present in all 161 real runs. The W2 site
is redundant, not load-bearing — so it is recorded rather than deleted, since
deleting it would be a change to a verified file for no behavioural gain.

This also settles an older open question. The gap is **not** the registry
counting declaration *calls* against a table keyed by *name*: the probe confirms
the core makes 87 calls producing 87 **distinct** names, with nothing declared
twice. `registry.json` now reports `declarations_maximal` and
`declarations_observed_in_app` separately and names the dormant site;
`tools/reconcile_with_app.py` regenerates the diff and exits non-zero if
anything other than the pinned dormant set ever differs.

---

## One endpoint per process

A sweep must fork a process per endpoint, the way each curated endpoint's own
runner already does. **`install!` is not idempotent**, and this lab measured
exactly where:

`targets/endpoints/comments_index.rb:881` creates `ConcolicThroughLoadProbe`
under `unless defined?(::ConcolicThroughLoadProbe)` and **declares its target
inside that guard**. On a second install in the same process the constant
already exists, the block is skipped, and the endpoint silently declares **104
targets instead of 105** — losing
`ConcolicThroughLoadProbe.load_intermediate`, the probe that carries the
through-load intermediate statement into the dump.

It is the only site of that shape in this library (all three files checked), and
it never surfaced before because each endpoint had always been run in its own
process. It only appears once you try to drive several endpoints from one
runner — which is exactly what an auto lab is for.

The loader cannot fix it: the guard lives in a verified endpoint layer. So it
**detects** it. A repeat install of the same endpoint whose declared set differs
from the first warns on stderr and sets `repeat_install_drift` in the report,
naming the targets lost:

```
[autolab] REPEAT INSTALL of comments_index in this process declared a DIFFERENT
set: lost ["ConcolicThroughLoadProbe.load_intermediate"], gained [].
install! is not idempotent -- drive one endpoint per process.
```

`test/test_install.rb` pins this as a regression guard, with
`aspect_memberships_create` as the stable control.

---

## The override mechanism, and its known defect

The layers install core-first, local-second, and the local layer wins by going
last. It has to be that way round: `declare_target` installs via
`define_method`, so a later declaration does not *replace* an earlier one.

**It wraps it — and that is lossy. The defect is named D5 where it was
measured:**

> On a second `declare_target` for the same `(class, method)`,
> `declare_target` reads `klass.instance_method(method).parameters` — and "the
> method" is now the *first* mock's wrapper, whose signature is
> `|*splat_args, **kwargs, &block|`. Every named argument the second mock wanted
> comes back `nil`.

Measured on a bare runtime at
`targets/endpoints/aspect_memberships_create.rb:946`; the core's own
warning that a **prepend** is the correct tool for a second layer is at
`targets/core.rb:1914`.

Consequences, and they shaped this lab:

* **The kind-axis split reduces redeclarations, which is an independent argument
  for it.** Every target the core and an endpoint layer both declare is a
  wrapped declaration exposed to D5; there are 27 of them today
  (CONFLICTS.md C2).
* **`shared_shims.rb` never redeclares.** It takes a `skip:` list — the targets
  the endpoint claims for itself — so each `(class, method)` is declared exactly
  once per run.
* **The loader reports every double declaration** per run, rather than leaving
  it to be met in a dump.

A clean override would need the runtime to either replace a declaration or
expose the original signature. **That is a `src_new` change and this lab did not
make one** — it is reported, not worked around.

---

## A property every mock body must have

> **A mock must not collapse a conditional access into an unconditional one.**

This is application-independent, and it is the one durable rule to come out of a
long investigation into a single wrong mock. It is a property of the body, not
of the declaration: the declaration can be perfectly well-formed — right
`kind:`, right `type:`, loads, passes every test here — and still be wrong in
this way.

**The shape.** Real code performs one access, and then performs a *second*,
separately gated access to the same entity, widening what it reads, only when a
runtime condition holds. The mock answers both with a single unconditional
access of the wide shape. Two distinct harms follow, and they point in opposite
directions:

* on the branch that should have been narrow, the mock **over-discloses** —
  every downstream precision claim inherits the surplus;
* on the branch that should have been wide, the mock **erases the condition**
  that made it wide, so a real decision never becomes a decision.

**Why it survives review: it is invisible to aggregate comparison.** A
comparison that unions shapes — every field any access read, every entity
touched, any set-or-union-level diff — saturates the moment one wide shape is
present. Getting *every* narrow shape wrong then changes nothing at the union
level, and the diff stays green while the per-branch answer is wrong. **So the
check has to be per-shape: compare access shapes branch by branch, against a
recorded reference for that branch.** An aggregate check cannot see this class
of defect at all, and that is the part most likely to be rediscovered
expensively by someone who assumes a green union diff means agreement.

**The fix direction**, and the two wrong turns either side of it:

* Model the second access as a **separate access with its own gate**, emitted in
  its own right when the gate holds.
* The gate must be a decision the run is **already** making symbolically. Do not
  widen the first access to cover both cases, and do not narrow it.
* Do **not** mint a free symbolic boolean for "did the second access fire". A
  fresh free boolean is not a function of the state the run already branches on,
  so it admits gate combinations that cannot occur, and — being unconstrained —
  it can be pruned away rather than forcing the branch it was supposed to
  represent.

Nothing in `test/` enforces this today: these tests check the declaration-time
contract (see [What is NOT verified](#what-is-not-verified)), and this property
is about behaviour under a real run. It is a review obligation on every new mock
body and a candidate for a per-shape differential check in whatever drives the
endpoint. The worked instance that produced the rule, with the measurements
behind it, is at
`reports/diaspora/docs/RC1_LAZY_FETCH_AS_DECISION_20260925.md`.

---

## How to trust this

Every count in `inventory/` was **measured**, by running the real `install!`
against the real `CallInterceptor` from `src_new` and reading back what the
interceptor holds. Nothing here is grepped.

That matters more than it sounds. The single app-wide targets file this library
replaces was retired because it had stopped loading under either runtime and
nobody noticed — and **it looked fine to a grep**: all 67 of its
`declare_target` sites carried `type:`, neatly, and not one carried `kind:`, so
`install!` raised `MissingKind` at its first declaration and declared nothing at
all.

Two more reasons parsing is not enough:

* A naive `grep -c declare_target` over the four source files says
  **67/67/22/15**. The real site counts are **59/59/10/14** — they write the
  word in prose and across line continuations. `tools/extract_sites.rb` uses
  Ripper.
* **29 of the 142 sites are loop-bound**: `%i[find take! first!].each { |m|
  declare_target(fm, m, ...) }`. Receiver *and* method are block variables, so
  nothing resolves them from the call site. Those 29 sites are why the core's 59
  sites produce 87 declarations. They are listed under
  `manifest.loop_bound_sites`.

| tool | what it does |
|---|---|
| `tools/stub_world.rb` | the fake world a config declares against: the real src_new runtime, plus auto-vivifying stubs for Rails and for the application's own classes |
| `tools/declaration_probe.rb` | runs a real `install!` against a real `CallInterceptor` and records every declaration |
| `tools/extract_sites.rb` | Ripper call-site parser; counts sites and flags loop-bound ones |
| `tools/scrape_constants.rb` | the constants the probe must pre-create so `if defined?(...)` guards are true |
| `tools/build_inventory.py` | regenerates `manifest.json` and `candidates.json` |
| `tools/build_partition.py` | emits `partition.json`; **fails** if its ruling table and the manifest disagree about the target set |
| `tools/build_conflicts.py` | emits `conflicts.json` |
| `tools/reconcile_with_app.py` | diffs the probe's maximal set against real runs' declaration tables; emits `app_reconciliation.json` |
| `tools/check_citations.py` | re-resolves every `file:line` the prose argues from; emits `citations.json` |

```sh
/home/dev/project/venvs/queries_from_runs/bin/python3 tools/build_inventory.py
/home/dev/project/venvs/queries_from_runs/bin/python3 tools/build_partition.py
/home/dev/project/venvs/queries_from_runs/bin/python3 tools/build_conflicts.py
/home/dev/project/venvs/queries_from_runs/bin/python3 tools/reconcile_with_app.py
/home/dev/project/venvs/queries_from_runs/bin/python3 tools/check_citations.py
```

### What is NOT verified

**The application is never booted here.** The probe and the tests replace Rails
and the app with stub modules. So the library is proven to satisfy the runtime's
*declaration-time* contract — every `kind:` in `CallInterceptor::KINDS`, every
`type:` through `CallInterceptor.valid_type?`, `install!` running to completion —
and **not** proven to behave correctly against real ActiveRecord. Only a JRuby
run inside the app proves that, and this lab has not done one.

One consequence to keep in mind when reading the counts: the probe measures the
**maximal** declaration set. That caveat is no longer hypothetical — it is
measured, bounded and pinned; see "Two counts" above.

The reconciliation it *can* do, it does: of the 142 sites, 141 produce at least
one declaration, and the one that does not is
`targets/core.rb:1820` — a `render_mod` table the core deliberately empties
(`{}.each`) and documents as "kept as an inert, never-iterated table for the
diff".

---

## Tests

```sh
./test/run_tests.sh
```

* **`test/test_install.rb`** — 38 checks. Installs every registered endpoint
  against a real `CallInterceptor`; asserts every kind is in
  `CallInterceptor::KINDS`, every type passes `CallInterceptor.valid_type?`, and
  no `opaque` sits on a `TARGET_FUNCTION` (the library has 9 `opaque`/`opaque?`
  declaration sites, 5 distinct targets, and every one is behind `SHIM` — the
  test holds that line). It also checks the library is byte-identical to the
  files it was copied from (each recorded with its md5 in `registry.json`), and
  drives `Autolab::Targets.install!` itself in a fresh subprocess to confirm the
  loader reaches the same counts the manifest publishes.

  Crucially it runs **negative controls**: it takes the real core file, deletes
  one `kind:` argument, loads the mutant and asserts `MissingKind` is raised —
  then asserts that the mutant still contains plenty of other `kind:` sites,
  i.e. that a source-text check would have waved it through. Same for `type:`/`MissingType`. A
  test that cannot fail is not evidence.

* **`test/test_inventory.py`** — the inventory is internally consistent and
  regenerating it is a no-op (so a stale manifest is a test failure, not a
  surprise). It also re-resolves every `file:line` this file and CONFLICTS.md
  argue from: the curated files get revised — D7a moved nearly every line in
  `core.rb` — and a citation that rots points confidently at the wrong code,
  which is worse than no citation at all.

`run_tests.sh` runs `test_install.rb` TWICE when the
`scripts/diaspora-concolic` toolchain is on disk: once under **JRuby 9.3**, the
interpreter a sweep actually uses, and once under CRuby. Both passes are
green and report identical counts (90 / 105 / 87, the maximal figures). Everything in
`tools/stub_world.rb` is Ruby 2.6 syntax for that reason — JRuby 9.3 has no
endless method definitions.

---

## Sources and provenance

The library's current contents are the diaspora concolic experiment's target
declarations. Each file records where it came from; these are citations, and
nothing below has to be read to use the library.

* **Copied verbatim, and curated** (`tier: "gold"` in `registry.json`):
  `reports/diaspora/results4/{aspect_memberships_create,comments_index}/` —
  `concolic_targets.rb` (byte-identical in both, which is what makes it a
  *core*) and each endpoint's own `targets.rb`. `registry.json` records the
  source md5 and the test asserts no drift.
* **Mined for names, not shipped**: `reports/diaspora/results3/*/` — six older
  endpoint configurations, **670 declarations, every one of them missing both
  `kind:` and `type:`**. Used only to discover the 34 target names in
  `candidates.json`.
* **Retired**: `_trash/diaspora_shared_concolic_targets_20260925/` — the single
  app-wide targets file this library replaces, and its `_RETIRED.md`.
* Spec: DESIGN_IR §4.1.1f (a target declares its name and its
  kind), §5.0 (the type grammar), §5.0.1 (every mock declares its target's
  return type), §5.2 (`opaque` is an admission).
