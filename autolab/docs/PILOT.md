# The pilot — 2026-09-28

What was run, what it proved, what it did not, and what it cost.

Evidence files are in `reports/autolab/pilot_evidence/`; the coordinator's own
log is `reports/autolab/entrypoints/sweep_out_or_pilot/pilot.log`.

---

## What was run

```bash
export PATH=/home/dev/tools/google-cloud-sdk/bin:$PATH
cd /home/dev/project && venvs/sky/bin/python3 reports/autolab/tools/run_real_sweep.py \
  --spec reports/autolab/entrypoints/sweep_openrouter_pilot.json \
  --out  /home/dev/project/reports/autolab/entrypoints/sweep_out_or_pilot \
  --corpus-root /home/dev/project/reports/autolab/e2e/runs \
  --execution skypilot --region us-central1 --instance-type n2-standard-2 \
  --repo /home/dev/project/ruby_examples/dse-apps/apps/diaspora \
  --domain ruby_rails_sql --app-revision diaspora-concolic \
  --no-refresh --max-steps 400 --interval-s 5
```

The 4-endpoint spec. It got through the **first** endpoint
(`comments_index`) and was stopped there deliberately — see "why it was
stopped".

### Attempt 1 failed before any VM existed, and that is itself a result

With no `--instance-type`, SkyPilot's GCP optimizer chose `n4-standard-2` and
**n4 had no capacity in any us-central1 zone**: a, b, c and f each answered
`ResourcesUnavailableError`. No instance was ever created and nothing was
billed. Log: `pilot_attempt1_n4_no_capacity.log`.

This is exactly the hazard §8.4 describes from the other direction (n4 is in
the default family set and only supports `hyperdisk-balanced`), and it is why
`--instance-type` now exists and defaults to `n2-standard-2`.

---

## What it proved

### 1. The box builds, including the parts that are new

`pilot_evidence/box_setup_verify.txt`, from `sky logs <cluster> 1`:

```
[box] setup starting
[box] python 3.12
[box] unpacking bundle
[box] pip
[box] node + npm packages
[box] verify
[box] python ok
openjdk version "21.0.5" 2024-10-15 LTS
jruby 9.3.0.0 (2.6.8) 2021-09-17 85c20e780f OpenJDK 64-Bit Server VM 21.0.5+11-LTS …
v22.23.3
0.1.7-rc.2
[box] setup complete
```

The last three lines are the new part: **node 22.23.3** from nodesource and
**`dsh` 0.1.7-rc.2** from `npm install -g`, both verified inside `setup`
rather than discovered later. Provision to `setup complete` was about
**5 minutes** on a cold `n2-standard-2` (launch submitted 20:38:49, setup
complete 20:44:34, of which ~100 s was provisioning).

### 2. The agent ran ON THE VM

`pilot_evidence/events_comments_index.ndjson` is agentd's event log, written
on the VM and rsynced down by the channel. Frame 1:

```json
{"agent_backend": "dsh", "kind": "batch", "endpoint": "comments_index",
 "execution_backend": "skypilot", "max_wall_s": 21600.0,
 "model": "deepseek/deepseek-chat", "interjection_rung": 3,
 "capabilities": {"live_input": true, "reply_correlation": "echo",
                  "interrupt": false, "resume": "none",
                  "usage_in_stream": true, "cost_in_stream": false,
                  "budget_cap": false, "rate_limit_signal": false,
                  "enqueue_only": true},
 "worker_id": "worker/batch/comments_index/0#1"}
```

**agentd could only have announced `dsh`'s capability set by having
constructed a `dsh` adapter** — that block is `adapter.caps.as_json()`, read
off the object. Before this change the `hello` frame carried `caps: {}` for
every worker, because agentd had no adapter to ask.

Frame 3, the adapter's `started` event, carries a real harness handshake:

```json
{"kind": "started", "payload": {"profile": "sdk", "resumed": false,
 "server_info": {"name": "deepseek-harness-sdk-runtime", "version": "0.0.1"},
 "session_id": "6affdaca-936d-48e0-98b3-af29a2bb5182"}}
```

Frame 17 is the model route resolving through the bundled profile:

