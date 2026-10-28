# AliasAssumption — the loop refactor, and what the falsifier did to it
### notifications_index, 2026-09-09/10

**Headline: the rename and the widened key are in; the collapse they were
supposed to buy is REFUTED by the gate.** The `to_ary` notifications list's
four WHERE-clause variants are not one loop — intervening on them has three
different effects, because the typed variant's rows never reach the
photos/mentions chain. The `Relation#records` mentions loops fail the new
k+1 arm because the bulk preload's `IN` arity follows the row count and the
policy consumer preserves `IN` arity. What survives is the five CollectionProxy
families: **435 tracked expressions -> 411, and 2 050 maximal cliques -> 1 277**,
not the ~200 nodes the widening was expected to produce (which the full widening does deliver — measured — but
only by merging decisions the evidence says are different).

---

## 1. The rename

`DecisionAliasAssumption` -> `AliasAssumption`. Every reference updated:

| file | what changed |
|---|---|
| `src/concolic_engine/assumptions.py` | class renamed, docstring rewritten, `loop_key` added, `key="loop"` and `k: int = 1` fields, `_alias_core` key selection |
| `src/concolic_engine/coverage.py` | comment; `assumptions_to_dict` serialises `k` **only for a loop alias** |
| `src/end_to_end_completion_checker/assumption/assumption_checker.py` | import, `_ALIASES` construction (carries `k`), `_test_alias` (parts (i) and (iii)), unique probe label token |
| `src/test_assumptions.py` | existing test renamed; new `test_alias_loop_key_folds_list_variants_but_not_owner_chains` |
| `results3/{notifications_index,people_stream,posts_show}/coverage_assumptions.py` | import + declaration |
| `results3/{notifications_index,people_stream,posts_show}/coverage_report.py` | comments |

**No `DecisionAliasAssumption = AliasAssumption` deprecated alias was kept.**
Nothing needed it. The one place the old name still appears is the gate's
type dispatch, which accepts `"DecisionAliasAssumption"` alongside
`"AliasAssumption"` as a *serialised type string* so the gate can still be run
against a `coverage_summary.json` written before this change. Historical `*.md`
reports were left alone.

## 2. The widened key

`loop_key(note)` (assumptions.py): from the statement key, keep the FROM table
and the binds; drop everything that only makes a VARIANT of the same loop — an
extra scope, a type or flag predicate over literals, an ordering, a page
window.

    FROM notifications BY $$(SYM_RESULT_..._devise_user_first_1_id)

The CALL SITE is not in the key because it is already in the NAME:
`canonical_result_name` keeps the result's stem, so `Relation_to_ary` and
`Relation_records` on the same table with the same bind stay two names (they
do, on this endpoint — the paginated list and the unread badge list share a
loop key and are still two names).

`_alias_core` stays a pure function of `(events, aliases)`; the only change is
which key function it applies to the note it has already rendered with the
chain-identity map (`kmap`). That is the rule it already applied to NESTED
READS, now available for the reading itself.

**The `len(<list>) > 1` hubs collapse with the body, and that follows from the
alias map alone** — the length variable is named `SYM_LEN_<result name>_rows`
and the row decisions `<result name>_row_<chain>`, so renaming the result
renames both. No second assumption kind is involved; `test_assumptions.py`
asserts exactly this (`sum(1 for e in names if "SYM_LEN_" in e) == 1` over
three variant runs).

`k: int = 1` is the iteration at which the identity kicks in. It is carried in
the summary only for a loop alias, so a `statement`/`shape` declaration
serialises exactly as it did before the field existed.

## 3. IN-arity: the ruling

**The policy consumer is arity-SENSITIVE, so the falsifier is too.** Evidence
in `queries_from_runs`:

* `transform.py:105-110` (`_tokenize_binds`) rewrites each `$$(x)` in place —
  the element count of an `IN` list is untouched;
* `transform.py:589` — `clean_conjunct` returns early for anything that is not
  an `exp.Binary`, and `exp.In` is not one, so an `IN` conjunct never gets the
  SYM_PARAM broadening or the my-person-join rewrite that `= $$(...)` gets;
* `dump.py:114-119` — view dedup is on the exact SQL string;
* `subsume.py:59-82` — the syntactic pre-pass compares conjuncts as a frozenset
  of exact rendered strings, so `IN (a, b)` and `IN (a)` are unrelated.

