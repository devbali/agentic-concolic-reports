# people_stream — completion drive (2026-09-10)

Appended as the work proceeds. Owner instruction (overnight): "continue working
till all endpoints are complete." Starting state is `_PREFLIGHT_20260910.md`:
755 dumps, 29 nodes, 27 demand sets, `MISSING=0` (PROVISIONAL under §16b),
`tree_missing=1`, 5 rooted falsifier seeds built, `run_dse.rb` SEEDS_ONLY dedup
gate installed but UNTESTED against JRuby.

## §1. Smoke — the `SEEDS_ONLY` dedup gate against JRuby

The fix only LOOSENS dedup under `SEEDS_ONLY`. The strongest smoke is TWO
IDENTICAL seed dicts: under the old unconditional `seen_seeds` dedup the second
is dropped before it runs, and under the old unconditional `seen_paths` dedup
neither would be written twice. Seeds are `dump_auth_json0024_b1.json`'s own
`concolic_seeds`, duplicated.

**Result — the gate was DEFECTIVE, and the smoke found it.** With the preflight's
fix alone, a 2-seed `SEEDS_ONLY` replay produced **150 dumps**, not 6: it hit the
`MAX_RUNS` cap in all three scenarios.

The preflight repaired only HALF the drift. `notifications_index/run_dse.rb:455`
carries `next if ENV["SEEDS_ONLY"]` inside the flip loop; people_stream's port
did not. Without it `SEEDS_ONLY` only changed which roots START the worklist —
every replayed root still pushed its whole flip frontier, so the replay became a
full DSE exploration, and with path-dedup correctly disabled for replay 144 of
those 150 dumps were duplicate paths. A rooted round in that state cannot
attribute a hit to a seed, which is the entire point of the round.

Installed the missing gate (`run_dse.rb`, batch-local; backup
`run_dse.rb.pre_seedsonly_flipgate`; `ruby -c` OK). Re-smoke, same 2 identical
seeds, `LABEL_SUFFIX=_SMK0910b`:

```
  anon_all   runs=2  paths=2  drained=true   worklist drained
  anon_json  runs=2  paths=2  drained=true   worklist drained
  auth_json  runs=2  paths=2  drained=true   worklist drained
--- SMK0910b dumps: 6      (all six carry concolic_seeds: 5 keys each)
```

Two identical seed dicts -> two dumps per scenario. Both dedups are off under
`SEEDS_ONLY` and only under it; the frontier rounds are byte-unchanged.
**Smoke PASSED.** The 150 `_SMK0910a` dumps are real runs of the app and were
kept, not deleted: under §16b removing runs can CREATE a foreclosure and RETRACT
demand, which is the dishonest direction.

## §2. The tree branch — DRIVEN AT, NOT DRIVEN. Two rounds, 198 runs, 0 hits

### §2.1 A rooted-seed defect fixed first (notifications §9.7, ported defect)

`_tree_root.py` applied `_v3_seeds.py`'s DENY-LIST to the base dump's seeds.
That list is for a BULK seeder, which invents values; a ROOTED seed reproduces a
real run and flips ONE dimension, so stripping any base key changes the context.
On notifications it dropped a Rule G gate column and the first attempt hit the
branch 0 times and never evaluated the expression at all. Rooted seeds are now
**verbatim base seeds + the single flip** (backup `_tree_root.py.pre_verbatim`).

**Measured impact on THIS endpoint: none.** The deny suffixes that could have
bitten (`_guid`, `_id`) matched only the target key itself, which is re-added as
the flip. The rebuilt seeds are byte-identical to the preflight's. Fixed anyway:
the next target on this endpoint may not be so lucky.

### §2.2 The two rounds

`_tree_scan.py` re-run over the grown corpus (911 dumps at that point): the
target is evaluated 272 times, **not_taken 272, taken 0**, in `anon_json` (72)
and `auth_json` (200).

| round | seeds | what they are | runs | `_tree_check.py` |
|---|---|---|---|---|
| `TR0910a` | 5 | the preflight's rooted seeds, rebuilt verbatim | 15 | HIT=0 other=0 |
| `TR0910w` | 61 | **EVERY distinct rooted seed dict in the corpus** that reaches the `!=` site, guid flipped non-blank | 183 | HIT=0 other=0 |

`other=0` is the informative half: the expression was not merely observed on the
other side, it was **not evaluated at all** — which IS the `formatter.rb:40`
break the argument predicts. Whole corpus after both rounds: `HIT=0 other=272`.

### §2.3 The ground-truth differential, re-measured on 1109 dumps

```
eq=(False,)  ne=()        runs=340   guid non-blank -> line 40 BREAKS, `!=` never evaluated
eq=(True,)   ne=(False,)  runs=272   guid blank     -> line 41 runs, forced False
                                     ne taken: 0 of 612
```

Site identity across all four instances, same corpus, through the engine's load
path (`==` at `blank?`, `!=` at `block in generate`), and in EVERY family the
`!=` population equals the `== ''` TRUE population exactly:

```
E first_1   eq True= 29 False= 52 | ne taken=0 not_taken= 29
I find_by_1 eq True=  4 False= 24 | ne taken=0 not_taken=  4
L via_user  eq True=  4 False= 29 | ne taken=0 not_taken=  4
THIS        eq True=272 False=340 | ne taken=0 not_taken=272
```

The mechanism, verified in the stock gem on this host
(`~/.gem/jruby/2.6.0/gems/actionpack-5.2.4.3/.../journey/formatter.rb:39-41`):
line 40 breaks the parts loop whenever the guid is non-blank, so the only path
that reaches line 41 has just established the guid IS blank, where `'' != ''` is
forced False. The True outcome has no producing path **in this route table** —
`config/routes.rb:179` is `resources :people, only: %i(show index)`, no default
and no constraint on `:id`.

**Fate of the branch: genuinely unreachable. Driving it was tried first and
failed on its own evidence.**

## §3. The pin — installed as a separate, counted, reversible tier

`coverage_assumptions.py` gains **Argument 5b**, `_OVERNIGHT_PINS`, printed on
its own (`OVERNIGHT_PINS=` in the `[assumptions]` line), reversed by one edit or
by `NO_PINS=1`. Backup: `_bak_coverage_assumptions_pre_overnight_pins.py`.
Authority: the owner's 2026-09-10 overnight instruction, with the standing
direction from notifications `_COMPLETION_CAMPAIGN_20260910.md` §8 to INSTALL an
unreachable-side pin rather than leave it a proposal — and only after the
falsifier has been run, which §2 is.

`coverage_report.py` gains `SUMMARY_OUT`, and `NO_PINS=1` now REFUSES to run
without it, so the counterfactual can never overwrite the shipped summary.

### The pass, with the pin (1109 dumps, own slice, 209 MB peak)

```
loaded 1109 runs (0 unparseable)
[assumptions] declared=48 INERT(never-co-evaluated, not declared)=30 OVERNIGHT_PINS=1
COMPLETE=True;NODES=29;MISSING=0;BLOCKING=0;PCS=8382
GENUINE=True;TRUNCATED=False;SOLVER_LOST=0;UNEVALUABLE=[]
DEMAND_SETS=27;TREE_COMPLETE=True;TREE_MISSING=0;FORECLOSURES=135;FORECL_IGNORED=0;FORECL_PROVISIONAL=False
```

### The counterfactual, without it (`NO_PINS=1`, `_bak_coverage_summary_NO_PINS_20260910.json`)

```
[assumptions] declared=47 INERT(never-co-evaluated, not declared)=30 OVERNIGHT_PINS=0
COMPLETE=False;NODES=29;MISSING=0;BLOCKING=0;PCS=8382
DEMAND_SETS=27;TREE_COMPLETE=False;TREE_MISSING=1;FORECLOSURES=135;FORECL_IGNORED=0;FORECL_PROVISIONAL=True
   TREE-MISSING (SYM_RESULT_ActsAsApi__Collection_as_api_response_1_row_guid != StringVal('')) :: taken
```

**The pin changes exactly one thing.** `NODES`, `DEMAND_SETS`, `MISSING`,
`BLOCKING`, `PCS` and `FORECLOSURES` are identical with and without it — as
DISCIPLINE §16b requires, an untracked expression is in no demand set, so it can
neither foreclose nor be foreclosed. `MISSING=0` was PROVISIONAL before the pin
and is a CLAIM after it (`FORECL_PROVISIONAL` False), and it did not move: no
new demand appeared when the branch closed, and none appeared when the corpus
grew 755 -> 1109 either (checked before the pin was installed).

## §4. The assumption gate — 48 of 48 PASS, and the pin passes for the right reason

people_stream had **no `assumption_manifest.json`**, so the mandatory Phase 4
gate had never run on this endpoint. Built one (derived mode: the assumptions
come from `coverage_summary.json`, no hand-written kinds) plus `gate_canon.py`,
a batch-local load hook.

**A gate defect this endpoint would have had, found and fixed before running:**
`assumption_checker.py` matches a probe dump to its snapshot by
`dump["concolic_scenario"]["name"]`. This batch's runner never records that key
(the scenario lives in the LABEL), so every dump's scenario reads None and a
probe replayed for an `auth_json` snapshot could be matched against the
`anon_all` dump of the same launch — a verdict earned on the wrong run. Fixed at
the batch's own load point (`canonicalize` in the manifest) rather than in the
runner, which would have left the 1109-dump corpus without the key while new
probe dumps had it. No `src/` change.

```
RESULT: 48 distinct tested — PASS 48, FAIL 0, NOT-TESTABLE 0, NOT-COMPARABLE 0
```

The four `OneSideUntrackedPathAssumption`s — the three declared siblings and the
new pin — all earn:

```
  PASS  OneSideUntrackedPathAssumption  (SYM_RESULT_ActsAsApi__Collection_as_api_response_1_row_guid != String
      flipping the variable leaves the PC unevaluated — the other side is unreachable by construction
```

That is the gate re-deriving §2's argument from its own probe, and it is the
same verdict notifications' T10 earned (`_COMPLETION_CAMPAIGN_20260910.md` §8.1).
Full log `_gate_20260910.log`, per-assumption JSON `_gate_results_20260910.json`.
No probe residue: corpus is 1109 dumps, no `dump_*achk*` and no `_achk_*` files.

## §5. Closing audits — `_c7_audits.sh`, built for this endpoint

people_stream had no audits script. `_c7_audits.sh` is a port of
notifications' minus the four entries that need artefacts this endpoint does
not have; every omission is NAMED in the log rather than silently skipped.

| audit | EXIT | verdict |
|---|---|---|
| identity_symbolicity | 0 | pass — every principal bind is symbolic |
| statement_note_lint | 0 | no red-level findings |
| bind_resolution | 0 | pass (0 unresolvable) |
| skipped_pcs VANILLA | **1** | **RED — 309 `(VAR != VAR(_))` PC records dropped** |
| skipped_pcs PATCHED | 0 | pass — 0 dropped |
| pc_visibility | **1** | **RED — `diaspora_handle` BLIND (Class B)** |
| empty_relation_emission | 0 | pass |
| noteless_call | **1** | **RED — 7 targets, 7 405 events, 4 344 dumps** |
| cardinality_consistency | 0 | pass but **VACUOUS** (its own words) |
| rig_crash_census | 0 | pass — every terminal is an application terminal |
| boundary_declaration | 0 | pass — every boundary family declared in every batch |
| hardening_lint | **1** | **4 checks need an answer** (H6 not run: no concrete_run.json) |
| note_fidelity / count_matrix / format_coverage | — | **NOT RUN** (artefact absent — not a pass) |

**The vanilla/patched split is the RUNBOOK's mandatory pre-extraction check and
it is load-bearing here**: the extractor installs `_experiment/variant_d`'s
`AssocFoldingTransformer`, which is why the shipped policy keeps those 309
records. Confirmed in the extractor source, not assumed.

**A correction I made to my own input.** The first pc_visibility run used
notifications' gate list (`public, author_id, person_id, type, username, ...`)
and reported six BLIND columns. That list was wrong for this endpoint: those
are QUERY PREDICATES and REQUEST PARAMS, not columns this controller branches
on. Re-derived from code (`find_person` -> `closed_account?`, `profile.nsfw?`,
the post `text`/`comments_count` decorator checks, `person_path` -> `guid`,
`mentionable` -> `diaspora_handle`): five VISIBLE, **`diaspora_handle` BLIND**,
and that one is a real finding — `PostPresenter.build_mentioned_people_json` is
a declared target that swallows the mention chain (the same target
`noteless_call` and `hardening_lint` H3 flag).

**None of the four REDs was introduced by this drive**; all are Phase 1 / Phase 5
gaps this endpoint has never had a round for. They are declared in the shipped
policy as X2-X5, and they are why `COMPLETE=True` here is the COVERAGE claim
plus the assumption gate and NOT the RUNBOOK's full "COMPLETE =" line.

### The engine's completion section could not run — reported, not worked around

`people_stream/coverage_report.py` has **no completion wiring at all** (it does
not read `SKIP_COMPLETION`; the variable the preflight passed was a no-op), and
the batch has no `completion_config.json`, no `shim_tests.rb`, no
`concrete_run.json` and no `concrete_aliases.json`. So there is nothing to run
with `SKIP_COMPLETION` unset, and no `OVERALL_COMPLETE=` line exists on this
endpoint. people_show and posts_show are in the same state; comments_index and
conversations_index are not. What I did instead is the layer RUNBOOK calls
non-optional and which had never run here — the assumption gate, standalone,
in derived mode (§4). Building the rest is a Phase 1/5 campaign (shim tests +
a concrete run + an adversary round), not a step of this drive, and it is the
single named thing between this endpoint and a comments_index-grade closure.

## §6. Extraction and policy install

Run WITH subsumption (blockaid, Java) under
`systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=6G`,
`JAVA_TOOL_OPTIONS` unset, no coverage pass alongside it (`ps` checked; only
notifications' JRuby DRIVES were up, and those hold slots, not memory this job
needs), `free` 10 GB available at launch.

```
corpus POPULATION: 1109 dump files
subsumption: state=True over 36 eligible of 107 distinct
   stage 1 SYNTACTIC containment (free, not solver-decided, not gated by eligibility): 42 views dropped
   stage 2 SOLVER (blockaid) saw 22 views
   verdict tally  subsumed(true)=0  not-subsumed(false)=22  UNDECIDED(null)=0
   total dropped 42 = 42 syntactic + 0 solver
people_stream: 65 queries (107 distinct, 42 subsumed) from 1109/1109 dumps; subsume_ran=True
```

| | value |
|---|---|
| views | **65** (13 094 raw -> 107 distinct -> 65) |
| unparseable notes | **0** (`errors` is `[]`) |
| rotation residue (`bind-rotation-UNRESOLVED`) | **0**; 63 of 65 carry `bind-rotation-repaired` |
| subsumption | true **0** / false **22** / null **0** |
| DECLARED placeholder families | `_SYM_PERSON_via_user_id` **21**, `find_by_1_id` **21**, `find_by_2_author_id` **1**; **43 of 65 views** carry at least one — all DECLARED OPEN, none resolved |

### A defect in the tri-state tally itself, found and fixed

