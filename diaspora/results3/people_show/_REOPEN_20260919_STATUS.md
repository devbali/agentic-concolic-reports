# people_show — REOPEN 2026-09-18/19 status

Reopened to repair **F6** (the signed-in principal was concrete, not symbolic),
which `AGENT_RUN.md`'s "EXTRACTION + SET-ASIDE" section named as *"the thing to
fix first if people_show is ever reopened"*, and to pick up **B-1** (class-level
finder dropping its WHERE) by corpus regeneration.

**Headline: F6 is fixed and verified green (0 literal principal binds, down from
27 726). B-1 is resolved. The completion gate has been BUILT FROM NOTHING and
RUN AUTHORITATIVELY for the first time on this endpoint: `OVERALL_COMPLETE =
False`, with audits 3/3 green and all 42 shims PASS/PROTOCOL, blocked by
note_check (1 statement — the already-declared P-7) and by the assumption layer
(293 declared, 20 verified, 42 FAIL, 231 NOT-TESTABLE). The engine has marked
the coverage numbers STALE. RC-1 is implemented but deliberately NOT activated
(see §7).**

---

## 1. Backups — nothing was lost

`run_dse.rb:710` deletes every `dump_*.json` on startup with no guard. The
pre-existing, adversarially-verified corpus was copied **before** anything ran:

| what | where |
|---|---|
| original 12 997-dump corpus + summaries + pre-fix `targets.rb`/`concolic_targets.rb` + shipped `people_show.sql` | `results3/_redrive_20260919/people_show_original_backup/` |
| the new F6 corpus (10 656 dumps) + its `exploration_summary.json` + post-fix target files + drive log | `results3/_redrive_20260919/people_show_f6only/` |

---

## 2. F6 — verified real before it was touched

The framing was **not** stale. `identity_symbolicity_audit` on the original
corpus, before any edit:

```
owner_id       symbolic  11436   literal      0
recipient_id   symbolic   6599   literal   7030  <-- RED
user_id        symbolic  27008   literal  20696  <-- RED
RESULT: RED — literal principal binds; the session user must be a symbolic id.
```

7 030 + 20 696 = **27 726** literal principal binds, matching `AGENT_RUN.md`
exactly. Attributed by scenario: **every** literal bind came from the four
`auth_*` scenarios (the `signed_in_user` users); the five anon scenarios were
already clean, because their `symbolic_user` is never wired as `current_user`.

The defect was visible in the **shipped policy** too: `people_show.sql` carried
32 `user_id = 1` and 2 `recipient_id = 1` literals.

---

## 3. What changed, and why

### `targets.rb` — `PeopleTargets.signed_in_user` (the F6 repair)

The fix was to **delete pins, not add machinery**.
`ConcolicTargets.symbolic_instance` already mints one symbolic var per column of
`users` (`SYM_USER_PE_id`, …), seeded through `seed_for` and therefore flippable
by the DSE worklist like any other var. Four singleton definitions were
*shadowing* those vars:

| removed | becomes |
|---|---|
| `id -> 1` | the symbolic `users.id` column var — **the principal** |
| `person_id -> 1` | not a column; `user.rb:60` is `delegate :id, :guid, to: :person, prefix: true`, so it now routes through the REAL has_one `person` reader (P-10 / W3 `find_target`) |
| `guid -> "abc123"` | likewise a delegate (`user.rb:57`) |
| `blocks -> Block.where(user_id: 1)` | `Block.where(user_id: id)` — still a REAL relation (so `block_for` keeps firing the finder mock under the P-5 shape), now bound to the symbolic id |

The corpus itself proved the shadowing diagnosis: association-reader paths that
never consult `#id` (`aspects`, the has_one `person`) already emitted
`$$(SYM_USER_PE_id)` in the *same dumps* where `contact_for`/`block_for`
emitted `= 1`.

