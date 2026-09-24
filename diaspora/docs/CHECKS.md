# The Completion Checks — reference-free verification of a concolic batch

Split out of `notifications_index/FINAL_REPORT.md` §5. This is the full
check battery in detail, one section per check, each with an example from
this project's history.

**Framing (Bali, 2026-08-24): the engine must stand WITHOUT a reference
policy.** Every check below is judged against ground truth we always
have — the app's own real execution (its SQL log, its branch coverage)
and the corpus's internal consistency. A reference policy, when one
happens to exist, is a bonus oracle (§C3) — never the completion
criterion. "Complete" means: C1 and C2 pass, and the per-mock /
per-assumption / fold-space audits pass.

**Plain names (Bali, 2026-08-25) — the two MAIN drivers:** the letter
codes below are historical; operationally the suite is:
- **THE MOCK CHECKER** (`ruby_runtime/completion_checker/mock_checker.rb`)
  = Part I per-mock battery: shim probes (zero target functions + 100%
  line coverage of the real body) and target-note shape checks, driven
  by a per-batch manifest, exit-code gated. Smoke: 2/2 on
  notifications_index probes.
- **THE ASSUMPTION CHECKER**
  (`end_to_end_completion_checker/assumption/assumption_checker.py`) = Part II:
  per-assumption corpus scan (tripwire) + directed flip-probe
  (controlled experiment) from a per-batch manifest, run at the END of
  each generation. Smoke: persisted-foreclosure probe passes in ~15s.
- the **fold diagnostics** (Part III, all dump-side) run at the end to
  catch anything missing;
- the **real-run check** (Part IV, formerly C1/C2): one real fixture
  run of the endpoint, statements and coverage diffed against the
  corpus — the strongest check, pending the fixture-DB harness.

Implementation status per check is marked. Implemented checks live in
two homes (split 2026-08-25, Bali): the language-agnostic corpus/fold
auditors and the C1 differ in **`src/end_to_end_completion_checker/`**
(Python — the dump schema is runtime-agnostic, so they serve py_runtime
and ruby_runtime corpora alike), and the in-process probes that must run
inside the target app (T1 target_call_probe, C1 statement_log capture,
C2 coverage_probe capture) with their runtime:
`src/ruby_runtime/completion_checker/`. See each README for invocation.

---

## Part I — per-mock checks

**Terminology (naming convention, Bali 2026-08-24).** There are exactly
two kinds of mock, and every check below names which one it applies to:
- A **shim mock** replaces pure computation. It must reach no target
  function and contributes NO evidence. T1/M2 are its checks.
- A **target mock** is the mock of a declared **target function** — the
  functions registered with `declare_target`, where the runtime mints its
  evidence (events, notes, symbolic results). A target mock's obligation
  is the opposite of a shim mock's: it MUST produce evidence, and that
  evidence must match what the real target function would have done
  (C1-shape, T1b are its checks).

### T1 — shim-mock probe (target-function form)
**Claim it verifies:** a shim mock replaces only computation that reaches
**no target function**. This is the engine-native contract
(reframed 2026-08-24, Bali): target functions are where the runtime mints
its evidence, so a shim mock over a target-reaching body swallows
evidence *by construction*, whatever the target does. SQL-issuing target
functions are the most important family, but the rule is about targets,
not about SQL: a shim mock that hides a finder, an association load, a
declared helper probe, or any future target family fails T1 identically.
**Method:** call the shimmed method's REAL body (shim mock disabled) with
concrete fixture values, with every (module, method) pair the batch
declares wrapped by a counting tracer; assert zero target invocations.
Where a DB is wired, additionally assert zero statements (statement_log)
— a redundant belt for the SQL target family.
**Example:** `Person.name_from_attrs(first, last, handle)` passes — pure
string logic, reaches nothing declared. `Person#name` FAILS — its body
reads `self.profile`, which is a declared association target
(`SingularAssociation#find_target`); this is exactly why the X6i shim mock of
it was removed in gen2, and the probe reports the precise target reached
(`SingularAssociation#find_target`), not just "some SQL happened."
**Pass:** `TargetCallProbe.assert_shim_mock!(targets: <the batch's declared
pairs>) { real body }` — zero target-function invocations.
**Status:** implemented (`target_call_probe.rb`: `capture`,
`raise_on_call:` fail-fast for bodies that would crash past the target,
`assert_shim_mock!`). `statement_log.rb` remains the SQL-family supplement.
This supersedes the SQL-phrased T1 wording in `DISCIPLINE_TESTS.md` /
`notifications_index/README_TESTS.md` (kept there as historical record).