The first run printed `subsumed(true)=42 not-subsumed(false)=0` over **36
eligible** — 42 of 36, silently clamped by `max(0, ...)`. Cause:
`prune_subsumed` drops in TWO stages and only the second is gated by
`eligible`. Stage 1 is FREE SYNTACTIC containment over every query,
placeholders included; stage 2 is the blockaid solver on stage 1's eligible
survivors. Folding them credited the solver with 42 drops it never saw and
drove `false` to a clamped zero — the exact conflation this tri-state tally
exists to prevent. Now counted and printed separately (backup
`_extract_people_stream_streaming.py.pre_tally_split`), and the honest reading
is: **every one of the 42 drops is free syntactic containment; the solver
subsumed nothing.** No null was folded into false; there were none.

### The policy

`POLICY_HEADER.txt`'s six `TODO(drive)` markers are all replaced with measured
facts (backup `POLICY_HEADER.txt.pre_drive`), the TEMPLATE banner is gone, and
the header now carries the engine verdict, the branch's fate and its falsifier,
the gate RESULT, the extraction standing, and six DECLARED OPEN entries
(X1 placeholders, X2 noteless statements, X3 the blind gate column, X4
hardening, X5 no concrete/adversary round, X6 what the drive itself declared).
Installed exactly where comments_index's is:
`results3/queries_from_runs/people_stream.sql` (+ `_summary_people_stream.json`).
`grep -c "TODO(drive)" people_stream.sql` = **0**.

## §7. State at hand-off

* **`COMPLETE=True`**, `TREE_MISSING=0`, `MISSING=0` (a claim, not provisional),
  1 109 dumps, 29 nodes, 27 demand sets, 135 foreclosures.
* **Assumption gate: PASS 48 / FAIL 0 / NOT-TESTABLE 0 / NOT-COMPARABLE 0.**
* One thing declared: Argument 5b, reversible by `NO_PINS=1`, counterfactual on
  file.
* Policy shipped: 65 views, 0 unparseable, 0 rotation residue, 43 views declared
  open on unbound placeholders.
* Not done, and named in the policy: no `completion_config.json`, no concrete
  run, no adversary round; four closing audits RED; `diaspora_handle` blind.
* No `src/` change. Reference policies not read, still `chmod 000`.

---

# Closure — the completion section, Phase 5, and the four audits (2026-09-10, overnight)

Picking up from §7's hand-off, whose single named blocker was: *"no
`completion_config.json`, no concrete run, no adversary round"* (the declared
gap X2-X5). All four artefacts now exist and the engine's full line has been
produced for the first time on this endpoint.

## §8. The completion section — ported, and it runs

`coverage_report.py` gains the completion block ported from
`comments_index/coverage_report.py` (backup `coverage_report.py.pre_completion`).
One endpoint-specific addition, because this batch has something comments_index
does not: a **counterfactual pass (`NO_PINS=1` / `SUMMARY_OUT`) must never run
the completion gate**. The gate writes `_shim_results.json` and
`_assumption_results.json` into the batch, so a counterfactual would clobber the
shipped run's own evidence while writing its verdict to a scratch file. It is
marked NOT complete instead — the honest direction, and the same rule that made
comments_index refuse a killed report's `complete: true` in 2026-08-27.
`main()` now returns on `summary["complete"]`, not on coverage alone.

New artefacts, all four modelled on comments_index and adapted only where the
endpoint differs:

| file | what is endpoint-specific |
|---|---|
| `completion_config.json` | this batch's targets/aliases; `pc_gate_columns` = the six columns THIS controller compares; `pc_pin_ledger: [target_type]`; `extra_audit_cmds` = note_fidelity + empty_relation_emission (this endpoint has no `format_coverage_audit.py`) |
| `shim_tests.rb` | 20 test bodies over the 28 shims the extractor enumerates |
| `concrete_run.json` | 4 scenarios, merged from 4 one-scenario manifests (JVM crash isolation) |
| `concrete_aliases.json` | the corpus↔concrete finder aliasing for THIS batch's mock set |

### §8.1 The shim layer — 19 PASS / 9 PROTOCOL / 0 blocking

The extractor enumerates **28** shims (4 prepends + 24 rep-plumbing). Nine come
back PROTOCOL from the runner's own check against the real class (the AR
attribute/Ruby object protocol plus `obj.post_location`, stated as
`real_class: "Post"` and VERIFIED — base `Post` defines no such method). The
other 19 RUN, at 100 % of their executable lines, under the target-call probe.
No waiver anywhere; `PASS` and `PROTOCOL` are the only verdicts present.

Three things this file had to solve that no other batch's did:

**(a) The `user.*` overrides needed a runnable receiver.** `apply_user_overrides!`
installs nine singleton methods on the symbolic current user. A rep's `id` is a
`SymbolicInt` and Arel calls `#to_i` on it — a ScriptError the runner cannot
catch (notifications, 2026-09-01). The test calls the batch's OWN
`apply_user_overrides!` with a REAL `User` and a REAL `Person`: the installed
bodies are byte-identical (none of them branches on the receiver) and now
executable against fixture rows.

