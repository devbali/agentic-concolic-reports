# aspect_memberships_create — local_amc1 batch-1 — NOTES

Config digest `3c17dcb967e9806a2f14e2f21f1c83e9a76a05ab8994992571cbb85dd48e7ecf`.
Everything below was measured in this box on 2026-10-08 unless it says otherwise.

## 1. Corpus (417 dumps, all produced in this box, one provenance)

| batch | how | runs | dumps |
|---|---|---|---|
| run1 | default worklist, `MAX_RUNS=1500 TIME_BUDGET=3000`, via `launch.sh`, `DUMP_OUT=batch/run1` | 1500 | 403 |
| run2 | `EXTRA_SEEDS_JSON` = the 14 SAT witnesses coverage reported missing after §3's declarations, `SEEDS_ONLY=1`, `LABEL_SUFFIX=_cov2` | 14 | 14 |

The same 417 files are at the top level of `batch/` and in `dumps/`.
run1 printed `[am_create] AspectMembershipsTargets installed` and
`[am_create devise] AmDeviseUserNaming installed`. It recorded `run_errors: {}`,
`unflippable: 0 distinct PC shapes` and `worklist empty: false` (stack 2728).
The worklist is not empty because the path space grows; that is not a budget
problem. run2 recorded `worklist empty: true`, `terminals: {}` and no run errors.

Terminals in run1 (both are app outcomes, not walls):
* `I18n::InvalidLocale` ×112: `"xx" is not a valid locale`, raised by
  `I18n.enforce_available_locales!` from `I18n.locale=` in `set_locale`. The
  principal's `users.language` is outside the available locales, so the
  request ends before the action body. In the dumps this is the
  `devise_user_first_1_language == 'xx'` arm (2 PCs).
* `ActiveRecord::AssociationTypeMismatch` ×151: `Aspect expected, got nil`,
  raised by `association.rb:246 raise_on_type_mismatch!`. When
  `current_user.aspects.where(id:).first` finds nothing (`first_1_not_found`),
  `share_with(@person, nil)` does `contact.aspects << nil`. That is the real
  app's behaviour for an `aspect_id` the principal does not own.

## 2. Coverage (engine `CoverageChecker`, the config's `max_cliques=200 max_missing_per_clique=50`)

| corpus | declared | tree_complete | coverage_complete | missing | truncated | solver_lost |
|---|---|---|---|---|---|---|
| run1 (403) | none | true | false | 88 | true | 0 |
| run1 (403) | the 6 below | true | false | **14** | **false** | 0 |
| run1+run2 (417) | none | true | false | 82 | true | 0 |
| run1+run2 (417) | the 6 below | **true** | **true** | **0** | false | 0 |

So with the 6 declarations the corpus covers every remaining combination. The
14 left after declaring were not pruned away. Each is a SAT witness the solver
produced, and each was DRIVEN (run2) and is in the corpus.

## 3. What is declared, and why (`assumptions.json`, 6 × `UntrackedPathAssumption`)

The 20 distinct PC expressions include three copies of the `users.language`
three-arm compare (`== 'pl'`, then `== 'xx'`, else `en`) on users who are not
the principal:
* `SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_user_language`: `contact.user`
* `SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_owner_language`: `contact.person.owner`
* `assoc_person_owner_language`: `@person.owner` before a contact row exists

`AspectMembershipsTargets#symbolic_instance` records all of them when a `User`
row is instantiated (`targets/endpoints/aspect_memberships_create.rb:538-546`).
It only concretizes the attribute.

**Evidence.** I grouped the corpus runs by their PC sequence with that
variable's language compares removed. Within each group I took every pair
whose language ARM differs and compared access traces
(`concolic.corpus.load.access_trace`):

| variable | pairs (en/pl, en/xx, pl/xx) | traces differ |
|---|---|---|
| find_by_1_user_language | 264 (88/88/88) | 0 |
| find_by_1_person_owner_language | 264 (88/88/88) | 0 |
| assoc_person_owner_language | 54 (18/18/18) | 0 |

