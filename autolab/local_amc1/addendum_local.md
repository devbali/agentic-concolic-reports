---

## OPERATOR ADDENDUM — `aspect_memberships_create`, this box, and what is actually open

The addendum above was written for a cloud box on a different endpoint. Where
the two disagree, THIS one is right about this campaign.

This is the **FIRST** drive of `aspect_memberships_create`, and the first drive
in this campaign of any endpoint other than `posts_destroy` (`local_cc/`),
`conversation_visibilities_destroy` (`local_cvd/` … `local_cvd6/`) and
`tags_index` (`local_tags1/`). There is no prior drive record of this endpoint
to read and none to write. The eight prior drive directories are completed
records of OTHER endpoints: do not write any of them.

Everything stated below as "measured" was measured on this machine on
**2026-10-07** by the coordinator, against this app tree and this engine
revision, and the command that produced it is named. Nothing here is inherited
prose; where a predecessor drive's sentence would have been convenient, it was
re-measured instead, and three of those re-measurements came out the other way
(§0, §2, §7).

### 0. READ THIS FIRST: this endpoint does NOT hit a runtime wall, and the open question is COMBINATION COVERAGE

The two endpoints driven before this one both died at a declared non-goal of
the symbolic runtime — `SymbolicList#to_ary` on
`conversation_visibilities_destroy`, `SymbolicString#gsub!` on `tags_index` —
and both drives' launch logs printed *"no target override … running on core
targets only"*. **Neither is true here**, and that is the whole reason this
endpoint was chosen:

* `targets/registry.json` registers this endpoint `tier: gold` with
  `file: targets/endpoints/aspect_memberships_create.rb` and modules
  `AspectMembershipsTargets`, `AmDeviseUserNaming`. Measured: the launcher
  prints `[am_create] AspectMembershipsTargets installed` and
  `[am_create devise] AmDeviseUserNaming installed`, and no "no target
  override" line.
* `shakedown/manifest.jsonl` records `reach_best: 10` for it — against 0 for
  39 endpoints, 1 for 118 and 2 for 3. It is the only endpoint in the lab with
  reach past 2.
* The corpus has **real statement content**. Measured over a 403-dump corpus:
  **5331 clean notes, 19 distinct statement shapes**, including the DML —

```
  128  INSERT INTO "aspect_memberships" ("aspect_id","contact_id","created_at","updated_at") …
   12  INSERT INTO "contacts" ("user_id","person_id","created_at","updated_at","receiving") …
   76  UPDATE "notifications" SET "notifications"."unread" = false WHERE "notifications"."type" IN (…)
   64  UPDATE "contacts"  SET "updated_at" = …, "receiving" = true WHERE "contacts"."id" = ?
```

  (Compare `tags_index`, whose corpus had **0** clean notes. That drive's
  finding was an empty policy; yours will not be.)

So you have no wall to report and no excuse. **The thing that is open is
combination coverage**, and §3 is the measurement.

### 1. Your box is a directory on this machine, and the paths are absolute

`host` backend: a box is a directory, not a container. Your `in/` and `repo/`
mounts are symlinks, nothing is isolated, and the box root is an absolute path
the worker protocol gave you. Use it. There is no `/work`.

You may write inside your box, inside
`/home/dev/project/reports/autolab/local_amc1/`, and in `/tmp`. Writes to
`src/`, `src_new/`, `reports/diaspora/`,
`reports/autolab/{entrypoints,targets,endpoints}/`, `ruby_examples/` (the app)
and `scripts/` are DENIED by the harness, and `in/config.json` and
`local_amc1/inputs/` are denied explicitly. Those denials are the boundary,
not an obstacle to route around: if you believe the endpoint cannot be
explored without crossing one, say so and stop.

**`targets/endpoints/aspect_memberships_create.rb` is READ-ONLY and you should
READ IT.** It is 67 KB of curated, reasoned mocks — 10 `declare_target` sites,
23 declarations, 20 of them redeclaring a core target to give it a
statement-shaped note, and a header that names eleven defects (D1…D11) found
when it was written. Its §2 is why this endpoint's writes render as real
INSERT/UPDATE instead of as `"<Class>#save args={}"`. It is shared under Rule T
and a change to it would restart every endpoint, so if you find a defect in it,
**escalate** (`ctl/ask/<name>.json`, class `shared`) — do not patch it, and do
not work around it silently.