### M2 — probe coverage rule
**Claim:** the T1 probe actually exercised the whole body (a branch the
probe missed can still reach a target function).
**Method:** run the T1 probe under line coverage (JRuby needs `--debug`);
require 100% of the real body's lines.
**Example:** a probe of `MessageRenderer#plain_text` that only passes
mention-free text covers half the body; M2 rejects it and forces a
mention-bearing fixture, which is how the `make_mentions_plain_text`
path stayed honest.
**Pass:** 100% line coverage of the shimmed method.
**Status:** implemented pattern (Coverage + `--debug`); helper in
completion_checker (`coverage_probe.rb`).

### C1-shape (formerly M4) — note fidelity against ground truth
**Claim:** a target mock's emitted note IS the statement real execution
would issue — tables, joins, predicates-with-binds, and projection.
**Method:** boot the CLEAN app (no mocks), render the real relation's
SQL (`to_sql`, or capture via C1's statement log), and compare against
the mock's note shape.
**Example (violation 4+):** the pluck target mock's note said
`SELECT "tags".*` where the real statement is
`SELECT tags.name, taggings.id ... ORDER BY taggings.id` — the ground
truth probe (`notifications_index/_probe_tags_sql.rb`) exposed BOTH the
projection gap and the fact that the association scope's ORDER BY column
is projected by real pluck. Note-vs-args checking alone missed the
second fact — always compare against the real statement, never against
what the mock intended.
**Pass:** normalized statement equality (literals wildcarded, binds as
placeholders).
**Status:** probe pattern established; normalizer + differ implemented
(`statement_diff.py`).

### T1b — statement-SET equivalence
**Claim:** a target mock standing in for a multi-statement mechanism emits
EVERY statement the real path issues, not just one.
**Method:** enumerate the real mechanism's statements (through-table
fetch for `has_many :through`; one SELECT per step for `.includes`
preload chains) and require one emitted note per statement, routed
through an event-generating probe (extraction only collects from
events).
**Example (violations 1, 3):** `mentions.includes(person: :profile)` —
real Preloader issues `mentions...`, `people WHERE id IN ...`,
`profiles WHERE person_id IN ...`; the materialize target mocks emitted only
the first. The `emit_includes_preloads` repair walks `includes_values`
reflections and emits each step; the six profiles-via-mentions coverage
gaps closed the same day.
**Pass:** real statement multiset == emitted note multiset (C1 subsumes
this check once implemented end-to-end).
**Status:** repair pattern in targets.rb; detection via `statement_diff.py`.

### T1c — pin branch-neutrality
**Claim:** every pinned (concrete) value either provably cannot change
any branch outcome, or carries a seeded, PC-RECORDED decision.
**Method:** per pin, a written neutrality argument; if the app compares
the pinned value, the pin must record the compare as a PC (concrete
value + recording `==`, the TypeLinkedString pattern) or be seeded
symbolic.
**Example (violation 7):** `attrs["type"] = "Notifications::Liked"` (a
plain String) silenced `note.type == "Notifications::StartedSharing"`
(_notification.haml:5) — no PC, so the type predicate vanished from
every downstream view. TypeLinkedString keeps the concrete value (so
`constantize`/`Hash#key`/`is_a?` behave) but records the compare.
**Pass:** zero data-dependent compares against pinned values without a
recorded PC or a ledger entry (detected by C2 / `pc_visibility_audit`).
**Status:** audit implemented (`pc_visibility_audit.py`).

---

## Part II — per-assumption checks (A-rules)

### A1 — corpus-wide zero-violation scan
Scan every dump for a state violating the assumption. Necessary, never
sufficient — and it is important to be precise about WHY (Bali,
2026-08-24): the corpus is an *uncontrolled* sample. Runs vary many
inputs at once, so between any two runs, other inputs may be influencing
each of the supposedly-independent paths — observed non-correlation can
be an artifact of which inputs were tried (we seeded the dimensions
independently, so they LOOK independent), and observed correlation can
be confounded by a third varying input. A1 therefore never *establishes*
independence. What it soundly provides is: (1) a **falsifier** — one run
exhibiting the assumed-impossible state kills the assumption on a single
witness; (2) a **standing tripwire** — it re-runs free on every future
corpus, catching couplings introduced by NEW paths that did not exist
when A2 last ran (assumptions, like mocks, are only correct relative to
the paths that reach them). Establishing independence is A2's job: a
CONTROLLED experiment — hold the entire seed dict fixed, vary ONLY the
dimension under test, both directions — which excludes the
different-inputs confound by construction (A3's line-diff is available
as a diagnostic when an A2 probe fails). An A1 hit on a later corpus
means: re-run A2 in the new path context.
**Example:** IndependenceAssumption on two seeded dimensions — scan that
no run shows the assumed-impossible combination or a seed overridden by
the other dimension's setting.

