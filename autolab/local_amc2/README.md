# local_amc2 — `aspect_memberships_create`, re-driven through the six-stage chain

Drive 9, and the second drive of this endpoint. Drive 8 (`local_amc1`) ran the
whole chain and did not close; five defects it found were fixed in `src_new`
(`70bca8e`) and this drive is the first run of the chain with all five in
place. Nothing in `local_amc1` — or in any other `local_*` directory — was
written by this drive.

```
batch     submitted=True  detail=ok  elapsed=1288s  cost=$1.99  denials=0
          stopped_by=submitted   corpus 417 dumps (403 default + 14 seeded)
          packet 422 files, tree digest 6e2be27e…
pregate   passed=True  decision=D-0001  refusals=[]
          config digest matches; app tree digest matches the pin
check     outcome=COMPLETE  complete=True  blocking=[]  elapsed=1108s
          coverage: coverage_complete TRUE  tree_complete TRUE  missing_branches 0
                    truncated FALSE  solver_lost 0  total_runs 417  assumptions_used 6
          gates:    completion.complete TRUE, completion.blocking []
                    assumptions 6 declared / 6 distinct tested / PASS 6, FAIL 0,
                      ERROR 0, NOT-TESTABLE 0, NOT-COMPARABLE 0, OUTSTANDING 0
                    shims 22 extracted, {PASS: 10, PROTOCOL: 12}
                    audits 6/6 green (cardinality_consistency VACUOUS by its own text)
          packet 422 files / digest 6e2be27e... before AND after -- unchanged
policy    runs=417  atoms=55  notes=570  minimal=partial
realmode  10 scenarios, 99 statements, 41s; 6 scenarios recorded an error, each predicted
concrete  elapsed=446s  detail=agent:ok; static:ok  findings=10 (4 agent + 6 static)
          static half EXIT 1; 4 distinct boxes this drive (asserted, not assumed)
          agent box stopped_by=submitted wall_s=446  (drive 8: wall_clock, 10800)

[certificate] endpoint=aspect_memberships_create attempt=1
              ENGINE=COMPLETE(0 blocking)  DOMAIN=BLOCKED(1 blocking)
              claims=10  VERDICT=NOT CLOSEABLE
```

## The five fixes, and what each one actually did here

| | fix | measured on this drive |
|---|---|---|
| 1 | **the coverage wire** — `_validate_one` built an `Assumption` from each declared record, proved its identity, and returned `None`, so declarations reached the gate and never `CoverageChecker` (`_coverage_assumptions`, `concolic/check.py:1130`) | **CONFIRMED, and it is what closed the endpoint.** The check reports `coverage_complete: true`, `missing_branches: 0`, `truncated: false`, `assumptions_used: 6`. Drive 8, same endpoint, same six declarations, all six gate-PASSED: `false / 82 / true / 0`. Verified independently three ways before the drive ran: this coordinator re-ran `declared_assumption_set` + `run_complete` over drive 8's own 417-dump packet and its own six records and got `true / 0 / false / 6`; over a fresh 403-dump probe with no declarations it reproduced drive 8's `false / 88 / true / 0` exactly. |
| 2 | **the instrument no longer causes a read it records** — the body-skip classifier's `concrete_result == true` dispatched `CollectionProxy#==` (`load_target == other`), so the type probe LOADED the association; now `.equal?` (`call_interceptor.rb:705,731-732`) | **CONFIRMED.** Drive 8's 417-dump corpus carried 19 distinct statement shapes including 1508 notes of `SELECT "blocks".* FROM "blocks" WHERE "blocks"."user_id" = ?` in 414 dumps. This drive's 417-dump corpus carries **18** shapes and that statement **zero** times. The narrow real `exists?` is untouched (1508 notes / 414 dumps). The coordinator's own 403-dump probes either side of the fix agree: 5331 clean notes → 4599, the difference being exactly those 732 notes. The agent found the same thing independently and said so in its `NOTES.md`. |
| 3 | **writes have a shape** — `_shape_of` read INSERT/UPDATE through a FROM/JOIN-only regex | **CONFIRMED by direct measurement.** `_shape_of` now returns `INSERT tables={aspect_memberships}`, `UPDATE tables={notifications} pred={notifications.type}` and `UPDATE tables={contacts} pred={contacts.id}`. Drive 8's static items named its INSERT rows by COLUMN (`INSERT/contact_id`, `/created_at`, `/person_id`, `/receiving`, `/updated_at`) — the table lost — and carried no UPDATE row at all. |
| 4 | **the gate no longer writes into the packet** — `run_probe`'s seed file moved from `batch_dir` to `workdir`, in a `try/finally` (`concolic/gate/replay.py:238`) | **CONFIRMED LIVE.** The packet was 422 files / tree digest `6e2be27e…` before the check stage and byte-identical while the check box held it symlinked at `in/packet` with the assumption gate running. Drive 8 went 422 → 423 and `da981ddc…` → `78546c27…` at exactly this point. Seed files appeared in `/tmp/amc2_achk_dumps` (the manifest's `workdir`) instead. |
| 5 | **a verified submission ends the box** — `REASON_SUBMITTED`, agent path only (`sweep/agentd/main.py:90,525`) | **CONFIRMED.** The batch box's `worker.json` reads `stopped_by: submitted`, `wall_s: 1288`. Drive 8's read `stopped_by: exit`, `wall_s: 3359`, and its CONCRETE agent box read `stopped_by: wall_clock`, `wall_s: 10800` — the three-hour idle this fix exists to end. |