Measured consequence on this corpus: `..._to_ary_1_row{,2,3}` and
`..._to_ary_1_row{,2,3,4}` bulk reads emit **two separate views per table**
(3-bind and 4-bind), each carrying unresolved `_rowN_` placeholders (only
`row_`/`item_` are stripped by `pcs.py:126-133`), each therefore
`eligible=False` for subsumption pruning.

So the falsifier's "identical target-call shapes" uses `access_trace` —
`$$(...)` -> `?`, `'...'` -> `'?'`, **arity preserved**. It does NOT use
`mock_note_check._wildcard`, which folds `exp.In` in with `exp.EQ` and would
have made every arity change invisible. That choice is the difference between
the mentions loops passing and failing, and it was made from the consumer's
code, not from the result it produced.

## 4. Per-loop falsifier verdicts

Gate run through the engine's own load path
(`assumption_checker.py --declared`, `canonicalize: coverage_report:canonicalize_ordinals`,
single-run replays via `tools/slot`, `ACHK_LABEL_TOKEN=lp0909`, drained: 0
`*achk*` files left, corpus still 68 231).

### 4a. The full widening (every list read keyed by loop) — 13 names, PASS 9 / FAIL 4

| loop | verdict | why |
|---|---|---|
| `CollectionProxy_records_aspects` | PASS | one statement; 8 members x flips [0,2,3]; k+1 clean |
| `CollectionProxy_records_services` | PASS | one statement; 8 members; k+1 clean |
| `CollectionProxy_records_tags` | PASS | one statement; 5 members; k+1 clean |
| `CollectionProxy_records_aspect_memberships` x2 | PASS | one statement each (contact `find_by_1` / `find_by_2`); k+1 clean |
| `CollectionProxy_records_photos` x3 | PASS | **2 statements merged each** (an owner chain and its `AND (1=0)` empty-scope variant); identical intervention effects; k+1 clean |
| `Relation_records_notifications` (unread) | PASS | one statement; k+1 clean |
| `Relation_records_mentions` x3 | **FAIL (iii)** | NEEDS k=2. At 2 rows the target-call shape set changes: `SELECT "people".* ... WHERE "people"."id" IN (?, ?, ?)` +2/-2, and two `... "id" = ?` singular loads disappear. Each of these names merges NOTHING (one statement) — the failure is purely the k=1 iteration claim. |
| `Relation_to_ary_notifications` (the ×4 layer) | **FAIL (ii)** | The four merged variants split into THREE intervention-effect groups. Named difference: at length 0 one variant removes `SELECT "photos".* FROM "photos" WHERE "photos"."status_message_guid" = $$(...)` that another does not. |

**Why the `to_ary` failure is real, not an artefact.** The four variants are
plain / `type = '?'` / `unread = true` / both. The typed variant is
`type = 'Notifications::StartedSharing'`, whose rows have no status-message
target, so their rendering never reaches the photos or mentions chain that the
plain variant's rows do reach. That is DISCIPLINE violation 7 seen from the
other side: the notification TYPE decides the downstream statement set, which
is precisely why the type PC had to be made visible in the first place. A row
of the typed list and a row of the plain list are not the same row, so a
decision about them is not the same decision.

### 4b. What is declared (the shipped set) — 16 names, PASS 16 / FAIL 0

    AliasAssumption(result_pattern=r"SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_\d+",
                    key="loop", k=1)
    AliasAssumption(result_pattern=r"SYM_RESULT_ActiveRecord__(?:Relation_records|Relation_to_ary)_\d+",
                    key="statement")

16/16 PASS (`ACHK_LABEL_TOKEN=mx0909`). The eight statement-keyed names return
the exact verdict text they returned before this refactor — "single member
(ordinal N): identity by statement key, no cross-ordinal claim to intervene
on" — which is the gate-side half of the inertness proof.

### 4c. Undeclared loops, and why

| loop | why not declared |
|---|---|
| `Relation_to_ary_notifications` x4 | falsifier FAIL (ii). Merging them would merge rows of different notification types. |
| `Relation_records_mentions` x3 | falsifier FAIL (iii) at k=1 ("NEEDS k=2"). Not re-declared at k=2: the instruction was not to tune k, and a k=2 claim would still have to survive its own k+1 replay. |
| `Relation_records_notifications` (unread) | PASSES, but is minted through the same `Relation#records` call site as the three failing mentions loops, so no pattern over ORDINAL names selects it alone. It loses nothing — one statement, hence one name, under either key. |

## 5. P2 / K1: nothing is subsumed, nothing double-declared