**Deliberately left concrete** (leaf, non-identity, none of them a principal
column under `queries_config/app.json`): `diaspora_handle` (drives the
local/remote host split, read as a Ruby string — a symbolic value there is the
`Contains`/`SubString` PC class the fold cannot represent anyway), `language`
(I18n.locale must be a real locale), `gender`.

**Scenario-local overrides preserved.** `auth_other_html`'s
`seeds: { "assoc_person_id" => 2 }` is untouched and still forces the
`person == user.person` OTHER arm — `auth_other_html` reproduced its baseline
302 paths exactly.

### Shape note — this is NOT the conversations_index/notifications_index shape

Those endpoints resolve `current_user` through the real Devise
`serialize_from_session(symint)` → `devise_user_first`, which also mints the two
principal-resolution statements. people_show keeps its minted principal and
simply stops pinning it. The property the F6 audit tests — every principal bind
symbolic — is fully achieved either way, but the `SELECT users.*` /
`SELECT people.* WHERE owner_id = ?` resolution pair is **not** added here, so
the statement set is a repair, not a scope expansion. Adopting the full Devise
shape remains available as a follow-on.

---

## 4. Exploration — full fresh DSE, all 9 scenarios

Not a seed replay: the principal representation changed, so old seeds do not
correspond 1:1. (people_show cannot be seed-replayed regardless — it records no
`concolic_seeds`.)

`TIME_BUDGET` raised 1200 s → 3600 s per scenario; `MAX_RUNS` 1 000 000.

| scenario | old runs | old paths | old drained | new runs | new paths | new drained |
|---|---:|---:|:--:|---:|---:|:--:|
| anon_handle | 119 | 26 | yes | 119 | 26 | yes |
| anon_json | 16 | 9 | yes | 16 | 9 | yes |
| anon_mobile | 8 473 | 2 976 | yes | 7 375 | 2 680 | **no (TIME_BUDGET)** |
| anon_mobile_presenter | 9 267 | 2 927 | no | 7 518 | 2 571 | no (TIME_BUDGET) |
| auth_self_html | 856 | 332 | yes | 856 | 332 | yes |
| auth_other_html | 723 | 302 | yes | 723 | 302 | yes |
| auth_json | 38 | 38 | yes | 38 | 38 | yes |
| auth_mobile | 10 384 | 6 370 | no | 7 438 | 4 681 | no (TIME_BUDGET) |
| anon_remote_401 | 68 | 17 | yes | 68 | 17 | yes |
| **TOTAL** | **29 944** | **12 997** | | **24 151** | **10 656** | |

**Six of nine scenarios reproduce the baseline exactly** — identical run counts
*and* identical path counts, including all four `auth_*` scenarios. That is the
key evidence that the F6 repair changed **binds, not control flow**.

**Honest shortfall.** The three mobile scenarios are short of the baseline, and
`anon_mobile` regressed from drained to time-capped. The cause is throughput,
not semantics: **2.2 runs/s** this campaign vs **9.4 runs/s** in the original
(24 151 runs in 11 098 s vs 29 944 in 3 175 s). Two candidate causes, not
separated: `posts_show`'s 13 GB Z3 coverage check held ~1 core for most of the
drive (it ended 21:30), and `src/ruby_runtime` now carries SQL/context notes on
every symbolic var and call event (commit `1c10841`), making every dump larger.
A future drive should budget ≥3× the wall clock for the three mobile scenarios.

Run errors are all accounted for (§8).

---

## 5. Coverage — REAL mode, completeness verified

Run as `PYTHONPATH=src python3 coverage_report.py` with **no `NO_PINS` and no
`SUMMARY_OUT`** (either one alone silently forces counterfactual/scratch mode).

```
COMPLETE=True;NODES=97;MISSING=0;BLOCKING=0;PCS=414532
GENUINE=True;TRUNCATED=False;SOLVER_LOST=0;UNEVALUABLE=[]
```

