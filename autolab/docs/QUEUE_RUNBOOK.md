# Driving the sweep with the durable queue

The coordinator's long-running driver loop is gone as the thing that carries a
run. Work is now entries in a directory, and three short-lived programs move
them. Nothing runs between invocations, so nothing can crash and lose the run —
the boxes really are up in GCP between ticks, and the queue reconciles against
them rather than remembering them.

## One-time setup

Write the context file once per run. It is the same information
`run_real_sweep.py` takes as flags, so the two cannot drift.

```bash
cat > /home/dev/project/reports/autolab/entrypoints/queue.json <<'JSON'
{
  "spec":          "/home/dev/project/reports/autolab/entrypoints/sweep_openrouter.json",
  "out":           "/home/dev/project/reports/autolab/entrypoints/sweep_out_or",
  "repo":          "/home/dev/project/ruby_examples/dse-apps/apps/diaspora",
  "corpus_root":   "/home/dev/project/reports/autolab/entrypoints/scaffold",
  "execution":     "skypilot",
  "region":        "us-central1",
  "instance_type": "n2-standard-2",
  "manifest":      "/home/dev/project/reports/autolab/box/manifest.json",
  "provider":      "openrouter",
  "key_file":      "/home/dev/project/openrouter_api_key.txt",
  "max_launch":    0
}
JSON

# THE INTERPRETER IS NOT A FREE CHOICE. `advance` provisions, and
# `venvs/sky/bin/python3` is the only interpreter on this machine that can
# `import sky` (LAUNCH_SWEEP.md §1). Anything else dies with
# `SkyPilotUnavailable: No module named 'sky'`, reported as a `ClusterLeaked`
# whose scary wording is a red herring — the failure is before `launch()`, so
# nothing was ever billed. Measured 2026-09-29.
export PY=/home/dev/project/venvs/sky/bin/python3

export SWEEP_QUEUE_CONFIG=/home/dev/project/reports/autolab/entrypoints/queue.json
export PYTHONPATH=/home/dev/project:/home/dev/project/src_new
export Q=/home/dev/project/reports/autolab/entrypoints/sweep_out_or/queue
export CTX=reports.autolab.tools.queue_context:make
```

`max_launch: 0` means "whatever admission allows". Set it to a small number
for the first run — the cost of a mistake is one box, not fifty.

## The three verbs

```bash
# enqueue one endpoint's batch attempt
$PY -m sweep.queue put --out "$Q" --endpoint likes_index --sweep autolab-diaspora-or

# move everything that can move: launch, poll, collect, tear down
$PY -m sweep.queue advance --out "$Q" --context "$CTX"

# read what has finished (no side effects, safe at any time)
$PY -m sweep.queue get --out "$Q"
```

`advance` is the only verb that touches the cloud. Run it as often as you
like — every invocation is a bounded pass and re-running one after a partial
failure neither double-launches nor loses a box. A poll loop is just

```bash
while :; do $PY -m sweep.queue advance --out "$Q" --context "$CTX"; sleep 60; done
```

— and killing that loop at any instant is safe, which is the point.

## Supervision

```bash
$PY -m sweep.queue status --out "$Q"     # counts, per-entry state, orphans
$PY -m sweep.queue get --out "$Q" --all  # including unfinished entries
tail -f "$Q/log.jsonl"                      # every transition, with its reason
```

`status` prints `orphans` when the backend has a cluster that no open entry
claims — the expensive mistake, reported rather than silently billed.

## Stopping

```bash
$PY -m sweep.queue stop --out "$Q" --context "$CTX" --reason "operator"
```

Safe at any time, including after an `advance` died mid-flight. It enqueues a
`stop` message and advances once, so the stop is a fact on disk before it is
an action. Exit 0 means nothing is left billing; exit 2 means something is,
and the message says which cluster.

`stop` means "nothing is billing", not "this work is abandoned": entries that
had not started stay queued, and the next `advance` starts them. That is what
makes it cheap to reach for. To abandon work, delete its entry files.

## Enqueuing the whole sweep