P2 untracks the `> 1` arm of the aspects/services/tags root families; K1 does
the same for the unread-notifications root family. The alias decides only what
a length is CALLED. For all four of those families the alias renames nothing
(one canonical name before, one after), so neither declaration changes and
neither is subsumed. `_P2_RE` and `_K1_RE` match the new names unchanged
(`[0-9a-f]{6,}`); the build line still reports `untracked=6 K1=1`. Both stay
as they were.

## 6. Inert unless declared

**people_stream** (`key="statement"`, 755 runs) re-run on the new code:

| quantity | standing summary | after |
|---|---|---|
| tree_nodes | 29 | 29 |
| missing_branches | 40 | 40 |
| coverage_complete / truncated / solver_lost | False / True / 0 | False / True / 0 |
| total_runs / total_path_conditions | 755 / 6 021 | 755 / 6 021 |
| assumptions (172 entries) | — | **JSON-equal, byte for byte** |
| assumptions_used | 102 | 102 |
| `missing[]` node-constraint SET | — | **equal** (0 only-before, 0 only-after) |

The `coverage_summary.json` FILE is not byte-stable across identical runs —
two consecutive runs of the same new code differ from each other, in the order
of `missing[]` entries and in which satisfying model Z3 returned. So
"byte-identical" is established where it is meaningful: every deterministic
field, the whole assumption serialisation, and the missing set.

**posts_show** (`key="statement"`, 96 357 runs): all **26** canonical names in
its standing summary are reproduced exactly by the new code over a 3 000-dump
sample (0 not reproduced); one additional name appears in the sample that the
truncated `missing[200]` list did not contain.

**Unit tests**: `test_assumptions.py` 15 tests, 14 pass. The whole python suite
(minus `queries_from_runs`, which needs a venv) is **100 passed, 1 failed** —
`test_untracked_by_expression_at_a_shared_source`, which fails identically
before this task (it is the known casualty of the earlier uncommitted
combination-semantics rewrite, recorded in `_DECISION_ALIAS_REPORT.md` §3) and
touches no alias code.

## 7. Rule T — which endpoints are affected

**This is NOT a Rule T2 event.** Nothing in the shared target boundary changed:
no `declare_target`, no note, no return kind, no mock, no application code, no
pin. `shared/target_boundary.rb` is untouched, and so is
`ruby_runtime/call_interceptor.rb` — the ordinal-naming root cause the
STATE_HANDOFF calls out as the upstream fix stays unfixed on purpose, because
fixing it there IS a Rule T event and this refactor deliberately is not one.
No closed endpoint's `complete: true` is voided.

| endpoint | references the class? | effect |
|---|---|---|
| conversations_index (CLOSED) | no | none |
| comments_index (CLOSED) | no | none |
| people_show (milestone) | no | none |
| **notifications_index** (open) | yes | renamed + `key="loop"` declared for the CollectionProxy families; corpus, targets and seeds untouched |
| **people_stream** (open) | yes | renamed only; `key="statement"` unchanged; summary re-run and equal (§6) |
| **posts_show** (open) | yes | renamed only; `key="statement"` unchanged; all 26 canonical names reproduced (§6) |

The three closed/milestone endpoints do not import the class at all — verified
by grep over `results3/*/coverage_*.py`; only the three open batches match.

## 8. The price — exact, not `cliques x MMC`

