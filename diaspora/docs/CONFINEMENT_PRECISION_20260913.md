# Why §16c's inference is refuted by its own gate — and what a sound cheaper
# inference looks like (2026-09-13)

**Status of §0-§7: a MEASUREMENT and a PROPOSAL. Nothing in `src/` was
changed, no endpoint state file was touched, no coverage pass or gate was
run.** The tools are
`reports/diaspora/tools/_conf_precision_{sample,pairs,span}.py`
(read-only, `concolic-cov.slice`, cap 2 G).

**SUPERSEDED IN PART BY §8 (2026-09-14).** C1 is measured and landed in
comments_index, C2 and C3 are implemented in `src/` behind flags that default
to today's behaviour, the matrix is re-measured with the ENGINE's own
licensing, and comments_index now runs with confinement OFF. Two of §5's
claims did not survive that: **C3 as written (`fp = reach`) is inert** — the
knob to use is the existing `confinement_keying="exact"` — and **criterion I
makes ONE false licence, not zero**. Read §8 before acting on §5.

Question asked: the §16c inference is refuted by its own gate at 76-85 % on
notifications_index and 33 % on comments_index. The gate's stated failure mode
is *"the flip changed shapes OUTSIDE the measured footprint"*, i.e. the
footprint is measured too small. **Establish why, precisely, from the failing
pairs' own data.**

---

## 0. The answer in five lines

1. On notifications_index and comments_index the footprint is not measured in
   §16c's currency at all. Their batch loaders drop `note` and `args` from every
   event before `Run.from_dict`, so `call_shape` degenerates to the **target
   method name**: 16 distinct shapes on notifications, 9 on comments_index,
   against the **91** and **22** the gate's `access_trace` measures on the same
   corpus. The two currencies the `call_shape` docstring says "can never
   disagree" disagree by 5.7× and 2.4×.
2. That is real but it is **not the biggest cause**. Re-measuring the footprints
   in the correct currency on the same corpora recovers only **8 of the 93
   FAILs**.
3. **50 of the 93 FAILs (54 %) are on a decision that has NO EXACT MATCHED
   CONTEXT at all** — it is "decided" only through the co-evaluated fallback
   added on 2026-09-11 ("GATES ARE MEASURABLE"). Pairs in which both members
   have a real exact context pass the gate **35/40 = 87.5 %** of the time; pairs
   with at least one fallback-only member pass **64/152 = 42 %**.
4. **33 of the 93 (35 %) are context-blind**: the shape the flip moved lies
   outside the union of the traces of every profile in the decision's matched
   contexts, so the differential was structurally unable to see it either way.
   On notifications **158 of 159** exactly-keyed decided decisions have a
   non-empty blind set, median **31 %** of everything the decision reaches.
5. It is **not** a small-cell problem. FAILing pairs have *more* matched
   contexts than PASSing ones (notifications median 71 vs 39). **No minimum-
   support threshold separates them**; every threshold that removes the 78
   removes most of the 24 PASSes first.

The sound cheaper inference is therefore not a support threshold. It is:
measure in the currency the falsifier is tested in; attribute what the matched
contexts could not observe to the footprint instead of withholding it; and stop
treating the co-evaluated fallback as a licence. Priced below: **precision 1.00,
zero false licences over 192 probed pairs, at recall 0.21.**

---

## 1. What was read, and what each artefact says

| artefact | what it gave |
|---|---|
| `notifications_index/_assumption_results.json` | 146 `ConfinementAssumption` rows: **102 freshly probed (78 FAIL / 24 PASS)** + 44 class-reused PASS from the 2026-09-11 gate |
| `notifications_index/_assumptions_declared.json` | the **656** pairs the C20R4 pass licensed, each with `footprint_a` / `footprint_b` |
| `notifications_index/_prior_footprints.json` | the 2026-09-11 pass's footprints, 193 decisions, **20 distinct shapes** |
| `notifications_index/_c11_withdraw_conf.json` | the 2026-09-11 class gate: 247 non-PASS classes covering **1 806 pairs** — (i) 1 112, (ii) 447, (iv) 243 |
| `notifications_index/_c21_withdraw_conf.json` | the 78 current FAILs with their probe detail |
| `notifications_index/_achk_probe_checkpoint.jsonl` | **4 169 replay traces** the gate actually measured (fine currency) |
| `comments_index/_bak_assumption_results_20260913_0200.json` | 46 probed, **15 FAIL** ((i)×12, (ii)×3) |
| `comments_index/_RESTORED_20260913.md` §2.3 | the three-way confinement OFF / ON / ON-15 A/B |
| `posts_show/_p25_pairs_P24.json`, `_COMPLETION_20260910.md` §82 | 123 decided, 700 strict / **2 701** OR pairs, and the three demand readings |

New measurements (uniform samples, fixed seed 20260913):
notifications 20 000 of 132 524 dumps → 19 367 profiles, 441 exprs;
comments_index all 26 528 dumps → 25 408 profiles.
The sample reproduces the shipped inference: 633 of the 651 declared pairs it
can score come back licensed under the coarse currency, against 656 shipped.

---

