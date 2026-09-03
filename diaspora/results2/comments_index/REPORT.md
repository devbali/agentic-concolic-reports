# results2/comments_index — rerun with symbolic entrypoint arguments

(Report authored by the batch agent; saved by the coordinating session.)

## Acceptance test — PASSED

`params[:post_id]` is a symbolic string (`SYM_PARAM_post_id`, seed "5").
Quoted from `dump_dse0001.json`:

```
"note": "SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"id\" = $$(SYM_PARAM_post_id)"
```

A genuine `$$()` bind — the original `results/comments/` batch recorded the
concrete literal `'5'` here.

## New genuine branch exposed by the symbolic param

`PostService#post_key` does `id_or_guid.to_s.length < 16 ? :id : :guid`. With
a concrete String this records nothing; with `SymbolicString`, `.length`
returns a SymbolicInt `Length(SYM_PARAM_post_id)` and the compare records a
PC. The runner's flip helper (`flip_length_seed`, local to `run_dse.rb`)
inverts `(Length(VAR) OP N)` by reseeding VAR with a string of the needed
length. This surfaced the sibling lookup, also with a real bind:

```
"note": "SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"guid\" = $$(SYM_PARAM_post_id)"
```

## Coverage

- 6 dumps (`dse0001/0002/0004/0006/0007/0008`), 15 runs executed (9 deduped),
  worklist **drained** (`worklist_exhausted: true`, `stack_remaining: 0`,
  `unflippable_pcs: {}`), 0.7s elapsed.
- Full 2×3 cross-product of the two decision points
  (`length<16` × `{not_found, non_public, found}`).
- `CoverageChecker`: `coverage_complete: true`, `tree_nodes: 5`,
  `missing_branches: 0`, `total_path_conditions: 16`, `solver_lost: 0`.
- **All 6 dumps genuine** (≥1 PC each); none vacuous.

## Errors / walls

Every dump has `"error": null`. The two `RecordNotFound` dumps (`dse0004`,
`dse0006`) are the app's real 404 path (`rescue_from` → `head :not_found`),
not a framework wall.

## Pinned values

None. `comments_index` is anonymous (`before_action :authenticate_user!,
except: :index`); `current_user` is nil on this path, so no user/person/guid
identity exists to pin or symbolize. The source batch's `symbolic_user`
helper (with its `person.id = 1` pin) was dropped entirely — nothing in this
flow invokes it.

## Mocks

All 5 mocks in the ported `targets.rb` are unchanged from the source batch;
3 fired on this path (`IterableSymbolicList` for `records.map`, `Person.none`
for `people_from_string`, the asset-path stub for `AvatarPresenter`), 2 are
unreached here (`BelongsToPolymorphicAssociation`, `SuccIntValue` — only hit
via create/destroy; harmless to keep). No new wall-fix mocks were needed.

## Files

`concolic_targets.rb` (private copy), `targets.rb`, `run_dse.rb`,
`dump_*.json` ×6, `exploration_summary.json` (includes the symbolic params
map), `coverage_summary.json`, `coverage_report.py`. Nothing outside this
directory was modified.

---

## ADDENDUM (2026-08-18): completed under combination-coverage semantics

Coverage sections above are superseded. Authoritative state (fresh checker
run reproduces): `coverage_complete: true, truncated: false, solver_lost: 0,
unevaluable_exprs: [], assumptions_used: 1`.

- **Runner bug found & fixed**: `symstr("SYM_PARAM_post_id", ...)` ran
  BEFORE `$interceptor.run`, whose `SymbolicFunc.reset!`
  (call_interceptor.rb:262) wipes registered vars — so the param var was
  missing from every dump's symbolic_vars and the Length-dispatch PC sat in
  unevaluable_exprs, silently shrinking the demand universe. Fixed by
  declaring the param inside the run body; dumps regenerated (same 6 paths,
  worklist drained, now with the var declared).
- True universe: one 3-clique {length<16, not_found, public} with 4 real
  missing combos (not_found=True × length × public), all structurally
  unobservable: post_service.rb:51-55 raises RecordNotFound before
  `post.public?`, and finder_mock returns nil without ever instantiating
  the `_public` var (empirically: zero `_public` events in the
  not_found=True dumps). Closed by ONE argued
  `IndependenceAssumption(not_found ⊥ public)` in coverage_assumptions.py;
  the split 2-cliques are fully covered by the 6 runs.
- Old dumps backed up under the batch scratch dir for diffing.
