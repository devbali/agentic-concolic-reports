# results2/people_show — rerun with symbolic entrypoint arguments

(Report authored by the batch agent; saved by the coordinating session.)

## Scenario

Single scenario ported from `../../results/people/`: `anon_handle`
(GET /people/:id, PeopleController#show, anonymous,
`params[:username] = "bob@example.org"`). The source batch documents that
people_show never had a signed-in scenario (signed-in walls on
`mark_corresponding_notifications_read`'s `SymbolicList#each`).

## Acceptance test — PASSED

`dump_anon_handle_0001.json` (and every true-branch dump):

```
SELECT "people".* FROM "people" WHERE "people"."diaspora_handle" = $$(SYM_PARAM_username)
```

`params[:username]` is `SYM_PARAM_username` (a `SymUsernameString <
SymbolicString`), seeded "bob@example.org".

**Pagination/bind-rotation check:** people#show issues no LIMIT/OFFSET
queries at all (grepped every note across all 10 dumps) — the historical
rotation bug lived on people#index's `.paginate`; nothing to regress here.
`concolic_targets.rb` is the fixed copy (byte-identical to
`results2/conversations_index/`'s, diffed to confirm).

## Walls closed (runner-local, targets.rb §B)

Symbolic `params[:username]` exposed two walls absent with a concrete param:

1. `PeopleController#diaspora_id?` crashes on `.lstrip`/`.downcase`
   (SymbolicString UNSUPPORTED). SQL-free leaf → mocked as a boundary
   decision mirroring the shared `finder_mock` pattern: the real
   `Validation::Rule::DiasporaId` logic runs on the concrete seed, and the
   outcome is a seedable `symbool` `SYM_DECISION_diaspora_id_username` —
   genuinely flippable.
2. `downcase` / `blank?` (`=~`) on the value: `SymUsernameString` overrides
   `downcase` as identity (seed already lowercase) and `blank?`/`present?`
   with a concrete seed check (the documented Ruby-truthiness gap).

Plus the known `User#person` association gap on symbolic instances, closed
with a one-method prepend (same pattern as people/targets.rb §1). All other
PeopleTargets mocks ported verbatim.

## Exploration & coverage

- 28 runs, 10 distinct-path dumps, **worklist drained**
  (`worklist_exhausted: true`) in 1.0s; MAX_RUNS/TIME_BUDGET nowhere near.
- 0 run errors, 0 unflippable PCs; all 10 dumps genuine (50 PCs total).
- Both sides of every branch observed, including
  `SYM_DECISION_diaspora_id_username` true/false and the
  not-found/closed-account/empty-photos/public-profile/birthday branches.
- `coverage_summary.json`: **coverage_complete: true, 13 tree nodes,
  0 missing branches, 0 assumptions** (none declared).

## Minor observation (cosmetic, not fixed)

`User.find_by_username`'s note renders as the generic
`"User query (class-level finder), args=args=nil"` fallback (sql_for's
pre-existing behavior for class-level dynamic finders) instead of SQL with a
`$$(SYM_PARAM_username)` bind. The not_found PC is still symbolic and
flippable; only the note is generic.

---

## ADDENDUM (2026-08-18): completed under combination-coverage semantics

Coverage sections above are superseded by the engine rewrite. Current
authoritative state (fresh checker run reproduces it):
`coverage_complete: true, truncated: false, solver_lost: 0,
unevaluable_exprs: [], assumptions_used: 29, 9/9 exprs checkable`.

- No new exploration was needed and the 10 dumps are byte-unmodified: the
  reachable state space, derived by hand from people_controller.rb:129-141
  (+rescue_from :17-27) and person_presenter.rb, is exactly the 10 observed
  paths; the 128 cap-raised "missing" combos were all guard-foreclosed
  cross-products.
- 27 expr-keyed IndependenceAssumptions (if/else exclusivity, sequential
  guard raises, guard×presenter foreclosure) + 2 OneSideUntracked whose
  untracked (non-empty) side was disproven BY EXECUTION (probe forcing the
  length seed to 3 still recorded taken:false — Rails NullRelation
  overrides the mock in the anonymous scenario). All 29 carry source/probe
  citations in coverage_assumptions.py.
- `len(X)` pseudo-vars are alpha-renamed to `SYM_LEN_X` at dump-load time in
  coverage_report.py (pure surface-syntax; no semantic change), moving both
  length exprs from unevaluable_exprs INTO the checked universe.
- Genuinely dependent pairs (dispatch×profile-stage, length×profile) were
  left demanded and are covered by observed combos.
