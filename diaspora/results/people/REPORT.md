# people batch — concolic re-run (prefix-directed DSE + batch-local targets)

Batch 12: `PeopleController`'s 6 entrypoints, driven through Rails' own
`ActionController::TestCase` rig against the real app. Regenerated 2026-08-15
with `run_dse.rb` + `targets.rb`.

- Runner: `run_dse.rb` (prefix-directed DSE, seed inheritance + single-branch
  flip, SAGE generational bound)
- Overlay: `targets.rb`, loaded AFTER `ConcolicTargets.install!`
- `src/` untouched, shared `concolic_targets.rb` untouched, app source untouched
- 40 dumps / 106 executions / 4.5 s for the whole batch; every dump parses

> **Provenance.** Reconstructed 2026-08-15 from the batch agent's own final
> report plus a re-measurement of the dumps on disk
> (`reports/diaspora/batch_stats.py people`). The agent finished and delivered
> its findings but was blocked from writing report `.md` files itself; the
> coordinator session that would have saved this file died first (dead provider
> pin, 01:12). Every number below was re-derived from the dumps.

## Results — BEFORE vs AFTER

| entrypoint | dumps | PCs | nodes | missing | complete | genuine | **both sides seen** | clean dumps | runs | drained |
|---|---|---|---|---|---|---|---|---|---|---|
| `people_index` | 1 → **25** | 0 → **203** | 0 → **39** | 0 | true | **VACUOUS → genuine** | 10 / 11 | 25 / 25 | 80 | yes |
| `people_show` | 8 → 5 | 31 → 20 | 7 → 6 | 0 | true | genuine | 4 / 6 | 5 / 5 | 14 | yes |
| `people_stream` | 4 → 4 | 10 → 10 | 4 → 4 | 0 | true | genuine | 3 / 4 | 4 / 4 | 5 | yes |
| `people_hovercard` | 5 → 3 | 14 → 6 | 4 → 3 | 0 | true | genuine | 2 / 3 | 3 / 3 | 4 | yes |
| `people_refresh_search` | 1 → 1 | 0 → 0 | 0 → 0 | 0 | true* | **VACUOUS** | 0 / 0 | 1 / 1 | 1 | yes |
| `people_retrieve_remote` | 2 → 2 | 0 → 0 | 0 → 0 | 0 | true* | **VACUOUS** | 0 / 0 | 2 / 2 | 2 | yes |
| **total** | 21 → **40** | 55 → **239** | 15 → **52** | **0** | 6/6 | 3/6 → **4 genuine, 2 vacuous** | **19 / 24** | **40 / 40** | 106 | 6/6 |

`*` complete only because the tree is empty — see Honest limits.

**Error dumps: 8 → 0.** Every `error` in the batch is gone, and none was
swallowed by mocking a branch. **0 unflippable PCs. All six worklists drained**
(`stop_reason: worklist_drained`, no cap hit).

### `complete=true` is the weakest number in that table

19 of 24 branch expressions are two-sided. The 5 that are not are listed under
Honest limits with the reason for each; four are `len(...)` nodes the solver
cannot parse at all, so `missing=0` on them means "both outcomes were observed
where they were observed", never "Z3 agreed". The load-bearing evidence for this
batch is **the drained DSE worklist with zero unflippable PCs**, not `missing=0`.

## What is in `targets.rb`

Moved out of `run_dse.rb` verbatim: `PersonSymAssociations` prepend (§1),
asset-path stub (§3), concrete `language`/`gender`/`guid` + current-user
association readers (§4). New in this round: NullRelation short-circuit (§2),
value-object subclasses (§5), per-run gon reset (§6).

**§4 and §6 are `module_function`s the runner calls, not `declare_target`s, and
the reason is load-bearing.** `symbolic_instance` installs column readers with
`define_singleton_method`, which beats both a class-level `define_method` (what
`declare_target` does) and any prepend. `users.language` **is** a column, so no
declared target could ever win — and `language` is not cosmetic: the real
`set_locale` before_action feeds it to i18n's `enforce_available_locales!`,
which crashes on a `SymbolicString` *before the action body runs*, walling every
authenticated entrypoint at 0 PCs.

### §2 — the NullRelation short-circuit, measured in isolation

Run as a standalone A/B first (the code move was behaviour-preserving:
`people_stream` came out byte-identical). Result: **8 → 2 error dumps** and
**15 → 12 tree nodes**.

Anonymous is the canonical scenario for `show`/`stream`/`hovercard`, so
`PersonPresenter` returns `Contact.none` / `Block.none`. `present?` →
`records.blank?`; the shared mock made that seedable, DSE flipped it TRUE, and
the app entered `contact_hash` / `BlockPresenter.new(...)` — **unreachable in
production** — then died with
`NoMethodError: id for #<Contact::ActiveRecord_Relation>`. `.none` is
`where("1=0").extending!(NullRelation)`, defined empty, issues no SQL, and has
no declared target beneath it. The concrete empty result is a sound
over-approximation.

