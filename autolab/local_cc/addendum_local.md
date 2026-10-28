---

## OPERATOR ADDENDUM 2 — this box, and what would make this attempt succeed

Two things are different from the addendum above. Read them and then work.

### 1. Your box is a directory on a machine other people are using

This campaign runs on the `host` execution backend: **your box is not a
container and not a VM, it is a directory**, and the worker protocol above gave
you its absolute path. The `ro` mounts (`in/config.json`, `repo/`) are symlinks
and a convention here, not an enforced mode. So the boundary is YOURS to keep:

* Write only inside your box (`batch/`, `out/`) and into the `DUMP_OUT`
  directory you choose inside it. Your own settings file denies `Write`/`Edit`
  outside the box, but `Bash` can reach the whole filesystem and nothing will
  stop you — so do not.
* **Never write into any of these, by any tool, for any reason:**
  `/home/dev/project/src/`, `/home/dev/project/src_new/`,
  `/home/dev/project/reports/diaspora/`,
  `/home/dev/project/reports/autolab/` (except your own box tree),
  and the `repo/` you were given. Other agents are working in them right now.
* Do not `git commit`, `git push`, or start anything in the background that
  outlives you.

`/home/dev/project/src_new` is on `PYTHONPATH` for a plain `python3` and is
**readable** — you may import from it, and §3 below says why you want to.

### 2. Producing a corpus is not the job. WIDENING it is.

`in/response.json` carries the previous check of this endpoint, against a
packet with this exact `config_digest`. Its verdict was `INCOMPLETE`, and the
two coverage lines are the ones you exist to clear:

* **8 missing branches** — the demand set has leaves no run in that corpus
  walked;
* **the execution tree is not complete**, with 2 missing prefixes named
  literally in the response.

That corpus was 14 dumps and it was **inherited**, not produced: the explorer
could not be run at all on the box that submitted it. You can run it. A packet
that hands back those same 14 dumps, or 14 new ones of the same shape, is a
wasted attempt.

**The target is a corpus for which the checker reports
`missing_branches == 0` AND `tree_complete == true`.** That is what
"coverage-complete" means and it is a thing you can measure yourself, before
you submit — see §3.

### 3. Measure your own coverage. Do not guess and do not submit blind.

The same checker that will judge you is importable here. Run this against the
dumps you have produced, as often as you like:

    PYTHONPATH=/home/dev/project/src_new python3 -c "
    import json, sys
    from concolic.checks import load_runs
    from concolic.check import run_complete
    runs = load_runs(sys.argv[1])
    s = run_complete(runs)
    print('runs            :', s['total_runs'])
    print('coverage_complete:', s['coverage_complete'])
    print('missing_branches :', s['missing_branches'])
    print('tree_complete    :', s['tree_complete'])
    print('tree_missing     :', json.dumps(s['tree_missing'], indent=1))
    " <your dumps dir>

`completion` will say NOT CONFIGURED there and that is expected — this call
passes no config, so only the coverage layer runs. **Coverage is the part you
can move.** If you want the individual missing branches rather than the count:

    PYTHONPATH=/home/dev/project/src_new python3 -c "
    import sys
    from concolic.checks import load_runs
    from concolic.coverage import CoverageChecker
    r = CoverageChecker(load_runs(sys.argv[1])).check_coverage()
    for m in r.missing[:40]: print(m)
    " <your dumps dir>

Write each measurement into `batch/NOTES.md` with the run count it was taken
at. That file is your memory; re-measuring is cheap, re-reading directories is
not.

### 4. How to actually widen it, with the numbers that were measured today

The explorer is **prefix-directed**: it keeps a worklist of unexplored branch
flips and its summary line prints `worklist empty : true|false`. An exploration
that ends with `worklist empty : false` stopped because it ran out of budget,
not because it ran out of work. **`worklist empty : true` is what you are
driving at**; it is the explorer's own statement that it has nothing left to
flip, and it is what makes `missing_branches == 0` reachable.

Measured on this machine today, for this endpoint:

* **Rails boot costs about 6 minutes** and happens once per invocation.
* **Exploration itself costs seconds**: 4 runs took 13.2 s after boot.

So the invocation shape that matters is ONE long run with a high `MAX_RUNS` and
a high `TIME_BUDGET`, not ten short ones. The config's `scenarios` numbers
(`MAX_RUNS=24`, `TIME_BUDGET=300`) are what the previous sweep drove and they
stopped with `worklist empty : false` at run 4. **You may raise them** — they
are environment variables you pass to the explorer, not config you are editing.
Start around `MAX_RUNS=250 TIME_BUDGET=2400` and read the summary.

Two other environment variables the shared driver reads, for when the worklist
empties and branches are still missing:

* `EXTRA_SEEDS_JSON=<file>` — a JSON list of seed dictionaries pushed onto the
  front of the worklist. This is how you aim at a specific leaf: take a missing
  branch, work out the input that reaches it, and seed it.
* `SEEDS_ONLY=1` — drive only those seeds, skipping the seen-path filter.

Dumps accumulate: point `DUMP_OUT` at the same directory across invocations and
add a `LABEL_SUFFIX=<tag>` so filenames do not collide.

### 5. Budget your wall clock against a 6-minute boot

You have a long ceiling, and the shape that fits it is:

1. **0-5 min** — read `in/config.json` and `in/response.json` once; write
   `batch/NOTES.md`; compute the config digest.
2. **5-15 min** — start the FIRST long exploration. Do not wait on it idly and
   do not start it twice: one JRuby+Rails process is about 4 GB and this
   machine is shared. While it runs, write `assumptions.json`,
   `assumption_manifest.json` and (if you can do it honestly) `shim_tests.rb`.