## 2. The root fact: the two currencies disagree

`concolic_engine/assumptions.py::call_shape` returns
`(target, note with binds and string literals wildcarded, arg shape)`, and its
docstring says it is "one function so the two can never disagree on what a shape
is". The engine calls it on `run.symbolic_call_events`; the gate calls it on the
raw dump. Between them sits the batch loader.

`notifications_index/coverage_report.py::fix_len_names` (and the byte-identical
copies in `comments_index` and `conversations_index`) — a 2026-08-27 memory
optimisation written 15 days before §16c existed:

```python
for ev in dump.get("events") or ():
    ...
    ev.pop("note", None)      # "notes are large SQL strings"
    ev.pop("args", None)
    ev.pop("traceback", None)
```

`posts_show/coverage_report.py` does **not** do this — it round-trips the dump
through `json.dumps`/`loads` and keeps everything.

Measured consequence:

| endpoint | loader keeps `note`? | distinct shapes the ENGINE sees | distinct shapes the GATE sees | footprints with a non-empty note |
|---|---|---|---|---|
| notifications_index | **no** | **21** (16 ever used in a footprint) | **91** | **0 / 16** |
| comments_index | **no** | **22** (9 used) | **22** | **0 / 9** |
| posts_show | yes | 69 | 69 | **52 / 69** |

On notifications one target carries up to 18 distinct statements
(`Anonymous.load_intermediate`), and in 2 865 of the gate's 4 169 replay traces
two or more of them co-occur *in the same run*. When a flip swaps
`… "people"."id" IN (?, ?, ?)` for `… IN (?, ?, ?, ?)`, or an SQL read for the
`preloaded association #actors: answered from the loaded target` answer, the
coarse target's presence is unchanged, the differential
`(uT & ~iF) | (uF & ~iT)` cancels to zero, and the shape never enters the
footprint. The gate then replays in the fine currency, sees the change, and
reports it OUTSIDE the footprint — correctly.

The clean demonstration is comments_index's `(Length(SYM_PARAM_post_id) < 16)`,
the guid-versus-id dispatch. Its coarse footprint is **empty**, so it was
licensed as vacuously confined with everything; the gate's flip moves
`ci_author_first | … WHERE "posts"."guid" = ? …` to
`ci_author_first | … WHERE "posts"."id" = ? …`. Same target, different column,
one shape to the engine.

Note the endpoints' own `coverage_report.py` already records the mechanism, in
the comment above `apply_len_bounds`: *"the real Preloader emits `col = ?` for
one owner row and `col IN (…)` for two or more, and the corpus has to be able to
say which."* The loader 40 lines above deletes exactly the field that says which.

### 2a. The coordinator's preload hypothesis, tested

Hypothesis relayed: the missed shapes are preloaded-association / loaded-target
answers, which "in the corpus's matched context are answered from memory and so
may contribute no statement to the differential", so `infer_footprints` must be
made to count them.

**The pattern is real; the mechanism is not, and the proposed fix is a no-op.**

* Pattern, quantified over the 235 named leak shapes: **54 (23 %) are
  memory-answered** (`preloaded association #…`, `loaded relation: #first
  answers from the in-memory target`). At pair level **47 of the 76**
  notifications FAILs with a parsed leak list name at least one; 29 name none.
  On comments_index it is **0 of 37** — that endpoint's 15 FAILs are pure SQL,
  so the mechanism cannot be the general cause.
* Mechanism, checked in the dumps: a memory-answered read **is** a
  `symbolic_call` event **with** a `result_name` (verified on
  `dump_html_plain_dse0001_C13Ahtmp0000r0.json`: `target
  ActiveRecord::Associations::CollectionProxy.records`, `note "preloaded
  association #actors: …"`, `result_name SYM_RESULT_…_records_1`). It therefore
  already enters `run.symbolic_call_events`, already enters the engine's trace
  mask, and already enters `access_trace`. **Nothing is missing from the
  footprint's input.** Adding memory-answered reads would change no bit.
* What is lost is the *note that distinguishes* the memory answer from the SQL
  sibling at the same target — which is the §2 defect, not a separate one. Keep
  the note and the swap becomes a visible differential; add memory-answered
  reads and nothing happens.

---

## 3. The 93 FAILs, classified

Per-FAIL primary cause. The gate's `detail` names at most 3 of the leaked
shapes, so shape-level counts are over the 235 named (198 notifications + 37
comments_index); pair-level counts are over all 93. Each leaked shape is scored
against the footprint the FINE currency produces on the same corpus
(`_conf_precision_pairs.py --pairs`, `fp_shapes_fine`).

### 3.1 Pair level — the requested (a)/(b)/(c)/(d)

| class | notifications | comments_index | **both** |
|---|---|---|---|
| **(a-struct)** offending decision has **no exact matched context** — decided only by the co-evaluated fallback | 43 | 7 | **50 (54 %)** |
| **(a)** context-blind: the leak is another statement at a target the footprint already names | 13 | 7 | **20 (22 %)** |
| **(a)** context-blind: the leak is at a target the footprint never names | 12 | 1 | **13 (14 %)** |
| **(b)** keying: the leak is recovered by the FINE currency (or is an IN-arity / clause-order sibling of a footprint shape) | 8 | 0 | **8 (9 %)** |
| **(d)** removal-shaped dependence — criterion (iv), the partner is left unevaluated | 2 | 0 | **2 (2 %)** |
| **total** | **78** | **15** | **93** |

