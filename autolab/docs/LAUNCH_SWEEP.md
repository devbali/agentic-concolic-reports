# Launching the 161-endpoint cloud sweep

Written 2026-09-28 for someone who was not here. The build is done and the
pilot has been run; **the 161-endpoint sweep has deliberately not been
started** — it was taken out of scope so it would not run unsupervised.

Everything below is either a command you can paste or a fact you can check.
Where something is uncertain, it says so.

---

## 0. The one-paragraph summary

A batch worker's agent now runs **on the provisioned VM**, not in the
coordinator's process. The route taken was *an agent-building branch in
agentd's entrypoint* (§8.3/§8.4's second option); §8.2's `agent` field became
`execution.base.AgentBackendSpec`, which carries everything `agentd` needs to
construct the adapter on the box. The box bundle now carries node and `dsh`
and the OpenRouter route. `OPENROUTER_API_KEY` reaches the VM as a **name** in
every document and a **value** only in a process environment. The dev box runs
the coordinator and nothing else.

---

## 1. The command

**Read these three before you paste it.** Each is explained below; each will
cost you money or time if you skip it.

1. **The run will stop at the first endpoint that reaches CHECKING** — a
   `check` worker has no remote drive and now refuses a non-co-located
   backend loudly rather than computing a verdict on the wrong machine
   (§8 item 1). Lift that branch first, or accept that the sweep gets as far
   as EXPLORING.
2. **Lower `max_wall_s` first** (§5, "the brake that does not exist"). At
   6-12 hours it is not a bound, `dsh` enforces no turn or dollar cap of its
   own, and a confused agent holds a billing VM for the whole window.
3. **Always run §7 afterwards, however the run ended.** `reap()` cannot see
   a box whose worker was still running (§8 item 10).

```bash
export PATH=/home/dev/tools/google-cloud-sdk/bin:$PATH
mkdir -p /home/dev/project/reports/autolab/entrypoints/sweep_out_or

cd /home/dev/project && venvs/sky/bin/python3 reports/autolab/tools/run_real_sweep.py \
  --spec      reports/autolab/entrypoints/sweep_openrouter.json \
  --out       /home/dev/project/reports/autolab/entrypoints/sweep_out_or \
  --corpus-root /home/dev/project/reports/autolab/e2e/runs \
  --execution skypilot \
  --region    us-central1 \
  --instance-type sm=n2-standard-2,md=n2-standard-4 \
  --repo      /home/dev/project/ruby_examples/dse-apps/apps/diaspora \
  --domain    ruby_rails_sql \
  --app-revision diaspora-concolic \
  --app-tree-digest "$(python3 reports/autolab/local_cvd6/tools/app_tree_digest.py)" \
  --engine-digest  "$(PYTHONPATH=src_new python3 -m sweep.engine_digest)" \
  --max-steps 4000 \
  --interval-s 5 \
  2>&1 | tee reports/autolab/entrypoints/sweep_out_or/sweep.log
```

Why each flag:

| flag | why it is there |
|---|---|
| `venvs/sky/bin/python3` | the **only** interpreter on this machine that can `import sky`. `venvs/queries_from_runs` cannot; the runner will die on the import. |
| `PATH=…/google-cloud-sdk/bin` | SkyPilot shells out to `gcloud` for GCP provisioning and to `ssh`/`rsync` over the host alias it writes. Without it `preflight()` reports not-ready and the launch fails after you have waited for it. |
| `--spec sweep_openrouter.json` | the 161-endpoint spec. `usd_total: 8.00`, `usd_per_endpoint: 0.045`, `max_concurrent_vms: 3`. |
| `--out …/sweep_out_or` | the coordinator's own disk: `workers.jsonl`, per-box local mirrors under `boxes/`, and the fetched packets. Nothing here is on a VM. |
| `--corpus-root …/e2e/runs` | `<root>/<endpoint>/dump_*.json`. **Required**: every endpoint enters EXPLORING, EXPLORING is a batch worker over a corpus, and `build_coordinator` refuses an endpoint with none. All 161 have dumps there. |
| `--app-tree-digest` | the pre-gate's app-tree PIN, measured by the campaign's own script. Left out, the comparison reports NOT CONFIGURED on every attempt — a recorded gap, never a match — so an app edit nobody proposed would not be caught. |
| `--engine-digest` | the pre-gate's ENGINE pin: a digest of the content of the trees whose code a drive runs. A revision name cannot be checked — in a tree with uncommitted work it names code that is not on disk — so the gate compares this against the packet's `runtime_digest` and against the tree the gate is itself running in. Measure it before you launch and paste the value; `--engine-digest now` measures at launch instead, which still catches a tree that moves under the campaign but cannot catch a campaign launched against the wrong tree. |
| `--execution skypilot` | the boxes are GCP VMs. This used to be refused; see §2. |
| `--instance-type sm=…,md=…` | **not cosmetic — see §6.** Left to the optimizer, SkyPilot picks `n4-standard-2`, and n4 had **no capacity in any us-central1 zone** on 2026-09-28. The spec has 77 `sm` and 84 `md` boxes, so one shape will not do: the per-class form pins each. |
| `--repo …/apps/diaspora` | §6.2 mounts the app checkout `ro` into each box. The seam carries no repo, so the runner must be told. |
| `--domain ruby_rails_sql` | §6.3's pass-through name; there is no spec key for it. |
| `--app-revision` | §12.1's provenance half — what revision of the app was explored. Free-form. |
| `--max-steps 4000` | the scheduling loop's bound. 161 endpoints × several transitions each; 400 (the default) stops the sweep early and silently. |
| `--interval-s 5` | one scheduler tick every 5 s. |

