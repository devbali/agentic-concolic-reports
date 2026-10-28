---

## OPERATOR ADDENDUM — `tags_index`, this box, and what is actually open

The addendum above was written for a cloud box on a different endpoint. Where
the two disagree, THIS one is right about this campaign.

This is the **FIRST** drive of `tags_index`, and the first drive in this
campaign of any endpoint other than `posts_destroy` (`local_cc/`) and
`conversation_visibilities_destroy` (`local_cvd/` … `local_cvd6/`). There is no
prior record of this endpoint to read and none to write. The six prior drive
directories are completed records of OTHER endpoints: do not write any of them.

Everything stated below as "measured" was measured on this machine on
2026-10-07 by the coordinator, against this app tree and this engine revision,
and the command that produced it is named. Nothing here is inherited prose.

### 0. READ THIS FIRST: the endpoint has ONE branch and its interesting side is WALLED

`TagsController#index` is 17 lines
(`ruby_examples/dse-apps/apps/diaspora/app/controllers/tags_controller.rb:17-34`).
It has exactly **one** conditional, and the concolic runtime records exactly
one path condition for it:

    (Length(SYM_PARAM_q) > 1)        tags_controller.rb:18

The **false** side falls to `head :unprocessable_entity` and issues no SQL.

The **true** side is the whole endpoint — the tag query, the limit arithmetic,
the JSON render — and it **terminates immediately** on the next line:

    tags_controller.rb:19   params[:q].gsub!("#", "")
    -> NotImplementedError: SymbolicString#gsub! is not supported in the
       concolic runtime
       raising frame: src_new/runtimes/ruby_runtime/string.rb:391

That is not a bug and not a crash to hide. `gsub!` is in
`SymbolicString::UNSUPPORTED` (`src_new/runtimes/ruby_runtime/string.rb:359-387`),
in the group commented "Mutation / concat / format (would mutate or produce a
plain copy)", under a header that reads "This list is the complete set of
String methods that are NOT PC-tracked and MUST fail loudly." It is a DECLARED
NON-GOAL of the runtime, reached by application code on the only path that
matters.

**Four more declared non-goals stand behind it on the same path**, so lifting
`gsub!` alone would move the wall rather than remove it. Each is in an
`UNSUPPORTED` list or named in `/home/dev/project/CLAUDE.md`:

| line | expression | refused by |
|---|---|---|
| controller:19 | `params[:q].gsub!("#","")` | `SymbolicString#gsub!` — mutation |
| controller:20 | `params[:limit].to_i` | `SymbolicString#to_i` — numeric coercion |
| controller:21 | `params[:limit] - 1` | `SymbolicInt` arithmetic (CLAUDE.md: "arithmetic raises `NotImplementedError`") |
| model:12 | `name.downcase` inside `Tag.autocomplete` | `SymbolicString#downcase` — transformation |
| controller:70 | `"#" + tag.name`, `@tags << …`, `@tags.uniq!` | `SymbolicString#+` — concat; list mutation |

(`model:12` is `app/models/acts_as_taggable_on-tag.rb:12`.)

**What this means for your submission.** You are not expected to get past
this, and you must not try to get past it by making the symbolic value
concrete, by seeding `q` so the branch is skipped, or by touching `src_new/`
(denied) or the app (denied). **Report the wall.** An honest packet here
describes a corpus whose coverage is complete and whose *content* is almost
empty, and says why in `NOTES.md`. A packet that quietly presents the
`length <= 1` path as this endpoint's behaviour would be worthless.

### 1. Your box is a directory on this machine, and the paths are absolute

`host` backend: a box is a directory, not a container. Your `in/` and `repo/`
mounts are symlinks, nothing is isolated, and the box root is an absolute path
the worker protocol gave you. Use it. There is no `/work`.

You may write inside your box, inside
`/home/dev/project/reports/autolab/local_tags1/`, and in `/tmp`. Writes to
`src/`, `src_new/`, `reports/diaspora/`,
`reports/autolab/{entrypoints,targets,endpoints}/`, `ruby_examples/` (the app)
and `scripts/` are DENIED by the harness, and `in/config.json` and
`local_tags1/inputs/` are denied explicitly. Those denials are the boundary,
not an obstacle to route around: if you believe the endpoint cannot be explored
without crossing one, say so and stop.

**Memory.** This machine has an OOM history. Put anything that starts a JVM or
a long Python job under a scope with a cap, and clear the JVM options variable
that leaks in from the parent (a leaked value also breaks blockaid):

    unset JAVA_TOOL_OPTIONS
    XDG_RUNTIME_DIR=/run/user/1000 \
      systemd-run --user --scope -p MemoryMax=10G --quiet <command>

`XDG_RUNTIME_DIR` is already `/run/user/1000` in the environment this box was
launched from, and `systemd-run --user` succeeded here both with and without it
(measured). Pass it anyway: it costs nothing and it has been observed missing
in a child environment on an earlier drive, where `systemd-run --user` then
failed with "Failed to connect to bus".

