> **2026-10-03:** see `ADDENDUM_20261003.md`. Some artifacts in this
> directory were deleted on 2026-09-30 (not by this task) and the
> `findings/` write-ups have been regenerated; and **S-6 was fixed in
> `src_new` on 2026-09-28**, which re-renders the same dumps from 20 SQL
> views to **548** and recovers exactly the 822 atoms this report
> predicted. Everything below is the record of what the sweep measured
> on 2026-09-26 and is left as it was.

# Will a sweep of the auto lab complete smoothly?

## The seven bar items, each answered with what was run

### 1. Every endpoint completes every stage without crashing

**Evidence available now.** The round-2 pipeline was run over **73 endpoints**
of round-1 artifacts (all that had finished at the time), in 2-way parallel,
and returned **zero non-zero exit codes**. Across those 73 endpoints exactly
**one stage on one endpoint** was not `ok`: `dump_ir` on `comments_index`,
which FIX-11 addresses at its source. `build_policy` no longer fails an
endpoint whose richest dump is unrepresentable — it degrades, records which
dump it refused and why, and builds from the rest.

**Round 2, measured:** `dump_ir`, `run_complete`, `build_policy`, `normalize`, `policy_text`, `render_sql` — **161 `ok`, 0 failed, 0 missing, on every one of the six stages**. Zero pipeline timeouts. One run timeout (`users_auth_token`), which still produced 3 dumps that the pipeline processed cleanly.

### 2. Every dump accepted; every policy passes the acceptance checks

**Round 1:** every dump accepted except five, all on `comments_index`, all the
same `MalformedProvenance` (`obj<Comment>` named but not declared) — mechanism
measured, not inferred, and repaired by FIX-11.