### A2 — directed probe (the controlled experiment that licenses the assumption)
**Claim it verifies:** the assumption's causal story is true under
controlled conditions — for an INDEPENDENCE assumption, that varying
dimension X (with everything else held fixed) leaves dimension Y's path
and outcome unchanged; for a FORECLOSURE assumption, that the
assumed-impossible state, when forced, actually produces the divergence
the assumption claims (and nothing it doesn't claim).

**Method (the protocol that answers the confounding objection in A1):**
1. Pick a real run from the corpus and snapshot its ENTIRE applied seed
   dict — this freezes every input.
2. Produce probe seed dicts that differ from the snapshot in ONLY the
   dimension under test. Both directions: one probe forcing each side
   (for a pair-independence claim: flip X with Y held, then flip Y with
   X held).
3. Replay each probe deterministically (`SEEDS_ONLY=1` +
   `EXTRA_SEEDS_JSON=<probe>.json` — pure replay, no exploration, so the
   only degree of freedom is the flipped seed).
4. Compare the probe run against the snapshot run ON THE OTHER
   DIMENSION'S EVIDENCE: its PCs, its emitted notes, its outcome.
   Identical ⇒ the flip did not influence the other path under these
   conditions. Different ⇒ dependence witnessed; the assumption is dead
   and the difference IS the repair's specification.
Because the two runs share every input except one, "a different input
could be influencing each path" is excluded by construction — this is
the single-variable control A1 cannot provide.

**Worked example (a dependence this project learned the hard way —
gen3b, recorded in targets.rb §gen2b):** the batch originally seeded the
Mention container type (`SYM_MENTION_CONTAINER`: Post vs Comment) as a
dimension INDEPENDENT of the notification type
(`SYM_NOTE_TYPE_PROFILE`). An A2 probe of that independence claim is:
take a `mentioned_in_comment` run's full seed dict, flip ONLY the
container seed to Post, replay. The probe run diverges violently — the
i18n render dies on a missing `:comment_path` (this exact crossing
produced 294 crashes when exploration wandered into it blind) — so the
probe run's evidence on the "other" dimension is nothing like the
snapshot's: **independence refuted on one controlled witness**, days of
crash-triage compressed into one replay. The repair the divergence
dictates: container type is DERIVED from the active note profile, not
independently seeded — which is exactly what §gen2b now does.
The persisted-foreclosure direction, same protocol: take a
`persisted=true` run's seeds, flip only `_persisted` to false, replay —
confirm the `1=0` scope family appears AND is labeled by its own
`(<base>_persisted == False)` PC rather than leaking unlabeled into the
corpus. That both confirms the foreclosed side exists (the assumption
isn't hiding a reachable state) and that its evidence is attributed.

**Pass:** for independence — the probe pair's evidence on the untouched
dimension is identical (PC set, notes, outcome), both directions; for
foreclosure — the forced state produces exactly the claimed, labeled
divergence (this criterion also catches a dead knob: a seed that
silently does nothing fails, since the claimed divergence never
appears).

**Timing (Bali decision, 2026-08-25): A2 is verified AT THE END of each
generation, against the FINAL evidence layer.** An A2 pass is a
statement relative to the target/note set it ran under, and this
engine's evidence layer grows with every repair (preload emissions,
TypeLinkedString, probe events...). Running the probes last — after the
final target/mock/note change, on the corpus the policy is actually
extracted from — makes the verdict contemporaneous with the policy, so
no staleness argument arises. Cost is low: probes are SEEDS_ONLY
replays + an evidence diff, seconds each; re-running the full
assumption probe set is part of the end-of-batch gate.

**What A2 observes (scope, Bali 2026-08-24):** the evidence layer only —
target-function calls (events, notes, `$$()` binds), recorded PCs, and
run outcome; that is all a dump contains. This is the RIGHT surface
because the extracted policy is built from nothing but evidence: a
dependence that never manifests in a note, bind, or PC cannot affect the
policy by construction. The conditionality: a dependence flowing through
a BLIND branch (Class B) is invisible to A2 exactly as it is to DSE — so
A2's guarantee is only as strong as branch visibility (D2/T1c/C2) and
note fidelity (D1/C1) on that corpus.

**What A2 cannot do:** it licenses the assumption only along the paths
its probe context exercises. New branch families opened by later
exploration can create couplings that did not exist when the probe ran —
which is A1's job to watch for (tripwire), sending A2 back out in the
new context. Record each A2 run's probe seeds in the assumption's
ledger entry so the re-run is one command.

**Status:** the protocol is fully mechanical given the runner's existing
knobs (`SEEDS_ONLY` + `EXTRA_SEEDS_JSON`); probes are authored per
assumption (judgment chooses WHICH dimension pair and snapshot, the
replay and comparison are scriptable). A `seed_flip_probe` driver —
snapshot run + dimension name in, evidence diff out — is the planned
completion_checker addition; until then the comparison is done with
`bind_chain.py`/dump diffing per probe.

### A2-derived — the tests the ENGINE runs per declared assumption (Bali, 2026-08-26)

The coverage checker already hands the engine every declared assumption
with its TYPE and exprs, so no manifest "kind" is needed: the test is
derived from the type's own claim in `concolic_engine/assumptions.py`,
in ACCESS-TRACE currency (target function + normalized statement +
argument shapes per call):

- **IndependenceAssumption(A, B)** — claim: no combination of A/B
  outcomes produces a target-call sequence or argument shape the
  individual branch trees don't already cover (the class's own
  "practical test"). Test: from a snapshot run recording both, replay
  flip-A, flip-B, flip-both; the both-flipped trace must add NO shape
  absent from base ∪ flip-A ∪ flip-B. Never co-evaluated in any run ⇒
  mutually exclusive ⇒ PASS without probes.