**(c)** — a genuinely two-sided decision the strict one-sidedness test passed by
accident — is measurable separately, because the counterexample search runs over
`side_seen`, which is built in the *same* coarse currency. Re-running it in the
fine currency disqualifies **18 more notifications decisions** (190 → 208 of
360) and **0 more** on comments_index. Those 18 are class (c): one-sided only
because the currency could not see the counterexample. They account for part of
the 81-pair gap between the coarse (633) and fine (552) licences.

### 3.2 Shape level — how far wrong the footprint was

| the leaked shape … | notifications (198) | comments_index (37) |
|---|---|---|
| **is** in the FINE footprint (pure currency loss) | 25 (13 %) | 13 (35 %) |
| differs from a FINE footprint shape only by IN-arity / clause order | 3 (2 %) | 0 |
| is a *different statement* at a target the FINE footprint names | 137 (69 %) | 23 (62 %) |
| is at a target the FINE footprint never names | 33 (17 %) | 1 (3 %) |

Against the footprint that was actually **shipped** (coarse), 114 of the 198
notifications leaks project onto a target the footprint already contained —
i.e. more than half of the "outside footprint" shapes are outside only because
of the currency.

### 3.3 Why "different statement at a known target" is not a support problem

Because those statements are not rare. Take the top leaked shapes by frequency:
`Anonymous.load_intermediate | SELECT "people".* … "id" = ?` (39 hits in the
2026-09-11 class gate, 20 here), `CollectionProxy.records | preloaded
association #actors …` (20), `FinderMethods.first | SELECT "people".* … "id" =
?` (18). `Anonymous.load_intermediate` appears in **74 %** of the gate's replay
traces; `SingularAssociation.find_target` in **99.98 %**. These are shapes the
corpus sees constantly. They are missing from the footprint because the *matched
contexts* — profile pairs that agree on every other evaluated expression — never
contained them varying, not because the corpus is thin.

§24.3 of `_COMPLETION_CAMPAIGN_20260910.md` read this as the property genuinely
not holding: *"almost every decision's flip perturbs the SAME `people` read …
245 of 291 tested classes is not a marginal failure rate."* That reading is
premature. The `people` read it names is exactly the shape whose coarse
projection is present in three quarters of all runs, so the coarse differential
could never contain it under any corpus.

---

## 4. Is the corpus hole systematic? — measured, and the answer is NO in the
## form the question assumed

`infer_footprints` buckets each single-sided profile by
`(evaluated \ D, taken \ D, both-sided)` and calls a bucket with both a `D=T`
and a `D=F` side a matched context. "Matched" therefore means **agreeing on
every expression any profile mentions**, tracked or not.

### 4.1 Cell-size distribution behind the inferred pairs, split by gate verdict

Matched-context count (`ctxn`) of each pair member, fine keying:

| endpoint | verdict | n | min | p25 | **median** | p75 | max |
|---|---|---|---|---|---|---|---|
| notifications | PASS | 136 | 1 | 22 | **39** | 66 | 18 011 |
| notifications | **FAIL** | 156 | 1 | 31 | **71** | 1 081 | 19 366 |
| comments_index | PASS | 62 | 22 | 425 | **2 853** | 5 910 | 6 888 |
| comments_index | **FAIL** | 30 | 1 | 1 130 | **2 633** | 9 787 | 13 182 |

**The FAILing pairs have MORE support, not less.** A minimum-support threshold
is therefore not available. Priced anyway, on notifications:

| threshold on min(ctxn) | pairs licensed | of 78 FAIL removed | of 24 fresh PASS removed | precision |
|---|---|---|---|---|
| none (fine currency) | 552 | 35 | 6 (of 68 incl. reused) | 0.59 |
| ≥ 2 | 513 | 37 | 9 | 0.59 |
| ≥ 5 | 425 | 39 | 15 | 0.58 |
| ≥ 10 | 385 | 43 | 19 | 0.58 |
| ≥ 50 | 44 | 62 | 59 | 0.36 |
| ≥ 100 | 23 | 66 | 67 | 0.08 |

Precision never rises. There is no threshold that removes the 78 and keeps the
24: the two populations are not separated on this axis at all.

### 4.2 The hole that IS systematic — CONTEXT SPAN

The right measure is not how many contexts a decision has but **what those
contexts contain**. Define, in the fine currency:

* `reach(D)` — the union of the trace masks of every profile that evaluates `D`
  single-sided;
* `span(D)` — the union of the trace masks of the profiles that actually sit in
  one of `D`'s matched contexts;
* `blind(D) = reach(D) \ span(D)` — shapes `D` co-occurs with that no matched
  context contains. The differential is structurally unable to put these in the
  footprint **or** to rule them out.

Measured (`_conf_precision_span.py`):