`_exact_enum.py` (new, in this batch) answers the question the engine's
`missing` count cannot — that number is `cliques x MAX_MISSING_PER_CLIQUE` and
measures the clique count, never the gap. The tool builds the SAME universe the
coverage pass builds (same load path, same `build()` assumptions, same graph,
same maximal cliques via the engine's own `_maximal_cliques`) and then counts
exactly:

* **satisfiable** — inside a clique, expressions sharing no Z3 variable are
  independent, so the clique's count is the PRODUCT over its variable-connected
  COMPONENTS. A component is the handful of decisions over one variable, so its
  own count is enumerated with the checker's own solver. Exact for any width;
  not a 2^w enumeration and not the 4 096-capped job.
* **covered** — the union of the cubes each whole-clique-evaluating run covers
  (the engine's blocking clause: the outcomes it fixed, free where it recorded
  both sides), by sum-of-disjoint-products, each piece counted through the same
  factorisation. **`bounded_cliques=0` on every run below** — nothing was
  bounded, every figure is exact, not a lower bound.
* cross-check — `--verify` re-derives the satisfiable count of random narrow
  cliques by direct all-SAT: **6/6 OK** (widths 5, 5, 5, 6, 6, 6).

Same 68 231-dump corpus, `MAX_CLIQUES=16384`, one declaration per row.
`nodes` is the engine's `tree_nodes` (all distinct PC expressions); `active` is
what enters the graph after untracking.

| declaration | nodes | active | cliques | satisfiable | covered | remaining | uncovered |
|---|---|---|---|---|---|---|---|
| `statement` (before this task) | **435** | 426 | 2 050 | 606 496 | 18 509 | 587 987 | 96.95% |
| **SHIPPED** — `loop` for CollectionProxy, `statement` for Relation | **411** | 402 | **1 277** | **542 784** | **13 891** | **528 893** | 97.44% |
| the full widening the gate REFUTED | **189** | 183 | 327 | 158 876 | 4 517 | 154 359 | 97.16% |
| SHIPPED at half the corpus (34 000 runs) | 411 | 402 | 1 253 | 535 952 | 11 812 | 524 140 | 97.80% |

The `statement` row reproduces the standing summary's `tree_nodes = 435`
exactly (426 active + 9 untracked), which is the tool validating itself against
the engine.

### 8a. The owner's three expectations, ruled on

1. **"nodes 435 -> ~200 (the ×4 layer alone)" — CONFIRMED as arithmetic,
   REFUTED as a declaration.** The full widening gives **189**, squarely in the
   predicted range. But the gate refuses it (§4a), and the part that survives
   gives **411**.
2. **"cliques far fewer and narrower" — CONFIRMED, and it is the largest real
   gain.** Shipped: 2 050 -> **1 277** maximal cliques (−38%) for a −5.6% node
   reduction, because photos' three owner chains stop being six mutually
   entangled families. Widths are unchanged in shape (3–20, median 32
   satisfiable assignments per clique, max 32 768 at width 20).
3. **"the target stops GROWING with runs" — CONFIRMED.** Doubling the corpus
   34 000 -> 68 231 runs moves nodes **402 -> 402** (flat), cliques
   1 253 -> 1 277 (**+24**), and the target itself 535 952 -> 542 784
   (**+1.3%**). Against the old declaration's "+16 869 runs added +216
   cliques", the target is now effectively stationary.

### 8b. The hubs

The four cardinality hubs did not go away; three of the shipped universe's top
eight are still `to_ary` variants — degrees 185 (`photos_341476bd_rows > 1`),
182/181/181 (`to_ary_notifications_{10254800,cf379872,c7e6a7ca}_rows > 1`) out
of 402, against 432/428/427/395 out of 435 before. They shrank because the
universe shrank. Under the full widening they DO collapse to one — a single
`to_ary_notifications_0320524d_rows > 1` at degree 182 of 183, i.e. still
adjacent to almost everything — and that collapse follows from the alias map
alone, with no second assumption kind, exactly as §2 claims. It is the merge
itself the evidence refuses, not the mechanism.

## 9. Reachability — no

**notifications_index is not reachable by driving, and the alias does not
change that.** Three independent reasons, all exact:

1. **330 of 1 277 cliques are evaluated whole by NO run in the corpus.** More
   runs of the same shapes cannot cover them at any count — they need runs that
   reach all of a clique's expressions in one execution, which is a scenario
   problem, not a volume problem.
2. **The marginal rate.** Going from 34 000 to 68 231 runs added 2 079 covered
   assignments — **0.061 per run**, and falling (coupon-collector). At that
   already-optimistic constant rate the remaining 528 893 need **~8.7 million
   further runs**; at the corpus's own measured throughput (STATE_HANDOFF:
   ~1.5 M runs ≈ 13 h, i.e. ~32 runs/s) that is **~75 hours** as a LOWER bound,
   with the true figure larger because the rate decays.
3. **The uncovered fraction is invariant to the keying** — 96.95% (statement),
   97.44% (shipped), 97.16% (the refuted full widening). Re-keying changes the
   size of the target, not the reach of the driving. Even if the ×4 merge had
   been sound, 154 359 of 158 876 assignments would still be unobserved.

Only **17 cliques of 1 277 are fully covered**. The engine's `missing` at
`MAX_MISSING_PER_CLIQUE=1` is therefore exactly **1 260** (the cliques with any
unobserved satisfiable assignment) — derived from the exact census, and the
same quantity the pass reports.

## 10. How it was run

