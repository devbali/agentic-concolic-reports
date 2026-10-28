---

## OPERATOR ADDENDUM — `aspect_memberships_create`, drive 10, and what is actually open

The addendum above was written for a cloud box on a different endpoint. Where
the two disagree, THIS one is right about this campaign.

This is the **THIRD** drive of `aspect_memberships_create`. Drive 8
(`local_amc1`, 2026-10-07/08) ran all six stages and did not close. Drive 9
(`local_amc2`, 2026-10-08) got the ENGINE half to complete and still did not
close it — its domain half blocked. Both are completed records: **you may not
write them**, nor any other `local_*` directory, and you may read all of them.
§0 says what has changed in the engine since drive 9 ran, and that is the
whole reason this drive exists.

**WHICH NUMBERS HERE ARE THIS DRIVE'S, AND WHICH ARE INHERITED.** This file is
drive 9's addendum with §0, §7 and §10 rewritten. Re-measured for this drive:
the engine changes in §0, the engine digest in §7, and the expected domain-gate
items (`drive.py`'s header has them). **Everything else is drive 9's
measurement, taken on 2026-10-08 against this same app tree, and is inherited
prose.** The app tree and the ground truth have not moved since, so those
numbers still describe the world your corpus will be produced in — but they
were taken by a different engine, and where one of them is about what the
ENGINE said rather than about what the APP contains, treat it as a starting
point and re-derive it. Your corpus is your own and every verdict must be
this run's.

### 0. READ THIS FIRST: a non-arriving probe no longer PASSES

Drive 9's ENGINE half came back complete: `complete: true`, `blocking: []`,
`missing_branches: 0`, `assumptions_used: 6`, all six assumptions gate-PASSED
by replay. Those six were `UntrackedPathAssumption`s on the non-principal
`users.language` compares — and **the rule that decided them has changed.**

A gate probe is a run launched with one decision flipped. Drive 9's gate
answered **PASS** when such a probe never reached the expression at all: it
checked arrival before it consulted the difference it had already computed, so
"the flipped run went somewhere else entirely" and "the flipped run touched
the same things" produced the same word. It also credited that non-arrival as
one of the three witnesses the floor wants, so a floor could be satisfied
entirely by runs that never reached the branch.

**Now a probe that does not arrive answers `NOT-TESTABLE` / `NOT-REALISED`,
and that reason settles nothing and credits no witness.** Concretely:

* **A declaration the gate PASSED for drive 9 may not pass here.** If the flip of a
  `users.language` compare does not arrive at that compare, the row reads
  NOT-TESTABLE, the coverage demand does not get that assumption, and
  `missing_branches` can rise off zero. That is the engine being honest, not a
  regression, and **you are not expected to make it go away.**
* **You may not route around it** by declaring something weaker, by choosing
  bases that avoid the question, or by reading a NOT-TESTABLE row as a
  near-miss. A row that settled nothing is a NO.
* **What you CAN do is give the gate a run where the flip actually arrives.**
  A declaration is testable on runs that record BOTH members of its pair. If
  none of your bases produce an arriving flip, say so, with the rows that show
  it, and let the endpoint stay open.

Drive 9's six records are at

    local_amc2/boxes/aspect_memberships_create-batch-1-*/out/packet/assumptions.json

and are readable. They are a legitimate starting point and emphatically **not**
a free pass: they were written against drive 9's corpus under the old rule,
your corpus is your own, and every verdict must be **this run's**.

Three other engine changes landed with it. Only the first could touch your work:

* `AliasAssumption` in `mode: "loop"` keys members on a variant family
  (`<VERB> OVER <sorted relation set>`); a member set spanning more than one
  family FAILS instead of merging. No alias is declared on this endpoint.
* `principal_restriction_check` is a new DOMAIN check and is **not yours** —
  §8 says why the domain gate is not your work. It is expected to block.
* The pre-gate compares a measured content digest of the engine trees, so §7's
  `runtime_digest` is verified three ways and a tree that moves under you is a
  refusal.

The soundness note in `_coverage_assumptions`' own docstring governs what a
pass means: `coverage_complete` means *"complete given these declarations"*.
`concolic/checks/run.py` puts `assumption FAIL (...)` and `assumption NOT
SETTLED (...)` into `blocking`, and `complete` is `coverage_complete AND
completion.complete`, so a declaration the gate refutes or cannot settle
**blocks the close**. You cannot buy completeness with a claim the gate will
not confirm. Four rules follow and none of them is new,
only newly load-bearing:

* **Every declaration must be evidenced from the corpus** and testable by the
  configured gate on runs that record BOTH members of its pair.
* **A gate row whose verdict is NOT-TESTABLE / NOT-COMPARABLE / ERROR /
  UNKNOWN settled NOTHING** and is read as a NO. Where its `detail` says no run
  records both members, that row is an **exploration target**: produce a run
  that records both (`EXTRA_SEEDS_JSON` + `SEEDS_ONLY`) and the gate will have
  a base to replay.
* **Do not drop, weaken or re-declare an assumption to make a row disappear.**
  A withdrawn assumption restores the demand it was pruning, which is a bigger
  corpus obligation, not a smaller one.
* **If you conclude the demand cannot be honestly discharged, say that**, and
  say precisely which demands are left. An honest `coverage_complete: false`
  with a named cause is a result. A `true` bought by an assumption you cannot
  evidence is worthless, and it is now reachable, which is exactly why this
  paragraph exists.

Four other defects drive 8 found landed with that wire, and three of them
change what you will see:

* **The instrument no longer causes a read it then records.**
  `call_interceptor.rb`'s body-skip classifier asked `concrete_result == true`;
  an AR `CollectionProxy` defines `==` as `load_target == other`, so the type
  probe LOADED the association. It is `.equal?` now
  (`call_interceptor.rb:705,731-732`). **Measured, 403-dump probe corpora
  either side of the fix:** `SELECT "blocks".* FROM "blocks" WHERE
  "blocks"."user_id" = ?` went from 19 distinct statement shapes to 18 — the
  whole-collection `blocks` read is **gone**, clean notes 5331 -> 4599 (the
  difference is exactly those 732 notes), and the narrow real `exists?`
  (`SELECT 1 AS one FROM "blocks" WHERE user_id = ? AND person_id = ? LIMIT 1`)
  is untouched at 1464 notes / 400 dumps. `User#blocks` is still 732 JUNK
  events in `statement_note_lint` and still a note-less DECLARED SHIM in
  `noteless_call_audit` — which is what a shim that issues no SQL is supposed
  to look like. **If `SELECT "blocks".*` is in your corpus, something did not
  take: say so loudly.**
* **`_shape_of` reads DML now.** It used to fall through to a regex that knows
  only FROM/JOIN, so an INSERT came out as its own column list and an UPDATE as
  `frozenset()`. The one `UPDATE "notifications"` drive 8's recording issued
  was therefore reported by nothing at all. Both normalizers read the statement
  as of 2026-10-08.
* **The assumption gate no longer writes into your packet.** `run_probe`'s
  seed file used to be created in `batch_dir`, which on a §6.3 check box is a
  symlink to YOUR `out/packet` — drive 8's packet went 422 files -> 423 and its
  digest changed mid-check. It is written under `workdir` now, in a
  `try/finally` (`concolic/gate/replay.py:238`). This config declares no
  `workdir` key (deliberately — see `in/config.json`'s `_note_no_workdir`), so
  it lands in the system temp directory, which is also not your packet.
* **Your box ends when you submit.** `REASON_SUBMITTED`
  (`sweep/agentd/main.py:90,525`) stops an agent-bearing worker as soon as every
  artifact it owes is verified. Drive 8 burned `wall_s=10800` after submitting
  fifteen minutes in. This applies to the AGENT path only — the deterministic
  check worker still runs to its own exit (`sweep/workers/base.py:274-287`
  explains why, and it is measured, not stylistic). Practical consequence:
  **submit when you are done, not when the clock runs out, and do not treat the
  wall clock as a budget you are expected to spend.**

### 1. This endpoint does NOT hit a runtime wall, and the open question is COMBINATION COVERAGE

The two endpoints driven before drive 8 both died at a declared non-goal of the
symbolic runtime — `SymbolicList#to_ary` on
`conversation_visibilities_destroy`, `SymbolicString#gsub!` on `tags_index` —
and both drives' launch logs printed *"no target override … running on core
targets only"*. **Neither is true here:**

* `targets/registry.json` registers this endpoint `tier: gold` with
  `file: targets/endpoints/aspect_memberships_create.rb` and modules
  `AspectMembershipsTargets`, `AmDeviseUserNaming`. The launcher prints
  `[am_create] AspectMembershipsTargets installed` and
  `[am_create devise] AmDeviseUserNaming installed`, and no "no target
  override" line.
* `shakedown/manifest.jsonl` records `reach_best: 10` for it — against 0 for 39
  endpoints, 1 for 118 and 2 for 3. It is the only endpoint in the lab with
  reach past 2.
* **The corpus has real statement content.** Re-measured 2026-10-08 over this
  coordinator's own 403-dump probe (18 distinct shapes, 4599 clean notes),
  including all four DML shapes:

```
  256 notes /  64 dumps  INSERT INTO "aspect_memberships" ("aspect_id","contact_id","created_at","updated_at") …
  152 notes /  76 dumps  UPDATE "notifications" SET "notifications"."unread" = false WHERE "notifications"."type" IN (…)
  128 notes /  64 dumps  UPDATE "contacts"  SET "updated_at" = …, "receiving" = true WHERE "contacts"."id" = ?
   24 notes /  12 dumps  INSERT INTO "contacts" ("user_id","person_id","created_at","updated_at","receiving") …
```

  (Compare `tags_index`, whose corpus had **0** clean notes. That drive's
  finding was an empty policy; yours will not be.)

So you have no wall to report and no excuse.

### 2. Your box is a directory on this machine, and the paths are absolute

`host` backend: a box is a directory, not a container. Your `in/` and `repo/`
mounts are symlinks, nothing is isolated, and the box root is an absolute path
the worker protocol gave you. Use it. There is no `/work`.

You may write inside your box, inside
`/home/dev/project/reports/autolab/local_amc3/`, and in `/tmp`. Writes to
`src/`, `src_new/`, `reports/diaspora/`,
`reports/autolab/{entrypoints,targets,endpoints}/`, `ruby_examples/` (the app)
and `scripts/` are DENIED by the harness, and `in/config.json` and
`local_amc3/inputs/` are denied explicitly. **Every other `local_*` directory
is a completed drive's record and is outside your writable roots — including
`local_amc1` and `local_amc2`, this endpoint's own first two drives.** Those
denials are the boundary, not an obstacle to route around: if you believe the endpoint cannot
be explored without crossing one, say so and stop.

**`targets/endpoints/aspect_memberships_create.rb` is READ-ONLY and you should
READ IT.** It is 67,161 bytes of curated, reasoned mocks; `targets/registry.json`
records 10 `declare_target` sites, 23 declarations, 20 of them redeclaring a
core target to give it a statement-shaped note, 3 new targets, `tier: gold`,
and 90 declared maximal / 89 observed in the app (the one difference is the
pinned dormant `ActionController::Metal#head`). Its §2 is why this endpoint's
writes render as real INSERT/UPDATE instead of as `"<Class>#save args={}"`.

**One correction to drive 8's addendum, measured 2026-10-08.** It said this
file's header "names eleven defects (D1…D11) found when it was written". It
does not: the only defect labels in the whole file are **D4–D8**, and the
header points at `./REPORT.md` for the rest. D1…D11 are in
`reports/diaspora/results4/aspect_memberships_create/REPORT.md` — the
authoritative batch this layer was lifted from (`registry.json`'s `source`),
which is readable and which you may not write. Read the defect list there and
the kind discipline here. It is shared under Rule T
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

### 3. The explorer, re-measured on THIS engine revision

`in/config.json` names `runtime.runner`. There is a launcher beside it that
already exports `JAVA_HOME`, `PATH`, `GEM_HOME` and `RAILS_ENV=concolic` and
runs the runner under `bundle exec jruby` from the app directory:

    /home/dev/project/reports/autolab/entrypoints/scaffold/aspect_memberships_create/launch.sh

Measured through that launcher on 2026-10-08, at `MAX_RUNS=1500
TIME_BUDGET=3000` (this config's values), with the fixed interceptor:

```
  runs executed  : 1500        distinct paths : 403
  worklist empty : false       stack remaining: 2725
  elapsed        : 51.6s       run errors     : {}
  terminals      : {"I18n::InvalidLocale" => 112,
                    "ActiveRecord::AssociationTypeMismatch" => 151}
  unflippable    : 0 distinct PC shapes
```

Both terminals are real app outcomes, not framework walls. `unflippable: 0`
means the flip matchers read every PC this corpus has. **Every one of those
numbers is identical to drive 8's pre-fix measurement** (1500 / 403 / false /
{} / 112 / 151 / 0) — the interceptor fix removed a recorded READ, not a path.

Wall clock is dominated by Rails boot (~2–3 min); the exploration itself is
seconds. **`worklist_exhausted: false` is NOT a budget problem.** The worklist
*grows* with runs — every flip of a 16-PC path queues more seeds than it
consumes — so there is no `MAX_RUNS` at which it drains. Drive 8's coordinator
measured 24 runs -> stack 237, 400 -> 1706, 1500 -> 2725+. Do not report "not
exhausted" as something more runs would fix; it is a property of the path space.

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
dump label, so a targeted batch is identifiable), `TRACE`. You will not need
seeds to reach the write: measured, the `aspect_memberships` INSERT appears in
64 of 403 default-run dumps and the `contacts` UPDATE in another 64.

### 4. THE ACTUAL JOB: what more runs buy, and what they do not

The engine's coverage layer, over real corpora at this config's own
`max_cliques=200 max_missing_per_clique=50` — the two `limits` keys this config
sets that `concolic/check.py::LIMIT_TO_COVERAGE_KWARG` maps (the map has a
third, `solver_timeout_ms`, which this config does not set; `max_runs`,
`max_probe_replays`, `max_solver_queries` and `solver_rlimit` are reported
UNENFORCED):

| corpus | declared | `tree_complete` | `coverage_complete` | `missing_branches` | `truncated` |
|---|---|---|---|---|---|
| this coordinator's 403-run probe, 2026-10-08 | — | **TRUE** | false | 88 | true |
| drive 8's 417-dump packet | — | TRUE | false | 82 | true |
| **drive 8's 417-dump packet + its 6 records** | **6** | TRUE | **TRUE** | **0** | **false** |

Read that third row carefully, because it is the shape of your task.

* **Tree completeness is cheap** — somewhere between 24 and 181 runs the last
  unwalked prefix gets walked and `tree_missing` goes to `[]`. Both corpora
  above are already there.
* **Combination coverage is not bought by runs at all.** `missing_branches` did
  not fall from 181 to 403 runs on drive 8's probes, and it is `truncated: true`
  without declarations, i.e. the enumeration hit the cap, so the number is a
  floor and not a measure of progress.
* **It is bought by declarations, and now they actually arrive.**

The reason is in the vocabulary. Measured over a 403-dump corpus: **20 distinct
PC expressions**, and they are not 20 independent facts. Four of them are the
SAME `users.language` compare reached under four different variable names,
because the name is prefix-relative:

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

**So `assumptions.json` is the deliverable here, and it is not `[]`.** Drive 8
wrote six records, evidenced them with a differential (264/264/54 run pairs
agreeing on everything but the language arm; **0** trace differences), and
deliberately left the PRINCIPAL's language decision UNDECLARED because flipping
that one changes the trace in 169 of 169 pairs. All six passed the gate. That
file is at

    local_amc1/boxes/aspect_memberships_create-batch-1-de5bd305/out/packet/assumptions.json
    local_amc2/boxes/aspect_memberships_create-batch-1-dfb2bc19/out/packet/assumptions.json

and both are readable — the second is drive 9's, which closed. They are a
legitimate starting point and **not** a free pass: each was written against its
own drive's corpus, your corpus is your own, and the evidence and the gate
verdicts must be **this run's**. Both drives' PASSes were reached under the
arrival rule §0 describes as changed, so a row copied from either is a
hypothesis here and not a result. Each drive's `NOTES.md` beside it says how
its differential was built. The nine registered
kinds, measured: `AliasAssumption`, `DecisionAliasAssumption`,
`IndependenceAssumption`, `UntrackedPathAssumption`,
`OneSideUntrackedPathAssumption`, `SymbolicConstraintAssumption`,
`ForeclosureAssumption`, `ConjunctionForeclosureAssumption`,
`SubconjunctionForeclosureAssumption`.

### 5. The six audits are green on a real corpus — including one that is VACUOUS

Re-measured by this coordinator 2026-10-08 over the 403-dump probe, with the
exact `audit_cmds` this config configures — all six exit 0:

```
statement_note_lint             403 dumps, 4599 clean notes   RESULT: no red-level findings
                                0 NO-WHERE, 0 STAR-PLUCK, 0 STAR-AGGREGATE
                                JUNK (warn): 1794 events / 4 distinct —
                                  User#blocks 732, ActionController::Rendering#_set_rendered_content_type 726,
                                  ActionController::Metal#status= 288, Diaspora::Federation::Dispatcher.defer_dispatch 48
noteless_call_audit             6393 target-call events; all 1794 note-less calls are those same 4 DECLARED SHIMS
exception_note_audit            0 notes captured an exception (150 of 403 dumps scanned — it samples)
empty_relation_emission_audit   0 empty-list states
cardinality_consistency_audit   pass but VACUOUS
identity_symbolicity_audit      pass — every principal bind is symbolic
```

Two things to carry into `NOTES.md` rather than rediscover:

* The four JUNK notes are each a documented wall or a non-access, and all four
  are declared SHIMs whose real bodies issue no SQL. **Verify each against the
  target layer yourself and say so**; do not quote this list as if checking it
  were done. `User#blocks` is the one to look at first: before 2026-10-08 the
  interceptor's own type probe made that shim emit a real whole-collection
  SELECT (§0), and its appearing here as note-less is the fix working.
* `cardinality_consistency_audit` says of itself: *"this corpus contains no bulk
  loader reading a list's own rows, so the rule was never applied. Absence of
  the subject is not evidence about it; do not count this as a check that
  passed."* **Quote it that way.** Six green audits are five checks and one
  vacuity.

### 6. `shim_tests.rb` — configured, and it is about the SHARED boundary

The shim gate is configured (`extract_cmd` + `test_cmd` in `in/config.json`)
and `extract_cmd` + `test_cmd` + `shim_tests` are all mandatory: omit
`shim_tests.rb` and the engine blocks with `shim gate: NOT CONFIGURED`.

The extractor runs over the **shared** target library, not over this
endpoint's override:

    ruby src_new/runtimes/ruby_runtime/completion_checker/shim_extractor.rb \
      reports/autolab/targets/core.rb reports/autolab/targets/shared_shims.rb

Re-measured 2026-10-08: it emits **22 entries, 22 distinct keys** (the first
five being `obj.read_attribute`, `obj._read_attribute`, `obj.concolic_attrs`,
`obj.concolic_note`, `obj.attributes`) — the same 22 the `aspect_memberships_create`
(drive 8), `conversation_visibilities_destroy`, `posts_destroy` and `tags_index`
packets were built against, because the boundary is shared app-wide (Rule T)
and the argv does not name this endpoint's layer. So a prior packet's
`shim_tests.rb` is a legitimate starting point; all of these exist and are
readable:

    local_amc1/boxes/aspect_memberships_create-batch-1-de5bd305/out/packet/shim_tests.rb
    local_amc2/boxes/aspect_memberships_create-batch-1-dfb2bc19/out/packet/shim_tests.rb
    local_tags1/boxes/tags_index-batch-1-acf20787/out/packet/shim_tests.rb          (30077 bytes)
    local_cvd4/boxes/conversation_visibilities_destroy-batch-1-bb942577/out/packet/shim_tests.rb (30005 bytes)

**Re-run it against this box before submission; the verdicts must be this run's,
not inherited**, and say in `NOTES.md` where the file came from. Drive 8's shim
gate came back `{PASS: 10, PROTOCOL: 12}` over 22 extracted keys — a PROTOCOL
row is not a pass and is worth a sentence of its own in your notes.

### 7. `produced_with` is REQUIRED, and every value in it is MEASURED

    runtime_digest     measure it:  python3 -m sweep.engine_digest
    runtime_revision   measure it:  python3 -m sweep.engine_digest --json
    app_revision       0760b6a22e113b74567330ff69ccc55a1d07022c   (the app's HEAD)
    app_tree_digest    916d393795a47b99d2128464ba268defb51524555bc26c659560575051501954

**Run both measurements yourself and confirm them rather than copying a line
from this document.** A digest copied from a brief is a digest of whatever the
brief's author was looking at.

`app_tree_digest` is the app's PIN; `tools/app_tree_digest.py` is the
measurement and covers `app/ lib/ config/ db/schema.rb Gemfile Gemfile.lock`
and nothing else — `targets/core.rb` is correctly outside it.

`runtime_digest` is the ENGINE's, and it is a digest of the CONTENT of the
trees whose code this drive runs, measured from the tree the tool is imported
from. The pre-gate compares it **three ways**: against the campaign's pin,
against what the packet claims, and against the tree the gate measures while it
is itself running. Two of those three can refuse your attempt:

* the engine tree **moved while you were working** — refused, `moved_in_flight`;
* it **differs from the campaign's pin** — refused, `changed_before_the_drive`.

So this value is not a label. Measure it, record it, and if `--json` reports
`dirty: true` say so beside the value: a revision name cannot tell a reader
that it fails to describe the tree, and a drive whose engine is uncommitted has
no identifier that means anything.

`runtime_revision` is recorded **beside** the digest and only as a pointer for
a reader — where to look, not what ran. `python3 -m sweep.engine_digest --json`
prints the digest, the revision and the `dirty` flag together, for exactly this.

### 8. THE DOMAIN GATE IS NOT YOURS, AND BOTH ITS INPUTS EXIST

The mock-note check left the generic engine's mandatory gate on 2026-10-05 and
is now `domains/ruby_rails_sql/checks.py::shape_check`, reached through
`Domain.check(policy, real)` by DESIGN_SWEEP §6.3's STATIC HALF and gated there
as `WorkResult.domain_blocking`. `statement_differential` is built —
re-measured 2026-10-08, `_UNBUILT` is `()` (`checks.py:1201`) — so
`check-not-implemented/statement_differential` does not appear.

This endpoint **declares both** `fixtures` and `real_mode_plan`, so the
domain's conjunction is answerable. They are COORDINATOR-OWNED GROUND TRUTH and
they are not in your box to author:

* `local_amc3/fixtures/aspect_memberships_create/world.json` — `amc-world-2`,
  29 rows: five users carrying the three-arm `language` domain (`en`/`pl`/`xx`),
  seven people (one owned by the principal for the self-contact arm, one closed
  account, one blocked, two already contacted), seven profiles, five aspects,
  **two contacts — one receiving and one NOT** — one existing membership, one
  block and one unread `Notifications::StartedSharing`.
* `local_amc3/plan/real_mode_plan.json` — `amc-real-2`, **ten** scenarios, with
  a `principal` block (this endpoint is `signed_in: true`), an EMPTY
  `frame_aliases`, and `replay_callbacks: ["set_locale",
  "set_grammatical_gender"]` on every scenario (`autolab_dse.rb:1102` replays
  exactly those two for a signed-in endpoint, so a plan that did not replay
  them would be recording a different execution from the one your corpus
  describes).

**Both are drive 8's `amc-world-1` / `amc-real-1` plus exactly one row and
exactly one scenario, added BEFORE this drive ran.** Drive 8's closing agent
measured that the corpus explores a PERSISTED contact with `receiving = false`
and that none of its nine scenarios reached it, and refused to add a scenario
mid-drive — correctly, because ground truth edited after you have seen which
review items it produced is no longer ground truth. The gap is real and
re-measured here: `UPDATE "contacts" SET … "receiving" = true` is 128 notes in
64 of 403 dumps and is reachable only from a persisted non-receiving contact,
which amc-world-1 did not contain. Contact 101 (user 1 -> person 6,
receiving=false) and scenario `share-existing-nonreceiving-contact` close it.
The reasoning is in the documents' own
`_why_one_row_was_added_BEFORE_the_drive` and
`_the_tenth_scenario_was_added_BEFORE_this_drive_ran` keys.

`frame_aliases` is EMPTY by measurement, not by omission. Drive 8's plan first
carried a cvd6-shaped entry mapping `ActiveRecord::FinderMethods#first` to
`devise_user_first`; that drive's coordinator dry-ran the plan and measured
that `FinderMethods#first` **never appears as a real frame at all** (the real
frames are `find_by_sql`, `exists?`, `save`, `save!`, `update_all`). An alias
from `find_by_sql` WOULD have matched and was deliberately not written: five of
the ten target functions the IR declares never appear as a real frame, because
a mocked target's body never runs, so the corpus names the OUTER target while a
real run names the innermost one. Repairing one instance would be the
coordinator choosing which cases of a five-case asymmetry the gate may report.
**Expect `shape_check` to have something to say about frame attribution, and do
not treat it as your defect.**

**DO NOT produce a `concrete_run.json`.** `sweep/briefs/batch.md` forbids it
and it would be a fabricated ground truth. An agent that writes its own ground
truth has been handed the answer key.

**Two things the domain gate is expected to block on, and BOTH ARE REAL
FINDINGS.** They are named here so they do not surprise you and so that nobody
mistakes them for something to tidy away:

* **The fold emits SELECT views only.** Every write atom this endpoint produces
  is excluded with `terminates in INSERT/UPDATE, which is a write and not a
  select view` (`domains/ruby_rails_sql/render.py:248`). Drive 8 measured all
  16 of its unsupported atoms excluded for exactly that reason and 0 for any
  other. **A `_create` endpoint's policy therefore structurally cannot name
  what it writes.**
* **Views whose predicates omit the principal column.** Drive 8 rendered 21
  views and 3 carried no principal restriction at all, the starkest being
  `SELECT people.* FROM people` with no `WHERE` clause whatsoever. (The
  `profiles` read that an earlier guess blamed comes out correctly restricted by
  `_MY_UID`. The string `*** UNRESTRICTED ***` is emitted by no renderer
  anywhere; the real signature is an absent `_MY_UID`.)

If your corpus reproduces either, **say so**. Neither is to be suppressed,
waived, or absorbed by widening a policy. A blocked endpoint with a true
account is a correct outcome; a closed one that hid a finding is worthless.

### 9. What an honest submission looks like here

* `dumps/` — the distinct paths you keep, at the top level of `batch/` as well.
  §3's numbers say what a given `MAX_RUNS` yields.
* `assumptions.json` — **the deliverable** (§4), and now the thing that decides
  the coverage verdict (§0). Each declaration evidenced from YOUR corpus and
  testable by the configured gate.
* `shim_tests.rb` — carried over, **re-run here**, provenance stated (§6).
* `assumption_manifest.json` — `batch_dir` must be `in/packet/dumps`,
  RELATIVE to the box root. **It SHOULD carry a `workdir`, and drive 8's
  addendum was wrong to forbid one.** There are two config documents and they
  are not the same one. The **completion config** is `in/config.json`'s
  `completion` block; `concolic/checks/proc.py::_run` uses its `workdir` as
  the cwd for every configured gate COMMAND, and THAT is the key
  `_note_no_workdir` forbids — a `workdir` there made drive 7's attempt 1
  resolve `in/packet/dumps` against `/home/dev/project`, index a directory
  that does not exist, and then report a corpus it had never read. The
  **assumption cfg** is the separate document you supply through the packet
  and that `assumption_cmd` substitutes as `{cfg}`;
  `concolic/checks/assumptions.py`'s own docstring names its keys as
  `batch_dir, runner, workdir, env_by_scenario`, and `run_probe` reads
  `workdir` BOTH as the probe subprocess's cwd and as the third (and here
  only) entry of `_dump_dirs`, which is where it globs probe dumps. With a
  shell launcher as `runner` (no `.rb` token) and no `workdir`, `_dump_dirs`
  has no directory to glob and **every probe silently finds nothing.** So set
  it, to an absolute writable directory you `mkdir -p` before submitting
  (`_dump_dirs` filters on `os.path.isdir`), and point `env.DUMP_OUT` at the
  same path. Drive 8 did exactly this (`workdir: /tmp/amc1_achk_dumps`) on its
  coordinator's answer to ticket `manifest-dump-dir`, and all six of its rows
  PASSED. The narrowness of `_dump_dirs` is a real shared-tier defect; it is
  unfixed, `src_new/` is run-only here, so **escalate it, do not patch it.**
* `NOTES.md` — the combination-coverage demand and what you did about it (§4),
  which declarations you carried from drive 8 and which are new, the vacuous
  audit quoted as vacuous (§5), the four JUNK notes checked individually (§5),
  the two real terminals and why each is an app outcome rather than a wall
  (§3), and anything you found in the target layer that you escalated. This
  file is the deliverable that makes the drive worth anything.

### 10. WAITING ON A PROCESS, AND SIGNALLING ONE

Single provenance is a hard rule on this campaign, and waiting is where it
breaks. A `pgrep -f <pattern>` wait matches **the shell holding the wait loop**,
because that pattern is in its own command line: the loop then waits for
itself and never ends. This has cost three agents real time, each having read a
warning about it, so the rule here is a tool and not a warning:

```bash
PYTHONPATH=/home/dev/project/src_new python3 -m sweep.box.wait_for --help
```

* **Wait with the helper.** It identifies a target by pid (with the start-time
  re-check that makes a recycled pid end a wait instead of extending it onto a
  stranger), by `/proc/<pid>/exe`, by exact `comm`, or by a sentinel file — and
  before any of those it removes its own pid, every ancestor up to pid 1, and
  its process group. A `--contains` substring may only ever NARROW an exe or
  name match; on its own it is refused, because that is the defect.
* **A wait takes a timeout.** `--timeout` is required; `--timeout 0` means
  forever and has to be asked for out loud. An unbounded wait makes whatever
  follows it unreachable.
* **A sentinel file is the strongest wait there is** — there is nothing to
  match, so there is nothing to match wrongly. Prefer `--file` when the thing
  you are waiting for can write one. `run_rest.sh` waits that way.
* **Never signal by pattern.** Resolve a PID, verify it belongs to the run you
  mean by its box session-id, and only then signal that PID.
* **If you ever suspect two runs overlapped, discard the corpus and re-run from
  clean** rather than reasoning about which dumps came from where.

The coordinator's own probe for this drive wrote into a session scratch
directory and never into `local_amc3/layer/aspect_memberships_create/batch`, so
no dump in your corpus shares a directory with a coordinator probe. Keep it
that way. Another agent may be running on this machine concurrently: expect CPU
contention and do not read slowness as a hang.