That is exactly the gate's `UntrackedPathAssumption` test: flip the variable,
and the access trace must be identical. Script: `batch/sib2.py`.

**Deliberately NOT declared:** the PRINCIPAL's language
(`devise_user_first_1_language`). en vs pl changes the trace in 169 of 169
pairs. 'pl' adds `SELECT "people".* … WHERE "people"."owner_id" = ?` and
`SELECT "profiles".* … WHERE "profiles"."person_id" = ?`, which is
`set_grammatical_gender` reading the profile gender for a gendered locale.
'xx' is the InvalidLocale terminal. This is a real decision and it stays in
the universe; its combinations were explored (run2), not licensed.

No `IndependenceAssumption` or `AliasAssumption` is declared. Once the three
language copies are untracked, the remaining demand is 14 leaves, and run2
drives all of them, so a further licence would prune nothing that needs
pruning. Declaring one anyway would only add an unneeded licence. The other
doubling the operator brief names (`closed_account` and the self-contact
identity compare, each under two names) is NOT the same decision twice. It
is the same column reached on two different code paths: contact row present
(`find_by_1_*`) vs absent (`assoc_person_*`). The two are never evaluated in
one run, so they carry no combined demand.

## 4. Assumption gate, run LOCALLY on this packet before submission

I ran `assumption_cmd`'s checker (`src_new/concolic/gate/assumption_checker.py`)
with THIS packet's `assumption_manifest.json` and `assumptions.json`. I ran it
over a writable copy of `dumps/` at `<tmpbox>/in/packet/dumps`, with cwd at
that tmp box root, to mirror the check box's layout. Result:

    RESULT: 6 distinct tested — PASS 6, FAIL 0, ERROR 0, NOT-TESTABLE 0, NOT-COMPARABLE 0, OUTSTANDING 0

Every row reads `[8 base(s) probed, 8 realising; 4-5 witness(es)/1 scenario(s),
floor 3 of 4-5 available; PASS=8] access trace identical on both sides`. Stage
1 found 6 of 6 probe dumps and stage 2 found 40 of 40 (34 replayed singly, one
boot each, about 25 min), all through `workdir`/`DUMP_OUT=/tmp/amc1_achk_dumps`.
So the manifest's runner really re-drives this batch. Full log:
`batch/local_gate.log` and `batch/local_gate_results.json`. That is my run,
not the check's. The verdict that counts is the check box's.

The first local attempt used the `.rb`-token workaround from my escalation.
I stopped it (and its one orphaned probe JVM, matched on the absolute token
path) when the coordinator's answer arrived, and re-ran from clean with the
final manifest. No probe dump from either attempt is in `dumps/`.

## 5. Escalation `manifest-dump-dir` (class shared). ANSWERED, and the defect stands

`concolic/gate/replay.py::run_probe` writes its seed file INTO `batch_dir`
(replay.py:251-252). It globs probe dumps only in `_dump_dirs` = `batch_dir` +
dirname of each `.rb` token of `runner` + `workdir`-or-`.`. The brief requires
`batch_dir = in/packet/dumps`, which is a read-only mount by convention. On
this host backend the mounts are symlinks, so the seed write succeeds here.
**On any backend with real filesystem isolation, every probe would raise at
the seed-file write. The defect is latent, not firing here.** The coordinator
confirmed it as a shared-tier defect and did not fix it. As the coordinator
directed, the assumption cfg sets `workdir` and `env.DUMP_OUT` to
`/tmp/amc1_achk_dumps` (created before submission). That `workdir` is the
ASSUMPTION CFG's and is unrelated to the completion config's forbidden
`workdir`. The manifest's `_note_workdir` key says so.

## 6. Audits (the config's six `audit_cmds`, over `batch/`, 417 dumps)