| endpoint | exactly-keyed decided decisions | with `blind ≠ ∅` | median `blind`/`reach` | median reach | median span | median footprint |
|---|---|---|---|---|---|---|
| notifications | 159 | **158** | **0.31** | 57 | 38 | **0** |
| comments_index | 34 | **21** | 0.05 | 20 | 18 | **0** |

A footprint whose median size is **0** while the decision reaches a median of 57
shapes, 18 of which no matched context ever contained, is not a measurement of
"this decision changes nothing". It is a measurement of a corner of the corpus.
The matched-context filter is a near-duplicate-profile filter, so the contexts
it finds cluster in the low-entropy region (empty lists, early returns); the
gate's snapshot is chosen by `pick_snapshot_with` for recording both members,
not for lying in that region. **The footprint is measured in the corner and
applied everywhere.**

### 4.3 The other systematic hole — the co-evaluated fallback

`project_confinement` falls back to `infer_footprints_coevaluated` for every
decision with no exact context ("GATES ARE MEASURABLE", 2026-09-11). Under the
fallback, decisions evaluated in only one of the two runs are *not matched on* —
"they ARE the footprint". That is right for a gate's own downstream and wrong as
a general licence: everything the two runs happen to share is subtracted out.

| | pairs probed | PASS | FAIL | pass rate |
|---|---|---|---|---|
| both members have an exact matched context | 40 | 35 | 5 | **87.5 %** |
| ≥ 1 member fallback-only | 152 | 64 | 88 | **42 %** |

Of the 93 FAILs, **88 (95 %)** have at least one fallback-only member; 23 have
two. Of the 702 declared pairs across the two endpoints, **291 (41 %)** have at
least one.

---

## 5. The proposed change to `src/concolic_engine/coverage.py` — NOT implemented

Three changes, in increasing cost. (1) and (2) are corrections: they restore the
semantics §16c already states. (3) is a policy knob whose price is
endpoint-dependent.

### C1 — TRACE-CURRENCY PRECONDITION (a check, no parameter)

§16c precondition (3) is "a trace layer exists". It must become "a trace layer in
`call_shape`'s currency exists". In `CoverageChecker._check` (step 1, where
`shape_id` is built), after interning: if **no** shape in the whole corpus has a
non-empty `note` *and* no shape has a non-empty arg tuple, the trace layer has
been flattened to target names. Set `confinement_provisional = True`, license
nothing, and name it in `summary()` — exactly as an incomplete tree already
does. New field `confinement_currency: str` ∈ `{"call_shape", "target_only"}`.

Falsifier: the corpus's own dumps carry notes; a pass whose `Run` objects do not
is a loader defect, and this check is the tripwire that says so.

Cost: zero (one pass over the interned shape table). Effect today: notifications
and comments_index license **0** pairs until their `fix_len_names` stops popping
`note`/`args`; posts_show is unaffected.

### C2 — SPAN-CONSERVATIVE FOOTPRINTS (the actual fix)

In `infer_footprints`, alongside the existing per-bucket accumulation, keep

```
reach |= prof_union[i]                        # every single-sided profile of D
span  |= prof_union[it] | prof_union[if_]     # only profiles in a matched context
```

and return `fp[d] = m | (reach & ~span)`.

The rule in words: *a shape the matched contexts never contained is UNKNOWN, and
unknown belongs in the footprint.* Today the code reads "not observed to toggle"
as "not D's"; the only sound reading of "not observed at all" is "possibly D's",
and since disjointness is what a licence is refused on, unknown must go **in**.
Same accumulation in `infer_footprints_coevaluated`, where the matched set is
`M` rather than a bucket pair.

Parameter: `footprint_unobserved: str = "attribute"`, with `"withhold"`
reproducing today's behaviour byte-for-byte so the nesting property test can
assert `attribute ⊆ withhold ⊆ §16b`. Monotone: `fp` only grows, so
`restrict_confinement` only loses edges — the same direction as every other
§16c change, and Rule T is not triggered.

Cost: two extra `|=` per bucket. No new pass over the corpus.

### C3 — THE FALLBACK IS NOT A LICENCE (policy)

Add `confine_coevaluated_only: bool = True` to `project_confinement`. With it
`False`, a decision decided only by `infer_footprints_coevaluated` gets
`fp = reach` (confined with nothing) instead of the fallback differential. This
is exactly the "earlier strict (exact keying, gates protected)" reading §16c's
own nesting chain already names, so `False ⊆ True ⊆ §16b` holds by the chain
that is already tested.

### 5.1 Confusion matrix against today's gate verdicts

Positive = "the criterion licenses the pair". TP = licensed and the gate PASSed
it; FP = licensed and the gate FAILed it (a false licence, the thing that must
go to zero); FN = refused although the gate PASSed it (lost demand reduction).
192 probed pairs: 99 PASS, 93 FAIL. Footprints re-measured on the samples of §1;
posts_show has **no gate verdicts at all**, so it cannot appear in the matrix
(§6).

**notifications_index** — 656 declared, 146 probed (68 PASS / 78 FAIL)

