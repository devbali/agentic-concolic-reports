---

## OPERATOR ADDENDUM 4 — this box, this endpoint, and what is actually open

The addendum above was written for a cloud box on a different endpoint. Where
the two disagree, THIS one is right about this campaign.

This is the **FOURTH** drive of this endpoint. All three prior records are
complete and readable and must not be written:

* `/home/dev/project/reports/autolab/local_cvd/`  — drive 1, ended `INCOMPLETE` (6 then 5 blocking)
* `/home/dev/project/reports/autolab/local_cvd2/` — drive 2, ended `INCOMPLETE` (5 blocking)
* `/home/dev/project/reports/autolab/local_cvd3/` — drive 3, ended `INCOMPLETE` (2 blocking)

What has changed since drive 3 is in §10, which is the point of this drive.
**Read §10 before you plan.** There is also a FOURTH STAGE on this drive
(§6.3's closing round, with the domain's own gate) that runs after the check
and is not yours — §8 is what you need to know about it.

### 1. Your box is a directory on this machine, and the paths are absolute

`host` backend: a box is a directory, not a container. Your `in/` and `repo/`
mounts are symlinks, nothing is isolated, and the box root is an absolute path
the worker protocol gave you. Use it. There is no `/work`.

You may write inside your box, inside `/home/dev/project/reports/autolab/local_cvd4/`,
and in `/tmp`. Writes to `src/`, `src_new/`, `reports/diaspora/`,
`reports/autolab/{entrypoints,targets,endpoints}/`, `ruby_examples/` (the app)
and `scripts/` are DENIED by the harness, and `in/config.json` is denied
explicitly. Those denials are the boundary, not an obstacle to route around: if
you believe the endpoint cannot be explored without crossing one, say so and
stop.

**Memory.** This machine has an OOM history. Put anything that starts a JVM or
a long Python job under a scope with a cap, and clear the JVM options variable
that leaks in from the parent:

    unset JAVA_TOOL_OPTIONS
    XDG_RUNTIME_DIR=/run/user/1000 \
      systemd-run --user --scope -p MemoryMax=10G --quiet <command>

(`systemd-run --user` fails with "Failed to connect to bus" without that
`XDG_RUNTIME_DIR` — measured on drive 2.)

### 2. The explorer, measured

`in/config.json` names `runtime.runner`. There is a launcher beside it that
already exports `JAVA_HOME`, `PATH`, `GEM_HOME` and `RAILS_ENV=concolic` and
runs the runner under `bundle exec jruby` from the app directory:

    /home/dev/project/reports/autolab/entrypoints/scaffold/conversation_visibilities_destroy/launch.sh

Measured on this machine: **a whole run of the explorer is ~40 s**, almost all
of it Rails boot; the exploration itself is 1.8 s. It is cheap. Run it as often
as you like.

    unset JAVA_TOOL_OPTIONS
    mkdir -p <box-root>/batch/dumps
    MAX_RUNS=90 TIME_BUDGET=900 DUMP_OUT=<box-root>/batch/dumps \
      XDG_RUNTIME_DIR=/run/user/1000 systemd-run --user --scope \
      -p MemoryMax=10G --quiet \
      .../scaffold/conversation_visibilities_destroy/launch.sh 2>&1 | tail -30

**Always set `DUMP_OUT`.** With it unset the runner writes dumps next to its own
source, inside the SHARED scaffold directory that every other endpoint reads.
That directory is pinned and you are denied writes to it.

**`dump_*.json` must end up at the TOP LEVEL of `batch/`.** The dump-side audits
are configured with `{batch}` = that directory and `{batch}` is the only
substitution `run_audits` offers. Drive 1's attempt 1 left the corpus in
`batch/dumps/` and `statement_note_lint` exited 1 with `no dump_*.json under
.../batch` — one blocking line that said nothing about the corpus. Explore into
a subdirectory if you like, then copy every dump you keep directly into
`batch/`, and put the same files in `out/packet/dumps/`.

Four environment variables the shared driver reads, and they are the whole of
your steering: `EXTRA_SEEDS_JSON` (a JSON **list of seed dicts**, each one a
worklist root), `SEEDS_ONLY` (drive exactly those roots and nothing else — and
it also switches off the duplicate-path filter), `LABEL_SUFFIX` (added to every
dump label, so a targeted batch is identifiable), `TRACE`.

### 3. The baseline corpus is coverage-complete

