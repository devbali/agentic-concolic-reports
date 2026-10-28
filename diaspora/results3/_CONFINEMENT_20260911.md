# CONFINEMENT (DISCIPLINE §16c), 2026-09-11 — strict, gated end to end

> The brief called this `_SEPARABLE_EFFECTS_20260911.md`. The owner renamed the
> property mid-task to **CONFINEMENT** (per-decision "footprint", "undecidable"
> for no matched context; gate type `ConfinementAssumption`; §16c). Later the
> same day the owner refined it to be **STRICT**, asked that the gate
> **actively try to falsify it** with a PASS resting on the gate's **own
> probes**, and — from the posts_show census — that **GATES be measurable**
> (the owner's original case, which the first two rounds excluded by
> construction). All four rounds are in. No
> worktree or branch was ever created; all work is in the live `src/`, on top
> of the pre-existing uncommitted changes, nothing reverted, nothing
> committed. No driving, no JRuby, no live-corpus passes except one read-only
> identity re-run of people_stream; everything caged at 1 GB.

## 1. The property, as it stands

**Footprint.** For a tracked decision `D`, `footprint(D)` = the target-call
SHAPES (`concolic_engine.assumptions.call_shape`: target, note with binds and
string literals wildcarded, argument shape — the gate's access-trace currency,
now one shared function) whose PRESENCE differs between two runs that MATCH
on every other evaluated expression (same evaluated set, same outcomes, same
both-sided set) and differ only in `D`. A run recording both sides of `D` is
in none of its contexts. DECIDED iff ≥1 matched context; else UNDECIDABLE,
never "empty".

