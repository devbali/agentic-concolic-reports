# Autolab cloud sweep — result, 2026-09-29

**Outcome: the cloud path was repaired and proven, and it produced no packets.**
Three defects were found; two are fixed and demonstrated on real VMs, the third is
not a plumbing bug and is stated rather than worked around. Ten endpoints ran, all
ten read the corpus, none submitted. Nothing is running.

---

## What was asked, and what happened

| wave | scope | result |
|---|---|---|
| W2 (`sweep_out_w2`) | 161 endpoints, width 51 | stopped after ~50 min — corpus never staged |
| W3 (`sweep_out_w3`) | 10-endpoint sample, one-box gate first | gate passed on the second attempt; ten ran; 0 packets; stopped by the spend ceiling |

## Verdict per endpoint — 0 packets of 10

| endpoint | box | outcome | corpus read? |
|---|---|---|---|
| `posts_destroy` | sm | `stopped` at 1800 s wall clock, no packet | yes — 6 dumps opened, 279 tool calls |
| `profiles_show` | sm | `stopped` at 1800 s wall clock, no packet | yes — 7 dumps opened, 310 tool calls |
| `two_factor_authentications_recovery_codes` | sm | `stopped` at 1800 s wall clock, no packet | yes — 13 dumps opened, 287 tool calls |
| `blocks_create` | md | torn down mid-run by the ceiling stop | yes |
| `devise_passwords_create` | md | torn down mid-run by the ceiling stop | yes — 26 dump commands at 09:06 |
| `people_retrieve_remote` | md | torn down mid-run by the ceiling stop | yes |
| `services_create` | md | torn down mid-run by the ceiling stop | yes |
| `sessions_create` | md | torn down mid-run by the ceiling stop | yes — 36 dump commands at 09:06 |
| `streams_liked` | md | torn down mid-run by the ceiling stop | yes |
| `tag_followings_destroy` | md | torn down mid-run by the ceiling stop | yes |

**Read the seven `md` rows carefully.** They are recorded `failed` with
`tool_calls: 0` only because **teardown deletes the local box mirror**, and the
event stream goes with it. They were not idle: a monitor sampling every five
minutes recorded **10 of 10 boxes having opened a dump by 09:06**, with per-box
dump-command counts of 36, 26, 13, 11, 6, 5, 5, 5, 5, 3, each box at 245-310 tool
calls. The zeros in the table are an artefact of the teardown, not a measurement.

The three `sm` boxes are the only ones that reached their own wall clock, and all
three did the same thing: read the corpus for thirty minutes, 65-80 million
cache-read tokens each, and submitted nothing.

## Defect 3 — the agent reads the corpus and still does not submit. NOT FIXED.

This is what is left once the plumbing works, and it is not a plumbing bug.

`docs/LAUNCH_SWEEP.md` §8 item 12 already flagged it and could not settle it:
"nothing has yet shown this model producing a packet on this brief, and a
161-endpoint sweep is a large bet on it doing so." Tonight moved that forward by
exactly one step. The model demonstrably **reads the corpus** now, on ten
endpoints out of ten, which was never true before. It still produces no packet.

Two explanations remain and they look identical from here: the task does not fit a
30-minute box, or the agent does not converge on the submission protocol. Nothing
measured tonight separates them. What *is* now excluded is the whole class of
"the agent never found the corpus", which is what the first two defects were.

**Do not run the 161 until this is settled on one endpoint.** At the measured rate
a full sweep is ~$105 and, on tonight's evidence, would return nothing.

## Defect 1 — the corpus never reached the box. FIXED.

`reports/autolab/tools/queue_context.py` created `batch_dir` and never filled it.
`corpus_root` was read into a local and never used again; `plan_batch` has no
corpus parameter at all. So every box was told by its brief that
"`batch/` ... is where the corpus of `dump_*.json` lives" and arrived to an empty
directory. 51 boxes spent their whole wall clock re-listing directories.

The config compounded it: `corpus_root` pointed at
`reports/autolab/entrypoints/scaffold`, which holds no `dump_*.json` at all. The
real corpus is 840 dumps under `reports/autolab/e2e/runs`, all 161 endpoints
covered.

**Fix**, all in the write-freely zone, no `src_new` change:

* `corpus_for()`, `stage_corpus()`, `check_every_endpoint_has_a_corpus()` in
  `queue_context.py`; `plan_for` now stages before the plan is built.
* Dumps are **copied**, not symlinked — a symlink into a tree the box does not
  have is a dangling link on the far side.
* `corpus_root` repointed to `reports/autolab/e2e/runs` in `queue.json`,
  `queue_w2.json`, `queue_w3.json` and in the module docstring's sample.
