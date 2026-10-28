# conversations_index — the 2026-09-26 full-gate result, what it actually means, and where things stand

Author: sub-agent, 2026-09-26. Resumable state doc: everything needed to pick
this up cold is here.

> **CLOSURE, 2026-09-26 (coordinator decision).** This endpoint is closed as
> **COVERAGE-COMPLETE WITH NO CONFINEMENT LICENCE CLAIMED**. It is **not**
> `complete: true`, and `completion.complete` remains **False** — see §8 for
> the exact claim being made, what is deliberately not claimed, and why.
> No further assumption-gate run was authorised.

---

## 0. TL;DR

1. The endpoint's **coverage verdict is complete and does not depend on the
   §16c confinement licence at all.** Proven four ways on the full 18,633-run
   corpus (§3).
2. The full gate's **71 ConfinementAssumption FAILs are, for 55 of them, an
   artifact of a known and already-documented defect (C1 trace currency)**,
   not evidence of dependence (§2). The remaining 16 are currency-independent
   and stand.
3. The C1 defect has now been **fixed batch-locally** in this endpoint's
   `coverage_report.py` (§4). `withdrawn_pairs=` wiring has been added and the
   71-pair ledger created (§4).
4. A restricted re-verification of only the confinement layer (option C) is
   **mechanically sound and needs no src/ change**, but its cost is dominated
   by an active-search layer that **has never actually executed on this
   endpoint** and is uncapped by default (§5). **Not authorised** — the
   endpoint was closed on (1) instead; see §8.
5. **Closed 2026-09-26** as coverage-complete with no confinement licence
   claimed (§8). `completion.complete` stays `False` and that is not papered
   over.

---

## 1. The state that was handed over

`coverage_summary.json` (backed up as `coverage_summary.json.fullgate_20260926`),
written 2026-09-26 19:34 by scope `fullgate-conversations-index-919r43c`,
verified field by field:

| field | value |
|---|---|
| `complete` | `False` |
| `completion.complete` | `False` |
| `completion.blocking` | 71, all `assumption FAIL (ConfinementAssumption)` |
| `tree_complete` | `True` |
| `tree_missing` | `[]` |
| `missing` | `[]` (0) |
| `coverage_complete` | `True` |
| `tree_nodes` | 105 |
| `demand_sets` | 98 |
| `total_runs` / `total_path_conditions` | 18,633 / 748,211 |
| `confinement_withdrawn_by_gate` | 71 pairs |
| `coverage_numbers_stale` | `"STALE: confined pair(s) FAILED the gate; missing/demand above were computed with them licensed"` |

Gate totals from `_assumption_results.json`:

| type | PASS | FAIL | ERROR |
|---|---|---|---|
| IndependenceAssumption | 5877 | 0 | 0 |
| ConfinementAssumption | 42 | **71** | 0 |

The gate ran 2026-09-19 -> 2026-09-26 in ~40 rounds. Each round died on
`completion.py`'s hard-coded 6-hour subprocess timeout
(`_run(..., timeout=21600)` — note this, not `completion_config.json`'s
`assumption_timeout: 604800`, is what bounded each round) and resumed from
`_fullgate919_probes.ckpt.jsonl`. That checkpoint now holds **37,505 probe
records (1.07 GB)**; `_fullgate919_index.ckpt.jsonl` holds 18,634 rows.

---

## 2. Why 55 of the 71 refutations are not refutations — the C1 trace-currency defect

### 2.1 The mechanism

`concolic_engine.assumptions.call_shape(target, note, args)` is the single
function that defines what a "shape" is, deliberately shared so the engine's
§16c footprint and the gate's `access_trace` can never disagree
(`assumptions.py:451-465`).

This endpoint's own `coverage_report.py::fix_len_names` popped `note` and
`args` off every event — a 2026-08-27 memory optimisation written 15 days
before §16c landed. The engine reads those two fields in exactly one place
(`coverage.py:2401`, the `call_shape` call). With them popped, the engine's
footprint currency degenerated to the **bare target name**, while the gate's
`access_trace` — which reads the dump files directly and never goes through
`coverage_report.py` — stayed on the **full shape**.

