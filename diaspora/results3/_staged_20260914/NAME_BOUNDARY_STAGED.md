# STAGED name-boundary adoptions — 2026-09-14

Helper: `src/concolic_engine/names.py` (`NameSpace`, `to_checker`, `to_runtime`,
`keys_for`, `resolve`, `audit`). Tests: `src/test_names.py` (30).

Everything below is a call site that HAS FAILED or WOULD fail on spelling, but
sits in a file a live campaign is executing. NOT APPLIED. Apply after the
named job finishes, or hand to the owning agent.

---

## BATCH MANIFEST — what lands together in the ONE `assumption_checker.py` edit

> **LANDED 2026-09-14 09:5x, as ONE edit, on coordinator's instruction.**
> The posts_show gate finished on its own at 08:40:56 (1,363 classes:
> PASS 785, FAIL 274, ERROR 0, NOT-TESTABLE 243, NOT-COMPARABLE 61), so the
> bank it was protecting no longer existed.
> Pre-edit backup: `_bak_assumption_checker_pre_nameboundary_20260914.py`
> (md5 `2b55066358604fe74f3a1bee6c6ca87f`, the base the §16g patch names).
> Post-edit md5: see `_MERGE_20260914.md`. Suite 385 -> **391 green**.
> Sections A, G and the §16g diff below are now HISTORY, not instructions.
> Section H (`producers`) remains NOT implemented.

| # | change | section | status |
|---|---|---|---|
| 1 | name-boundary sites: `pick_snapshot` l.668, `flipped_seeds` l.1355, l.2283/2286 asymmetry, `_load_dump_uncached` l.502-513 tripwire | A.1, A.2, A.3, A.6 | staged, spec'd |
| 2 | `seeds_as_written(sd)` at the three unadopted probe-seed sites (l.1509, 2146, 2199, 2307) | A.4 | staged, spec'd |
| 3 | **`canonicalize = _canon_key()` in the ProbeCache header** — closes a SOUNDNESS hole, not an efficiency one | **G** | **staged, spec'd, IN the batch** |
| 4 | the incremental-index agent's changes | — | owned by that agent |
| — | `producers` / call-graph probe key | H | **design only, NOT implemented** |

Reading order for whoever merges: **E** (why it must be one edit, with the
arithmetic), then **G** (the soundness fix and its two-direction acceptance
test), then **A** (the name-boundary sites, noting the withdrawn scope claim
at the top).

---

## A. `src/end_to_end_completion_checker/assumption/assumption_checker.py`

**BLOCKED TWICE.** (1) pid 1752703 is executing it right now — the posts_show
P26 confinement gate, ~2-3 h left, must never be stopped. (2) another agent is
making its corpus index incremental. **Announce to Bali before any edit; do not
apply directly.**

Root cause: `posts_show/gate_canon.py::canonicalize_for_gate` calls
`fix_len_names(dump)`, which round-trips the WHOLE dump through
`json.dumps`/`json.loads` and therefore renames `concolic_seeds` KEYS too.
Verified: `len(SYM_RESULT_..._records_9_rows)` -> `SYM_LEN_SYM_RESULT_..._records_9_rows`,
with zero `len(` keys left. Meanwhile `expr_dimension()` (l.868-876)
deliberately emits the RUNTIME spelling `len(X)`. So the checker asks in one
spelling and the index answers in the other.

> **SCOPE CORRECTION, 2026-09-14 — read this before re-raising the alarm.**
> An earlier draft of this file said "every length dimension is unprobeable".
> That was measured against the wrong entry point and is WITHDRAWN. Items 1
> and 2 below are real defects but **neither is on the `--declared`
> (confinement gate) path**, which is what the P26/P30 gates run. The
> measurement that settled it is in item 6. Do not stop a running gate over
> items 1-3.

