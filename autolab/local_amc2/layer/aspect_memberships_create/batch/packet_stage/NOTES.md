# aspect_memberships_create — local_amc2 (drive 9) batch-1 — NOTES

Config digest `f835fea0ad4f6be4daa59a07fd958f09ff960d3a329be8df9c7e46fe034932ad`.
Everything below was measured in this box on 2026-10-08 unless it says otherwise.

## 1. Corpus (417 dumps, all produced in this box, one provenance)

| batch | how | runs | dumps |
|---|---|---|---|
| run1 | default worklist, `MAX_RUNS=1500 TIME_BUDGET=3000`, via `launch.sh`, `DUMP_OUT=batch/run1` | 1500 | 403 |
| run2 | `EXTRA_SEEDS_JSON` = the 14 SAT witnesses coverage reported missing after §3's declarations (`batch/seeds_r2.json`), `SEEDS_ONLY=1`, `LABEL_SUFFIX=_cov2` | 14 | 14 |

The same 417 files are at the top level of `batch/` and in `dumps/`. No other
process wrote into `batch/` (the coordinator's probe used its own scratch dir).

run1 printed `[am_create] AspectMembershipsTargets installed` and
`[am_create devise] AmDeviseUserNaming installed` and no "no target override"
line. It recorded `run_errors: {}`, `unflippable: 0 distinct PC shapes`,
`worklist empty: false`, 55.1 s of exploration. These numbers match the
coordinator's probe (1500 / 403 / false / {} / 112 / 151 / 0). The worklist is
not empty because the path space grows as you explore it. More runs would not
change that. run2: `worklist empty: true`, `terminals: {}`, no run errors.

**No `SELECT "blocks".*` in the corpus.** I grepped all 403 run1 dumps for the
whole-collection blocks read and found 0, so the interceptor `.equal?` fix
(§0 of the addendum) holds here.

Terminals in run1. Both are app outcomes, not walls:
* `I18n::InvalidLocale` ×112: the principal's `users.language == 'xx'`.
  `set_locale` calls `I18n.locale=`, which raises in
  `enforce_available_locales!`, so the request ends before the action body.
* `ActiveRecord::AssociationTypeMismatch` ×151: `Aspect expected, got nil`.
  When `current_user.aspects.where(id:).first` finds nothing
  (`first_1_not_found`), `share_with(@person, nil)` does
  `contact.aspects << nil`. That is the real app's behaviour for an
  `aspect_id` the principal does not own.

## 2. Coverage (engine `CoverageChecker`, config limits `max_cliques=200 max_missing_per_clique=50`)

Declarations were built through `concolic.assumptions.declared.declared_assumption_set`,
the same wire `check.py::_coverage_assumptions` uses. Script: `batch/cov.py`.

| corpus | declared | tree_complete | coverage_complete | missing | truncated | solver_lost |
|---|---|---|---|---|---|---|
| run1 (403) | none | true | false | 88 | true | 0 |
| run1 (403) | the 6 below | true | false | 14 | false | 0 |
| run1+run2 (417) | none | true | false | 82 | true | 0 |
| run1+run2 (417) | the 6 below | **true** | **true** | **0** | false | 0 |

The 14 leaves left after declaring were not licensed away. Each is a SAT
witness the solver produced, and each was DRIVEN (run2) and is in the corpus.
**`coverage_complete: true` here means "complete GIVEN these 6
declarations".** It is worth only what the assumption gate's verdict on them
is worth (§4).

## 3. What is declared, and why (`assumptions.json`, 6 × `UntrackedPathAssumption`)

**Carried from drive 8** (`local_amc1/.../out/packet/assumptions.json`). The
`type`, `source`, `expr` and `description` are unchanged. `agent_notes` was
rewritten to cite THIS corpus's evidence. No new declarations were added.

The 20 distinct PC expressions include three copies of the `users.language`
three-arm compare (`== 'pl'`, `== 'xx'`, else `en`) on users who are NOT the
principal:
* `SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_user_language`: `contact.user`
* `SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_owner_language`: `contact.person.owner`
* `assoc_person_owner_language`: `@person.owner`, before a contact row exists

All of them are recorded by `AspectMembershipsTargets#symbolic_instance` when
a `User` row is instantiated. I re-checked
`targets/endpoints/aspect_memberships_create.rb:536-547`: line 540 is
`attrs["language"] = if lang == "pl"` and line 542 is `elsif lang == "xx"`.
The compare only concretizes the attribute.

**Evidence, from this corpus** (`batch/sib2.py`, outputs `batch/sib2.out`
for 403 dumps and `batch/sib2_417.out` for 417). I grouped runs by their PC
sequence with that variable's language compares removed. Within each group I
took every pair whose language ARM differs and compared access traces
(`concolic.corpus.load.access_trace`):

| variable | pairs (en/pl, en/xx, pl/xx) | traces differ |
|---|---|---|
| find_by_1_user_language | 264 (88/88/88) | 0 |
| find_by_1_person_owner_language | 264 (88/88/88) | 0 |
| assoc_person_owner_language | 54 (18/18/18) | 0 |

**Deliberately NOT declared:** the PRINCIPAL's language
(`devise_user_first_1_language`). en vs pl changes the trace in 169 of 169
pairs at 403 dumps, and in 180 of 180 at 417. With 'pl',
`set_grammatical_gender` adds `SELECT "people".* … WHERE "people"."owner_id" = ?`
and `SELECT "profiles".* … WHERE "profiles"."person_id" = ?`. With 'xx' the
run hits the InvalidLocale terminal. This is a real decision. Its combinations
were explored (run2), not licensed.

**The other doublings the brief names are not declared.** `closed_account`
appears as `assoc_person_closed_account` and as
`…find_by_1_person_closed_account`, and the self-contact identity compare also
appears under two names. Each pair is one column reached on two different
code paths: contact row absent (`assoc_person_*`) vs present (`find_by_1_*`).
The two are never evaluated in the same run, so there is no combined demand
to prune. Once the language copies are untracked, the remaining demand is
14 leaves and run2 drives all of them. A further licence would prune nothing.

## 4. Assumption gate, run LOCALLY before submission

I ran `assumption_cmd`'s checker (`src_new/concolic/gate/assumption_checker.py`
manifest `--declared assumptions.json`, venv python, the config's `env`) with THIS
packet's `assumption_manifest.json` and `assumptions.json`. It ran with cwd set to
a mirror box `/tmp/amc2_chkbox`, whose `in/packet/dumps` holds a copy of the same
417 dumps, so `batch_dir` resolved exactly as it will on the check box. Result:

    RESULT: 6 distinct tested — PASS 6, FAIL 0, ERROR 0, NOT-TESTABLE 0, NOT-COMPARABLE 0, OUTSTANDING 0

Every row reads `[8 base(s) probed, 8 realising; 4-5 witness(es)/1 scenario(s),
floor 3 of 4-5 available; PASS=8] access trace identical on both sides`. Stage 1:
6 of 6 probes matched. Stage 2: 41 of 41 matched (34 of them replayed singly).
Every probe dump was globbed from `/tmp/amc2_achk_dumps` through the manifest's
`workdir`, so the manifest's runner really re-drives this batch. The seed file
was written there too, not into the packet. The mirror box still held exactly
417 dumps afterwards. Logs: `batch/local_gate.log` and
`batch/local_gate_results.json`. **This is my run, not the check's. The
verdict that counts is the check box's.** The gate also tests the
coverage-inferred set on the check box; this local run tested the 6 declared
records only.

## 5. Escalation `manifest-workdir` (class local): ANSWERED, plan approved, defect stands

The coordinator answered (`ctl/answer/manifest-workdir.json`): *"YOUR
READING IS CORRECT AND YOUR PLAN IS APPROVED"*. The answer says §9's "no
workdir key" sentence conflated the COMPLETION config (whose `workdir` must stay
absent) with the ASSUMPTION CFG (where `workdir` is a documented key). Cite
that answer, not the addendum. **The `_dump_dirs` narrowness is still an open
shared-tier defect**, and the coordinator asked that it stay standing. A shell
launcher plus a manifest with no workdir gives the probes no glob directory,
so every probe silently finds nothing. No `src_new` edit was made.