**Memory.** This machine has an OOM history. Put anything that starts a JVM or
a long Python job under a scope with a cap, and clear the JVM options variable
that leaks in from the parent (a leaked value also breaks blockaid):

    unset JAVA_TOOL_OPTIONS
    XDG_RUNTIME_DIR=/run/user/1000 \
      systemd-run --user --scope -p MemoryMax=12G --quiet <command>

`XDG_RUNTIME_DIR` is already `/run/user/1000` in the environment this box was
launched from. Pass it anyway: it costs nothing and it has been observed
missing in a child environment on an earlier drive, where `systemd-run --user`
then failed with "Failed to connect to bus".

### 2. The explorer, measured

`in/config.json` names `runtime.runner`. There is a launcher beside it that
already exports `JAVA_HOME`, `PATH`, `GEM_HOME` and `RAILS_ENV=concolic` and
runs the runner under `bundle exec jruby` from the app directory:

    /home/dev/project/reports/autolab/entrypoints/scaffold/aspect_memberships_create/launch.sh

Measured through that launcher, three times, on 2026-10-07:

| `MAX_RUNS` | runs | distinct paths | exploration elapsed | `worklist empty` | stack remaining |
|---|---|---|---|---|---|
| 24   | 24   | 23  | 3.2 s  | **false** | 237  |
| 400  | 400  | 181 | 21.9 s | **false** | 1706 |
| 1500 | 1500 | 403 | 56.8 s | **false** | still non-empty |

`run_errors: {}` on all three. Terminals at 1500 runs:
`{"I18n::InvalidLocale" => 112, "ActiveRecord::AssociationTypeMismatch" => 151}`
— both real app outcomes, neither a framework wall. `unflippable: 0 distinct PC
shapes` on all three, so the flip matchers read every PC this corpus has.

Wall clock is dominated by Rails boot (~2–3 min); the exploration itself is
seconds. **The September shakedown's `worklist_exhausted: false` was NOT an
artefact of its small `MAX_RUNS`.** The worklist *grows* with runs — every flip
of a 16-PC path queues more seeds than it consumes — so there is no `MAX_RUNS`
at which it drains, and `worklist_exhausted` is not a target you can reach here.
Do not report "not exhausted" as a budget problem; it is a property of the path
space. `in/config.json` sets `MAX_RUNS=1500 TIME_BUDGET=3000` for that reason,
and its `_note_run_limits_raised` records the measurement.

    unset JAVA_TOOL_OPTIONS
    mkdir -p <box-root>/batch
    MAX_RUNS=1500 TIME_BUDGET=3000 DUMP_OUT=<box-root>/batch \
      XDG_RUNTIME_DIR=/run/user/1000 systemd-run --user --scope \
      -p MemoryMax=12G --quiet \
      /home/dev/project/reports/autolab/entrypoints/scaffold/aspect_memberships_create/launch.sh \
      2>&1 | tail -40

**Always set `DUMP_OUT`.** With it unset the runner writes dumps next to its
own source, inside the SHARED scaffold directory that every other endpoint
reads. That directory is pinned and you are denied writes to it. (Three dumps
from the September shakedown already sit there; they are not yours and are not
your corpus.)

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
dump label, so a targeted batch is identifiable), `TRACE`. The authoritative
batch used `EXTRA_SEEDS_JSON` + `SEEDS_ONLY` to drive a write path on purpose
(`reports/diaspora/results4/aspect_memberships_create/write_path_seeds.json`,
readable); you will not need that, because the write is already in the default
set — measured: the aspect_memberships INSERT appears in 76 of 403 default-run
dumps.

### 3. THE ACTUAL JOB: what more runs buy, and what they do not

The engine's coverage layer, run by the coordinator over three real corpora
with this config's own `max_cliques=200 max_missing_per_clique=50` (the only two
`limits` keys `concolic/check.py::LIMIT_TO_COVERAGE_KWARG` enforces):

| corpus | `tree_complete` | `coverage_complete` | `missing_branches` | `truncated` | `solver_lost` |
|---|---|---|---|---|---|
| 23 runs  | **false** | false | 76  | true | 0 |
| 181 runs | **TRUE**  | false | 100 | true | 0 |
| 403 runs | **TRUE**  | false | 88  | true | 0 |

Read that table carefully, because it is the shape of your task.

* **Tree completeness is cheap** — somewhere between 24 and 181 runs the last
  unwalked prefix gets walked and `tree_missing` goes to `[]`. At 23 runs there
  were four, all of them the same two decisions on differently-named variables.
* **Combination coverage is not bought by runs at all.** `missing_branches`
  does not fall from 181 to 403 runs; it is `truncated: true` at both, i.e. the
  enumeration hit the cap, so the number is a floor and not a measure of
  progress.