Clauses (i) and (ii) of `_test_confinement` compute
`leak = delta - footprint` as a **set difference of shape strings**
(`assumption_checker.py:2267-2276`). A full shape string and a bare one are
never equal, so for any changed shape carrying a note the subtraction is a
no-op and the clause cannot pass.

### 2.2 The evidence

* All **727** declared footprint entries across the 113 pairs carry an
  **empty note**. Under the C1 fix the same corpus yields **1012** entries of
  which **865 carry a note**, and the two shape-identity sets are
  **disjoint (overlap 0)**: 19 distinct shapes before, 46 after.
* **117 of the 120** leak shapes the FAIL details name carry a SQL note.
* Corpus measurement (1500-dump sample): **48 full `call_shape`s collapse to
  22 bare target names, 2.2x.**
* 40 of the 120 named leak shapes would have matched at target granularity;
  **12 of the 55** leak pairs would have passed clause (i)/(ii) outright had
  the two sides been in the same currency.
* Every ConfinementAssumption PASS on this endpoint — and on comments_index
  and notifications_index — has **dA = dB = 0**. No pair anywhere in this
  project has ever passed with a non-empty delta. The footprint-membership
  test has only ever been exercised on the FAIL side.
* The broken currency **over-licensed**: it declared **113** pairs where the
  C1-fixed measurement declares **94**, and the 94 are a strict subset
  (19 dropped, 0 added). Coarser footprints look disjoint more easily, and
  disjointness is what the licence is granted on.

### 2.3 Split of the 71

| clause | n | currency-sensitive? |
|---|---|---|
| (i) flip-A changed shapes OUTSIDE footprint(A) | 35 | **yes** — shape-set difference |
| (ii) flip-B changed shapes OUTSIDE footprint(B) | 20 | **yes** — shape-set difference |
| (iv) partner left UNEVALUATED / flip not recorded / partner's outcome changed | 16 | **no** — decided on path-condition outcomes |

So **55 currency-suspect, 16 standing**. Each row of
`_confinement_withdrawn.json` carries a `currency_suspect` flag.

34 of the 71 involve `SYM_PARAM_page_beyond`. That is one systemic pattern,
not 34 findings — but the systemic cause is the currency defect. (The
pagination reading is independently plausible: `page_beyond`'s declared
footprint was 3 shapes, and flipping it changes the conversations
`LIMIT 15 OFFSET 0` query and every per-conversation `messages` query
downstream. With the currency broken we cannot say which of those leaks
survives an honest footprint measurement.)

### 2.4 This was already known, and a doc says it was already fixed here

`reports/diaspora/docs/CONFINEMENT_PRECISION_20260913.md` §2 and
`reports/diaspora/tools/_c1_currency_patch.md` diagnose exactly this and carry
the two-line diff.

**`tools/_c1_currency_patch.md`'s "Status" section says
"`conversations_index` — applied". That claim is false.** Both pops were live
in the file when the 2026-09-19 gate ran, and the same document's §8.1
contradicts it: *"Landed in `comments_index` only ... `conversations_index` is
a closed endpoint outside this work's scope and re-running it was not in
budget."*

**Corrected 2026-09-26.** `tools/_c1_currency_patch.md`'s Status section now
reads "`conversations_index` — **applied 2026-09-26**, NOT on 2026-09-13" and
carries a dated correction block recording the false claim, the §8.1
contradiction, the 22-vs-48 shape measurement, and a warning that any
`conversations_index` result dated before 2026-09-26 has its confinement layer
measured in the wrong currency.

### 2.5 Cross-endpoint implication (NOT this endpoint's to fix)

`notifications_index` has the same unported pop and reached `complete:true`
with 44/44 ConfinementAssumption PASSes, all dA=dB=0. Per the C1 doc its
footprints are measured on 21 shapes where its gate measures 91. Its verdict
rests on the same broken handshake — in the *licensing* direction rather than
the refuting one. Flagged to the coordinator; not acted on here.

---

## 3. The coverage verdict does not depend on confinement at all

Ran `_c1_covonly.py` (non-destructive; writes `_covonly_<tag>.json`, never
`coverage_summary.json`) over the full corpus in four configurations. All
numbers below are by **direct JSON field extraction**, not stdout.