* **The guard**, which is worth more than the staging: pointed at the old tree it
  refuses the whole run *before provisioning anything* —
  `corpus_root .../scaffold: no dump_*.json for 147 of 161 endpoint(s)`.
  `run_real_sweep.py` had this refusal; the queue path did not, which is why a
  missing corpus ran at width 51 instead of failing at endpoint one.

**Proven on the box**, by ssh into the live cluster:

    /work/batch -> /home/gcpuser/.sky/file_mounts/work/batch
    dump_auth_json_dse0001.json ... count: 14

## Defect 2 — the config points the agent at an empty directory. FIXED.

Found by reading the proof agent's own words:

> "The config references paths under `/home/dev/project/reports/autolab/...`
>  but the actual paths are relative."

`in/config.json` carries absolute dev-box paths:

    "paths": {
      "root":      ".../entrypoints/scaffold/posts_destroy",
      "batch_dir": ".../entrypoints/scaffold/posts_destroy",
      "out":       ".../entrypoints/scaffold/posts_destroy/out"
    }

The box bundle reproduces `/home/dev/project/reports/autolab/entrypoints` **at its
absolute path**, so on the VM that directory really exists — holding `config.json`,
`launch.sh`, `run_dse.rb` and **no dumps**. Confirmed by ssh on the live box:

    ls .../scaffold/posts_destroy/dump_*.json  -> No such file or directory
    ls /work/batch/*.json | wc -l              -> 14

So the brief says the corpus is in `batch/`, the config says `batch_dir` is the
scaffold path, and **both are real directories on the box** — one full, one empty.
The agent believed the config. Over 186 tool calls it listed `batch/` twenty times,
opened **zero** dumps, wrote nothing to `out/`, and looped on "Let me explore the
environment more thoroughly."

**Fix.** `config["paths"]` is written by `scaffold.py` and **read by nothing** —
no Python or Ruby consumer exists anywhere in `reports/`, `src_new/` or `scripts/`;
`run_dse.rb` derives its own output directory from `File.dirname(__FILE__)`. So the
block was never load-bearing and its only reader was the agent, which it
misinformed. It is now box-relative — `root: "."`, `batch_dir: "batch"`,
`out: "out"` — matching the brief's own table. Applied in `scaffold.py` so
regeneration cannot reintroduce it, and to all 161 live configs. Verified: 0 of 161
carry an absolute path in `paths`.

`/work` was deliberately NOT hardcoded: the brief says "do not assume `/work`",
and on the host path the box root is the mirror directory. Relative values are the
only ones true on both. `runtime.targets`, `runtime.shims` and `runtime.runner`
were left absolute on purpose — the bundle reproduces those trees at their absolute
paths, so they resolve to the right files on the box. The distinction that matters
is not absolute-vs-relative, it is whether the thing at the path is the right thing.

**The guard that catches both classes.** `check_config_points_at_the_corpus()`
refuses any absolute path in the block, and any `batch_dir` that does not resolve
inside the `batch` mount. It runs for every endpoint in `make()` before anything can
provision, and again per entry. Demonstrated on three inputs: passes on the fixed
config, refuses the old absolute path, and refuses a plausible-but-wrong
`batch_dir: "dumps"`. That last case is the point — it catches a config aimed at the
wrong place **even when the dumps are present**, which the corpus guard cannot see.

**Proof it worked**, same endpoint, same model, same brief, same box class:

    before:  186 tool calls, 20 listings of batch/, 0 dumps opened, out/ empty
    after:   `head -c 2000 batch/dump_auth_json_dse0001.json` — the bytes, not the listing

## Was the staged corpus visibly used?

**Yes — this is the one question that changed answer tonight.** Before the fixes:
present but never opened. After: every one of the ten boxes opened at least one
dump, with per-box dump-command counts of 36, 26, 13, 11, 6, 5, 5, 5, 5, 3.

The gate was applied literally. My first counter would have passed on the substring
"dump" appearing inside an echoed shell banner; I read the full command instead and
required the bytes. The passing command was
`head -c 2000 batch/dump_auth_json_dse0001.json`.

## Money

`/credits` is the only signal used; the derived cost column overstates by 2-3x.

| point | `total_usage` |
|---|---|
| session baseline | 83.014684612 |
| after W2 stop | 98.851 |
| W3 budget baseline | 110.964684 |
| ceiling stop fired | 131.157750598 |
| **final, settled** | **132.342545032** |

* W2: **$15.84** — 51 boxes, ~50 min, five completed endpoints, no packets.
* W3: **$21.38** — eleven boxes over two proof attempts and the ten-endpoint run.
* **Session total: $49.33.**

**The ceiling is not a hard stop, and the lag is measurable.** The supervisor polls
`/credits` every pass and fired at `131.158`, 0.2 above the 130.96 threshold — but
credits settled at `132.343`, **$1.38 past the ceiling**, because requests already
in flight on seven boxes bill after the stop decision. Budget a margin of roughly
$0.20 per running box for this. It is not drift in the signal; it is work already
sent.

**Measured burn rate, the most reusable number here.** Steady state at 51 boxes,
07:31:49-07:41:58: $7.232 in 609 s = **$42.8/hr = $0.84 per box-hour**. At width 10
it started near $0.53 per box-hour and **rose to about $3 per box-hour** as contexts
grew — cache-read tokens dominate and they compound with session length. So
per-box-hour is not a constant and a projection from the first ten minutes of a run
will understate it. A completed `sm` box (0.54 h) cost $2.4-2.9 derived against
roughly $1.5-2 real.

## Also fixed on the way: cluster-name collision

`cluster_name_for` in `src_new/sweep/execution/skypilot.py` truncated to 60 chars
with a bare `[:60]`. Enumerated over all 161 endpoints: two colliding families,
five endpoints —
`api_openid_connect_authorizations_{create,destroy,new}` and
`two_factor_authentications_confirm_{2fa,and_activate_2fa}`.
Across box classes this is a loud `ResourcesMismatchError` and two lost endpoints;
**within** one class it silently reuses another endpoint's cluster and the corpus is
attributed to the wrong endpoint. `create[sm]`/`destroy[sm]` are such a pair.

Fixed by ending an over-long name with an 8-hex sha256 of the full name. Re-enumerated:
**161 of 161 distinct**, all <= 60 chars, all matching SkyPilot's own regex. Three
regression tests in `sweep/tests/test_execution_skypilot.py` (the collision, name
stability, and a negative control that short names are untouched). 97 passed, 11
skipped across the three related test files.

**No cluster was silently reused in either wave** — all three members of the only
same-class family are recorded `failed`, so no agent ran on a shared box.

## The asymmetry that hid all of this

The 840-dump end-to-end verification passed on all 161 endpoints and could not have
caught defect 1. **On the local path `batch_dir` IS the working directory, so the
corpus never has to travel. The cloud path is the only place it does.** Anything
that has to move from the dev box to the VM — the corpus, and any absolute path in
a config — is untested by a local run however green it is. That belongs in the
runbook.

## Nothing is running

Verified 09:48 UTC, both tools, after the automatic ceiling stop:

    gcloud compute instances list --filter="name~'^sweep-'"   -> (no rows)
    RealSky().status()                                        -> ()
    supervisor processes                                      -> 0
    sweep.queue processes                                     -> 0

The seven pre-existing VMs (`jim-blockaid`, `policy-extraction-arm-jamie`,
`scalog-machine`, two `tack`, two ray heads) are untouched. Every `stop` this
session exited 0 with zero orphans and zero errors.

**Note:** teardown deletes the local box mirror, so `boxes/<id>/ctl/events.ndjson`
— the only per-box diagnostic record — is erased with it. Both diagnoses in this
document exist only because the event stream was read *before* stopping. Read it
before you tear a box down, or the evidence goes with the box.

## What a next attempt needs, in order

1. **Settle defect 3 on ONE endpoint before spending anything at width.** The
   plumbing is proven; the open question is whether this agent ever submits. A
   single box, watched, is the whole experiment. Candidates to vary: a longer
   `max_wall_s`, a smaller brief, or a different model — `agents.batch.model` in
   the spec is one line.
2. Only if an endpoint submits, run the ten again.
3. Only if the ten submit, consider the 161 (~$105 at the measured rate).

The queue is intact. W3's entries are re-enqueueable with
`sweep_out_w3/enqueue_nine.py`; W2 still holds 107 untouched queued entries that one
`advance` would resume.

## Reusable findings

* **The local-vs-cloud asymmetry** (see above) — anything that must travel from the
  dev box to the VM is untested by a local run however green it is. Both of tonight's
  fixed defects were in that gap.
* **Ramping launches works.** 2 -> 6 -> 12 -> 19 -> ... -> 51 produced **zero**
  `ReadTimeout`s against the local SkyPilot API server. The previous single 51-wide
  burst produced 41. `advance --max-launch N` is the lever.
* **`ReadTimeout` is classified correctly.** It carries `last_error_kind: transient`
  and is deferred, not retired — `is_transient` matches the substring "timed out".
  A wave of entries reading "torn down: stop message" were retired by an operator
  `stop`, not by the classifier.
* **The spend ceiling has ~$0.20/running-box of settling lag.** Budget for it.
* **Per-box-hour cost is not constant** — it roughly quadruples over a run as
  cache-read tokens accumulate. Do not project from the first ten minutes.