### 2. The explorer, measured

`in/config.json` names `runtime.runner`. There is a launcher beside it that
already exports `JAVA_HOME`, `PATH`, `GEM_HOME` and `RAILS_ENV=concolic` and
runs the runner under `bundle exec jruby` from the app directory:

    /home/dev/project/reports/autolab/entrypoints/scaffold/tags_index/launch.sh

Measured through that launcher, twice, at `MAX_RUNS=24 TIME_BUDGET=300`: a
whole run is **28 s of wall clock, essentially all of it Rails boot** — the
exploration itself reported `elapsed 0.1s`. The September shakedown of this
endpoint recorded `run_seconds 167.3` on a loaded machine, so treat 28 s as the
floor and not a promise. It is cheap either way. Run it as often as you like, and expect CPU
contention: another drive is running concurrently on this machine.

    unset JAVA_TOOL_OPTIONS
    mkdir -p <box-root>/batch
    MAX_RUNS=24 TIME_BUDGET=300 DUMP_OUT=<box-root>/batch \
      XDG_RUNTIME_DIR=/run/user/1000 systemd-run --user --scope \
      -p MemoryMax=10G --quiet \
      /home/dev/project/reports/autolab/entrypoints/scaffold/tags_index/launch.sh \
      2>&1 | tail -30

**Always set `DUMP_OUT`.** With it unset the runner writes dumps next to its
own source, inside the SHARED scaffold directory that every other endpoint
reads. That directory is pinned and you are denied writes to it.

**`dump_*.json` must end up at the TOP LEVEL of `batch/`.** The dump-side
audits are configured with `{batch}` = that directory and `{batch}` is the only
substitution `run_audits` offers. On an earlier drive, dumps left in
`batch/dumps/` made `statement_note_lint` exit 1 with `no dump_*.json under
.../batch` — one blocking line that said nothing about the corpus. Explore into
a subdirectory if you like, then copy every dump you keep directly into
`batch/`, and put the same files in `out/packet/dumps/`.

Four environment variables the shared driver reads, and they are the whole of
your steering: `EXTRA_SEEDS_JSON` (a JSON **list of seed dicts**, each one a
worklist root), `SEEDS_ONLY` (drive exactly those roots and nothing else — and
it also switches off the duplicate-path filter), `LABEL_SUFFIX` (added to every
dump label, so a targeted batch is identifiable), `TRACE`.

**This endpoint has no target override**: the runner announces `no target
override for tags_index (tier=candidate) — running on core targets only.
Expect unmocked call sites; that is a finding, not a crash to hide.` Take it at
its word.

### 3. The baseline corpus is coverage-complete, and it is two runs

Measured by the coordinator at `MAX_RUNS=24 TIME_BUDGET=300`: the default
invocation drives **3 runs**, keeps **2 distinct paths**, and ends `worklist
empty : true` with `unflippable : 0 distinct PC shapes`. `stack_remaining` is
0. A bigger `MAX_RUNS` buys nothing; the September shakedown's
`worklist_exhausted: false` was only an artefact of its `MAX_RUNS=2`.

The engine's coverage layer, run over that corpus (`python -m concolic.check`,
this engine revision):

    coverage_complete true    tree_complete true    missing_branches 0
    truncated false           total_runs 2          solver_lost 0

So **you have no licence not to explore**: the tree is complete and the
worklist is exhausted. The corpus is complete in COVERAGE and nearly empty in
CONTENT, and §0 is why. Say both.

Two things the coordinator measured in that same pass that you should not be
surprised by, and neither is yours to fix:

* `Failed to eval var decl 'Length(SYM_PARAM_q) = Int('Length(SYM_PARAM_q)')'`
  — printed twice. The endpoint's only symbolic variable is a derived LENGTH
  variable whose NAME contains parentheses, and the declaration is built by
  `eval` of generated Python source, where `Length(SYM_PARAM_q) = …` is a
  syntax error. It was **not fatal here**: with one decision and both sides
  taken concretely, coverage resolves by path-signature matching and no solver
  query was lost (`solver_lost 0`, `tried_unknown 0`). Record it; do not try
  to repair it, and do not rename a variable to dodge it.
