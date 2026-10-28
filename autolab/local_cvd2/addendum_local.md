---

## OPERATOR ADDENDUM 2 — this box, this endpoint, and what is actually open

The addendum above was written for a cloud box on a different endpoint. Where
the two disagree, THIS one is right about this campaign.

This is the SECOND drive of this endpoint. The first drive's complete record is
at `/home/dev/project/reports/autolab/local_cvd/` and you may read it. It ended
`INCOMPLETE`. What has changed since is in §10, which is the point of this
drive; read §10 before you plan.

### 1. Your box is a directory on this machine, and the paths are absolute

`host` backend: a box is a directory, not a container. Your `in/` and `repo/`
mounts are symlinks, nothing is isolated, and the box root is an absolute path
the worker protocol gave you. Use it. There is no `/work`.

You may write inside your box, inside `/home/dev/project/reports/autolab/local_cvd2/`,
and in `/tmp`. Writes to `src/`, `src_new/`, `reports/diaspora/`,
`reports/autolab/{entrypoints,targets,endpoints}/`, `ruby_examples/` (the app)
and `scripts/` are DENIED by the harness, and `in/config.json` is denied
explicitly. Those denials are the boundary, not an obstacle to route around: if
you believe the endpoint cannot be explored without crossing one, say so and
stop. `reports/autolab/local_cvd/` (the FIRST drive's record) is readable and
must not be written.

**Memory.** This machine has an OOM history. Put anything that starts a JVM or
a long Python job under a scope with a cap, and clear the JVM options variable
that leaks in from the parent:

    unset JAVA_TOOL_OPTIONS
    systemd-run --user --scope -p MemoryMax=10G --quiet <command>

### 2. The explorer, measured

`in/config.json` names `runtime.runner`. There is a launcher beside it that
already exports `JAVA_HOME`, `PATH`, `GEM_HOME` and `RAILS_ENV=concolic` and
runs the runner under `bundle exec jruby` from the app directory:

    /home/dev/project/reports/autolab/entrypoints/scaffold/conversation_visibilities_destroy/launch.sh

Measured 2026-10-02 on this machine: **a whole run of the explorer is ~40 s**,
almost all of it Rails boot; the exploration itself is 1.8 s. It is cheap. Run
it as often as you like.

    unset JAVA_TOOL_OPTIONS
    mkdir -p <box-root>/batch/dumps
    MAX_RUNS=90 TIME_BUDGET=900 DUMP_OUT=<box-root>/batch/dumps \
      systemd-run --user --scope -p MemoryMax=10G --quiet \
      .../scaffold/conversation_visibilities_destroy/launch.sh 2>&1 | tail -30

**Always set `DUMP_OUT`.** With it unset the runner writes dumps next to its own
source, inside the SHARED scaffold directory that every other endpoint reads.
That directory is pinned and you are denied writes to it.

**`dump_*.json` must end up at the TOP LEVEL of `batch/`.** The dump-side audits
are configured with `{batch}` = that directory and `{batch}` is the only
substitution `run_audits` offers. The first drive's attempt 1 left the corpus in
`batch/dumps/` and `statement_note_lint` exited 1 with `no dump_*.json under
.../batch` — one blocking line that said nothing about the corpus. Explore into
a subdirectory if you like, then copy every dump you keep directly into
`batch/`, and put the same files in `out/packet/dumps/`.

Four environment variables the shared driver reads, and they are the whole of
your steering: `EXTRA_SEEDS_JSON` (a JSON **list of seed dicts**, each one a
worklist root), `SEEDS_ONLY` (drive exactly those roots and nothing else — and
it also switches off the duplicate-path filter), `LABEL_SUFFIX` (added to every
dump label, so a targeted batch is identifiable), `TRACE`.

### 3. The baseline corpus is coverage-complete. That is not the whole job.

Measured on this machine before you started: the default invocation drives 18
runs, keeps **7 distinct paths**, ends `worklist empty : true`, and the
checker's coverage layer over those 7 dumps reports `missing_branches 0`,
`tree_complete true`, `truncated false`. So a bigger `MAX_RUNS` buys nothing —
the flip worklist is exhausted at 18.

What is open is the **assumption gate**. The coverage layer INFERS four
`ConfinementAssumption` pairs on this endpoint, over these four decisions:

    A  ..._Calculations_count_1_count == 1
    B  ..._devise_user_first_1_language == 'pl'
    C  ..._devise_user_first_1_language == 'xx'
    D  ..._FinderMethods_first_1_not_found == True

and the inferred pairs are A×B, A×C, A×D and B×D. Nothing declares them; they
are tested whether your `assumptions.json` mentions them or not.

### 4. `assumptions.json` is very likely `[]`, and that is correct

You have no licence not to explore: the worklist is exhausted and the tree is
complete. An empty declared list is the honest list here. Everything the gate
tests on this endpoint it infers for itself. If you do declare something, it
must be one of the 8 kinds and it must survive the validator the brief shows
you — the pre-gate runs the same validator and a refusal is a failed attempt.
**Do not drop, weaken or re-declare an assumption to make a gate row go away.**

### 5. `shim_tests.rb` — configured, and the first drive already solved it

The shim gate is wired. Both halves are measured:

* the engine's key set comes from exactly this command, which you may run:

      ruby /home/dev/project/src_new/runtimes/ruby_runtime/completion_checker/shim_extractor.rb \
        /home/dev/project/reports/autolab/targets/core.rb \
        /home/dev/project/reports/autolab/targets/shared_shims.rb

  It emits a JSON list of 22 shims on stdout.
* run with an EMPTY `SHIM_TESTS = {}`, the runner answers **14 PROTOCOL** (the
  runtime's own representative plumbing, decided at runtime from the real
  class — you cannot and need not test these) and **8 NO-TEST**, blocking.

**The first drive wrote those 8 bodies and they scored 10 PASS + 12 PROTOCOL,
0 red, against this same boundary.** The file is at

    /home/dev/project/reports/autolab/local_cvd/boxes/conversation_visibilities_destroy-batch-2-da27632d/out/packet/shim_tests.rb

Copy it. Do not rewrite it from scratch — that is solved work and your budget
belongs on §10. But **re-verify it yourself** before you submit, because a
malformed file is worse than an absent one: `shim_test_runner.rb` aborts with
`shim_tests.rb must define SHIM_TESTS`, writes no results file, and raises out
of `check()`, leaving **no report at all**, coverage verdict included.

    unset JAVA_TOOL_OPTIONS
    ruby .../shim_extractor.rb ... > /tmp/shims.json
    JRUBY_OPTS=--debug systemd-run --user --scope -p MemoryMax=10G --quiet \
      /home/dev/project/scripts/diaspora-concolic \
      /home/dev/project/src_new/runtimes/ruby_runtime/completion_checker/shim_test_runner.rb \
      /tmp/shims.json <your shim_tests.rb> /tmp/shim_results.json
    python3 -c "import json,collections;print(collections.Counter(x['verdict'] for x in json.load(open('/tmp/shim_results.json'))))"

A body either RUNS and reaches zero declared targets with 100 % of the real
method's executable lines, or it is blocking. There are no waivers and prose is
not evidence. If a body genuinely cannot run, say so per-key in
`batch/NOTES.md` with what you tried.

### 6. `assumption_manifest.json` — the paths that are right ON THE CHECK BOX

The check runs in a DIFFERENT box, with your packet mounted read-only at
`in/packet` relative to that box's root, which is that process's working
directory. So:

    {
      "batch_dir": "in/packet/dumps",
      "runner": ".../scaffold/conversation_visibilities_destroy/launch.sh",
      "workdir": "/home/dev/project",
      "env": {"DUMP_OUT": "in/packet/dumps", "JAVA_TOOL_OPTIONS": ""},
      "assumptions": []
    }

`runner` and `workdir` are absolute because they are outside your packet and
exist at those paths on every box here. `DUMP_OUT` must equal `batch_dir`: the
gate globs for the probe dumps it launched in `batch_dir`, the runner's own
directory and `workdir`, and with `DUMP_OUT` unset the probe dumps land in the
shared scaffold directory instead of anywhere the gate looks.

### 7. `produced_with.app_tree_digest` is REQUIRED on this campaign

Pre-gate step 3 compares it against the pin. Run the campaign's own
measurement and put the bare hex string in `packet.json`:

    python3 /home/dev/project/reports/autolab/local_cvd2/tools/app_tree_digest.py

Its docstring says exactly which paths it covers (`app/ lib/ config/
db/schema.rb Gemfile Gemfile.lock`). If it does not match the pin, you changed
the application: that is a refusal, and this campaign's spec sets
`app_source_edits: none`, so the answer is to revert, not to propose.

### 8. One gate is NOT configured and it is not yours to fix

`note_check` reports NOT CONFIGURED and that line will be in the report whatever
you do, because its artefact is a real-mode recording against a real database
and the config declares `fixtures: null` / `real_mode_plan: null`. **Do not
produce a `concrete_run.json`** — the brief forbids it and it would be a
fabricated ground truth. Seeing that blocking line in `response.json` is
expected; everything else in that list is either yours or named here as not.

### 9. What an honest submission looks like here

`dumps/` (every dump you kept), `assumptions.json` (probably `[]`),
`shim_tests.rb`, `assumption_manifest.json`, and `batch/NOTES.md` saying
per-pair and per-shim what you drove and what came back. Then `packet.json`,
re-read every file it names, then the marker — last, once.

Re-run `sha256sum in/config.json` for `config_digest`. **Do not reuse a digest
from the first drive's record** — this campaign's config differs from it (one
path), so the digest differs.

---

### 10. WHAT CHANGED SINCE THE FIRST DRIVE, AND WHAT THIS DRIVE IS FOR

The first drive ended `INCOMPLETE` with the four confinement rows reported

    NOT-TESTABLE — no run in the CURRENT corpus records both — the pair is
    inert, nothing to test

**That sentence was a defect and it has been fixed.** `src_new` commit
`ee49d91` ("Gates demand; the index is a cache; identity is structured"):

* A path condition's IDENTITY is now its structured expression. Dumps have
  carried a structured `expr` since 2026-09-23, so the corpus index keyed them
  as a Python dict repr while the gate looked up infix text; the two key sets
  were disjoint and `pick_bases_with` returned nothing on every corpus any
  runtime has written since the cutover. Measured over the first drive's own
  12-dump corpus: **0 of 4 pairs had a base before, all 4 have one now**
  (5, 2, 5 and 8 bases respectively).
* The four assumption gates now **EMIT DEMANDS** instead of inventing
  verdicts. `gate/demands.py`: `demand_for(assumption, config)` takes no
  corpus argument and `cache_lookup(point, batch)` is the only corpus reader.
  A cache miss is a **construction request**, not a verdict. For a pair the
  demand is the 2×2 over its two decisions — TT, TF, FT, FF — and each unmet
  cell comes back with the nearest run and a **seed delta** that would reach
  it.
* **Every banked probe and checkpoint is invalidated.** The first pass on each
  batch re-indexes and re-probes from scratch. Expect the check to take longer
  than the first drive's 45–56 s and do not read that as a hang.

So the rows are live for the first time. **Settling them is this drive's whole
job**, and the loop you are being asked to run has never been run by anyone.

**Attempt 1: submit the BASELINE corpus. Do not pre-construct co-occurrence
runs.** The first drive's agent guessed at co-occurrence runs before any gate
had asked for one. That is exactly what the demand mechanism exists to replace,
and doing it again would skip the thing under test. Drive the default
invocation, keep the distinct paths, verify coverage is complete, reuse the
shim file, and submit.

**Attempt 2 onward: read `in/response.json` and construct what the gate asked
for.** If a confinement row comes back carrying `demands`, each demand names:

* `point.decisions` — the `(expr, outcome)` pairs ONE run must record;
* `nearest_run` — the dump that already has the most of them;
* `seed_delta` — the seeds that run would need changed to reach the point.

Turn a `seed_delta` into a run with `SEEDS_ONLY=1` and an `EXTRA_SEEDS_JSON`
holding the nearest run's seeds UPDATED by the delta (read the base dump's
`concolic_seeds`; `SEEDS_ONLY` also switches off the duplicate-path filter, so
a path you already have will still be written):

    EXTRA_SEEDS_JSON='[{...base seeds merged with the delta...}]' SEEDS_ONLY=1 \
    LABEL_SUFFIX=_d1 DUMP_OUT=<box>/batch/d1 ... launch.sh