```json
{"native_kind": "route", "payload": {"provider": "openrouter",
 "model": "deepseek/deepseek-chat", "context_window": 163840}}
```

### 3. It was NOT the dev box

* **The `sample` frames are the VM's cgroup**: `disk_total_mb: 19662` — the
  20 GB boot disk of the `n2-standard-2`. The dev box has 86 GB free on one
  shared filesystem and would never report that.
* **No model process ran here.** `run_batch` took the non-co-located branch,
  so the coordinator's own `DeepSeekBackend` object was never started — it was
  only asked for `remote_spec()`. The unit differential
  (`test_the_remote_run_accounts_for_exactly_what_the_host_run_does`) asserts
  the same property mechanically by checking the coordinator's adapter has no
  session after a remote run.
* The event log did not exist on this machine until `SkyChannel` rsynced it
  down.

### 4. The key reached the VM and is on no disk of ours

The task document the coordinator wrote and rsynced up
(`pilot_evidence/task.json`) — **zero** occurrences of the key:

```
$ grep -c "$(cat openrouter_api_key.txt)" task.json box.json
task.json:0
box.json:0
```

What it carries instead:

```json
"argv": [],
"agent": {"backend": "dsh", "model": "deepseek/deepseek-chat",
          "env_passthrough": ["OPENROUTER_API_KEY"],
          "ctor": {"executable": ["dsh", "--profile", "sdk"],
                   "base_env": {"PATH": "/usr/local/bin:/usr/bin:/bin",
                                "HOME": "/home/dev",
                                "DSH_HOME": "/home/dev/project/reports/autolab/box/dshhome"}}}
```

`argv` is empty — agentd had no command and had to build the agent. The
credential is a **name**. And the box record
(`pilot_evidence/box.json`), which is written to the coordinator's disk *and*
synced up with `ctl/`, carries:

```json
"secret_envs": ["OPENROUTER_API_KEY"],
"envs": {"PATH": "…", "PYTHONPATH": "/home/dev/project/src_new:/work",
         "SWEEP_WORK": "/work"},
"instance_type": "n2-standard-2"
```

— names in `secret_envs`, and no key in `envs`. The value was resolved from
the coordinator's process environment inside `RealSky.to_task()` at launch and
put into SkyPilot's task `envs`; `dsh` read it on the box because the bundled
profile says `apiKeyEnv: OPENROUTER_API_KEY`. That it worked is proved by the
`route` frame above and by a real billed completion.

### 5. The brief was written for the box's root, not the mirror's

`task.json`'s `agent.brief.system_append` contains `/work/out/packet`, not
`…/sweep_out_or_pilot/boxes/<id>/out/packet`. Getting this wrong is silent —
the agent runs, writes somewhere, and submits nothing.

---

## What it cost

`pilot_evidence/credits.log`, from OpenRouter's own `/credits` endpoint:

| when | `total_usage` | remaining |
|---|---|---|
| before any pilot model call | 81.257774913 | **$8.742225087** |
| after the batch agent's turn 1 on the VM | 81.260445444 | **$8.739554556** |

**Billed: $0.002670531** for one turn of 9 260 input + 279 output tokens.

Against the table:

| | input | output | total |
|---|---|---|---|
| **billed** (OpenRouter) | | | **$0.00267053** |
| list price (0.2574 / 1.0287 per Mtok) | $0.0023835 | $0.0002870 | $0.0026705 |
| **the spec's table** (×1.2396) | $0.0029546 | $0.0003558 | $0.0033104 |

**The list price was exact to five decimal places for this request, and the
raised table overstates it by 24 %.** That is the opposite direction from the
earlier measurement that motivated raising it ($0.00472779 billed vs
$0.00381386 at list). Both are real. The honest conclusion is that **the
effective rate is not a constant**: OpenRouter routes each request to a
third-party provider and the request carries nothing that says which one, so
any client-side table is an estimate with per-request variance of at least
±24 %.

The table has been left at ×1.2396 — overstating is the safe direction for a
ceiling, and §11.2.1's `margin: 0.15` sits on top of it — but see
`entrypoints/PRICES.md`, and treat `/credits` as the only truth.