| tag | §16c | loader | withdrawn | confined pairs | splits | demand_sets | tree_complete | tree_missing | missing | nodes |
|---|---|---|---|---|---|---|---|---|---|---|
| `noconf` | **OFF** | as-shipped | – | 0 | 0 | 83 | True | **0** | **0** | 105 |
| `noconf_c1` | **OFF** | **C1 fixed** | – | 0 | 0 | 83 | True | **0** | **0** | 105 |
| `wd71` | on | as-shipped | 71 | 42 | 22 | 99 | True | **0** | **0** | 105 |
| `c1keep` | on | **C1 fixed** | 0 | 94 | 43 | 93 | True | **0** | **0** | 105 |
| `c1keep_wd71` | on | **C1 fixed** | 71 | 40 | 22 | 97 | True | **0** | **0** | 105 |

`noconf` and `noconf_c1` are **field-identical on every verdict field**, which
is expected and worth stating: `confinement=False` skips the shape computation
entirely (`coverage.py:2397 if self.confinement:`), so with §16c off the
loader's note retention cannot affect the result. **The canonical citation is
therefore invariant under both the C1 fix and the withdrawal ledger** — it
depends on neither.

Every configuration also has `coverage_complete=True`, `truncated=False`,
`solver_lost=0`, `unevaluable_exprs=[]`, `total_runs=18633`,
`total_path_conditions=748211`.

**`noconf` is the decisive row.** Switching §16c off entirely is strictly more
conservative than withdrawing any subset of the pairs — it withdraws all of
them and declines to infer any new ones. The tree is still complete with zero
missing. Therefore the 71 refutations, genuine or artifact, **cannot open this
tree**. This is outcome (a): no re-drive is needed.