Measured on this machine, on this engine revision, over drive 2's own kept
corpus: the default invocation drives 18 runs, keeps **7 distinct paths**, ends
`worklist empty : true`, and the checker's coverage layer reports
`missing_branches 0`, `tree_complete true`, `truncated false`, `complete true`.
A bigger `MAX_RUNS` buys nothing — the flip worklist is exhausted at 18.

### 4. `assumptions.json` is very likely `[]`, and that is correct

You have no licence not to explore: the worklist is exhausted and the tree is
complete. An empty declared list is the honest list here. If you do declare
something, it must be one of the **six** kinds (§10) and it must survive the
validator; the pre-gate runs the same validator and a refusal is a failed
attempt. **Do not drop, weaken or re-declare an assumption to make a gate row
go away.**

### 5. `shim_tests.rb` — configured, and drive 1 already solved it

The shim gate is wired. Both halves are measured:

* the engine's key set comes from exactly this command, which you may run
  (it needs `LANG=C.UTF-8` or `String#scan` dies on "invalid byte sequence in
  US-ASCII"):

      LANG=C.UTF-8 ruby /home/dev/project/src_new/runtimes/ruby_runtime/completion_checker/shim_extractor.rb \
        /home/dev/project/reports/autolab/targets/core.rb \
        /home/dev/project/reports/autolab/targets/shared_shims.rb

  It emits a JSON list of 22 shims on stdout.
* run with an EMPTY `SHIM_TESTS = {}`, the runner answers **14 PROTOCOL** and
  **8 NO-TEST**, blocking.

**Drive 1 wrote those 8 bodies; drive 2 reused them byte-identically and they
scored 10 PASS + 12 PROTOCOL, 0 red, against this same boundary.** The file is
at

    /home/dev/project/reports/autolab/local_cvd2/boxes/conversation_visibilities_destroy-batch-1-229a7a54/out/packet/shim_tests.rb

Copy it. Do not rewrite it from scratch — that is solved work and your budget
belongs on §10. But **re-verify it yourself** before you submit, because a
malformed file is worse than an absent one: `shim_test_runner.rb` aborts with
`shim_tests.rb must define SHIM_TESTS`, writes no results file, and raises out
of `check()`, leaving **no report at all**, coverage verdict included.

    unset JAVA_TOOL_OPTIONS
    LANG=C.UTF-8 ruby .../shim_extractor.rb ... > /tmp/shims.json
    JRUBY_OPTS=--debug XDG_RUNTIME_DIR=/run/user/1000 \
      systemd-run --user --scope -p MemoryMax=10G --quiet \
      /home/dev/project/scripts/diaspora-concolic \
      /home/dev/project/src_new/runtimes/ruby_runtime/completion_checker/shim_test_runner.rb \
      /tmp/shims.json <your shim_tests.rb> /tmp/shim_results.json
    python3 -c "import json,collections;print(collections.Counter(x['verdict'] for x in json.load(open('/tmp/shim_results.json'))))"

A body either RUNS and reaches zero declared targets with 100 % of the real
method's executable lines, or it is blocking. There are no waivers and prose is
not evidence. If a body genuinely cannot run, say so per-key in
`batch/NOTES.md` with what you tried.

### 6. `assumption_manifest.json` — USE DRIVE 2's, IT IS THE CORRECTED ONE

The check runs in a DIFFERENT box, with your packet mounted read-only at
`in/packet` relative to that box's root, which is that process's working
directory. Drive 2 verified the following manifest end to end, and it
**deviates deliberately** from drive 1's addendum §6, which prescribed
`workdir: /home/dev/project` + `DUMP_OUT: in/packet/dumps` and is WRONG:
`diaspora-concolic` cd's into the app directory and `autolab_dse.rb:1108` uses
`DUMP_OUT` verbatim, so a relative `DUMP_OUT` writes the probe dumps into the
app tree, where `replay._dump_dirs` never looks — the probes come back empty
with no error. Use this:

    {
      "batch_dir": "in/packet/dumps",
      "runner": ".../scaffold/conversation_visibilities_destroy/launch.sh",
      "workdir": "/tmp",
      "env": {"DUMP_OUT": "/tmp", "JAVA_TOOL_OPTIONS": ""},
      "assumptions": []
    }

`runner` is absolute because it is outside your packet and exists at that path
on every box here. If you change this, say in `NOTES.md` what you verified and
how.

### 7. `produced_with.app_tree_digest` is REQUIRED on this campaign

Pre-gate step 3 compares it against the pin. Run the campaign's own
measurement and put the bare hex string in `packet.json`:

    python3 /home/dev/project/reports/autolab/local_cvd4/tools/app_tree_digest.py

Its docstring says exactly which paths it covers (`app/ lib/ config/
db/schema.rb Gemfile Gemfile.lock`). If it does not match the pin, you changed
the application: that is a refusal, and this campaign's spec sets
`app_source_edits: none`, so the answer is to revert, not to propose.

`produced_with.runtime_revision` is this engine's HEAD and it has MOVED since
drive 3: `450893a2b4d066a7b6fcb2dccf8e773e9c985ae3`. Do not copy drive 3's
`d73105b...`.

Re-run `sha256sum in/config.json` for `config_digest`. **Do not reuse a digest
from either prior drive** — this campaign's config differs from both by one
path (`completion.batch_dir`), so the digest differs.

### 8. THE NOTE CHECK HAS MOVED TIERS. It is still not yours.

On drives 1-3 the engine reported `note_check: NOT CONFIGURED (concrete_run +
note_check_cmd are mandatory)` as a blocking line, on every attempt, whatever
the agent did. **That line is gone from this engine.** `src_new` commit
`a20ddd7` deleted the generic engine's `note_check` step: the check is now
`domains/ruby_rails_sql/checks.py::shape_check`, reached through
`Domain.check(policy, real)` by DESIGN_SWEEP §6.3's STATIC HALF, and gated
there as `WorkResult.domain_blocking`. `concolic/checks/run.py` appends nothing
for it any more and `note_check_cmd` configures nothing.

**What that means for you: the obligation did not disappear, it moved to a
tier you are not in.** A fourth stage runs after the check on this drive
(`drive.py --stage concrete`) and it is EXPECTED to block, because the
artefact that would discharge `shape_check` is a real-mode recording against a
real database, this endpoint declares `fixtures: null` / `real_mode_plan:
null`, and `drive_real_mode` is not defined anywhere in the tree.

* **Do NOT produce a `concrete_run.json`, a `real_mode_plan.json`, or
  anything shaped like a real-mode recording.** The brief forbids it and it
  would be a fabricated ground truth. The domain reports an UNMET OBLIGATION
  and that is the honest state.
* Nothing about the domain gate is in your packet and nothing you submit can
  change it. Do not mention it in `NOTES.md` as work you did or could not do.
* It is also no longer a line in `in/response.json`, so if a previous drive's
  notes told you to expect `note_check: NOT CONFIGURED` there, they are stale.

### 9. What an honest submission looks like here

`dumps/` (every dump you kept), `assumptions.json` (probably `[]`),
`shim_tests.rb`, `assumption_manifest.json`, and `batch/NOTES.md` saying
per-claim and per-shim what you drove and what came back. Then `packet.json`,
re-read every file it names, then the marker — last, once.

---

### 10. WHAT CHANGED SINCE DRIVE 3, AND WHAT THIS DRIVE IS FOR

Drive 3 ended `INCOMPLETE` with exactly **two** blocking lines and nothing
else — no unsettled rows, no unwalked prefixes:

    note_check: NOT CONFIGURED (concrete_run + note_check_cmd are mandatory)
    assumption gate: NOT CONFIGURED (assumption_cfg is mandatory; the engine
                                     supplies the gate itself)

**Both of those are engine defects that have since been fixed, and neither was
your predecessor's fault.**

1. **`note_check` is gone from the engine** (`a20ddd7`). See §8. The check is
   the domain's now and is gated in a stage you are not in.

2. **An empty declared list is no longer a missing artefact.** Drive 3
   submitted a perfectly good `assumption_manifest.json` AND `assumptions.json`
   of `[]`, and `concolic/checks/assumptions.py` returned a bare `None` for
   both "no manifest" and "a manifest but nothing declared" — so
   `checks/run.py` rendered the second as `assumption gate: NOT CONFIGURED`.
   The two conditions are now distinct: no manifest still blocks, a manifest
   with no claims is a **VACUOUS PASS** (`green: true`, `vacuous: true`,
   `declared: 0`), which is what a universally quantified statement over an
   empty set means. Drive 3's own check box is where that was measured.

**WHAT THIS DRIVE IS FOR.** Two questions, and they are the whole job:

1. **Can the ENGINE's conjunction now be satisfied on this endpoint?** Both of
   drive 3's lines should be gone. If `complete: true` comes back, say so in
   `NOTES.md` in those words — it is the first time any drive of this endpoint
   has reached it, and it is the result that matters.
2. **If something else blocks instead, what?** Measure it and report it. Do
   not manufacture work to look busy and do not assume drive 3's corpus was
   deficient: it was not.

**Attempt 1: submit the BASELINE corpus, and reuse drive 3's solved work.**
Drive 3's packet is readable and every part of it was accepted:

    /home/dev/project/reports/autolab/local_cvd3/boxes/conversation_visibilities_destroy-batch-1-c5e6200d/out/packet/

7 distinct dumps, `assumptions.json` = `[]`, `shim_tests.rb`, and an
`assumption_manifest.json` with the corrected `workdir: /tmp` +
`DUMP_OUT: /tmp`. Copy the dumps and the shim file, **re-verify both yourself**
(re-run the explorer if you want them regenerated in place; re-run
`shim_test_runner.rb` once to confirm the shim file still scores clean), and
spend the rest of your budget on getting the submission shape right rather
than on new exploration. The worklist is exhausted at 18 runs and a bigger
`MAX_RUNS` buys nothing.

**Three things that are per-drive and must NOT be copied from drive 3:**

* `config_digest` — re-run `sha256sum in/config.json`. This config differs from
  drive 3's by `completion.batch_dir` and one `_note_*` key.
* `produced_with.runtime_revision` — `450893a2b4d066a7b6fcb2dccf8e773e9c985ae3`.
* `completion.batch_dir` is under `local_cvd4/`, so your dumps go in YOUR
  batch directory. `assumption_manifest.batch_dir` stays `in/packet/dumps`
  (relative to the CHECK box root) — that part is right and is §6.

**Attempt 2 onward: read `in/response.json` and construct what the gate asked
for.** If a gate row comes back carrying `demands`, each demand names:

* `point.decisions` — the `(expr, outcome)` pairs ONE run must record;
* `nearest_run` — the dump that already has the most of them;
* `seed_delta` — the seeds that run would need changed to reach it.

Turn a `seed_delta` into a run with `SEEDS_ONLY=1` and an `EXTRA_SEEDS_JSON`
holding the nearest run's seeds UPDATED by the delta (read the base dump's
`concolic_seeds`; `SEEDS_ONLY` also switches off the duplicate-path filter, so
a path you already have will still be written):

    EXTRA_SEEDS_JSON='[{...base seeds merged with the delta...}]' SEEDS_ONLY=1 \
    LABEL_SUFFIX=_d1 DUMP_OUT=<box>/batch/d1 ... launch.sh