| criterion | licensed / 656 | TP | FP | FN | TN | precision | recall |
|---|---|---|---|---|---|---|---|
| A. today (shipped) | 633 | 64 | 78 | 4 | 0 | 0.45 | 0.94 |
| B. C1 only (fine currency) | 552 | 62 | 43 | 6 | 35 | 0.59 | 0.91 |
| F. C1 + C3 | 377 | 28 | 4 | 40 | 74 | 0.88 | 0.41 |
| **I. C1 + C2 + C3** | **147** | **19** | **0** | 49 | 78 | **1.00** | 0.28 |

**comments_index** — 46 declared, all 46 probed (31 PASS / 15 FAIL)

| criterion | licensed / 46 | TP | FP | FN | TN | precision | recall |
|---|---|---|---|---|---|---|---|
| A. today (shipped) | 46 | 31 | 15 | 0 | 0 | 0.67 | 1.00 |
| B. C1 only | 35 | 26 | 9 | 5 | 6 | 0.74 | 0.84 |
| F. C1 + C3 | 8 | 7 | 1 | 24 | 14 | 0.88 | 0.23 |
| **I. C1 + C2 + C3** | **2** | **2** | **0** | 29 | 15 | **1.00** | 0.06 |

**Combined**

| criterion | licensed / 702 | TP | FP | FN | TN | precision | recall |
|---|---|---|---|---|---|---|---|
| A. today | 679 | 95 | **93** | 4 | 0 | 0.51 | 0.96 |
| B. C1 only | 587 | 88 | 52 | 11 | 41 | 0.63 | 0.89 |
| F. C1 + C3 | 385 | 35 | 5 | 64 | 88 | 0.88 | 0.35 |
| **I. C1 + C2 + C3** | **149** | **21** | **0** | 78 | 93 | **1.00** | 0.21 |

**Criterion I made no false licence on either endpoint.** Every one of the 93
pairs the gate refuted, it refuses first — including both criterion-(iv)
removal-shaped pairs, which it catches because their members are fallback-only.

Caveat, in the conservative direction: the notifications footprints here are
measured on 15 % of the corpus, so they are smaller than a full pass would give;
a full pass would enlarge them and license fewer pairs still. The FP column
cannot get worse.

### 5.2 Demand cost — the point of confinement is to remove demand

| endpoint | pairs today | under I | recorded demand effect of confinement |
|---|---|---|---|
| notifications_index | 656 | 147 (−78 %) | §20.2, identical snapshot: §16b remaining **4 695** → §16c **2 020** (−57 %), demand 65 217 → 34 948, sets 1 042 → 1 539 |
| comments_index | 46 | 2 (−96 %) | §2.3 three-way: **off 85 sets / on 80 / on15 79 — `COMPLETE=True; MISSING=0` in all three** |
| posts_show | 2 701 | not measurable here (its gate has never run) | §82.3, one universe: §16b **8.46e13** → strict **2.57e9** → OR-refined **1.39e4**; booked residue now **4 093** |

Read those three rows together, because they say three different things.

* **comments_index — I costs nothing.** The endpoint is `COMPLETE=True,
  MISSING=0` with confinement entirely OFF. Confinement buys 5 demand sets out
  of 85 and 46 licences the gate refuted 15 of. Criterion I's 2 surviving pairs
  are irrelevant either way.
* **notifications_index — I is affordable.** Confinement is worth 2 675
  assignments (57 % of the §16b residue) at 1 153 pairs on the §20.2 corpus.
  I keeps 22 % of the pairs. The pairs→demand map is structural, not linear, so
  the exact re-projection is a coverage pass and was **not** run; but the
  endpoint's §16b residue is 4 695 and its §16e/§16f work has since driven the
  gap-set count to 0, so the fallback is a bounded, drivable amount of demand.
* **posts_show — I would be very expensive, and that is the finding.** Its
  entire confinement gain lives in the fallback: 41 of its 123 decided decisions
  are co-evaluated-only, and those are its gates. C3 reverts it to "earlier
  strict", i.e. somewhere between 2.57e9 and 8.46e13 — **five orders of
  magnitude**. So on posts_show C3 must not be applied blind. C1 costs it
  nothing (its loader is already correct) and C2 is the right instrument there:
  make the gate's own fallback footprint conservative rather than deleting it.

**Recommended sequencing.** C1 and C2 are corrections and should land together;
C3 should be a per-endpoint knob, defaulted OFF (fallback licensed) only where
an endpoint can show its fallback-decided pairs surviving a gate.

---

## 6. Confinement ON or OFF? — and what rests on pairs never probed

| endpoint | confined pairs licensed | probed | PASS | FAIL | **never probed** |
|---|---|---|---|---|---|
| notifications_index | 656 | 146 (22 %) | 68 (44 of them class-reused from a different corpus) | 78 | **510 = 77.7 %** |
| comments_index | 46 | 46 (100 %) | 31 | 15 | **0** |
| posts_show | 2 701 | **0** | — | — | **2 701 = 100 %** |