This is the same three-way verification comments_index documented for its own
15 withdrawn pairs (`_confinement_withdrawn.README.txt` there: "confinement
OFF / ON / ON-with-these-15-withdrawn all print COMPLETE=True").

Cost of the C1 fix, measured on this corpus: peak RSS **522 -> 610 MB
(+17 %)**, load time unchanged (~40 s), check 15-23 s. Affordable.

---

## 4. What has been changed (all batch-local; nothing in `src/` touched)

| file | change |
|---|---|
| `_confinement_withdrawn.json` | **new** — all 71 gate FAILs, people_stream's format (`pair` / `withdrawn_by` / `refutation` / `bases_probed` / `bases_failing` / `currency_suspect`). Verified set-identical to `confinement_withdrawn_by_gate`. |
| `_confinement_withdrawn.README.txt` | **new** — contents + the C1 caveat. |
| `coverage_report.py` | **§16c cross-pass loop wired**: reads the ledger as `CoverageChecker(withdrawn_pairs=)`, plus `WITHDRAWN_PAIRS_FILE` / `NO_WITHDRAWN_PAIRS` / `CONFINEMENT=0` env knobs. Matches comments_index and people_stream. |
| `coverage_report.py` | **C1 fix applied** — the `ev.pop("note")` / `ev.pop("args")` pair deleted; `ev.pop("traceback")` kept. `sv.pop("note")` on `symbolic_vars` kept (call_shape never reads it). |
| `coverage_report.py.pre_withdrawn_20260926` | backup of the file as the 2026-09-26 gate ran it. |
| `coverage_summary.json.fullgate_20260926` | backup of the gate's summary. |
| `_c1_covonly.py` | **new** — non-destructive coverage-only probe with `--no-confinement` / `--keep-notes` / `--withdraw`. |
| `_covonly_{noconf,wd71,c1keep,c1keep_wd71}.json` + `.log` | the §3 results. |
| `_c1_declared_confinement.json` | the 94 C1-fixed declared pairs with honest footprints. |

`completion_config.json` was **not** touched; `assumption_timeout` is still
604800.

---

## 5. Option (C) — restricted re-verification of the confinement layer: feasibility and cost

### 5.1 Mechanically sound? YES, and it needs no src/ change

`completion.py:342-349` writes `_assumptions_declared.json` and invokes
`assumption_cmd` with `--declared <that file>`. `run_declared(cfg, declared)`
simply tests whatever list it is handed. So restricting scope is: write a
declared file containing only the ConfinementAssumption rows and invoke
`assumption_checker.py` on it directly, with the same `ACHK_CHECKPOINT`.

**Is restricting scope safe — can it silently miss something?** Yes, safe, and
this is provable rather than assumed:

* The C1 fix changes the confinement layer **only**. Declared
  IndependenceAssumptions are **6123 before and 6123 after, identical**; the
  total moved 6236 -> 6217 purely because 19 confinement pairs dropped. So
  reusing the 5877 IndependenceAssumption PASSes is sound — they were not
  computed from anything C1 touches.
* The 5877 independence verdicts do not read footprints at all.
* The C1-fixed pair set is a **strict subset** of the tested set (94 ⊂ 113,
  0 new pairs, 61 ⊂ 67 distinct decisions), so nothing new enters scope.

### 5.2 The probe checkpoint survives the C1 fix

`ProbeCache`'s key is `{engine source hash, phase, digest(cfg), _canon_key(),
keep}` plus `digest([scenario, seeds])` per record. Checked:

* `digest(cfg)` is over `assumption_manifest.json` — **not** touched.
* `_canon_key()` returns the constant `"none"` unless the manifest declares a
  `canonicalize` hook. **This manifest declares none**, so editing
  `coverage_report.py` cannot invalidate the bank. (The gate reads dump files
  directly; it never loads through the endpoint's loader. This is also why the
  gate's side of the handshake was correct all along.)
* `engine` is the assumption_checker module's source hash — stays valid as
  long as no `src/` edit is made.

So the 37,505-probe / 1.07 GB bank is **reusable as-is**.

### 5.3 The cost — cheap where you'd expect, and one genuine unknown

Cost model (`assumption_checker.py:2074-2078`), per confined DECISION, with
identical seed dicts deduped in the ProbeCache:

* **composition, clauses (i)-(v)/(viii)** — 3 replays per pair per base.
  Stage 1 is 1 base; stage 2 escalates non-FAIL pairs to `ACHK_BASES=8`.
  Upper bound 94 x 8 x 3 = 2,256 replays, and **every one is a flip of one of
  61 decisions already probed on bases from the same corpus**, so the great
  majority should be cache hits. *Cheap: hours at worst, plausibly minutes.*
* **(vi) exhaustive flip** — one replay per profile carrying a footprint
  shape, per decision-member, capped by `ACHK_CONF_PROFILES` (**default 0 =
  ALL**).
* **(vii) constructed route** — one replay per footprint shape with another
  producer. Bounded by the 1012 footprint entries.

**The unknown, and it is a real one: (vi) and (vii) have never actually
executed on this endpoint.** In the completed gate:

* every one of the 84 `(vi)` readings across the 42 PASSes says
  **`0/0 profile(s) flipped`** — with note-less footprints, no profile carried
  a footprint shape, so the exhaustive flip had nothing to do;
* every `(vii)` route came back **`UNSAT — no route exists`**, i.e.
  **0 constructed routes replayed**.

With the C1 fix the footprints carry 46 real shapes that profiles genuinely
do carry, so (vi) would do real work for the first time. **The corpus has
17,902 distinct outcome profiles** (of 18,633 dumps). With the default cap of
ALL, the worst case is ~17,902 flips per decision-member; across 61 decisions
that is O(10^6) probes. At the rates recorded in
`assumption_checker.py:1122-1123` (28 min / 184 probes = 9.1 s; 112 min /
5,075 probes = 1.3 s, the difference being `ACHK_PROBE_BATCH=40` batching),
10^6 probes is **~2 weeks of pure JRuby**. Even 5 % of the worst case is
~20 hours; 25 % is ~4 days.

**Capping does not rescue it.** `ACHK_CONF_PROFILES=N` that truncates makes the
verdict `NOT-TESTABLE` — *"a PASS needs every profile"*
(`assumption_checker.py:1843-1845`) — and `completion.py:416` withdraws a
NOT-TESTABLE inferred pair exactly as it withdraws a FAIL. So a capped (C)
produces the same outcome as not running (C) at all, only slower.

### 5.4 Honest estimate

| part | estimate | confidence |
|---|---|---|
| composition (i)-(v)/(viii) for 94 pairs, reusing the bank | **minutes to a few hours** | high — subset of already-probed decisions |
| (vii) constructed routes, ≤1012 shape entries | **~0.5-3 hours** if all miss | medium |
| **(vi) exhaustive flip** | **unbounded by default; 20 h to ~2 weeks** | **low — never executed here, no empirical base** |

So (C) is **not** reliably "dramatically cheaper". Its cheap half is genuinely
cheap; its expensive half is work the previous 7-day run never did, so the
7-day figure is not an upper bound for it.

### 5.5 A policy question (C) raises

54 of the 94 C1-fixed pairs are in the 71-pair withdrawal ledger. If the
ledger is honoured, only **40** pairs remain to test and (C) shrinks
accordingly. But those 54 were withdrawn on currency-broken evidence, so
honouring the ledger inside (C) partly defeats (C)'s purpose. Whoever runs (C)
must decide explicitly: **discard the ledger for the re-run** (test all 94,
full cost) or **honour it** (test 40, cheap, but 54 pairs stay withdrawn on
evidence we now know is unreliable). Running with `NO_WITHDRAWN_PAIRS=1` is
the "discard" path.

### 5.6 A cheaper alternative worth considering (option D)

Since §3 shows the endpoint is complete with **no** confinement licence at
all, the confinement layer buys this endpoint nothing. Closing it as
"complete with §16c switched off" needs **zero** further gate time. The only
thing (C) would add is the ability to write `completion.complete: true` rather
than "coverage-complete under no confinement licence".

---

## 6. Where things stand / what is NOT done

* **Not started, and deliberately so:** any gate re-run — full (B) or
  restricted (C). The coordinator closed the endpoint on §3 instead (§8).
  §5 is the standing cost analysis if anyone revisits.
* **Done 2026-09-26:** correcting `tools/_c1_currency_patch.md`'s false
  "conversations_index — applied" status line (§2.4).
* **Done 2026-09-26:** `POLICY_HEADER.txt` rewritten from a 14-line stub into
  a real canonical header carrying the ASSUMPTION BASIS (the §8 closure
  wording), the SCOPE block, and the three declared limits from `REPORT.md`
  §4. Stub preserved at `POLICY_HEADER.txt.pre_c1close_20260926`.
  `docs/TODO.md` §B1 had this endpoint flagged *"closed; POLICY_HEADER
  missing (T1, deferred)"* — that deferral is now discharged.
* **Done 2026-09-26:** SQL-policy re-extraction + `policy-extraction-bench`
  — see §9.
* **Not touched:** `results3/posts_show/` and anything in `src/`.
* **Not touched:** `notifications_index` (§2.5 is a lead for someone else,
  raised to the user by the coordinator, not acted on here).
* **Not promoted:** `results3/queries_from_runs/conversations_index.sql`
  remains the stale 2026-09-01 canonical file. Per
  `_BENCHMARK_RUNS_20260919.md` §2 — *"Nothing has promoted
  `_pcfold3_fix.sql` to canonical, and this pass deliberately did not do so —
  that is a decision for the user"* — promotion is not a sub-agent decision
  and was not taken here either.

## 7. How to resume

```bash
cd /home/dev/project/reports/diaspora/results3/conversations_index