The reason is in the vocabulary. Measured over the 403-dump corpus: **20
distinct PC expressions**, and they are not 20 independent facts. Four of them
are the SAME `users.language` compare reached under four different variable
names, because the name is prefix-relative:

```
SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_language == 'pl' / 'xx'
SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_user_language       == 'pl' / 'xx'
SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_owner_language == 'pl' / 'xx'
assoc_person_owner_language                                           == 'pl' / 'xx'
```

and the same doubling happens to `closed_account`
(`assoc_person_closed_account` vs
`SYM_RESULT_…find_by_1_person_closed_account`) and to the self-contact identity
compare. Combination coverage over a universe that counts one column's compare
four times demands products that do not exist in the program.

**So `assumptions.json` is the deliverable here, and it is not `[]`.** That is
the single biggest difference from every prior drive in this campaign, all of
which honestly declared nothing. What you are looking for is independence (and
where the kinds support it, alias) declarations that say, with evidence from
the corpus, which of those decisions cannot interact — for example that the
`language` arm is decided by `set_locale` before the action body runs and
therefore cannot co-vary with anything inside `share_with`. The declared gate
(`assumption_cmd` in `in/config.json`) then has to AGREE, on runs that record
both members of each pair. A declaration the gate cannot test is an
**exploration target**, not a thing to argue away:

* **Do not drop, weaken or re-declare an assumption to make a gate row go
  away.** A withdrawn assumption restores the demand it was pruning, which is a
  bigger corpus obligation, not a smaller one.
* A gate row whose verdict is NOT-TESTABLE / NOT-COMPARABLE / ERROR / UNKNOWN
  settled NOTHING and is read as a NO. Where its `detail` says no run records
  both members of a pair, **produce a run that records both** (`EXTRA_SEEDS_JSON`
  + `SEEDS_ONLY`) and the gate will have a base to replay.
* If you conclude the demand cannot be honestly discharged, **say that**, and
  say precisely which demands are left. An honest `coverage_complete: false`
  with a named cause is the result; a `true` bought by an assumption you cannot
  evidence is worthless.

### 4. The six audits are green on a real corpus — including one that is VACUOUS

Measured by the coordinator over the 403-dump corpus, with the exact
`audit_cmds` this config configures:

```
statement_note_lint             403 dumps, 5331 clean notes   RESULT: no red-level findings
                                JUNK (warn): 1794 events / 4 distinct —
                                  User#blocks, ActionController::Rendering#_set_rendered_content_type,
                                  ActionController::Metal#status=, Diaspora::Federation::Dispatcher.defer_dispatch
noteless_call_audit             7125 target-call events; every note-less call is a DECLARED SHIM
exception_note_audit            0 notes captured an exception
empty_relation_emission_audit   0 empty-list states
cardinality_consistency_audit   pass but VACUOUS
identity_symbolicity_audit      pass — every principal bind is symbolic
```

Two things to carry into `NOTES.md` rather than rediscover:

* The four JUNK notes are each a documented wall or a non-access, and three of
  them are declared SHIMs whose real bodies issue no SQL. **Verify each against
  the target layer yourself and say so**; do not quote this list as if checking
  it were done.
* `cardinality_consistency_audit` says of itself: *"this corpus contains no bulk
  loader reading a list's own rows, so the rule was never applied. Absence of
  the subject is not evidence about it; do not count this as a check that
  passed."* **Quote it that way.** Six green audits are five checks and one
  vacuity.

### 5. `shim_tests.rb` — configured, and it is about the SHARED boundary

The shim gate is configured (`extract_cmd` + `test_cmd` in `in/config.json`)
and `extract_cmd` + `test_cmd` + `shim_tests` are all mandatory: omit
`shim_tests.rb` and the engine blocks with `shim gate: NOT CONFIGURED`.

The extractor runs over the **shared** target library, not over this
endpoint's override:

    ruby src_new/runtimes/ruby_runtime/completion_checker/shim_extractor.rb \
      reports/autolab/targets/core.rb reports/autolab/targets/shared_shims.rb

Measured 2026-10-07: it emits **22 entries, 22 distinct keys** (the first five
being `obj.read_attribute`, `obj._read_attribute`, `obj.concolic_attrs`,
`obj.concolic_note`, `obj.attributes`) — the same 22 the
`conversation_visibilities_destroy`, `posts_destroy` and `tags_index` packets
were built against, because the boundary is shared app-wide (Rule T) and the
argv does not name this endpoint's layer. So a prior packet's `shim_tests.rb`
is a legitimate starting point; both of these exist and are readable:

    local_tags1/boxes/tags_index-batch-1-acf20787/out/packet/shim_tests.rb          (30077 bytes)
    local_cvd4/boxes/conversation_visibilities_destroy-batch-1-bb942577/out/packet/shim_tests.rb (30005 bytes)