* Coverage passes and the enumerator ran in
  `concolic.slice/concolic-cov.slice/<scope>` with `-p MemoryMax=10G` / `5G`,
  `JAVA_TOOL_OPTIONS` unset. **The cap must be verified AND the slice must be
  outside `app.slice`**: the first attempt used `systemd-run --user --scope`
  with no `--slice`, which lands in `app.slice`, whose own `MemoryMax` is
  **5 GB**. Both my jobs (2.5 GB + 2.0 GB) were OOM-killed there
  (`Result=oom-kill`, `Memory cgroup out of memory` in the kernel log) while
  each scope's own 10 G cap was never approached — the same failure mode the
  DecisionAlias report hit. `systemctl --user show <scope> -p MemoryMax` said
  10 G and was true; it is the PARENT that killed them.
* Gate probes: `tools/slot`, `CONCOLIC_SLOTS=2`, unique `ACHK_LABEL_TOKEN`
  per invocation (`lp0909`, `mx0909`). `run_probe` now stamps that token into
  `LABEL_SUFFIX` so a stale probe dump from a crashed run can never be globbed
  back in as this launch's evidence. Drained, not hard-killed: **0** `*achk*`
  files left in the batch and the corpus still exactly **68 231** dumps.
* **CORRECTION (coordinator, 2026-09-10 02:30): the end-of-batch pass did
  NOT die.** `ndxcovB.scope` finished its coverage phase in **2 443 s**, ran
  shim extraction and the shim tests, wrote `_assumptions_declared.json`
  (78 567 declarations), and was 46 minutes into the assumption gate when the
  coordinator **killed it deliberately at 02:16** — the owner had just
  approved replacing the complete-graph dependence semantics with
  co-evaluation (`_COEVAL_SEMANTICS_20260910.md`), which supersedes this pass.
  The earlier paragraph here attributing the exit to a JVM abort was written
  by an agent that did not know about the kill; it is withdrawn, and no
  conclusion about the gate's stability should be drawn from it. What does
  stand: a 78 556-declaration gate is expensive enough that running it in
  isolation from the report is still the better instrument.
* Consequence: the batch's `coverage_summary.json` remained the pre-refactor
  statement-keyed one from 22:30, preserved as
  `_bak_coverage_summary_preP3_statement_20260909_2230.json`. The follow-up
  coverage-only pass (`ndxcovC.scope`) was **stopped by the coordinator**
  before completing, for the same reason: the next summary for this batch
  will be produced under the co-evaluation semantics.
* The two `AliasAssumption` entries reach the summary correctly, verified in
  `_assumptions_declared.json` written by the engine's own serialiser: the
  loop alias carries `"key": "loop", "k": 1`, and the statement alias carries
  **no `k` field at all** — the serialisation-side half of §6's inertness
  claim, confirmed end to end rather than argued.
* None of §8's or §9's numbers depend on any of this: they come from
  `_exact_enum.py`, which computes its own universe.

## 11. Artefacts

* `_exact_enum.py` — this batch, with `ALIAS_OVERRIDE=statement|loop|off` so
  the same corpus can be measured under a different declaration without
  editing the batch.
* scratchpad `= /tmp/claude-1000/-home-dev-project/94ab9891-.../scratchpad/`:
  `exact_{statement,shipped,loop,half}.{log,json}` (per-clique census),
  `alias_loop.log` / `alias_loop_results.json` (the full-widening gate, 9 PASS
  / 4 FAIL), `alias_mixed.log` / `alias_mixed_results.json` (the shipped
  declaration, 16/16 PASS), `ndxcovB.log`, `ps_baseline_summary.json` /
  `ps_after_{1,2}.json` (the inertness diff).

## 12. What is left open for the owner

* The `to_ary` ×4 merge is refuted **as stated**. A narrower merge — plain with
  unread, typed with typed+unread, i.e. folding only the `unread` scope and
  keeping the TYPE apart — is the obvious next hypothesis, and the falsifier
  would decide it in one gate run. It was not tried here: that is tuning the
  shape definition, which the instruction forbade.
* The mentions loops fail at k=1 with the detail "NEEDS k=2". Re-declaring them
  at k=2 was likewise not done. Note that a k=2 claim still has to survive its
  own k+1 (=3-row) replay, and the `IN`-arity ruling means each new row is a
  new view, so the honest expectation is that it fails again.
* The root cause remains `call_interceptor.rb` naming a result by WHEN it was
  called. Fixing it there is a Rule T event; this refactor is deliberately not
  one.