Measured **3 phantom nodes, not 4** (`show` −2 = `has_contact?` + `is_blocked?`;
`hovercard` −1 = `has_contact?`), and **6 error dumps removed, not 4** (4 ×
Contact + 2 × Block).

Two things worth knowing for whoever generalises this:

- **`none?: true` is included here, which `photos/targets.rb` §4 omits.** A
  NullRelation has no elements, so `none?` must short-circuit true. `photos`
  never reaches it; `people` does.
- **`next []` does not reach the app as a plain Array.** `CallInterceptor`
  re-wraps every native return (`call_interceptor.rb:174-180`), so the app gets
  a zero-length `SymbolicList`. The PC is still recorded, pinned to the empty
  side; only the infeasible TRUE subtree is gone. Right outcome, but by accident
  rather than by design.

### §5 — both named walls closed without touching `src/`

**`SymbolicString#year` → `ConcolicDate` (§5a).** A real `::Date` subclass whose
`#year` is a seedable symint, wired via a batch-local alias around
`ConcolicTargets.symbolic_instance`. `bday.year <= 1004` now **records**
`(SYM_PROFILE_PERSON_birthday_year <= 1004)` instead of crashing. Subclassing
`::Date` rather than wrapping keeps `Date === obj`, `I18n.l` and `strftime`
intact. `birthday_format` stayed unmocked — its body *is* the branch.

**`SymbolicList#each`/`#map` → `IterableSymbolicList` (§5b),** yielding
`@representative` once when `concrete_length != 0` — the same Gate 1b
sampled-row semantics `#first`/`#last`/`#[0]` already implement.
`hashes_for_people` stayed unmocked (its body calls `contact_for` → SQL).

### `include Enumerable` was tried, measured, and removed

`IterableSymbolicList` initially did `include Enumerable`, copied from
`photos/targets.rb` §6b. The `notifications_tags` and `streams` batches proved
that a module included into a subclass inserts **above** the superclass, so
`Enumerable#any?` shadows the PC-recording `SymbolicList#any?` — in `streams`
that silently took all 8 entrypoints from genuine to VACUOUS (72 PCs → 0) while
`complete` stayed `true`.

This batch was re-run both ways and diffed, not assumed:

| | WITH `include Enumerable` | WITHOUT |
|---|---|---|
| `people_index` | 25 dumps / **203** PCs | 25 dumps / **203** PCs |
| `people_show` | 5 / 20 | 5 / 20 |
| `people_stream` | 4 / 10 | 4 / 10 |
| `people_hovercard` | 3 / 6 | 3 / 6 |
| `people_refresh_search` | 1 / 0 | 1 / 0 |
| `people_retrieve_remote` | 2 / 0 | 2 / 0 |
| **TOTAL** | **239** | **239** (delta +0) |

Per-entrypoint dump counts and a per-expression `Counter` of every PC string
across all 40 dumps were compared — **byte-identical, not one expression changed
multiplicity**. So **203 is the true figure for `people_index`**, not a shadowed
one.

**Why this batch was not exposed.** The shadow set is exactly:

```
any?, count, first, include?, none?     <- Enumerable would shadow these
empty?                                  <- Enumerable does NOT define it
```

Every `SymbolicList`-derived PC here is `(len(...) != 0)` — 31 of 239 — and all
of them come from `empty?`, reached through `Relation#blank?` →
`records.blank?` → `present?`. `Enumerable` has no `empty?`, so there was
nothing to shadow. That is a property of the paths *currently reached*, not a
guarantee, which is exactly the argument for keeping the include out rather than
reinstating it as harmless. **`include Enumerable` is removed and stays
removed**, with a comment at `targets.rb:239` explaining the hazard and
crediting the `notifications_tags` finding.

## `people_index`: 0 → 203 PCs, and the two walls behind it

It did not stay vacuous, but it took two more walls, each uncovered only by
clearing the previous one:

1. **`NoMethodError: gon for nil`.** `GonHelper#gon_load_contact` uses the
   CLASS-level `Gon`, not the `gon` helper the shared file stubs. `Gon.preloads`
   → `current_gon.gon[...]` → `RequestStore.store[:gon]`, which the
   controller-test rig never populates. §6 installs a real `Gon::Request` **per
   run** — it *must* reset, because RequestStore is thread-local and nothing
   clears it, so a surviving `preloads[:contacts]` would leak rows between runs
   and turn `stored_contact[:person][:id] == contact.person_id` into a cross-run
   symbolic comparison. §6 also pre-seeds `preloads => {}`, reproducing what
   `ApplicationController#gon_set_preloads` does in production — that assignment
   currently lands on the shared `gon_stub` instead of on the store the
   class-level `Gon` reads.

2. **`Querying#find_by_sql` (`concolic_targets.rb:514`)**, reached via AR's
   statement cache from `ContactPresenter#full_hash`'s `aspect_memberships.map`.
   **Two defects at once**: no `representative:` (so even the iterable subclass
   cannot yield), *and* a hard-coded length that never calls `seed_for` — the
   exact inert-mock antipattern. Re-declared batch-locally with both fixed.
   **This single mock is what took `people_index` from 1 PC to 203.**