1. **l.668 `pick_snapshot`** — `if dimension in seeds:`
   `dimension` = `len(<canonical>_rows)`; `seeds` comes from `corpus_index`
   rows (`_index_row` l.424 reads `d["concolic_seeds"]` AFTER `_CANON_FN`), so
   `SYM_LEN_<ordinal>_rows`. Double mismatch: spelling AND ordinal/canonical.
   Falsy -> caller at l.2696 prints `PROBE: SKIP — no dump seeds this
   dimension` and `continue`s.
   **SCOPE: the CLI `--assumptions` path ONLY** (`main()`, l.2680-2796).
   `_test_confinement` uses **`pick_snapshot_with`** (l.1316), whose contract
   is explicitly *"dims need not be seeded — unseeded ones are inferred from
   the recorded PC"*. So this cannot fire on a `--declared` run, and the
   `PROBE: SKIP` line is unreachable there.
   Patch: `NameSpace(seeds, name="index row seeds", alias_map=row_alias_map).resolve(dimension)`.

2. **l.1355 `flipped_seeds`** — `if rdim in seeds:`
   `rdim = _runtime_key(sd, dim)` maps canonical->ordinal correctly but NOT
   `SYM_LEN_`->`len(`, so it asks `len(<ordinal>_rows)` of a `SYM_LEN_`-keyed
   dict. Falsy -> `return None` -> callers at 1654, 1836-7, 2078, 2148-9,
   2199 emit `NOT-TESTABLE: cannot infer a flip value from the recorded PC`.
   **SCOPE: reachable only when `flip_for(sd, expr)` returns None**, because
   the seed lookup is the FALLBACK for inferring a flip value — when
   `flip_for` succeeds (it reads the recorded PC, not the seed dict) the
   branch is skipped entirely. Measured on the 27 distinct declared LEN exprs
   of `_p26_gate_classes.json` across 40 real dumps through `gate_canon`:
   **21/21 inferred a value, 0 returned None.** Unreachable in practice on
   this endpoint.
   Patch: `keys_for(rdim)` / `resolve(rdim)`.

3. **l.2283 vs l.2286, asymmetric normalisation inside one function**
   ```python
   low, high = (0, None) if dim.startswith("len(") else (None, None)   # runtime spelling
   ...
       if sv.get("name") == dim:                                       # post-hook spelling
   ```
   Whichever spelling `dim` has, exactly one half misses: `SYM_LEN_X` loses the
   implicit `low=0`; `len(X)` loses the dump's declared `low`/`high`.
   Both misses are CONSERVATIVE (extra probing, no false PASS) — low severity.
   Patch: `to_runtime(dim).startswith("len(")` and
   `same_variable(sv.get("name"), dim)`.

4. **Collateral, same boundary, not a dict miss. THIS is the item that
   actually touches the gate.** Probe seed dicts are built
   as `seeds = dict(sd.get("concolic_seeds") or {})` at l.1509, 2146, 2199,
   2307 — from the LOADED (post-hook) dump, so probes are launched with
   `SYM_LEN_`-keyed length seeds the Ruby runtime never reads and the
   snapshot's whole length context is lost. `seeds_as_written()` /
   `RAW_SEEDS_KEY` exist for exactly this hazard but are used only at l.1175
   (batch matching). The `realised_value`/`unmet` guards make this surface as
   NOT-TESTABLE rather than a false PASS, so it is self-detecting but
   permanently untestable. Patch: `seeds_as_written(sd)` on all four.