- **UntrackedPathAssumption(e)** — claim: the branch is irrelevant to the
  access pattern. Test: flip e; the trace must be identical.
- **OneSideUntrackedPathAssumption(e, tracked_side)** — claim: the
  untracked side is a no-op. Test: flip from the tracked side; if the
  flipped run never records e at all, that side is unreachable by
  construction (PASS, annotated — flipping the VARIABLE can route into
  a different region, whose shapes are not this assumption's business);
  otherwise the untracked side must add no shape beyond the tracked.
- Unseeded dimensions are still flippable: the run's value is inferred
  from the recorded PC (`(X == L)` taken ⇒ X = L; not taken ⇒ set X to
  L), since the seed dict is a total assignment. Operators covered:
  `==`/`!=` against literals or variables, `<`/`<=`/`>`/`>=` against
  ints, and `Length(X) op N` (flip = a string whose length crosses N —
  the guid-vs-id dispatch; added 2026-08-26 after the sub-agent's run
  reported 20 NOT-TESTABLE on exactly that family).
- Anything else (raw SymbolicConstraint) reports NOT-TESTABLE, never a
  silent pass. FAIL blocks completion in the engine's report.

Notifications_index, 15 declared, three runs while the test matured:
10 PASS / 1 FAIL / 4 NOT-TESTABLE → 12 / 0 / 3 → **14 PASS / 0 FAIL /
1 NOT-TESTABLE**. The FAIL was the value-forced-region subtlety above
(fixed by the reachability check); the NOT-TESTABLEs were unseeded
dimensions, var-vs-var compares and ordering compares (fixed by
inferring the flip from the recorded PC: `==`/`!=` against literals or
variables, `<`/`<=`/`>`/`>=` against ints). The last one is a genuine
finding: a `guid != ''` assumption whose expr never occurs in the
current corpus — stale, carrying no coverage; reported as such rather
than passed.

### A3 — data-flow divergence (DEMOTED to on-demand diagnostic — Bali decision, 2026-08-25)

**Not a gate.** With A2 verified at the end of each generation against
the final evidence layer (see A2's timing rule), evidence-level
independence is contemporaneous with the extracted policy and A3's
"A2-pass staleness" rationale no longer applies. Execution-level side
effects that never touch a PC or a target function do not affect the
policy, so they are not checked.

**What remains of A3:** when an end-of-batch A2 probe FAILS, run the
same probe pair under line coverage (`coverage_probe.rb`, JRuby
`--debug`) and take the symmetric line diff — the first diverging line
names the exact site where the dependence enters, which is the repair's
specification. (In the mention-container example, the diff begins in
the i18n key construction for the type's translation, pointing straight
at the note-type ↔ container coupling.) A debugging tool reached for on
failure; nothing gates on it.

### A4 — the blocklist
Anything unverifiable is LISTED as an assumption, never silently
assumed. The checker's continuation pass ignores assumptions — so every
entry must name its seed and its blast radius.

**Status:** implemented as THE ASSUMPTION CHECKER
(`end_to_end_completion_checker/assumption/assumption_checker.py`): A1's scan and
A2's flip-probe protocol per manifest entry, end-of-generation; A3's
line-diff remains its on-demand failure diagnostic.

---

## Part III — fold-space checks (extraction; violations 5 & 8 lived here)

### F1 — placeholder audit
**Method:** count unresolved `$$()`/`_SYM_PARAM_` binds in the extracted
output; name every excluded view. A placeholder SPIKE is a fold
regression, not noise.
**Example (gen8):** owner-qualified renames broke fold registration →
21/71 views became placeholders in one generation. The count was the
alarm; the fix (note-driven registration) restored 70/71 the same day.
**Status:** implemented DUMP-SIDE as `bind_resolution_audit.py` (Bali
directive 2026-08-25: all checks run on dumps): every `$$()` bind in
every note is resolved against the dump's own var table with the fold's
own rules (schema-aware; column resolution mirrors
`_bind_value`/`_match_column`), so placeholder views are PREDICTED
before extraction runs. Validated: flags the gen10 `first_1_person_id`
family (1,392 occurrences) from dumps alone — the same finding the
extracted-SQL audit made post hoc.

### F2 — skipped-PCs audit
**Method:** every recorded PC the extraction cannot parse lands in
`skipped_pcs` — audit that bucket; a whole CLASS of exprs being skipped
is a Class-B-in-fold-space alarm.
**Example (violation 8):** `StringVal('…')` — the runtime's native
rendering for EVERY string compare — was unparseable by `parse_pc`, so
every string-equality branch in every corpus was silently dropped. The
bucket had been shouting since gen1; nobody audited it.
**Status:** implemented in its REAL form (`skipped_pcs_audit.py`): every
recorded PC runs through the pipeline's ACTUAL `parse_pc` (with an
all-resolving synthetic producer/schema so only grammar failures remain;
`--patched` installs a batch's fold patches first to audit the pipeline
as deployed). First run reproduced violation 8 mechanically: vanilla
src/ drops 99,197 StringVal-shaped PC records (RED); the patched
pipeline drops zero (2,906 len() records dropped by design). The shape
census in `pc_visibility_audit.py` remains the no-dependency fallback.

### F3 — chain-attribution spot check
**Method:** for each NEW view family, trace one dump's `$$` bind chain
by hand (or script) from the consuming query back through producers, and
confirm the folded join matches.
**Example (violation 5):** three colliding `assoc_profile` producers in
one run — the fold guessed, attributed the tags read to the contacts
chain, and the view was provably wrong. Owner-qualified names
(`assoc_base_name`) made chains unambiguous.
**Status:** automated corpus-wide by `bind_resolution_audit.py`'s
AMBIGUOUS class (same name, multiple SELECT producers in one dump — the
violation-5 signature); `bind_chain.py` (retired to trash 2026-08-26) was for interactive
single-chain tracing.

### F4 — complement audit
**Method:** run-level PC folding over-scopes queries that execute on
BOTH sides of a branch. Views identical modulo `col = 'x'` vs
`col <> 'x'` merge to the unscoped view (their union, sound);
single-variant scoped views are listed with the gating branch.
**Example (gen10b→c):** the actors chain gained `=`/`<>` StartedSharing
variants; two reference queries flipped to proven-rejected until the
merge. The taggings view correctly KEPT its predicate — the contact read
genuinely only happens inside the branch.
**Status:** implemented DUMP-SIDE (`complement_audit.py <batch_dir>`):
a PC expr recorded with both polarities is what becomes `=`/`<>` view
variants; the audit reports which producer-note families appear under
BOTH polarities (mergeable — union is the unscoped view) vs only one
(genuinely branch-gated, predicate kept), which is exactly the input the
view-build's merge step needs. Merging itself stays in the view-build.

### F6 — identity symbolicity (added 2026-08-26, from the metric-only sub-agent experiment)
**Claim:** the endpoint's PRINCIPAL (the session user) is symbolic in the
corpus — every bind on a principal column (`users.id`, `*.user_id`,
`*.owner_id`, `*.recipient_id`) is a `$$(SYM_...)` bind, never a literal.
**Why it exists:** the sub-agent reached `complete: true` while seeding
the session key concretely (`serialize_from_session(1, ...)`), so every
signed-in view folded as `users.id = 1` instead of `_MY_UID`: a policy
for ONE user. It evaded every other check — the note check wildcards
literals (`= 1` ≡ `= ?`), the fold audits saw well-formed binds, and the
coverage checker does not know what a principal is. The reference diff
exposed it (rejections on the `_MY_UID` families). This is the results2
"pinned id" trap, now mechanized as a gate.
**Method:** `identity_symbolicity_audit.py <batch>` — count symbolic vs
literal binds per principal column across all notes; any literal is RED.
Discriminates cleanly: comments (agent run) RED on 1,202 literal
`users.id = 1`; notifications pass with 868 symbolic.
**Status:** implemented; wired into the engine's `audit_cmds` gate (the
engine now runs ALL dump-side audits itself — the experiment showed an
agent can reach `complete` while skipping them).