Operator addendum §9 says the manifest should carry no `workdir`.
`concolic/gate/replay.py::_dump_dirs` (src_new 70bca8e, lines 216-235)
globs probe dumps only in three places: `batch_dir`, the dirname of each
`.rb` token in `runner`, and `workdir` (default `.`). The runner is
`launch.sh` and has no `.rb` token. So without a workdir, a probe's dumps
land somewhere nothing globs:
* with `DUMP_OUT` set to any absolute dir, that dir is not globbed;
* with `DUMP_OUT` unset, the dumps land in the SHARED scaffold dir, which is
  not globbed either.

The checker reads `batch_dir` relative to its own cwd and never chdirs. The
manifest `workdir` only becomes the probe subprocess's cwd, the seed-file
directory and a glob dir, so it cannot reproduce the attempt-1 failure §9
cites (that came from the COMPLETION config's `workdir`). I therefore used
drive 8's arrangement: `workdir` and `env.DUMP_OUT` both set to
`/tmp/amc2_achk_dumps`. That directory exists on this host, and the check box
is on this host. With that arrangement, drive 8's rows PASSED on the check box.

## 6. Audits (the config's six `audit_cmds`, over `batch/`, 417 dumps). All exit 0. That is five checks and one vacuity.

* `statement_note_lint`: 4749 clean notes; 0 NO-WHERE, 0 STAR-PLUCK,
  0 STAR-AGGREGATE. No red-level findings. JUNK (warn): 1858 events,
  4 distinct. I checked each one against the target layer myself:
  * `User#blocks` (754). Declared `kind: SHIM` at
    `targets/endpoints/aspect_memberships_create.rb:317-321` (§1). Its body
    is `receiver.association(:blocks).reader`, which builds an AR
    CollectionProxy and issues no SQL. The access happens at the downstream
    `exists?` TARGET (`SELECT 1 AS one FROM "blocks" …`). This shim appears
    note-less, with no whole-collection SELECT, which is the 2026-10-08
    interceptor fix working.
  * `ActionController::Rendering#_set_rendered_content_type` (754).
    `core.rb:2084-2092` (W4), a SHIM no-op. The real method sets the response
    content-type header and issues no SQL.
  * `ActionController::Metal#status=` (302). `core.rb:1894-1901` (Y1), a SHIM.
    The real method writes the response status and issues no SQL.
  * `Diaspora::Federation::Dispatcher.defer_dispatch` (48). `shared_shims.rb:58-106`,
    redeclared at `targets/endpoints/aspect_memberships_create.rb:398-400`.
    The real body (`lib/diaspora/federation/dispatcher.rb:23-25`) is
    `Workers::DeferredDispatch.perform_async(sender.id, object.class.to_s, object.id, opts)`:
    a job enqueue with no SQL.
  * Not a JUNK note, but recorded here: the endpoint layer documents
    (lines 389-396) that shimming `User#deliver_profile_update` (called from
    `connecting.rb:26` `unless person.local?`) elides a `self.profile`
    association read the real code would perform. That cost is already known
    and written in the file. I did not escalate it as new.
* `noteless_call_audit`: 6607 target-call events. Every note-less call is a
  declared shim (the same four). Pass.
* `exception_note_audit`: 0 notes captured an exception. The audit samples:
  it scanned 150 of the 417 dumps. Pass.
* `empty_relation_emission_audit`: 0 empty-list states. Pass.
* `cardinality_consistency_audit`: **pass but VACUOUS.** In its own words:
  *"this corpus contains no bulk loader reading a list's own rows, so the rule
  was never applied. Absence of the subject is not evidence about it; do not
  count this as a check that passed."*
* `identity_symbolicity_audit`: every principal bind is symbolic. Pass.

Full output: `batch/audits.log`.

## 7. Shim gate (`shim_tests.rb`)

**Provenance.** Carried over from drive 8's
`local_amc1/.../out/packet/shim_tests.rb` (sha256 `af94ef76…`), itself
local_tags1's file. Only the header comment changed, and a diff of everything
from the `# Keys are EXACTLY` line down is empty.

The extractor (`extract_cmd`'s argv, run with `LANG=C.UTF-8`) emits
22 entries with 22 distinct keys, the same set as before.

**Run in this box** with `test_cmd`'s runner (`scripts/diaspora-concolic
shim_test_runner.rb`, `JRUBY_OPTS=--debug`): **PASS 10, PROTOCOL 12,
FAIL 0** (`batch/shim_results.json`).

A PROTOCOL row is not a pass. It means the runner classified the key as
runtime representation machinery that has no app body to run against
(`shim_test_runner.rb` `machinery?`). The 12 rows are `read_attribute`,
`_read_attribute`, `concolic_attrs`, `concolic_note`, `attributes`,
`concolic_dirty`, `write_attribute`, `_write_attribute`, `inspect`,
`persisted?`, `new_record?`, and `obj.post_location`. For `post_location` the
runner said `Post#post_location is defined by the AR/Ruby protocol — verified
against the real class`. The file's header still describes `post_location`
as carrying an entry. The runner's verdict is PROTOCOL regardless, so that
entry is never exercised. Whether the gate counts PROTOCOL as blocking is the
gate's decision.

## 8. Domain gate: not mine. Expected findings, not suppressed.

I did not write a `concrete_run.json` or anything resembling a recording. The
corpus has these DML statements: INSERT `aspect_memberships`, UPDATE
`notifications`, UPDATE `contacts` (`receiving = true`) and INSERT
`contacts`. The fold emits SELECT views only, so a `_create` endpoint's policy
cannot name what it writes. I expect `shape_check` to report that. I also
expect it to report frame attribution (mocked outer target vs innermost real
frame) and any view missing the principal column. Those are real findings
and nothing here suppresses them.

## 9. produced_with

`runtime_revision` 70bca8e0… is `git rev-parse HEAD` in `src_new`, and that
tree had a clean `git status`. Nothing verifies this field. `app_revision`
0760b6a2…. `app_tree_digest` 916d3937…954: I ran
`local_amc2/tools/app_tree_digest.py` myself and it matches.
