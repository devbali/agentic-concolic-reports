# aspect_memberships_create — local_amc3 (drive 10) batch-1 — NOTES

Config digest `7995d56e4ccddc57b130d2b2d52e67921f25793252db3c42eee6a6499f8ec925`.
Everything below was measured in this box on 2026-10-14 unless it says otherwise.
This was the first attempt; there was no `denials.json` or `response.json`.

## 1. Corpus (417 dumps, all produced in this box, one provenance)

| batch | how | runs | dumps |
|---|---|---|---|
| run1 | default worklist, `MAX_RUNS=1500 TIME_BUDGET=3000`, via `launch.sh`, `DUMP_OUT=batch/explore1` | 1500 | 403 |
| run2 | `EXTRA_SEEDS_JSON` = the 14 SAT witnesses that coverage reported missing under §3's declarations (`batch/seeds_r2.json`), `SEEDS_ONLY=1`, `LABEL_SUFFIX=_cov2` | 14 | 14 |

The same 417 files are at the top level of `batch/` and in `dumps/`.

There was one false start. My first run2 passed the seed JSON *content* in
`EXTRA_SEEDS_JSON`, but the driver reads it as a FILE PATH
(`entrypoints/lib/autolab_dse.rb:1118`). So that launch drove only the default
seed (1 run). I deleted its directory before any of its dumps were copied
anywhere, then re-ran with the path. The 14 seeds are the same set drive 9
derived (I compared the canonicalized sets and they match).