`opaque` in a policy: **zero defects** corpus-wide once the check is the
correct one. The six shakedown failures were the check, not the corpus
(`src_new/README.md:333`'s false claim); `normalize.py:341` states the
opposite from the other side.

**Round 2, measured:** **161 of 161 endpoints have every dump accepted** by `Run.from_dict` + `validate_provenance`. 840 dumps written, none refused. `opaque` defects: **0** corpus-wide; every opaque site is a shim signature return, classified `by_design`.

Getting there took one repair round 1 could not have known about. Sweep 2's extra depth reached `SingularAssociation#writer` for the first time and six endpoints' dumps were refused: the shim declares `obj<?>?` but returns a record minted under a different symbol, so nothing can ever be an attribute of its result. FIX-14 re-declares it `opaque?` — the type the refusal message itself proposes — and all six are clean.

### 3. Zero path conditions: fixed or justified, per endpoint

Separated by evidence, never by assumption. A run that finished with **no
exception at all** genuinely had no branch; a run that ended at an unrescued
exception never reached one. In round 1 the honest cases are the static
OpenID-Connect documents (`discovery_configuration`, `id_tokens_jwks`, …),
verified by reading the actions: they render a document built from route URLs
and constants, with no symbolic input.

**A third category was found and is now separated too**: an endpoint whose
action raised and whose own `rescue_from` handler rendered an error page reads
as "ran to completion" unless the handled exception is recorded.
`api_openid_connect_clients_create` is that case — four events, all of them
what a 400-rendering handler does. FIX-13 records it.

**Round 2, measured:** 33 endpoints still record no path condition, split by evidence into **18 that ran to completion with no exception at all** (genuinely no branch) and **15 that died before reaching one**, each with a named site. Round 1 had 36. A third category is now separated too: an endpoint whose action raised and whose own `rescue_from` rendered an error page is no longer counted as having run to completion (FIX-13); five endpoints carry a `HANDLED_ERROR_PATH` issue.

### 4. Depth addressed, not just measured

Five repairs exist only to raise reach, each aimed at a wall measured in a
trial rather than guessed: the principal that never resolved (FIX-1), the i18n
wall behind it (FIX-3), the session lookup consuming the exploration budget
(FIX-4), a deleted runtime method that made every relation materialisation
raise (FIX-7), and Gate 1b's representative row that nothing could iterate
(FIX-9). Measured on `admin_pods_index`: reach 1 → 3, with
`devise_user_first`, `Relation#records` and `SingularAssociation#find_target`
all reached where only `FinderMethods#first` was before.

**Round 2, measured:** endpoints reaching **exactly one** declared target function fell from **115 to 2**; endpoints reaching **two or more** rose from **7 to 121**; distinct target functions ever called rose from **16 to 25**. `SingularAssociation#find_target` is now reached by 119 endpoints and `devise_user_first` by 114 — the principal resolves across the corpus. The write surface went from **2 endpoints to 23** (30 INSERT, 94 UPDATE and 17 DELETE statements recorded).

**38 endpoints still reach nothing, and that is now mostly honest:** 19 run to completion with no exception at all (they issue no query), 9 stop at `SymbolicString` operations the runtime does not implement, 3 are the unconfigurable ActiveStorage routes, 2 ask an anonymous request to authenticate, 2 have no template.

### 5. The seven known failures

**F1 (6 endpoints) — resolved, and it was not the endpoints.** The check was
wrong; it is fixed, and `sessions_new` runs clean through every stage. Their
*real* defect was `dev_stub.to` returning the stub where Devise expects the
model class, which the backtraces name precisely (FIX-2).

**F2 (1 endpoint) — diagnosed, not repairable from here.** Two `src_new`
defects: the runtime records `Contains` **operands reversed** (S-1: the
recorded term is unsat where the true one is sat), and the builder's §7.2
sub-language has no `Contains` at all (S-2). At `MAX_RUNS=24` this costs that
endpoint 8 of its 9 dumps, not 1 of 2. The harness now degrades instead of
losing the endpoint.

### 6. A real dry run — RUN, over the repaired corpus

`python -m sweep.testbed`, spec at `dryrun/sweep_spec.json`, over **six
endpoints' post-fix dumps**: `admin_pods_index`, `contacts_index`,
`comments_index`, `likes_index`, `home_show`, `links_resolve`. Real
`concolic.review` and real `concolic.check` subprocesses (the two couplings
§14.1 permits); the agent backend is the shipped fake harness, which is the
only one this tree has.

What it did, from `dryrun/out/`:

* **19 campaign steps**, every endpoint moving SETUP → SUBMITTED → CHECKING →
  EXPLORING → SUBMITTED → CHECKING → EXPLORING → … and each ending in
  `CHECKING` with §5.4's own note: *"3 of 3: 1 initial, 2 failed attempts — no
  entry into EXPLORING remains"*. That is the correct terminal state for a
  scaffolded endpoint: the check does not return complete, because the gates
  are NOT CONFIGURED and say so.
* **219 decisions** written to `campaign/decisions.jsonl` — 177 review items
  and 42 operational — each with its own `decision_id`, `text_digest`,
  `config_digest` and timestamp.
* **177 review items** across five kinds: `scope_exclusion` 90,
  `pin_neutrality` 33, `entrypoint_inputs` 18, `scenario` 18,
  `untestable_assumption` 18.
* a per-endpoint ledger under `campaign/ledger/<id>.jsonl` and a per-attempt
  review packet under `campaign/review/<id>/attempt-N.json`.

An earlier smoke run of the same machinery is what produced issue 8: its
review item quoted `config.json`'s `MAX_RUNS=6, TIME_BUDGET=600` back at me,
which no run had ever used. **In this run that item reads 24 / 300** — the
limits the sweep actually drives — because FIX-10 made the sweep take its
limits from the config instead of from a flag.

### 7. Operational gaps

* **One OS process per endpoint** — confirmed by measurement, not by
  construction. `install!` is not idempotent, so a reused process would show a
  §4.1.1f declaration table that GROWS. Read off every dump of round 1:

  | table size | dumps | which endpoints |
  |---:|---:|---|
  | 86 | 171 | every core-only endpoint, without exception |
  | 89 | 23 | `aspect_memberships_create` (86 core + its own 3) |
  | 104 | 12 | `comments_index` (86 core + its own 18) |

  **Zero variance inside any endpoint and zero drift across them.** The
  inventory records `declaration_table_sizes` per endpoint and raises
  `DECLARATION_TABLE_ANOMALY` for any core-only endpoint that is not exactly
  86; none is.
* **Process-group cleanup** — measured; see the correction in §"One
  measurement was wrong". Named scope units were added on top and are what
  reaped the fix trial's JVM when it was stopped mid-run.
* **Disk** — measured, not assumed: 161 endpoints at `MAX_RUNS=24` project to
  about **14 MB** of dumps against 141 GB free. The sweep refuses to start a
  new endpoint below a configurable free-space floor and records each
  endpoint's own dump bytes.


---

# The answer

**A sweep of all 161 auto-lab endpoints will complete smoothly.** That is not
a projection — it is what round 2 did, end to end, under exactly the
conditions a sweep runs in:

* 161 of 161 endpoints attempted; **every one of the six pipeline stages
  returned `ok` on every endpoint**;
* **every dump accepted** by `Run.from_dict` + `validate_provenance` — 840
  dumps, none refused;
* zero pipeline timeouts; **one** run timeout out of 161, and even that
  endpoint produced usable dumps;
* zero harness faults, zero OOM kills, no endpoint undriven or silently
  dropped, and `install!` verified to have run exactly once per process (the
  declaration table is 86 on every core-only endpoint, 89 and 104 on the two
  with overrides, with zero variance inside any endpoint);
* **42 MB** of dumps against 141 GB free, with a disk floor that stops the
  sweep rather than letting it die at endpoint 120;
* the campaign machinery itself driven for real: `sweep.testbed` over six
  endpoints' final dumps, 19 state-machine steps, 234 logged decisions, 192
  review items, all six endpoints reaching a terminal state.

**What a sweep will NOT do is certify these endpoints**, and nothing in this
report should be read as claiming otherwise. Overall `complete` is `false` on
all 161 because the shim, note-check and assumption gates are **NOT
CONFIGURED** — the honest state for a scaffolded endpoint, now reported
blockingly rather than skipped. `coverage_complete: true` on 128 of them means
the explored tree has no missing branch *given where execution stopped*, and
for 100 endpoints that tree is still bounded by a wall rather than by the
application.

## The named residue — what still blocks depth, ranked

| endpoints | what | mine to fix? |
|---:|---|---|
| 161 | gates NOT CONFIGURED (no shim extractor, no concrete run, no assumption driver) | no — that is what promoting an endpoint from scaffolded to driven means |
| 122 | **822 atoms** that would render as SQL but for one line in `src_new` (**S-6**) | no — `src_new` |
| 100 | `EXHAUSTED_BEHIND_A_WALL`: the tree is complete for where execution stopped, not for the endpoint | partly — each wall is its own item below |
| 36 | `I18n::InvalidLocale` — the "xx" arm of the principal-language domain, a **real** app outcome that FIX-3 deliberately opened | no, but it consumes exploration budget and someone should decide if it is worth it |
| 37 | `DEPTH_TRUNCATED` at `MAX_RUNS=24`; `aspect_memberships_create` still ends with 251 branches on its worklist | yes, by raising the per-endpoint limit — the config now carries it |
| ~30 | `SymbolicString` operations the runtime does not implement (`strip`, `gsub`, `downcase`, `split`, `=~`, `match`, `force_encoding`) and `SymbolicInt` (`to_i`, `+`, `-`, `next`) | no — runtime scope; each needs a target at the smallest enclosing SQL-free method, per endpoint |
| 13 | `SOLVER_CONSTRAINT_UNPARSED` (down from 41) — cardinality decisions the solver cannot build (**S-7**) | no — `src_new` |
| 5 | ActiveStorage routes this deployment never configured (**G-4**) | no — they are not endpoints of this application |
| 3 | `params.require(:user)` and friends need a **nested** symbolic param (**G-3**) | yes, but it is a scaffold design change |
| 1 | `users_auth_token` — a single run that does not terminate inside the inter-run time budget | yes, needs diagnosis |
| 1 | `diaspora_federation_h_card_hcard` — 8 of 9 dumps refused by `Contains(…)` (**S-1/S-2**) | no — `src_new` |

## What I would do next, in order

1. **Fix `classify_note` in `src_new`** (one line, `findings/SRC_NEW_DEFECTS.md`
   S-6). It is worth 822 atoms across 122 endpoints and nothing else on this
   list comes close.
2. **Fix the `Contains` operand order** (S-1). It is a soundness bug, not a
   spelling one, and it is currently masked by S-2 refusing the dump.
3. **Decide the `users.language` domain** for candidate endpoints. 36
   endpoints ending at `I18n::InvalidLocale` is correct modelling inherited
   from the gold batches, but it is a third of the corpus spending its budget
   on a locale check.
4. **Turn on the per-dump type table** for the 159 candidate endpoints (G-1),
   **in its own round**, and watch `dump_ir` only.
5. Raise `MAX_RUNS` per endpoint for the 37 truncated ones — the config now
   carries the limit, and `stack_remaining` says who needs it.