| | prior campaign | this campaign |
|---|---:|---:|
| `coverage_complete` | True | **True** |
| `tree_nodes` | 97 | **97** |
| `missing_branches` | 0 | **0** |
| `tree_complete` | (not emitted then) | **True** |
| `tree_missing` | 0 | **0** |
| `demand_sets` | (not emitted then) | **239** |
| `truncated` / `solver_lost` / `unevaluable` | False / 0 / [] | False / 0 / [] |
| `assumptions_used` | 130 | 130 |
| runs / PCs | 12 997 / 525 378 | 10 656 / 414 532 |

**The tree is the same size and equally complete on 18 % fewer paths.** Peak
RSS 3.1 GB, 104 s.

`demand_sets = 239` and `tree_complete = True` together mean the §16 combination
claim is stated over a complete tree layer, which is the condition it requires.

---

## 5b. Extraction — both fixes land in the shipped artifact

Re-extracted with the current `src/queries_from_runs/transform.py` (including
the hash-derived alias-collision fix) via the batch's own streaming driver.
10 656/10 656 dumps loaded, **0 errors**, 274 326 raw → 162 distinct → 96
subsumed → **66 views**.

| | shipped (2026-09-07) | control (current src, OLD corpus) | **THIS (current src, NEW corpus)** |
|---|---:|---:|---:|
| statements | 59 | 69 | **66** |
| distinct / subsumed | 75 / 16 | 155 / 86 | 162 / 96 |
| **literal principal binds** (`user_id`/`recipient_id`/`owner_id` `= <int>`) | **34** | **33** | **0** |
| `find_by_1_id` placeholder lines | 10 | 22 | **0** |
| `find_by_2_id` placeholder lines | — | present | **0** |
| "unresolved symbolic binds" NOTE lines | 7 | 13 | **1** |
| placeholder families | 3 | 3 | **1** |
| **F7 policy loadability** | 42.37 % (25/59) | — | **98.48 % (65/66)** |
| F7 unresolved binds | 3 distinct / 7 occurrences | — | **1 distinct / 1 occurrence** |

* **F6 in the artifact: 34 literal principal binds → 0.**
* **B-1 in the artifact: resolved.** Both `find_by_*_id` placeholder families
  are gone. The control column proves regeneration was required: a `src`-only
  change did **not** clear them (10 → 22, because the precision fix keeps more
  statements); only the fresh corpus does.
* The single surviving placeholder is `_SYM_POSTS_GUID` — `TODO.md` item 7
  records it as **not a defect** (a deliberate free symbolic leaf, no query
  behind it; any fix is extraction-side). It is the sole reason F7 is not 100 %.

Shipped to `results3/queries_from_runs/people_show.sql` (previous file kept as
`people_show.sql.pre_f6repair_20260919`). `POLICY_HEADER.txt` was rewritten:
its F6 section now reads REPAIRED AND GREEN instead of RED, a B-1 section was
added with the three-way table above, and the corpus/coverage figures were
updated (previous header kept as `POLICY_HEADER.txt.pre_f6repair_20260919`).

---

## 6. THE COMPLETION GATE — BUILT AND RUN FOR REAL (2026-09-19)

people_show had NO completion gate of any kind. It now has one, and it has been
run authoritatively (no `NO_PINS`, no `SUMMARY_OUT`, no `SKIP_COMPLETION` — all
three verified unset at launch).

### THE VERDICT

```
OVERALL_COMPLETE=False;COMPLETION=False
COMPLETE=True;NODES=96;MISSING=0;BLOCKING=0;PCS=356409
GENUINE=True;TRUNCATED=False;SOLVER_LOST=0;UNEVALUABLE=[]
DEMAND_SETS=217;TREE_COMPLETE=True;TREE_MISSING=0;FORECLOSURES=14856
```

