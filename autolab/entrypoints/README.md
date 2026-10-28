# `reports/autolab/entrypoints/` — the entry-point manifest

Everything an automated sweep needs in order to pick up *any* controller action
of the application under test and start driving it concolically, without a
human hand-writing that endpoint's runner and configuration first. The
application here is diaspora: 161 drivable entry points, enumerated from the
real app in `manifest.json`.

This half of the auto lab owns **enumeration and scaffolding**. The shared
target library (mocks, `declare_target` declarations) is the peer half, under
`reports/autolab/targets/`, and is consumed here through its
`registry.json` — never copied.

---

## Status vocabulary (read this before quoting any number)

Three different things, deliberately not blurred:

| Term | Means | How it is established |
|---|---|---|
| **enumerated** | The endpoint is in `manifest.json` with verb, path, params, filters, auth, source location. | Runtime introspection of a booted Rails app. |
| **scaffolded** | `scaffold/<id>/` exists with a runner, a one-stack config and a launcher, and the runner *parses*. | `scaffold.py` + `tools/syntax_check.rb`. |
| **verified to launch** | The runner was actually executed and produced dumps and an `exploration_summary.json`. | `tools/smoke.sh`, results in `smoke_results.json`. |

A fourth thing the manifest also establishes: the generated spec is
**accepted by the real sweep loader** (`sweep.spec.load_spec`), which is a
schema check, not a run.

Scaffolded is **not** verified. A scaffolded endpoint has a generated runner
built from measured facts and a *generic, uncurated* app-error policy; it has
never been run. `config.json` carries `.autolab.verified` for exactly this.

Two further terms name work done by hand **before** this lab, which a few
endpoints carry and the rest do not:

| Term | Means | Where it is recorded |
|---|---|---|
| **driven before** | The endpoint was explored by hand, to a close: 7 of the 161. They are tier 0 and carry `driven_before: true`. | `manifest.json`; the runs themselves are under `reports/diaspora/results3/` and `results4/`. |
| **curated targets** | A hand-written, closed set of mocks for it exists in the target library (`targets.tier: "gold"`): 2 of the 161. Every other endpoint gets the shared core alone (`targets.tier: "candidate"`). | `reports/autolab/targets/registry.json`. |

---

## The app boots

`manifest.json` is **not** a static parse of `config/routes.rb`. The app
boots under `RAILS_ENV=concolic` on JRuby 9.3 / Rails 5.2.4.3, so the
enumeration comes from the real, fully-expanded router:
`resources` expansions, constraint blocks and the mounted
`DiasporaFederation::Engine` are all resolved by Rails before anything is
recorded. It was then cross-checked row-by-row against `bin/rails routes` in
the same environment.

---

## Layout

```
entrypoints/
├── README.md                  this file
├── PRIORITY.md                the prioritised ordering, and why
├── manifest.json              THE MANIFEST (see schema below)
├── sweep_endpoints.json       a paste-ready `endpoints` array for a sweep spec
├── sweep.json                 a COMPLETE, loadable sweep spec (see caveat below)
├── raw_introspection.json     unreduced facts from the booted app
├── smoke_results.json         which endpoints were actually launched
├── lib/
│   └── autolab_dse.rb         the generic driver: harness, principal, flip
│                              matchers, prefix-directed worklist
├── scaffold/
│   ├── _index.json            id -> tier / rank / cost / dir
│   └── <endpoint_id>/
│       ├── run_dse.rb         thin: CFG only
│       ├── config.json        one-stack DESIGN_ONE_STACK §4 config
│       └── launch.sh          the exact scripts/diaspora-concolic command
└── tools/
    ├── introspect_entrypoints.rb   runs INSIDE the booted app
    ├── build_manifest.py           raw -> manifest
    ├── scaffold.py                 manifest -> scaffold/
    ├── syntax_check.rb             parse every runner in one JRuby process
    └── smoke.sh                    launch endpoints, record how far they got
```

---

