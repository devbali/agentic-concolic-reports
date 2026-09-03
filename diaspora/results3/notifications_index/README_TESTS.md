# README_TESTS — the verification checks behind this batch's mocks & assumptions
### (notifications_index, final composite state, 2026-08-20 — synthesized from experiment variants A/B/D; canonical rule text in `../MOCK_TEST_RECIPE.md` + `../DISCIPLINE_TESTS.md`; this README writes the tests OUT in full and records what was actually run here.)

Nothing in this batch's mock/assumption surface is admitted by argument
alone. Every mock passed (or was removed by) the MOCK TESTS below; every
assumption class passed (or was blocked by) the ASSUMPTION TESTS below.
All verdicts are produced by scripts with metrics; ledgers are
machine-readable JSON.

---

## PART 1 — THE MOCK TESTS (run on every `declare_target` / prepend shim)

### Test M1 — leaf isolation: "the real body issues no SQL and calls no target"

Procedure, exactly as executed (`_experiment/variant_a/_leaf_probe.rb`):
1. Boot the real Rails env (`RAILS_ENV=concolic`) with the batch's
   `concolic_targets.rb` + `targets.rb` installed. Before installation,
   wrap `CallInterceptor#declare_target` to capture every target's
   PRISTINE pre-mock `UnboundMethod` (keyed by `[klass.object_id, method]`
   — plain names collide across anonymous singleton classes).
2. Pre-warm the connection's `schema_cache` for every fixture model and
   run one harmless scoped read per model, so Rails' own lazy metadata SQL
   (`PRAGMA table_info`, `sqlite_master`) cannot false-positive.
3. Install a connection-adapter hook (prepend on `execute`/`exec_query`)
   that records/raises on ANY database touch.
4. For the method under test: swap the real body back in
   (`define_method(pristine)`), leaving every OTHER target still mocked.
5. Invoke it on a CONCRETE fixture matrix — at minimum {nil-ish, typical,
   boundary} per argument; models are `allocate`d with concrete attribute
   writes, no symbolic types.
6. Record: the interceptor's `TargetCall` delta (any entry = the real body
   CALLS A DECLARED TARGET), and adapter-hook hits (any = the real body
   ISSUES SQL).
7. Restore the mock.

**Metric:** `target_calls == 0 AND connection_touches == 0`.

### Test M2 — the 100% coverage rule on mocks

M1's verdict is only as good as what the fixtures reached, so:
1. During each M1 invocation, collect executed lines via
   `TracePoint(:line)` scoped to the method's `source_location` range.
   (JRuby: MUST run under `jruby --debug` or line events silently drop —
   verified empirically. Denominator = executable-line scan via Ripper,
   documented as an approximation since JRuby lacks
   `RubyVM::InstructionSequence`.)
2. Union coverage across the whole fixture matrix.

**Metric:** `covered_lines / body_lines == 100%`. A line the matrix never
executed is a branch the probe never checked — and a branch that could
hide SQL. Below 100%, the verdict is NOT pass: either add fixtures that
take the uncovered branches (the uncovered line numbers say which), or
record a PER-LINE WAIVER with the reason the line is unreachable.

### Test M3 — ledger closure

Every declared target/shim must have a row in `LEAF_PROBES.json`:
`{method, fixtures, target_calls, connection_touches, body_lines,
covered_lines, coverage_pct, waivers, verdict}` — including NOT_PROBED
rows, which require an explicit `skip_reason`. A verdict produced by
inspection instead of the harness does not count as a probe.

### Test M4 — note fidelity (design mocks)

A design (query-boundary) mock's `note` must be the real SQL. Corpus-wide
scripted sweeps assert: 0 "WHERE unavailable" notes, 0
`render_relation_sql failed` fallbacks, and 0 UNLABELED degenerate SQL
(`1=0` may appear only in runs whose own `_persisted == False` PC is
taken, checked via the taken flag, not string presence).

### What M1-M4 produced on THIS endpoint
- 98-row ledger (variant A): 6 clean PASS, 4 design-EXEMPT (probed,
  recorded), 3 structural-pass prepends, 80 NOT_PROBED with skip_reasons,
  2 FAIL + 1 FAIL_COVERAGE + 1 instrumentation-failed + 1
  inherited-no-override.
- The repair loop (below) then consumed the FAILs: 3 declarations REMOVED
  (`assert_is_devise_resource!`, both `head` declarations — one dead code,
  one redundant cover over PASS leaves; each corpus-proven dead: 0 calls
  in 7,837 dumps, deterministic regen reproduced 3,966 paths / 0 errors).
  Ledger: `LEAF_PROBES_REPAIRS.json` (this dir). One FAIL_COVERAGE
  remains OPEN (fixture repair pending), recorded as such.

---

## PART 2 — THE ASSUMPTION TESTS (run per declared class)

Assumption classes here: type-variant exclusivity (Tier 0),
existence-foreclosure (Tier 1: same-var chains, finder arms,
persisted-gates, count-chains), one-sided value-forced exprs (Tier 2).
All are DERIVED FROM THE RUNS at check time (`coverage_assumptions.py`)
and only within argued structural classes — and derivation alone is not
admission. Three tests gate them:

### Test A1 — corpus-wide zero-violation scan (necessary, never sufficient)

Pure-python scan over every dump's recorded path conditions: for the
claim "guard@side forecloses expr B", count runs where guard took that
side AND B was recorded.

**Metric:** `violations == 0` with BOTH populations >= 100 runs, and B
observed both ways on the recording side. Re-run MANDATORY after any
mock/code change: ordinals ride a shared per-(class,method) counter, and
the gen1 finder-arm tier went provably stale on the gen3 corpus exactly
this way (caught by this scan).

### Test A2 — directed probe ("data independence", both directions)

The corpus shows explored runs never violated; A2 shows a DIRECTED
attempt cannot:
1. Foreclosing side: seed the guard's variable concretely to the
   foreclosing side (single `SEEDS_ONLY=1` run, everything else default);
   assert FROM THE DUMP'S RECORDED EVENTS (never from the seed dict) that
   expr B's recording site did not fire — no PC, no var mint.
2. Recording side: seed the other side; assert B DOES fire.
Both directions must hold or the class is inconclusive.

### Test A3 — data-flow divergence (the mechanism test)

Run the entrypoint under a line tracer twice — one fresh JVM per side
(`Coverage.start` before `config/environment` loads; same-process double
runs double-patch `declare_target`), identical seeds except the guard —
and diff the executed-line sets (`_experiment/variant_b/
_t2_divergence_run.rb`).

**Metric — BOTH mechanically:**
1. The line sets first diverge AT THE GUARD'S CITED CODE SITE. Divergence
   anywhere else falsifies the claimed MECHANISM even when the conclusion
   happens to hold.
2. The foreclosed expr's recording-site lines are a subset of the
   recording-side set and DISJOINT from the foreclosing-side set.
Output per class into `ASSUMPTION_FLOW.json`
({class, guard, guard_site, divergence_line, gated_lines,
present_on_recording_side, absent_on_foreclosing_side, verdict}).

### Test A4 — the blocklist

A class without a mechanical A2+A3 PASS is NOT declared, whatever A1's
counts say — wired as a constant the derivation loop consults
(`_T2_BLOCKED_CLASSES` in variant B's `coverage_assumptions.py`).

### What A1-A4 produced on THIS endpoint
- finder-arm: PASS (disjoint PC sets, 0/24 vs 3/27 directed runs).
- persisted-gate: PASS — and the probe FALSIFIED the first mechanism
  hypothesis before it shipped (sibling-`_persisted` guess was wrong; the
  witness identified the true gated family: the through-association
  `count_records` PCs, with coverage divergence at the exact
  `collection_association.rb` null_scope? site). The flagship
  demonstration of why A2/A3 exist.
- Tier-0 sanity pair: PASS (disjoint sets, types 0 vs 4).
- same-var-chain: not separately probed — sound by construction
  (identical Z3 variable), the same carve-out Tier 0 gets.
- count-chain, Tier-2 one-sided: BLOCKED (no probe within budget) —
  undeclared rather than carried on corpus counts.

---

## PART 3 — THE REPAIR LOOP (what a FAIL triggers)

A FAIL is an input, not a terminal state. Its machine-readable WITNESS
(violating call site / uncovered lines / counterexample run / divergence
line) must generate a replacement — descended mock, added fixtures,
re-derived assumption — which re-enters the same test. Bounded at 3
turns; terminal states are PASS or PROVEN-IMPOSSIBLE with the witness
attached; every chain recorded as `repair_chain` triples in the ledger.
"FAIL kept with a note" is a scriptable discipline violation. Executed
live on this batch: `LEAF_PROBES_REPAIRS.json`.

---

## PART 4 — corpus/pipeline checks this batch also passed

- Scenario/type minimum coverage: every STI type profile got its own
  bounded round (LIFO worklists starve everything behind the first root).
- Missing-combination seeding: every checker-named missing combo with
  concrete_values replayed via `SEEDS_ONLY`; conjunctions verified in the
  dumps' PCs (types 0-3 closed; types 4-7 REFUTED — the conjunction
  structurally cannot mint there — and the refutation recorded).
- View-usability: 63 final queries, 1 placeholder (excluded from views,
  kept in the set, named).
- Zero run errors across the final corpora (8,031 dumps), all degenerate
  SQL labeled by its own PC.

### Hard-won pipeline lesson (2026-08-20, appended)
`systemd-run` does NOT inherit the caller's environment: the per-query
capped-checker wrapper silently dropped `SUBSUME_TIMEOUT_MS`, so the JVM
ran its 15s default while our ledger said 60s — caught only because a
verdict's reason string quoted "15000 ms" against a 300000 request. Rule:
timeout/thread env MUST be passed with explicit `--setenv`, and every
recorded verdict carries the reason string so a budget mismatch is
self-evident. Corollary proven immediately after the fix: a query that
was "unknown at any budget" for two days was PROVEN COVERED in one true
300s run (~3.1G solver peak — which is also why the memory watchdog must
be coordinated with, not fought: it had been correctly killing exactly
these ballooning solver runs).