Then **CHECK WHAT THE DUMP ACTUALLY RECORDED** before you believe the run
discharged the demand. You can do that without the gate:

    PYTHONPATH=/home/dev/project/src_new python3 -c "
    from concolic.corpus.index import corpus_index, _TRACE_INDEX
    B='<your dumps dir>'; corpus_index(B)
    for p,(d,s,pcs) in sorted(_TRACE_INDEX[B].items()):
        print(p)
        for e,o in sorted(pcs): print('   ', o, e[:120])"

The keys printed are the condition IDENTITIES the gate looks up — compare them
to `point.decisions` literally. A run that sets both seeds but never EVALUATES
the second decision does not discharge the demand; the first drive produced
several of those.

If a demanded cell cannot be reached, that is the honest third outcome: record
in `batch/NOTES.md` what you drove, what the dump recorded, and why you believe
the cell is unreachable, and leave the row. The gate does not yet check a
demanded cell for satisfiability (`demands.py` says so in its own docstring), so
a Z3-infeasible cell WILL be demanded forever — if you think you have one, say
so, with the dump evidence. That is a finding, not a failure.

`ee49d91` is new and this is its first exercise outside its own tests. If the
engine misbehaves — a demand whose `seed_delta` is empty with no
`unconstructible` reason, a row that claims a witness you cannot find, a crash —
**raise it as an escalation (§2 of the protocol) with the evidence**, and do not
work around it by editing `src_new/`, which is denied anyway.

### 11. `pgrep -f <pattern>` MATCHES YOUR OWN COMMAND LINE

Measured on the first drive: the agent waited on
`until [ -f logs/both.done ] && ! pgrep -f shim_test_runner.rb.*batch-2-...; do sleep 3; done`.
`both.done` appeared in seconds; the loop then spun for **six and a half
minutes** of wall clock until an operator killed it, because the shell running
the loop has that same pattern in its own `/proc/<pid>/cmdline` and `pgrep -f`
matched it. Guard every such wait — `pgrep -f "[s]him_test_runner"`, or match on
the pid you started — or do not use `pgrep` at all: write a sentinel file when
the job ends and wait for the file, which is what `both.done` already was.