## Manifest schema

`manifest.json` top level:

| Key | Meaning |
|---|---|
| `schema_version` | `1`. |
| `generated_at`, `generator` | Provenance of this file. |
| `provenance` | How the facts were obtained: Rails version, env, app root, and the cross-check against `bin/rails routes`. |
| `cost_model` | The weights and tier cut points used for ordering — see PRIORITY.md. |
| `counts` | Every count quoted anywhere, in one place. |
| `findings` | Places the router and the controllers disagree. |
| `non_controller_routes` | Routes that reach a Rack app, an engine mount or a redirect rather than an action. |
| `endpoints` | The array below, **in sweep order**. |

### One endpoint

One entry per distinct `controller#action`. An action reachable by several
routes (`people#show` via both `/people/:id` and `/u/:username`) is **one**
endpoint with several `routes`, because the concolic unit of work is the
action, not the URL.

```jsonc
{
  "id": "comments_index",                 // <controller>_<action>; the same id the
                                          //   hand-built runs use, so ids join across them
  "entrypoint": "CommentsController#index", // the one-stack `entrypoint` string
  "controller": "comments",
  "controller_class": "CommentsController",
  "action": "index",
  "engine": null,                          // or the mount name, e.g. "diaspora_federation"
  "owner": "app",                          // app | gem | engine
  "status": "ok",                          // ok | implicit_render | action_missing
  "driven_before": true,                   // one of the seven driven by hand before this lab

  "source":  { "file": "...", "line": 49, "defined_in": "...", "loc": 7,
               "body_extracted": true },
  "controller_file": "app/controllers/comments_controller.rb",
  "views": ["app/views/comments/index.mobile.haml"],
  "view_loc": 3,

  "verbs": ["GET"],
  "routes": [
    { "name": "post_comments", "verb": "GET",
      "path": "/posts/:post_id/comments(.:format)",
      "path_params": ["post_id"], "route_defaults": {}, "primary": true }
  ],

  "params": {
    "path":            ["post_id"],   // required route segments
    "read_in_action":  ["post_id"],   // params[:x] / params.require(:x) in the body
    "query_or_body":   [],            // read minus path — query string or body
    "format_segment":  true,          // the route carries (.:format)
    "respond_to":      ["json","mobile"]
  },

  "auth": {
    "authenticate_user_enforced":    false, // authenticate_user! resolves ON for this action
    "authenticate_user_conditional": false, // present but gated by a runtime predicate
    "role_required":                 null,  // "admin" | "moderator" | null
    "reads_current_user":            false, // the body mentions current_user
    "recommended_scenario":          "anon" // anon | auth | both
  },

  "filters": {
    "applied":     [...],   // resolved ON for this action
    "conditional": [...],   // gated by a Symbol/String predicate — a runtime decision
    "not_applied": [...],   // only:/except: excluded it, or skip_before_action removed it
    "beyond_application_controller": [...],  // the controller's own work
    "declared_in_controller": [ {"line": 10, "source": "before_action :authenticate_user!, except: ..."} ]
  },

  "behaviour": { "writes_db": false, "enqueues_job": false, "federation": false,
                 "sends_mail": false, "external_http": false, "renders_stream": false,
                 "redirects": false, "paginates": false, "uses_presenter": true,
                 "renders_json": true, "reads_session": false, "reads_request": false },

  "model_graph": { "models_named": ["Comment"],       // AR models named in the body
                   "association_total": 12,           // sum of their association counts
                   "max_model_associations": 12 },

  "cost": { "score": 9.6, "components": { ... }, "blockers": [] },
  "priority": { "tier": 0, "rank": null, "why": "already driven — regression set" },
  "targets": { "tier": "gold",             // gold = a curated endpoint layer exists;
                                           //   candidate = shared core only
               "override_file": "targets/endpoints/comments_index.rb",
               "modules": ["CommentsTargets", ...] }
}
```

### How `auth` is determined, and why there are two questions