### F8 — exception notes (added 2026-09-15, from the B-4 boundary defect)
**Claim:** no note in the corpus is a captured exception.
**Why it exists:** a boundary renderer that raises has its exception text
stored AS THE NOTE. The note field then looks populated and NOTHING downstream
can tell prose from a statement — `noteless_call_audit` sees a note and passes,
the fold sees a non-SELECT and quietly leaves the bind unresolved, and the
shipped policy carries a placeholder no SQL consumer can load. B-4 lived this
way for about four weeks and through a full endpoint closure: `collect_binds`
called `#value` on an `Arel::Nodes::Casted`, which arel-9.0.0 does not define,
so every STI relation raised — 1 574 occurrences per 150 posts_show dumps, the
largest single gap in that corpus, and it was only found by auditing
placeholders in a SHIPPED policy, i.e. two steps downstream.
**Method:** `exception_note_audit.py <batch>` — grep every event and var note
for captured-exception text (`<x> failed:`, a Ruby exception class name,
`undefined method`), skipping anything that is already a SELECT. Pure text
scan: no runtime, no re-render, and it works retroactively on corpora already
on disk.
**Discriminates cleanly (2026-09-15, 120 dumps each):** RED on posts_show
(4 457 notes), **pass on all five others** — which independently confirms the
`TODO.md` T-DIV finding, since posts_show is precisely the copy that never
received the 2026-08-19 "bug-2b" repair.
**Status:** implemented (`src/queries_from_runs/audits/exception_note_audit.py`).
A second, stronger option — prefixing captured-exception notes with a reserved
sentinel so they are machine-classifiable — was deliberately NOT taken: it
moves every existing degenerate note and so needs a corpus-wide ruling, and
this audit gets most of the value without it.