**GCP cost** is a separate account: one `n2-standard-2` (about $0.10/hr) for
roughly 12 minutes, so on the order of **$0.02**. No VM was created by
attempt 1.

---

## Why it was stopped after one endpoint — and the finding that caused it

The batch agent completed turn 1 and the session went **idle**:

```
seq 38  session.event/step/end   {"step": 1, "turn": 1}
seq 39  turn_end                 {"num_turns": 1, "stop_reason": "completed"}
seq 40  session.status/idle      {"status": "idle", "was": "running"}
```

and then nothing but `sample` frames.

**`dsh` does not exit when its turn ends.** §7.5 puts it at rung 3
(enqueue-only, `resume: "none"`, no interrupt), and an idle session means
"ready for another prompt", not "finished". Nothing sends another prompt: the
coordinator issues one brief and does not interject. So:

> **A `dsh` batch worker that finishes its turn without submitting sits idle
> until agentd's wall clock — `max_wall_s`, which is 21 600 s (6 hours) for an
> `sm` box — and the VM bills for all of it.**

This is not something the §8.4 change introduced; it is how `dsh` and agentd
compose, and on the `host` backend it costs an idle process rather than a
machine. On the cloud it is a six-hour bill for nothing. The pilot was stopped
rather than left to demonstrate it at full price.

The model also did not do the task — it replied conversationally about the
worker protocol rather than exploring the endpoint
(`"It seems you've provided detailed instructions about a worker protocol…"`).
`deepseek/deepseek-chat` through OpenRouter is a weak agent for this brief.
That is a *content* result and says nothing about the plumbing.

---

## What it did NOT prove

1. **No packet was produced**, so the artifact round trip
   (`fetch` → `packet.submitted` → digest verified → `BatchResult.submitted`)
   was exercised only in the unit tests against `FakeVMBackend`, not against a
   real VM. `drive_agent_remote`'s `fetch_detail` call ran and correctly
   reported the packet missing.
2. **Endpoints 2-4 of the pilot spec never ran.** Only `comments_index`.
3. **The CHECKING state was never reached**, so the refusal that `run_check`
   now raises on a non-co-located backend was not exercised live.
4. **Teardown on SIGTERM did NOT work, and that is a finding rather than a
   gap.** `shutdown()` ran, printed `TEARDOWN (signal 15)` and
   `reap: []` — and `sky status` a moment later still showed the cluster
   `UP`. It was downed by hand with `sky down`. See `LAUNCH_SWEEP.md` §8
   item 10: `SkyPilotBackend.reap()` skips any listed cluster it cannot name
   a reason for, and "recorded RUNNING, cluster UP" is not one of its
   reasons. The runner now tears down its own boxes by recorded identity
   before reaping, with a control test showing reap alone leaving the
   cluster up; the underlying `reap()` is unchanged and still blind.
   **This is the most valuable thing the pilot found**, and it would not have
   shown up in any unit test, because the unit tests all take the normal exit
   path where `run_batch` calls `teardown()` itself.
5. **Nothing about `complete: true`.** As expected — no config carries a
   `completion` block, so every endpoint would report `complete: false`. This
   is not disguised and was never in question.
6. **Upstream rate limiting was hit and recovered from, once.**
   `deepseek/deepseek-chat` returned five consecutive `429 … temporarily
   rate-limited upstream` before the first successful call; `dsh` retried with
   exponential backoff (0.5 s → 8.3 s) and succeeded on retry 5. A sweep of
   161 endpoints with 3 concurrent agents will meet this constantly, and
   nothing has measured what it does to throughput.

---

## Consequences for the 161-endpoint run

Recorded in `LAUNCH_SWEEP.md`, but the two that came out of the pilot:

* **Lower `max_wall_s` before launching.** It is the only thing that bounds a
  `dsh` worker in flight, and at 6-12 hours it is not a bound at all. The idle
  session above would have held a VM for six hours.
* **Pin `--instance-type` per box class.** `sm=n2-standard-2,md=n2-standard-4`.
  Without it the optimizer picks n4 and every launch fails four zones deep.