`authenticate_user_enforced` is read from the **resolved callback chain** of
the real controller class, not from grepping for `before_action`. Rails
compiles `only:`/`except:` into one-argument procs over `action_name`; the
introspector calls them. A `Symbol` predicate (`if: :devise_controller?`) is
a runtime decision and is reported as `conditional`, never guessed.

Enforcement is **not** the same question as whether the action needs a
principal. `PeopleController` declares
`before_action :authenticate_user!, except: %i(show stream hovercard)` — yet
`people#show` and `people#stream` both read `current_user` and branch on it.
So `recommended_scenario` is:

* `auth` — `authenticate_user!` resolves ON;
* `both` — reachable anonymously **but** the body reads `current_user`, so
  both arms are real and a runner should drive both variants (this is exactly
  what the curated `comments_index` runner does with its `anon_*` / `auth_*`
  variants);
* `anon` — neither.

---

## Findings: where the router and the controllers disagree

Recorded in `manifest.json.findings`, not dropped.

* **`photos_edit` — dead route.** `GET /people/:person_id/photos/:id/edit`
  routes to `PhotosController#edit`, which has no action method *and* no
  `app/views/photos/edit.*` template. A request raises
  `AbstractController::ActionNotFound`. Not scaffolded.
* **`help_faq` — route with no action, but valid.** `HelpController` is an
  empty class body; `GET /help` and `GET /help/:topic` render
  `app/views/help/faq.html.haml` implicitly. Routable and drivable, with no
  Ruby body to explore. Scaffolded, `status: implicit_render`.
* **Eight public methods with no route**, all helpers that should have been
  `private`: six in `SessionsController` (`find_user`,
  `authenticate_with_2fa`, `valid_otp_attempt?`,
  `authenticate_with_two_factor_via_otp`, `prompt_for_two_factor`,
  `reset_authentication_token`), plus
  `NotificationsController#default_serializer_options` and
  `Api::OpenidConnect::UserInfoController#current_user`. Because they are
  public they are in `action_methods` and Rails *would* dispatch to them if a
  route existed. Recorded as `severity: info`.

The raw set difference `action_methods − routed` is 663; almost all of it is
methods inherited from `ApplicationController` and helper modules. The
manifest reports only the 8 whose definition is in this app's own
`app/controllers` tree, and `raw_introspection.json` keeps the raw count
(`unrouted_raw_candidate_count`) so the filtering is auditable.

---

## Fit to `src_new/sweep`

The sweep already has an endpoint concept, and the manifest matches it rather
than inventing a parallel one.

`sweep.spec.EndpointSpec` is `{name, config, home, max_attempts, box, agents}`
and the endpoint **name is an opaque string** to `sweep/` — nothing there
parses a verb, path, controller or action. All the HTTP-shaped facts live one
layer down, in the one-stack `config.json` that `EndpointSpec.config` points
at, which the sweep only hashes and mounts read-only.

So:

* `scaffold/<id>/config.json` is written in the **one-stack
  `DESIGN_ONE_STACK` §4** shape — `schema_version`, `endpoint`, `entrypoint`,
  `paths`, `runtime`, `scenarios`, `inputs`, `must_stay_symbolic`, `limits` —
  plus the `request_format` / `signed_in` keys the sweep's own e2e config
  synthesizer uses. Extras are namespaced under `.autolab` so they cannot
  collide with a §4 key.
* `sweep_endpoints.json` is a ready-to-paste `endpoints` array whose key set
  is exactly `_ENDPOINT_KEYS`, ordered by priority. `config` paths are
  absolute, so the array works wherever the spec file ends up.
* `sweep.json` is a complete spec: that array wrapped in the `boxes`,
  `host_pools`, `budgets`, `agents`, `prices` and `preauthorized` blocks
  taken from the canonical example (`sweep/tests/conftest.py:BASE_SPEC`).
  **Those surrounding blocks are the example's test values** — box sizes,
  dollar ceilings and agent routes must be reviewed before a real run. The
  `endpoints` array is the part this lab generated.