At the fresh-probe rate on notifications (78/102 = 76.5 % FAIL) the 510 unprobed
pairs project to ≈ 390 further failures. §82.5 already priced posts_show's gate
at 483 289 replays / 40-134 h and did not run it, and §16c is explicit that a
budget which truncates (vi) makes the verdict NOT-TESTABLE and the pair
withdrawn — so a capped run withdraws exactly what it could not probe.

**Should these endpoints run with confinement OFF?**

* **comments_index — yes, and the measurement already exists.** OFF gives
  `COMPLETE=True; NODES=84; MISSING=0; BLOCKING=0` at 85 demand sets against 80
  ON. The endpoint's closure does not need confinement, and running OFF removes
  46 unverifiable licences for 5 demand sets.
* **notifications_index — no, but the ON number must be re-earned.** C20R4
  reached `COMPLETE=True; MISSING=4; BLOCKING=0` with all 656 licensed; the
  C21 gate then FAILed 78 and the summary is `coverage_numbers_stale`,
  `complete: false`. C21 (running, `withdrawn_pairs` fed back) is the right
  answer — but it re-earns the number with 510 pairs still unprobed and, on
  today's inference, expected to fail. Under C1 the endpoint licenses **0** until
  its loader is fixed, which is the honest reading of where it stands.
* **posts_show — the question is not yet answerable, and that is the point.**
  Its residue of 4 093 rests entirely on 2 701 pairs that no probe has ever
  touched. §82.3's own numbers say the three readings are 8.46e13 / 2.57e9 /
  1.39e4: **the confinement layer is worth nine orders of magnitude on this
  endpoint and is 100 % unverified.** Turning it OFF is not an option (8.46e13 is
  not drivable) and leaving it ON is not a claim. C1 + C2 is the only route that
  keeps the layer and makes it defensible without 40-134 h of replays.

**Fraction of each completeness claim resting on unprobed pairs**:
notifications 77.7 % of its licences (its `complete` is already `false`);
comments_index 0 % (and it is complete with confinement off anyway);
posts_show 100 %.

---

## 7. Artefacts

```
reports/diaspora/tools/_conf_precision_sample.py    footprints + ctxn, coarse vs fine
reports/diaspora/tools/_conf_precision_pairs.py     + pair licence (strict + OR) both currencies
reports/diaspora/tools/_conf_precision_span.py      reach / span / blind, fp and fp|blind masks
```

All three are read-only, take `--batch --snapshot --n --out`, write only where
`--out` points, and were run under
`systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=2G`.
Longest run 106 s, peak well under the cap. `src/`, every endpoint state file
and the running confinement gate, notifications C21 pass and posts_show round
were untouched.

---

# §8 — ACTED ON (2026-09-13 21:26 – 2026-09-14 01:14)

§0-§7 were a measurement and a proposal. §8 is what was implemented, what it
measured, and the two places the proposal did not survive contact with the
engine.

## 8.1 C1 — the currency, measured on the endpoints' own loaders

`tools/_c1_currency_cost.py` imports the endpoint's `coverage_report` and runs
its own `canonicalize_ordinals` / `fix_len_names` / `apply_len_bounds` /
`share_run_objects` chain, so these are the loader's numbers.

| endpoint | dumps | mode | peak RSS | load | distinct `call_shape`s |
|---|---|---|---|---|---|
| comments_index | 26 528 | today | 1 413 MB | 177 s | 13 |
| comments_index | 26 528 | **keep** | **1 451 MB (+2.7 %)** | 181 s | **22** |
| comments_index | 26 528 | digest | 1 431 MB (+1.3 %) | 182 s | 22 (same SET) |
| notifications_index | 132 524 | today | 3 632 MB | 1 526 s | 21 |
| notifications_index | 132 524 | **keep** | **4 299 MB (+18.4 %)** | 1 573 s | **91** |

`keep` reproduces the gate's shape count EXACTLY on both endpoints — 22 and
**91** — which is §2's table read the other way round. At 4.3 GB inside a
32 G cage full retention is affordable, so the digest is not needed; it is
measured anyway and does reproduce the same shape SET, but it is not a general
currency fix (a HASH would break `confinement_to_dict()`'s `shape_str`
handshake with the gate, and the one safe digest — the note's `call_shape`
normal form — drops the bind text `apply_aliases` rewrites).

**Landed in `comments_index` only** (`tools/_c1_currency_patch.md` carries the
two-line diff and the status of the other two). `notifications_index`'s copy
was the script its C21 pass was executing; `conversations_index` is a closed
endpoint outside this work's scope and re-running it was not in budget. For a
census that cannot wait, `tools/confinement_census.py` now takes
`CONF_KEEP_NOTES=1`, which wraps the batch's loader instead of editing it.

## 8.2 C2 and C3 in `src/` — both default OFF

`coverage.py` (one edit, 21:26; blake2b-128 `db740be0…`):

* `infer_footprints` / `infer_footprints_coevaluated` take
  `unobserved="withhold"|"attribute"` plus optional `reach_out` / `span_out`.
  `reach` and `span` are accumulated ONLY when asked for, so the default path
  is unchanged in cost as well as in result.
* `project_confinement` takes `footprint_unobserved=` and
  `confine_coevaluated_only=`.