### F7 — policy loadability (added 2026-09-15, from the conversations_index placeholder defect)
**Claim:** every statement of a SHIPPED policy LOADS in the project's own SQL
loader, and no bind is left unresolved.
**Why it exists:** every other check here is DUMP-side; none opens the file
that ships. `subsume.py`'s contract is that a query the loader cannot take
"participates in no pair and always survives" — it stays in the policy, is
counted as a view, and means nothing to any consumer. conversations_index
shipped the authenticated user's own person id as
`_SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id`,
43 times, with a fully symbolic corpus, F6 green, engine complete and
adversary R7 zero wins. An unresolved bind is not just unparseable, it is
OVER-PERMISSIVE: a bare token constrains nothing where the run proves the
value is the row some recorded query returned. Measured on the six shipped
policies before the fix: conversations_index 11 of 58 statements loadable.
**Method:** `policy_loadability_audit.py <batch> <policy.sql>` — feeds the
file's statements to `subsume/check_subsumed.sh` (Calcite parse + the app
config's schema + blockaid's type probe) and reports `written` / `loadable`;
then, for each unresolved bind, prints what the corpus recorded for it, which
separates a RESOLVER defect (a SELECT was recorded and should have become a
join) from a BOUNDARY-INSTRUMENTATION defect (the note is a description, an
error, or absent — no resolver can recover a statement that was never
recorded).
**Status:** implemented
(`src/queries_from_runs/audits/policy_loadability_audit.py`); run it on the
file about to ship. The sibling tool `tools/policy_loadability.py` does the
same measurement across several policies at once for a differential.

### F5 — statement-note lint
**Method:** cheap corpus-wide lint of every emitted note: junk-fallback
notes ("WHERE unavailable", "render failed"), finder-family notes with
no WHERE, pluck notes projecting `*`.
**Example (violation 6):** 806/806 find_by events with the bare
`SELECT "contacts".* FROM "contacts"` — one lint run would have flagged
the severed conditions years of generations earlier.
**Status:** implemented (`statement_note_lint.py`).

---

## Part IV — the differentials (the completion criterion)

