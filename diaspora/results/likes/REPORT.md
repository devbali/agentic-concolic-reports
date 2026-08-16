# likes batch — concolic re-run (prefix-directed DSE + batch-local targets)

Batch 11: `LikesController#create/destroy/index`, driven through Rails' own
`ActionController::TestCase` rig against the real app. Regenerated 2026-08-15
with `run_dse.rb` + `targets.rb`.

- Runner: `run_dse.rb` (prefix-directed DSE, seed inheritance + single-branch flip)
- Overlay: `targets.rb`, loaded AFTER `ConcolicTargets.install!`
- `src/` untouched, shared `concolic_targets.rb` untouched, app source untouched
- 18 dumps / 1161 executions / 15.2 s for the whole batch; every dump parses

> **Provenance.** This report was reconstructed on 2026-08-15 from the batch
> agent's own final report plus a re-measurement of the dumps on disk
> (`reports/diaspora/batch_stats.py likes`). The agent finished its work and
> delivered its findings, but was blocked from writing report `.md` files
> itself; the coordinator session that would have saved this file died before
> it got to this batch (dead provider pin — see the parent session's failure at
> 01:12). Every number below was re-derived from the dumps, not copied.

## Results — BEFORE vs AFTER

BEFORE = `LIKES_WA_FIX=0 LIKES_WB_FIX=off` (shared targets only), which
reproduces the previous round exactly.