3. **then** — measure coverage (§3). If `worklist empty : false`, raise the
   budget and go again into the same `DUMP_OUT`. If it is `true` and branches
   are still missing, read them and seed them (§4).
4. **last 10 min** — write `packet.json`, re-read every file it names, then the
   marker. Once, last.

### 6. What an honest submission says when it is not complete

If you cannot reach `missing_branches == 0`, submit anyway, and put in
`packet.json` — in a free-text field of your choosing — the LAST measurement
you took: run count, `missing_branches`, `tree_complete`, `tree_missing`, and
the explorer's `worklist empty` line. A precise negative is a result. An
invented number, a corpus you relabelled, or a `dumps/` you did not produce is
not, and the brief above already tells you what happens to it.

### 7. Two gates ARE configured this time, so your two artefacts are live

The previous attempt's third blocking line was "the config declares no
`completion` block: mocks/shims and every gate ... were not run". This
campaign's config declares one. Concretely:

* the **shim gate** is configured — the extractor and the test runner are named
  in the config, and `shim_tests` is taken from YOUR PACKET. The key set is the
  engine's: it is what
  `ruby /home/dev/project/src/ruby_runtime/completion_checker/shim_extractor.rb`
  extracts from `/home/dev/project/reports/autolab/targets/core.rb` and
  `shared_shims.rb`, and you may run that command yourself to read the keys —
  it is plain Ruby and takes under a second. Note before you start writing
  bodies: the runner decides PROTOCOL **at runtime from the real class**, so a
  key that is the symbolic runtime's own rep plumbing needs no body at all.
  Find out which ones those are before you write anything.
* the **assumption gate** is configured, and `assumption_cfg` is taken from
  YOUR PACKET's `assumption_manifest.json`. Its `batch_dir` and `runner` are
  read unguarded — get them right or omit the whole manifest. `batch_dir` is
  `in/packet/dumps` (the check process's working directory IS the box root);
  `runner` must be a command that really re-drives one run of your batch, by
  absolute path.
* **`note_check` is NOT configured and will not be.** Its artefact is a
  real-mode recording and neither you nor this config can honestly supply one
  (this config declares `fixtures: null` and `real_mode_plan: null`). It will
  be reported NOT CONFIGURED, that line will block `complete`, and that is the
  correct and intended outcome. **Do not try to fix it.** Do not write a
  `concrete_run.json`, do not put one in your packet, and do not name a
  `note_check_cmd` anywhere — the brief above explains what that would be.

So the ranking of your effort is: **the corpus first** (it is the only blocking
line you can actually clear), then the assumption manifest, then the shim
tests. If you run out of clock, an omitted `shim_tests` is a recorded NOT
CONFIGURED and is a fine place to stop.

### 8. ONE turn. Do not end it before you have submitted.

This overrides the brief's "frequent boundaries" section, which was written for
a different harness. On THIS backend your session is driven by an adapter that
sends the brief as the first user message and then **sends nothing else**.
There is no coordinator nudging you between turns and no scheduled follow-up.
So if you end your turn before the marker is written:

* your process stays alive with nothing to do,
* the box keeps its wall clock running until the ceiling,
* and the attempt is recorded as `no_submission` — a failed attempt.

Nothing is gained by stopping early and nothing is lost by working through.
Use sub-agents freely if your harness offers them (they are a boundary inside
your turn, which is the useful kind), keep long jobs in the foreground of a
Bash call rather than backgrounding them and returning, and write
`batch/NOTES.md` as you go so a crash does not cost you the reasoning. But
**the turn ends when `out/packet.submitted` is written, and not before.**

### 9. `shim_tests.rb` has a FORMAT, and getting it wrong is worse than omitting it

MEASURED on this endpoint today, against the previous attempt's packet: the
file it submitted was 36 plain Ruby methods named `test_<something>`, derived
from the targets it saw during exploration. The runner aborted with

    shim_tests.rb must define SHIM_TESTS

and because it wrote no results file the gate step raised out of the whole
check pass. **A malformed `shim_tests.rb` does not produce a red gate — it
destroys the run, including the coverage verdict you worked for.** So:

* The file must define a constant `SHIM_TESTS`, a Hash. Nothing else is read.
* The KEYS are the engine's, not yours. They are exactly the
  `"<owner>.<method>"` strings the extractor prints — run the extractor (§7)
  and use its output. There were 22 of them today, not 36, and they are not the
  targets your exploration happened to call.
* The VALUES are as the runner's own header documents:
  `{ targets: [[Mod, :meth], ...], coverage_of: [Owner, :meth, :singleton|:instance],
  fixture: -> { ... } }` for a real test, or `{ real_class: "Comment" }` to state
  that a key is the AR/Ruby protocol on a named real class — which the runner
  VERIFIES against that class and will reject if the class has a body of its
  own. Read
  `/home/dev/project/src/ruby_runtime/completion_checker/shim_test_runner.rb`
  from the top: its first 30 lines are the contract and its verdict dispatch is
  about 200 lines down. It is the only authority on this format.
* A key you leave out of the hash is a `NO-TEST` red **unless** the runner
  decides it is rep plumbing at runtime, in which case it is `PROTOCOL` and
  needs nothing. Leaving keys out is safe. Malformed Ruby is not.
* Before you put the file in your packet: `ruby -c <file>` must pass, and
  `ruby -e 'load "<file>"; abort "no SHIM_TESTS" unless defined?(SHIM_TESTS)'`
  must pass. If either fails, fix it or **omit the `shim_tests` key from
  `packet.json` entirely** — that is a recorded NOT CONFIGURED and costs you
  nothing else.

The same applies to `assumption_manifest.json`: `batch_dir` and `runner` are
read unguarded, so a manifest missing either is a crash with a red verdict
attached. Omit the whole key rather than ship a half one.