**Driver (2026-08-26): C1 and C2 are run by an ADVERSARIAL SUB-AGENT, not
by a script.** The agent did not build the batch; it reads the endpoint's
real code and constructs real-mode scenarios (real app, real fixtures, no
mocks) whose target-function trace the corpus cannot reproduce. The
scripts below are its instruments and its judge (capture + "in corpus or
not"); the search for the scenario is the adversary's job, because the
scripts can only diff what the engine already decided to look at. A win
for the adversary = a Class S/B finding = the batch is not complete. See
`RUNBOOK.md` Phase 5 and `src/end_to_end_completion_checker/concrete/CONCRETE_CHECKER.md`.


### C1 — statement differential (kills Class S, all mechanisms)
**Method:** run the endpoint END-TO-END in real mode — concrete
fixtures, real DB, `sql.active_record` subscription logging every
statement — then diff the normalized real statement set against the
corpus notes AND the folded views (both: violations 5/8 proved evidence
can be recorded and still lost at fold time):
- real statement with no counterpart → **swallowed** (violations 1, 3, 6);
- counterpart with different projection/joins/predicates →
  **mis-shaped** (violations 0b, 4);
- note with no real counterpart → warn (usually a seeded branch the
  fixture didn't take — cross-check the run's PCs).
Per-PATH, not per-mock: every new branch family opened by exploration
gets a fixture scenario and a fresh differential.
**This is the primary completion check.** It needs no reference —
ground truth is the app itself.
**Status:** capture side implemented (`statement_log.rb`); normalizer +
differ implemented (`statement_diff.py`); the fixture-scenario harness
per endpoint is per-batch wiring.

### C2 — branch differential (kills Class B)
**Method:** same real-mode run under line/branch coverage; diff against
(a) the union of app lines executed across the concolic corpus and
(b) recorded PCs:
- app conditional executed in real mode, never reached in the corpus →
  blind spot (violation 2's photos family);
- conditional the corpus DOES execute with no PC over any symbolic
  operand and no pin-ledger entry → blind compare (violations 0a, 3, 7 —
  the "zero `diaspora_handle` PCs corpus-wide" scan that cracked the
  preload bug is C2 done by hand).
**Status:** capture helper implemented (`coverage_probe.rb`); corpus-side
coverage collection needs a runner flag (wire per batch); PC-side audit
implemented (`pc_visibility_audit.py`).

### C3 — external oracle (OPTIONAL — only when a reference exists)
When a reference policy happens to be available, a determinacy diff
against it is a free extra detector: any residue it finds means C1/C2
have a gap — fix the CHECK, not just the mock (rule P: the new check
must catch the violation's CLASS with the mechanism unspecified).
**The engine's completion criterion never depends on this.** For
diaspora we had one and it served as the detector of record while C1/C2
didn't exist; that dependency ends with this suite.

---

## Part V — verdict-layer rules (when any solver-based check IS used)

- Four-way taxonomy only: covered / rejected / unknown / tried_unknown;
  every "tried" records subset used, budget, CPU-vs-memory attribution.
- Subset soundness: subset proof ⇒ covered; subset failure ⇒ NEVER
  rejected; subset-definitive verdicts must be re-checked full-set
  before being reported (the gen7 taggings "subset-definitive" was a
  filter artifact; the gen10b regressions were confirmed real this way).
- Environment: `--setenv` on every systemd scope (env does NOT inherit),
  `JAVA_TOOL_OPTIONS` unset, extraction in a fresh unit (page-cache
  cgroup accounting), per-query blast-radius scopes.

## The process rule (P)

When a violation is found, the repair loop (T3) ends only when a check
exists that catches the violation's CLASS with the mechanism left
unspecified. Instance-shaped tests do not close the loop — this is the
rule that was broken three times before it was written down, and the
reason violations 1→3 and 4→8 came in chains.

### A2-derived — additions 2026-08-26 (from the conversations_index gate)
- **Canonical expr matching.** Batch reports rename the runtime's `len(X)`
  to `SYM_LEN_X` for Z3; the checker now matches modulo that rename.
  Before this, every declared expr over a list length silently matched no
  dump and 127 independences over them PASSed as "mutually exclusive"
  while the corpus co-evaluated them — a false green.
- **"Never co-evaluated" is PASS only if BOTH exprs are recorded somewhere
  in the current corpus;** an expr recorded nowhere is NOT-TESTABLE
  ("stale or renamed"), never PASS.
- **`len(X)` is a flip dimension:** the runtime seeds a SymbolicList's
  length under the key `len(<name>)`, so length-based decisions are
  replayed like any int compare (`(len(X) != 0)` taken → replay with
  `len(X) = 0`).
- **`((- VAR) op N)`** (negated int operand) parses; the flip is the
  mirrored relation on `-N`.
- **SymbolicConstraintAssumption now has a derived test.** Claim: the
  region where `z3_expr` is false does not exist. Test: seed the
  constrained variable to a violating value (`>= N` → `N-1`, `< N` → `N`,
  …) on the richest snapshot and replay. PASS if the run is unrealizable
  (no dump — e.g. a negative list length) or adds no target-call shape
  beyond the snapshot's; FAIL if the excluded region issues shapes of its
  own (the constraint was hiding behaviour from the coverage checker).
- **Probe batching.** Distinct (scenario, seeds) roots are replayed up to
  40 per runner launch; roots that share a path with another root in the
  batch (the runner writes one dump per distinct path) are re-run singly.
- **SymbolicConstraint, domain-implied case.** If the violating value lies
  outside the variable's declared domain (engine `SymbolicVar` low/high, or
  the built-in fact that a list length `len(X)` is a concrete row count ≥ 0)
  the constraint PASSes as "implied by the variable domain" without a
  replay — and the batch should state it as a variable BOUND rather than a
  constraint. (First attempt seeded `len(X) = -1`: the runtime accepted it
  and rendered the representative row, producing shapes that do not exist
  in any real run — a replay cannot judge a type-level fact.)

### F7 — evidence fidelity per target call (an ADVERSARY duty, not a script)
For every target-function call in a real run (the batch's scenarios and
the adversary's), the corpus note for that target must be faithful to what
the real call actually did — for a data-access target, that means the
projection (which columns / an existence bit / an aggregate), the
predicate columns, and the ordering, not merely the tables. What each
target must evidence is described in the project's target doc
(`TARGET_FUNCTIONS.md`); the adversary reads the real call, reads the
note, and reports every discrepancy as a finding (a `t.*` note over a
one-column read over-approximates the policy; a row-read note over an
aggregate misstates it). mock_note_check accepts a superset shape and is
deliberately generic; the projection judgment is the adversary's. A
diaspora-specific helper that automates the SQL comparison lives with the
reports (`tools/note_fidelity_audit.py`), not in the engine. First results
(2026-08-26): comments_index 11/11 exact; conversations_index — `pluck(:author_id)`
and `contacts.empty?` noted as whole-row reads, the messages COUNT noted as
a row read, the DISTINCT-subquery COUNT and the INNER JOIN conversations
read noted only in their eager-load form.

## REQUIRED, NOT YET BUILT — class-scoped OVER-emission (adversary R9, 2026-09-01)

**The gap.** 4 014 of 12 999 anonymous comments_index dumps asserted two LIMIT-1
person reads that no anonymous request can issue, and neither existing check
could see it: `hardening_lint` H6 is a GLOBAL presence test and real *auth* runs
issue those reads, while `_multiset_counts` skips a shape whose class ground
truth lacks it entirely. That skip is deliberate — judging UNDER-emission per
class produced a false RED in R7 (DISCIPLINE §14, "presence is global"). The
asymmetry to encode: **under-emission is a global question, over-emission is a
per-class one.**

**Where it belongs: inside the batch's `_multiset_counts.py`, not a new tool.**
The coordinator attempted a standalone `tools/class_shape_review.py` on
2026-09-01 and **deleted it** rather than ship it. It needed to know each
statement's request class, and tried to read that off scenario NAMES. That
fails on real data in two different ways, both discovered by running it:
- conversations_index classes its scenarios by FORMAT (`html_withcid`,
  `js_plain`, `mobile_plain`…) and its ground-truth files by something else
  again, so corpus and ground truth were two different populations — the first
  version printed 21 shapes at "100% of class" that were pure misclassification;
- comments_index has a ground-truth scenario literally named
  `comments-mobile-anon-session-switch+auth-explicit`, which is BOTH classes:
  the class is a property of a REQUEST, and a scenario can change class midway.

`_multiset_counts.py` already derives request boundaries (openers, the principal
rewind, the `under: null` body rule), so it already knows the class of each
request. The check therefore belongs there, as a distinct verdict line —
`CLASS-OVER: shape S asserted in N dumps of class C whose real requests never
issue it` — reported separately from the under/over counts and never folded into
the pass/fail line without the population it was computed over.

**Standard it must meet:** unobserved in a class is NOT the same as impossible
in a class (a corpus explores far more states than a handful of real scenarios
exhibit), so this is a RANKED REVIEW LIST for the adversary to triage, ordered
by how much of the class rests on each shape — not a verdict.

## boundary_declaration_audit — EXERCISE CENSUS + CROSS-BATCH CONTRAST (2026-09-01)

**Why it grew.** notifications_index C7 found `Calculations#sum` DECLARED and
invoked **0 times in 879 248 symbolic_call events**, because a `layout(false)`
pin removed its only call site. The audit passed — correctly, since it checked
DECLARATION — and was blind to the very class its own docstring describes.
Declaration is not exercise.

**What it now prints** (exit status unchanged; this is information, not a
verdict):
1. per declared boundary method, how many `symbolic_call` events invoked it
   (`symbolic_call` only — a `call` trace event carries a target but is not an
   invocation, DISCIPLINE §14);
2. a REVIEW line for declared-but-never-invoked methods;
3. given TWO OR MORE batch dirs, the **cross-batch contrast**: methods invoked
   in one batch and never in another. That is the sharp form of the question.
   "Zero here" is weak — no endpoint calls `delete_all`. "Zero here, 18 306 next
   door, same declared boundary" is the shape of a suppressed call site.

**Validated on the closed endpoints, and it corroborates them:** comments shows
`count`/`empty?`/`find_by`/`pluck`/`save`/`sum`/`take`/`to_ary` at 0 against
conversations' thousands — every one explained by comments' own verified
findings (it renders NO layout, `render layout: false` in the app's own code,
and makes no writes: 0 DML notes corpus-wide). conversations shows no gap
against comments. A tool whose output on known-good data matches what the
evidence already said is one you can take to unknown data.

**Standing use:** run it over ALL batches at once, not one at a time — the
contrast is the point, and it costs nothing extra.