**Strict confinement (owner's refinement).** `D` is CONFINED iff decided AND
every shape in its footprint is strictly ONE-SIDED across the ENTIRE corpus:
the shape is present ⇒ `D` took its enabling side; never in a run where `D`
took the other side, nor in a run recording `D` both ways. Runs where `D` is
UNEVALUATED count neither way: `D` has no outcome there, the shape is enabled
by whatever gated `D` away, and that leaf is foreclosure's business, demanded
on its own. Per shape, all-or-nothing: one two-sided shape disqualifies the
decision; the shape is never dropped to keep the rest.

**Confined pair.** Both confined, footprints disjoint. Inside a demand set a
confined pair needs each outcome observed once (under any compatible prefix),
not the cross product.

**Soundness / falsifier.** `A=x ∧ B=y ⇒ Z` puts `Z` in both footprints, so
disjointness refutes it. Strictness adds "only possible when the upstream thing
is one way", and its falsifier is a COUNTEREXAMPLE SEARCH at load, every pass:
one run anywhere with the decision on its non-enabling side and a footprint
shape present disqualifies the decision (run and shape named).

**What strict EXCLUDES, and why it is conservative.** Under the weak reading
("toggles in SOME matched context") a shape reachable on `A`'s other arm via
an unrelated `C` still counted as `A`'s, and `A × B` could collapse although
`Z` did not need `A`. Strict says a shape the other arm can still issue is not
the decision's to control, and demands the product. Direction, stated
carefully: strict is a SUBSET relation on PAIRS (strict pairs ⊆ weak pairs)
and hence a SUPERSET on DEMAND:

    weak-confined ⊆ STRICT-confined ⊆ foreclosure-aware (§16b) ⊆ set-level (§16) ⊆ complete-graph

The weak reading survives only as `confinement_strict=False`, for the nesting
test; batches never use it.

**Preconditions, CHECKED.** (1) tree completeness → PROVISIONAL otherwise;
(2) matched contexts for both members; (3) a trace layer — a corpus with no
recorded target call makes every decision undecidable (what keeps the engine's
old trace-less fixtures byte-identical).

**Gates are measurable (round 4).** A gate has no exact matched context (its
flip changes which decisions are evaluated), and the earlier rule kept every
gate in every part — so posts_show's 24 length gates in one set still
multiplied to 2^24 (its 1.33e11). Now a decision with no exact context is
measured under the **co-evaluated keying**: a matched context for `D` = two
runs that agree on every decision evaluated in BOTH (other than `D`) and
differ only in `D`; decisions evaluated in only one of them — `D`'s
downstream, foreclosed on the other side — are not matched on: they ARE the
footprint. A gate's footprint is its downstream's shapes; strictness applies
unchanged; two gates with disjoint downstreams are a confined pair. A
decision that HAS an exact context keeps that (less confounded) measurement;
the fallback only ADDS decided decisions — which is what makes the new
demand nest in the earlier rule. Computed without enumerating pairs: bitsets
over profiles, leave-one-out compatibility products from one prefix/suffix
pass per profile (`infer_footprints_coevaluated`); cost ≈ profiles ×
decisions-per-profile × |trace| big-int ops.

**THE DEMAND RULE, exactly.** For a demand set `S` with its foreclosure
relation `F` (gates first): over ALL members the confinement graph keeps the
edge `{x,y}` unless `(x,y)` is a confined pair. Parts = the maximal cliques
of that graph, each CLOSED under "a part holding `d` holds every gate of `S`
that forecloses `d`" (transitively); each part is judged by §16b on its own
(its pruned tree, its gates first); the demand over `S` is the union over the
parts (subset parts deduplicated). Hence: a confined gate's own downstream
stays with it — the closure keeps the gate in the downstream's part and the
pruned tree demands the downstream only under the gate's enabling side
(foreclosure); two confined gates land in different parts, so the product of
their arms is not demanded, nor the product of their downstreams where those
are confined pairs too (confinement); a member confined with nothing keeps
every edge and holds its part together (conservative default).
`restrict_confinement(..., protect_gates=False, bit=...)`; the earlier rule
survives as `confinement_gates=False` / `confinement_keying="exact"` for the
nesting test.

## 2. Implementation (`src/`, additive; pre-task backups in scratchpad)

| file | change |
|---|---|
| `concolic_engine/assumptions.py` | `call_shape`, `shape_str`. |
| `concolic_engine/coverage.py` | docstring "Confinement" section; step 1 keeps per-profile trace union/intersection AND per-expression per-side shape masks with a first-witness run per (expr, side, shape); `infer_footprints` (exact keying), `infer_footprints_coevaluated` (bitsets over profiles, the gate keying); `project_confinement` — steps 5d as ONE function shared with the census tool (keying fallback, strict counterexample search, per-set projection); `restrict_confinement(group, local, footprint, cap, disqualified, withdrawn, protect_gates, bit)` with the closure rule; `CoverageChecker(confinement=True, confinement_strict=True, prior_footprints=None, withdrawn_pairs=None, confinement_keying="coevaluated", confinement_gates=True)`; `CoverageResult` fields (defaults): `footprints`, `footprints_undecidable`, `footprints_coevaluated`, `confined_decisions`, `confinement_disqualified`, `confined_pairs`, `footprint_sides`, `foreclosing_gates`, `confinement_overlapping`, `confinement_undecidable_pairs`, `confinement_splits`, `confinement_provisional`, `confinement_withdrawn`; `summary()` line + DISQUALIFIED rows; `confinement_to_dict()`; **`assumptions_to_dict()` now appends the inferred pairs** (`"inferred": true`, with footprints, enabling sides, other producers, foreclosing gates). Step 6, `_next_untried_combo`, tree layer, foreclosure: untouched. |
| `concolic_engine/completion.py` | `assumption_check` returns `confinement_tested`, `confinement_withdrawn` (any non-PASS on an inferred pair), `confinement_unverified`; `green` requires no unverified pair; `run_completion` blocks on `assumption FAIL (ConfinementAssumption)` and on `confinement NOT VERIFIED (<verdict>)`; `attach_to_summary` writes `confinement_withdrawn_by_gate` and `coverage_numbers_stale`; `main` prints the `[confinement]` line. |
| `end_to_end_completion_checker/assumption/assumption_checker.py` | `access_trace` → `call_shape` (byte-identical, pinned); `_TRACE_INDEX` (profile digest, shapes, PCs per dump, built in the `corpus_index` pass); `probe_record` gains `outcomes`; `outcomes_of`; `_combined_flip` (X10's lines, shared); `_exhaustive_flip` (vi); `_constructed_route` (vii, Z3 via `concolic_engine.solver`); `_test_confinement` dispatched on `ConfinementAssumption`. Independence test logic unchanged. |
| new tests | `test_confinement.py` (23), `test_confinement_gate.py` (25), `test_confinement_active.py` (8), `test_confinement_e2e.py` (4). |
| `reports/diaspora/tools/confinement_census.py` | deferred pricing (strict; §16b vs §16c census on a DUMP_LIST). |
| `reports/diaspora/docs/DISCIPLINE.md` | §16c, dated, updated for strict / active gate / end-to-end wiring. |

Diff vs the pre-task files (scratchpad backups): `coverage.py` ≈ 600 changed
lines (docstring, helpers, fields), `assumption_checker.py` ≈ 420,
`completion.py` ≈ 40. Last `src/` commit untouched (`3ef8a9e`).

## 3. Tests — results (all caged ≤ 1 GB)

### Layer 1 — engine, `test_confinement.py`: 23/23

(a) confined pair: demanded cubes before `['And(Not((a > 0)), Not((b > 0)))']`
→ after `[]`, `demand_sets 1 → 2`; the serializer carries the pair with
enabling sides/producers/gates and `assumptions_to_dict()` equals it.
(b) jointly-gated shape in both footprints, no collapse. (c) undecidable ≠
empty, 3 undecidable pairs, product kept. (d) both-sided runs excluded from
that decision's contexts. (e) PROVISIONAL on an incomplete tree. (f) 60 random
corpora (disjunctive shape rules): every §16c-missing cube ⊆ a §16b-missing
cube; identical reports where nothing is confined. Gates kept in every part;
cap keeps the set whole; canonical-name keying under `AliasAssumption` (the
posts_show 791 "pending" pairs); trace-less identity; the tripwire.

**Strict — adversarial, planted counterexamples:**
`test_strict_a_shape_reachable_via_an_unrelated_decision_disqualifies` — weak
licensed `(a,b)`; strict disqualifies `a` AND `c` (both produce `z`
two-sidedly), names runs `a-t`/`via-c`, product stays demanded.
`test_strict_one_run_among_thousands_is_enough` — 1 000 runs with `z` only on
`a=T`, one run `the-one` with `z` on `a=F` → disqualified, that run named.
`test_strict_is_per_shape_all_or_nothing` — three one-sided shapes + one
two-sided → not confined, footprint still reports all four; remove the plant
→ confined again. A both-sided run with the shape disqualifies; an unevaluated
run does not. `test_strict_is_nested_in_weak_on_random_corpora` — 60 corpora:
strict pairs ⊆ weak pairs, weak demand ⊆ strict demand ⊆ §16b (39 corpora
with strict pairs, 2 with weak-only pairs; identity where nothing strict).

**Gates measurable — the owner's case:**
(a) `test_two_gates_with_disjoint_downstreams_need_per_gate_demand` — set
`{g,a,c,b}` (g=T drops a, c=T drops b; a → za, b → zb): §16b's exact cube
list `['And(Not(g), Not(c), a, Not(b))', 'And(Not(g), Not(c), Not(a), b)']` →
confined pairs `(a,b),(a,c),(b,g),(c,g)`, overlapping `(a,g),(b,c)` (each
gate with its own downstream), parts `{g,a}`,`{c,b}`, **complete**. The
differentiating corpus — arm combination (g=T,c=T) never walked — the earlier
rule (exact keying, gates protected) demands `And(g, c)`; per-gate demand is
complete. (b) `zboth` only under g=F ∧ c=F → in both gates' footprints, not
confined, the gates' product a part of its own (3 parts), its unwalked leaf
demanded again. (c) `za` reachable with g=T via another route → g
disqualified. (d) same corpus: g, c undecidable under `confinement_keying=
"exact"`, decided under the co-evaluated keying; the helper matched/blocked
directly on profiles. Nesting: `test_gate_confinement_is_nested_in_the_earlier_rule_on_random_corpora`
— 60 corpora (disjunctive shape rules): earlier pairs ⊆ new pairs, every
new-missing cube ⊆ an earlier-missing cube ⊆ a §16b cube, earlier-complete ⇒
new-complete; 23 corpora with new (gate) pairs, 37 identical to the earlier
rule.

### Layer 2 — the gate: `test_confinement_gate.py` 25/25, `test_confinement_active.py` 8/8

`_test_confinement`, PASS iff all of: (i) ΔA ⊆ fp(A); (ii) ΔB ⊆ fp(B);
(iii) `trace(both) == (base − removed_A − removed_B) ∪ added_A ∪ added_B`;
(iv) each single flip leaves the partner evaluated with its base outcome and
the double flip records both flipped (sees removal-shaped dependence, X11);
(v) no footprint shape present in the base survives its decision's flip, in
flip-A/flip-B or flip-both — a flip that leaves the decision UNEVALUATED with
the shape still issued is a ROUTE AROUND it, FAIL; (vi) EXHAUSTIVE FLIP OVER
PROFILES — every distinct outcome profile carrying a footprint shape, one
representative each (richest seeds), flipped and replayed; (vii) an
ADVERSARIAL CONSTRUCTED ROUTE per footprint shape with other producers — the
decision off, each producer on, its foreclosing gates held open, from a base
run or a Z3 model over the base's declared variables; UNSAT recorded as
"no route exists under the inferred structure".

**Own probes, or no verdict.** A truncating budget (`ACHK_CONF_PROFILES`,
default unlimited), a flip that did not take, a route that could not be
constructed or produced no run → NOT-TESTABLE, never PASS. Overlapping
footprints FAIL before any replay is spent. Per-probe isolation and the
results file under `finally` as X10 requires; ERROR counts as failure.

Ground-truth differential: one fixture per criterion violating exactly it →
FAIL naming it; the honest program → PASS with "(vi) A: 2/2 profile(s)
flipped". The X11 case (flip-both ⊂ flip-A) → FAIL (iii)/(iv). The posts_show
27-shared-shape pair → FAIL at disjointness; wrongly licensed → FAIL (i) on 27
shapes. The six negative controls (stub replays, DISJOINT footprints handed
in) → all FAIL on (iv). Active: (vi) catches a shape a SECOND profile still
issues (the single-snapshot part passes it; capped to 1 profile the verdict
is NOT-TESTABLE "truncated (1/2 profiles)"); (vii) catches the A-or-C route
no corpus run walked (passive + (vi) PASS it; with the producer `C` handed in
the constructed replay issues `za` with A off → FAIL); the solver route for a
producer no run recorded (`VAR_D > 5` from the model) → FAIL, and with a gate
`(VAR_D > 3) :: taken` → UNSAT recorded, PASS; a dead flip on one profile →
NOT-TESTABLE; planning enqueues all probes; (e) for a GATE — enabling side
`not_taken`, downstream shape `zd`, another producer `C` no corpus run had on
— (i)-(vi) PASS and the constructed probe (gate on its non-enabling side, C
on) reaches `zd` → FAIL.

**Cost model, per confined DECISION** (shared across its pairs; identical seed
dicts dedupe in `ProbeCache`): 3 composition replays per pair + one flip per
distinct outcome profile carrying a footprint shape (vi) + one constructed
replay per footprint shape with another producer (vii). On posts_show p5 that
is bounded by 31 054 profiles per decision in the worst case; in practice the
profiles carrying a given decision's shapes on its enabling side are a
fraction, and (vii) is ≤ |footprint|. If certification cannot afford (vi) in
full, `ACHK_CONF_PROFILES=N` samples — and the verdict is then NOT-TESTABLE,
which withdraws the pair: the budget decides what the batch can CLAIM, not
what it can quietly pass.

### Layer 3 — end to end, `test_confinement_e2e.py`: 4/4

The real completion flow with a stub runner subprocess speaking `run_probe`'s
protocol (`EXTRA_SEEDS_JSON`, `LABEL_SUFFIX`, dumps drained). Call chain by
file:line:

```
endpoint coverage_report.py: summary["assumptions"] = result.assumptions_to_dict()
                                                  coverage.py  CoverageResult.assumptions_to_dict -> + confinement_to_dict()
completion.attach_to_summary(summary, config)     completion.py:246  declared = summary["assumptions"]
  -> run_completion(config, declared)             completion.py:186
     -> assumption_check(config, declared)        completion.py:98
        writes <batch>/_assumptions_declared.json completion.py:118-121
        runs config["assumption_cmd"]             completion.py:127   = assumption_checker.py <cfg> --declared … --json-out …
          assumption_checker.main -> run_declared -> test_declared -> _test_confinement   (type ConfinementAssumption)
             -> ProbeCache.execute -> run_probe -> subprocess(cfg["runner"]) -> dumps -> probe_record
        reads _assumption_results.json            completion.py:129-135
        confinement_withdrawn / confinement_unverified (any non-PASS on an inferred pair)
     -> blocking += "assumption FAIL (ConfinementAssumption)" / "confinement NOT VERIFIED (…)"   completion.py:213 ff
     -> section["complete"] = not blocking        completion.py:225
  -> summary["complete"] = coverage_complete and section["complete"]                            completion.py:254
  -> summary["confinement_withdrawn_by_gate"], summary["coverage_numbers_stale"]
next pass: CoverageChecker(withdrawn_pairs=summary["completion"]["assumptions"]["confinement_withdrawn"])
```

(a) the inferred pair appears in `summary["assumptions"]` as
`ConfinementAssumption`/`inferred` with **no per-endpoint change**;
(b) `_assumptions_declared.json` equals it and the results row is
`("ConfinementAssumption", "PASS")` with the (vi) counts in its detail;
`completion.complete` and `summary.complete` True; probe dumps drained.
(c) with `PROBE_LEAK=1` (the claim false at replay) the row is FAIL on (v),
`blocking` names it, both `complete` flags are False, the pair is in
`confinement_withdrawn`, and fed back as `withdrawn_pairs` the next pass
licenses nothing (`confined_pairs=()`, product demanded again, "WITHDRAWN" in
`summary()`). (d) the withdrawal is in the summary and printed by
`completion.main` ("[confinement] inferred pairs gated: 1, WITHDRAWN by the
gate: 1 / withdrawn: A x B"). An unverified (NOT-TESTABLE/NOT-COMPARABLE)
inferred pair blocks too.

**What an endpoint must change: nothing** to be gated. Two optional one-liners
for the cross-pass loop, in each `coverage_report.py` where `CoverageChecker(`
is built: pass `withdrawn_pairs=` from the previous summary's
`completion.assumptions.confinement_withdrawn` (so a gate FAIL stays withdrawn
across passes without waiting for the corpus to learn it), and
`prior_footprints=` from the previous `footprints` (the cross-pass tripwire).
Without them the engine still re-infers from the corpus each pass and the
gate still tests and blocks each pass — correctness does not depend on them;
persistence of a withdrawal does. Their `[assumptions]` print line is batch
code and does not show confinement counts; the engine's `summary()` and
`completion.main` do.

### Backwards compatibility

Pre-existing suites, all unchanged and green: `test_coevaluation.py` (19),
`test_symbolic.py`, `test_assumptions.py`, `test_assumption_checker.py` (4),
`test_path_explosion.py`, `test_interceptor.py`, `test_symbolic_func.py`,
`test_query_ops.py`, `py_runtime/test_list_rep.py`, and
`queries_from_runs/test_queries_from_runs.py` 47 passed under pytest
(needs `PYTHONPATH=src` + its venv). Confinement family: 18 + 25 + 7 + 4.

**Read-only identity re-run, people_stream, under the FINAL rule (gates
measurable)** — 2 910 dumps on disk at that moment (its agent reshapes the
corpus continuously); its own load path and unchanged
`coverage_assumptions.py`; nothing written; peak RSS 785 MB:

```
confinement=False: complete=False nodes=37 demand_sets=21 missing=28 tree_missing=0 foreclosures=322 truncated=True  267s
confinement=True : complete=False nodes=37 demand_sets=21 missing=28 tree_missing=0 foreclosures=322 truncated=True  383s
FIELDS DIFFERING between OFF and ON: NONE (byte-identical verdict)
  Confinement (strict): decided 32 (19 by the co-evaluated keying) / confined 6 / disqualified 26 / undecidable 5;
  pairs confined 0, overlapping 1, undecidable 67
  e.g. DISQUALIFIED PeopleController_diaspora_id__1_result: shape ActiveRecord::FinderMethods.take | SELECT "people".* … on both sides
```

19 gates became decided that the exact keying could not see; 26 of the 32
decided decisions are disqualified by the strict search; 6 are confined but
no pair among them is co-evaluated with disjoint footprints — so nothing is
licensed and the verdict is the identity, as the rule requires. The earlier
STRICT-only run (3 288 dumps, gates protected):

```
confinement=False: complete=False nodes=37 demand_sets=28 missing=64 tree_missing=0 foreclosures=293 truncated=True  398s
confinement=True : complete=False nodes=37 demand_sets=28 missing=64 tree_missing=0 foreclosures=293 truncated=True  373s
  Confinement (strict): decided 13 / confined 0 / disqualified 13 / undecidable 24; pairs confined 0
  e.g. DISQUALIFIED take_1_not_found: shape ActiveRecord::Relation.records | SELECT "posts".* … present on both sides (runs anon_json0010…, anon_json0008…)
```

— every verdict field identical there too (all 13 decided decisions
disqualified). And the weak-mode run on 2 520 dumps: 33/20/32, identical.

## 4. Rule T

Every part is a subset of its set closed under the gates that foreclose its
members, so its pruned tree is the restriction of the set's (gates of `S`
outside the part foreclose nothing in it), each of its leaves is the
restriction of a leaf of `S`, a satisfiable leaf of the part extends to a
satisfiable leaf of `S` (a Z3 model determines every expression), and a run
covering the extension covers the restriction (its clause over the part is a
closed prefix under the same gate outcomes). New licences ⊇ earlier licences
(the co-evaluated keying only adds decided decisions; a gate leaving a part
is a cut the earlier rule never made), so every new part is contained in an
earlier part:

    confined-gates ⊆ earlier strict ⊆ §16b ⊆ §16 ⊆ complete-graph

old-complete implies new-complete; a corpus with no confined pair is judged
byte-identically. Verified by the two randomized property tests and the
people_stream identity run. The three closed endpoints were not re-run (no
live-corpus passes from this agent); by the argument they cannot move, and
their next `coverage_report.py` pass re-verifies it. **Rule T is NOT
triggered.**

## 5. Is the gate now as complete as the independence gate — and where is it weaker?

The independence gate: one snapshot, three replays, FAIL on a novel shape
(and blind to removal — X11). The confinement gate: three composition replays
with seven criteria (including the removal-shaped cases the independence
probe cannot see), PLUS a flip on every profile that carries a footprint
shape, PLUS a constructed route per shape with other producers, PLUS the
engine's corpus-wide counterexample search — and a PASS only on complete
own-probe evidence. On the axes the owner named — active, by construction,
not relying on already-run things — it is now stronger than the independence
gate, not weaker.

Where it is still weaker than a proof, stated:

1. **Routes through decisions the corpus never measured.** (vii) constructs
   routes only through OTHER PRODUCERS the corpus decided (footprints holding
   the shape). A producer that is undecidable, or a shape needing TWO other
   decisions jointly on (`Z iff C ∧ D`) when no profile has both on, is not
   constructed. Under tree completeness (vi) covers single-decision routes
   (some profile has `C` on; if it carried `Z` with `A` on, flipping `A`
   there reveals the route); joint routes remain the residual.
2. **One representative per profile.** (vi) replays one run per outcome
   profile; two runs of one profile that differ only in untracked state could
   differ in trace. The engine's footprint uses union AND intersection over
   all runs of a profile, so the corpus side sees this; the replay side does
   not.
3. **Shapes, not binds.** Footprints and probes compare shapes (binds and
   literals wildcarded); a dependence that changes a bind but no shape is
   invisible — the same reading the gate's access trace has always used.
4. **Empty decided footprints** are vacuously strictly confined with every
   other confined decision; the reduction will be largest there, and the gate
   has nothing to flip for them beyond (i)-(v) (no shape to survive).
5. **Snapshot choice for (i)-(v)** is the richest-seed dump; (vi) is what
   removes the dependence on that choice.

## 6. Soundness — my judgement

Sound, in this sense: the demand reduction is licensed only where the corpus
shows disjoint, strictly one-sided footprints on a complete tree; the engine's
own counterexample search refutes it from any single contrary run; the gate
refuses to pass it on anything but its own complete replays; and an
unverified or failed pair withdraws, blocks `complete`, and stays withdrawn
when fed back. The case where it is NOT sound as a claim about the program —
and I name it rather than hide it — is the joint-route residual in §5.1: a
shape produced only when two decisions OTHER than `A` are both on, with `A`
off, when no corpus profile ever had both on and `A` is confined on every
context that exists. No probe here constructs that run. It is exactly the
shape of gap §16b already carries for multi-gate foreclosure (notifications
§13.3: 6.5 % of its residue), and the honest reading is the one §16b gives:
the verdict is a claim at the fixed point, the intermediate numbers are a
lower bound.

## 7. Pricing — deferred

`reports/diaspora/tools/confinement_census.py <batch_dir>` with `DUMP_LIST`
and the batch's own flags: strict footprints on the enumerator's own profiles,
the counterexample search, the projection, and the exact census §16b vs §16c
(decisions decided/confined/disqualified/undecidable; pairs
confined/overlapping/disqualified/undecidable; demanded/covered/remaining
before → after; overlapping examples). Baselines: posts_show p5
`48548318047288 / 482516 / 48548317564772` (1 805 sets, peak 3.3 GB — run under
the batch's cap); notifications `_snapshot_pruned_20260910_192233.txt`
`65 156 / 41 034 / 24 122`. Cross-check, not input: the posts_show census
(raw names, weak XOR footprint) found 54 decided / 57 undecidable and
231 disjoint / 44 overlapping / 667 undecidable (+791 namespace); strict on
canonical names will license fewer pairs than that, never more — people_stream
is the warning: 13 decided, 13 disqualified.

## 8. Loose ends

* `assumption_checker.py:97` `ResourceWarning` (`json.load(open(path))`) is
  pre-existing; not touched.
* `ConfinementAssumption` is a gate type string, not a declarable
  `Assumption` subclass; a declared form is a small, separate Rule-T question.
* Rig verdicts on the six controls and the 27-shape pair are the endpoint
  agent's next gate pass; here they are stub-replay verdicts.

## 9. Round 5 — OR-sharing: measurement first (2026-09-11, later)

**The question.** Gate-aware confinement on posts_show (GC0911 snapshot,
31 394 profiles): §16b `52 145 853 293 867` → §16c `77 660 122 561` remaining
(~670×), sets 1 901 → 6 494, but 6 365 wide sets hold all of it. The census
categories say WHERE it lives: **overlapping 0, disqualified 2 416, undecidable
1 220, confined 430** — under STRICT an OR-shared shape does not "overlap", it
DISQUALIFIES the decision (present with the decision off, via another): 73 of
114 decided decisions carry 30–56 two-sided shapes each. The coordinator's
suspicion: most of that is OR-sharing (the same presenter query fed by several
collections) — not interaction.

**The measurement** (`reports/diaspora/tools/or_sharing_census.py`, read-only on
`_snapshot_pruned_GC0911.txt`, 2 G cage, 160 s). For every co-evaluated pair of
decided decisions and every shape in fp(A) ∪ fp(B), the 2×2 over co-evaluated
profiles (cell = present in some run / absent in all; unobserved cells
enumerated over their completions; four orientations of "on" tried; a shape is
monotone if some orientation makes reachability non-decreasing in (A on, B on)):

```
pairs examined (co-evaluated, both decided): 3 776
  ALL-OR            2 295   every shape OR / A-only / B-only / ALWAYS   (61 %)
  ANY-AND             602   at least one shape present only with BOTH on (16 %)
  NO-SHAPES           464
  UNDETERMINED        407   an unobserved cell leaves AND possible
  ANY-NONMONOTONE       8
(pair, shape) classes: ALWAYS 44 883, NEVER 29 216, UNDETERMINED 11 479,
  UNDETERMINED(AND?) 5 705, A-only 3 078, OR 2 811, B-only 2 538, AND 2 477,
  OR-family 1 534, NON-MONOTONE 10
```

By family (ALL-OR / ANY-AND / UNDETERMINED): text×text 628/50/0;
len-gate×text 517/120/32; not_found-gate×text 347/119/126;
len-gate×not_found-gate 116/78/52; row-attr×text 127/61/28;
not_found×not_found 48/32/30; len-gate×len-gate 79/24/5;
dispatch×not_found 11/10/0; dispatch×len-gate 20/4/0; public-gate×text 11/13/30.

**The AND pairs are real interaction, and they are named.** The dominant
shapes: `ActiveRecord::Relation.findpublic_like` / `findpublic_reshare` — issued
only when the dispatch arm is taken AND the previous finder in the
act → like → reshare fall-through did NOT find (`Length(SYM_PARAM_id) < 16` ×
`findpublic_act_1_not_found`, × `findpublic_like_1_not_found`, …);
`Person.name | Person#name` (dispatch × len gates, len gate × text);
`CollectionProxy.size | SELECT COUNT(*) FROM "photos"` (photos length × mentions
length). These are sequential fall-throughs and joint presenter conditions —
exactly "a shape needing BOTH on".

**Pre-registration for the pricing (written before it ran).** What-if: the
2 295 ALL-OR pairs forced confined (`WHATIF_PAIRS`, `confinement_census.py`,
identical flags and snapshot to the GC0911 census); UNDETERMINED and NO-SHAPES
pairs NOT forced. Against §69.1: the dispatch hub (`Length(SYM_PARAM_id) < 16`,
degree 136) sits in AND pairs with the whole `findpublic_*` family and several
len gates, and the len-gate × text family has 120 AND pairs — those keep wide
cliques glued. I expect **outcome (3)**: `remaining` drops by 2–4 orders of
magnitude from 7.77e10 to **10^6–10^9**, not below 10^4, with the residual in
sets containing the dispatch × findpublic chain and the len-gate × text AND
pairs. Falsifiers: < 10^4 → outcome (1), the AND pairs do not glue the wide
sets and I misread the hub; ≥ 10^10 → the OR-forcing does not split the wide
sets at all (AND pairs form connected cliques across every wide set) and the
refinement is not worth implementing.

**Pricing — what ran and what did not.** The identical-flags exact census
(`confinement_census.py` + `WHATIF_PAIRS`) was **OOM-killed at the 2 G cap**
during the dump load (rc 137; the batch's own census peaked ~3.3 G). I did not
raise the cap. A Z3-free STRUCTURAL pricing (scratchpad `whatif_structural.py`,
2 G, 408 s) rebuilds the identical universe — aliases, untracked, declared
independence, foreclosure, `project_confinement` — and reproduces the census
exactly on structure (§16b 1 901 sets; §16c 6 494 sets with the same width
histogram), then forces the 2 295 ALL-OR pairs:

```
§16b     sets=1901  sum(2^w)=1.493e15  max_w=45  wide(>=13)=1892
§16c     sets=6494  sum(2^w)=8.942e12  max_w=36  wide(>=13)=6365   (census: sat 7.766e10)
§16c+OR  sets=1677  sum(2^w)=4.466e09  max_w=27  wide(>=13)=999    ratio 2002x
```

At the census's own Z3 ratio for §16c (7.77e10 / 8.94e12 = 0.87 %) the exact
`remaining` after OR would be ≈ **4×10^7** — inside the pre-registered
10^6–10^9 band: **outcome (3)**, as predicted; not (1) (< 10^4), not (2).
The residual is named: 999 wide parts glued by 1 079 non-confined pairs —
`CollectionProxy_records × assoc_root_text_has_mention` (745 parts), same-rep
`as_api_response_N_row_guid == '' × != ''` (712 / 669), mentions length ×
root text (697), `find_by_3_not_found × find_by_3_text_empty` (650, own
downstream) — AND / UNDETERMINED / own-downstream pairs. Decisive on the
structural evidence; the exact number is one 3.3 G run away, flags identical,
and is the coordinator's call.

**Implemented (round 5).** `coverage.py`: `infer_pair_tables` (one pass over
profiles: per co-evaluated pair, per cell, the trace union and a witness
profile), `classify_cells` (the four orientations, completions of unobserved
cells; OR / A-only / B-only / ALWAYS / NEVER benign; AND, NON-MONOTONE,
UNDETERMINED(AND?) refuse), the OR licence in `project_confinement` as a
UNION with the strict licence (`confinement_or_sharing=True`, the earlier
rule as `False`), fields `confinement_or_pairs`, `confinement_and_pairs`
(pair, shape, class, cell, witness run), `summary()` line; the `force_confined`
what-if hook used for the pricing. Gate: criterion (viii) — shared shapes
judged as a 2×2 on the four replays; (iii) and (v) on unshared shapes only
(the additive law is the wrong law for an OR shape — it survives each single
flip and vanishes only in the double, so from an (on,on) base (iii) would
FAIL every OR pair; the coordinator's "already PASSES" holds only from an
(off,off) base); survival allowed where another producer is on; (vii) now
builds the ALL-OFF cell and FAILs on a route around every known producer.
`or_sharing_census.py` in `tools/`.

**Tests.** `test_confinement.py` **29/29** — `_or_corpus` (z iff a OR c):
strict refuses, refined licenses `(a,c)` via the table; `zj` only with both
on → AND, refused, cell and run `a-t c-t` named; the (T,T) cell made z-less
→ NON-MONOTONE, withdrawn (the falsifier); (T,T) never walked →
UNDETERMINED, refused; `classify_cells` directly incl. the flipped-polarity
OR; nesting `refined ⊆ strict ⊆ §16b` on 60 corpora (20 with OR pairs, 40
byte-identical); every earlier strict assertion re-pinned under
`confinement_or_sharing=False`. `test_confinement_gate.py` 25/25: the OR
pair PASSes with "(viii) 1 shared shape(s) OR-monotone by replay", the AND
pair FAILs "(viii) shared shape is AND by replay", the non-monotone pair
FAILs, the 27-shape posts_show pair as an AND table FAILs.
`test_confinement_active.py` 8/8: a route via a DECLARED producer is OR
(PASS), an undeclared one still FAILs (v), a route around every known
producer in the never-walked all-off cell FAILs (vii), the solver's UNSAT
evidence stands. e2e 4/4, X10 4/4, every pre-existing suite green.

**Nesting, stated.** `weak ⊆ strict` at each keying; `confined-gates ⊆ earlier
strict ⊆ §16b`; and now `OR-refined ⊆ strict ⊆ §16b` — each refinement only
ADDS licences (a union), which is what makes every one of them provable on
random corpora rather than argued.

**Attribution and the notifications pricing (2026-09-11, later).** The
`confinement_census.py` run on notifications the coordinator killed (pid
847496, 1.4 G, 11 min, to give people_stream's blockaid subsumption its window)
was NOT launched by this agent: it was the notifications agent's own run of
`tools/confinement_census.py` (its `_confinement_census.json`, 11:58, sits in
that directory). This agent's only corpus jobs were the posts_show OR what-if
(OOM at 2 G, rc 137) and the posts_show structural pricing. Per the
coordinator's ruling the exact notifications census is nice-to-have and a
STRUCTURAL pricing is acceptable, labelled as such: a headroom-gated run
(waits for blockaid and every census/pass to exit and ≥ 4 G free; 3 G cap) of
the structural tool — now driven by the ENGINE's own OR licence
(`project_confinement(or_sharing=True/False)`), so strict vs OR needs no forced
pair list and the same run names the AND-refused pairs — is armed for
posts_show (GC0911, consistency with the forced-list number above) and for
notifications' latest snapshot (`_snapshot_pruned_20260911_122751.txt`). Its
numbers were to be appended below — but the harness's low-memory watchdog
killed the launcher while it was still IDLE (no structural log was ever
written): the box is held by the notifications agent's own certification pass
(`coverage_report.py`, 4.5 G) and its own run of `tools/confinement_census.py`
(3.1 G). That run imports the live engine, so its exact `16c` line IS the
OR-licensed number for notifications and supersedes any structural estimate;
its owner reports it. The structural tool is left for whoever runs next as
`tools/confinement_structural.py` (strict vs OR from the engine's own licence;
a 2–3 G job; run only when no pass or census is up), and
`confinement_census.py` now prints the OR/AND breakdown. The notifications
OR-vs-strict comparison is therefore UNMEASURED by this agent, by the
coordinator's own memory rule, and not estimated in its absence.