Then **CHECK WHAT THE DUMP ACTUALLY RECORDED** before you believe the run
discharged the demand:

    PYTHONPATH=/home/dev/project/src_new python3 -c "
    from concolic.corpus.index import corpus_index, _TRACE_INDEX
    B='<your dumps dir>'; corpus_index(B)
    for p,(d,s,pcs) in sorted(_TRACE_INDEX[B].items()):
        print(p)
        for e,o in sorted(pcs): print('   ', o, e[:120])"

The keys printed are the condition IDENTITIES the gate looks up — compare them
to `point.decisions` literally. A run that sets both seeds but never EVALUATES
the second decision does not discharge the demand.

If a demanded cell cannot be reached, that is the honest third outcome: record
in `batch/NOTES.md` what you drove, what the dump recorded, and why you believe
the cell is unreachable, and leave the row. If the engine misbehaves — a demand
whose `seed_delta` is empty with no `unconstructible` reason, a row that claims
a witness you cannot find, a crash, a `NoStatementKeys` from a gate subprocess
— **raise it as an escalation (§2 of the protocol) with the evidence**, and do
not work around it by editing `src_new/`, which is denied anyway.

### 11. `pgrep -f <pattern>` MATCHES YOUR OWN COMMAND LINE

Measured on drive 1: the agent waited on
`until [ -f logs/both.done ] && ! pgrep -f shim_test_runner.rb.*batch-2-...; do sleep 3; done`.
`both.done` appeared in seconds; the loop then spun for **six and a half
minutes** of wall clock until an operator killed it, because the shell running
the loop has that same pattern in its own `/proc/<pid>/cmdline` and `pgrep -f`
matched it. Guard every such wait — `pgrep -f "[s]him_test_runner"`, or match on
the pid you started — or do not use `pgrep` at all: write a sentinel file when
the job ends and wait for the file, which is what `both.done` already was.