**Re-run it against this box before submission; the verdicts must be this run's,
not inherited**, and say in `NOTES.md` where the file came from.

### 6. `produced_with` is REQUIRED, and these are the three values

    runtime_revision   7951750cecc9334e794fda2312d85de541034db7   (src_new HEAD -- CORRECTED, see below)
    app_revision       0760b6a22e113b74567330ff69ccc55a1d07022c   (the app's HEAD)
    app_tree_digest    916d393795a47b99d2128464ba268defb51524555bc26c659560575051501954

**CORRECTION, 2026-10-08 00:38, after this section was written and after the
batch round had already consumed it.** This line first read
`runtime_revision ee9f17bcddbc38285a0a2c2099831369b27b9f29`, which is what
`git rev-parse HEAD` answered in `src_new/` when the addendum was written --
and which did NOT identify the code this drive runs. At 2026-10-08 00:36:41,
23 minutes into the drive, a commit landed in `src_new/`
(`7951750cecc9334e794fda2312d85de541034db7`, "A gate that cannot pass on
nothing, and the first real-mode comparison") publishing 6,471 insertions
across 49 files that had been sitting in the working tree UNCOMMITTED --
including the whole real-mode producer (`real_mode/real_mode_probe.rb`,
`real_mode/fixture_env.rb`), `domains/ruby_rails_sql/checks.py` (+541),
`domains/static_check.py`, `domains/ruby_rails_sql/app_config.py` and
`sweep/workers/concrete.py`'s mounts.

**No byte this drive executes changed.** Every chain-critical file's mtime is
2026-10-07T18:40:02 or earlier, i.e. before this drive started at 00:11, and
`git status` is clean, so the commit published code already on disk and
unchanged. Single provenance holds at the level that matters: the executed
bytes. What moved is only the identifier.

**The defect this exposes.** `runtime_revision` taken as `git rev-parse HEAD`
does not identify the code that runs when the tree carries uncommitted work,
and this tree carried ~6.5k lines of it. `ee9f17bc` does not contain the
real-mode stage AT ALL, so every drive that recorded it was labelling the
real-mode producer with a revision that does not include it -- `local_tags1`
included (`local_tags1/README.md` records `runtime_revision
ee9f17bcddbc...` and that drive ran `--stage realmode`). Nothing catches this:
the pre-gate verifies only `produced_with.app_tree_digest`
(`sweep/coordinator/pregate.py:691-716`) and `runtime_revision` appears in no
non-test verification anywhere in `src_new/`. So the field the campaign
documents most carefully is the one nothing checks.

All three values above were measured with `git rev-parse HEAD` in each tree and
`local_amc1/tools/app_tree_digest.py` for the digest. The digest is §5.2.1's
PIN and the pre-gate compares it; run the script yourself and confirm it rather
than copying this line. It covers `app/ lib/ config/ db/schema.rb Gemfile
Gemfile.lock` and nothing else — `targets/core.rb` was last modified
2026-10-07 and is correctly outside it.

### 7. THE DOMAIN GATE IS NOT YOURS, AND BOTH ITS INPUTS EXIST

The mock-note check left the generic engine's mandatory gate on 2026-10-05 and
is now `domains/ruby_rails_sql/checks.py::shape_check`, reached through
`Domain.check(policy, real)` by DESIGN_SWEEP §6.3's STATIC HALF and gated there
as `WorkResult.domain_blocking`. `statement_differential` is built as of
2026-10-07 (`_UNBUILT` is `()`, measured), so
`check-not-implemented/statement_differential` does not appear.

This endpoint **declares both** `fixtures` and `real_mode_plan`, so the
domain's conjunction is answerable. They are COORDINATOR-OWNED GROUND TRUTH and
they are not in your box to author:

* `local_amc1/fixtures/aspect_memberships_create/world.json` — `amc-world-1`,
  28 rows: five users carrying the three-arm `language` domain (`en`/`pl`/`xx`),
  seven people (one owned by the principal for the self-contact arm, one closed
  account, one blocked, one already contacted), seven profiles, five aspects,
  one receiving contact, one existing membership, one block and one unread
  `Notifications::StartedSharing`.
* `local_amc1/plan/real_mode_plan.json` — `amc-real-1`, **nine** scenarios,
  with a `principal` block (this endpoint is `signed_in: true`), an EMPTY
  `frame_aliases`, and `replay_callbacks: ["set_locale",
  "set_grammatical_gender"]` on every scenario — the last of which is the one
  structural thing neither predecessor plan needed and which was re-measured
  rather than inherited (`autolab_dse.rb:1102` replays exactly those two for a
  signed-in endpoint, so a plan that did not replay them would be recording a
  different execution from the one your corpus describes).

  **CORRECTION, 2026-10-08, after this section was written.** The plan first
  carried a cvd6-shaped `frame_aliases` entry mapping
  `ActiveRecord::FinderMethods#first` to `devise_user_first` inside
  `OrmAdapter::ActiveRecord#get`. The coordinator then dry-ran the plan and
  measured that `FinderMethods#first` **never appears as a real frame at all**:
  the five real frames the whole nine-scenario run produces are `find_by_sql`,
  `exists?`, `save`, `save!` and `update_all`. The entry was a no-op resting on
  a false premise and has been removed, with the measurement recorded in the
  plan's own `_frame_aliases_empty_MEASURED` key. An alias from `find_by_sql`
  **would** have matched and was deliberately not written — see
  `_why_no_alias_was_written_instead`: five of the ten target functions the IR
  declares never appear as a real frame, for the same structural reason (a
  mocked target's body never runs, so the corpus names the OUTER target while a
  real run names the innermost one), and repairing only the devise instance
  would be the coordinator choosing which cases of a five-case asymmetry the
  gate gets to report. **Expect `shape_check` to have something to say about
  frame attribution, and do not treat it as your defect.**

**DO NOT produce a `concrete_run.json`.** `sweep/briefs/batch.md` forbids it
and it would be a fabricated ground truth. An agent that writes its own ground
truth has been handed the answer key.

What that gate is likely to say, so it does not surprise you. This paragraph
first guessed that the `profiles` read would be the unrestricted one, because
its statement is `SELECT "profiles".* FROM "profiles" WHERE
"profiles"."person_id" = ?` — a foreign-key predicate with no principal column.
**That guess was wrong, and the measurement is better news for `profiles` and
worse news elsewhere.** Rendering the coordinator's own probe IR (403 scratch
dumps) through `domains/ruby_rails_sql/render.py::render_views` with this
campaign's app config produces 21 views, and the `profiles` view comes out
correctly restricted:
`SELECT profiles.* FROM profiles, people, users WHERE profiles.person_id =
people.id AND users.id = _MY_UID AND people.owner_id = users.id AND
users.language = 'pl'`. Three OTHER views carry no principal restriction at
all, the starkest being `SELECT people.* FROM people` with no WHERE clause
whatsoever. If your corpus reproduces those, say so in `NOTES.md`; it is a true
statement about the corpus and a real disclosure question, and it is **not**
something to make go away by changing a note.

### 8. What an honest submission looks like here

* `dumps/` — the distinct paths you keep, at the top level of `batch/` as well.
  More than `tags_index`'s two; §2's table says what a given `MAX_RUNS` yields.
* `assumptions.json` — **the deliverable** (§3). Each declaration evidenced
  from the corpus and testable by the configured gate.
* `shim_tests.rb` — carried over, **re-run here**, provenance stated (§5).
* `assumption_manifest.json` — `batch_dir` must be `in/packet/dumps`,
  RELATIVE to the box root, and **no `workdir` key** (the configured commands
  are all absolute; a `workdir` made an earlier drive's assumption gate index a
  directory that does not exist and then report a read corpus it had never
  read).
* `NOTES.md` — the combination-coverage demand and what you did about it (§3),
  the vacuous audit quoted as vacuous (§4), the four JUNK notes checked
  individually (§4), the two real terminals and why each is an app outcome
  rather than a wall (§2), and anything you found in the target layer that you
  escalated. This file is the deliverable that makes the drive worth anything.

### 9. `pgrep -f <pattern>` MATCHES YOUR OWN COMMAND LINE

Single provenance is a hard rule on this campaign. A previous drive was
contaminated when two runs shared a batch directory because a `pkill` pattern
did not match a relative command line. If you kill a stray explorer, match on
an absolute path, check what you matched before you signal it, and remember
that `pgrep -f` will happily match the shell you are typing in. **If you ever
suspect two runs overlapped, discard the corpus and re-run from clean rather
than reasoning about which dumps came from where.** Another agent may be
running on this machine concurrently: expect CPU contention and do not read
slowness as a hang.