* `statement_note_lint`: 5503 clean notes, no red-level findings. JUNK
  (warn): 1858 events, 4 distinct. I checked each one against the target
  layer myself:
  * `User#blocks` (754): declared `kind: SHIM` in
    `targets/endpoints/aspect_memberships_create.rb` §1. It returns
    `receiver.association(:blocks).reader`, an AR CollectionProxy, which issues
    no SQL. The access is at the downstream `exists?` TARGET, which carries a
    `SELECT 1 AS one FROM "blocks" …` note.
  * `ActionController::Rendering#_set_rendered_content_type` (754): `core.rb`
    W4 (line 2084), a SHIM no-op. The real body sets the response content-type
    header and issues no SQL.
  * `ActionController::Metal#status=` (302): `core.rb` Y1 (line 1894), a SHIM.
    The real body sets the response status and issues no SQL.
  * `Diaspora::Federation::Dispatcher.defer_dispatch` (48): `shared_shims.rb:58-106`,
    redeclared in the endpoint layer at line 398, a SHIM. The real body enqueues
    a federation job, so there is no SQL on this request.
* `noteless_call_audit`: 7361 target-call events. Every note-less call is a
  declared shim (the same four). Pass.
* `exception_note_audit`: 0 notes captured an exception (150 of 417 dumps
  scanned, the audit's own sample). Pass.
* `empty_relation_emission_audit`: 0 empty-list states. Pass.
* `cardinality_consistency_audit`: **pass but VACUOUS.** The audit's own
  words: *"this corpus contains no bulk loader reading a list's own rows, so
  the rule was never applied. Absence of the subject is not evidence about it;
  do not count this as a check that passed."* So six green audits are five
  checks and one vacuity.
* `identity_symbolicity_audit`: every principal bind is symbolic. Pass.

## 7. Shim gate (`shim_tests.rb`)

Keys: `shim_extractor.rb targets/core.rb targets/shared_shims.rb` gives the
22 keys, the same set as prior drives. **Finding:** the extractor CRASHES
under the default US-ASCII locale (`shim_extractor.rb:35 scan: invalid byte
sequence in US-ASCII`). It needs `LANG/LC_ALL=C.UTF-8`. The completion
config's `env` sets no locale, so whether `extract_cmd` works on the check
box depends on the inherited environment. Not escalated as a boundary
change, because it is config/env and the coordinator owns it; noted here.

Provenance: the bodies are carried verbatim from
`local_tags1/boxes/tags_index-batch-1-acf20787/out/packet/shim_tests.rb`
(sha256 `25015e76…`), which was itself carried from local_cvd4 and local_cc.
Only the header comment changed. I re-ran it in THIS box with the config's
`test_cmd` (`diaspora-concolic shim_test_runner.rb`, `JRUBY_OPTS=--debug`):
**10 PASS, 12 PROTOCOL, 0 FAIL/ERROR** (`batch/shim_results.json`).

## 8. Domain gate: not mine, and an expected finding

I wrote no `concrete_run.json`; the fixtures and real-mode plan are the
coordinator's. Expect the policy render to show `SELECT "profiles".* FROM
"profiles" WHERE "profiles"."person_id" = ?`, a foreign-key predicate with no
principal column. Here it comes from `set_grammatical_gender` on the
principal's own person (the 'pl' arm; measured: the read is absent from the
en arm's runs). If the render reports it as unrestricted, that is a true statement about the
corpus. I did not try to change it.

## 9. Provenance

`runtime_revision ee9f17bcddbc38285a0a2c2099831369b27b9f29` (src_new HEAD),
`app_revision 0760b6a22e113b74567330ff69ccc55a1d07022c`, and
`app_tree_digest 916d393795a47b99d2128464ba268defb51524555bc26c659560575051501954`
(re-run `local_amc1/tools/app_tree_digest.py` in this box). All three match
the operator brief. I edited nothing under the app, `src_new/` or `targets/`.