5. **MEASUREMENT, 2026-09-14 — what the defect actually costs the P26 gate.**
   Taken while `posts-p26-gate-v3-20260914` was running, to decide whether to
   stop it. Verdict: **it does not degrade the gate**, and the gate was
   allowed to finish (coordinator's decision).
   * Of 1,363 declared classes (all `type: ConfinementAssumption`; they carry
     no `kind` field, so `a.get("kind","independence")` misreads them),
     **604 (44.3 %)** have a list-length dimension on at least one side (541
     one side, 63 both); **667 of 2,726 dimension slots (24.5 %)**.
   * **`Length(SYM_PARAM_id) < 16` is NOT affected** — `expr_dimension`
     returns `SYM_PARAM_id` for it, not a `len(...)` name. **0 of 65
     `Length(...)` expr slots** produce a len-spelled dimension. The probe
     that is 44 % of all probes is clean.
   * **0 of the 604 are decided on an unprobeable dimension.** The only two
     seed-dict lookups on the `_test_confinement` path are items 1 and 2, and
     both are unreachable there (see the SCOPE notes). Every verdict-bearing
     comparison goes through `outcomes_of` / `_reading_changed`, i.e. through
     `canon()`, which normalizes `SYM_LEN_X` -> `len(X)` on BOTH sides.
     `realised_value` — the `ABSENT` / "unknown is not evidence" path — is
     called at l.2370 only, inside `_test_conjunction_foreclosure`;
     **`_test_confinement` never calls it.**
   * The banked probes are not degraded. Sampled 2,500 records from
     `_p26_achk_probes.ckpt.jsonl` by random seek: `values` keys are
     `SYM_LEN_`-spelled (21,613; zero `len(`), `outcomes` exprs are canon'd
     to `len(` — and the comparison is through `canon()`, so they meet.
     **18 of the 27 declared LEN decisions appear at BOTH polarities** in the
     bank, so the flips land. The 9 frozen ones are all `!= 0` (non-empty)
     association lengths sitting at True.
   * The REAL residual effect, quantified: a post-hook seed dict has **22 of
     211 keys (10.4 %) spelled `SYM_LEN_`**, which the Ruby runtime ignores,
     so a probe loses the snapshot's length CONTEXT. The flip ITSELF still
     lands, because `flipped_seeds` writes at `rdim = _runtime_key(sd, dim)`,
     which is `len(...)`-spelled and live. And a flip that fails to take is
     caught by the test's own clause (iv) — *"a flip that did not take ... is
     NOT-TESTABLE — a dead knob is no evidence either way."*
   * **Therefore the failure mode is FAIL / NOT-COMPARABLE / NOT-TESTABLE,
     never a false PASS.** That is why finishing was safe: only a false PASS
     could corrupt a completeness claim. If the final verdict distribution
     shows NOT-TESTABLE clustered on the 604 length classes (especially those
     9 frozen decisions), that is the context-loss effect surfacing
     conservatively — re-run THOSE classes after patching, not all 1,363.

6. **l.502-513 `_load_dump_uncached`** — `lens` is built with
   `startswith("len(")` and read as `lens.get(f"len({o}_rows)")`. Both sides
   are raw TODAY because this runs BEFORE `_CANON_FN`. It is one reordering
   away from silently producing an all-`None` `_alias_len`. Tripwire only:
   `NameSpace(lens, name="_alias_len source").resolve(...)`.

## B. `reports/diaspora/results3/posts_show/_p31_construct.py`, `_p31_gapdiag.py`, `_p31_basecompat.py`

Campaign P32 (light phase) owns this script family; `run_dse.rb` is live.
These sites are **clean today** (`idx["lens"]` keys and the pin names are both
`SYM_LEN_<canonical>_rows`), so this is a TRIPWIRE, not a fix — zero behaviour
change now, loud if the spelling ever drifts:

- `_p31_construct.py` l.596 `j = LIDX.get(L)` -> `pin_unminted.append(L)`
- `_p31_construct.py` l.813 `_pins_ok`  -> `continue  # unminted anywhere: unverifiable`
- `_p31_construct.py` l.823 `_pins_bad` -> `L + " (unminted in the corpus)"`
- `_p31_gapdiag.py` l.33/64, `_p31_basecompat.py` l.58 — same `LIDX.get`.

Patch (same in all four): build once after `idx` is loaded
```python
LIDX_NS = NameSpace(LIDX, name='index lens table (LIDX)')
```
and replace every `LIDX.get(L)` with `LIDX_NS.get(L)`. `get` RAISES only when
the table holds the same variable under another spelling; a genuinely unminted
length still returns `None` and still reports "unminted", unchanged. This is
the class-D site: the "unminted" test dropped a variable the corpus mints in
68 % of runs and that was routed to Bali as a `src/`-inference question.

## C. `reports/diaspora/results3/notifications_index/coverage_report.py` and `_c23_coverage_report.py`

pids 1825328 (C24R2) and 1826450 (C23 C1) are executing these. No confirmed
defect found in them; listed only so the next editor knows they were skipped
deliberately, not audited away.

## D. `reports/diaspora/results3/notifications_index/_c24_construct.py`

Modified 04:35 today, adjacent to the live C24 round. `seedkeys()` l.423
returns `[]` with **no `or outs` fallback and no counter** (l.461-470: the
variable is not written and `wrote` is not incremented, and `nolad` does not
cover it). Simulated over the 24 member vars of `_cov_C20_C20R1.json`: 24/24
resolve, so no live miss — an observability regression, not a measured defect.
Patch when the round ends: `NameSpace(s, alias_map=...).keys_for(k)` plus a
`nunres` counter, matching `_c13_construct.py:320-322`.

---

## E. LANDING RULE — `assumption_checker.py` changes go in ONE batched edit

**Coordinator's ruling, 2026-09-14. Do not land section A independently.**

Every edit to `assumption_checker.py` — a comment, a print, a docstring —
costs a full rebuild of BOTH checkpoints, because each header pins the
module's source hash:

* `ProbeCache.__init__` l.1122: `{"engine": _ckpt.source_hash(sys.modules[__name__]), ...}`
* `_phase_keys` l.225: `{"engine": _ckpt.source_hash(<this module>, <concolic_engine.assumptions>), ...}`

Measured on the P26 v3 gate (232,419-dump corpus, 1,363 classes):

| | count | cost |
|---|---|---|
| probes needed | 111,241 | — |
| banked at 06:58 | 88,859 | — |
| **surviving any patched restart** | **0 (0.0 %)** | — |
| remaining, unpatched | 22,382 | ~2.0 h at the observed 3.08 probes/s |
| full redo, patched | 111,241 | **10.0 h** at 3.08/s (11.6 h at 2.667/s) |

Plus a full re-index of 232,523 units (the 16 GB-RSS build) and a ~16 min
derive pass. **~2 h to finish vs ~11-13 h to redo.**

So: batch section A with the incremental-index agent's changes and land them
together, once. The coordinator sequences the merge — do not land yours
independently, and wait to be told.

## F. WHY THE TWO CHANGES DO NOT COMPOSE

The incremental-index work makes a future INDEX rebuild cheap. It does
nothing for the PROBE bank, which stays all-or-nothing on the module hash. So
after any patched restart the index is nearly free and the 111 k probes are
not — the saving does not compose, and the probe bank remains the whole cost
of a gate restart. That is the next structural saving worth taking.

**The probe key is simultaneously too STRICT and too LOOSE.** Both halves are
worth fixing, and the loose half is a soundness bug, not just a cost one.

* **Too strict.** `engine` hashes the ENTIRE module, so editing
  `_test_confinement`, `pick_snapshot`, a print, or a docstring discards
  111 k probes that those functions do not produce. A probe record is
  `{trace, trace_b, amap, exprs, outcomes, values}` — the output of replaying
  the runner at one `(scenario, seeds)` and reading the dump back. Its
  PRODUCERS are only: the runner invocation, `access_trace` /
  `access_trace_binds` (hence `call_shape` / `shape_str` in
  `concolic_engine.assumptions`), `_outcomes_of_dump` + `canon`, the
  `values` assembly, and the load hook. Everything else in the module
  CONSUMES probes.

* **Too loose — and this one can hand back a wrong answer.** The ProbeCache
  header carries `cfg`, `engine`, `keep`, `phase` and **no `canonicalize`
  key**, unlike `_phase_keys`, which includes `_canon_key()`. `cfg` digests
  `assumption_manifest.json`, which names the hook as the STRING
  `"gate_canon:canonicalize_for_gate"` — not its source. **So editing
  `gate_canon.py` or `coverage_report.py`'s `fix_len_names` /
  `canonicalize_ordinals` changes every record's `amap`, its `values`
  spellings and its `outcomes` — and the stale bank is silently reused.**
  This is the name-boundary family again, one level up: the exact fix
  contemplated in section A, if it were ever made on the BATCH side instead
  of the checker side, would be silently ignored by the probe cache. The
  index checkpoint gets this right; the probe cache does not.

The two halves are split below: **G is IN the batch** (coordinator,
2026-09-14 — cheap, closes a soundness hole, independent of the strictness
work). **H is design only and stays unimplemented.**

## G. IN THE BATCH — `canonicalize = _canon_key()` in the ProbeCache header

`ProbeCache.__init__` l.1122. Add one key, exactly as `_phase_keys` l.225
already does:

```python
self.ckpt = _ckpt.open_checkpoint(
    checkpoint if checkpoint is not None else os.environ.get(CKPT_ENV),
    {"engine": _ckpt.source_hash(sys.modules[__name__]),
     "phase": "assumption_checker:ProbeCache",
     "cfg": _ckpt.digest(cfg),
     "canonicalize": _canon_key(),        # <-- ADDED
     "keep": str(bool(keep))})
```

**ORDERING GUARD — the patch depends on an invariant nobody wrote down.**
`_canon_key()` returns the string `"none"` when `_CANON_FN is None` (l.391).
The hook is installed in `main()` at l.2690; `ProbeCache` is constructed at
l.2587 inside `run_declared`, called at l.2710 — so today the hook IS set
first and the key is meaningful. But if anyone ever moves the ProbeCache
construction earlier (warming the cache before the declared set is parsed,
say), the key silently degrades to `"none"`, stays constant across every
hook, and **the hole reopens with the fix apparently in place** — the same
disease, one layer down. So do not rely on the ordering: ASSERT it. At
ProbeCache construction, raise if `cfg.get("canonicalize")` is set while
`_CANON_FN` is None. A guard that fires loudly is the whole point of this
document.

**Expect the bank to be discarded ONCE, by this patch.** Adding a header key
changes the header, so the first run after the merge starts from zero
probes. That is correct and is already priced into section E — the batch
discards the bank anyway.

**ACCEPTANCE TEST — both directions, and both are required.**

1. Same corpus, edit ONLY a print statement in `assumption_checker.py`.
   With the `producers` work NOT done, the bank is still expected to be
   discarded here (`engine` is the whole-module hash) — so this direction
   only becomes meaningful once H lands. Record the result either way.
2. Same corpus, edit `gate_canon.py` (or `coverage_report.py`'s
   `fix_len_names` / `canonicalize_ordinals`). **The bank MUST be
   DISCARDED.** Before this patch it is silently REUSED — that is the bug.
   This is the direction that certifies G.

**A key that only ever keeps the bank is the loose failure wearing a new
hash.** Demonstrate both directions or the fix is not certified.

## H. DESIGN ONLY — NOT IMPLEMENTED — the `producers` (strictness) half

Replace `engine` with a source hash over the probe-PRODUCING closure only,
not the whole module. The producers are: the runner invocation,
`access_trace` / `access_trace_binds` (hence `call_shape` / `shape_str` in
`concolic_engine.assumptions`), `_outcomes_of_dump` + `canon`, the `values`
assembly, and the load hook. Everything else in the module CONSUMES probes.

**Derive the set from the call graph, or do not do it at all.** A
hand-maintained list of producers relies on the next author remembering to
extend it — which is precisely the discipline that failed four times in one
night for the name boundary, and the reason `concolic_engine.names` exists.
Walk the call graph from the record-assembly function and hash every function
reachable inside the two modules, so a new producer cannot silently escape
the key.

Expected effect: a verdict-logic or presentation edit — the common case, and
what section A mostly is — stops invalidating the bank, so a patched restart
costs the derive pass plus whatever probes genuinely changed, instead of
10-12 h. Until then, section E's arithmetic stands and every
`assumption_checker.py` edit costs a full rebuild.
