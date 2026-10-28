---

## OPERATOR ADDENDUM 2 — this box, this endpoint, and what is actually open

The addendum above was written for a cloud box on a different endpoint. Where
the two disagree, THIS one is right about this campaign.

### 1. Your box is a directory on this machine, and the paths are absolute

`host` backend: a box is a directory, not a container. Your `in/` and `repo/`
mounts are symlinks, nothing is isolated, and the box root is an absolute path
the worker protocol gave you. Use it. There is no `/work`.

You may write inside your box, inside `/home/dev/project/reports/autolab/local_cvd/`,
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
    systemd-run --user --scope -p MemoryMax=10G --quiet <command>

### 2. The explorer, measured today

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

Four more environment variables the shared driver reads, and they are the whole
of your steering: `EXTRA_SEEDS_JSON` (a JSON **list of seed dicts**, each one a
worklist root), `SEEDS_ONLY` (drive exactly those roots and nothing else — and
it also switches off the duplicate-path filter, which matters below),
`LABEL_SUFFIX` (added to every dump label, so a targeted batch is identifiable),
`TRACE`.

### 3. The baseline corpus is already coverage-complete. That is NOT the job.

Measured today, before you started: the default invocation drives 18 runs, keeps
**7 distinct paths**, ends `worklist empty : true`, and the checker's coverage
layer over those 7 dumps reports `missing_branches 0`, `tree_complete true`,
`truncated false`. So reproducing the baseline buys nothing, and a bigger
`MAX_RUNS` buys nothing either — the flip worklist is exhausted at 18.

What is open is the **assumption gate**. The coverage layer INFERS four
`ConfinementAssumption` pairs on this endpoint, and over the baseline corpus all
four come back `NOT-TESTABLE — no run in the CURRENT corpus records both — the
pair is inert, nothing to test`. That is four blocking lines, and the brief
above tells you what an unsettled row is: a NO, and your work.

The four pairs, by their seed dimensions:

| pair | decision A | decision B |
|---|---|---|
| 1 | `..._Calculations_count_1_count == 1` | `..._devise_user_first_1_language == 'pl'` |
| 2 | `..._Calculations_count_1_count == 1` | `..._devise_user_first_1_language == 'xx'` |
| 3 | `..._Calculations_count_1_count == 1` | `..._FinderMethods_first_1_not_found == True` |
| 4 | `..._devise_user_first_1_language == 'pl'` | `..._FinderMethods_first_1_not_found == True` |

The gate needs **one run that RECORDS BOTH path conditions** — not both seeds,
both recorded decisions. The baseline has runs with both seeds set and the
second decision never evaluated, which is exactly why the rows are inert. The
instrument for this is `SEEDS_ONLY=1` plus an `EXTRA_SEEDS_JSON` holding a seed
dict that sets BOTH dimensions, e.g.

    [{"SYM_RESULT_ActiveRecord__Calculations_count_1_count": 1,
      "SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_language": "pl"}]

Drive it, then CHECK whether the dump records both exprs before you believe it.
You can check without a box:

    PYTHONPATH=/home/dev/project/src_new python3 -c "
    from concolic.corpus.index import corpus_index
    for p, seeds, scen, rec in corpus_index('<your dumps dir>'):
        print(p); [print('   ', r) for r in rec]"

If a pair cannot be made to co-occur, that is the honest third outcome the
brief describes: record in `batch/NOTES.md` what you drove and what the dump
recorded, and leave the row unsettled. **Do not drop or re-declare an
assumption to make a row go away**, and do not put a confinement record in
`assumptions.json` to "confirm" one — the four pairs are INFERRED by the
checker and are tested whether you declare them or not.

### 4. `assumptions.json` is very likely `[]`, and that is correct

You have no licence not to explore: the worklist is exhausted and the tree is
complete. An empty declared list is the honest list here. Everything the gate
tests on this endpoint it infers for itself. If you do declare something, it
must be one of the 8 kinds and it must survive the validator the brief shows
you — the pre-gate runs the same validator and a refusal is a failed attempt.

### 5. `shim_tests.rb` — this IS configured, and the key set is knowable

Unlike the previous campaign, the shim gate is wired. Both halves are measured:

* the engine's key set comes from exactly this command, which you may run:

      ruby /home/dev/project/src_new/runtimes/ruby_runtime/completion_checker/shim_extractor.rb \
        /home/dev/project/reports/autolab/targets/core.rb \
        /home/dev/project/reports/autolab/targets/shared_shims.rb

  It emits a JSON list of 22 shims on stdout.
* run with an EMPTY `SHIM_TESTS = {}`, the runner answers **14 PROTOCOL** (the
  runtime's own representative plumbing, decided at runtime from the real
  class — you cannot and need not test these) and **8 NO-TEST**, which are
  blocking. Those 8 are your work:

      obj.image_url
      obj.hidden_shareables
      obj.post_location
      ActiveRecord::Associations::SingularAssociation.find_target
      ::Gon.singleton_class.preloads
      ActionDispatch::Journey::Router::Utils.singleton_class.escape_segment
      ActiveRecord::Base.singleton_class.DYNAMIC
      ActiveRecord::Base.update

**FORMAT, and getting it wrong is worse than omitting it.** The file must
define the CONSTANT `SHIM_TESTS`, a Hash keyed by the engine's keys:

    SHIM_TESTS = {
      "obj.image_url" => {
        targets:     [[SomeModule, :some_method], ...],   # the zero-target set
        coverage_of: [Owner, :meth, :instance],           # or :singleton
        fixture:     -> { ... }                           # must RUN
      },
    }