* `CoverageChecker` takes `confinement_span_union=False` (C2) and
  `confinement_fallback_licence=True` (C3), both folded into the step-6
  checkpoint `params` digest CONDITIONALLY — a default pass keeps the digest
  it has always had, so no checkpoint written before today is invalidated by
  the knobs (the `foreclosure_subconjunctions` precedent).

Tests: `src/test_confinement_span.py` (7 new) — the span unit on masks and on
the co-evaluated helper, a corpus where a blind shape flips the verdict, the
C3 case, the defaults-are-today check, the checkpoint-key check, and the
nesting property on 60 random corpora (footprints only grow, licences only
shrink, every finer-rule missing cube contained in a coarser-rule one,
finer-complete ⇒ coarser-complete). Whole `src/` suite: **328 passed**.

**Endpoint-scale byte-identity, not just unit tests.** comments_index re-run
with its SHIPPED configuration under the new engine, both flags unset:
18 non-completion summary keys compared, **NONE differing** — `demand_sets`
79, `assumptions` 4 213, `confined_pairs` 31, `withdrawn` 15, all identical
(`comments_index/_RESTORED_20260913.md` §4.2).

## 8.3 Where the proposal did not survive contact — C3 as written is inert

§5's C3 says a fallback-decided decision "gets `fp = reach` (confined with
nothing)". Implemented literally (`confinement_fallback_licence=False`) it
changes the licensed set by **ZERO pairs** on comments_index (35 → 35 under
C1, 30 → 30 under C1+C2) and by 4 on notifications. The reason is
OR-SHARING: on these endpoints almost every licence is a `classify_cells`
2x2 licence, not a disjointness licence (under C1+C2, notifications licenses
s0/o96 — *none* strictly), and a bigger footprint only means more shapes that
must have a benign table, which they do.

What §5.1's table actually prices is the STRICTER reading of the same
sentence — **a pair with a fallback-only member is refused outright** — and
that is the engine's EXISTING `confinement_keying="exact"`: a decision with no
exact context stays UNDECIDABLE, so it enters no pair and `infer_pair_tables`
never sees it. Verified equivalent on both endpoints' full pair sets: "refuse"
and `keying="exact"` license the IDENTICAL sets (comments 8 under C1+C3 and 3
under C1+C2+C3; notifications 32 and 27). **So C3 needs no new engine knob —
it is `confinement_keying="exact"`**, which is also what §5 itself calls it
("the earlier strict (exact keying, gates protected) reading").

## 8.4 The four-way confusion matrix, re-measured (`tools/_conf_precision_matrix.py`)

Same corpora and seed as §1 (notifications 20 000 of 132 524, comments_index
all 26 528). Licensing is the ENGINE's own — `infer_footprints`,
`infer_footprints_coevaluated`, the strict counterexample search,
`infer_pair_tables` + `classify_cells` — called with the knobs
`project_confinement` now takes.

**notifications_index** — 146 probed (68 PASS / 78 FAIL)

| criterion | licensed/146 | TP | FP | FN | TN | prec | rec | §5.1 |
|---|---|---|---|---|---|---|---|---|
| A today | 142 | 64 | 78 | 4 | 0 | 0.451 | 0.94 | matches |
| B C1 | 105 | 62 | 43 | 6 | 35 | 0.590 | 0.91 | matches |
| C C1+C2 | 96 | 60 | **36** | 8 | 42 | 0.625 | 0.88 | new row |
| F C1+C3 | 32 | 28 | 4 | 40 | 74 | 0.875 | 0.41 | matches |
| I C1+C2+C3 | 27 | 26 | **1** | 42 | 77 | 0.963 | 0.38 | §5.1 said 0 FP |

**comments_index** — 46 probed (31 PASS / 15 FAIL)

| criterion | licensed/46 | TP | FP | FN | TN | prec | rec | §5.1 |
|---|---|---|---|---|---|---|---|---|
| A today | 46 | 31 | 15 | 0 | 0 | 0.674 | 1.00 | matches |
| B C1 | 35 | 26 | 9 | 5 | 6 | 0.743 | 0.84 | matches |
| C C1+C2 | 30 | 22 | **8** | 9 | 7 | 0.733 | 0.71 | new row |
| F C1+C3 | 8 | 7 | 1 | 24 | 14 | 0.875 | 0.23 | matches |
| I C1+C2+C3 | 3 | 3 | **0** | 28 | 15 | 1.000 | 0.10 | §5.1 said 2 |

**Combined, 192 probed pairs (99 PASS / 93 FAIL)**

| criterion | licensed | TP | FP | FN | TN | precision | recall |
|---|---|---|---|---|---|---|---|
| A today | 188 | 95 | **93** | 4 | 0 | 0.505 | 0.96 |
| B C1 | 140 | 88 | 52 | 11 | 41 | 0.629 | 0.89 |
| C C1+C2 | 126 | 82 | **44** | 17 | 49 | 0.651 | 0.83 |
| F C1+C3 | 40 | 35 | 5 | 64 | 88 | 0.875 | 0.35 |
| **I C1+C2+C3** | 30 | 29 | **1** | 70 | 92 | **0.967** | 0.29 |