Both were **verified to load**: `sweep.spec.load_spec()` accepts `sweep.json`
and returns 161 `EndpointSpec`s, and every `config` path it names exists on
disk.
* `limits` lives in the per-endpoint `config.json` and **never** in the sweep
  spec — `sweep.spec._forbid_limits` rejects it at any depth.

**No one-stack `config.json` previously existed anywhere on disk**; every
sweep spec in the tree points at a `reports/diaspora/results4/<endpoint>/config.json`
that its own tests synthesize at runtime. These are the first real instances.

### Glue that would be needed in `src_new/` (proposed, not written)

None is strictly required to *run* the sweep — the files above satisfy its
existing contract. Two small things would make it seamless, and both belong
to whoever owns `src_new/`:

1. **Corpus wiring.** `sweep.testbed` requires a corpus per endpoint,
   supplied out-of-band as `--corpus ENDPOINT=DIR`, and refuses to start
   without one. For 161 endpoints that is 161 flags. A `--corpus-root DIR`
   that resolves `DIR/<endpoint>/` would let the whole manifest be driven with
   one flag. Purely additive to `testbed.py`'s argument parsing.
2. **Spec-from-manifest.** A loader that reads `sweep_endpoints.json` into the
   spec's `endpoints` key, so re-running `build_manifest.py` re-plans the
   sweep without a hand edit. This could equally live here rather than in
   `src_new/`.

Neither was implemented, per instructions.

---

## Regenerating

Three steps. Only the first needs the app.

```bash
# 1. introspect the booted app  (~2 min, needs the JRuby/JDK env)
cd /home/dev/project/ruby_examples/dse-apps/apps/diaspora
export PATH="/home/dev/tools/jdk-21.0.5/bin:/home/dev/tools/jruby-9.3.0.0/bin:$PATH"
export JAVA_HOME=/home/dev/tools/jdk-21.0.5 GEM_HOME=/home/dev/.gem/jruby/2.6.0
export RAILS_ENV=concolic
bundle exec jruby \
  /home/dev/project/reports/autolab/entrypoints/tools/introspect_entrypoints.rb \
  /home/dev/project/reports/autolab/entrypoints/raw_introspection.json

# 2. build the manifest
cd /home/dev/project/reports/autolab/entrypoints/tools
/home/dev/project/venvs/queries_from_runs/bin/python3 build_manifest.py

# 3. regenerate the scaffolding
/home/dev/project/venvs/queries_from_runs/bin/python3 scaffold.py

# check: every generated runner parses (one JRuby process, ~20 s)
cd .. && jruby tools/syntax_check.rb lib scaffold
```

The introspector writes to the file named by `ARGV[0]` rather than stdout,
because an app initializer prints `Rack::SSL is enabled` at boot.

## Adding or fixing an endpoint

Do not hand-edit `manifest.json` or anything in `scaffold/` — both are
generated and will be overwritten.

* **A route or filter changed in the app** → re-run step 1.
* **A cost weight or tier cut is wrong** → edit the weights in
  `build_manifest.py` (they are one dict) and re-run steps 2–3.
* **A seed value is implausible** → `NAMED_SEEDS` / `ID_SEEDS` in
  `scaffold.py`.
* **An endpoint needs real mocks** → that is the *targets* half: add
  `targets/endpoints/<id>.rb` and an entry in `targets/registry.json`. The
  driver picks it up automatically at the next launch; nothing here changes.
* **You are ready to curate an endpoint** → copy `scaffold/<id>/` out of
  `scaffold/` (which is generated) and start editing, in particular replacing
  the generic terminal policy with a real `app_error_terminal?` predicate.

## How a runner is put together

