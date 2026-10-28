# e2e run — live progress note (update in place; an interruption costs one step)

Started 2026-09-26 08:30 UTC.

## Phase 1 — the inventory sweep (RUNNING)

`tools/sweep.py --par 3 --max-runs 24 --time-budget 300`, output to
`manifest.jsonl` / `runs/` / `results/` / `logs/`, console in `sweep1.out`.
Checkpointed per endpoint; a re-run skips every id already in the manifest.

Differences from the shakedown, and why:

| knob | shakedown | here | why |
|---|---|---|---|
| `MAX_RUNS` | 2 | 24 | 125 of 161 shakedown endpoints stopped with `worklist_exhausted:false` and a non-empty worklist — cut off by MAX_RUNS. DSE cost 390.8 s across ALL 161 (max 9.8 s each) against ~180 s of JRuby boot per endpoint, so depth is nearly free. |
| `TIME_BUDGET` | 120 | 300 | headroom; the budget was never the binding constraint |
| run timeout | 480 | 900 | matches the raised depth |
| `run_complete` config | none | `CompletionConfig(batch_dir=…)` | the `extract_cmd` KeyError was fixed in src_new on 2026-09-26, so the gates now report **NOT CONFIGURED** blockingly instead of raising. Recorded as that state; NOT a pass. |
| `has_opaque` | any opaque = failure | `opaque_sites()` | the old check was built on `src_new/README.md:333`'s false claim. A shim contributes no atom but does contribute a SIGNATURE (`normalize.py:341`). Split into defects / by_design / unreferenced. |
| terminal record | type, cause, message | + backtrace, raising frame, `NameError#receiver`/`#name`, per-RUN rows | "where did this endpoint stop" was unanswerable from the shakedown's artifacts |

## Phase 2 — fixes (STAGED, validated on a trial)

`fixes/apply_fixes_round1.py` (`--check` / `--apply`). Seven fixes; every one
motivated by an artifact named in the script itself.

| id | file | what | evidence |
|---|---|---|---|
| FIX-1 | driver | `authenticatable_salt` leaf shim for candidate endpoints | `probes/probe_principal.out` — the salt compare returns concrete `false`, so `serialize_from_session` returns nil and `set_locale` dies. 113 of 114 signed-in endpoints. |
| FIX-2 | targets/core.rb | `dev_stub.to` returns `::User`, not the stub | `probes/probe_fixes.out` — `stub.equal?(stub.to)` is true, and all five methods the six devise endpoints died on are `::User` class methods |
| FIX-3 | driver | `users.language` 3-arm domain + `profiles.gender` pin | fixtrial v1 — with FIX-1 alone the next wall is `i18n.rb:383 enforce_available_locales!` → `SymbolicString#!=(false)` NotImplementedError. Both gold batches carry this pin. |
| FIX-4 | driver | `devise_user_first` target + `OrmAdapter#get` routing | fixtrial v1 — run 2 spent its budget on the session-lookup `not_found` arm, which Devise 401s upstream of the controller |
| FIX-5 | driver | tell "no handler" from "handler RAISED" | `comments_index`/`likes_index` recorded `Diaspora::NonPublic` while what stopped them was the handler itself raising |
| FIX-6 | driver | named `AuthenticationRequired` for anon `authenticate_user!` | `Devise::MissingWarden` is a rig artifact (no Warden middleware), recorded where the endpoint's outcome belongs |
| FIX-7 | targets/core.rb | `SymbolicVar.len_var_name` was DELETED from the runtime; core.rb still calls it at :1395 and :1483 | fixtrial v2 — every relation materialisation raises `NoMethodError`. **Concealed by the shallowness**: no shakedown endpoint got deep enough to materialise a relation. |

| FIX-8 | entrypoints/tools | scan the controller's own private helpers for `params` reads | `links_resolve` stops at `ParameterMissing: q`; `params.fetch(:q)` is in the private `query` helper, and `introspect_entrypoints.rb:295` scans the ACTION body only |
| FIX-9 | targets/core.rb + driver | `records`/`to_a` return an iterable list, so Gate 1b's representative can be reached | fixtrial v2 — `SymbolicList#each is not supported` at `list.rb:305`. core.rb:1482 already looks for `IterableSymbolicList`; it exists only in comments_index's layer |
| FIX-10 | entrypoints/scaffold + tools/sweep.py | the sweep reads its run limits FROM config.json, and config.json declares what is actually run | all 161 configs say `MAX_RUNS=6, TIME_BUDGET=600`; both shakedowns drove 2/120 and this sweep drives 24/300, so the document the review gates quote has never described a real run |

| FIX-11 | targets/endpoints/comments_index.rb | scope the rows memo to the RUN, with the guard core.rb:1928 already uses | 5 of comments_index's 12 dumps REFUSED by `validate_provenance` — `obj<Comment>` named but not declared, because a memo hit skips the `register_type` call while the per-run type table is cleared |
| FIX-12 | driver (rig) | stub `javascript_include_tag` / `stylesheet_link_tag` | this checkout strips frontend assets by its own Gemfile header, and the tag is in the SHARED layout, so it aborts every HTML render before any query |
| FIX-13 | driver | record a HANDLED exception too, as `concolic_handled` | `api_openid_connect_clients_create` reads as "ran to completion" while its four events are `Metal#status=` + `_set_rendered_content_type` — what one of its four `rescue_from` handlers does, not what `create` does |

Harness round 2 (`fixes/apply_pipeline_round2.py`, staged): run_complete and
build_policy over EVERY accepted dump, degrade-not-fail on an unrepresentable
one, and record render losses as findings.

## Phase 3 — the `src_new` write-up (DONE, `findings/SRC_NEW_DEFECTS.md`)