```bash
python - <<'PY'
import json, subprocess, os
spec = json.load(open(os.environ["SWEEP_QUEUE_CONFIG"]))
eps = json.load(open(spec["spec"]))["endpoints"]
for e in eps:
    subprocess.run([os.environ["PY"], "-m", "sweep.queue", "put",
                    "--out", os.environ["Q"], "--endpoint", e["name"],
                    "--sweep", "autolab-diaspora-or"], check=True)
PY
```

Admission still decides what actually starts: `sched.tick()`, the pools and
§9.3 are unchanged, and `parallel_batch_agents` / `cloud.max_concurrent_vms`
are what bound concurrency. Putting 161 entries does not launch 161 boxes.

## Messages

Anything sent to the sweep is an entry too, with a kind and a payload:

```bash
$PY -m sweep.queue put --out "$Q" --endpoint "" --kind config \
    --payload '{"racers": {"posts_show": 3}}'
$PY -m sweep.queue put --out "$Q" --endpoint "" --kind message \
    --payload '{"text": "stop exploring the stream endpoints for now"}'
```

Control messages (`stop`, `config`) are drained before anything is launched,
`stop` first. A message whose handler fails is parked with the reason on the
entry — never dropped.

## Exit codes

* **0** — the queue is consistent. Entries may have failed; a failure retires
  one entry, never the run. This is the normal exit.
* **2** — the queue directory is unreadable, `--context` will not import, or a
  `stop` left something billing. The only genuinely unrecoverable conditions.

## Monitoring: never idle while the queue has work

The queue only moves when something runs `advance`. Boxes are up and billing
between invocations, so an agent that goes quiet is not resting — it is a run
that stopped with VMs running and nobody collecting them.

Arm a monitor first, and make its filter cover the failures, not just the
good news. A monitor that greps for completions is silent through a stall, a
stuck launch and a crashloop, and that silence looks exactly like progress.

```bash
# One line per advance, covering every terminal and stuck condition.
while :; do
  $PY -m sweep.queue advance --out "$Q" --context "$CTX" 2>&1 \
    | grep -E --line-buffered 'launched=|completed=|failed=|deferred=|STOPPED|orphan|error'
  $PY -m sweep.queue status --out "$Q" \
    | python -c 'import json,sys; d=json.load(sys.stdin); c=d["counts"]; o=d.get("orphans",{}).get("orphans",[]);
print(f"open={c[\"queued\"]+c[\"provisioned\"]+c[\"running\"]} done={c[\"done\"]} failed={c[\"failed\"]} orphans={len(o)}")'
  sleep 60
done
```

Kill that loop at any instant — it is safe, because every invocation is a
bounded pass that either completed or did not.

**Three things that must never be left sitting.**

| Sighting | Where it shows | What to do |
|---|---|---|
| an orphan | `status`'s `orphans`, `advance`'s `orphans` | a cluster no open entry claims is billing for nothing — `stop`, or tear that cluster down by name |
| a deferred entry | `advance`'s `deferred`, the entry's `failures` | it will retry next invocation; if it keeps deferring, read `last_error` — a transient failure that never clears is a genuine one in disguise |
| a parked message | `get --all`, state `failed`, kind `config`/`message` | the sender believes their instruction arrived. Read it before launching anything else |

Stopping is a deliberate act: enqueue a `stop` and advance. Going quiet is
not stopping — it leaves the boxes up.

## Boxes no longer run their full wall clock

`dsh` never exits when its turn ends, and §8.1's `submitted` frame did not end
a worker, so every box used to bill its whole `max_wall_s` whether the agent
finished in two minutes or idled the rest of the way. The queue now ends a
worker as soon as **agentd has verified every artifact it was asked for**, and
tears the box down in the same pass.

Nothing is lost by stopping there: agentd recomputed the digest, §8.1 already
holds that "a verified artifact stands whatever ended the worker", and
`SubmissionWatch` dedupes markers by name, so an agent that kept working could
not have resubmitted under the same marker anyway. An *invalid* marker does
not end the worker, and neither does a partial submission — both are in
`sweep/tests/test_queue_idle_box.py` as negative controls.

The response records `stopped_by: "submitted"` for such a box, so it is
distinguishable in the report from one that hit a ceiling.

This is a coordinator-side change: it ships without rebuilding the 400 MB box
bundle.