Two flags deliberately **not** used:

* `--allow-shared-machine` — §8.5's grant is only needed by a backend that
  cannot isolate a filesystem. SkyPilot can, and passing it anyway would hand
  every worker a waiver for a rule that was already satisfied.
* `--no-refresh` — leaving it off keeps `SpecRefresher` live, so the console's
  money levers actually bite mid-run. Add it only if you want the spec frozen.

**The command above has been dry-run exactly as written**
(`--dry` appended, which builds everything and calls no model):
`reports/autolab/pilot_evidence/dryrun_161.txt`. All 161 endpoints resolved
their corpora, the spec parsed, the box-side agent was constructed, and
nothing was launched. That is the whole of what "launch-ready" is claimed to
mean here — it says nothing about what the sweep will find.

### The console (optional, recommended)

```bash
cd /home/dev/project && venvs/queries_from_runs/bin/python3 -c \
  'import sys; from sweep.console.server import main; sys.exit(main())' \
  /home/dev/project/reports/autolab/entrypoints/sweep_out_or \
  --bind 0.0.0.0 --port 8787 \
  --spec /home/dev/project/reports/autolab/entrypoints/sweep_openrouter.json
```

It reads the out directory and the spec; it is a dependency of nothing.

---

## 2. Which §8.3/§8.4 route was taken, and why

`sweep/workers/base.py::agent_supervisor_for` used to say:

> an agentic worker in docker or skypilot needs either an argv on the
> interface or an agent-building branch in agentd's entrypoint, and that is a
> decision for whoever builds §8.3/§8.4

**The branch in agentd was taken.** Three reasons, all from the design rather
than from convenience:

1. **§7.2's first line** is "`AgentBackend` runs *inside* the box, driven by
   `agentd`", and **§8.1's first bullet** gives agentd "the agent process (via
   an `AgentBackend`, §7.2)". The adapter belongs on the box; that is what
   these two sentences say.
2. **The argv route contradicts them.** Only the coordinator could build a
   harness argv, so the adapter would have to live there — the opposite of
   §7.2 — and agentd would be left supervising an opaque subprocess.
3. **agentd's own listed jobs need the object.** §7.3's event normalization,
   routing §8.1's `interject` frame "to the backend's rung (§7.5)", and §7.2's
   `usage()` are all adapter methods. The cheaper-looking route would have had
   to reimplement three of the things agentd exists to do.

### What actually changed

