---

<!-- TWO OF THIS FILE'S CORRECTIONS ARE NOW IN THE BRIEF ITSELF (2026-09-29).
     `src_new/sweep/briefs/batch.md` now states (a) that the check box mounts
     the packet at `in/packet`, so `assumption_manifest.batch_dir` is
     `in/packet/dumps`, and (b) that the marker is written LAST and exactly
     once, because the coordinator ends the worker the moment it verifies —
     which is what the "THE MARKER ENDS YOUR BOX" section below was for, and
     what the brief's own "submit as soon as you have something defensible"
     contradicted. `sweep/tests/test_briefs_batch.py` asserts both.

     The sections below are therefore DUPLICATES of the brief on those two
     points. They are kept because the rest of this file is genuinely the
     caller's — the explorer's invocation, the measured failure mode, the
     clock — and because an addendum every campaign must remember to attach is
     not where a general instruction belongs. If you re-attach this file,
     nothing breaks; the agent reads the same rule twice. -->

## OPERATOR ADDENDUM (this campaign)

The brief above is app-agnostic and says nothing about how this application is
explored. This section is the caller's, added because a previous wave of boxes
measured exactly where agents lose their time. Read it once, then work.

### What was measured, so you do not repeat it

On 2026-09-29 three boxes on this same brief each ran ONE turn of 279-310 tool
calls and submitted nothing. Nearly every call was `ls -la /work` or
`cat in/config.json` again. They re-listed directories they had already listed
around two hundred times, never invoked the explorer, and never wrote a single
byte to `out/`. **Re-reading is the failure mode here, not under-reading.**

So: read `in/config.json` ONCE. Write what you learn to `batch/NOTES.md`
(`batch/` is read-write) and consult that file instead of re-listing. If you
catch yourself running a command you have already run, stop and go to step 3.

### THE MARKER ENDS YOUR BOX — write it LAST, exactly once

The brief says "submit as soon as you have something defensible". Take that as
advice about PACE, not about ordering. On this campaign the coordinator ends
the worker and tears the box down the moment `out/packet.submitted` verifies,
so the marker is not a checkpoint — it is the last thing that happens. Build
`out/packet/` completely, verify it yourself, and only then write the marker.
A second submission under the same name is ignored, so there is no second try.

### The explorer, concretely

`in/config.json` names `runtime.runner` — a `run_dse.rb`. It is the explorer
that produces dumps, and this is how it is invoked on this box:

    export JAVA_HOME=/home/dev/tools/jdk-21.0.5
    export PATH=$JAVA_HOME/bin:/home/dev/tools/jruby-9.3.0.0/bin:$PATH
    export GEM_HOME=/home/dev/.gem/jruby/2.6.0
    export RAILS_ENV=concolic
    mkdir -p <box-root>/out/packet/dumps
    cd /home/dev/project/ruby_examples/dse-apps/apps/diaspora
    MAX_RUNS=24 TIME_BUDGET=300 DUMP_OUT=<box-root>/out/packet/dumps \
      bundle exec jruby -I. <the runtime.runner path from your config> 2>&1 | tail -40

`DUMP_OUT` matters: without it the runner writes beside its own source file,
which is in a read-only part of the bundle. `MAX_RUNS` and `TIME_BUDGET` are
the config's `scenarios` values. The whole exploration takes SECONDS to a few
minutes for this class of endpoint, not tens of minutes. If it fails, read the
error, fix the invocation, and try twice more; if it still fails, say so in
`packet.json` and submit the corpus in `batch/` as your `dumps/` instead,
labelled honestly as inherited rather than produced.

### Waiting for the explorer: use the helper, never a command-line pattern

The explorer is the one thing here you will background, so it is the one thing
you will wait for. The worker protocol's section "Run anything longer than a
minute as a background task" carries the rule and the tool; this is what it
costs on this machine when it is skipped.

`pgrep -f` and `pkill -f` match a pattern against whole command lines,
**including the command line of the shell running your wait loop**:

```bash
until ! pgrep -f "shim_test_runner.rb.*batch-2"; do sleep 3; done
```

The loop above does not wait for the explorer. It waits for its own shell, so
it does not end: measured on this lab, that costs between six and a half
minutes and twenty-five minutes of wall clock per occurrence, all of it spent
after the job had already finished. Knowing about the hazard is not protection
from it — the rule is the tool below, not the warning.

`pkill -f` has the matching problem and a worse consequence: a pattern can
match another run's explorer as readily as yours, and two runs sharing a batch
directory costs the whole corpus.

So, in order of preference:

```bash
PY=/home/dev/project/venvs/queries_from_runs/bin/python3
W="$PY -m sweep.box.wait_for"

$W --pid "$EXPLORER_PID" --timeout 1800            # you launched it
$W --file "$DUMPS/../logs/run.done" --timeout 900  # a sentinel the job writes
$W --exe /home/dev/tools/jruby-9.3.0.0/bin/jruby --contains run_dse.rb \
   --timeout 1800
$W --name jruby --list      # what matches right now, without waiting
```

It matches on `/proc/<pid>/exe` or an exact `/proc/<pid>/comm`, never on a
command-line substring, and it excludes itself, every ancestor and its process
group before it matches anything — so the loop above, written through it,
cannot wait on the shell that launched it. Exit 0 is "nothing (left)
matching"; exit 2 is "the timeout elapsed", which is a result to report.

**Single provenance is a hard rule on this campaign**, so never signal by
pattern either. Resolve a pid with `--list`, satisfy yourself it belongs to
the run you mean, and signal that pid. Another agent may be running on this
machine: expect CPU contention and do not read slowness as a hang. If you ever
suspect two runs overlapped, discard the corpus and re-run from clean rather
than reasoning about which dumps came from where.

### Suggested order, with a clock

You have a wall clock. Spend it roughly like this:

1. **0-5 min.** Read `in/config.json` once, and the brief. Write
   `batch/NOTES.md`: the endpoint, `runtime.runner`, `runtime.targets`,
   `runtime.shims`, the `scenarios` numbers, and the config digest from
   `sha256sum in/config.json`.
2. **5-20 min.** Run the explorer. Get dumps into `out/packet/dumps/`.
3. **20-40 min.** Write `assumptions.json` and `assumption_manifest.json`.
   The manifest's `batch_dir` and `runner` must be valid WHERE THE CHECK RUNS,
   which is a box like this one with the same bundle at the same absolute
   paths — so absolute paths into `/home/dev/project/...` are correct there,
   and a path into your own `/work` is not.
4. **40-50 min.** `shim_tests.rb`. The shim key set comes from the target
   declarations this endpoint installs: `runtime.targets` names the registry
   and `runtime.shims` the shared shim file. If you cannot enumerate the keys
   honestly, or cannot write bodies that really run, **omit the
   `shim_tests` key and say why in `packet.json`**. The brief means that
   literally: an omission is a recorded NOT CONFIGURED gate, a fabrication is
   a lie standing where a check was meant to be. Omitting is the better
   outcome and it does NOT invalidate your packet.
5. **50-55 min.** Write `packet.json`, re-read every file it names to confirm
   it is really there, then write `out/packet.submitted` with the digest the
   worker protocol describes. Then stop.

### A packet is still a packet with gaps

Do not withhold a submission because it is not complete. `dumps/` +
`assumptions.json` + `assumption_manifest.json` + an honest note about what
you could not do is a real submission and is worth far more than a box that
hits its wall clock with an empty `out/`. The one thing that is never
acceptable is inventing content for an artefact you did not derive.