# re-prove the §3 table (each ~1-2 min, non-destructive)
PYTHONPATH=/home/dev/project/src python3 _c1_covonly.py --tag noconf --no-confinement
PYTHONPATH=/home/dev/project/src python3 _c1_covonly.py --tag c1keep_wd71 --keep-notes \
    --withdraw _confinement_withdrawn.json

# the FINAL report (coverage + completion), now C1-fixed and honouring the ledger.
# NOTE: this overwrites coverage_summary.json — the gate's copy is backed up at
# coverage_summary.json.fullgate_20260926.
PYTHONPATH=/home/dev/project/src python3 coverage_report.py

# coverage-only (no completion gate):
SKIP_COMPLETION=1 PYTHONPATH=/home/dev/project/src python3 coverage_report.py
```

---

## 8. THE CLOSURE — exactly what is and is not claimed

Coordinator decision, 2026-09-26: ship as coverage-complete now; no gate
re-run, restricted or full.

### 8.1 The claim

> **conversations_index is COVERAGE-COMPLETE WITH NO CONFINEMENT LICENCE
> CLAIMED.** On the 18,633-run corpus, with §16c switched off entirely, the
> execution tree is complete and nothing is missing: `tree_complete=True`,
> `tree_missing=[]`, `missing_branches=0`, `tree_nodes=105`,
> `demand_sets=83`, `truncated=False`, `solver_lost=0`,
> `unevaluable_exprs=[]`, over 748,211 path conditions.

**Canonical citation: `_covonly_noconf.json`** (reproduced byte-for-byte on
the verdict fields by `_covonly_noconf_c1.json`).

This is the right artifact to cite externally because it is the **strictly
conservative reading** and it depends on nothing contested:

* it claims **no** confinement licence — every inferred pair is dropped, not
  just the 71 the gate refuted, so the correctness of those 71 verdicts is
  irrelevant to it;
* it does **not** read the withdrawal ledger;
* it is **invariant under the C1 fix** (§3), so it does not depend on the
  defect diagnosis either.

Put differently: every known and suspected defect in this endpoint's
confinement layer is in the *licensing* direction, and this claim takes zero
licence.

### 8.2 What is NOT claimed

**`completion.complete` is `False`, and this closure does not change that.**
It is False for one reason: the assumption gate FAILed 71 inferred
ConfinementAssumptions, and `completion.py:416` blocks completion on any
inferred pair the gate did not PASS. That is the correct behaviour and the
flag is left standing.

Specifically NOT claimed:

* **not** `complete: true`;
* **not** that the 71 refuted pairs are independent — 16 of them (§2.3) are
  currency-independent refutations that stand, and the other 55 are simply
  *unknown*, not disproved;
* **not** that any confinement licence is sound on this endpoint. The
  confinement layer here is measured in a currency the gate does not share
  (§2) and has never had its active search (clauses vi/vii) actually execute
  (§5.3). Nothing in this closure rests on it.

`coverage_summary.json` is deliberately **left as the gate wrote it** —
`complete: False`, 71 blocking entries, `coverage_numbers_stale` set. It is
the honest record of the gate run and it is not overwritten by this closure.
Anyone reading that file sees the failure and the stale warning, and is
pointed here.

### 8.3 The 16 refutations that stand

These are currency-independent (clause (iv), decided on path-condition
outcomes, not shape sets) and are real findings regardless of C1. They are not
a gap in the closure — §16c is not licensed at all — but they are recorded so
nobody re-derives them:

* **8x "flip-X leaves the partner UNEVALUATED"** — removal-shaped dependence
  (foreclosure, X11), not a confined pair. Six of these pair
  `SYM_PARAM_page_beyond == True` or a row-count against a
  `Calculations.count` / association decision: on a beyond-the-last-page
  request the app short-circuits and the partner decision is never reached.
* **3x "flip-both does not record A flipped (base outcome)"** — all three are
  two comparisons **on the same variable**
  (`to_a_2_rows != 0` vs `< 15`; `count_2 != 0` vs `> 1`;
  `count_3 != 0` vs `> 1`). Flipping one constrains the other, so the double
  flip cannot realise both. These could never have been confined pairs.
* **3x "the partner is downstream of the flipped decision"** — identity
  comparisons chained through `devise_user_first_1_person_id`.

Each is flagged `"currency_suspect": false` in `_confinement_withdrawn.json`.

### 8.4 If someone later wants `completion.complete: true`

They need the confinement layer to be honest, which means the C1 fix (already
applied, §4) plus a gate run over the confinement pairs. **§5 is the complete
cost analysis — start there, do not re-derive it.** In short:

* option **(B)** full gate re-run: the last one took 2026-09-19 -> 2026-09-26;
* option **(C)** restricted to the 94 C1-fixed confinement pairs: mechanically
  sound, needs no `src/` change, and the 37,505-probe bank is reusable — but
  the cost is dominated by clauses (vi)/(vii), which **have never executed on
  this endpoint** and are uncapped by default against 17,902 distinct outcome
  profiles. Estimate 20 h to ~2 weeks, low confidence. Capping
  `ACHK_CONF_PROFILES` does not help: a truncating cap yields NOT-TESTABLE,
  which is withdrawn exactly like a FAIL.
* §5.5 records the policy choice (C) forces: honour the ledger (40 pairs to
  test, cheap, but 54 stay withdrawn on unreliable evidence) or discard it
  with `NO_WITHDRAWN_PAIRS=1` (94 pairs, full cost).

Neither was started.

---


## 9. Policy re-extraction and benchmark (2026-09-26)

### 9.1 TWO CORPORA, TWO DEPLOYMENTS — read this before comparing any numbers

This endpoint has two corpora and they are **not interchangeable**:

| | `results3/conversations_index/` (MAIN) | `_redrive_20260919/conversations_index/` (RC-1) |
|---|---|---|
| dumps | 18,633 | 18,623 |
| driven | 2026-08-31 | 2026-09-18 |
| targets | `targets.rb.pre_rc1_20260919` | current `targets.rb` |
| `Rails.env` | `concolic` (**non-mod**) | `concolic_mod` |
| `profiles` reads | **wide** — `SELECT "profiles".*`, 18 cols (905 in a 400-dump sample) | **narrow Q1** — `profiles.id, diaspora_handle, first_name, last_name, image_…` (909 in the same-size sample) + gated Q2 |
| certified complete | **yes — this is the corpus §3/§8 certify** | by transfer (below) |

`docs/RC1_LAZY_FETCH_AS_DECISION_20260925.md` §6.3 is explicit that
`Rails.env.include?("mod")` is deliberately NOT symbolised, so **a policy file
describes ONE deployment**, and which one depends on the corpus. Without the
`concolic_mod` default scope, `default_projection` reads an empty
`select_values`, every `profiles` read reverts to 18 columns, and no lazy
reader is installed — so a main-corpus policy describes a **non-mod pod**.

**Completeness transfers between the two; the projection does not.**
`_redrive_20260919/_logs/_verify_conversations_index.txt` certifies
`VERDICT: BRANCHING IDENTICAL` across all ten request variants — per-seed PC
mismatches 0, seed multisets identical, error profiles identical. The RC-1
redrive changed what the mocks RECORD, not which branches the app takes. That
is precisely what `_verify_corpus.py` exists to license.

Neither the C1 fix nor the closure can move any of these numbers:
`queries_from_runs` reads the dump files directly and never goes through
`coverage_report.py`, so the loader change cannot touch extracted SQL.

### 9.2 What was run

`_pcfold3_parallel.py` over the MAIN corpus — the corpus §8 certifies —
`--shards 4 --cap 2 --suffix _c1close`, under `MemoryMax=8G CPUQuota=500%`
(scope `ci-c1close-extract.scope`) because another agent's posts_show
confinement census was live. Shard count does not affect the result: shards
merge into one dict keyed on `(shape, pc_preds)` (`_pcfold3_parallel.py:148`),
and `two_query_cap=2` matches RC-1 exactly.

Bench grader calibration checked first (`scripts/selftest.py`): oracle
`disclosure_macro_f1`, `disclosure_f1`, `table_f1`, `statement_f1` all `1.0`.

Artifacts: `_c1close_extract.log`, `_c1close_{base,fix}.sql`,
`_c1close_summary.json`, `_c1close_bench.jsonl` (+ `.graded.jsonl`),
`_c1close_finish.log`. Driver: `_c1close_finish.sh`.

### 9.3 Numbers

Extraction, MAIN corpus: 18,633 dumps, 18,633 runs, 404,285 raw queries,
**2,023 distinct (shape, preds)**, 0 errors, 896 s.
Arms: `base` 353 statements (PC 8772 -> 1471 kept), `fix` 465 statements
(PC 8772 -> 2275 kept).

**These are identical to RC-1's** (18,623 dumps, 404,127 raw, 2,023 distinct,
base 353 / PC 1471, fix 465 / PC 2275) — the two corpora agree on structure
exactly, which is the branching-identical verdict showing up a second way, in
the extractor rather than the verifier.

Where they differ is the `profiles` projection, and only there:

| | MAIN (`_c1close_fix.sql`) | RC-1 (`conversations_index_rc1mod_fix.sql`) |
|---|---|---|
| statements | 465 | 465 |
| bytes | 521,436 | 533,130 |
| wide `profiles`.* reads | **62** | **0** |
| lazy columns (bio/gender/birthday/location) | 0 | 0 |

`bench.grade`, `diaspora/conversations-index` (16 reference statements,
465 predicted in all three):

| metric | MAIN `_c1close` (this pass) | RC-1 `rc1mod` | MAIN `pcfold3` (2026-09-18) |
|---|---|---|---|
| disclosure_precision | 0.9286 | **0.9630** | 0.9211 |
| disclosure_recall | 0.8889 | 0.8889 | 0.8898 |
| disclosure_f1 | 0.9083 | **0.9244** | 0.9052 |
| disclosure_macro_f1 | 0.6956 | **0.7060** | 0.6677 |
| table_precision | 0.7333 | 0.7333 | 0.7333 |
| table_recall | 1.0 | 1.0 | 1.0 |
| table_f1 | 0.8462 | 0.8462 | 0.8462 |
| statement_f1 | 0.0404 | 0.0421 | 0.0413 |

Reading it:

* **This pass reproduces the main corpus.** `_c1close` lands on top of the
  2026-09-18 `pcfold3` run of the same corpus (precision 0.9286 vs 0.9211,
  recall 0.8889 vs 0.8898, table_f1 identical). The small precision gain is
  the 10 `_achk*` gate-probe dumps the corpus has gained since. **Nothing
  here moved because of the C1 fix or the closure, and nothing could have:**
  `queries_from_runs` reads dump files directly and never goes through
  `coverage_report.py`.
* **The MAIN-vs-RC-1 precision gap is the deployment, not quality.**
  0.9286 vs 0.9630 is the 62 wide `profiles`.* statements — §9.1. Recall and
  every table metric are identical, which is what you expect when the same
  reads are described at a different projection width.

Suite level, all four diaspora tasks (the other three rows are unchanged
controls — comments-index 1.0/1.0, people-stream 1.0/1.0, notifications-index
0.9483/0.9940):

| suite metric | with MAIN `_c1close` | with RC-1 `rc1mod` |
|---|---|---|
| disclosure_macro_f1 | 0.8735 | 0.8760 |
| disclosure_f1 | 0.9697 | 0.9738 |
| disclosure_recall | 0.9707 | 0.9707 |
| disclosure_precision | 0.9692 | 0.9778 |
| table_f1 | 0.9484 | 0.9484 |
| statement_f1 | 0.2909 | 0.2913 |
| n_tasks / n_errored | 4 / 0 | 4 / 0 |

**So the RC-1 policy remains this endpoint's best artifact**, and it is the
one that describes the reference's own deployment. The `_c1close` extraction's
job was provenance — to show what the corpus the completeness claim is
actually certified on yields — and it did that.

### 9.4 Nothing was promoted

`results3/queries_from_runs/conversations_index.sql` is left as the stale
2026-09-01 canonical file. `_BENCHMARK_RUNS_20260919.md` §2: *"Nothing has
promoted `_pcfold3_fix.sql` to canonical, and this pass deliberately did not
do so — that is a decision for the user."* Coordinator ruling 2026-09-26 kept
it that way.

### 9.5 F7 loadability — PASS, and it retired a stale declared limitation

`policy_loadability_audit.py` on `_c1close_fix.sql` (log: `_c1close_f7.log`):

    written=465  loadable=465  unloadable=0  100.00%
    unresolved binds: 0 distinct, 0 statement occurrences
    RESULT: pass — every statement loads and every bind is resolved.

This is worth more than a green tick, because it **contradicted** a
limitation this endpoint had been carrying. The audit's own docstring records
that *"conversations_index shipped 43 such occurrences (the authenticated
user's own person id) with every dump-side audit green"*, and the 14-line stub
`POLICY_HEADER.txt` declared exactly that bind as an unresolved placeholder.
Counting non-comment lines:

| policy | `_SYM_RESULT_` occurrences |
|---|---|
| `_c1close_fix.sql` (main corpus, 2026-09-26) | **0** |
| `conversations_index_rc1mod_fix.sql` (RC-1) | **0** |
| `queries_from_runs/conversations_index.sql` (2026-09-01 canonical) | **47** |

The unresolved binds are a property of the **stale canonical file only**. The
resolver has since been fixed and both current policies resolve every bind.
The stub's NOTE was therefore describing a file nobody should be shipping, and
carrying it forward would have UNDERSTATED what the policy asserts — the
inverse of the failure the header convention is written against. The NOTE has
been withdrawn from `POLICY_HEADER.txt` and replaced with the measurement
above plus a warning about the canonical file.

Had F7 been assumed green rather than run, this would have gone unnoticed.

---