| entrypoint | dumps | PCs | nodes | missing | complete | genuine | **both sides seen** | clean dumps | runs | drained |
|---|---|---|---|---|---|---|---|---|---|---|
| `likes_create` BEFORE | 12 | 40 | 9 | 0 | true | genuine | 5 / 5 | 7 / 12 | 1125 | yes |
| `likes_create` **AFTER** | 12 | 40 | 9 | 0 | true | genuine | **5 / 5** | **11 / 12** | 1125 | yes |
| `likes_destroy` BEFORE/**AFTER** | 3 | 5 | 2 | 0 | true | genuine | 2 / 2 | 2 / 3 | 27 | yes |
| `likes_index` BEFORE/**AFTER** | 3 | 5 | 2 | 0 | true | genuine | 2 / 2 | 1 / 3 | 9 | yes |
| **total AFTER** | **18** | **50** | **13** | **0** | 3/3 | **3 genuine, 0 vacuous** | **9 / 9** | **14 / 18** | 1161 | 3/3 |

3/3 complete, 3/3 genuine, 0 missing, every worklist drained to a true fixpoint
(`stop_reason: worklist_drained`, no `MAX_RUNS`/`TIME_BUDGET` hit,
`unflippable_pcs` empty everywhere). Batch wall clock 18.1 s → 15.2 s.

**What the overlay bought:** every remaining `error` in the batch is now a real
app outcome. Zero framework walls left (`NotImplementedError` ×4 → ×0).

**What it did not buy: any new coverage.** PCs, nodes, dump labels and the
distinct-PC vocabulary are identical across the two configurations. Both walls
sat *after* the last branch on their path — `.next` is inside `like!`'s `tap`
after every recorded decision, and `.to_i` is inside the JSON renderer after
`respond_to` has dispatched. This was a wall-closing pass, not a coverage pass;
the batch was already at its fixpoint before it.

Cost: **+9,431 bytes across all 18 dumps (+2.6 %)**. Only the 4 previously
crashed dumps grew (`html0002`/`0013`/`0020` +1,734 each, `json0001` +4,226);
the ±2-byte wobble elsewhere is JRuby object-id noise in `inspect` strings,
verified by diffing event streams.

### `complete=true` is the weakest number in that table

Per `COMPLETENESS_AUDIT.md`: the engine cannot parse `len(...)`, so a one-sided
list-length node is reported identically to a covered one, and `solver_lost`
stays 0 either way. The column that carries the weight here is **both sides
seen — 9 / 9**, computed from the dumps and independent of the solver, together
with the drained worklist and the empty `unflippable_pcs`.

## `targets.rb` — what is in it and why

| # | target | shape | why legal | bought |
|---|---|---|---|---|
| W-A | `SuccIntValue < SymbolicInt` with `#next`/`#succ`/`#pred` | batch-local subclass, wired in by wrapping `ConcolicTargets.symbolic_instance` | `SymbolicInt#-@` (`int.rb:78`) is the precedent: derive a new named symbolic value, don't concretize | closed the `SymbolicInt#next` wall without a `src/` change |
| W-B | `prepend` shim on `ActiveModel::Type::Integer#cast`/`#deserialize` | returns a `SymbolicInt` unchanged, `super` otherwise | pure type-cast plumbing; records nothing, issues no SQL | closed the `SymbolicInt#to_i` wall **while keeping the value symbolic** |
| — | `SymbolicInt#to_i` (rejected default) | kept behind `LIKES_WB_FIX=to_i` | — | see the soundness measurement below |

Neither is a `declare_target` mock, so neither adds a `symbolic_call` event or
an inert call-ordinal var to any dump.

### W-A — why no app-method mock was legal

`update_or_create_participation!` is the smallest enclosing method, but it
issues SQL (`participations.find_by`), calls another declared target, and holds
both of its own branches. Mocking it would have deleted the coverage along with
the wall — the exact regression the wall-fixing discipline forbids. Everything
further out issues more SQL. Hence the value-shaped fix.

**One wiring correction worth propagating to other batches:**
`participation.count` does **not** reach `ActiveRecord::Calculations#count`.
`symbolic_instance` installs a *singleton* reader per column
(`concolic_targets.rb:229`) that shadows every class-level method, so the value
comes straight from the instance's `concolic_attrs`. Hooking only
`Calculations#count` — as `photos/targets.rb` §6c does — would not have closed
this. The overlay wraps `symbolic_instance` batch-locally and re-wraps each
integer column var as a `SuccIntValue` **with the same name, value and note**,
so it stays the same seedable var; the `Calculations#count` override is kept for
relation receivers. Also: `module_function` keeps **two** copies of a method and
`ConcolicTargets`' internal callers use the singleton copy — a wrapper must
replace both.

### W-B — the `declare_target` route was not merely expensive, it was unimplementable

`declare_target` natively-converts args before the lambda sees them
(`call_args[name] = to_native(val)`, `call_interceptor.rb:123`;
`to_native(SymbolicInt) → Integer`, `symbolic_func.rb:177`), so a `cast_value`
lambda receives `{"value" => 1}` and **cannot tell symbolic from plain**. Its
return would then be re-wrapped as
`to_symbolic(result, name: "SYM_RESULT_..._cast_value_<n>")`
(`call_interceptor.rb:181`), minting an inert call-ordinal var on every integer
attribute read and severing `like.author_id` from `SYM_PERSON_LKC_id`. The
dump-bloat worry that motivated looking at it is moot — that route was never
viable.

**The tiebreak between the two viable fixes is soundness, and it was measured**
(probe: one boot per mode):

| mode | `like.author_id` after AR's cast | PCs from a later `like.author_id == 7` |
|---|---|---|
| `cast` (default) | `SuccIntValue` — still symbolic | **1** — `(SYM_PROBE_id == 7)` |
| `to_i` | plain `Integer` — concretized | **0** — branch silently lost |
| `off` | raises | 0 — lost loudly |

`to_i` re-opens the implicit-concretization channel that `int.rb:25-32` closes
deliberately, for *every* `.to_i` on those values. It costs `likes` nothing
today only because nothing branches on `author_id` after the cast — luck, not
design, and the failure mode is silent. **Verdict: `cast` is better; delivered
as the default, `to_i` kept behind `LIKES_WB_FIX=to_i`.**

This is the "don't mock away the branch" rule at *value* level: a value-shaped
fix can swallow a branch just as thoroughly as a method-shaped one.

## W-C — `NoMethodError: post_id for #<Like>` is an app defect, kept

`likes_controller.rb:26`: `format.mobile { redirect_to post_path(like.post_id) }`.

Verified: `schema.rb:178-190` gives `likes` only `target_id`/`target_type`
(polymorphic); `lib/diaspora/fields/target.rb` declares
`belongs_to :target, polymorphic: true`; `like.rb` aliases only `parent` →
`target`; grep over `app/` and `lib/` finds no `post_id` attribute, alias or
method on `Like`. **This raises for every like, symbolic or real — the mobile
branch of `likes#create` is dead code that 500s in production.**

Repro: `likes_create/dump_mobile0001.json`. Correct app fix would be
`post_path(like.target_id)`. Not applied — app source is out of scope for a
batch runner.

## Termination fix — please port to the reference runner

`run_dse.rb`'s `other_value` maps integer flips into **`{0, 1}`**, not `v + 1`.

With `v + 1`, `likes_destroy`'s
`(SYM_PERSON_LKD_id == SYM_RESULT_..._find_1_author_id)` — two *symbolic* vars —
makes each generation seed a fresh integer, so the seed space is infinite over a
3-path space: measured **4000 executions / 3 paths, worklist still growing**.
With `{0, 1}` it drains in **375** (`likes_create`, per scenario) and **27**
(`likes_destroy`).

This is not a `likes` quirk — **any `VAR_A == VAR_B` PC triggers it**, and
`tmp/reference/run_proper.rb`'s flip helper has the `v + 1` shape. Recommend
porting.

## Every `error` in every dump

14 of 18 dumps are clean. All 4 errors are **real app outcomes**; there is no
`NotImplementedError` anywhere in the batch.

| error | dumps | where | classification |
|---|---|---|---|
| `NoMethodError` | 1 (`likes_create`, mobile) | `likes_controller.rb:26` | **app defect** — W-C above |
| `ActiveRecord::RecordNotFound` | 1 (`likes_destroy`) | finder mock, real 404 path | real app outcome |
| `Diaspora::NonPublic` | 1 (`likes_index`) | `find_public!` | real app outcome |
| `ActiveRecord::RecordNotFound` | 1 (`likes_index`) | `find_public!` | real app outcome |

Execution counts (350 / 9 / 4 / 3) exceed dump counts because DSE re-reaches
known path signatures; only new ones are persisted.

## Branches the runtime cannot record at all

1. **Ruby truthiness gap** (`src/TODO.txt`) hides `foreign_key_present?` and
   `participation.present?`. Their *decision* is still covered — via the
   seedable `..._not_found` bool at the finder-mock boundary — but the `if`
   itself contributes no node.
2. **Concrete-receiver gap**: `SYM_PERSON=1` is required, or the batch's only
   cross-var branch vanishes.
3. `ctrl.send(action)` bypasses `process_action`, so `authenticate_user!` and
   the `rescue_from Diaspora::NonPublic` handler never run — which is why
   `NonPublic` surfaces as a dump error rather than a re-auth redirect.
4. Format dispatch is request-driven, so the three `likes#create` formats are
   separate worklists, not a flippable branch.

## Inert shared mocks found (not blocking here, but they will block others)

`concolic_targets.rb:508` returns `symbool("#{name}_#{m}_ok", true, ...)` for
`save`/`save!`/`update`/`update!`/`destroy`/… **with no `seed_for`** — DSE can
never flip a persistence outcome. Harmless in `likes` (`LikeService#destroy`
returns literal booleans; no PC references an `_ok` var) but it is the same
shape as the `Photo#url` anti-pattern and **would block any batch branching on
a save result**. Lines 480 and 518 (`update_all`/`delete_all`/`count_by_sql`
counts) share the missing `seed_for`.

## Runner-local (deliberately not in the overlay)

`run_dse.rb` clears `CallInterceptor#@all_calls` after each run. The interceptor
appends a `TargetCall` per call and never trims, OOMing the JVM over thousands
of executions. The dump is already built when `run()` returns, so no recorded
output changes. This is a `src/` concern — reported, not patched.

## `src/` gaps to raise to Bali (worked around batch-locally, NOT patched)

1. `SymbolicInt` has no `#next`/`#succ` although `#-@` establishes the
   derive-a-new-named-value pattern.
2. Symbolic scalars are unquotable/uncastable by ActiveRecord — no
   `#value_for_database`, and `Type::Integer#cast_value` calls `.to_i`.
3. `declare_target` natively-converts args (`call_interceptor.rb:123`), so a
   mock **cannot** distinguish a symbolic argument from a concrete one.
4. Shared persistence mocks (`concolic_targets.rb:480/508/518`) never call
   `seed_for`, making their results unflippable by construction.
5. `CallInterceptor` retains `@all_calls` for the whole process.
6. Engine: `len(X)` var decls fail to eval and `len(...)` constraints fail to
   parse, and `coverage.py` treats "solver could not parse it" as "the missing
   side is unsatisfiable".
7. Ruby truthiness gap (`src/TODO.txt`).

## Files

```
results/likes/
├── targets.rb                  BATCH-LOCAL overlay (LikesTargets.install!)
├── run_dse.rb                  runner
├── coverage_check.py           per-entrypoint checker (wraps concolic_engine)
├── run_concolic.rb             previous-round runner, kept as input
├── exploration_index.json      batch-level roll-up of the 3 DSE runs
├── coverage_index.json         batch-level roll-up of the 3 coverage checks
├── elapsed_seconds.txt
└── <entrypoint>/
    ├── dump_*.json             one per DISTINCT path (+ per format scenario)
    ├── exploration_summary.json
    └── coverage_summary.json   this entrypoint's runs ONLY
```

Reproduce:

```
scripts/diaspora-concolic /home/dev/project/reports/diaspora/results/likes/run_dse.rb
cd /home/dev/project && PYTHONPATH=src python3 \
    reports/diaspora/results/likes/coverage_check.py
PYTHONPATH=src python3 reports/diaspora/batch_stats.py likes
```

Switches: `LIKES_WA_FIX=0`, `LIKES_WB_FIX=cast|to_i|off`, `OUT_DIR`, `EP`,
`SYM_PERSON`. `LIKES_WA_FIX=0 LIKES_WB_FIX=off` reproduces the BEFORE column
exactly.