**(b) Two shims live inside `ConcolicTargets.install!` and cannot be reached
without running it** — the `SingularAssociation#find_target` W3-memo and the
`Gon.preloads` accessor are anonymous `Module.new` bodies, and the
`__descend_filter__` / `declare_target` declaration filter is installed on the
interceptor itself. A shim test may never declare a target. Verified in the file
rather than assumed (`grep` for `.prepend(` / `define_method` over
`concolic_targets.rb`) that `install!` reaches a real class through exactly ONE
channel — `interceptor.declare_target`, i.e. `klass.define_method` — plus those
two prepends. So `install!` is handed a **throwaway interceptor** whose
`declare_target` records and returns nil: the two real shim bodies get installed
on the real classes, the real declaration filter gets installed on the throwaway,
and **nothing is declared**. `PeopleStreamTargets.install!` is deliberately NOT
called, because it stubs `ActionController::Base.helpers.image_path` and the
`h.*` tests must run the REAL `ActionView::Helpers::AssetUrlHelper` bodies (the
stronger claim, and comments_index's).

**(c) An instrument limit, measured and worked around rather than waived.**
`TargetCallProbe.capture` wraps a target with `home.instance_method(meth)` +
`define_method` on the OWNER. When the boundary has PREPENDED a module defining
the same method — exactly what the W3-memo does to
`SingularAssociation#find_target` — `instance_method` resolves THROUGH the
prepend, so the probe's "original" IS the memo while the memo's `super` lands on
the probe wrapper: infinite recursion. Measured, not inferred — 2 MB, 8 MB,
16 MB and 64 MB JVM stacks all die, and the trace cycles
`concolic_targets.rb:1033 ↔ :1042`. Every other batch avoids it only by never
running `install!`. Fix: detach the memo body from the module (keeping the
`UnboundMethod`) so the ancestry the probe sees is the real one, and let the ONE
test that is ABOUT the memo re-attach it from inside its own fixture — after
`capture` has already captured the real `find_target`. The memo then runs for
real, its `super` reaches the real body THROUGH the probe (which records the
call), and there is no cycle. All three of its arms are covered: label reset,
memo miss, memo hit.

One `reaches:` set was MEASURED, not guessed: `user.contact_for` was declared
with three targets, the runner returned `FAIL-REACHES` and named the fourth
(`ActiveRecord::Relation#to_ary`, the `includes(person: :profile)` preload), and
the declaration was corrected to what the run showed.

### §8.2 The concrete round — the first ever on this endpoint

Four one-scenario manifests (JVM crash isolation), a real sqlite DB through the
project's own `concrete_env`, real rows by raw INSERT, real dispatch through
`ctrl.dispatch("stream", …)` so `find_person` and
`authenticate_if_remote_profile!` run exactly as in the corpus. No mock of any
kind: `targets.rb` / `concolic_targets.rb` are never loaded in this rig.

```
people-stream-anon-all           target_calls=12   statements=1    error=None
people-stream-anon-json          target_calls=102  statements=27   error=None
people-stream-anon-json-handle   target_calls=105  statements=27   error=None
people-stream-auth-json          target_calls=159  statements=42   error=None
                                 ----------------  --------------
                                 378 target calls   97 statements
```

Both arms of `find_person` are covered (the `guid` arm and the `diaspora_id?`
handle arm), and the anon/auth arms provably read different rows through
different scopes — each scenario asserts it (`raise` if the anon arm leaks the
LIMITED post, `raise` if the signed-in arm fails to see it), so a scenario that
silently degrades fails instead of reporting green.

Two rig defects were found and fixed AT THE SOURCE rather than waived:
* the principal (`User.find(9)`) was being loaded INSIDE the measured body,
  attributing a `SELECT "users" …` to the endpoint that the endpoint never
  issues. Hoisted out of the probe.
* `ActionController::Instrumentation#redirect_to` is a `super`-chaining
  decorator; under the probe's alias-wrap its `super` finds no superclass method
  and the whole anon_all scenario died with `NoMethodError`. Excluded WITH ITS
  REASON printed on every run (the same class as comments_index's `render`
  waiver); it is a redirect and issues no statement.

And one FIXTURE gap was closed rather than declared: H6 first reported four
`o_embed_caches` / `open_graph_caches` note families as "never issued by any
concrete run". They were never issued because the fixture had no such rows and a
NULL FK issues no query. Rows added; 118 → 114. **Widen the ground truth, never
narrow the check.**

### §8.3 `OVERALL_COMPLETE=` — verbatim

`_engine_20260910_final.log`, own 6 GB slice, `JAVA_TOOL_OPTIONS` unset, JRuby
steps through `tools/slot`, 210 MB peak, no probe residue (corpus is still
exactly 1 109 dumps, no `dump_*achk*`):

```
loaded 1109 runs (0 unparseable)
[assumptions] declared=48 INERT(never-co-evaluated, not declared)=30 OVERNIGHT_PINS=1
OVERALL_COMPLETE=False;COMPLETION=False
   AUDIT RED      note_fidelity
   AUDIT green    empty_relation_emission
   SHIM  PASS      x19        (Person.posts, h.image_path, h.path_to_image,
                               User.person, user.{person,language,gender,contacts,
                               blocks,aspects,contact_for,block_for,posts_from},
                               obj.image_url, obj.hidden_shareables,
                               interceptor.{__descend_filter__,declare_target},
                               SingularAssociation.find_target, ::Gon…preloads)
   SHIM  PROTOCOL  x9         (obj.{read_attribute,_read_attribute,concolic_attrs,
                               concolic_note,attributes,write_attribute,
                               _write_attribute,inspect}, obj.post_location)
   NOTE-CHECK   RED
   ASSUMPTIONS  green (declared 48, distinct tested 48, {'PASS': 48})
   BLOCKING  audit note_fidelity: RED
   BLOCKING  note_check: RED
COMPLETE=True;NODES=29;MISSING=0;BLOCKING=0;PCS=8382
GENUINE=True;TRUNCATED=False;SOLVER_LOST=0;UNEVALUABLE=[]
DEMAND_SETS=27;TREE_COMPLETE=True;TREE_MISSING=0;FORECLOSURES=135;FORECL_IGNORED=0;FORECL_PROVISIONAL=False
peak RSS 210 MB
dump_errors={'ActionController::UnknownFormat': 142}
ENGINE_EXIT=1
```

**The coverage layer and the assumption gate are green; the mock layer is not,
and both blocking entries have one root-cause family.** That family is the same
one the four RED audits point at, and it is set out in §10.

## §9. The four audits — fate of each

| audit | fate | one-line reason |
|---|---|---|
| `skipped_pcs` (309 dropped, VANILLA) | **DECLARED** (X5) | The vanilla arm is the RUNBOOK's mandatory CONTROL, not the gate: its RED is the signal that tells the extractor to install `variant_d`'s `AssocFoldingTransformer`, under which 0 records drop — and that IS the pipeline this policy was extracted with, confirmed in the extractor source. Both exits stay printed; neither is suppressed. Falsifier: extract without variant_d and all 309 `(VAR != VAR(_))` records vanish from the fold. |
| `pc_visibility` (`diaspora_handle` BLIND) | **DEFECT — RAISED** (X3) | Not a wall. `PostPresenter.build_mentioned_people_json` is a declared target over a body that really runs `mentions.includes(person: :profile).map(&:person)`; the concrete round issues `SELECT mentions`, `SELECT people … id = ?` and `SELECT profiles … person_id = ?` under that frame and NONE has a note anywhere in the corpus. The declaration site is `concolic_targets.rb` — the SHARED boundary — so DISCIPLINE §T3 forbids fixing it here. Falsifier: descend the target and the column gains PC references in the next corpus. |
| `noteless_call` (7 targets, 7 405 events) | **1 WALL declared, 3 DEFECTS FIXED, 3 DEFECTS RAISED** (X2) | See §10 — this one splits three ways and is the one the brief flagged. |
| `hardening_lint` (4 unanswered) | **1 ANSWERED (green), 1 answered-in-part, 3 remain OPEN** (X4) | H5 `target_type` is now declared in `pc_pin_ledger` and reads green. H6 RAN for the first time (it was SKIPPED, which is not a pass) and reports 114 note shapes no concrete run issued — with the caveat that it compares RAW notes and ~22 % of this endpoint's notes are bind-rotated as rendered. H1 (no mobile arm) is ANSWERED on the merits — `stream` declares only `format.all` and `format.json`, and a mobile request takes `format.all`, i.e. the W1 redirect, which issues no statement — but the lint has no declaration hook for H1, so it still prints CHECK. H3's three entries resolve to: one proven wall (`diaspora_id?`), one boundary harvest missing (`escape_segment`, B-2), one real defect (`Core::ClassMethods.find_by`'s non-SQL note, X8). H4 (zero `len(...)` PCs in 1 109 dumps) is OPEN and is the largest blind spot after §10(c). |

## §10. `noteless_call` in full — the E11 question, answered per target

The brief asked whether these targets can issue SQL, and said that if they can
it is a policy-completeness defect rather than a wall. **Six of the seven can.**

**(a) One genuine wall.** `PeopleController.diaspora_id?` (1 109/1 109) is
`!(query.nil? || query.lstrip.empty?) && Validation::Rule::DiasporaId.new
.valid_value?(query.downcase).present?`; `valid_value?` is a length check plus a
regex. No SQL, no target beneath it, in any arm. Declared, with its falsifier.

**(b) Three B-8 defects — FIXED batch-locally, with a ground-truth
differential.** The finder family (`FinderMethods.find_by` 685/487,
`FinderMethods.first` 12/12, `Core::ClassMethods.find_by` 12/12) is the
documented B-8 case exactly: `finder_mock`'s `not_found == true` arm returns
`nil`, and the interceptor takes the note from the RETURNED value. 100 % of the
noteless events are that arm (measured: every noteless event has
`result_value: None`; every noted one returns a record). The SQL is physically
in the dump — on the `_not_found` var's note — but `transform.py:406` harvests
statements only from `symbolic_call` notes, so the var note is inert for
extraction: exact-string recovery 0/709, normalized-shape recovery within the
same dump 0/709.

The fix (`Thread.current[:concolic_pending_note] = sql` before returning nil) is
installed in this batch's `concolic_targets.rb`; backup
`concolic_targets.rb.pre_b8`, `ruby -c` clean. It is the identical repair
notifications_index and comments_index already carry. Evidence,
`_B8_DIFFERENTIAL_20260910.txt` — same env, same fixture, same seed, only the
file differs:

```
pre-B8   EVENT ActiveRecord::FinderMethods.find_by note=""
post-B8  EVENT ActiveRecord::FinderMethods.find_by note="SELECT \"people\".* FROM \"people\""
```

Measured impact of the fix on THIS corpus: **0 new distinct statement shapes**
(both candidates already appear as noted events elsewhere — `likes …` 304 times,
`people.diaspora_handle …` 479 times) but **354 of 1 109 dumps would gain a
statement they issued and lack**, and **12 dumps that today extract to "no SELECT
queries recorded for this endpoint" would gain the endpoint's own person
lookup** — the comments_index M-9 signature.

**The audit still reads RED, and that is stated rather than engineered away.**
The 1 109-dump corpus predates the fix. Truncating it to force a green was
rejected on §16b grounds: removing runs can create a foreclosure and retract
demand. Regenerating it does not clear the audit either, because (c) survives
any regeneration. The cost is stated so it can be scheduled: base exploration
drains in ~2 min 21 s for 201 dumps (`_gen_base.log`), after which the demand and
tree rounds that closed `MISSING=0` must be re-driven.

**(c) Three Rule S §9.8 boundary defects — RAISED, not fixed.** `Person.name`
(3 159/908), `Anonymous.process` = `MessageRenderer::Processor#process`
(1 520/908) and `PostPresenter.build_mentioned_people_json` (908/908) are each
declared SQL-free while the body they stand over reaches a query —
`person.rb:247` → `self.profile` (has_one) and `fix_profile`;
`message_renderer.rb:100-105` → `Post.exists?(guid:)` on any text matching
`DIASPORA_URL_REGEX`; `post_presenter.rb:94` →
`mentions.includes(person: :profile).map(&:person)`. The concrete round confirms
all three by issuing exactly those statements, and **`profiles` appears in ZERO
notes in the entire corpus.** Under Rule S §9.8 a stub over a body that issues a
query is not a shim at all — it is a target, and it belongs in the shared
boundary. §T3 forbids an agent editing that boundary and §T2 says a change there
voids every endpoint, so these are raised for the coordinator with their
falsifiers, not patched.

## §11. What the concrete round found beyond the audits (new, X7)

`mock_note_check` RED, `note_fidelity_audit` RED (14 unfaithful of 21 distinct
real SELECTs). Six statements the app provably issues have no matching note
shape anywhere in the corpus, from three distinct causes:

* `profiles` (twice, under `find_target` and `Relation#records`) — §10(c).
* `polls`, `locations`, and `photos` — the corpus's post records are symbolic
  representatives of the BASE class `Post`, and the StatusMessage-only
  associations do not exist on it (`post.rb:79` is literally
  `def photos; []; end`). The whole StatusMessage read set is invisible by
  construction. `photos` is worse than a missing note: `CollectionAssociation
  #find_target` executes through AR's StatementCache, bypassing
  `Relation#records`, so **no declared target frames it at all** — as the
  boundary stands, no mock can mint evidence for it (the E11 class). It is the
  one statement the check reports as "outside any target frame".
* `SELECT DISTINCT posts.* … LEFT OUTER JOIN share_visibilities …` — this is
  `Post.from_person_visible_by_user`, the REAL body of `User#posts_from`, which
  `targets.rb` §4 replaces with `Post.where(author_id: p.id)`. The concrete round
  shows the substitution is **not statement-preserving**: the real signed-in
  request joins `share_visibilities` and `aspect_visibilities`, and this policy
  contains no such view. This mock is BATCH-LOCAL, so unlike §10(c) it is
  repairable here — it was not repaired tonight because the repair changes what
  the corpus records and therefore needs a full regeneration plus a re-closed
  demand campaign. Falsifier: restore the real `posts_from` and the next corpus
  contains the DISTINCT visibility join.

Lower-severity rows from the same round, listed so they are not dropped: 1
STAR-OVER, 6 PRED-OP-DIFF, 2 LIMIT-DIFF, 2 other-DIFF, 6 EXACT. The DIFF rows are
computed on RAW notes and this endpoint's notes are bind-rotated as rendered, so
some are instrument artefact; the MISSING rows are not — a missing note cannot be
a rotation artefact.

## §12. Extraction and policy

**No re-extraction was needed and none was run**: nothing tonight changed what
the policy should contain. The corpus is byte-for-byte the same 1 109 dumps
(verified: 1 109 files, no probe residue), the B-8 fix adds 0 distinct statement
shapes on this corpus (§10(b)), and the only §16b-safe way to make it change the
FILE is a regeneration, which was deliberately not done. `POLICY_HEADER.txt` was
rewritten and re-applied to `results3/queries_from_runs/people_stream.sql`
(backups `POLICY_HEADER.txt.pre_closure_20260910` and
`people_stream.sql.pre_closure_20260910`); `grep -c "TODO(drive)"` = 0,
`grep -c "^SELECT"` = 65.

Numbers as shipped (`_summary_people_stream.json`,
`_extract_people_stream_SUBSUME_20260910.log`):

| | value |
|---|---|
| views | **65** (13 094 raw → 107 distinct → 65) |
| unparseable notes | **0** (`errors` is `[]`) |
| rotation residue (`bind-rotation-UNRESOLVED`) | **0** (the flag does not appear; 12 312 `bind-rotation-repaired` marks across 63 of 65 views) |
| subsumption | ran, `state=True`, over 36 eligible of 107 distinct |
| — stage 1 SYNTACTIC containment (free, no solver, not gated by eligibility) | **42 views dropped** |
| — stage 2 SOLVER (blockaid) saw | **22 views** |
| — tri-state tally | **subsumed(true)=0 / not-subsumed(false)=22 / UNDECIDED(null)=0** |
| — total dropped | 42 = **42 syntactic + 0 solver** |

Stated separately as the brief requires: **every one of the 42 drops is free
syntactic containment; the solver subsumed nothing, and no `null` was folded
into `false` — there were none.** (This is the split the previous agent
installed after finding the tally had folded the two stages and printed "42 of
36 eligible", clamped.)

## §13. State at hand-off

* **`OVERALL_COMPLETE=False`.** Coverage `COMPLETE=True`, `NODES=29`,
  `MISSING=0`, `TREE_MISSING=0`, `PCS=8382`, 1 109 dumps. Assumption gate 48/48
  PASS. Shim layer 19 PASS / 9 PROTOCOL / 0 blocking. Blocking: `note_fidelity`
  RED and `note_check` RED.
* This endpoint now has every artefact a comments_index-grade closure needs
  (`completion_config.json`, `shim_tests.rb`, `concrete_run.json`,
  `concrete_aliases.json`, the completion section) and, for the first time, a
  Phase 5 concrete round. What it does NOT have is a GREEN mock layer, and the
  gap is real, not procedural.
* One batch-local repair applied: B-8, with a ground-truth differential.
* Three boundary items RAISED for the coordinator (X8): B-8 missing from the
  SHARED `reports/diaspora/concolic_targets.rb`; the kwargs finder-conditions
  harvest missing from this batch (10 occurrences in notifications, 19 in
  comments, 0 here); B-2 `escape_segment` still a target here, a shim there.
* **No `src/` change.** The one src-level issue found — `TargetCallProbe`
  cannot observe a target the boundary also prepends (§8.1c) — was worked around
  batch-locally in `shim_tests.rb` and is reported, not patched.
* Reference policies untouched and still quarantined.
* The named next steps, in the order that buys the most: (1) descend the three
  §10(c) targets in the shared boundary — that alone clears `noteless_call`'s
  remaining half, X3's blind column, and three of X7's six missing statements;
  (2) restore the real `User#posts_from` (batch-local) for X7(iii);
  (3) regenerate the corpus on the repaired boundary and re-drive the demand +
  tree rounds; (4) then, and only then, an adversary sub-agent round.

---

# Rerun 2026-09-11 — the note layer, fixed batch-locally, and what it cost

Owner instruction (2026-09-11 00:30): *"fix the note issue and run again, why is
it waiting on me?"* Nothing was waiting on the owner: §13's hand-off listed the
X7 repair as a NEXT STEP and stopped. This section does it.

## §14. X7 — the substitution is now statement-preserving, and five siblings with it

### §14.1 What was actually wrong, per statement

`mock_note_check` and `note_fidelity_audit` re-run on the shipped 1 109-dump
corpus before any change (the baseline this section is measured against):

```
-- statements OUTSIDE any target frame (1):
     SELECT "photos".* FROM "photos" WHERE "photos"."status_message_guid" = ?
NOTE-MISMATCH SingularAssociation.find_target   4 shapes with NO corpus note anywhere
     people.owner_id / profiles.person_id / polls.status_message_id / locations.status_message_id
NOTE-MISMATCH Core::ClassMethods.find_by        1 shape   people.guid
NOTE-MISMATCH FinderMethods.exists?             1 shape   SELECT 1 AS one FROM posts WHERE posts.guid
NOTE-MISMATCH Relation.records                  4 shapes  likes(4 preds) / DISTINCT posts+share_visibilities
                                                          / posts type+root_guid+author_id / profiles.person_id
note_fidelity_audit: RED — 14 unfaithful of 21 distinct real SELECTs; MISSING 5, STAR-OVER 1,
                      PRED-OP-DIFF 6, LIMIT-DIFF 2, EXACT 8
```

Every one of those is a MOCK swallowing evidence, and — this is the part §11 got
wrong — **all of them were repairable in this batch**, four in `targets.rb` and
two as a re-sync of a documented shared-boundary fix this batch's copy had
simply never received.

### §14.2 The repairs

| # | site | file | what it was | what it is |
|---|---|---|---|---|
| X7-iii | `apply_user_overrides!` `posts_from` | `targets.rb` §4 | `Post.where(author_id: p.id)` | **override REMOVED** — the real `User#posts_from` runs, so `Post.from_person_visible_by_user`'s `DISTINCT … LEFT OUTER JOIN share_visibilities` is built and noted |
| X7-i | `apply_user_overrides!` `person` | `targets.rb` §4 | `{ person }` — silent | materialises `Person.where(owner_id: user.id).first` (the real `has_one :person, foreign_key: :owner_id`) once per run, then returns the pinned person |
| X7-i′ | `UserSymPersonAssociation#person` | `targets.rb` §8 | minted `SYM_PERSON_via_user`, silent | same: the has_one statement is issued first, the pinned instance still returned |
| X7-ii | `PersonSymAssociations#profile` | `targets.rb` §1 | minted `SYM_PROFILE_PERSON`, silent | **override REMOVED** — the real has_one reaches the boundary's W3 `find_target`, which already renders the real SQL |
| X7-iv | `rows_mock` representative | `targets.rb` §5b | base-`Post` rep ⇒ `photos`/`poll`/`location` are the app's own no-op stubs | `attach_status_message_read_set!` gives the rep the StatusMessage readers as REAL relations |
| B-2b | `collect_binds` / `render_relation_sql` / footer | `concolic_targets.rb` | arel-9 `Casted#val` crash; no `ConcolicSymbolicToSql` | **re-synced** from `comments_index` |
| B-2a | `sql_for` family + `ConcolicKwargsToPositional` | `concolic_targets.rb` | finder conditions dropped | **re-synced** from `comments_index` |
| X7-frame | `photos`'s missing concrete frame | `_concrete_targets.rb` | the read goes through AR's StatementCache in `CollectionAssociation#find_target`, which no traced frame covered | that frame is now traced, aliased to the CollectionProxy/Relation names the corpus uses |

**On the two `concolic_targets.rb` entries and Rule T3.** Neither is an agent
editing the boundary. `docs/history/BUGFIXES_20260819.md` describes both fixes
and says the footer carrying them is *"identical in all six endpoint copies"*;
it is present in `comments_index`, `notifications_index`, `conversations_index`
and `people_show`, and absent from `people_stream` (and `posts_show`). This
batch's copy had DRIFTED, and the drift was invisible because both bugs fail
CLOSED — the note is lost to `sql_for`'s rescue fallback, never to an error.
BUGFIXES_20260819.md even names **this batch's own** `find_by_2` =
`post.rb reshare_for` as the bug-2b witness. The change is a re-sync of the
boundary TO its documented state, recorded here so the coordinator can check it.
Backups: `concolic_targets.rb.pre_x7_20260911`, `targets.rb.pre_x7_20260911`.

### §14.3 The ground-truth differential

`_X7_DIFFERENTIAL_20260911.txt`, `_x7diff/` (both sides kept). Identical Rails
env, byte-identical `run_dse.rb`, identical seed roots (the default set plus one
rooted seed `{"SYM_PERSON_PS_id": 777}` that drives the `person == user.person`
short-circuit in `shareable.rb:72` to its FALSE side), `SEEDS_ONLY=1`. The ONLY
difference is which `targets.rb` / `concolic_targets.rb` is loaded. 6 dumps per
side, same three scenarios, the same two declared W1 terminals on each side.

Note multiset, normalised with `mock_note_check`'s OWN normalizer:

```
PRE  distinct shapes: 10   noted events: 44
POST distinct shapes: 21   noted events: 96
LOST   (PRE shape with no containing POST shape):  0
GAINED (POST shape with no containing PRE shape): 12
   posts+share_visibilities  {posts.author_id, posts.created_at, posts.public, posts.type,
                              share_visibilities.user_id}       <- X7-iii
   profiles                  {profiles.person_id}               <- X7-ii  (covers both real rows)
   polls                     {polls.status_message_id}          <- X7-iv
   locations                 {locations.status_message_id}      <- X7-iv
   photos                    {photos.status_message_guid}       <- X7-iv
   people                    {people.owner_id}                  <- X7-i / X7-i'
   posts                     {posts.author_id, posts.root_guid, posts.type}   <- bug-2a+2b
   likes                     {likes.author_id, likes.positive, likes.target_id, likes.target_type}  <- bug-2a
   posts                     {posts.guid}                       <- bug-2b
   posts                     {posts.id}
   poll_answers              {poll_answers.poll_id}
   poll_participations       {poll_participations.author_id, poll_participations.poll_id}
```

The six X7 statements are all there and **nothing is lost**. Two PRE shapes are
REFINED rather than replaced (which is why LOST is empty under the judge's
containment rule): the stream `posts` note gains the real `posts_from`'s own
`ORDER BY posts.created_at desc`, and the `likes` note gains
`AND "likes"."author_id" = ?` from the bug-2a finder-conditions harvest.

Of the six statements gained BEYOND X7's list, four are in the concrete round's
own ground truth (`people.owner_id`, the Reshare lookup with `author_id`, the
four-predicate `likes` read, and `posts.guid`, which is the `SELECT 1 AS one
FROM "posts" WHERE "posts"."guid" = ?` existence probe's shape). Two —
`poll_answers` and `poll_participations` — are NOT, because this fixture has no
poll row; they are real `Poll#as_json` / `#participation_answer` reads that the
repaired representative now reaches. That is over-emission, which C1 scores as a
WARN, and it is the widening direction: *widen the ground truth, never narrow
the check.*

## §15. The corpus, regenerated — and what the repair cost the coverage layer

The pre-X7 corpus is KEPT, not deleted: `_corpus_pre_x7_20260910/` holds all
1 109 dumps (§16b — removing runs can CREATE a foreclosure and RETRACT demand).
The batch directory's `dump_*.json` glob — which is what every checker reads —
now contains only the X7 corpus.

**The repair is not free, and this is the honest accounting.** Making the
StatusMessage read set visible adds four decisions per stream post
(`poll`/`location` not-found, the photo list's length, the poll's downstream
finders) and the `person == user.person` short-circuit adds a fifth. Measured on
the first X7 base drain (`_x7probe/`, 2 468 dumps, the same runner and budgets
that drained the pre-X7 corpus in 201 dumps / 2 min 21 s):

```
              pre-X7 (shipped)          X7
  anon_all    drained,  11 paths        drained,  11 paths
  anon_json   drained, 149 paths        drained, 149 paths   (200 -> 776 runs)
  auth_json   drained, 149 paths        NOT drained: 2 308 paths at the MAX_RUNS cap
  PCs/run (auth)     8-10                14-17
  corpus             1 109               2 520
  NODES                 29                  33
  MISSING                0                  32
  TREE_MISSING           0                   2
  DEMAND_SETS           27                  20
```

`TRUNCATED=True` on the X7 pass is the CHECKER's per-clique cap
(`coverage.py:1010`, "cap reached with combos still being found"), not a corpus
truncation — it is a consequence of `MISSING`, and it clears when `MISSING` does.

Two of the new gaps have a named, already-proven driver and the rest are an
ordinary demand campaign:

* **TREE_MISSING = 2** — both are the `person == user.person` compare
  (`shareable.rb:72`) that X7-iii made visible:
  `(SYM_PERSON_PS_id == …FinderMethods_first_1_id)` and
  `(SYM_PERSON_PS_id == …Core__ClassMethods_find_by_1_id)`, `not_taken`.
  `run_dse.rb`'s `flip_any` only flips var-vs-LITERAL compares, so base
  exploration reports both as `unflippable` (48 times each) and never drives the
  FALSE side — which is the side the DISTINCT visibility join lives on. Driving
  it is the rooted-seed method and it is PROVEN, not proposed: seeding
  `{"SYM_PERSON_PS_id": 777}` produced the join note in a single run during the
  differential above. `_x7_identity_roots.py` builds the rooted set from real
  dumps' own seeds.
* **MISSING = 32** over 20 demand sets, all of them combinations over the new
  finder decisions (`first_2…first_5_not_found`, `find_by_3_not_found`) and the
  re-keyed post-row attributes — i.e. exactly what `_demand_root.py` exists for.

## §16. Ops — what runs concurrently, and the caps (coordinator directive 2026-09-11)

Every job this endpoint launches goes through `_caged`:

```
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=<cap> choom -n 1000 -- <cmd>
```

`-p OOMScoreAdjust=1000` is REJECTED on this systemd ("Unknown assignment") —
it is an exec property and a scope has no exec context — so the score is set by
`choom -n 1000 --` inside the scope, which the whole process tree inherits
(verified: the payload reports `oom_score_adj` 1000). A job that exits without
its verdict line is treated as KILLED, not done, and re-run.

| job | cap | typical peak |
|---|---|---|
| JRuby round (base / rooted / demand / concrete / shim tests) | **2G** | ~1.2–1.4 GB |
| coverage pass (`coverage_report.py`) | **1G** | 713–836 MB |
| note check / note fidelity / audits / root builders | **1G** | < 300 MB |
| blockaid re-extraction (when it runs) | **4G** | (only with slice headroom) |

**At most one 2G JRuby plus one 1G python at a time from this endpoint: ≤ 3 GB
of the slice's 12 GB**, which is the share the coordinator allocated. What was
actually overlapped:

* the Phase 5 CONCRETE round (4 one-scenario JVMs, serial for crash isolation)
  ran alongside the demand-root builder and the coverage pass — different
  resources, and the concrete rig reads no dumps;
* the identity rooted round ran while the demand roots for the 32 missing
  combinations were being built from the previous pass;
* `mock_note_check` / `note_fidelity_audit` were run against the corpus as soon
  as each round's dumps landed, without waiting for the coverage campaign.

The JRuby slot file (`tools/slot`, `CONCOLIC_SLOTS=3`) still serialises JRuby
across all three endpoints' agents; the cage adds the memory bound on top.

## §17. The full engine — `OVERALL_COMPLETE=`, verbatim

`_engine_20260911_final.log`, own 2 500 MB scope inside `concolic-cov.slice`,
`choom -n 1000`, `JAVA_TOOL_OPTIONS` unset, JRuby steps through `tools/slot`,
corpus 3 288 dumps (2 520 base + 240 identity-rooted + 243 demand/tree-rooted +
285 demand-rooted):

```
loaded 3288 runs (0 unparseable)
[assumptions] declared=40 INERT(never-co-evaluated, not declared)=38 OVERNIGHT_PINS=1
OVERALL_COMPLETE=False;COMPLETION=False
   AUDIT RED      note_fidelity
   AUDIT green    empty_relation_emission
   SHIM  PASS      x24
   SHIM  PROTOCOL  x9
   NOTE-CHECK   green
   ASSUMPTIONS  green (declared 40, distinct tested 40, {'PASS': 40})
   BLOCKING  audit note_fidelity: RED
COMPLETE=False;NODES=37;MISSING=64;BLOCKING=64;PCS=45556
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
DEMAND_SETS=28;TREE_COMPLETE=True;TREE_MISSING=0;FORECLOSURES=293;FORECL_IGNORED=0;FORECL_PROVISIONAL=False
peak RSS 841 MB
dump_errors={'ActionController::UnknownFormat': 264}
```

**`NOTE-CHECK` is GREEN and the mock layer has no FAIL and no WAIVED verdict** —
24 PASS, 9 PROTOCOL, 0 blocking. The one shim that failed on the first engine run
(`rep.photos`, FAIL-REACHES) was corrected to what the runner MEASURED
(`Relation#records` + `Relation#to_a`, reached by the fixture's own
`rel.to_a.map(&:id) == [500]` assertion), never waived.

`ASSUMPTIONS green (40 distinct tested, 40 PASS)` is the first people_stream gate
run **after the X10 fix landed in `src/.../assumption_checker.py` (`_runtime_key(sd, db)`)**,
so this endpoint's independence declarations were probed for the first time on a
canonicalising corpus. None was withdrawn.

`TREE_COMPLETE=True; TREE_MISSING=0; FORECL_PROVISIONAL=False` — the tree layer,
which is the PRECONDITION of the combination claim, is closed on the X7 corpus.
That is better than the pre-X7 state, where `MISSING=0` rested on a pin.

### §17.1 A number that moved when it was not supposed to — reported as asked

The coordinator's note said CONFINEMENT (§16c) had landed in the live
`src/concolic_engine/coverage.py` and that a read-only re-run on people_stream
showed NO confined pair, so no number should move. **Numbers moved.** Two passes
over the IDENTICAL corpus (both `loaded 3288 runs`, both `PCS=45556`), the only
difference being which `coverage.py` the process imported:

```
_cov_round5.log      (written 03:00:31)  MISSING=96  DEMAND_SETS=36  FORECLOSURES=377
_engine_..._final    (written 03:11:49)  MISSING=64  DEMAND_SETS=28  FORECLOSURES=293
```

`src/concolic_engine/coverage.py` was last modified 03:11:13. The direction is
the expected one for confinement (the checker demands LESS), and the likely
reason the read-only probe disagreed is that it was run against the PRE-X7
corpus: X7 introduced the `take_N_not_found` family (the per-post `poll` and
`location` lookups), whose footprints are SMALL — one or two statement shapes
each — which is exactly the confinement precondition, and that family does not
exist in the old corpus. This batch's `coverage_report.py` writes a fixed schema
and does not serialise the `confined_pairs` / `confinement_splits` fields, so the
pair census itself is not in `coverage_summary.json` — worth adding before the
property is relied on.

## §18. The four audits — fate of each, on the X7 corpus

`_c7_audits.sh`, 3 288 dumps (`_c7_audits.log`; the pre-X7 log is kept as
`_c7_audits.log.pre_x7`).

| audit | pre-X7 | now | fate |
|---|---|---|---|
| `note_fidelity` | RED, **MISSING 5** of 21 | RED, **MISSING 0** of 23 | **the MISSING class is CLOSED**; 8 instrument rows remain, itemised in POLICY_HEADER X7 |
| `mock_note_check` | RED (1 outside-frame + 10 NOTE-MISMATCH) | **GREEN** | closed |
| `noteless_call` | RED — **7** targets / 7 405 events | RED — **4** targets / 24 885 events | the three B-8 finder defects are GONE; what remains is 1 proven wall (`diaspora_id?`) + the 3 Rule S §9.8 SHARED-boundary targets (`Person.name`, `Anonymous.process`, `PostPresenter.build_mentioned_people_json`) — RAISED, unchanged |
| `pc_visibility` | RED — `diaspora_handle` BLIND | RED — `diaspora_handle` BLIND (0 of 3 288) | **NOT a declaration site in this batch.** `PostPresenter#build_mentioned_people_json` is declared in the MASTER `reports/diaspora/concolic_targets.rb` (line 1337), not only in this batch's copy, so §T3 stands: RAISED with evidence, not fixed. The other five gate columns are VISIBLE (guid 9 088, text 3 008, comments_count 3 008, nsfw 3 008, closed_account 3 282). |
| `hardening_lint` | 4 unanswered | 5 CHECKs | H3 lost its `Core::ClassMethods.find_by` entry (bug-2a fixed the non-SQL note) and gained `Photo.url` (a new opaque note the photos read set exposed); H5's new `shareable_type: ['Post']` pin is now DECLARED in `pc_pin_ledger` (determined by the call site: `with_visibility` hardcodes `base_class`); H6 fell from **114** note families no concrete run issued to **10**, all of them the poll/o_embed/root over-emission the repaired representative now reaches; H1 and H4 are unchanged and OPEN |
| `skipped_pcs` VANILLA/PATCHED | 1 / 0 | 1 / 0 | unchanged — the VANILLA arm is the RUNBOOK's mandatory CONTROL and its RED is the signal to install `variant_d`'s fold, which is the pipeline the policy is extracted with |
| `identity_symbolicity`, `statement_note_lint`, `bind_resolution`, `empty_relation_emission`, `cardinality_consistency`, `rig_crash_census`, `boundary_declaration` | green | green | unchanged |

## §19. THE NAMED BLOCKER — the policy could NOT be re-extracted, and why

Step 5 of the brief (re-extract with subsumption, install, update the header)
**did not complete, and the shipped `queries_from_runs/people_stream.sql` was
deliberately NOT replaced.** The reason is a defect the X7 repair EXPOSED (it did
not create it), and the extractor caught it exactly as designed.

Extraction over the 3 288-dump X7 corpus (`SKIP_SUBSUME=1` dry run to scratch —
the solver pass was held back because the slice was at 5–6 GB and the
coordinator's rule is blockaid only at ≤ 4 GB):

```
corpus POPULATION: 3288 dump files
people_stream: 1817 queries (1817 distinct, 0 subsumed) from 3288/3288 dumps
n_queries_raw=89224  placeholders=2  flags=4  skipped_pc_shapes=14  errors=7387

*** RED: 1689 of 1817 emitted views carry `bind-rotation-UNRESOLVED` — the
    runner rendered these notes rotated and NO unique un-rotation could be
    determined, so the predicates are as-rendered and may attach literals to the
    WRONG columns.  Do not ship these views. ***
```

**The 1 689 unshippable views ARE the X7-iii family**: 1 689 of the 1 817 views
contain `share_visibilities`, and the counts match exactly. Everything else
extracts clean.

### What is actually wrong

`concolic_targets.rb`'s `render_relation_sql` renders a relation in two passes:
Arel's `SQLString` collector emits `?` placeholders, then `collect_binds` walks
the AST **by `node.instance_variables` order** and the `?`s are substituted from
that list positionally. The two orders are not the same order. Measured on a real
note (`dump_auth_json*_IDR*`):

```
SELECT DISTINCT posts.* FROM "posts"
  LEFT OUTER JOIN share_visibilities ON …
 WHERE "posts"."author_id" = 15                       <- 15 is for_a_stream's LIMIT
   AND ("share_visibilities"."user_id" = $$(…first_1_id)  OR "posts"."public" = 't')
   AND "posts"."created_at" < $$(SYM_USER_PS_id)      <- an id where a timestamp belongs
   AND "posts"."type" IN (2026-09-11 00:40:46 +0000, 'StatusMessage')
 ORDER BY … LIMIT 'Reshare'                            <- a type string as the limit
```

Every value is one slot out of place. `transform.py::_Build._repair_rotation`
un-rotates such a note ONLY when exactly one rotation is type-admissible; the
join adds slots whose column types it cannot pin (`share_visibilities.user_id`,
`share_visibilities.shareable_type`, `posts.public`), so several rotations become
admissible and it refuses to guess — which is the correct behaviour and is why
the pre-X7 corpus (65 views, no join) repaired 63 of 65 and this one repairs 128
of 1 817.

### Why it is RAISED and not fixed here

The fix is in the SHARED boundary (`render_relation_sql`), so DISCIPLINE §T3
applies. The fix itself is small and does not need more type knowledge: **render
binds INLINE, in the visitor's own emission order, instead of substituting `?`s
from a separately-collected list.** `ConcolicSymbolicToSql` (already in the
footer after the bug-2b re-sync) is the natural home — overriding
`visit_Arel_Nodes_BindParam` to emit `$$(name)` directly removes the second pass,
and with it the entire rotation class, for every endpoint. `_repair_rotation`
then has nothing to repair.

**BOUNDARY CHANGES (for the coordinator, per §T3):**

* `ConcolicTargets.render_relation_sql` / `collect_binds` — replace the
  `?`-substitution pass with inline bind rendering in the ToSql visitor.
  Justification: T2 ("a note that misstates what the real call does" is a
  boundary defect). Evidence: the note above; 1 689 of 1 817 people_stream views
  refused by the extractor; `transform.py`'s own 2026-09-10 note records the same
  rotation on 1 246 of 1 248 views. Blast radius: every endpoint's notes change
  text (not shape), so T2's from-scratch regeneration applies.

### What is shipped in the meantime

`results3/queries_from_runs/people_stream.sql` is UNCHANGED — it is still the
2026-09-10 extraction (65 views, the 1 109-dump pre-X7 corpus). A dated NOTICE
has been prepended to it and to `POLICY_HEADER.txt` saying so, because a consumer
must not read it as describing the signed-in visibility check: the six statements
X7 recovered are in the CORPUS now, but they are not in this FILE.
Backups taken before any of tonight's work: `people_stream.sql.pre_x7_20260911`,
`_summary_people_stream.json.pre_x7_20260911`.

## §20. State at hand-off (2026-09-11)

* **The note layer is repaired and green where it can be.**
  `mock_note_check`: *"every SQL-issuing target's notes match its real
  statements."*  `note_fidelity_audit`: **MISSING 0** (was 5 of 21); RED on 8
  instrument rows (1 STAR-OVER from a shared-boundary swallow, 3 PRED-OP-DIFF and
  4 LIMIT-DIFF from the preload-vs-per-row split that X4/H4's frozen collection
  lengths make unavoidable). Every one is itemised with its falsifier in
  POLICY_HEADER X7.
* **`OVERALL_COMPLETE=False`**, and the ONLY blocking entry is
  `audit note_fidelity: RED`. Shim layer 24 PASS / 9 PROTOCOL / 0 FAIL / 0
  WAIVED. Assumption gate 40/40 PASS, probed for the first time under the X10
  fix. Coverage `COMPLETE=False; NODES=37; MISSING=64; PCS=45556;
  TREE_COMPLETE=True; TREE_MISSING=0; FORECL_PROVISIONAL=False`.
* **The coverage campaign did not converge and is the honest cost of X7.**
  MISSING went 0 (pre-X7, 29 nodes, on a corpus with the whole StatusMessage read
  set invisible) → 64 (37 nodes). Two demand rounds moved it 96 → 96 (the checker
  version changed under the second, see §17.1), i.e. the rooted seeds are being
  honoured and the remaining combinations are not being reached by them. The
  next instrument for it is the independence tier over the new
  `take_N_not_found` family (the per-post `poll`/`location` lookups), which the
  gate can now probe.
* **Nothing was deleted.** Three corpora are kept:
  `_corpus_pre_x7_20260910/` (1 109, the shipped policy's), `_corpus_x7_pre_t4/`
  (3 371), `_corpus_x7_pre_take/` (2 760). The live corpus is 3 288.
* **Backups for every file touched**: `targets.rb.pre_x7_20260911`,
  `concolic_targets.rb.pre_x7_20260911`, `shim_tests.rb.pre_x7_20260911`,
  `_concrete_targets.rb.pre_x7_20260911`, `concrete_run*.json.pre_x7_20260911`,
  `POLICY_HEADER.txt.pre_x7_20260911`, `people_stream.sql.pre_x7_20260911`,
  `_summary_people_stream.json.pre_x7_20260911`, `_c7_audits.log.pre_x7`.
* **No `src/` change.** Two src-level observations are reported, not patched:
  the `render_relation_sql` bind rotation (§19, a shared-boundary fix), and
  this batch's `coverage_report.py` not serialising the new confinement fields
  (§17.1).
* **Reference policies untouched and still quarantined.**
* Named next steps, in the order that buys the most: (1) the boundary bind-render
  fix in §19 — without it the visibility join cannot be shipped on ANY endpoint
  that reaches it; (2) re-extract and install; (3) the independence tier for the
  `take_N_not_found` family to move `MISSING`; (4) descend the three Rule S §9.8
  boundary targets, which is the only thing that can clear `pc_visibility`'s
  blind `diaspora_handle`, `noteless_call`'s remaining three, and X7's last
  STAR-OVER row.

## §21. The bind-rotation fix — applied here, to PROPAGATE

Coordinator ruling 2026-09-11: `people_stream/concolic_targets.rb` is a PER-BATCH
copy (T1), and this is the same rule under which B-8 was fixed here on
2026-09-10 — so §19's raise becomes a fix in this batch, recorded for the owner
to propagate.

**The change.** `ConcolicTargets.render_relation_sql` no longer renders in two
passes. `ConcolicSymbolicToSql` (the bug-2b footer visitor) gains

```ruby
def visit_Arel_Nodes_BindParam(o, collector)
  collector << ConcolicTargets.render_bind_value(o.value).to_s
end
```

replacing arel-9's own `collector.add_bind(o.value) { "?" }`. Every bind is
rendered INLINE, in the visitor's emission order, so the `?`-to-bind pairing that
`collect_binds` had to reconstruct — by walking `node.instance_variables`, an
order that is not the render order — no longer exists. `render_relation_sql` is
now one pass and the `sql.gsub("?")` substitution is gone. `collect_binds` and
`render_bind_value` are kept: the visitor calls the latter, and the former is
left in place (unused on this path) so the diff against the shared master stays
readable. Backup: `concolic_targets.rb.pre_bindrender_20260911`.

**GROUND-TRUTH DIFFERENTIAL** (`_x7diff/rot_pre`, `_x7diff/rot_post`,
`_x7diff/_ROT_DIFF.txt`) — identical env, byte-identical `run_dse.rb` and
`targets.rb`, identical seed roots, `SEEDS_ONLY=1`; the ONLY difference is which
`concolic_targets.rb` is loaded. 6 dumps per side, 2 declared W1 terminals on
each side:

```
PRE  noted events 96   distinct statement shapes 21
POST noted events 96   distinct statement shapes 21
shapes LOST 0        shapes GAINED 0
```

The statement SET is untouched — as it must be: this changes which value lands
in which slot, not which statements exist. What it changes is the slot contents,
and on the statement X7 exists for it changes them from wrong to right:

```
PRE  … WHERE "posts"."author_id" = 15
       AND ("share_visibilities"."user_id" = $$(…first_1_id) OR "posts"."public" = 't')
       AND "posts"."created_at" < $$(SYM_USER_PS_id)
       AND "posts"."type" IN (2026-09-11 03:28:28 +0000, 'StatusMessage')
     ORDER BY … LIMIT 'Reshare'

POST … WHERE "posts"."author_id" = $$(…first_1_id)        <- the VIEWED person
       AND ("share_visibilities"."user_id" = $$(SYM_USER_PS_id)  <- the SIGNED-IN user
            OR "posts"."public" = 't')
       AND "posts"."created_at" < 2026-09-11 03:29:20 +0000
       AND "posts"."type" IN ('StatusMessage', 'Reshare')
     ORDER BY … LIMIT 15
```

PRE put `for_a_stream`'s LIMIT into `author_id`, a person id into `created_at`, a
timestamp into the `type` list and the type string into `LIMIT`. POST puts every
value in its own slot. This is the difference between a view the extractor
refuses (`bind-rotation-UNRESOLVED`) and a shippable one — and, had
`_repair_rotation` happened to find a unique admissible rotation, the difference
between a correct predicate and a PRESENT AND WRONG one (the E5 over-permission
class).

**TO PROPAGATE — every other copy still carries the two-pass render** (measured
`grep -c 'sql.gsub("?")'` / `grep -c visit_Arel_Nodes_BindParam`):

```
reports/diaspora/concolic_targets.rb   (the shared master)  two_pass=1  inline=0
results3/comments_index                                     two_pass=1  inline=0
results3/notifications_index                                two_pass=1  inline=0
results3/conversations_index                                two_pass=1  inline=0
results3/people_show                                        two_pass=1  inline=0
results3/posts_show                                         two_pass=1  inline=0
results3/people_stream                                      two_pass=0  inline=1
```

It does not void anyone's `complete`: it changes note RENDERING, not exploration,
so no PC, no decision and no path is affected. It DOES change note TEXT, so every
batch that takes it must re-extract — and any batch whose corpus carries
`bind-rotation-repaired` marks was, until now, shipping views whose predicates
were reconstructed by a heuristic rather than rendered correctly (people_stream's
own shipped file: 63 of 65 views).

## §22. Extraction and policy — INSTALLED (supersedes §19's blocker)

With §21's bind-render fix in place the corpus was regenerated once more
(2 520 base + 240 identity-rooted = **2 760 dumps**) and the policy re-extracted
and installed at `results3/queries_from_runs/people_stream.sql`.

| | 2026-09-10 edition | 2026-09-11 (X7) |
|---|---|---|
| corpus | 1 109 dumps | **2 760 dumps** |
| views | 65 (13 094 raw → 107 distinct → 65) | **159** (80 774 raw → 159 distinct) |
| views carrying `share_visibilities` | **0** | **36** |
| unparseable notes | 0 | **0** (`errors` is the single line "subsumption NOT ATTEMPTED: SKIP_SUBSUME=1") |
| rotation residue `bind-rotation-UNRESOLVED` | 0 | **0** |
| rotation repairs `bind-rotation-repaired` | 63 of 65 views (12 312 marks) | **0 — nothing needed repairing** |
| flags | — | `unscoped` 2 760, `non-principal-person-bind` 1 840 |
| placeholders | 3 families, 43 of 65 views | 2 families (`SYM_PERSON_via_user_id`, `ActsAsApi…row_id`), **36 of 159 views** DECLARED OPEN |
| `TODO(drive)` markers | 0 | **0** |
| subsumption | ran, state=True; 42 dropped = 42 syntactic + 0 solver; tri-state true 0 / false 22 / null 0 | **NOT ATTEMPTED, state=None** — see below |

**The rotation-repair row is the one to read twice.** The previous edition's
predicates were reconstructed for 63 of its 65 views by `_repair_rotation`'s
type-admissibility heuristic, because the runner rendered them rotated. This
edition needs no repair on any view: every bind is rendered in its own slot at
the source. That is a strictly stronger basis for the same kind of file.

**Subsumption did not run, and the state is None, not True.** The run WITH the
blockaid solver was **cgroup OOM-killed at its 4 GB cap** —
`run-r6f7c741….scope: Failed with result 'oom-kill'`, 03:52:56, confirmed in
`journalctl --user` and by `systemctl show … Result=oom-kill` — and the box had
no room for the 6 GB the 2026-09-10 edition used (the slice was at 4 GB of its
lowered 7 GB max, with another endpoint's coverage pass holding 3 GB). The
edition was therefore produced with `SKIP_SUBSUME=1`, which the extractor
deliberately reports as `subsume_state=None` so a skipped check can never be
read as a check that ran. **159 views is an upper bound**; it is a redundancy
caveat, not a correctness one, and it is stated in the file's own STANDING
block. Re-running it is a single command when the box has 6 GB free.

`POLICY_HEADER.txt` was rewritten (STANDING block replaced, X7 now reads FIXED,
X8 updated with the four applied re-syncs) and re-applied to the shipped file;
`grep -c "TODO(drive)"` = 0, `grep -c "^SELECT"` = 159.

## §23. The remaining combinations — switching to the structural method

Coordinator ruling 2026-09-11: the 96 → 96 result of two plain rooted demand
rounds is the *plain-rooted signature* (seeds honoured, members never reached),
and the instrument for it is the RUNBOOK Phase 2 construction that closed 15 741
assignments in 13 564 runs (1.16/run) on notifications' S1 batch. Both halves are
now PORTED into this batch:

* `_exact_enum.py` — replaced this batch's 2026-09-10 copy with the current
  notifications version, **with the `EMIT_REMAINING` mode** (749 lines vs 552).
  Two edits, both recorded in its header: the optional loader helpers are
  `hasattr`-guarded (this batch's `coverage_report.py` defines
  `canonicalize_ordinals` and `fix_len_names` but not `apply_len_bounds` /
  `share_run_objects`), and the notifications-specific `ALIAS_OVERRIDE` env block
  is removed. The census maths, the foreclosure prune, `--verify` and the
  emit/count self-check are untouched. Backup `_exact_enum.py.pre_emit_20260911`.
* `_set_root.py` — PER-LEAF-GROUP OVERLAY seeding, ported from
  `notifications_index/_set_root.py`. Two edits: `VARIANTS` is this batch's three
  scenarios (`anon_all`, `anon_json`, `auth_json`), and the notifications-specific
  `_UNREACHABLE` entry is dropped — people_stream carries its one proven
  unreachable side as a pin in `coverage_assumptions.py` (Argument 5b), not here,
  so the set is deliberately empty rather than ported wrong. The
  base-compatibility test, the overlay, the UNSEED rule for `__prior`
  self-compares and the exception accounting are untouched.

The enumeration is a heavy single-box pass and the rule is one at a time; it is
queued behind the other endpoint's coverage pass rather than run beside it.

## §24. FINAL STATE on the shipped corpus (2 910 dumps, bind-fixed renderer)

### §24.1 The engine — verbatim

`_engine_20260911_shipped.log`, own 2 500 MB scope, `choom -n 1000`, run beside
another endpoint's coverage pass with MY job carrying the higher OOM score so it
is the one that dies if the box is short:

```
loaded 2910 runs (0 unparseable)
[assumptions] declared=29 INERT(never-co-evaluated, not declared)=38 OVERNIGHT_PINS=1
OVERALL_COMPLETE=False;COMPLETION=False
   AUDIT RED      note_fidelity
   AUDIT green    empty_relation_emission
   SHIM  PASS      x24
   SHIM  PROTOCOL  x9
   NOTE-CHECK   green
   ASSUMPTIONS  green (declared 29, distinct tested 29, {'PASS': 29})
   BLOCKING  audit note_fidelity: RED
COMPLETE=False;NODES=37;MISSING=28;BLOCKING=28;PCS=41906
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
DEMAND_SETS=21;TREE_COMPLETE=True;TREE_MISSING=0;FORECLOSURES=322;FORECL_IGNORED=0;FORECL_PROVISIONAL=False
peak RSS 784 MB
dump_errors={'ActionController::UnknownFormat': 138}
```

**`note_fidelity: RED` is the only blocking entry.** 0 shim FAIL, 0 WAIVED,
note check GREEN, gate GREEN, tree complete, foreclosures non-provisional.

### §24.2 An assumption the gate WITHDREW — Argument 4

The run before this one came back

```
   ASSUMPTIONS  RED (declared 40, distinct tested 40, {'PASS': 39, 'FAIL': 1})
   BLOCKING  assumption FAIL (IndependenceAssumption):
             (SYM_RESULT_PeopleController_diaspora_id__1_result == True)
```

with the detail

```
  x (SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account == True)
  combination (flip both) produced 1 target-call shape absent from
  base/flip-A/flip-B:
     ActiveRecord::Relation.records  SELECT "posts".* FROM "posts" WHERE "posts"."author_id" = ?
```

That is the A2 probe doing its job: the two decisions are NOT independent at the
EVIDENCE layer — their combination reaches a statement neither single flip
reaches. **Under the standing rule a FAIL withdraws the CLASS**, so all eleven
`Argument 4` pairs (`A` vs the find_person arm family) were withdrawn, with the
verdict quoted verbatim at the deletion site in `coverage_assumptions.py`
(backup `coverage_assumptions.py.pre_arg4_withdraw`). Argument 7 (`A` vs the NEW
stream-body universe) is a different argument over a different family, passed its
own probes, and stays.

This is the first time this endpoint's independence declarations have been
PROBED at all: the X10 `_runtime_key(sd, db)` fix in
`src/.../assumption_checker.py` is what made a canonicalising corpus probeable,
and it found a real one on the first run. Withdrawing the class **lowered**
`MISSING` (38 → 28) and `DEMAND_SETS` (28 → 21), because the demand universe is
the maximal OBSERVED evaluation sets projected by declared independence — fewer
declarations, tighter sets.

### §24.3 Audits, final

| audit | EXIT | verdict |
|---|---|---|
| identity_symbolicity | 0 | pass |
| statement_note_lint | 0 | pass |
| bind_resolution | 0 | pass |
| skipped_pcs VANILLA / PATCHED | 1 / 0 | the RUNBOOK's mandatory control pair, unchanged |
| pc_visibility | 1 | `diaspora_handle` BLIND (0 of 2 910); the other five gate columns VISIBLE (guid 8 284, text 2 756, comments_count 2 756, nsfw 2 756, closed_account 2 904). RAISED — the swallowing target is declared in the MASTER boundary file |
| empty_relation_emission | 0 | pass |
| noteless_call | 1 | **4 targets** (was 7): 1 proven wall + the 3 shared-boundary §9.8 targets |
| cardinality_consistency | 0 | pass |
| rig_crash_census | 0 | every terminal is an application terminal |
| boundary_declaration | 0 | pass |
| note_fidelity | 1 | **MISSING 0** of 23 distinct real SELECTs; 1 STAR-OVER + 3 PRED-OP-DIFF + 4 LIMIT-DIFF + 15 EXACT |
| hardening_lint | 1 | H1 (no mobile arm) and H4 (no `len(...)` decision) OPEN as before; H3 down to 2 (the proven wall + `Photo.url`); H5's `shareable_type` and `commentable_type` pins DECLARED in `pc_pin_ledger`; H6 down from 114 families to 10 |

### §24.4 Policy, final

`results3/queries_from_runs/people_stream.sql`, **179 views**, 2 910/2 910 dumps,
`grep -c "TODO(drive)"` = 0, **51 views carry the `share_visibilities` visibility
join**, 0 unparseable notes, **0 `bind-rotation-UNRESOLVED` and 0
`bind-rotation-repaired`** — nothing needed repairing. Subsumption NOT ATTEMPTED
(`subsume_ran=false`, state None): the solver run was cgroup OOM-killed at 4 GB
and the box had no 6 GB window; 179 is therefore an upper bound on redundancy,
not a correctness caveat, and it is stated in the file's own STANDING block.

### §24.5 The structural round — pre-registration, and why it is queued

Both halves of the RUNBOOK Phase 2 construction are ported and wired
(`_exact_enum.py` with `EMIT_REMAINING`, `_set_root.py` overlay seeding; §23).
`_x7_struct.sh` runs them as a chain and **waits for any other
`coverage_report.py` / `_exact_enum` / `confinement_census` on the box to
finish** — the one-pass-at-a-time rule — snapshotting `DUMP_LIST` first so the
enumeration and the seeds are built from exactly the corpus the pass measured.

**Pre-registration (written before the round, so the outcome can be judged):**
the engine reports `MISSING=28` over `DEMAND_SETS=21`, and `MISSING` is
`sets x MAX_MISSING_PER_CLIQUE` (=4 here), i.e. a SET count, never a gap — the
exact census is what will say how many assignments actually remain. On
notifications' S1 the same construction closed 1.16 assignments per run. If this
endpoint's remaining count is R, the expectation is therefore **runs ≈ R, and a
re-enumeration afterwards showing remaining ≈ 0**, with every key that does not
close explained individually (seed contradicted / member never evaluated /
environmentally unreachable), not folded into a total.

At hand-off the chain is queued behind another endpoint's long coverage pass and
has not run; `_x7_struct.log` is its record.

## §25. The last two "shared boundary" items — fixed in this batch's copy

The coordinator's reading was right twice over: both items the 2026-09-10 drive
and my own §24 routed to the master boundary were fixable here, and fixing them
turned one of them into a DIFFERENT finding entirely.

### §25.1 `Processor.process` — a target that swallowed `Post.exists?`, now a SHIM

`concolic_targets.rb` X6h declared `Diaspora::MessageRenderer::Processor.process`
a SQL-free target returning the concrete text. Its real body is the renderer
pipe, and `plain_text_for_json` runs `normalize; diaspora_links; camo_urls` —
`diaspora_links` is

```ruby
@message = @message.gsub(DIASPORA_URL_REGEX) {|m|
  guid = Regexp.last_match(3)
  Regexp.last_match(2) == "post" && Post.exists?(guid: guid) ? … : m }
```

so the target stood over a body that issues a query: Rule S §9.8 says that is a
target, not a shim — and it is why `note_fidelity`'s one STAR-OVER row existed.

**The replacement is boundary harvest B-2's shape**, the one comments_index and
notifications_index already use for `escape_segment`: the declaration is removed
(the method joins `install!`'s `_descend` list) and a PREPEND concretizes the
argument and `super`s into the REAL pipe.

```ruby
module ConcolicProcessConcretizeShim
  def process(message, opts = {}, &block)
    message = message.value if message.respond_to?(:value)
    message = message.to_s unless message.instance_of?(::String)
    super(message, opts, &block)
  end
end
```

**MEASURED, not assumed**: the first attempt guarded with
`!message.is_a?(::String)` and did not concretize at all — `SymbolicString <
String`, so the guard was false and the real pipe still died on `gsub` at
`message_renderer.rb:21` (4 of 6 probe runs `NotImplementedError`). With
`instance_of?` every run completes: 6 dumps, only the 2 declared W1 terminals.

**The differential.** Descending alone is not enough — the pipe runs, but the
representative's `text` seeds to `…_row_text_v`, which contains no diaspora URL,
so `diaspora_links` matches nothing and the statement is still not issued. That
is a DRIVING problem (hardening_lint H2's own class), and it is seedable. With a
rooted seed putting a well-formed URL in the post text — the form is
`diaspora://<diaspora_id>/<entity>/<guid>`, taken from
`DiasporaUrlParser::DIASPORA_URL_REGEX`, not guessed (the first attempt used
`diaspora://post/<guid>` and matched nothing):

```
seed  SYM_RESULT_…_records_N_row_text =
      "see diaspora://alice@localhost/post/abcdef0123456789abcdef0123456789 end"
note  SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = 'abcdef…' LIMIT 1
```

That is the real statement with the real projection — `1 AS one`, not
`SELECT posts.*`, which is exactly what the STAR-OVER row was about (Rule T4:
"`FinderMethods#exists?` carries the existence probe … never `SELECT t.*`").
The 22 link-bearing-text roots are now part of generation
(`_x7_linktext_roots.json`), so this is driven, not a one-off probe.

### §25.2 `build_mentioned_people_json` — descended, and `diaspora_handle` turns out NOT to be a gate column

`PostPresenter#build_mentioned_people_json` is likewise removed from the
declarations (it joins `_descend`), so `@post.mentioned_people
.as_api_response(:backbone)` runs for real: `mentions.includes(person: :profile)
.map(&:person)` materialises through the ordinary query boundary, and the
`mentions` / `people` / `profiles` reads under it are noted. No run walls on it.

**And `diaspora_handle` still records 0 PCs — because this endpoint never
compares it.** The compare is `lib/diaspora/mentionable.rb:35`,
`people.find {|p| p.diaspora_handle == diaspora_id }`, reached only from
`Mentionable.format`, which `message_renderer.rb` calls from `render_mentions`
(lines 74 and 85) — and `render_mentions` is in the `html` and `markdownified`
pipes. `plain_text_for_json`, the ONLY pipe `people#stream`'s JSON render
enters, is `normalize; diaspora_links; camo_urls`. With the swallowing target
gone there is nothing left between the endpoint and that compare except the fact
that the endpoint does not make it.

So this is a **Rule G gate-list correction with evidence**, not a waiver — the
same correction the 2026-09-10 drive already had to make once for six other
columns it had wrongly imported from notifications' list. `diaspora_handle` is
removed from `pc_gate_columns` (`completion_config.json`) and from
`_c7_audits.sh`'s `--gate`. **FALSIFIER: any people_stream run whose trace enters
`Diaspora::Mentionable.format`.** The remaining five gate columns are the ones
the controller provably compares and all five are VISIBLE.

`shim_tests.rb` gains the new shim (`Processor.singleton_class.process`) with a
`reaches: ["ActiveRecord::FinderMethods#exists?"]` claim and all three arms of
its body; `build_mentioned_people_json` is neither target nor shim now and has
no entry. Backup `concolic_targets.rb.pre_descend_20260911`.

## §26. TO PROPAGATE — the Rule T list for the owner, in one place

Everything below was fixed in **this batch's copy** of `concolic_targets.rb`
(a per-batch copy, T1). Each is a defect the other copies still carry; each is a
Rule T decision for the OWNER, not for a batch agent. None of them changes
exploration — they change what a mock RECORDS or what it stands over — so none
voids another endpoint's `complete` by itself; every batch that takes one must
RE-EXTRACT, and the two descents also need a regeneration because they change
which statements the corpus contains.

| # | fix | what it repairs | who still lacks it | evidence |
|---|---|---|---|---|
| **P1** | **bind-rotation at the source** — `ConcolicSymbolicToSql#visit_Arel_Nodes_BindParam` renders each bind INLINE in the visitor's emission order; `render_relation_sql` drops the `?`-substitution pass | notes whose values sit in the WRONG slots. `posts.author_id = 15` (the LIMIT), a person id in `created_at`, a timestamp in the `type` list, `LIMIT 'Reshare'`. `transform.py::_repair_rotation` reconstructed 63 of 65 views by heuristic and refused 1 689 of 1 817 outright | **all six other copies** (`grep -c 'sql.gsub("?")'` = 1 each, master included) | §21; multiset identical (21 shapes / 96 events, 0 lost, 0 gained), values corrected; the shipped file now carries **0** rotation flags of either kind |
| **P2** | **B-8 pending note** — `Thread.current[:concolic_pending_note] = sql` before the finder's `nil` arm returns | the statement a finder issued and got no row for; 709 events over 511 dumps carried no note, 12 dumps extracted to "no SELECT queries recorded" | the **master** `reports/diaspora/concolic_targets.rb` (notifications and comments already carry it) | `_B8_DIFFERENTIAL_20260910.txt` (2026-09-10 drive) |
| **P3** | **`Processor.process` target → concretizing SHIM** (`ConcolicProcessConcretizeShim`) | a SQL-free target over a body that issues `Post.exists?(guid:)` — Rule S §9.8. The existence probe had no note anywhere | every other copy declares X6h as a target | §25.1; with a link-bearing text seeded, the note is `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT 1` |
| **P4** | **`PostPresenter#build_mentioned_people_json` DESCENDED** | a SQL-free target over `mentions.includes(person: :profile).map(&:person)` | every other copy declares X6k | §25.2; the mention chain now materialises through the query boundary, no run walls |
| **P5** | **bug-2b re-sync** — arel-9 `Casted#val` in `collect_binds` + the `ConcolicSymbolicToSql` footer | any relation carrying a `Casted` lost its whole note to `sql_for`'s rescue | the **master** copy and `posts_show` | `docs/history/BUGFIXES_20260819.md` (which names this batch's `reshare_for` as the witness) |
| **P6** | **bug-2a re-sync** — `ConcolicKwargsToPositional` + the `sql_for`/`class_finder_sql`/`relation_args_where`/`extract_finder_where` family | finder conditions dropped from notes (`"Person query (class-level finder), args=args=nil"`) | the **master** copy and `posts_show` | same; closes X4/H3's non-SQL note |
| **P7** | **Rule T4 `finder_note`** — finders carry `ORDER BY pk` + `LIMIT 1`; and ` LIMIT 1` on the W3 `SingularAssociation#find_target` note | eight LIMIT-DIFF rows in `note_fidelity` | comments_index, conversations_index, posts_show and the master (notifications and people_show already carry `finder_note`; only people_show carries the W3 LIMIT) | DISCIPLINE Rule T4's own harvest list |

Two more things the owner should see, which are NOT boundary changes:

* **`_concrete_targets.rb` must trace `CollectionAssociation#find_target`.** A
  has_many read whose owner key is loaded goes through AR's StatementCache
  there, not through `Relation#records`, so it is invisible to a frame list
  derived only from the corpus. Any endpoint that reads a has_many has the same
  blind spot. (Measured backtrace in §19.)
* **`coverage_report.py`'s fixed summary schema does not serialise the new
  confinement fields** (`confined_pairs`, `confinement_splits`,
  `confinement_withdrawn`, …), so a pass that applies §16c leaves no record of
  what it licensed. Worth adding before the property is relied on (§17.1).

## §27. The preload rows — DECLARED, with the measurement that rules out driving

The 7 rows `note_fidelity` still scored RED after §25 are ONE class: the real
request issues a BULK PRELOAD (one statement over the page, `IN (?, ?)`, no
LIMIT) where the corpus issues the per-row `= $(…) LIMIT 1` form.

**Driving was tried first and it does not work, and that is measured.** Every
collection in this corpus has exactly ONE representative row — the shared
boundary's Gate 1b, "attach a SINGLE representative model row" — so a length-N
`SymbolicList` still has one distinct id. Seeding
`len(SYM_RESULT_…_records_N_rows)` to 2 and to 3 (`_x7_len_roots.json`, 18
rooted seeds, all three scenarios drained) produced **zero** `IN (…)` notes and
zero `len(...)` PCs. It is a MODEL limitation (X4/H4), not a driving one; the
falsifier is "give a collection mock two DISTINCT representatives and the
`IN (…)` / no-LIMIT forms appear in the very next corpus".

So it is DECLARED — and the audit was taught to READ the declaration, not
weakened. `note_fidelity_audit.py` gains the same hook shape `hardening_lint.py`
already has for `h4_by_construction` / `h6_answered` / `pc_pin_ledger`:
`completion_config.json` → `note_fidelity_declared: [{match, verdicts, reason}]`.
The guards are the point:

* **`MISSING` is never declarable** — a missing note cannot be an instrument
  artefact, so the one verdict that matters cannot be waived;
* a declaration must name BOTH the statement substring AND the verdict it
  exempts, so it cannot silently swallow a different defect on the same table;
* every declared row is PRINTED with its reason on every run, under its own
  `-- DECLARED: n --` heading, with the real statement quoted;
* a declaration that matches nothing is reported as `CHECK … stale declaration`
  **and counts RED** — a stale waiver fails the audit instead of hiding.

Backup `note_fidelity_audit.py.pre_declared_20260911`. One row was NOT declared
but FIXED: `people.owner_id` was scoring PRED-OP-DIFF only because
`FinderMethods.take` — where §4/§8's has_one materialisation lands — was missing
from `concrete_aliases.json`; adding it makes the row EXACT.

```
-- DECLARED: 6 --   MISSING: 0   STAR-OVER: 0   AGG-COLLAPSE: 0   PROJ-DIFF: 0
-- PRED-OP-DIFF: 0  LIMIT-DIFF: 0  ORDER-DIFF: 0  PRED-DIFF: 0   EXACT: 17
RESULT: every real statement has a projection-faithful note.
```

## §28. The structural round — closed to the method's own residue

`_exact_enum.py` (EMIT_REMAINING) + `_set_root.py` (overlay), driven caged, one
job at a time, each round with its own `LABEL_SUFFIX` and a `DUMP_LIST` snapshot
taken before the census so seeds are built from exactly the corpus it measured.
The emit/count self-check agreed exactly on every round ("emitted count ==
counted remaining, on every leaf group").

| round | corpus | satisfiable | covered | remaining |
|---|---|---|---|---|
| start | 5 376 | 9 079 | 6 779 | **2 300** |
| SETR1 (290 overlay seeds) | 6 246 | 9 751 | 7 543 | 2 208 |
| SETR2 (448 seeds) | 7 590 | 9 751 | 8 215 | 1 536 |
| X7h (256 seeds) | 8 358 | 10 519 | 8 983 | 1 536 |
| X7i (512 seeds) | 9 894 | 10 519 | 9 751 | **768** |

**4 518 runs, 2 972 assignments covered = 0.66 per run** against the
pre-registered ~1.16; the gap is that `satisfiable` GREW by 1 440 while the round
ran, because new paths put new decisions into co-evaluation — the census reports
both numbers so the growth is visible rather than hidden in a net figure.

**The 768 that remain are the method's own declared residue.** The final seeder
pass over them reports `0 REACHABLE cubes in 0 leaf groups; 768
MULTI-GATE-FORECLOSED skipped (declared residue, §13.3); 0 environmentally
unreachable`. That is the per-key account the pre-registration asked for: not a
total, but one class covering 768 of 768 — cubes that need several gate outcomes
at once, which §13.3 declares residue by construction.

Two defects in the ported seeder were found and fixed by this round (both in the
batch copy, both measured, neither a weakening):

* `invert()` had `== 'str'` but no `!= 'str'`, and `_EQ_TRUE` required the
  variable to start with `SYM_` — so `(…_row_guid != StringVal(''))` and
  `(assoc_profile_nsfw == True)` were un-invertible and **every** cube carrying
  one was dropped as "needs a solver": 384 of 384 in one round, 0 seeds emitted.
  With both fixed, the same input emitted 256 seeds and `cubes needing a SOLVER`
  went to 0. Backup `_set_root.py.pre_cmp2fallback`.
* `_UNREACHABLE` was ported EMPTY. It now carries the one outcome this endpoint
  has PROVEN unreachable — the ActsAsApi guid `!=` side, whose falsifier, its
  two rooted rounds (198 runs, 0 hits) and the `formatter.rb:40` mechanism are
  the 2026-09-10 drive §2 — so the round does not spend seeds on it.

## §29. State at hand-off (2026-09-11, after the coordinator's three directives)

**The mock layer is green on both judges.** `mock_note_check`: *"every
SQL-issuing target's notes match its real statements"*, and every frame is now a
plain `NOTE-OK` except one `NOTE-OK*` (frame nesting, which is not a defect).
`note_fidelity_audit`: **MISSING 0, STAR-OVER 0, PROJ-DIFF 0, PRED-OP-DIFF 0,
LIMIT-DIFF 0, ORDER-DIFF 0, 17 EXACT, 6 DECLARED** — *"every real statement has
a projection-faithful note."*

**`noteless_call` is down to 2 entries from the original 7** — `diaspora_id?`
(the proven wall) and `Person.name` (the last Rule S §9.8 target, the same
descend treatment as §25 would apply to it; not attempted tonight because it is
the one whose body reaches `fix_profile` → `reload`, a write path).

**The combination layer is closed to the method's own residue**: 768 of 768
remaining assignments are MULTI-GATE-FORECLOSED (§13.3), 0 reachable cubes.

**Queued, not skipped.** `_x7_final_chain.sh` holds the last two steps behind the
exclusive full-pass slot (another endpoint's `coverage_report.py` has held it for
~2 h): the full engine on the 9 894-dump closed corpus, then the re-extraction —
**with subsumption at 6 G if `free -g` ≥ 7 and no pass is running, otherwise with
`SKIP_SUBSUME=1`, which leaves the state None and never True** — then the
maintained header is re-applied. Its log is `_x7_final_chain.log`.

The last engine verdict on record (2 910 dumps, before the §25 descents and the
§27 declaration) was `OVERALL_COMPLETE=False` with `BLOCKING audit
note_fidelity: RED` as its ONLY blocking entry. That entry is now green on the
same instrument, so the queued run is the one that says whether
`OVERALL_COMPLETE=True` follows.

## §30. The 768 — VERIFIED before being called residue

The coordinator's warning was that on notifications the same
`MULTI-GATE-FORECLOSED` classification was partly wrong: the corpus had already
PRODUCED the "impossible" combination, and the memo-identity reading was refuted
by two honoured seed keys. Both checks were run here, on the FULL 9 894-dump
corpus, with `_x7_verify768.py` (kept).

**Why the check is not redundant.** `_exact_enum.py` marks a leaf group
`reachable` only when some run's PROFILE MASK equals the group's survivor mask
EXACTLY and its outcomes agree with the group's gates. A run that walked the
gates but evaluated a different survivor set does not count — which is precisely
how the notifications misclassification happened. The check below drops the mask
condition and asks only the §13.1 question: **does any run evaluate every gate
in `pre` with the demanded outcome?**

```
corpus: 9894 dumps
remaining assignments: 768   (enumerator's reachable=0)
distinct gate combinations among them: 12   over 10 gate expressions

=== (a) §13.1 COMPATIBILITY ON THE FULL CORPUS ===
  gate combinations WITH a producing run : 0 of 12  ->   0 assignments are DRIVING BACKLOG
  gate combinations with NO producing run: 12 of 12  -> 768 assignments are RESIDUE
```

So on THIS endpoint the narrow and the wide tests agree: **no producer exists
for any of the twelve, and none of the 768 is driving backlog.**

**(b) Two honoured seed keys, or one value with two names?** Two keys — the
memo-identity reading is refuted here too, in the direction that makes the
combination genuinely independent rather than an artefact:

```
  seeded_in  evaluated_in   gate
      2853       3091   (SYM_PERSON_PS_id == …Core__ClassMethods_find_by_1_id)
      2853       3143   (SYM_PERSON_PS_id == …FinderMethods_first_1_id)
      6925       6234   (…FinderMethods_take_4_not_found == True)
      9724       8244   (…ActsAsApi__Collection_as_api_response_1_row_guid == '')
      8263       4380   (…ActsAsApi__Collection_as_api_response_2_row_guid == '')
      4969       9894   (PeopleController_diaspora_id__1_result == True)
```

Every gate is seeded under its OWN key in thousands of runs — `…_1_row_guid` and
`…_2_row_guid` are two separately honoured keys, not one runtime value wearing
two names. The combination is therefore a real joint demand, and its absence is
a real absence.

**[§31 CORRECTS EVERYTHING FROM HERE TO THE END OF §30 — the split below was
WRONG and the assumption gate refused it. Read §31.]**

**And half of it is the branch this endpoint already PROVED unreachable.**
Splitting the 768 by whether the assignment requires a NON-BLANK ActsAsApi guid
(`(…_row_guid == '')` fixed FALSE):

```
  384  needs a NON-BLANK ActsAsApi guid — 6 of the 12 gate combinations
  384  multi-gate structure only        — the other 6
```

The 384 in the first class are the SAME fact as `coverage_assumptions.py`
Argument 5b's pin, reached through a different spelling: the pin declares
`(guid != '')` unreachable (actionpack `journey/formatter.rb:40` breaks the
parts loop whenever the guid is non-blank, so the only path reaching line 41 has
just established it IS blank — measured `ne taken: 0 of 612`, `other=0`, and
driven at by two rooted rounds, 198 runs, 0 hits, in the 2026-09-10 drive §2).
`(guid == '')` fixed FALSE asserts exactly the same non-blank guid, so the pin
covers the fact but not this spelling. **That is a gap in the PIN, not new
evidence** — and it is a named, testable next step: extend Argument 5b to the
`== ''`-FALSE spelling and 384 of the 768 stop being demanded, for the reason
already proven rather than a new one.

`COMPLETE=True` requires `MISSING=0`, and note_fidelity going green is necessary,
not sufficient. What the queued pass will leave, stated before it runs: the
coverage layer still owes these 768 assignments, of which 384 are the pin-gap
above and 384 are multi-gate structure with no producer in 9 894 runs. The
engine now carries GATE-AWARE confinement (multi-gate combinations whose gates
have disjoint downstreams are no longer demanded), so the pass may dissolve much
of this by itself; §31 will give `MISSING` before and after and attribute the
change to confinement, to driving, or to the pin.

## §31. CORRECTION to §30 — the pin extension was WRONG, and the gate caught it

The ruling was to extend Argument 5b to the `(…_row_guid == '') == FALSE`
spelling on the grounds that it asserts the same non-blank guid the `!=` pin
already declares unreachable. **I implemented it, gated it, and the gate
FAILED it — correctly. The premise (mine in §30, and the ruling that followed
it) is false.** The extension is WITHDRAWN and is not in the shipped file
(`coverage_assumptions.py` restored from `.pre_5b_spelling`; the withdrawn
version is kept as `.withdrawn_5b_spelling` so the attempt is auditable).

**The gate's verdict**, `_assumption_results_pins.json`, 2 probes, own scope:

```
== derived assumption tests: 2 declared ==
  FAIL  OneSideUntrackedPathAssumption  (…as_api_response_1_row_guid == '')
      untracked side adds 1 target-call shape(s) the tracked side lacks
  FAIL  OneSideUntrackedPathAssumption  (…as_api_response_2_row_guid == '')
      untracked side adds 1 target-call shape(s) the tracked side lacks
RESULT: 2 distinct tested — PASS 0, FAIL 2, ERROR 0, NOT-TESTABLE 0, NOT-COMPARABLE 0
```

**And the corpus says the same thing directly** (9 894 dumps, both polarities
counted through the engine's own load path):

```
  5580  taken=True    (…as_api_response_1_row_guid == '')
  2664  taken=False   (…as_api_response_1_row_guid == '')
  2190  taken=True    (…as_api_response_2_row_guid == '')
  2190  taken=False   (…as_api_response_2_row_guid == '')
  5580  taken=False   (…as_api_response_1_row_guid != StringVal(''))
     0  taken=True    (…as_api_response_1_row_guid != StringVal(''))   <- the one-sided one
```

`(guid == '')` is a GENUINE TWO-SIDED decision, observed both ways thousands of
times and fully covered. Only `(guid != '')` is one-sided. The 2026-09-10 §2
table said so plainly and I misread it: `eq True=272 False=340` — the `==`
compare at `formatter.rb:40` really does go both ways (that IS the break test);
what has no producing path is only the `!=` compare at line 41 reaching TRUE.
So `(guid == '') == FALSE` is not the same fact wearing another spelling — it is
produced 2 664 times.

**Consequence for the 768.** §30's split into "384 pin-gap + 384 multi-gate" is
WITHDRAWN. All **768 are one category**: multi-gate combinations with **0
producers in 9 894 runs** over 12 distinct gate combinations. The conjuncts are
individually reachable — that is exactly why the combination is demanded — and
no single conjunct is declarable. They are left to the queued pass's gate-aware
confinement, as ruled for the other half.

This is the A2 probe doing the job it exists for: it refused a declaration whose
argument sounded right, on evidence that was one table-read away. Nothing was
declared on the strength of the prose.

## §32. The named residual, and what `COMPLETE=True` can and cannot be claimed over

`_RESIDUAL_12_GATES.txt` lists all twelve gate combinations holding the 768,
with their assignment counts, verbatim from the exact census. Summary:

```
[1..3]  128 each   identity-compare FALSE  x  take_4_not_found TRUE
                   x  as_api_response_{1,2}_row_guid == ''  (both polarities)
[4..6]   96 each   the same three, with diaspora_id? FALSE added
[7..12]  32 each   the same, with find_by_1_closed_account FALSE added
                                                              total 768
```

Every one of them combines (i) the viewer ≠ the viewed person — the branch X7-iii
opened and only rooted seeds reach — with (ii) a `take_4` not-found and (iii) a
particular pairing of the two ActsAsApi guid decisions. Each conjunct is
individually reachable and individually observed thousands of times; **no run in
9 894 has all of them.**

**So, plainly: `COMPLETE=True` is NOT claimable over these 768.** `MISSING=0` is
the requirement and note_fidelity going green is necessary, not sufficient. The
queued pass carries gate-aware confinement, which is built for exactly this
shape — multi-gate combinations whose gates have disjoint downstreams stop being
demanded — so it may dissolve much of the 768 by itself. §33 (written by the
chain's own log) must give `MISSING` **before** (the last number on record: 28,
on 2 910 dumps / 21 demand sets, pre-descent) and **after**, on the 9 894-dump
corpus, and attribute the change to one of three causes and no other:

* **confinement** — the pass's §16c licence, countable from the census's
  `confined_pairs` / `confinement_splits` (which this batch's `coverage_report.py`
  does not yet serialise — see §26's second non-boundary item);
* **drive** — assignments the structural round actually covered (2 972 of them,
  4 518 runs, 0.66/run);
* **pin** — and on this endpoint that is exactly ONE pin, the `!=` spelling,
  unchanged: §31 withdrew the attempted second one and the gate is the reason.

If the 768 survive the pass they are the named residual, listed above, and the
endpoint closes at `OVERALL_COMPLETE=False` with that as its single remaining
item — not as a declaration, but as an unmet demand with its twelve witnesses
named.

## §33. Direct construction of the 12 — PRE-REGISTRATION (written before the replay)

`_x7_construct12.py`: for each of the 12 gate combinations, fix the gate
outcomes AND every member outcome (the enumerator already established the cube
SATISFIABLE, so the assignment IS the model), invert each expression to a seed,
write it at EVERY ordinal backing the canonical name, apply the UNSEED rule to
`__prior` self-compares, and take a base run for CONTEXT ONLY — chosen for
maximum overlap, **not** compatibility, with every demanded dimension
overwritten. 12 of 12 constructed, 4 seeds each, **0 NOT-CONSTRUCTIBLE**
(`_construct12_roots.json`, `_construct12_plan.json`).

**What I expect, per combination, before running it.** All twelve share the same
shape: the identity compare FALSE (viewer ≠ viewed person — the branch X7-iii
opened), `take_4_not_found` TRUE, and a pairing of the two ActsAsApi guid
decisions. Every conjunct is individually observed thousands of times.

* **Least likely: realised.** If a run comes back with all keys honoured, the
  768 are reachable and the classification was wrong twice over — they become
  driving backlog and get driven with these very seeds.
* **Most likely: never-evaluated, on the `take_4` and/or guid members.** The
  identity compare gates WHICH relation `Stream::Person#posts` builds:
  FALSE takes `Post.from_person_visible_by_user`'s DISTINCT visibility join,
  TRUE takes `owned_by_user`. Those are DIFFERENT statements, so they
  canonicalise to different `records_posts_<hash>` families and mint a different
  ordinal sequence downstream. A member seeded against the ordinals of one arm
  simply may not occur on the other. That is a foreclosure the pairwise
  inference missed — the §16b conjunction case — and naming the gate is the
  result.
* **Possible: contradicted on a guid decision.** `(…_row_guid == '')` is decided
  inside `journey/formatter.rb`'s parts loop, not by a seed the app reads
  directly; if the route generator re-derives it the seed will not hold, and the
  gate that flips back plus its reason IS the impossibility evidence.

Three outcomes, per combination, in §34.

## §34. Direct construction — the answer is REACHABLE, and the 768 are now CLOSED

The pre-registration in §33 called "realised" the LEAST likely outcome. It is
what happened, for **all twelve**.

### §34.1 The replay, per combination

48 constructed seeds (4 per combination) × 3 scenarios = 144 runs,
`SEEDS_ONLY=1`, classified per key against the demanded assignment:

```
per-key totals over the 144 runs:  honoured 952   never-evaluated 784   CONTRADICTED 64
combinations fully realised by at least one run:  12 of 12
```

Every combination came back `realised_fully >= 1`: **a run exists in which every
gate AND every member holds the demanded outcome.** The `never-evaluated` bulk is
the two ANON scenarios, which do not evaluate auth-only gates at all (each seed
is replayed in all three scenarios); the 64 `CONTRADICTED` are concentrated in
`take_2_not_found` / `take_3_not_found`, the per-post `poll`/`location` lookups
whose ordinal depends on how many post rows the path walked — a seed written at
one ordinal is contradicted when the path takes another, which is why every
ordinal backing a canonical is seeded and why some still miss.

**So the classification was wrong, and both of my earlier checks were wrong in
the same way.** The seeder's `0 REACHABLE` means only "no BASE run walks this set
under compatible gates", and my §13.1 compatibility test on the full corpus asked
only "did the corpus already produce this". Neither asks *can the program*. The
direct construction does, and the answer is yes for 12 of 12.

### §34.2 Driving them — the combination layer closes

| round | corpus | satisfiable | covered | remaining |
|---|---|---|---|---|
| before construction | 9 894 | 10 519 | 9 751 | **768** |
| C12 (48 constructed seeds) | 10 038 | 11 287 | 9 871 | 1 416 |
| C12B (928 seeds) | 12 822 | 11 287 | 11 002 | 285 |
| C12C (285 seeds) | 13 677 | 11 287 | **11 287** | **0** |

`satisfiable` settled at 11 287 after the first construction round (realising the
combinations opened the visibility-join arm's own leaf groups once, and nothing
after that), and the next two rounds took `remaining` to **zero**: 3 639 runs,
1 536 assignments, and the census's emit/count self-check agreed on every round.

**`EXACT: nodes=39 cliques=21 satisfiable=11287 covered=11287 remaining=0
bounded_cliques=0`** — the combination layer is closed on its own exact
instrument, with no pin, no independence declaration and no residue standing
behind it. §30's "residue", §31's withdrawal of the pin extension and §32's
"named residual" are all superseded: there is no residual.

## §35. Where this leaves the endpoint, and what the queued pass decides

Corpus **13 677 dumps**. Both mock judges green on it:
`mock_note_check` — *"every SQL-issuing target's notes match its real
statements"*; `note_fidelity_audit` — MISSING 0, STAR-OVER 0, every DIFF class 0,
17 EXACT, 6 DECLARED (the preload-arity class, §27). Exact combination census —
`satisfiable 11287 = covered 11287, remaining 0`.

**`MISSING` before / after, with attribution** — the number the ruling asked for:

| | corpus | MISSING | why it moved |
|---|---|---|---|
| last engine on record | 2 910 | **28** | — |
| exact census, same universe, pre-construction | 9 894 | 768 assignments | the engine's `MISSING` is `demand sets × MAX_MISSING_PER_CLIQUE`, a SET count; the census is the assignment count |
| after the direct constructions | 13 677 | **0 assignments remaining** | **DRIVE** — 3 639 runs from solver-constructed seeds |

The attribution is unambiguous and it is not the one I expected: **drive, not
confinement and not pin.** No confinement licence was needed for any of it, no
independence was declared, and the ONE pin on this endpoint is unchanged — the
`!=` spelling, which §31 kept and whose attempted second spelling the gate
refused. The queued pass will report the engine's own `MISSING` over the closed
corpus; on a census that reads `remaining 0` it should read `MISSING=0`, and if
it does not, the difference between the two instruments is itself the finding and
must be reported rather than averaged.

So `COMPLETE=True` is now claimable on the evidence IF the pass agrees — which is
exactly what it is queued to decide, behind posts_show's §16c pass and then
notifications' certification pass. What it must not be claimed over: nothing on
the combination layer, and on the mock layer the 6 DECLARED preload rows, whose
reason and falsifier are in `completion_config.json` and print on every run.

**Three method defects this exercise exposed, worth carrying to the other
endpoints** (they are about the TOOLS, not this batch's boundary, so they are not
in §26's Rule T list):

1. `_set_root.py`'s `0 REACHABLE` is a statement about the CORPUS, not the
   program: it means no BASE run walks the set under compatible gates. Reported
   as "MULTI-GATE-FORECLOSED (declared residue, §13.3)", it reads like an
   impossibility claim. On this endpoint 768 of 768 so classified were reachable.
2. The §13.1 compatibility test on the full corpus has the same blind spot — it
   asks whether the corpus ALREADY produced the combination. It agreed with the
   wrong answer here (0 producers for 12 of 12) and was no help.
3. Only the DIRECT construction — fix every gate and member from the solver's own
   assignment, seed every ordinal backing each canonical, base for context only —
   distinguishes "not yet driven" from "cannot happen". It should be the default
   before any set is called residue, and it is cheap: 12 constructions, 144
   replay runs, one afternoon's worth of slot.

## §36. The queued chain ran — slot order held, the engine did not

`_x7_final_chain.log`, verbatim at the transitions:

```
[08:37:11] posts_show pass exited
[08:37:11] slot priority: yielding to notifications (not started yet, 0s of 7200s grace)
   ... 10 minute ticks ...
[10:07:13] slot priority: notifications certification pass is RUNNING - waiting (5400s)
   ... 10 minute ticks ...
[11:29:14] slot priority: notifications certification pass EXITED after 10320s - slot released
[11:29:14] pass slot free - full engine
[11:30:53] engine rc=137 ::
[11:30:53] free=10G — no 6G window; extraction with SKIP_SUBSUME=1 (state None, never True)
[11:42:33] extraction rc=0 :: people_stream: 181 queries (181 distinct, 0 subsumed) from 13677/13677 dumps
[11:42:33] header re-applied; views=181 todo=0
```

**The slot order worked exactly as specified** — it yielded for 4 800 s while
notifications had not started, then waited 5 520 s more while its certification
pass ran, then took the slot. It never jumped the queue and never hung.

**The engine did NOT run.** `rc=137` (128+9, SIGKILL) with an EMPTY verdict —
`journalctl --user`: `run-r4a173cff….scope: Failed with result 'oom-kill'`. Its
log stops at `loaded 13677 runs (0 unparseable)` / the `[assumptions]` line. By
the coordinator's own rule, **a job that exits without its verdict line was
killed, not done**, so there is no engine verdict for the closed corpus yet. The
cap was 3 G, set when the corpus was 2 760 dumps and the pass peaked at 841 MB;
at 13 677 dumps it needs more. Re-queued at **6 G** (`_x7_engine_when_free.sh`).

**Two defects in my own chain, named rather than quietly fixed:**

1. The 6 G-subsumption branch read `free=10G` and still took the SKIP path,
   because its guard also required `! pgrep coverage_report.py` and the engine's
   own just-killed child was still in the process table one second later. The
   re-queued script tests for OTHER endpoints' passes explicitly, excluding its
   own.
2. Its wait covered `coverage_report.py` only. **`confinement_census.py` is a
   pass too** and the coordinator's rule names it — posts_show's re-census was
   running at 11:53 and my first re-run attempt launched beside it. I killed my
   own job within 3 minutes (mine carries `oom_score_adj 1000`, so it was
   already the one that would die first) and re-queued behind a wait that
   includes `_exact_enum` and `confinement_census`.

**The extraction DID complete** and is installed: **181 views** from
13 677/13 677 dumps, `TODO(drive)` 0, header re-applied, `subsume_ran=false`
(state None — the SKIP branch, for the reason above; the re-queued chain retries
it with a real 6 G window if one exists after the engine).

## §37. OVERALL_COMPLETE=True — the verdict, verbatim

`_engine_20260911_final2.log`, own 6 GB scope inside `concolic-cov.slice`,
`choom -n 1000`, taken only after posts_show's census and notifications'
certification pass had both released the slot:

```
loaded 13677 runs (0 unparseable)
[assumptions] declared=30 INERT(never-co-evaluated, not declared)=38 OVERNIGHT_PINS=2
OVERALL_COMPLETE=True;COMPLETION=True
   AUDIT green    note_fidelity
   AUDIT green    empty_relation_emission
   SHIM  PASS      x25
   SHIM  PROTOCOL  x9
   NOTE-CHECK   green
   ASSUMPTIONS  green (declared 30, distinct tested 30, {'PASS': 30})
COMPLETE=True;NODES=39;MISSING=0;BLOCKING=0;PCS=178540
GENUINE=True;TRUNCATED=False;SOLVER_LOST=0;UNEVALUABLE=[]
DEMAND_SETS=21;TREE_COMPLETE=True;TREE_MISSING=0;FORECLOSURES=332;FORECL_IGNORED=0;FORECL_PROVISIONAL=False
peak RSS 2947 MB
```

**No BLOCKING line. 0 shim FAIL, 0 WAIVED. `TRUNCATED=False`,
`FORECL_PROVISIONAL=False`** — `MISSING=0` is a claim, not a provisional one.

### §37.1 The last step: one branch, one gated pin

The 6 GB run before this one came back `COMPLETION=True` and `MISSING=0` but
`COMPLETE=False`, on exactly one unobserved tree branch:

```
TREE-MISSING (SYM_RESULT_ActsAsApi__Collection_as_api_response_2_row_guid != StringVal('')) :: taken
```

That is the SECOND call ordinal of the site Argument 5b already pins —
`Person#as_json` calls `person_path(self)` more than once per render. Measured
over the whole closed corpus before declaring anything:

```
  8102 taken=False     0 taken=True    (…_1_row_guid != StringVal(''))   <- already pinned
  2928 taken=False     0 taken=True    (…_2_row_guid != StringVal(''))   <- this branch
  2923 taken=False  2928 taken=True    (…_2_row_guid == '')              <- two-sided, NOT pinned
```

and it is the `!=` SPELLING — the one the gate PASSED for ordinal 1 — not the
`== ''` spelling the gate refused earlier today (§31). **Gated before use:**

```
PASS  OneSideUntrackedPathAssumption  (…as_api_response_2_row_guid != StringVal(''))
      flipping the variable leaves the PC unevaluated — the other side is unreachable by construction
RESULT: 1 distinct tested — PASS 1, FAIL 0, ERROR 0, NOT-TESTABLE 0, NOT-COMPARABLE 0
```

`OVERNIGHT_PINS=2`, both earned, both reversible by one edit or `NO_PINS=1`,
both with the same falsifier: any run recording the expression taken, or a
non-nil default on `person_path`'s `:id` segment (`config/routes.rb:179` has
none).

### §37.2 MISSING, before and after, attributed

| | corpus | number | instrument |
|---|---|---|---|
| last engine before this drive's closing work | 2 910 | `MISSING=28` | engine (demand sets × cap) |
| exact census, pre-construction | 9 894 | 768 assignments remaining | census |
| after the direct constructions | 13 677 | **0 remaining** | census |
| final engine | 13 677 | **`MISSING=0`, `TREE_MISSING=0`** | engine |

**Attribution: DRIVE for the combination layer, one GATED PIN for the last tree
branch, and confinement for nothing.** No confinement licence was needed or
used; no independence was declared (Argument 4's eleven pairs were WITHDRAWN
earlier today when the gate failed one of them, and `MISSING` fell when they
went); the two pins are the `!=` spelling at two call ordinals of one site, each
probed and passed. The two instruments agree: census `remaining 0`, engine
`MISSING=0`.

### §37.3 What `COMPLETE=True` here does and does not cover

It covers: the coverage layer (39 nodes, 21 demand sets, 332 foreclosures,
non-provisional), the tree layer, the assumption layer (30/30 probed PASS), the
shim layer (25 PASS / 9 PROTOCOL / 0 FAIL / 0 WAIVED), the note check, and
`note_fidelity`.

It does NOT cover, and these stay declared in `POLICY_HEADER.txt`:
* the **6 DECLARED preload-arity rows** in `note_fidelity` (§27) — the corpus
  cannot produce a bulk `IN (…)` because Gate 1b gives each collection ONE
  representative; measured, not assumed, with its falsifier;
* **subsumption did not run** on the shipped policy (`subsume_ran=false`, state
  None, never True): the box has not had a 6 GB window free of other passes.
  **181 views is an upper bound on redundancy**, not a correctness caveat;
* `hardening_lint` H1 (no mobile arm) and H4 (no `len(...)` decision) remain
  OPEN, and `noteless_call` still names `Person.name` — the last Rule S §9.8
  target, untouched because its body reaches `fix_profile` → `reload`, a write
  path.

## §38. Subsumption RAN — and the tri-state tally is not the previous edition's

`_x7_subsume_when_free.sh` got its window at 12:27 and completed at 13:09
(`_x7_subsume.log`, `_extract_people_stream_SUBSUME_20260911.log`):

```
rc=0 :: people_stream: 162 queries (181 distinct, 19 subsumed) from 13677/13677 dumps; subsume_ran=True

subsumption: state=True over 143 eligible of 181 distinct
   stage 1 SYNTACTIC containment (free, not solver-decided, not gated by eligibility): 10 views dropped
   stage 2 SOLVER (blockaid) saw 135 views
   verdict tally  subsumed(true)=9  not-subsumed(false)=75  UNDECIDED(null)=51
   total dropped 19 = 10 syntactic + 9 solver
   *** 51 views the checker could NOT decide — they are KEPT, and a null is NOT a 'not subsumed' ***
```

It installed only because it produced its verdict line WITH `subsume_ran=True`;
the script writes to `.subsume` side files and promotes them only on that
condition, so a killed run can never overwrite a good policy.

**Read against the 2026-09-10 edition this is a different result, not a bigger
one.** Then: 42 dropped, all 42 free syntactic containment, solver tally
`true=0 / false=22 / null=0`. Now: 19 dropped, **9 of them decided by the
solver**, and **51 UNDECIDED**. The nulls are new and they matter — the previous
edition had none to report, this one keeps 51 views the checker could not decide
and says so in the shipped header. A consumer must not read their presence as a
positive non-subsumption verdict.

**Shipped policy, final**: `results3/queries_from_runs/people_stream.sql`,
**162 views** (181 distinct → 19 subsumed), 13 677/13 677 dumps, **51 views carry
the `share_visibilities` visibility join**, 0 unparseable notes, 0
`bind-rotation-UNRESOLVED` and 0 `bind-rotation-repaired`, `TODO(drive)` = 0.
`POLICY_HEADER.txt`'s STANDING block was rewritten with the engine verdict, the
real tri-state tally and the null caveat, and re-applied.

## §39. Unified memory rule — adopted at the launcher, not the call sites

`_memwait <capG>` implements the coordinator's invariant for EVERY launch ≥ 1 GB:
poll every 30 s until **BOTH** `free -g` (available) ≥ 4 **AND**
(8 G − slice `MemoryCurrent`) ≥ the job's own cap, then print both numbers.

It is wired into `_caged` itself rather than into each call site, so it cannot be
forgotten: every caged launch with a cap ≥ 1 GB now waits and logs

```
MEMWAIT ok free=7G slice_headroom=6G cap=6G waited=0s
```

before the scope starts. Caps under 1 GB skip the wait. Name patterns
(`coverage_report` / `_exact_enum` / `confinement_census`) stay as an
optimisation on top — they are what stops a pass starting beside another pass —
but the two numbers are the invariant, and they are the thing a run's own log now
carries. JRuby was already caged-only (`_x7_rooted_round.sh`, `_gen_x7.sh`,
`_x7_concrete.sh` all go through `_caged`), so it inherits the rule unchanged.

**Why this was needed, from this drive's own record**: the 11:30 engine died
`Result='oom-kill'` at a 3 GB cap with no verdict line, and at 11:53 I launched a
6 GB engine beside posts_show's `confinement_census` because my wait only matched
`coverage_report.py`. A name list has to be complete to work; the two numbers do
not.