| gate stage | verdict |
|---|---|
| audits (identity_symbolicity / exception_note / empty_relation_emission) | **3/3 green** |
| shims | **42 extracted — 30 PASS + 12 PROTOCOL, 0 NO-TEST, 0 waivers** |
| note_check | **RED** — 1 statement (see below) |
| assumptions | **RED** — 293 declared, 293 tested: **PASS 20, FAIL 42, NOT-TESTABLE 231, ERROR 0** |
| blocking entries | **47** = 1 note_check + 42 assumption FAIL + 4 confinement NOT VERIFIED |

### THE HEADLINE FINDING — the coverage numbers are marked STALE by the gate

`coverage_summary.json` now carries, written by the engine itself:

> `coverage_numbers_stale`: "STALE: confined pair(s) FAILED the gate;
> missing/demand above were computed with them licensed"

This is the point of the whole exercise. `MISSING=0` / `DEMAND_SETS=217` were
computed with the batch's declared assumptions LICENSED. The first time those
assumptions were actually tested, **4 ConfinementAssumptions FAILED and 4 more
were NOT-TESTABLE**, so the demand universe the `MISSING=0` claim was computed
over is not the one the evidence supports. The long-standing
"complete, 0 missing" claim for this endpoint rests on 293 assumptions of which
only **20 are verified**.

Breakdown by kind:

| assumption kind | PASS | FAIL | NOT-TESTABLE |
|---|---:|---:|---:|
| IndependenceAssumption | 19 | 36 | 199 |
| ConfinementAssumption | 1 | 4 | 4 |
| OneSideUntrackedPathAssumption | 0 | 2 | 18 |
| SymbolicConstraintAssumption | 0 | 0 | 10 |