* `cardinality_consistency_audit` passes **VACUOUSLY** and says so itself
  ("Absence of the subject is not evidence about it; do not count this as a
  check that passed"). Quote it that way.

### 4. `assumptions.json` is very likely `[]`, and that is correct

The worklist is exhausted and the tree is complete, so there is nothing to
assume your way past. An empty declared list is the honest list here. If you do
declare something it must survive the validator; the pre-gate runs the same
validator and a refusal is a failed attempt. **Do not declare an assumption in
order to describe the `gsub!` wall** — the wall is not a coverage assumption,
it is a terminal the corpus already records, and `NOTES.md` is where it belongs.
**Do not drop, weaken or re-declare an assumption to make a gate row go away.**

### 5. `shim_tests.rb` — configured, and it is about the SHARED boundary

The shim gate is configured (`extract_cmd` + `test_cmd` in `in/config.json`)
and `extract_cmd` + `test_cmd` + `shim_tests` are all mandatory: omit
`shim_tests.rb` and the engine blocks with `shim gate: NOT CONFIGURED`
(measured — the coordinator reproduced exactly that line with an empty file,
plus `shim_tests.rb must define SHIM_TESTS`).

The extractor runs over the **shared** target library, not over anything
endpoint-specific:

    ruby src_new/runtimes/ruby_runtime/completion_checker/shim_extractor.rb \
      reports/autolab/targets/core.rb reports/autolab/targets/shared_shims.rb

Measured: it emits **22 keys**, the same 22 the `conversation_visibilities_destroy`
and `posts_destroy` packets were built against, because the boundary is shared
app-wide (Rule T). So a prior packet's `shim_tests.rb` is a legitimate starting
point — `local_cvd4/boxes/conversation_visibilities_destroy-batch-1-bb942577/out/packet/shim_tests.rb`
is 517 lines and its own header documents the carry-over and the keys
deliberately absent (PROTOCOL-by-runtime). **Re-run it against this box before
submission; the verdicts must be this run's, not inherited**, and say in
`NOTES.md` where the file came from.

### 6. `produced_with` is REQUIRED, and these are the three values

    runtime_revision   ee9f17bcddbc38285a0a2c2099831369b27b9f29   (src_new HEAD)
    app_revision       0760b6a22e113b74567330ff69ccc55a1d07022c   (the app's HEAD)
    app_tree_digest    916d393795a47b99d2128464ba268defb51524555bc26c659560575051501954

All three measured 2026-10-07. The digest is §5.2.1's PIN and the pre-gate
compares it; run `local_tags1/tools/app_tree_digest.py` yourself and confirm it
rather than copying this line. It covers `app/ lib/ config/ db/schema.rb
Gemfile Gemfile.lock` and nothing else — `targets/core.rb` changed on
2026-10-07 and is correctly outside it.

### 7. THE NOTE CHECK IS NOT YOURS, AND IT WILL HAVE SOMETHING TO SAY

The mock-note check left the generic engine's mandatory gate on 2026-10-05 and
is now `domains/ruby_rails_sql/checks.py::shape_check`, reached through
`Domain.check(policy, real)` by DESIGN_SWEEP §6.3's STATIC HALF and gated there
as `WorkResult.domain_blocking`. A third check, `statement_differential`, is
built as of 2026-10-07 (`_UNBUILT` is empty, measured), so
`check-not-implemented/statement_differential` no longer appears.

This endpoint **declares both** `fixtures` and `real_mode_plan`, so the
domain's conjunction is answerable here. They are COORDINATOR-OWNED GROUND
TRUTH and they are not in your box to author:

* `local_tags1/fixtures/tags_index/world.json` (`tags-world-1`)
* `local_tags1/plan/real_mode_plan.json` (`tags-real-1`, six scenarios)

**DO NOT produce a `concrete_run.json`.** `sweep/briefs/batch.md` forbids it
and it would be a fabricated ground truth. An agent that writes its own ground
truth has been handed the answer key.

Be aware of what that gate is going to find, because it bears on how you write
`NOTES.md`: the real endpoint issues one statement,
`SELECT tags.* FROM tags WHERE (name LIKE ?) ORDER BY name ASC LIMIT ?`, and
your corpus records **no note for it at all** — measured, `statement_note_lint`
reports "2 dumps, **0 clean notes**", the only two target calls in the corpus
being `ActionController::Rendering#_set_rendered_content_type` and
`ActionController::Head#head`, both declared shims and neither an access.
That is a true consequence of §0 and it is the finding. Do not paper over it,
and do not invent a note to fill the hole.

### 8. What an honest submission looks like here

* `dumps/` — the 2 distinct paths, at the top level of `batch/` as well.
* `assumptions.json` — almost certainly `[]`.
* `shim_tests.rb` — carried over, **re-run here**, provenance stated.
* `assumption_manifest.json` — `batch_dir` must be `in/packet/dumps`,
  RELATIVE to the box root, and **no `workdir` key** (the configured commands
  are all absolute; a `workdir` made an earlier drive's assumption gate index a
  directory that does not exist and report a read corpus it had never read).
* `NOTES.md` — the wall (§0), the five refused operations, the empty note set
  (§7), the vacuous audit and the `Length(...)` var-decl line (§3). This file
  is the deliverable that makes the drive worth anything.

### 9. `pgrep -f <pattern>` MATCHES YOUR OWN COMMAND LINE

Single provenance is a hard rule on this campaign. A previous drive was
contaminated when two runs shared a batch directory because a `pkill` pattern
did not match a relative command line. If you kill a stray explorer, match on
an absolute path, check what you matched before you signal it, and remember
that `pgrep -f` will happily match the shell you are typing in. **If you ever
suspect two runs overlapped, discard the corpus and re-run from clean rather
than reasoning about which dumps came from where.**