## Runner fix — `flip_seed` could not flip `<=`

Once `ConcolicDate` made the birthday branch record, it showed up as **34
unflippable PCs** (30 in `index`, 4 in `show`) — a genuinely unexplored TRUE
side. `flip_seed` was extended with integer ordering (`<=`/`<`/`>=`/`>` → exact
boundary assignment; every PC this app emits compares a var to a literal, so it
is exact, not heuristic) and with `StringVal('...')` / `!=` literals.
**`unflippable_pcs` is now empty across the batch.**

## Honest limits

**Two entrypoints remain VACUOUS, and `complete=true` on them means nothing**
(the execution tree is empty):

- **`people_refresh_search`** — Ruby truthiness gap. `unless @people.empty?`
  gets a `SymbolicBool`, which is a truthy object even when it wraps `false`, so
  the entire action body is dead and no PC is recorded. This is *not* a
  missing-method wall and the subclass technique does not reach it: Ruby
  truthiness is not overridable, `false` is a singleton, and `CallInterceptor`
  re-wraps every native return, so a declared target physically cannot hand the
  app a raw `false`. Recording the PC from inside the mock while the app takes
  the other side would **fabricate** a branch. Left open and reported. The same
  gap silently forces `background_search(...) if @people.empty?` in `index`.
- **`people_retrieve_remote`** — structurally branch-free: the only `if` is on a
  plain request parameter. Both dumps are on disk taking opposite sides; neither
  can record a PC because there is no symbolic value in the action. No runtime
  fix changes this — it needs parameter enumeration, not DSE.

**Five one-sided branch expressions** (from `batch_stats.py`, solver-independent):

| entrypoint | expression | site |
|---|---|---|
| `people_hovercard` | `(len(SYM_RESULT_..._Relation_records_1) != 0)` | `active_support/.../blank.rb:20` |
| `people_index` | `(len(SYM_RESULT_..._Relation_records_2) != 0)` | `blank.rb:20` |
| `people_show` | `(len(SYM_RESULT_..._Relation_records_1) != 0)` | `blank.rb:20` |
| `people_show` | `(len(SYM_RESULT_..._Relation_records_2) != 0)` | `blank.rb:20` |
| `people_stream` | `(SYM_RESULT_..._first_1_guid != StringVal(''))` | `journey/formatter.rb:41` |

The `people_stream` one is the **UNSAT-by-construction** case flagged in
`COMPLETENESS_AUDIT.md`: it sits under a `(guid == '')` prefix, so the other
side is genuinely unreachable and Z3 pruning it is correct. The four `len(...)`
ones are the solver-blind case — the engine drops the query and reports
`missing=0` either way.

**The checker under-reports, and it was only caught because DSE disagreed.**
`concolic_engine/solver.py` cannot parse `len(...)` constraints (`name 'len' is
not defined`, 31 of 239 PCs here). When an unparseable constraint sits in a
node's *prefix*, the Z3 query is dropped — not counted as missing, and **not
counted in `solver_lost` either** (it reads 0 everywhere). Concretely: while
`birthday_year <= 1004` was still unflippable, its TRUE side was genuinely
unexplored and the checker reported `missing=0` anyway.

## `src/` gaps to raise to Bali (worked around batch-locally, NOT patched)

1. `symbolic_instance`'s `define_singleton_method` column readers cannot be
   overridden by any `declare_target` or prepend — every batch re-pays this.
2. `SymbolicString` has no date semantics; a `date`/`datetime` column reader
   hands the app a string, and `#year` raises.
3. `SymbolicList#each`/`#map` raise even when a `representative:` is present,
   although `#first`/`#last`/`#[0]` honour it.
4. `Querying#find_by_sql` (`concolic_targets.rb:514`) has no `representative:`
   and a hard-coded length that never calls `seed_for` — an inert mock that
   creates *uncoverable* branches.
5. Engine: `len(X)` var decls fail to eval, `len(...)` constraints fail to
   parse, and `coverage.py` treats "solver could not parse it" as "the missing
   side is unsatisfiable" while leaving `solver_lost` at 0.
6. Ruby truthiness gap (`src/TODO.txt`) — the cause of both vacuous entrypoints.

## Files

```
results/people/
├── targets.rb                  BATCH-LOCAL overlay (PeopleTargets.install!)
├── run_dse.rb                  runner
├── coverage_report.py          per-entrypoint checker (wraps concolic_engine)
├── run_concolic.rb             previous-round runner, kept as input
├── exploration_summary.json    batch-level roll-up of the 6 DSE runs
├── elapsed_seconds.txt
└── <entrypoint>/
    ├── dump_*.json             one per DISTINCT path (+ per root-knob variant)
    ├── exploration_summary.json
    └── coverage_summary.json   this entrypoint's runs ONLY
```

Reproduce:

```
scripts/diaspora-concolic /home/dev/project/reports/diaspora/results/people/run_dse.rb
cd /home/dev/project && PYTHONPATH=src python3 \
    reports/diaspora/results/people/coverage_report.py
PYTHONPATH=src python3 reports/diaspora/batch_stats.py people
```