| file | change |
|---|---|
| `sweep/execution/base.py` | **`AgentBackendSpec`** — §8.2's `agent` field, widened from identity (`{backend, model}`) to buildable (`+ ctor`, `+ brief`, `+ env_passthrough`). `remote_agent_spec()` asks an adapter to describe itself. `refusals_for` now refuses "no argv **and** no buildable agent" instead of "no argv". `BackendCapabilities.colocated` (default `True`). |
| `sweep/agentd/__main__.py` | **the branch.** `build_agent_worker()` resolves the adapter by name through `sweep.agents.build_adapter`, merges `env_passthrough` from agentd's own environment, and wraps it in `AgentWorker`. Imported lazily inside `build()` — `sweep.agentd` is the bottom layer and a top-level import would close a cycle. |
| `sweep/agentd/main.py` | `_finish` asks the worker for `final_accounting()` (duck-typed, exactly like the sampler) and puts it on the `done` frame. Without it the adapter's turns, denials, budget flag and cumulative usage die on the box. |
| `sweep/agents/{claude_code,deepseek}.py` | `remote_spec()` — each adapter describes its own constructor (§7.7 rule 2: only this package may know a backend's name). `env_passthrough` names are reported and their values dropped. `caps` is carried, because §7.6(a)'s shim is `ClaudeCodeBackend` with three capabilities removed and a rebuild that defaulted them would lie to §7.5's ladder. |
| `sweep/agents/__init__.py` | `build_adapter(name, ctor)` — the one place a serialized adapter becomes an object. |
| `sweep/agents/base.py` | `Usage.from_json`, `Termination.from_json`. |
| `sweep/workers/base.py` | `drive_agent_remote()` — `drive_agent`'s twin for a box on another machine: `launch()`, read frames off the `Channel`, `fetch()` the artifacts into the same `tree.out` the co-located path uses, and build the same `AgentRun`. Plus a **`hello` deadline** and a **synthetic `done`** (see §6). `supervises_in_process(backend)` is the capability question — never a backend name. |
| `sweep/workers/batch.py` | `run_batch` branches on `supervises_in_process`. `box_root_for()` decides whether the brief is written for the mirror's path or for `/work`. `_cost_for()` applies §11.2's table (see §5). Everything after `stage()` is wrapped so **no exception can leave a provisioned box running** — on `host` that clause is free, on §8.4 it is the difference between an error and a bill. |
| `sweep/workers/{check,concrete}.py` | **refuse** on a non-co-located backend rather than silently supervising a mirror. See §8 — this is the main thing left undone. |
| `sweep/testbed.py` | `--allow-shared-machine` is now required only when the backend cannot isolate a filesystem. |
| `sweep/execution/skypilot.py` | `colocated=False`; `TaskPlan.secret_envs` and `instance_type` (per box class). |

### `host` is unchanged — with one deliberate exception

The negative control below asserts it mechanically. The one thing that *does*
change on `host` is the §5 cost wiring: a worker whose adapter reports no
dollars and whose spec carries a price table for its route now gets a
**DERIVED** `Cost` where it previously got `None`. That is the fix, not a
side effect, and it applies to both backends because §11.2's table belongs to
the spec rather than to a box. Everything else — the supervisor, the brief's
root, the frames, the refusals, `launch()` staying uncalled — is identical,
and `sweep/tests/test_workers_batch.py` passes unmodified.

### The negative control

`sweep/tests/test_workers_remote_agent.py` (19 tests) holds both halves. The
control that matters:

* `test_the_host_path_never_launches_and_runs_the_adapter_in_this_process`
  wraps `HostBackend.launch` in a counter and asserts it is **never called**,
  that `result.remote is None`, and that the coordinator's own adapter object
  *did* open a session.
* `test_a_spec_built_the_old_way_is_still_refused_for_its_empty_argv` asserts
  the §8.2 refusal is unchanged — same rule, same capability name — for a spec
  with no agent block.
* `test_the_host_brief_still_names_the_box_directory_and_not_slash_work`.

The positive is a `FakeVMBackend` whose `launch()` starts a **real
`python -m sweep.agentd` subprocess** against a tree the coordinator does not
supervise. `test_the_remote_run_accounts_for_exactly_what_the_host_run_does`
is a differential: the same plan run co-located and remote must report the
same tokens, turns, tool calls, denials and **the same `cost`** — and `cost`
here is the adapter's own `total_cost_usd`, which exists only on the
`Termination` its `stop()` returned on the far side, so a matching figure
cannot have come from anywhere but the `done` frame.

---

## 3. Preconditions — check every one before you launch

```bash
# 1. gcloud on PATH and SkyPilot ready. Must print ready=True missing=[]
export PATH=/home/dev/tools/google-cloud-sdk/bin:$PATH
cd /home/dev/project && PYTHONPATH=src_new venvs/sky/bin/python3 -c \
  'from sweep.execution.skypilot import preflight; p=preflight(); print("ready=",p.ready,"missing=",list(p.missing))'

# 2. The SkyPilot API server. One process drives many clusters (§8.4).
#    It is already running; if not, `sky api start --deploy` under venvs/sky.
#    Listed through the wait helper rather than `pgrep -f`: a pattern matches
#    the command line of whatever shell you run it from as readily as the
#    server's, and `--list` identifies by executable and prints what matched.
PYTHONPATH=src_new venvs/queries_from_runs/bin/python3 -m sweep.box.wait_for \
  --exe /home/dev/project/venvs/sky/bin/python3 --contains sky.server.server --list

# 3. The key file. 73 bytes, starts sk-or-v1-.
wc -c /home/dev/project/openrouter_api_key.txt

# 4. Remaining OpenRouter credit — THE REAL CEILING.
curl -s -H "Authorization: Bearer $(cat /home/dev/project/openrouter_api_key.txt)" \
     https://openrouter.ai/api/v1/credits

# 5. The bundle exists and is current.
ls -l /home/dev/project/src_new/sweep/box/dist/box-bundle.tar.gz
cat /home/dev/project/src_new/sweep/box/dist/bundle.json

# 6. No clusters of ours are up.
cd /home/dev/project && venvs/sky/bin/python3 -c \
  'import sys; sys.path.insert(0,"src_new"); from sweep.execution.skypilot import RealSky; print(RealSky().status())'
```

### Rebuilding the bundle

Needed whenever `src_new/`, the app, the entrypoint scaffold, the targets or
`$DSH_HOME` change:

```bash
cd /home/dev/project/src_new && venvs/queries_from_runs/bin/python -m sweep.box.build \
  --manifest /home/dev/project/reports/autolab/box/manifest.json
```

It lands at `src_new/sweep/box/dist/box-bundle.tar.gz` (400.9 MB gz, 1.11 GB
uncompressed, 20 034 files) with a `bundle.json` sidecar carrying its sha256.
`bundle_mount()` refuses to build a task plan if it is missing — a setup
script with no bundle is a VM that provisions, fails, and costs money for
nothing.

### What is in the box, and what is new

`reports/autolab/box/manifest.json` — **it lives under `reports/` and not in
`src_new/`, because nothing in the source tree may name an application
(`tests/test_self_contained.py::NoAppPathsInTheSource`).** The trees are
reproduced at their absolute paths inside the box.

New for the agentic worker:

* `npm: ["@deepseek-ai/dsh@0.1.7-rc.2"]` — `setup_script` installs node 22
  from nodesource and then `npm install -g` the harness. **This was already
  in the manifest and was being thrown away**: the runner passed `npm=()`,
  which overrode it, so the box got python, JRuby and the app and *no
  harness*. That override is gone.
* a new tree, `/home/dev/project/reports/autolab/box/dshhome`, which is
  `$DSH_HOME` — four small files, the one that matters being
  `profiles/sdk/cordis.patch.yml` with `api: openai-completions`,
  `baseURL: https://openrouter.ai/api/v1`, `apiKeyEnv: OPENROUTER_API_KEY`,
  model `deepseek/deepseek-chat`. **No adapter code was changed to get the
  OpenRouter route; it is ordinary configuration in the profile's user
  layer.** See that directory's `README.md`.
* `verify_cmds` gained `node --version` and
  `env DSH_HOME=… HOME=/home/dev dsh --version`. This matters more than it
  looks: **SkyPilot 0.13 detaches setup**, so the only cheap place to discover
  a missing harness is inside the script that installs it.
* `writable: ["/home/dev"]` — one `chown -R`, because the batch agent runs
  with `HOME=/home/dev` on the box and `dsh`/`npm` write caches under it.

---

## 4. How the key reaches the box

`OPENROUTER_API_KEY` is **never** in the bundle, the task document, the box
record, an event log, a packet or anything synced back. There are exactly
three places it exists, and only the first two are on any machine we own:

1. **`/home/dev/project/openrouter_api_key.txt`** on the dev box, read by the
   runner at startup and placed in `os.environ[KEY_VAR]` of the coordinator
   process. Nothing else writes it.
2. **SkyPilot's task `envs`**, resolved at launch. `TaskPlan` carries
   `secret_envs` — a tuple of **names** — and `RealSky.to_task()` is the only
   code that reads the value, out of the coordinator's own environment, at the
   moment it builds the `sky.Task`. `TaskPlan.as_json()` (which *is* written
   to `boxes/<id>/ctl/box.json` on the dev box and *is* rsynced up with
   `ctl/`) prints `"secret_envs": ["OPENROUTER_API_KEY"]` and nothing else,
   because the dataclass does not hold the value.
3. **agentd's process environment on the VM.** The task document carries
   `agent.env_passthrough: ["OPENROUTER_API_KEY"]` — a name. `agentd`'s
   `build_agent_worker()` resolves that name against its own environment on
   the box and merges the value into the adapter's `base_env`. `dsh` then
   reads it because the profile says `apiKeyEnv: OPENROUTER_API_KEY`.

The box-side adapter is *constructed on the dev box* (to be serialized) and
would otherwise carry the key in `base_env`; `remote_spec()` excludes every
`env_passthrough` name from what it reports. A name that is not set on the box
is **skipped, not blanked** — an adapter that fails to authenticate says more
than one authenticating as nobody.

Asserted by:

* `test_a_passthrough_credential_is_never_written_into_the_task_document`
* `test_a_secret_env_name_reaches_the_plan_without_its_value`
* `test_the_box_side_agent_carries_no_key_and_names_box_paths`
  (with a negative control: co-located, the value *is* in `base_env`, because
  there the adapter is about to spawn a child of this very process)
* `test_the_box_manifest_carries_the_harness_and_the_route_and_no_key`

**Residual, stated rather than hidden:** SkyPilot persists a task's `envs` in
its own on-VM metadata and state DB. That is the environment path SkyPilot
provides and there is no narrower one; the VM is torn down at the end of the
attempt. Nothing under our control writes the value anywhere.

---

## 5. Money

### The real ceiling

**OpenRouter credit at the moment this was written: $8.739554556**
(`total_credits: 90`, `total_usage: 81.260445444`, read 2026-09-28 20:52 UTC,
after the pilot and after teardown). The pilot cost **$0.002670531** in total
— one turn. The number moves; the command below is the only truth.

**OpenRouter credit is the hard cap** — the account stops serving when it is
exhausted. Read it, do not assume it:

```bash
curl -s -H "Authorization: Bearer $(cat /home/dev/project/openrouter_api_key.txt)" \
     https://openrouter.ai/api/v1/credits
```

### `derived_cost()` is now wired

It had no caller outside tests, so every `dsh` worker's row carried
`cost: null` and §11.4 summed a genuinely-spending sweep to `usd_total: 0.00`.

* `telemetry.usage.derived_cost(tokens, rates, as_of, margin)` is now the one
  multiplication, shared by `agents/deepseek.py::derived_cost` (which has a
  live `Session`) and by `workers/batch.py::_cost_for` (which has only a
  `TokenCounts`, because on a remote box the session ended on the VM).
* `BatchPlan` carries the route's rates; `binding.py` reads them off
  `req.spec.prices`.
* **A measured figure always wins** and is never re-derived.
* **No table, or no row for this route, leaves the cost `None`** — not
  `0.00`. None and zero are different claims.

### The table is deliberately not the list price

See `reports/autolab/entrypoints/PRICES.md`. Measured 2026-09-28: one real
OpenRouter turn billed **$0.00472779** against **$0.00381386** derived from
list price — a 24.0 % understatement, because OpenRouter routes to third-party
providers and the request carries nothing saying which one served it. Pinning
the upstream provider would need a `provider` routing field that `dsh`'s
`openai-completions` adapter cannot send, so **the table was raised by
×1.2396** in both specs:

    list    input 0.2574    output 1.0287     USD / Mtok
    table   input 0.319073  output 1.275177   USD / Mtok

`margin: 0.15` sits on top, as §11.2.1 requires.

**The derived figure is still an estimate.** OpenRouter's `/credits` endpoint
is the truth. Check it before, during and after.

### THE BRAKE THAT DOES NOT EXIST — read this before launching

**`dsh` enforces neither `max_turns` nor `max_usd`.** `agents/deepseek.py`
reports both as *unmapped task fields* and says why: `caps.budget_cap` is
False, and "the box and agentd's wall clock bound" a `dsh` worker instead.
`sweep/testbed.py` does not wire `max_turns` either, so it is `None` anyway.

So the brakes on model spend, in the order they bite:

1. **`boxes.<class>.max_wall_s`** — agentd's ceiling, the ONLY thing that
   stops a running `dsh` worker. `sweep_openrouter.json` currently sets
   **21 600 s (6 h) for `sm` and 43 200 s (12 h) for `md`.**
2. **the admission-time budget** (`budgets.usd_total`, `usd_per_endpoint`) —
   it decides whether the NEXT worker may start. It does not reach into one
   that is already running.
3. **the supervisor's spend allowance** — `ALLOWANCE` in
   `entrypoints/sweep_out_w*/supervise*.sh`. It polls `/credits`, and when
   `total_usage` minus the baseline it read AT ITS OWN START reaches the
   allowance it enqueues a `stop`. **This is a DELTA, and it must stay one**
   (fixed 2026-10-03): it used to be `CEIL=<absolute total_usage>`, which is
   meaningless on this key — the key is SHARED and AUTO-TOPS-UP, so
   `total_usage` moves for reasons that have nothing to do with the sweep
   ($52 over four days while both sweeps had zero boxes). With live usage
   around 133.40, the old W2/W3 ceilings of 123.01 and 130.96 would fire on
   the first poll, before a box launched. A supervisor that cannot read its
   baseline now ABORTS (exit 2, `qlogs/STOPPED` = `NO_BASELINE`) rather than
   running with no brake.
4. **the OpenRouter credit running out** — a hard stop, mid-turn. **Do not
   rely on this.** It was brake 3 in this list until 2026-10-03, on the
   assumption of a fixed prepaid balance; auto-top-up removes it entirely.

**Re-deriving a past run's ceiling from today's `/credits` does not work**,
and this is how the record gets misread: the thresholds recorded in
`sweep_out_w3/RESULT.md` and in the `qlogs/` were correct against a baseline
a human read minutes before launching, so comparing them with a later
account-cumulative figure makes a pass that stayed inside its allowance look
like an overrun. The allowance and the baseline are both logged at start
(`spend baseline total_usage=… allowance=…`) — read that line, not the
absolute.

At roughly **$0.0047 per turn and ~14.7k input tokens each**, $0.045 per
endpoint is about **9-10 turns**. A six-hour box is not 10 turns; it is
hundreds. **One endpoint left alone at the current `max_wall_s` can consume
the whole remaining credit before the budget lever ever gets a say.**

**Recommendation before starting the 161 run: lower `max_wall_s` to something
matched to the per-endpoint budget** — e.g. `900` (15 min) for both `sm` and
`md` in `sweep_openrouter.json`. It is a spec edit and `SpecRefresher` picks
it up live, so it can also be tightened mid-run. This has NOT been changed for
you, because choosing the number is a decision about what an endpoint is
allowed to attempt, not a bug fix.

### VM cost is a different account

GCP box-hours are not on the OpenRouter credit. `n2-standard-2` is about
**$0.10/hr** and `n2-standard-4` about **$0.19/hr**; with
`max_concurrent_vms: 3` the sweep's ceiling is roughly $0.5/hr while it runs.
`--idle-minutes-to-autostop 15` and `--down` are set as a backstop for the
case where the coordinator dies hard.

---

## 6. What to watch, and what means stop

### Normal

```
[hh:mm:ss] spec=… endpoints=[…]
[hh:mm:ss] execution=skypilot agent=dsh/openrouter refresher=ON
[hh:mm:ss] agent runs ON THE BOX; dsh=dsh DSH_HOME=/home/dev/project/reports/autolab/box/dshhome;
           OPENROUTER_API_KEY reaches it as a NAME in the task document + a VALUE in SkyPilot envs
Running on cluster: sweep-worker-batch-<endpoint>-…
 GCP (us-central1-a)  n2-standard-2  2  8  -  0.10  ✔
⚙︎ Launching on GCP us-central1 (us-central1-a).
└── Instance is up.
```

then, per box, in order: file sync (the 400 MB bundle), `setup` (apt, python
3.12 from deadsnakes, untar, pip, node, `npm install -g dsh`, verify), the
`run` command (`agentd`), and then frames.

### The signals that mean stop

| signal | what it is | what to do |
|---|---|---|
| **a cluster is UP and no `hello` frame ever arrives** | **the big one.** SkyPilot 0.13 **detaches setup**, so `sky.launch` returns success and `LaunchOutcome.setup_failed` is `False` *even when setup exited non-zero*. The cluster then sits UP and billing with nothing on it. | `drive_agent_remote`'s `hello_timeout_s` (default 900 s) catches it, synthesises a terminal `done` with `reason: "no_hello"`, and the run tears the box down. If you see `no_hello`, read the real reason with `sky logs <cluster> 1` — **do that before the teardown removes the cluster**, or re-run one endpoint with `--keep`-style debugging. |
| `ResourcesUnavailableError` walking zones a→b→c→f | the instance family has no capacity. Measured on `n4` in all four us-central1 zones on 2026-09-28. | this is why `--instance-type` is pinned. If it recurs on `n2`, pin a different shape or change `--region`. |
| `ClusterLeaked` | a launch failed **and** the teardown that should have cleaned it up also failed. There may be a billed VM. | the message names the cluster and the box record. Run `sky down <cluster>` immediately, then the §7 verification. |
| every endpoint reporting `complete: false` | **expected, and not disguised.** No endpoint config carries a `completion` block, so one-stack's checker has no completion criterion to satisfy and cannot report `true`. It is not a symptom of the sweep failing and it is not evidence that it succeeded either — it means the question was never asked. |
| `usd_total` climbing toward 8.00, or `/credits` falling toward 0 | the budget lever biting, or the account about to stop serving | the console's money levers are live with `SpecRefresher`; lower `budgets.usd_total` in the spec file and it takes effect on the next interval. |
| `exit_reason: wall_clock` on many endpoints | boxes hitting `max_wall_s` (21 600 s `sm` / 43 200 s `md`) without submitting | not a money emergency, but the attempts are being wasted. |
| `CHECKING` reached | see §8 — a check worker on skypilot **refuses**, loudly, by design | expected; it is the known gap. |

### Teardown is on every exit path

`shutdown()` is registered on `SIGINT`, `SIGTERM` and `atexit`, is idempotent,
calls `reap(stop=True)` and prints `sky status` afterwards. `launch()` itself
tears down on **any** exception including `KeyboardInterrupt` — a Ctrl-C in
the middle of a provision is exactly when a VM gets left running.

---

## 7. Verifying zero clusters

```bash
export PATH=/home/dev/tools/google-cloud-sdk/bin:$PATH
cd /home/dev/project && venvs/sky/bin/python3 -c \
  'import sys; sys.path.insert(0,"src_new"); from sweep.execution.skypilot import RealSky; print(RealSky().status())'
gcloud compute instances list --filter="status=RUNNING" --format="table(name,zone,status,machineType)"
```

**Seven pre-existing GCP VMs are not ours and must be left alone:**
`jim-blockaid`, `policy-extraction-arm-jamie`, `scalog-machine`,
`instance-20260531-tack-client`, `instance-20260531-tack-switch`, and the two
ray heads `cpu-64-…-head-…` and `h100-2-…-head-…`. Anything named
`sweep-worker-…` is ours.

---

## 8. Left undone, and uncertain — named plainly

1. **`check` and `concrete` workers have no remote drive.** Only §6.2's
   `batch` worker branches. `run_check` and `run_concrete` now **raise a
   `WorkerError`** on a non-co-located backend rather than silently
   supervising a local mirror — a verdict computed on the wrong machine is
   worse than no verdict. **The 161-endpoint sweep will therefore stop at the
   first endpoint that reaches CHECKING.** The work to lift it is small and
   known and the refusal messages say what it is: a check worker *has* a
   static argv, so `launch()` already works for it (gate 2 proved that on a
   real VM), and `workers.base.drive_agent_remote` is generic over the frames;
   what is missing is writing the brief for `/work` instead of the mirror and
   reading `done` off the drive. Until then, either lift it or run check
   workers on `host`.
2. **`concrete` likewise**, same shape, same refusal.
3. **Interjection down the channel is not wired for the remote path.**
   `SkyChannel.send()` exists and `drive_agent_remote` never calls it; agentd
   ships no downlink reader loop either (`host.FileChannel` records the same).
   Nothing in the sweep interjects today, so this is a gap and not a
   regression.
4. **`host.FileChannel` (host.py:493-499) still has the cached-reader
   defect** that `SkyChannel.frames()` was fixed for: `EventLog._last_seq` is
   computed once in `__init__`, so a long-lived reader over an appending log
   answers `since(n)` with `SequenceGap` for frames sitting in the file it
   just read. It already tore down a healthy cluster once, on the cloud side.
   Not fixed here because "host behaviour unchanged" was a requirement of this
   change; it should be fixed deliberately, with its own test.
5. **`--instance-type` is a pin, not a floor.** The shape *replaces* the
   cpu/memory search. If you change a box class in the spec you must change
   the pin to match, or the box will be the wrong size with nothing objecting.
6. **The price table is an estimate raised by a single measured ratio** (one
   turn). If OpenRouter routes differently on another day the 1.2396 will be
   wrong. `/credits` is the only truth.
7. **`dsh` resolves its profile bundles from the global npm install.** On the
   dev box the same profile worked against a *local* install. It is verified
   on the box by `dsh --version` in setup, but a run-time `pnpm` fetch inside
   `dsh --profile sdk` (if one happens) has not been observed on a VM.
8. **`derived_cost` covers model tokens only.** Box-hours are §11.3's
   `box_hours` column and are not converted to dollars anywhere.
9. **No in-flight spend brake for `dsh`.** See §5's "the brake that does not
   exist". `max_wall_s` is the only one, and it is currently set six to twelve
   hours. This is the single biggest risk in running the sweep unattended.
10. **`SkyPilotBackend.reap()` cannot see a box whose worker is still
    running — a src/ defect, found by the pilot and worked around, not
    fixed.** MEASURED: the pilot was interrupted with SIGTERM mid-worker,
    `reap(stop=True)` returned `[]`, and the VM was still `UP`.

    `reap()` builds a `why` per listed cluster and `continue`s past any it
    cannot name a reason for. Its four reasons are a failed previous
    teardown, a deliberate `keep_on_failure`, a cluster stuck in INIT past
    the grace period, and **a record saying GONE while the cluster is UP**.
    "Recorded RUNNING, cluster UP" is correctly a healthy box *during a run*
    — and at shutdown there is no worker left to own it, which is exactly
    what a Ctrl-C leaves behind.

    The workaround is in the runner: `shutdown()` now tears down every box in
    `backend.boxes` by recorded identity BEFORE reaping, with a control test
    (`test_shutdown_tears_down_a_live_box_that_reap_alone_misses`) that shows
    reap alone leaving the cluster up. **The underlying `reap()` is still
    blind to the case**, so any other caller — a restarted coordinator
    following §12.4, a reap on a timer — has the same hole. Fixing it means
    deciding what a "live" recorded box means to a process that did not
    launch it, which is §8.5's recorded-identity rule and deserves its own
    change with its own test.

    Until then: `--idle-minutes-to-autostop 15 --down` is the only backstop,
    so a missed box bills for up to 15 minutes. **Always run §7 after a
    sweep ends, however it ended.**
11. **`dsh` does not exit when its turn ends** (pilot, §"why it was
    stopped" in `PILOT.md`). A batch worker that finishes a turn without
    submitting goes idle and agentd holds it to `max_wall_s`. Combined with
    (9), one confused agent is a six-hour VM. This is the strongest reason to
    lower `max_wall_s` before launching.
12. **`deepseek/deepseek-chat` did not do the task.** The pilot's agent
    replied conversationally *about* the worker protocol
    ("It seems you've provided detailed instructions about a worker protocol
    and endpoint exploration process…") rather than exploring the endpoint,
    and submitted nothing. One turn is not evidence about a model, and the
    plumbing is not implicated — but nothing has yet shown this model
    producing a packet on this brief, and a 161-endpoint sweep is a large
    bet on it doing so. **Worth one more single-endpoint run, watched, before
    widening.** The `--spec`'s `agents.batch.backend`/`model` is one line if
    you want a different harness.
13. **OpenRouter upstream rate limiting is real and unmeasured at scale.**
    The pilot's very first call took five `429 … temporarily rate-limited
    upstream` before succeeding on retry 5 (`dsh` backs off 0.5 s → 8.3 s).
    With `parallel_batch_agents: 3` against the same model this will be
    constant, and nothing has measured what it does to throughput or to the
    wall clock. `caps.rate_limit_signal` is False for `dsh`, so §12.3's
    ladder cannot see it either — it arrives as `kind: "error"` events.

---

## 9. The pilot

See `reports/autolab/docs/PILOT.md` — what it proved, with evidence, and what it
did not. Evidence files: `reports/autolab/pilot_evidence/`
(`task.json`, `box.json`, `events_comments_index.ndjson`,
`box_setup_verify.txt`, `credits.log`, `teardown_verified.txt`,
`dryrun_161.txt`).

In one line: **the agent ran on the VM, the key never touched a disk, and the
pilot cost $0.0027** — and it found two things that unit tests could not
(§8 items 10 and 11).

---

## 10. Teardown, verified

`reports/autolab/pilot_evidence/teardown_verified.txt`, 2026-09-28 20:51 UTC:

```
$ sky status --refresh
Clusters
No existing clusters.

$ gcloud compute instances list --filter="name~'^sweep-'"
(no rows)
```

Seven GCP VMs are RUNNING and **none is ours**: `jim-blockaid`,
`policy-extraction-arm-jamie`, `scalog-machine`,
`instance-20260531-tack-client`, `instance-20260531-tack-switch`, and the two
ray heads `cpu-64-…-head-…` and `h100-2-…-head-…`. They were not touched.

---

## 11. Test suite

Run `cd /home/dev/project/src_new && venvs/queries_from_runs/bin/python -m pytest -q`
(about 12 minutes).

**`2949 passed, 15 skipped, 1 failed`** on an otherwise idle machine, and
that failure is not this change's. (A run competing with other work also
flaked `test_agents_codex.py` — see the third bullet.)

* **+21 passed** are this change's new tests
  (`sweep/tests/test_workers_remote_agent.py`), plus 3 new/rewritten in
  `reports/autolab/tools/test_run_real_sweep.py`, which the `src_new` suite
  does not collect — run those with
  `PYTHONPATH=/home/dev/project/src_new venvs/queries_from_runs/bin/python3 -m pytest reports/autolab/tools/test_run_real_sweep.py -q`
  (**8 passed**). `sweep/tests` alone: **987 passed, 11 skipped**, twice in a
  row in random order. `tests/test_self_contained.py`: **9 passed, 6 subtests
  passed.**
* **`dumps_to_policy/tests/test_boundaries.py::test_the_module_actually_imports`
  — PRE-EXISTING, and proved so.** It asserts `"sqlglot" not in sys.modules`
  after importing `dumps_to_policy`, and `domains/` tests import sqlglot
  earlier in the same process. Reproduced at HEAD (`d2d3334`) in a clean
  `git worktree` with none of this change present:
  `pytest domains dumps_to_policy/tests/test_boundaries.py` fails there too.
  Nothing in this change imports sqlglot or alters import order. The quoted
  baseline of "2928 passed, 0 failed" predates it.
* **`sweep/tests/test_agents_codex.py::test_total_is_used_and_last_is_never_accumulated`
  — a load-induced timing flake in a file this change does not touch**
  (`git diff sweep/agents/codex.py` is empty). It drives a real fake
  app-server subprocess and pumps its events. It failed once, in a
  full-suite run competing with other work, and then passed: 3/3 alone,
  twice in a row over its whole directory, and in the clean full run above.
  Recorded rather than quietly rerun until green — a timing-sensitive test
  that can fail under load is worth knowing about before you run something
  for three hours.
