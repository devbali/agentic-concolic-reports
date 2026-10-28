# local_amc1 — `aspect_memberships_create`, driven through the six-stage chain

Drive 8. The lab has never closed an autolab endpoint, and the two attempts
before this one failed for the same reason: an endpoint running on the generic
core target library reaches one thing and then dies at the first operation the
symbolic runtime declares a non-goal. `conversation_visibilities_destroy` died
on `SymbolicList#to_ary` (the `dependent: :destroy` cascade has to iterate an
association); `tags_index` died on `SymbolicString#gsub!`, with four more
non-goals stacked behind it. Both drives' launch logs printed *"no target
override … running on core targets only"*.

This endpoint is the one the lab has a real chance with, and the reason is
measurable rather than hopeful:

| | |
|---|---|
| `shakedown/manifest.jsonl` `reach_best` | **10** — against 0 for 39 endpoints, 1 for 118, 2 for 3. The only endpoint past 2. |
| `path_conditions_max` | 16 |
| `reads_profiles` / `verdict` | `true` / `ran_clean` |
| curated target layer | `targets/endpoints/aspect_memberships_create.rb`, 67 KB, `tier: gold` in `targets/registry.json` — one of only two in the lab |
| it is a `create` | so it WRITES, and that is not the destroy wall: instance writes have statement-shaped notes (`…aspect_memberships_create.rb` §2) and the core carries the D8 autosave repair |

## Status — RAN IN FULL, DID NOT CLOSE, and the reason is a missing wire

```
batch     submitted=True  detail=ok  exit_reason=ok  elapsed=3359s  cost=$4.54  turns=94  denials=0
          corpus 417 dumps / 1514 runs; packet da981ddc…, 422 files
pregate   passed=True  decision=D-0001  refusals=[]  config digest + app_tree_digest both match
check     outcome=INCOMPLETE  complete=False  elapsed=949s
          coverage: coverage_complete false  tree_complete TRUE  missing_branches 82
                    truncated true  solver_lost 0  total_runs 417  assumptions_used 0
          gates:    completion.complete TRUE, completion.blocking []
                    assumptions 6 declared / 6 tested / {PASS: 6} / failures []
                    shims 22 extracted, {PASS: 10, PROTOCOL: 12}
                    audits 6/6 green (cardinality_consistency VACUOUS by its own text)
policy    runs=417  atoms=59  notes=672  minimal=partial
realmode  9 scenarios, 83 statements, 30s; 5 scenarios recorded an error, each predicted
concrete  elapsed=10801s  detail=agent:ok; static:ok  findings=14 (7 agent + 7 static)
          static half EXIT 1; boxes this round: agent + static (4 distinct overall)

[certificate] endpoint=aspect_memberships_create attempt=1
              ENGINE=INCOMPLETE(1 blocking)  DOMAIN=BLOCKED(1 blocking)
              claims=14  VERDICT=NOT CLOSEABLE
```

`ENGINE` blocking, verbatim and entire — **one** line:

```
coverage: 82 missing branch(es) — the demand set has leaves no run in the corpus walked
```

`domain_blocking`, verbatim and entire — **one** line:

```
static half: EXIT 1 — §6.3's static half is a script with an exit code and this
one did not exit 0, so the domain's static checks did not pass. The claims are
this round's review items
```

### The coverage demand CLOSES, and the engine cannot compute it

This is the drive's result. The batch agent declared **6** `UntrackedPathAssumption`s
on the non-principal `users.language` compares, evidenced by a differential
(264/264/54 run pairs agreeing on everything but the language arm; **0** trace
differences), and deliberately left the PRINCIPAL's language decision undeclared
because flipping that one changes the trace in 169 of 169 pairs. All six PASSED
the real gate by replay. It then drove the 14 SAT witnesses that remained
(`EXTRA_SEEDS_JSON` + `SEEDS_ONLY`, 14 runs, `worklist empty: true`) rather than
licensing them. Measured three ways:

| | coverage_complete | missing | truncated | assumptions_used |
|---|---|---|---|---|
| engine's own path, 417 dumps | false | 82 | true | 0 |
| coordinator's independent reproduction of that path | false | 82 | true | 0 |
| same corpus + the packet's 6 records, built **by the registry** | **true** | **0** | false | 6 |

So the corpus plus six gate-verified declarations close the demand exactly. The
engine says 82 because the declarations never reach the coverage layer, and the
engine says so itself, in its own `caveats`:

> 6 assumption(s) declared by the packet were VALIDATED at packet load (every
> record resolves to one of the 8 registered kinds, constructs, and has an
> identity) and handed to the gate, but they did NOT reduce the coverage demand:
> the instances `validate_declared` builds are discarded and the gate still
> consumes the raw dicts. The demand is therefore an over-approximation, never
> an under-one.

`_assumption_set` (`concolic/check.py:1314`) reads only
`config["assumptions_hook"]`, a `"module:function"` string; the packet table in
`completion_config_of` has exactly two entries (`shim_tests`,
`assumption_manifest`) and that is not one of them. The fix is a short wire in
`check.py` — the objects already exist and are thrown away. **Not applied:**
`src_new/` is fenced run-only here and the standing rule is that even a
well-diagnosed fix needs a go-ahead before it is applied, not a report after.

### Fourteen claims, and the policy is wrong in BOTH directions

The agentic half raised 7 (1 understate, 1 overstate, 1 wrong both ways, 1
phantom write, 1 gap in **this drive's own plan**, 2 judged benign same-reads);
the static half raised 7. Three findings are worth naming here:

* **The instrument causes a read it then records.**
  `call_interceptor.rb:704-707` tests `concrete_result == true || … == false` on
  a mock's return value; the `User#blocks` SHIM returns an AR `CollectionProxy`
  whose `==` is `load_target == other`, so the probe loads the association.
  Corpus: 754 notes of `SELECT "blocks".* FROM "blocks" WHERE
  "blocks"."user_id" = ?`, shipped in the IR as an Access atom. Recording: 11
  of 83 statements touch `blocks` and all eleven are the narrow real `exists?`;
  `SELECT "blocks".*` occurrences **zero**. Escalated by the agent as a source
  reading, promoted to a measurement by the coordinator.
* **The fold emits SELECT views only**, so every one of this endpoint's 16 write
  atoms is excluded (`terminates in INSERT/UPDATE, which is a write and not a
  select view`; 0 unsupported for any other reason). The policy cannot express
  what a `create` endpoint does.
* **`_shape_of` cannot extract a table from DML.** Measured directly: an INSERT
  yields the column list minus its first column and loses the real table (hence
  five items named `contact_id`, `created_at`, `person_id`, `receiving`,
  `updated_at`); an UPDATE yields `frozenset()`. So the one `UPDATE
  "notifications"` in the recording is reported by **nothing** — absent from the
  views and invisible to the check meant to catch that. sqlglot parses both
  correctly; the defect is the domain's.

### The cross-principal watch item manifested, but not where predicted

3 of 21 rendered views carry no principal predicate, the starkest being
`SELECT people.* FROM people` with no `WHERE` at all. The `profiles` read that
was predicted to be the culprit comes out correctly restricted by `_MY_UID`.
And the string `*** UNRESTRICTED ***` exists nowhere in `src/`, `src_new/` or
`reports/` except as prose in `local_tags1/README.md:198` — no renderer emits
it; the real signature is an absent `_MY_UID`.

### Provenance and verification

`APP_TREE_PIN` measured equal before and after. `inventory/*.json`
byte-identical. `targets/` untouched (every mtime predates the drive).
`src_new/` `git status` clean — run-only honoured. `reports/autolab/test/run_tests.sh`
**75/75, ALL SUITES PASSED**. `pytest sweep` 1265 passed / 11 skipped / 0 failed.
Cost $7.24 of a $40 endpoint budget.

## Layout

```
drive.py                                       the six stages, retargeted from local_tags1
inputs/aspect_memberships_create_config.json   fixtures + real_mode_plan DECLARED, run limits raised
fixtures/aspect_memberships_create/world.json  amc-world-1: the declared database world (28 rows)
plan/real_mode_plan.json                       amc-real-1: nine scenarios, a principal, replay_callbacks
out/policy-1.json                              the IR, built from the approved packet's corpus
out/concrete_run.json                          THE RECORDING (written by --stage realmode)
state/*.json                                   one record per stage
logs/*.log                                     one log per stage
addendum_local.md                              THIS endpoint's operator addendum
tools/{app_tree_digest,build_policy_ir}.py
```

## What this drive changed from drive 7 (`local_tags1`), and why

Drive 7's mechanism is reused verbatim — the same `WorkerLayer.run(WorkRequest)`
seam, the same four §6.3 arguments, the same `recording=` / `app_config=`
mounts, the same `STATIC_ARGV`. The diff is the endpoint and four authored
inputs:

1. **`ENDPOINT` / `ENTRYPOINT`** and the campaign spec's three retargeted
   strings (`sweep`, the endpoint `name`, the `config` path).
2. **The config's run limits.** Raised from the scaffold's `MAX_RUNS=24
   TIME_BUDGET=300` to `1500 / 3000`, on a coordinator measurement recorded in
   the config's own `_note_run_limits_raised`. The two `limits` keys the
   checker actually enforces (`max_cliques`, `max_missing_per_clique`) are the
   scaffold's values UNTOUCHED — they shape the coverage verdict and moving
   them would be widening a policy, not setting a budget.
3. **The batch box's wall clock**, 5400 s → 10800 s. This endpoint's open
   question is a combination-coverage demand over 20 PC expressions, not a
   two-path corpus, and the declared-assumption gate it feeds has a 5400 s
   timeout of its own. `sweep_local_check.json` keeps its 14400 s. (The note
   lives here rather than in the spec because `sweep/spec.py::parse_spec`
   rejects unknown top-level keys — measured.)
4. **One stale paragraph deleted.** Drive 7 inherited drive 4's sentence that
   `fixtures` and `real_plan` "are both `null` on this endpoint, which is
   exactly why the gate is expected to BLOCK". That was already false on drive
   7, whose config declared both. `drive.py`'s docstring now says what is
   actually true here instead of carrying it a third time.

Everything claimed in `addendum_local.md` was measured against this tree on
2026-10-07 rather than inherited, and three of those re-measurements came out
the other way from the predecessor drive's prose (the target override, the
worklist's behaviour, and whether the corpus has statement content).

## The coordinator's own measurements, before any agent ran

These are what `addendum_local.md` §2–§4 hand to the batch agent, and they are
the reason this drive's open question is different from every previous drive's.

**The explorer** — three runs through
`entrypoints/scaffold/aspect_memberships_create/launch.sh`, dumps into scratch
(never into this drive's `batch/`, so nothing here shares provenance with a
coordinator probe):

| `MAX_RUNS` | runs | distinct paths | exploration elapsed | `worklist empty` | stack remaining |
|---|---|---|---|---|---|
| 24   | 24   | 23  | 3.2 s  | false | 237  |
| 400  | 400  | 181 | 21.9 s | false | 1706 |
| 1500 | 1500 | 403 | 56.8 s | false | still non-empty |

The worklist **grows**: every flip of a 16-PC path queues more seeds than it
consumes. There is no `MAX_RUNS` at which `worklist_exhausted` becomes true, so
it is not a target. `run_errors: {}` and `unflippable: 0` on all three.
Terminals at 1500 runs: `I18n::InvalidLocale` 112, `ActiveRecord::AssociationTypeMismatch`
151 — both real app outcomes, neither a framework wall.

**The engine's coverage layer**, over those three corpora at this config's own
`max_cliques=200 max_missing_per_clique=50`:

| corpus | `tree_complete` | `coverage_complete` | `missing_branches` | `truncated` |
|---|---|---|---|---|
| 23 runs  | false | false | 76  | true |
| 181 runs | **TRUE** | false | 100 | true |
| 403 runs | **TRUE** | false | 88  | true |

Tree completeness is cheap and arrives somewhere between 24 and 181 runs.
Combination coverage is not bought by runs at all — `missing_branches` does not
fall from 181 to 403, and it is `truncated` at both, so the number is a floor.
The cause is in the vocabulary: 20 distinct PC expressions, of which four are
the same `users.language` compare under four different prefix-relative variable
names (`…devise_user_first_1_language`, `…find_by_1_user_language`,
`…find_by_1_person_owner_language`, `assoc_person_owner_language`), with the
same doubling on `closed_account`. **So `assumptions.json` is this drive's
deliverable**, which it was on none of the previous drives.

**The corpus has real content**, which `tags_index`'s did not. Over 403 dumps:
5331 clean notes, 19 distinct statement shapes, and the DML is there —
`INSERT INTO "aspect_memberships"` in 76 of 403 dumps with no seeded replay
needed, plus `INSERT INTO "contacts"`, `UPDATE "contacts" SET … "receiving" = true`
and `UPDATE "notifications" SET … "unread" = false`. All six configured audits
return 0 over it, one of them (`cardinality_consistency_audit`) vacuously and
saying so itself.

## Ground truth is the coordinator's, and it is this drive's own

`inputs/aspect_memberships_create_config.json` declares both artefacts the
producer needs and may not invent (they are `null` in
`entrypoints/scaffold/aspect_memberships_create/config.json`, which is this
drive's input):

```
fixtures       = local_amc1/fixtures/aspect_memberships_create   (world_id amc-world-1)
real_mode_plan = local_amc1/plan/real_mode_plan.json             (plan_id  amc-real-1)
```

Neither is inherited. **The world** (`amc-world-1`, 28 rows) carries five users
spanning the measured three-arm `users.language` domain — `en` available and
uninflected, `pl` available AND inflected so `set_grammatical_gender` reads the
principal's profile, `xx` syntactically fine and absent from
`I18n.available_locales` so `I18n.locale=` raises — seven people (one owned by
the principal, one closed account, one blocked, one already contacted), seven
profiles, five aspects across three users, one receiving contact, one existing
membership, one block and one unread `Notifications::StartedSharing`.

**The plan** (`amc-real-1`) has nine scenarios and three structural features
neither predecessor plan had:

* a `principal` block, because this endpoint is `signed_in: true` with an
  unconditional `before_action :authenticate_user!`, resolved through devise's
  own `serialize_from_session` with the salt computed from the declared world
  (`encrypted_password[0,29]`) rather than queried for;
* `replay_callbacks: ["set_locale", "set_grammatical_gender"]` on **every**
  scenario. This is the one thing that was re-measured rather than inherited and
  that changed the plan's shape: `autolab_dse.rb:1102` replays exactly those two
  for a signed-in endpoint, so the corpus's `language == 'pl'` / `== 'xx'`
  decisions exist only because of them, and a plan that did not replay them
  would be recording a different execution from the one the corpus describes;
* an **empty** `frame_aliases`, which is where the dry run changed the plan.
  It first carried a cvd6-shaped entry mapping `ActiveRecord::FinderMethods#first`
  to `devise_user_first` inside `OrmAdapter::ActiveRecord#get`, sourced from this
  endpoint's own target layer
  (`targets/endpoints/aspect_memberships_create.rb:1205-1254`). The dry run
  measured that `FinderMethods#first` never appears as a real frame at all, so
  the entry was a no-op on a false premise and was removed. An alias from
  `find_by_sql` would have matched and was deliberately not written: five of the
  ten target functions the IR declares never appear as a real frame, because a
  mocked target's body never runs and so the corpus names the OUTER target while
  a real run names the innermost one. Repairing one instance would have been the
  coordinator choosing which cases of a five-case asymmetry the gate may report.

The write path is deliberately split across two scenarios rather than asserted
to work in one. `share_with` computes `needs_dispatch = !contact.receiving?`
and, on the dispatch arm, calls
`Diaspora::Federation::Dispatcher.defer_dispatch` — a Sidekiq push. Nothing in
the rig stubs it, because the probe runs the real method bodies and has no
mechanism for stubbing an arbitrary app class; that is what makes a recording
ground truth rather than a second model. So scenario 1 (new contact,
`needs_dispatch` true) carries the INSERTs, and scenario 2 (contact 100,
`receiving: true`, `needs_dispatch` false, no dispatcher) carries the
`notifications` UPDATE that sits after the dispatch in source order. Between
them every statement is recorded whichever way the push goes.

The world is **rebuilt from the document before every scenario**, outside the
capture window. On a read endpoint that is belt; here it is load-bearing —
scenario 2 inserts `(aspect 10, contact 100)` into `aspect_memberships`, and a
later scenario running on the leftover would hit that table's unique index
instead of issuing the INSERT.

## Provenance

`APP_TREE_PIN` = `916d393795a47b99d2128464ba268defb51524555bc26c659560575051501954`,
measured before the drive and again after; `app_revision`
`0760b6a22e113b74567330ff69ccc55a1d07022c`.

`runtime_revision` needs a sentence rather than a value. `src_new` HEAD was
`ee9f17bcddbc38285a0a2c2099831369b27b9f29` when this drive started and
`7951750cecc9334e794fda2312d85de541034db7` 23 minutes later, when a concurrent
commit published 6,471 previously-uncommitted insertions across 49 files --
among them the entire real-mode producer and the domain gate this drive runs.
No executed byte changed (every chain-critical file's mtime is 2026-10-07T18:40
or earlier, before the drive began, and the tree is clean), so the identifier
moved and the code did not. The defect is that `git rev-parse HEAD` cannot
identify running code in a tree with uncommitted work, that `ee9f17bc` does not
contain the real-mode stage at all, and that nothing verifies the field:
the pre-gate checks only `produced_with.app_tree_digest`
(`sweep/coordinator/pregate.py:691-716`). `local_tags1` recorded `ee9f17bc`
while running that same real-mode stage, so its provenance line has the same
flaw. See `addendum_local.md` §6.

The coordinator's three exploration probes wrote into a session scratch
directory, never into `layer/aspect_memberships_create/batch`, so no dump in
this drive's corpus shares a directory with a coordinator probe. Single
provenance holds by construction rather than by inspection.