Score these tests are accountable to (reference diff, 71 queries):
1 covered (results2) → 7 (gen2) → 15 (round 1) → 30 (round 2) →
**64 covered / 0 rejected / 7 tried_unknown** — GEN4 FINAL. The last
two residue families fell to discipline repairs, not solver escalation:
T1b (note/statement-set equivalence — the through-association intermediate
now emitted) erased the final proven rejection, and T1c (pin
branch-neutrality — `_text_nil` seed + Post STI dispatch) opened the
photos family, flipping 15 more to covered. The 7 remaining: 5
subset-definitive (view families the extraction still lacks, each named
in the ledger), 2 CPU-bound solver instances. Prior-generation history
below for the record (the "1 rejected" era = the bare
`notification_actors` row, a named extraction-granularity residue).

### T1b repair #2 — eager-load preloads (2026-08-21, gen6)

The 6 profiles-via-mentions tried_unknowns were NOT a scope residue (a
gen5 hypothesis — handle-only mention formats forcing `Person#name` —
was refuted by its own experiment: 1,530 runs took the handle-only
branch, zero new profile reads, and zero `diaspora_handle` compare PCs
anywhere in the corpus). The true cause was found by asking why the
branch was *invisible*: `mentioned_people` (mentions_container.rb:18) is

    mentions.includes(person: :profile).map(&:person)

and the real AR Preloader issues one SELECT per `includes` step —
`people` by `mention.person_id`, `profiles` by `person.id` — while ALL
of our materialize mocks (Relation `to_a`/`records`/`to_ary`,
CollectionProxy `records`/`load_target`) returned a single-note list
and swallowed the preloads entirely. Same violation class as T1b
(note/statement-set equivalence), eager-load edition.

Repair: `emit_includes_preloads` in targets.rb — shared by every
materialize mock — walks `includes_values` via reflections and emits
each preload step through `ConcolicThroughLoadProbe`. Binds use the
value identity `person.id == mention.person_id`, so both preload
queries key on the rep's `person_id` var and assoc_fold reconstructs
the join chain to the mentions producer. `has_many :through` preloads
emit the REAL first Preloader query (the through-table fetch) and stop
the chain honestly — the naive rendering fabricated a non-existent
column (`people.person_id`), caught in the smoke replay before it could
hand the reference diff a new rejection. Polymorphic `includes`
(`:target`) are skipped (no static klass). Smoke-verified before the
gen6 corpus regen: all four expected emissions present, none bogus.

### FINAL (2026-08-21, gen10c): 71 covered / 0 rejected / 0 tried_unknown

The endpoint is closed. After gen6's 70/71, the last query (`tags.name,
taggings.id`) took four more chained repairs — each only visible after
the previous one (violations 4→8 in ../DISCIPLINE.md): pluck order-column
projection (gen7) → owner-qualified assoc var names fixing fold chain
attribution (gen8, plus a fold-registration fix, gen8b) → find_by
conditions thread-local capture restoring the notifications-target →
contacts link severed in every prior corpus (gen9) → TypeLinkedString
recording the app's `note.type == "Notifications::StartedSharing"`
branch plus the StringVal unwrapper that let string PCs fold at all
(gen10/gen10b). Type-scoping then over-constrained the actors chain
(two regressions, proven rejected) — resolved soundly by complement
elimination at view build (gen10c): `=`/`<>` variant pairs merge to the
unscoped view; the genuinely branch-gated taggings view keeps its
predicate. Corpus: 5,543 dumps, 15 rounds, errors={} throughout;
80 extracted queries → 77 usable views after placeholder exclusion and
complement merge. Verdicts in diff_gen10c/notifications_index/_progress.json.

### gen6 result (2026-08-21): 70 covered / 0 rejected / 1 tried_unknown

The preload repair flipped ALL SIX profiles-via-mentions queries plus the
two mention-row queries: gen6 baseline 62/0/9 at 15s, subset sweep
resolved 8 of 9 (most in 2-5s — the subset-view mode doing exactly what
it was built for). Extraction's subsume prune also ran clean this time
(107 distinct → 80 views).

The single holdout: the `tags.name, taggings.id` query — subset-definitive
(our views provably cannot answer it), i.e. the pluck-projection fix was
still not shape-faithful. A ground-truth probe (`_probe_tags_sql.rb`, a
first concrete C1 instance per ../DISCIPLINE.md: boots the clean app, no
mocks, renders the real relation SQL) showed why: the acts-as-taggable-on
tags association scope carries `ORDER BY taggings.id`, and real pluck
projects order columns alongside the requested ones — `taggings.id` comes
from the ORDER BY, not from the pluck arguments. The pluck mock's note
now appends un-projected order columns and table-qualifies bare columns
(real pluck renders `"tags"."name"`, not `"name"`). gen7 corpus running
with this in.