A file of `def test_*` methods, or any other shape, makes
`shim_test_runner.rb` abort with `shim_tests.rb must define SHIM_TESTS`, write
no results file, and raise `RuntimeError` out of `test_shims` — which
propagates out of `check()` and leaves **no report at all**, coverage verdict
included. So: run the runner yourself before you submit. It takes 40 s.

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

    python3 /home/dev/project/reports/autolab/local_cvd/tools/app_tree_digest.py

Its docstring says exactly which paths it covers (`app/ lib/ config/
db/schema.rb Gemfile Gemfile.lock`). If it does not match the pin, you changed
the application: that is a refusal unless the packet also carries a proposal,
and this campaign's spec sets `app_source_edits: none`, so the answer is to
revert, not to propose.

### 8. One gate is NOT configured and it is not yours to fix

`note_check` reports NOT CONFIGURED and that line will be in the report whatever
you do, because its artefact is a real-mode recording against a real database
and the config declares `fixtures: null` / `real_mode_plan: null`. **Do not
produce a `concrete_run.json`** — the brief forbids it and it would be a
fabricated ground truth. Seeing that blocking line in `response.json` is
expected; everything else in that list is either yours or named here as not.

### 9. What an honest submission looks like here

`dumps/` (the baseline 7 plus whatever co-occurrence runs you produced),
`assumptions.json` (probably `[]`), `shim_tests.rb` with the 8 bodies,
`assumption_manifest.json`, and `batch/NOTES.md` saying per-pair and per-shim
what you drove and what came back. Then `packet.json`, re-read every file it
names, then the marker — last, once.

---

### 10. ATTEMPT 2 — what changed, and the two things attempt 1 got wrong

Attempt 1 submitted a good packet: 12 dumps, coverage complete (`missing_branches
0`, `tree_complete true`), the shim gate fully green (22 keys, **10 PASS + 12
PROTOCOL, 0 red**), `assumptions.json` `[]` accepted by the validator, the
pre-gate passed all three steps, and two escalations raised that were both
correct. The check came back `INCOMPLETE` with six blocking lines. **Two of
them were the coordinator's fault, not yours, and both are fixed in the config
you now hold.**

1. **`in/config.json` HAS CHANGED, so its digest has changed.** Re-run
   `sha256sum in/config.json` and use the new value. Do not reuse attempt 1's.
   What changed: `completion.workdir` is gone (it made your own
   `assumption_manifest.batch_dir` resolve against `/home/dev/project` instead
   of against the check box root — your escalation
   `manifest-relative-batchdir` was right about the first half of this, and
   the fix is on the config side, so keep `in/packet/dumps`), and the two
   `_note_*` keys now record both faults.

2. **`dump_*.json` must be at the TOP LEVEL of `batch/`.** The dump-side audits
   are configured with `{batch}` = that directory, and `{batch}` is the only
   substitution `run_audits` offers. Attempt 1 left the corpus in
   `batch/dumps/` and `batch/cooc/`, so `statement_note_lint` exited 1 with
   `no dump_*.json under .../batch` — one blocking line that says nothing
   about your corpus. Put every dump you keep directly in `batch/`, and put
   the same files in `out/packet/dumps/`. Keep your logs and notes in
   subdirectories if you like; only `dump_*.json` placement matters.

**What you do NOT need to redo.** The corpus is already coverage-complete and
the worklist is exhausted, and `batch/shim_tests.rb` already scores 10 PASS +
12 PROTOCOL against this same boundary. Re-verify both rather than rebuilding
them: re-run the explorer if you want the dumps regenerated in place, re-run
`shim_test_runner.rb` once to confirm the file still scores clean, and spend
the rest of your budget on `response.json`.

**The four confinement rows will come back unsettled again, and that is not
your failure.** Attempt 1 established why, and the coordinator has since
confirmed it by differential: the dumps carry `path_condition.expr` as
STRUCTURED IR, `concolic/corpus/index.py::_index_row` indexes
`canon(ev["expr"])` — which is `str(dict)` on such a dump — and
`concolic/gate/replay.py::pick_bases_with` looks up the infix text the coverage
layer puts in `expr_a`/`expr_b`. Measured over your own attempt-1 corpus:
**0 of 4 pairs have a base under the shipped index; 4 of 4 have one under a
`render_legacy` index** (5, 2, 5 and 10 bases respectively). So the rows are a
reader defect in `src_new`, not an exploration target, and no seed choice moves
them. Leave them unsettled, say so in `batch/NOTES.md`, and do not re-raise the
escalation — it is recorded. Do not drop or re-declare an assumption.

### 11. `pgrep -f <pattern>` MATCHES YOUR OWN COMMAND LINE

Measured on attempt 2: the agent waited on
`until [ -f logs/both.done ] && ! pgrep -f shim_test_runner.rb.*batch-2-...; do sleep 3; done`.
`both.done` appeared in seconds; the loop then spun for **six and a half
minutes** of wall clock until an operator killed it, because the shell running
the loop has that same pattern in its own `/proc/<pid>/cmdline` and `pgrep -f`
matched it. Guard every such wait — `pgrep -f "[s]him_test_runner"`, or match on
the pid you started — or do not use `pgrep` at all: write a sentinel file when
the job ends and wait for the file, which is what `both.done` already was.