The dominant FAIL reason (36 of 42) is the **X10 flip-both probe**: "combination
(flip both) produced 2-3 target-call shape(s) absent from either single flip" —
i.e. the two decisions are NOT independent, the exact defect the X10 gate-probe
fix was added to catch. Two more are the X11 removal shape ("flip-A leaves B
UNEVALUATED"). These are real dependence findings, not plumbing.

The dominant NOT-TESTABLE reason (180 of 231) is **"cannot derive seed
dimensions from exprs"** — the `Contains`/`SubString` PC family on
`people.diaspora_handle` that `POLICY_HEADER.txt` already declares the fold
cannot represent. The same grammar limit that costs WHERE precision in the
policy also makes those assumptions unprobeable. A further 23 are "expr never
recorded in the CURRENT corpus (stale or renamed)" — declared assumptions that
no longer match any expression the corpus produces.

### note_check — the RED independently re-derives declared-open P-7

After the rig's own frame-naming was corrected (below), exactly one RED remains:

```
SELECT "aspects".* FROM "aspects" WHERE "aspects"."user_id" = ?
  AND "aspects"."post_default" = ? ORDER BY order_id
```

That is `POLICY_HEADER.txt`'s **P-7 declared-open item, verbatim**. Verified as a
genuine corpus gap rather than a naming artefact: `post_default` appears in 6 281
dumps but in **zero** dumps as a NOTE. So the first real gate run on this
endpoint re-derived a previously prose-declared gap from ground truth. The
concrete run reaches the publisher's aspects query; the corpus never records it.

Two other REDs in the first note_check pass were MY rig's frame naming, not
corpus defects, and were fixed in `concrete_aliases.json` (kept:
`concrete_aliases.json.pre_gate_20260919`):
`CollectionAssociation#find_target` (a has_many read whose owner key is already
loaded goes through AR's StatementCache, which the corpus frames one layer up
under the declared `CollectionProxy#records`/`#load_target` — people_stream's X7
note documents the identical case), and `update_column` delegating inward to
`update_columns` (measured: every UPDATE note in this corpus hangs on
`ActiveRecord::Base.update_column`).

### What had to be built, and three blockers found on the way

New files: `completion_config.json`, `shim_tests.rb`, `assumption_manifest.json`,
`_c1/gate_wrapper.sh`, `_concrete_fixture.rb`, `_concrete_targets.rb`,
`concrete_manifest_{anon_handle,anon_json,auth_self_html,auth_json}.rb`,
`_run_concrete.sh`, `_merge_concrete_runs.py`, `_backfill_scenario.py`;
`coverage_report.py` gained the completion hook.

Three defects, each of which would have silently wasted the run:

1. **The corpus carried no `concolic_seeds`.** The gate matches every probe to
   its launch through that key (`assumption_checker.seeds_as_written`); without
   it every base reports `{}` and no verdict means anything. This is why
   `_RAILS_ENV_MOD_FIX_20260919.md` §7.2 records that people_show "cannot be
   seed-replayed at all". `run_dse.rb` now records it.
2. **`run_dse.rb` deleted the whole corpus on startup, unguarded.** The gate
   launches the runner once per probe, so the FIRST probe would have destroyed
   the corpus it was probing. Now `KEEP_DUMPS=0`-gated and never while seeding.
3. **No `concolic_scenario`, so no `env_by_scenario`.** Each probe would have
   replayed all nine scenarios, and `_run_chunk` keeps only probe dumps whose
   scenario matches the chunk's — so `found` would have been empty every time.
   Now recorded natively, plus `_backfill_scenario.py` for pre-existing dumps.
   Corpus verified homogeneous: **9318/9318 carry both keys.**

Also measured, and now pinned in the config: `assumption_checker.run_probe`
hard-codes `timeout=900` for ONE runner launch and lets `TimeoutExpired`
propagate, killing the whole gate. At `CONCOLIC_PROBE_WORKERS=10` /
`ACHK_PROBE_BATCH=100` the box reached load ~44 and a launch blew that cap
mid-stage-2. The checkpoint (`ACHK_CHECKPOINT`, the RUNBOOK's "long jobs must
run CHECKPOINTED" rule) made the loss almost nil — the resumed run skipped
5 395/5 695 stage-1 probes and the 9 318-dump corpus index. Settled at
4 workers x 50 roots.

Gate cost, measured rather than extrapolated: stage 1 = 5 695 distinct probes,
stage 2 = 971, for 293 assumptions. That is far cheaper per assumption than
people_stream's 10 350 probes for 34, so the "~87k probes / 118 h" fear from
scaling that figure was wrong.

## 6b. Historical note — why the gate never ran before

This is a correction to the reopen brief, which assumed people_show had
`coverage_report.py` + `completion_config.json` wired for the gate. It does not:

* `people_show/completion_config.json` — **absent** (all five other endpoints
  have one).
* `people_show/coverage_report.py` is an **older port** than every other
  endpoint's: it has no completion hook, no `NO_PINS`/`SUMMARY_OUT` handling,
  and no alias-canonicalisation block. Its output has no `completion` or
  `complete` key at all — confirmed on the written summary.
* Also absent: `shim_tests.rb`, `concrete_run.json`,
  `assumption_manifest.json`, `_c1/gate_wrapper.sh`.

So `OVERALL_COMPLETE` is **not reported, because it was not computed**. The
verdict above is the exploration/coverage layer only. No completion-gate bug was
hit; the gate was never reachable. (`src` is at `c4e1446`, which does carry the
`shim_extractor` `"key"` fix.)

**What building it would take** (inventory, not an estimate-free wish): the
engine's shim extractor enumerates **42** shims for this endpoint — 31
`rep_plumbing`, 9 `prepend`, 2 `value_class` — so roughly 11 need real test
bodies. Beyond that, `concrete_run.json` needs a concrete reference run, and the
assumption gate needs a manifest verifying all **130** declared assumptions,
which is the Phase-4 work that took other endpoints days. The assumption gate is
the binding constraint: without it the gate reports `complete=False` regardless
of coverage.

---

## 7. RC-1 — implemented, validated, and deliberately NOT activated

RC-1 (`results3/queries_from_runs/_RAILS_ENV_MOD_FIX_20260919.md`):
`app/models/profile.rb:8` gates `lazy_load :bio, :gender, :birthday, :location`
on `Rails.env.include?("mod")`, so under `RAILS_ENV=concolic` our corpus records
a wide `profiles` projection the real app sometimes narrows.

**Independently reproduced here, including the part the original brief got
wrong.** A ground-truth differential (same probe, same seeds, `concolic` vs
`concolic_mod`) produced **identical SQL note sets** — 13/13 and 5/5 notes, the
only delta a wall-clock timestamp. The env change alone is **inert on this
corpus**, because every `profiles` read is synthesised by the mock layer:
`concolic_targets.rb`'s `SingularAssociation#find_target` hand-renders
`SELECT "<table>".*` from the reflection and never consults the relation. All
**34 884** `profiles` reads in the pre-reopen corpus have that one shape.

### What was applied

`default_projection(klass)` (ported verbatim from
`_redrive_20260919/_proto/concolic_targets.rb`) plus its use at people_show's
**2** star-synthesis sites — `class_finder_sql` and the
`SingularAssociation#find_target` note. people_show has no
`emit_includes_preloads`, no polymorphic-`find_target` and no `reload` site, so
2 sites, not the 5 of comments_index. Verified:

* `profiles` reads now render the reference's 14-column projection;
* **path conditions identical** (20/20 and 11/11), note counts unchanged —
  matching the 0/26 528 branching drift measured on comments_index;
* the helper is **automatically inert under `RAILS_ENV=concolic`**
  (`select_values` is empty ⇒ it returns the star), so it changed nothing in
  this campaign's corpus.

### Why it is NOT activated — a recall trap specific to this endpoint

people_show falls under the same caveat that excluded notifications_index:

1. **people_show genuinely discloses all four lazy columns** — in 798 of 800
   sampled dumps, `assoc_profile_bio`, `_gender`, `_birthday` and `_location`
   are all read.
2. **The lazy fetch cannot fire in this harness.** `symbolic_instance` defines a
   singleton reader per entry of `klass.columns_hash` — all 18 — and singleton
   methods shadow the `define_method` accessors `lazy_columns` installs. Probed
   directly: `p.bio` returns `SymbolicString "PROBE_PROFILE_bio"` with no
   `reload` and no second statement.

So narrowing the projection **alone** would move those four columns from
"disclosed unconditionally" to "not disclosed at all" — a recall loss, not a
precision gain. The complete repair needs the `reload`-driven fetch modelled
(Rails' `reload` is `unscoped { find(id) }` ⇒ a full-width 18-column statement).
That changes `symbolic_instance`'s reader semantics for every model, which is
the Rule-T sign-off `_RAILS_ENV_MOD_FIX_20260919.md` §7.4 explicitly defers, so
it was **reported rather than guessed at**.

Activating RC-1 for people_show later costs one env switch plus that fetch
modelling — **no third exploration**, since branching is proven identical.
`_concolic_mod_runner.sh` (batch-local; the shared `scripts/diaspora-concolic`
was deliberately not edited) is in place for that drive.

---

## 8. Dump-side audits on the new corpus

| audit | verdict |
|---|---|
| **F6** identity_symbolicity | **pass** — owner_id 8 740 / recipient_id 10 262 / user_id 36 026, **0 literal** |
| F8 exception_note | pass — 0 notes captured an exception |
| empty_relation_emission | pass — 10 656 dumps, 7 986 empty-list states, 0 violations |
| noteless_call | **RED — pre-existing B-8, not introduced here** |
| **F7** policy_loadability | RED, but **42.37 % → 98.48 %**; the only unloadable statement is the `_SYM_POSTS_GUID` non-defect |

B-8 is the known, Rule-T-pending "finder note = `""` on a falsy return" defect.
It is RED on the **baseline** corpus too, and this campaign **reduced** it: the
baseline's largest family (`FinderMethods.first`, 2 081 events) is gone
entirely, and `Core::ClassMethods.find_by` fell 16 → 12.

### Dump `error` attribution — all framework walls, no unexplained failures

* `ActionView::Template::Error` ×4 008 — dominated by the pre-existing
  `uninitialized constant Service::MAX_CHARACTERS` wall
  (`publisher_helper.rb:14`; `MAX_CHARACTERS` exists only on `Services::*`
  subclasses). Pre-existing: 328 of the baseline's 332 `auth_self_html` dumps
  carry the identical error. It fires **after** every SQL note is minted, so it
  costs no evidence.
* `Warden::Unauthenticated => 401` ×6 — a **real app outcome**, not a wall:
  the modelled NM-1 terminal (anon + remote handle → `authenticate_user!` →
  `throw :warden` → 401).

---

## 9. Controls run (so effects are attributable)

Because `src/` has moved a great deal since the 2026-09-07 extraction, a
**current-`src` / old-corpus** control was extracted before drawing any
conclusion from the new numbers: `_redrive_20260919/control_oldcorpus_currentsrc.sql`.
It separates "the `transform.py` precision fix" from "the new corpus".

| | shipped (2026-09-07 src, old corpus) | control (current src, old corpus) |
|---|---:|---:|
| statements | 59 | **69** |
| distinct | 75 | 155 |
| subsumed | 16 | 86 |
| literal principal binds | 34 | 33 |
| unresolved-bind NOTE lines | 7 | 13 |
| `find_by_1_id` placeholder lines | 10 | 22 |

So the statement-count growth is the alias-collision precision fix
(`_COMMENTS_PRECISION_FIX_20260917.md`), **not** the re-drive; and B-1's
placeholders survive a `src`-only change, confirming they need corpus
regeneration exactly as `TODO.md` item 1 says.

---

## 10. Open items

1. **The assumption layer is the real blocker** (§6). 293 declared, only 20
   verified: 42 FAIL, 231 NOT-TESTABLE. The engine has marked the coverage
   numbers STALE because 4 ConfinementAssumptions the demand universe was
   computed with FAILED. Until those are repaired or withdrawn, "MISSING=0"
   is not a supported claim for this endpoint. The 36 X10 flip-both failures
   are genuine dependence findings and need per-pair adjudication; the 180
   `Contains`/`SubString` NOT-TESTABLEs are the same fold-grammar limit the
   policy header already declares.
2. **note_check RED = declared-open P-7** (§6). Either model the publisher's
   `aspects.post_default` read or keep it declared — but it is now evidenced,
   not asserted.
3. **`anon_mobile_presenter` 1472/2927 and `auth_mobile` 4146/6370** (§4) —
   both stopped by me in an expensive-run regime under box contention, not by
   budget. The other seven scenarios reproduce the prior campaign exactly.
4. **RC-1 activation blocked on modelling the lazy fetch** (§7) — Rule T.
5. **B-8 noteless-call RED** (§8) — pre-existing, Rule T.
6. **`ensure_var_registered` is O(n) per call** (`src/ruby_runtime/symbolic_func.rb:54`),
   called from `SymbolicVar#record!` on every path condition, so a run that
   mints many vars degenerates quadratically; `run_dse.rb` checks TIME_BUDGET
   only BETWEEN runs, so such a run is unbounded. Reported, not patched
   (src/ is not mine to change). Evidence:
   `_HANG_jstack_anon_mobile_presenter.txt`, `_HANG_jstack_auth_mobile.txt`.
7. **`assumption_checker.run_probe`'s hard-coded 900 s per-launch timeout**
   raises an unhandled `TimeoutExpired` that kills the entire gate (§6). A
   per-chunk catch that degraded to single replays would make the gate robust
   to host load instead of fatal.
8. The `SYM_PERSON_via_user_*` constraint-parse warnings (X1, `TODO.md` item 5)
   still appear during the coverage run. They did **not** degrade the coverage
   verdict (`unevaluable_exprs` empty, `truncated` False), but they ARE the
   same family as the 23 assumptions the gate scored NOT-TESTABLE with "expr
   never recorded in the CURRENT corpus (stale or renamed)".
