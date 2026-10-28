---

## OPERATOR ADDENDUM 3 — this box, this endpoint, and what is actually open

The addendum above was written for a cloud box on a different endpoint. Where
the two disagree, THIS one is right about this campaign.

This is the **THIRD** drive of this endpoint. Both prior records are complete
and readable and must not be written:

* `/home/dev/project/reports/autolab/local_cvd/`  — drive 1, ended `INCOMPLETE`
* `/home/dev/project/reports/autolab/local_cvd2/` — drive 2, ended `INCOMPLETE`

What has changed since drive 2 is in §10, which is the point of this drive.
**Read §10 before you plan.**

### 1. Your box is a directory on this machine, and the paths are absolute

`host` backend: a box is a directory, not a container. Your `in/` and `repo/`
mounts are symlinks, nothing is isolated, and the box root is an absolute path
the worker protocol gave you. Use it. There is no `/work`.

You may write inside your box, inside `/home/dev/project/reports/autolab/local_cvd3/`,
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

    python3 /home/dev/project/reports/autolab/local_cvd3/tools/app_tree_digest.py

Its docstring says exactly which paths it covers (`app/ lib/ config/
db/schema.rb Gemfile Gemfile.lock`). If it does not match the pin, you changed
the application: that is a refusal, and this campaign's spec sets
`app_source_edits: none`, so the answer is to revert, not to propose.

`produced_with.runtime_revision` is this engine's HEAD and it has MOVED since
drive 2: `d73105bda75eb50c82d2eb3175154d163cd117db`. Do not copy drive 2's
`ee49d91...`.

Re-run `sha256sum in/config.json` for `config_digest`. **Do not reuse a digest
from either prior drive** — this campaign's config differs from both by one
path (`completion.batch_dir`), so the digest differs.

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
per-claim and per-shim what you drove and what came back. Then `packet.json`,
re-read every file it names, then the marker — last, once.

---

### 10. WHAT CHANGED SINCE DRIVE 2, AND WHAT THIS DRIVE IS FOR

Drive 2 ended `INCOMPLETE` with **five** blocking lines: `note_check: NOT
CONFIGURED`, three `assumption FAIL (ConfinementAssumption)` rows and one
`confinement NOT VERIFIED (NOT-TESTABLE)` row (reported as 1 OUTSTANDING). All
four of the latter were about the same four decisions:

    A  ..._Calculations_count_1_count == 1
    B  ..._devise_user_first_1_language == 'pl'
    C  ..._devise_user_first_1_language == 'xx'
    D  ..._FinderMethods_first_1_not_found == True

**`Confinement` has been DELETED as a kind.** `src_new` commit `d73105b`
("Six assumption kinds, one per level of the demand graph"):

* Confinement claimed *"these two decisions cannot cross-multiply inside a
  leaf"* — a **cube**-level fact implemented as a **pairwise edge** construct.
  Its own gate said so, by reclassifying two of its three refutations as
  *"removal-shaped dependence (foreclosure, X11), not a confined pair"*, which
  is foreclosure's definition. Measured store-wide before deleting (164
  corpora, 861 dumps, each run with the licence on and off): **0 endpoints
  change their `complete` verdict**, 158/164 byte-identical missing sets,
  largest movement ±2 demand cubes on corpora already incomplete.
* `CoverageResult.assumptions_to_dict()` **no longer carries confined pairs**.
  That is a wire change to every `coverage_summary.json` and it means drive 2's
  four rows do not exist for you to settle. Do not go looking for them and do
  not re-declare them under another kind to keep the row.
* **The two foreclosure kinds are one.** `Foreclosure` carries `conditioning`
  and `section` and claims all three wire tags — §16b's
  `"ForeclosureAssumption"` included, which no kind in the closed registry
  claimed before, so the gate was emitting a tag that could not resolve.
* **`AliasAssumption` is de-domained.** The kind is generic; its key functions
  (`statement_key`, `loop_key`, `canonical_result_name`, `is_statement_note`)
  moved behind `concolic/model/statement.py`'s provider seam with the bodies in
  `domains/ruby_rails_sql/statement.py`. **A declared alias with no provider
  installed now RAISES** (`NoStatementKeys`) rather than running inert. This
  config's `completion.assumption_cmd` launches
  `concolic/gate/assumption_checker.py` as a SUBPROCESS and its
  `completion.env` sets no `CONCOLIC_STATEMENT_KEYS`, so **if you declare an
  alias, expect that subprocess to raise.** Report it; do not work around it.
* **Every banked probe, checkpoint and corpus index is invalidated again** —
  the engine key digests the provider's own module now. The first pass
  re-indexes and re-probes from scratch. Drive 2's check took 556 s. Expect at
  least that and **do not read it as a hang.**

**So the six kinds are: `AliasAssumption` (merge nodes), `UntrackedPathAssumption`
(delete a node), `IndependenceAssumption` (cut an edge), `Foreclosure` (drop a
cube), `SymbolicConstraintAssumption` and `OneSideUntrackedPathAssumption`
(constrain the solver).** `ConfinementAssumption` is not one of them and the
validator will refuse it.

**WHAT THIS DRIVE IS FOR.** This is `d73105b`'s first real exercise outside its
own tests. Two questions, and they are the whole job:

1. **What blocks this endpoint now?** Drive 2's four confinement rows should
   simply not appear. Measure what IS in the gate's claim list — declared plus
   coverage-inferred — and report it, even if the answer is "nothing".
2. **Is `complete: true` reachable?** `note_check: NOT CONFIGURED` is a known
   structural wall (§8) and will stay. **If it is the ONLY remaining blocking
   line, say that in `NOTES.md` explicitly and in those words** — that is the
   result of this drive, and it converts a design question into a single
   decision for the owner. Do not manufacture work to look busy.

**Attempt 1: submit the BASELINE corpus. Do not pre-construct runs for a demand
nothing has asked for yet.** Drive the default invocation, keep the distinct
paths, verify coverage is complete, reuse the shim file, declare `[]`, submit.

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
the second decision does not discharge the demand; drive 1 produced several of
those.

If a demanded cell cannot be reached, that is the honest third outcome: record
in `batch/NOTES.md` what you drove, what the dump recorded, and why you believe
the cell is unreachable, and leave the row. The gate does not yet check a
demanded cell for satisfiability (`demands.py` says so in its own docstring),
so a Z3-infeasible cell WILL be demanded forever — if you think you have one,
say so, with the dump evidence. That is a finding, not a failure.

If the engine misbehaves — a demand whose `seed_delta` is empty with no
`unconstructible` reason, a row that claims a witness you cannot find, a crash,
a `NoStatementKeys` from a gate subprocess — **raise it as an escalation (§2 of
the protocol) with the evidence**, and do not work around it by editing
`src_new/`, which is denied anyway.

### 11. `pgrep -f <pattern>` MATCHES YOUR OWN COMMAND LINE

Measured on drive 1: the agent waited on
`until [ -f logs/both.done ] && ! pgrep -f shim_test_runner.rb.*batch-2-...; do sleep 3; done`.
`both.done` appeared in seconds; the loop then spun for **six and a half
minutes** of wall clock until an operator killed it, because the shell running
the loop has that same pattern in its own `/proc/<pid>/cmdline` and `pgrep -f`
matched it. Guard every such wait — `pgrep -f "[s]him_test_runner"`, or match on
the pid you started — or do not use `pgrep` at all: write a sentinel file when
the job ends and wait for the file, which is what `both.done` already was.