`scaffold/<id>/run_dse.rb` is ~45 lines and contains only a `CFG`. Everything
else is `lib/autolab_dse.rb`, which is the ~450 lines that the two
hand-written reference runners have in common — the runners of the two
endpoints with curated targets, at
`reports/diaspora/results4/<endpoint>/run_dse.rb`. Those ~450 lines are: the
`ActionController::TestCase` rig factory, the lazily-memoized symbolic principal
(`symint("SYM_USER_CI_id", …)` through real Devise
`User.serialize_from_session`), the structured-term-to-string renderer, the
four flip matchers, the FIFO prefix-directed worklist, the MD5 seed/path
dedup, and the `@all_calls` leak workaround.

Three invariants in there were paid for by those reference runners and carry
"GROUND TRUTH" comments; do not simplify one away without re-measuring:

1. **Symbolic entry arguments must be declared *inside* the `run` block.**
   `CallInterceptor#run` calls `SymbolicFunc.reset!` at entry, so a `symstr`
   made earlier never reaches `symbolic_vars` and Z3 drops every path
   condition over it.
2. **`pc_expr_to_s` must render structured terms back to the old string
   spelling.** The flip matchers are regexes over that spelling; without the
   renderer every PC is booked "unflippable" and the worklist drains after
   one run reporting `worklist_exhausted: true` — a *false completion
   signal*, not a visible failure.
3. **The principal id stays symbolic.** A concrete key folds every signed-in
   view to `users.id = 1` instead of `_MY_UID`. `PRINCIPAL` in the driver
   refuses to reseed those vars.

## What launching a sample actually showed

`tools/smoke.sh` launched a 14-endpoint sample (both endpoints with curated
targets plus three candidates from each of tiers 1–4) with `MAX_RUNS=3`,
`TIME_BUDGET=120`. Results in `smoke_results.json`; per-endpoint output in
`smoke_logs/`.

**Result: 14 of 14 launched productively** — every one booted, dispatched its
action and wrote dumps plus an `exploration_summary.json`. 12 of the 14 had
*no* target override and ran on the shared core alone.

That is 14 of 161, not 161 of 161. The other 147 are scaffolded and
unattempted.

The useful part of the exercise is what it *broke*, because both failures
were in this lab's own driver and both are now fixed:

1. **Namespaced controllers could not be rigged.** `make_harness` registered
   the `ActionController::TestCase` subclass as a top-level constant named
   after the controller, so `Api::OpenidConnect::IdTokensController` produced
   `NameError: wrong constant name
   Api::OpenidConnect::IdTokensControllerTest`. The two reference runners only
   ever drove top-level controllers, so the case had never arisen. It affects
   every `api/openid_connect/*` and `admin/*` endpoint — about 20 of the 161.
   Fixed by flattening the namespace.
2. **Implicit-render actions raised instead of rendering.** `help#faq` has no
   method, so `ctrl.send(:faq)` raised `NoMethodError`, which the generic
   terminal policy dutifully recorded as an app outcome. Direct dispatch skips
   the machinery that would have rendered `app/views/help/faq.html.haml`.
   Fixed by calling `default_render` when the action has no method.

Neither bug is reachable from the two reference runners; both were found only
by generalising to the whole app. That is the argument for the smoke tool
existing. Before the fixes the same sample scored 11 productive, 1 partial
and 2 no-paths; after, 14 productive.

What the sample does **not** establish: that exploration is complete, that
the mocks are right, or that anything generalises to the 147 untried
endpoints. One candidate,
`api_openid_connect_user_applications_index`, records three `NoMethodError`
terminals — an unmocked call site on a core-only endpoint, which is exactly
the finding the driver's `tier=candidate` warning predicts.

### What the generated runner does *not* have

A curated **app-error terminal policy**. Each reference runner hand-wrote an
`app_error_terminal?` predicate naming the unrescued 500s that are genuine
outcomes *for that action*. A generated runner cannot know that list, so it
records every unrescued exception as a terminal and stamps the summary with
`"terminal_policy": "generic (uncurated…)"`. Writing that predicate is part
of promoting an endpoint from scaffolded to driven.