## The one deliberate addition, and why its timing makes it sound

`amc-world-2` is `amc-world-1` plus ONE row and `amc-real-2` is `amc-real-1`
plus ONE scenario. Nothing else in either document changed.

```
contacts  id 101  user_id 1  person_id 6  sharing false  receiving FALSE
scenario  share-existing-nonreceiving-contact   person_id 6  aspect_id 10
```

Drive 8's corpus issues `UPDATE "contacts" SET "updated_at" = …, "receiving" =
true WHERE "contacts"."id" = ?` in **64 of its 417 dumps** (128 notes;
re-measured by this coordinator over drive 8's own packet, and present in the
same proportion here). That statement is reachable only from a **persisted**
contact whose `receiving` is false: `share_with` assigns `contact.receiving =
true` and `contact.save` then has a dirty attribute to write. `amc-world-1`
had exactly one contact, 100, with `receiving: true`, so **no scenario in
`amc-real-1` could issue it** — scenario 1 builds a NEW contact (INSERT, not
UPDATE) and scenario 2's contact is already receiving, so its `save` writes
nothing to `contacts`.

**Drive 8's closing agent found that gap and refused to add a scenario
mid-drive.** That refusal was correct: ground truth edited after you have seen
which review items it produced is no longer ground truth — it is a result
fitted to its own answer key. Adding the same scenario **here, before this
drive's first run existed**, is the opposite operation. There was no corpus, no
policy, no recording and no review item in being for it to be fitted to, and
the gap it closes was named and measured in advance rather than discovered by
reading what the gate said. The difference is entirely one of timing, and that
is exactly why it is admissible now and was not then.

The row is the minimum that opens the arm. Person 6 is dave's own person
(`owner_id 4`), so it is local, open, unblocked and not the principal's own
person: the contact is valid, `needs_dispatch` is TRUE, and
`deliver_profile_update` is skipped (`unless person.local?`), so the arm
contributes the `contacts` UPDATE and no federation statement. Contact 101
carries no `aspect_memberships` row, so `contact.aspects << aspect` on aspect
10 cannot collide with that table's unique index. The reasoning lives in the
documents themselves, in `world.json`'s
`_why_one_row_was_added_BEFORE_the_drive` and the plan's
`_the_tenth_scenario_was_added_BEFORE_this_drive_ran`.

**It is a world change as well as a plan change, and that is worth saying
plainly.** The brief asked for a scenario; a scenario alone could not reach the
arm, because `real_mode_probe.rb` takes a scenario's `name`, `controller`,
`action`, `format`, `params`, `principal` and `replay_callbacks` and has no
per-scenario row mechanism (measured). So the world had to gain the contact.
`world_id` and `plan_id` were both re-stamped (`amc-world-2`, `amc-real-2`) so
that no recording can be mistaken for one made in drive 8's world.

## What this drive changed from drive 8, and nothing else

1. **The directory**: `local_amc2/`, with its own `state/`, `logs/`, `out/`,
   `boxes/`, `layer/`, `base/` and `agent_config/`. Sweep name
   `autolab-local-amc2`.
2. **The world and the plan**, as above.
3. **`drive.py`'s header**, rewritten for this drive. The mechanism below it —
   the `WorkerLayer.run(WorkRequest)` seam, the four §6.3 arguments, the
   `recording=` / `app_config=` mounts, `STATIC_ARGV`, the box-separation
   assertion, the certificate — is drive 8's, byte for byte.
4. **`addendum_local.md`**, re-measured rather than inherited. Two of drive 8's
   own sentences came out false and are corrected in it (see below).
5. **Not changed, deliberately**: every gate, audit, timeout and `limits` value
   in `inputs/aspect_memberships_create_config.json`. `max_cliques=200` and
   `max_missing_per_clique=50` are the scaffold's values untouched — they shape
   the coverage verdict, and a re-drive that moved a gate would not be
   measuring the five fixes.

## Two inherited claims that were false, found by checking them

* **The target layer does not name eleven defects.** Drive 8's addendum said
  `targets/endpoints/aspect_memberships_create.rb`'s header "names eleven
  defects (D1…D11) found when it was written". The only defect labels in the
  whole 67,161-byte file are **D4–D8**; D1…D11 are in
  `reports/diaspora/results4/aspect_memberships_create/REPORT.md`, the
  authoritative batch this layer was lifted from. Corrected in §2 of this
  drive's addendum. **The correction landed after the batch brief was
  composed**, so this round's batch agent read the wrong sentence; it is a
  pointer to a defect list, not a measurement anything depends on.
* **The assumption manifest SHOULD carry a `workdir`.** Drive 8's addendum §8
  said it must carry none, conflating two documents: the COMPLETION config's
  `workdir` (which must stay absent — `concolic/checks/proc.py::_run` uses it
  as the cwd of every gate command, and setting it made drive 7's attempt 1
  index a directory that does not exist) with the ASSUMPTION CFG's, which
  `concolic/checks/assumptions.py` names in its own docstring and which
  `run_probe` uses as the probe's cwd, the seed-file directory and the third
  entry of `_dump_dirs`. This drive's batch agent spotted the contradiction,
  escalated it (`ctl/ask/manifest-workdir.json`, class `local`) rather than
  routing around it, and was answered: its plan was approved and §9 was
  corrected. **The underlying defect stands and is not fixed**:
  `_dump_dirs` globs only `batch_dir`, the dirname of each `.rb` token of
  `runner`, and `workdir or "."`, so a campaign whose runner is a shell
  launcher and whose manifest omits `workdir` gives its probes no glob
  directory and every probe silently finds nothing. `src_new/` is run-only
  here, so it is reported, not patched.

## Provenance

`APP_TREE_PIN` = `916d393795a47b99d2128464ba268defb51524555bc26c659560575051501954`,
measured before the drive and again after, and matched by the pre-gate;
`app_revision` `0760b6a22e113b74567330ff69ccc55a1d07022c`.

`runtime_revision` = `70bca8e05e4e7e2956f8121cf2c671de070ef6fb`. `src_new`'s
working tree was clean before the drive and clean after (`git status
--porcelain` empty both times), so this value does identify the code that ran —
**but the mechanism is still unsound and nothing verifies it.** The field is a
hand-copied `git rev-parse HEAD`; the pre-gate compares only
`produced_with.app_tree_digest`
(`sweep/coordinator/pregate.py:691-716`), and `runtime_revision` appears in no
non-test verification anywhere in `src_new/` (its only other occurrence in the
tree is a test fixture, `tests/sweep_e2e/support.py:133`). Drive 8 recorded
`ee9f17bc…` and then had 6,471 uncommitted insertions published 23 minutes into
its run — including the whole real-mode producer its own `--stage realmode` was
executing — so the revision it wrote down named code that did not contain the
stage. It identifies the running code here because the tree happened to be
clean, not because anything checked.

**Single provenance.** This coordinator's probes (one 1500-run exploration, one
policy build, one render) all wrote into a session scratch directory and never
into `layer/aspect_memberships_create/batch`, so no dump in this drive's corpus
shares a directory with a coordinator probe. The agent's own `NOTES.md` records
the same from its side: run1 into `batch/run1`, run2 into `batch/run2`, both
copied up, and nothing else writing there.

## Layout

```
drive.py                                       the six stages, retargeted from local_amc1
run_rest.sh                                    pregate->check->policy->realmode->concrete, in order
inputs/aspect_memberships_create_config.json   drive 8's config, batch_dir retargeted; gates untouched
fixtures/aspect_memberships_create/world.json  amc-world-2: 29 rows (amc-world-1 + contact 101)
plan/real_mode_plan.json                       amc-real-2: ten scenarios (amc-real-1 + the tenth)
out/policy-1.json                              the IR, built from the approved packet's corpus
out/concrete_run.json                          THE RECORDING (written by --stage realmode)
state/*.json                                   one record per stage
logs/*.log                                     one log per stage, plus chain.log
addendum_local.md                              THIS endpoint's operator addendum, re-measured
tools/{app_tree_digest,build_policy_ir}.py
```

---

## The result, both halves, exactly

**ENGINE: `complete: true`, `blocking: []`.** This is the lab's first. The
engine's own report
(`boxes/aspect_memberships_create-check-1-b0a742ea/out/report.json`,
`report_verified: True`):

```
outcome            COMPLETE
complete           True
blocking           []
coverage_complete  True
tree_complete      True
missing_branches   0
truncated          False
solver_lost        0
total_runs         417
assumptions_used   6
completion.complete   True
completion.blocking   []
```

and every configured gate green on its own terms:

```
assumptions   6 declared, 6 distinct tested — PASS 6, FAIL 0, ERROR 0,
              NOT-TESTABLE 0, NOT-COMPARABLE 0, OUTSTANDING 0   (green: true)
              each row: [8 base(s) probed, 8 realising; 4-5 witness(es)/1 scenario(s),
              floor 3 of 4-5 available; PASS=8] access trace identical on both sides
shims         22 extracted — PASS 10, PROTOCOL 12, FAIL 0, NO-TEST 0
audits        6/6 exit 0 — and that is FIVE CHECKS AND ONE VACUITY:
              cardinality_consistency_audit says of itself "this corpus contains no
              bulk loader reading a list's own rows, so the rule was never applied.
              Absence of the subject is not evidence about it; do not count this as
              a check that passed."
```

**What `coverage_complete: true` means here, stated so it cannot be
over-read.** It is *complete given these six declarations*. Six
`UntrackedPathAssumption`s on the `users.language` three-arm compare, on the
THREE NON-PRINCIPAL users who carry it (`contact.user`,
`contact.person.owner`, `@person.owner`); the PRINCIPAL's language decision is
deliberately left undeclared because flipping it changes the access trace in
180 of 180 run pairs. The agent evidenced the six from its own corpus
(264 + 264 + 54 differing-arm pairs, **0** trace differences) and the gate then
PASSED all six by real replay, 47 probes over 8 bases. The 14 leaves that
remained after declaring were **driven** (`run2`, `EXTRA_SEEDS_JSON` +
`SEEDS_ONLY`, `worklist empty: true`), not licensed away. Carried, not
invented: the `type`/`source`/`expr`/`description` of all six are drive 8's;
only the evidence and the verdicts are this run's.

**DOMAIN: `domain_blocking` has ONE line, verbatim and entire:**

```
static half: EXIT 1 — §6.3's static half is a script with an exit code and this
one did not exit 0, so the domain's static checks did not pass. The claims are
this round's review items
```

So the certificate is `ENGINE=COMPLETE(0 blocking) DOMAIN=BLOCKED(1 blocking)
claims=10 VERDICT=NOT CLOSEABLE`. **That is the correct outcome, not a
shortfall**: the engine's conjunction is discharged and the domain's is not,
and the two are reported from two different stages precisely so they can never
be merged.

## Ten claims, and the two the owner predicted are both here

The static half raised **6**, the agentic half **4**.

**1. The write-omission — a `_create`'s policy structurally cannot name what it
writes.** All four write relations come back as `statement-differential/
not-in-views`:

```
statement-differential/not-in-views/INSERT/aspect_memberships
statement-differential/not-in-views/INSERT/contacts
statement-differential/not-in-views/UPDATE/contacts
statement-differential/not-in-views/UPDATE/notifications
```

The cause is in the fold, not the corpus: rendering this drive's own IR
produces **19 views and 16 unsupported atoms, and all 16 are excluded for one
reason** — 8 × `terminates in INSERT, which is a write and not a select view`
and 8 × the same for UPDATE (`domains/ruby_rails_sql/render.py:248`), with
**zero** excluded for any other reason. Not suppressed, not waived, and no
policy was widened to absorb it.

**This item set is itself the proof of fix 3.** Drive 8's four write relations
were reported as `INSERT/contact_id`, `INSERT/created_at`, `INSERT/person_id`,
`INSERT/receiving`, `INSERT/updated_at` — the INSERT's own column list with the
table lost — and **no UPDATE row at all**, because `_shape_of` returned
`frozenset()` for an UPDATE and the one `UPDATE "notifications"` in the
recording was, in drive 8's own words, "reported by nothing". Both UPDATEs are
named now.

**2. `UPDATE/contacts` exists as an item only because of the tenth scenario.**
It is in the policy (128 notes / 64 dumps) and, as of this drive, in the
recording — scenario `share-existing-nonreceiving-contact` issued
`UPDATE "contacts" SET "receiving" = ?, "updated_at" = ? WHERE
"contacts"."id" = ?` under frame `ActiveRecord::Base#save`, after the
`aspect_memberships` INSERT and before the Redis terminal. In drive 8 the
corpus claimed that write and no scenario could confirm or refute it. The
scenario did not make a finding go away; it made one **reportable**.

**3. Views whose predicates omit the principal column — 3 of 19.** This is a
coordinator measurement, not a gate item (nothing in the static half checks
it, on this drive or on drive 8). Rendering this drive's IR with this
campaign's app config:

```
SELECT `users`.* FROM `users`, `people`, `people` AS `people0` WHERE `users`.`id` = `people`.`owner_id` AND `people`.`id` = `people0`.`id`
SELECT `people`.* FROM `people`, `people` AS `people0` WHERE `people`.`id` = `people0`.`id`
SELECT `people`.* FROM `people`
```

The starkest is `SELECT people.* FROM people` with no `WHERE` at all. 3 of 19
here against drive 8's 3 of 21 — the same three, over a corpus one atom set
smaller. The `profiles` read an earlier guess blamed comes out correctly
restricted by `_MY_UID`. A real disclosure question, and nothing here makes it
go away.

**4. The agentic half's four**, each with measured evidence and an honest
catchability call:

| identity | catchable |
|---|---|
| `note-fidelity/missing/aspects.name-uniqueness-probe/ActiveRecord::FinderMethods#exists?/MISSING` — the real new-contact path issues `SELECT 1 AS one FROM "aspects" WHERE LOWER("aspects"."name") = LOWER(?) AND "aspects"."id" != ? AND "aspects"."user_id" = ?` inside the save transaction; the corpus has no such note, so an enforcer holding this policy would refuse the real request at its INSERT | true |
| `check-fidelity/shape-match-ignores-predicate-operators/statement-shape` — `_shape_of` reduces a WHERE clause to its SET OF COLUMN NAMES, dropping `=`, `!=`, `IS NULL`, `IS NOT NULL` and `LOWER()`, so three real/note pairs on this endpoint compare as covered when their row sets are disjoint. It is the comparator every endpoint's `shape_check` uses. | **false** |
| `note-fidelity/not-same-write/mock-dml-ignores-record-state` — the mocked `save`/`save!` returns a seeded bool without applying post-save record state: one INSERT loses a column, another doubles one, and one arm invents an UPDATE | **false** |
| `note-fidelity/same-read/frame-alias/users.id/devise_user_first-vs-first` — the session principal lookup, identical in tables, projection, predicate, operator and ORDER BY, named `first` by the real run and `devise_user_first` by the corpus; a `frame_aliases` entry is PROPOSED and deliberately not applied | true |

The last one is the five-case mock-vs-real frame asymmetry this plan's
`_why_no_alias_was_written_instead` already records, arriving as a gate item
exactly as the addendum predicted it would.

## The escalation this drive's agent raised, and the answer

`ctl/ask/manifest-workdir.json`, class `local`, raised rather than routed
around: the addendum's "no `workdir` key" instruction, followed literally,
would have given the assumption gate's probes no directory to glob and made
every probe silently find nothing. The reading was correct and the answer
(`ctl/answer/manifest-workdir.json`) approved the plan, corrected the
addendum, and asked that the escalation stand. The agent then set
`workdir`/`env.DUMP_OUT` to `/tmp/amc2_achk_dumps`, documented why in the
manifest's own comment key, and the gate's 47 probes all globbed from there.
**The `_dump_dirs` narrowness is an open shared-tier defect and is not fixed**
— `src_new/` is run-only here.

## Three defects in `src_new` found by this drive, none of them applied

1. **The engine's own caveat now contradicts its own numbers.**
   `concolic/check.py:1456-1464` appends, whenever a packet declares anything:
   *"N assumption(s) declared by the packet were VALIDATED at packet load …
   and handed to the gate, but they did NOT reduce the coverage demand: the
   instances `validate_declared` builds are discarded and the gate still
   consumes the raw dicts."* That sentence described the defect fix 1 repaired
   and was not updated with it. It is in **this drive's report**, three lines
   away from `assumptions_used: 6` and `missing_branches: 0`, which prove the
   opposite. A reader who trusts the prose over the numbers would conclude this
   endpoint's coverage was an over-approximation when it is not.
2. **The same caveat says "one of the 8 registered kinds".** `registry.tags()`
   answers **9**: `AliasAssumption`, `DecisionAliasAssumption`,
   `IndependenceAssumption`, `UntrackedPathAssumption`,
   `OneSideUntrackedPathAssumption`, `SymbolicConstraintAssumption`,
   `ForeclosureAssumption`, `ConjunctionForeclosureAssumption`,
   `SubconjunctionForeclosureAssumption`. The same count is in
   `check.py:448`'s refusal text, and a test asserts the string.
3. **`_dump_dirs` is too narrow to find a shell launcher's probe dumps** — see
   the escalation above.

## Verification

| | |
|---|---|
| `APP_TREE_PIN` | `916d3937…1954` measured before the drive and again after — **equal**; the pre-gate compared it and matched |
| `reports/autolab/test/run_tests.sh` | **ALL SUITES PASSED** — `test_install.rb` 38/38 under JRuby and 38/38 under CRuby, `test_inventory.py` **75/75**, `test_cost.py` 24/24, `reconcile_with_app.py` and `check_citations.py` green |
| `pytest`, four suites, each in its OWN process | `concolic` **1198** passed / 3 skipped, `sweep` **1265** passed / 11 skipped, `domains` **309** passed / 1 skipped, `dumps_to_policy` **513** passed — all four exactly the counts `70bca8e`'s own message records |
| `inventory/*.json` | five of six byte-identical; `citations.json` changed — see below |
| `targets/` | untouched, every mtime predates this drive |
| boxes | 4 distinct, asserted from artefact paths rather than assumed |
| single provenance | the coordinator's probes wrote only into session scratch; the agent's two runs wrote into `batch/run1` and `batch/run2` |
| cost | **$1.99** of a $40 endpoint budget (batch agent; the check worker and the static half are free, the concrete agent's usage was not priced) |

**`inventory/citations.json` is NOT byte-identical, and the cause is the
suite itself.** `tools/check_citations.py` — a member of `run_tests.sh` —
rewrites that file on every invocation by design ("Writes
`inventory/citations.json` either way", its own docstring). Running the
required verification therefore necessarily changes one of the files the
requirement asks to be unchanged. The refreshed content passes its own check
(24/24, 0 unresolvable patterns, 0 doc citations matching no pattern) and is
byte-stable across repeated runs, and nothing this drive wrote is an input to
it: it reads only `README.md`, `docs/CONFLICTS.md` and the `targets/` files,
none of which this drive touched (mtimes 2026-10-07 and earlier). So the
pre-drive copy was **stale with respect to the current prose** and the suite
refreshed it. The old bytes are not recoverable — `inventory/` is untracked in
`reports/`'s git — so this is reported rather than reverted.

**`src_new` did not stay clean, and it was not this drive.**
`git status --porcelain` was empty before the drive and reads
`M concolic/README.md` after: +118 lines of new documentation about the shim
gate, mtime **21:04:35**, three seconds after the check stage exited and
before the concrete stage started. This drive wrote nothing to `src_new`; both
of its agents are denied `Write`/`Edit` under `src_new/**` by
`agent_config/settings.json`, and the only thing running in that window was
the deterministic check worker, which does not write prose. The file is
documentation, nothing imports it, and the engine's report was already written
and digest-verified before the edit, so **no result here is affected**. It is
recorded because it is a concurrent modification to a tree this drive was told
was fenced — and because it is the second consecutive drive on which
`runtime_revision` ended up naming a tree that was not the tree, which is the
unsoundness in the next section.

**The complete list of things outside this directory that changed during the
drive**, so the fence is auditable rather than asserted: `src_new/concolic/README.md`
(not this drive — above), `reports/autolab/inventory/*.json` (rewritten by the
required suite; five byte-identical, `citations.json` as above),
`reports/autolab/entrypoints/sweep_out_{or,w2}/vitals.jsonl` (appended every
300 s by a pre-existing `sweepmon` poller that was already running — not this
drive), two cache files inside the pre-existing `/home/dev/project/.pytest_cache`
(created 2026-08-14), and the app's sprockets cache below. Nothing else.

**`ruby_examples/` sprockets cache.** Files under
`apps/diaspora/tmp/cache/assets/sprockets/` have today's mtimes. That is the
Rails asset cache, written by booting the application, which every exploration
run does. `APP_TREE_PIN` covers `app/ lib/ config/ db/schema.rb Gemfile
Gemfile.lock` and is **equal** before and after, so the pinned surface is
intact and `APP_TREE_PIN must keep measuring equal` holds.

## `runtime_revision` is still unverified, and this drive demonstrates why

`runtime_revision` = `70bca8e05e4e7e2956f8121cf2c671de070ef6fb`. It identifies
the executed code: the tree was clean when the drive started, and the only
change since is 118 lines of documentation in a file nothing imports.

**But nothing checked that, and nothing could have.** The field is a
hand-copied `git rev-parse HEAD`. The pre-gate verifies
`produced_with.app_tree_digest` and nothing else
(`sweep/coordinator/pregate.py:691-716`), and `runtime_revision` appears in no
non-test verification anywhere in `src_new/` — its only other occurrence in the
whole tree is a test fixture (`tests/sweep_e2e/support.py:133`). Drive 8
recorded a revision that did not contain the real-mode stage its own
`--stage realmode` was executing. Drive 9 recorded a revision that stopped
describing the tree 90 seconds before the drive ended. Both times the executed
bytes were fine and the identifier was not checkable. Unlike
`app_tree_digest`, which has a tool, a pin and a gate, this field is prose.