**run1** printed `[am_create] AspectMembershipsTargets installed` and
`[am_create devise] AmDeviseUserNaming installed`. It did not print "no target
override". Its numbers were 1500 runs, 403 distinct paths, `worklist empty:
false`, 51.0 s, `run errors: {}`, `unflippable: 0`, and terminals
`{"I18n::InvalidLocale"=>112, "ActiveRecord::AssociationTypeMismatch"=>151}`.
Those match the addendum §3 measurement exactly. `worklist empty: false`
reflects the path space growing as it is explored, not the budget.
**run2**: 14 runs, 14 paths, `worklist empty: true`, no terminals, no errors.

**No `SELECT "blocks".*` anywhere in the 417 dumps (0 files).** The narrow
`SELECT 1 AS one FROM "blocks" … LIMIT 1` is in 414 dumps. So the interceptor
`.equal?` fix held for this corpus.

DML in the corpus (file counts): INSERT `aspect_memberships` 76, UPDATE
`notifications` 76, UPDATE `contacts` (`receiving = true`) 64, INSERT
`contacts` 12.

Both terminals are app outcomes, not walls:
* `I18n::InvalidLocale` ×112. The principal has `users.language == 'xx'`.
  The `set_locale` before-action assigns `I18n.locale`, which raises in
  `enforce_available_locales!` before the action body runs.
* `ActiveRecord::AssociationTypeMismatch` ×151 ("Aspect expected, got nil").
  `current_user.aspects.where(id:).first` finds nothing (`first_1_not_found`),
  and `share_with(@person, nil)` then does `contact.aspects << nil`. That is
  the real app's behaviour for an `aspect_id` the principal does not own.

## 2. Coverage (engine `CoverageChecker`, `max_cliques=200 max_missing_per_clique=50`)

I built the declarations through `concolic.assumptions.declared.declared_assumption_set`,
which is the wire `check.py` uses. The script is `batch/cov.py`, carried over
from drive 9.

| corpus | declared | tree_complete | coverage_complete | missing | truncated | solver_lost |
|---|---|---|---|---|---|---|
| run1 (403) | none | true | false | 88 | true | 0 |
| run1 (403) | the 6 below | true | false | 14 | false | 0 |
| run1+run2 (417) | none | true | false | 82 | true | 0 |
| run1+run2 (417) | the 6 below | **true** | **true** | **0** | false | 0 |

The 14 leaves left over after declaring were not licensed away. They were
DRIVEN (run2) and are in the corpus. **`coverage_complete: true` means
"complete GIVEN these 6 declarations"**, so it is worth only what the
assumption gate's verdict on them is worth (§4). The demand that the
combination universe adds is the language compare counted four times under
four names (addendum §4). The 6 declarations address the three non-principal
copies. The principal's copy is explored.

## 3. Declared: 6 × `UntrackedPathAssumption`, carried from drives 8/9, re-evidenced here

`type`, `source`, `expr` and `description` are unchanged from
`local_amc2/.../out/packet/assumptions.json`. `agent_notes` was rewritten to
cite this corpus. No records were added or dropped. The compare sits at
`targets/endpoints/aspect_memberships_create.rb:540/542`
(`if lang == "pl"` / `elsif lang == "xx"`) in `symbolic_instance`, and only
concretizes the attribute.

Evidence is `batch/sib2.py` (from drive 9), with output in `batch/sib2.out`
(403) and `batch/sib2_417.out` (417). Runs are grouped by their PC sequence
with that variable's language compares removed. For every pair in a group
whose arm differs, the access traces are compared:

| variable | pairs (en/pl, en/xx, pl/xx) | traces differ |
|---|---|---|
| find_by_1_user_language | 264 (88/88/88) | 0 |
| find_by_1_person_owner_language | 264 (88/88/88) | 0 |
| assoc_person_owner_language | 54 (18/18/18) | 0 |

**Deliberately NOT declared: the PRINCIPAL's language**
(`devise_user_first_1_language`). Flipping en vs pl changes the trace in
169/169 pairs at 403 dumps and 180/180 at 417: with 'pl',
`set_grammatical_gender` adds the `people` and `profiles` reads, and 'xx'
ends in the InvalidLocale terminal. Its combinations were explored, not
licensed. The `closed_account` and self-contact doublings are not declared
either. Each is one column reached on two mutually exclusive paths (contact
row absent vs present), so no run evaluates both and there is no product
demand to prune.

## 4. Assumption gate, run LOCALLY under the NEW arrival rule (engine 4ff15f8f…, rev 962acb01)

This is the question this drive exists for (addendum §0): **do the flips
arrive?** **Yes, on every base.** I ran `assumption_cmd`'s checker with the
venv python and the config's env, with cwd = a mirror box `/tmp/amc3_chkbox`
whose `in/packet/dumps` is a copy of the same 417 dumps, so `batch_dir`
resolves as it will on the check box. It used this packet's
`assumption_manifest.json` and `assumptions.json`. Result
(`batch/gate_results.json`, log `batch/logs/gate.log`):

    RESULT: 6 distinct tested — PASS 6, FAIL 0, ERROR 0, NOT-TESTABLE 0, NOT-COMPARABLE 0, OUTSTANDING 0

Every row: `bases_probed 8, bases_realising 8, bases_passing 8`, witnesses 4
or 5 against a floor of 3, `access trace identical on both sides`. Stage 1
matched 6/6. Stage 2 matched 41/41 (40 in one launch, then 1). No row is
NOT-TESTABLE/NOT-REALISED, so none of these PASSes rests on a non-arriving
probe. **This is my run, not the check's. The check box's verdict is the one
that counts**, and the check also tests the coverage-inferred set, which this
local run did not.

**Manifest change vs drive 9: `env.MAX_RUNS=1500`, `env.TIME_BUDGET=3000`**
(this config's own `scenarios.auth_json` values). Without them the probe
runner falls back to its defaults (MAX_RUNS=6 / TIME_BUDGET=600). A
SEEDS_ONLY batch of 40 roots then drives only 6, and the other 34 are replayed
one Rails boot at a time. I measured that in my first local gate run
(`batch/logs/gate_attempt1_killed.log`, `batch/gate_results_attempt1.json`):
PASS 6, same 8/8 realising, but "40 roots -> 6 dumps, 34 replayed singly",
and about 18 min of wall clock against a 5400 s `assumption_timeout` on a
shared machine. (That run had already finished on its own when I went to stop
it; my `kill` hit no process. Its results are kept.) With the env set, the
same 40 roots ran in one launch, so the submitted manifest is the one that was
tested. SEEDS_ONLY still restricts each probe launch to exactly the gate's
roots.

`workdir` and `env.DUMP_OUT` are both `/tmp/amc3_achk_dumps`, which I created
on this host (the check box's host). This is drive 8/9's arrangement, per the
coordinator's answer to drive 9's ticket `manifest-workdir`. After the gate
the mirror still held exactly 417 dumps, so nothing was written into the
packet copy.

## 5. Escalation `dump-dirs-narrow` (class shared). No answer at submission.

As the addendum §9 asks, I re-raised the shared-tier defect in
`concolic/gate/replay.py::_dump_dirs`. It globs only `batch_dir`, the dirname
of `.rb` runner tokens, and `workdir`. With a shell launcher and no workdir,
every probe silently finds nothing. I did not patch it. The manifest works
around it as described in §4. No answer had arrived when I submitted, and none
was needed for this packet.

## 6. Audits (the config's six `audit_cmds` over `batch/`, 417 dumps). All exit 0: five checks and one vacuity.

* `statement_note_lint`: 4749 clean notes; 0 NO-WHERE, 0 STAR-PLUCK,
  0 STAR-AGGREGATE. No red-level findings. JUNK (warn): 1858 events, 4 distinct.
  I checked each one against the target layer in this box:
  * `User#blocks` (754). `targets/endpoints/aspect_memberships_create.rb:297-321`
    declares it `kind: SHIM`, with body `receiver.association(:blocks).reader`:
    it builds a CollectionProxy and issues no SQL. The access is at the
    downstream `exists?` TARGET (`SELECT 1 AS one FROM "blocks" …`, 414 dumps).
    It shows up note-less and with no whole-collection SELECT, which means the
    interceptor fix is working.
  * `ActionController::Rendering#_set_rendered_content_type` (754).
    `core.rb:2084-2092` (W4), a SHIM no-op. The real method sets the
    content-type header and issues no SQL.
  * `ActionController::Metal#status=` (302). `core.rb:1894-1901` (Y1), a SHIM.
    The real method writes the response status and issues no SQL.
  * `Diaspora::Federation::Dispatcher.defer_dispatch` (48). `shared_shims.rb:58-106`,
    redeclared at `targets/endpoints/aspect_memberships_create.rb:386-400`. The
    real body (`lib/diaspora/federation/dispatcher.rb:23-25`) is
    `Workers::DeferredDispatch.perform_async(...)`, a job enqueue with no SQL.