Rows A, B and F reproduce §5.1 to the unit. **Row I does not: one false
licence survives, not zero.** It is
`FinderMethods.exists?_1_exists == True` × `FinderMethods.find_by_1_person_
profile_disp_dlink_is_post == True` on notifications, and it is an OR-SHARING
licence (row I is s0/o27 there — every surviving licence comes from the 2x2,
none from disjointness). §5.1's zero was measured without the engine's
`classify_cells` licence in the loop. With `confinement_or_sharing=False` as
well, notifications licenses 0 of 146 and comments 1 of 46: precision 1.00 at
recall 0.01, i.e. the layer is gone rather than repaired.

**And the bar the brief set for C1+C2 alone is NOT met**: it still makes **44
false licences** (36 + 8). They are not exotic — on notifications 5 of them
are `CollectionProxy.records` × `Relation.to_ary(notifications …)` and 12 more
involve `devise_user_first`; on comments they are the `ci_*_first` × `devise_
user_first` family and the `Relation.to_a` row-attribute family. C1+C2 is a
correction worth landing; it is not on its own a defensible licence.

## 8.5 Demand cost per endpoint

Pairs licensed over EVERY co-evaluated decided pair on the same samples
(`--all-pairs`), and, for comments_index, the DEMAND SETS an actual coverage
pass produced (`COMPLETE=True; MISSING=0` in every row — the endpoint is
complete under all of them, so remaining assignments are 0 throughout):

| criterion | comments pairs / 2 611 | comments demand sets | notifications pairs / 23 762 |
|---|---|---|---|
| §16b (confinement off) | 0 | **85** | 0 |
| A today (coarse) | 1 555 | 80 (79 with the 15 withdrawals) | 15 214 |
| B C1 | 1 354 (−13 %) | 77 | 11 585 (−24 %) |
| C C1+C2 | 971 (−38 %) | 76 | 6 575 (−57 %) |
| F C1+C3 | 419 (−73 %) | 86 | 5 577 (−63 %) |
| I C1+C2+C3 | 145 (−91 %) | 86 | 2 274 (−85 %) |

(86 > 85 is not more demand: confinement SPLITS a set, so three confined pairs
turn one set into two smaller ones. The assignment count is what nests, and it
is 0 remaining in every row.)

* **comments_index** — measured end to end, and free either way. See §8.6.
* **notifications_index** — the endpoint declared 656 pairs (the subset lying
  inside a demand set). Scaling the sample's pair ratios, C1+C2 keeps ≈ 283 of
  them and C1+C2+C3 ≈ 98 — the same order as §5.2's estimate of 147. The
  assignment-level re-projection is a full coverage pass on 132 524 dumps and
  was **NOT run**: that endpoint's C21 campaign owns it, its own C21R1 pass
  finished at 21:23 with `COMPLETE=False; MISSING=11; BLOCKING=7`, and under
  C1 its footprints change currency, so the number has to be re-earned by that
  campaign rather than estimated here. Its loader was not edited for the same
  reason.
* **posts_show** — no new measurement. C1 costs it nothing (its loader already
  keeps `note`/`args`; 69 shapes in both currencies). C2 is the instrument
  §5.2 recommends for it and is now available. C3 remains the five-orders-of-
  magnitude risk and stays OFF: `confinement_keying` is untouched there. Its
  2 701 pairs are still 100 % unprobed, and its P26 gate — which was running
  throughout this work and was sampled before and during every stage, never
  below 0.67 probes/s in a 2-minute sample and 1.07 over a 10-minute one — is
  what will change that.

## 8.6 comments_index runs with confinement OFF

Full record in `comments_index/_RESTORED_20260913.md` §4.

```
  before (shipped)   COMPLETE=True;NODES=84;MISSING=0;BLOCKING=0;PCS=928746
                     DEMAND_SETS=79   confined_pairs=31  withdrawn=15
                     OVERALL_COMPLETE=True;COMPLETION=True
                     assumptions 4 213 = 4 182 Independence + 31 Confinement

  after  (CONFINEMENT=0)
                     COMPLETE=True;NODES=84;MISSING=0;BLOCKING=0;PCS=928746
                     DEMAND_SETS=85   confined_pairs=0   withdrawn=0
                     OVERALL_COMPLETE=True;COMPLETION=True
                     assumptions 4 182 = the count REPORT.md recorded at closure
                     ASSUMPTIONS green: declared 4182, distinct_tested 3648,
                     PASS 3648 / FAIL 0, confinement_tested 0
                     21 PASS / 11 PROTOCOL / 0 NO-TEST, BLOCKING (none)
```

Two summary keys move and no others: `demand_sets` 79 → 85 and the 31
inferred `ConfinementAssumption` entries. The gate was re-run from a FRESH
probe checkpoint (4 182 probes, 1 h 23 m), so no verdict rests on a probe run
under a different declared set. `POLICY_HEADER.txt` and the shipped
`queries_from_runs/comments_index.sql` header now say the endpoint relies on
§16c for nothing.