S-1 `include?` records `Contains` operands backwards (soundness).
S-2 §7.2 has no `Contains`, so one dump is refused wholesale.
S-3 an unparseable constraint is returned as UNSAT.
S-4 `README.md:333`'s false invariant, which cost 6 endpoints in both shakedowns.
S-5 a nameless symbolic value becomes a LITERAL in the structured PC.
S-6 the SQL renderer classifies every STRUCTURED note as prose, so the whole
    corpus renders ZERO views. Proven in two lines against the classifier.

## Phase 4 — the dry run (SMOKE-TESTED, `dryrun/`)

`python -m sweep.testbed` over two autolab endpoints, real `concolic.review`
and `concolic.check` subprocesses, fake agent harness. The campaign's state
machine moved SETUP -> SUBMITTED -> CHECKING -> EXPLORING -> SUBMITTED ->
CHECKING and stopped at `max_attempts`, and `campaign/review/<id>/attempt-1.json`
carries real review items. `dryrun/sweep_spec.json` (6 endpoints) validates
through `sweep.spec.load_spec`.

## Still to do

- finish sweep 1, build the inventory (`tools/build_inventory.py`)
- apply round-1 fixes + pipeline round 2, re-sweep all 161
- the `sweep.testbed` dry run (`dryrun/sweep_spec.json`, already validates)
- the residue: ActiveStorage (no service configured in ANY environment),
  asset-pipeline template errors, `ParameterMissing` scaffold gaps,
  SymbolicString runtime gaps

---

## Automation chain (so an interruption costs one step, not the job)

Launched 2026-09-26 ~09:57, each step gated on the previous one:

1. `fixes/apply_round2.sh` — waits for `sweep1.out` to say "sweep finished",
   then: freeze `INVENTORY*` and archive round 1 to `_round1/`; run the target
   library's suite and REFUSE to continue unless it is green
   (`fixes/tests_before.out`); apply all 13 fixes + the pipeline patch;
   `jruby -c` every Ruby file a sweep loads; re-run the suite and STOP if it
   regressed (`fixes/tests_after.out`).
2. `fixes/run_after_round2.sh` — refuses unless `tests_after.out` is green,
   then: `fixes/regen_scaffolds.sh` (backs up the whole scaffold tree, re-runs
   introspection → manifest → scaffold, re-applies the run limits, and prints
   which endpoints' symbolic inputs moved — STOPS if any endpoint LOST one);
   the 6-endpoint verification trial (`sweep_verify.out`);
   `fixes/check_verification.py`, which judges it against
   `fixes/VERIFICATION_CHECKLIST.md` — written before the trial ran — and
   STOPS if any expectation fails; only then launches the full `sweep2.out`.

**To resume after an interruption**, look for these files in order and run the
first script whose output is missing: `fixes/tests_after.out`,
`fixes/regen.out`, `sweep_verify.out`, `sweep2.out`. Every patch script is
idempotent-by-refusal — it checks its anchor appears exactly once and does
nothing if it has already been applied.

**To roll back**: `*.bak_e2e_round1` / `.bak_e2e_fix8` / `.bak_e2e_fix10` /
`.bak_e2e_fix11` / `.bak_e2e_fix12` beside each edited file,
`entrypoints/scaffold.bak_e2e/` for the whole scaffold tree, and
`entrypoints/lib/autolab_dse.rb.bak_pre_e2e` for the driver as it was before
any of this.

## After sweep 2

```
tools/build_inventory.py . ./INVENTORY          # the round-2 inventory
tools/compare_rounds.py _round1/INVENTORY.json INVENTORY.json   # regressions first
tools/assemble_report.sh "round 2 (after the repairs)"          # REPORT.md
# then the 6-endpoint dry run, dryrun/sweep_spec.json
```

---

## Round 2 — what actually happened (2026-09-26 11:00–11:52)

1. **Sweep 1 finished 11:01**: 161/161, 159 `ran_clean`, 2 `failed`, **zero run
   timeouts, zero pipeline timeouts**, 10.1 MB of dumps. Archived to `_round1/`
   with its INVENTORY.
2. **The library suite refused my first fix round.** `core.rb` and
   `comments_index.rb` must be byte-identical to the results4 gold
   (`test/test_install.rb:156-166`). Both reverted; FIX-2/7/9/11 re-made from
   the runner (`fixes/apply_runner_local_core_fixes.py`). Suite green again:
   38/38 + 38/38 + 75/75, `ALL SUITES PASSED`. See
   `fixes/SHARED_BOUNDARY_DECISION.md`.
3. **Citations**: my core.rb edits moved every line after them, so
   `check_citations.py` went stale. Restored with the revert; it now reports
   "every prose citation lands on a registered pattern".
4. **Scaffold regeneration (FIX-8)**: **21 endpoints gained symbolic inputs, 0
   lost any** — `links_resolve +q`, both federation receives `+xml`,
   `photos_create +aspect_ids/+photo/...`, `search_search +q/+term`, and more.
5. **Verification trial** (9 endpoints, judged against
   `fixes/VERIFICATION_CHECKLIST.md` written beforehand): failed twice, and
   both failures were real.
   * `home_show` still hit Sprockets — FIX-12 rewritten to answer the seam
     rather than individual helpers.
   * `contacts_index` read as a regression because my own render-quality
     finding flipped its verdict — `failures` now carry a `severity`.
   Re-run: **every expectation met**.
6. **Dry run**: `sweep.testbed` over six endpoints' post-fix dumps — 19 campaign
   steps, 219 logged decisions, 177 review items. The review item that exposed
   issue 8 now reads `MAX_RUNS=24, TIME_BUDGET=300`.
7. **Sweep 2 launched 11:52**, 150 endpoints to drive (11 already done by the
   trials), limits taken from each endpoint's own `config.json`.