* `noteless_call_audit`: 6607 target-call events. Every note-less call is one
  of those 4 declared shims. Pass.
* `exception_note_audit`: no note captured an exception. It samples, and
  scanned 150 of 417. Pass.
* `empty_relation_emission_audit`: 0 empty-list states. Pass.
* `cardinality_consistency_audit`: **pass but VACUOUS.** In its own words:
  *"this corpus contains no bulk loader reading a list's own rows, so the rule
  was never applied. Absence of the subject is not evidence about it; do not
  count this as a check that passed."*
* `identity_symbolicity_audit`: every principal bind is symbolic. Pass.

Full output: `batch/audits.log`.

## 7. Shim gate (`shim_tests.rb`)

**Provenance:** drive 9's file (sha256 `93b9555f…`), which was drive 8's and
before that local_tags1's. Only the header changed. A diff from the
`# Keys are EXACTLY` line down is empty. `extract_cmd` (run with
`LANG=C.UTF-8`) emits 22 entries with 22 distinct keys, the same set as
before. I ran `test_cmd`'s runner in this box (`JRUBY_OPTS=--debug`):
**PASS 10, PROTOCOL 12, FAIL 0** (`batch/shim_results.json`). A PROTOCOL row is
not a pass. It means the runner classified the key as runtime representation
machinery with no app body to run against: `read_attribute`,
`_read_attribute`, `concolic_attrs`, `concolic_note`, `attributes`,
`concolic_dirty`, `write_attribute`, `_write_attribute`, `inspect`,
`persisted?`, `new_record?`, and `obj.post_location`. The file has an entry for
`post_location`, but the runner says PROTOCOL ("verified against the real
class"), so that entry is never exercised. Whether PROTOCOL blocks is the
gate's call.

## 8. Domain gate: not mine. Expected findings, not suppressed.

I did not write a `concrete_run.json` or anything resembling a recording. The
corpus writes (INSERT `aspect_memberships`, UPDATE `notifications`, UPDATE
`contacts`, INSERT `contacts`), but the fold emits SELECT views only, so a
`_create` endpoint's policy cannot name what it writes. Expect `shape_check`
and `principal_restriction_check` to report that, frame attribution, and any
view without the principal column. These are real findings.

## 9. produced_with

* `runtime_digest` `4ff15f8f8fee8ceb1c84f9206fd50d8b47b56133d9392a3ff2e0b8d6a153c9d0`:
  `python3 -m sweep.engine_digest`, measured at the start and again just
  before packing, with the same value both times. `--json` reports
  `dirty: false` and revision `962acb01a739276ea37ba53453dd09a0225e7376`.
* `app_tree_digest` `916d393795a47b99d2128464ba268defb51524555bc26c659560575051501954`:
  `local_amc3/tools/app_tree_digest.py`, measured twice. It equals the pin.
* `app_revision` `0760b6a22e113b74567330ff69ccc55a1d07022c` is the app's HEAD.
  **The app working tree is NOT clean against that HEAD**: `git status` shows
  modified `Gemfile`, `Gemfile.lock`, `app/controllers/streams_controller.rb`,
  `app/models/post.rb` and others. Those modifications are the pinned state
  the digest covers, so the revision name alone does not describe what ran.
  The digest does. I made no change to the app.
