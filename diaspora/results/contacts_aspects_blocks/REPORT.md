# Batch `contacts_aspects_blocks` — concolic re-run WITH batch-local targets

Regenerated 2026-08-15. Runner `run_dse.rb`; new overlay `targets.rb`. Launched
only via `concolic-slot`. **`src/`, the shared `concolic_targets.rb`, and the app
source were not modified.**

## Headline

| | BEFORE | AFTER |
|---|---|---|
| dumps (distinct paths) | 43 | **160** |
| path conditions | 89 | **984** |
| tree nodes | 32 | **151** |
| missing branches | 0 | **0** |
| entrypoints complete | 13/13 | **13/13** |
| genuine / vacuous | 12 / 1 | **12 / 1** |
| worklists drained | 13/13 | **13/13** (no cap fired) |
| `NotImplementedError` | 0 | **0** |
| harness failures | 0 | **0** |
| PC `(expr,taken)` pairs LOST vs BEFORE | — | **0** |

That last row is the anti-regression check: every `(expression, taken)` pair seen
in the BEFORE dumps is still present in the AFTER dumps for the same entrypoint.
Nothing was mocked away. 831 DSE executions, 13.7 s total.

## Per entrypoint (BEFORE → AFTER)

| entrypoint | dumps | PCs | nodes | missing | complete | genuine | runs | drained |
|---|---|---|---|---|---|---|---|---|
| contacts_index | 2 → 2 | 2 → 2 | 1 → 1 | 0 | true | genuine | 3 → 3 | yes |
| community_spotlight | 1 → 1 | 0 → **0** | 0 → 0 | 0 | true* | **VACUOUS** | 1 → 1 | yes |
| aspects_create | 3 → **31** | 5 → **269** | 2 → **30** | 0 | true | genuine | 9 → 233 | yes |
| aspects_show | 2 → 2 | 2 → 2 | 1 → 1 | 0 | true | genuine | 3 → 3 | yes |
| aspects_update | 2 → **3** | 2 → **5** | 1 → **2** | 0 | true | genuine | 3 → 6 | yes |
| aspects_destroy | 3 → **7** | 5 → **23** | 2 → **6** | 0 | true | genuine | 9 → 21 | yes |
| aspects_update_order | 3 → **7** | 5 → **23** | 2 → **6** | 0 | true | genuine | 9 → 22 | yes |
| aspects_toggle_chat_privilege | 5 → **7** | 12 → **20** | 4 → **6** | 0 | true | genuine | 57 → 20 | yes |
| aspect_memberships_create | 3 → **51** | 5 → **401** | 2 → **50** | 0 | true | genuine | 9 → 315 | yes |
| aspect_memberships_destroy | 5 → **8** | 12 → **30** | 4 → **7** | 0 | true | genuine | 27 → 30 | yes |
| blocks_create | 7 → **22** | 23 → **135** | 6 → **21** | 0 | true | genuine | 81 → 121 | yes |
| blocks_destroy | 3 → **6** | 7 → **23** | 4 → **9** | 0 | true | genuine | 9 → 19 | yes |
| share_visibilities_update | 4 → **13** | 9 → **51** | 3 → **12** | 0 | true | genuine | 15 → 37 | yes |
| **total** | **43 → 160** | **89 → 984** | **32 → 151** | **0** | 13/13 | 12 / 1 | 235 → 831 | 13/13 |

`*` complete only because the tree is empty — **not covered**.
`aspects_toggle_chat_privilege` shows fewer runs but more paths (57 → 20 runs,
5 → 7 paths): that is the duplicate-path pruning below, not lost coverage.

## The mechanism, and one discovery that changes the recipe

All four results are consumed in bare-truthiness position, so each mock mints a
seedable symbolic bool, **records `(VAR == True)` itself**, and returns a value
whose Ruby truthiness matches — the `col?` predicate-reader pattern.

**A mock cannot return a concrete `false`.** `CallInterceptor#declare_target`
(`src/ruby_runtime/call_interceptor.rb:170-186`) pushes every
`TrueClass`/`FalseClass` mock result through `to_symbolic`, which re-wraps it as
a `SymbolicBool` — truthy again. `nil` is the only falsey value `to_symbolic`
passes through unchanged (`symbolic_func.rb:151-155`). So the mocks return
`true` / **`nil`**. The PC is recorded either way.

**Raise to Bali:** the clean fix is for the interceptor to pass a mock's explicit
`false` through unwrapped. **This single behaviour is why every bare-truthiness
branch in this batch was dead.**

## The four mocks — and whether each OPENS or swallows

Verified two ways: (a) an ablation run with the mock disabled, (b) both sides of
its PC family actually explored.

| mock | PC family | true / false | before | measured effect |
|---|---|---|---|---|
| **1. `User#mine?`** | `_mine` | 9 (7 T / 2 F) | **0 — never recorded** | *ablation-measured*: `aspect_memberships_destroy` 6→8 dumps, 17→30 PCs, 5→7 nodes; every other entrypoint numerically identical. 2 `Diaspora::NotMine` dumps → the 403 branch |
| **2. persistence + `delete`** | `_ok` | 157 (103 T / 54 F) | **0** | affects 9 entrypoints; `head :unprocessable_entity` reached (5 `save_ok=false` paths, one a 1-PC path straight to the 422) |
| **3. `exists?`/`any?`/`empty?`** | `_exists` etc. | 220 (59 T / 161 F) | **0** | `aspect_memberships_create` 3→51 dumps / 5→401 PCs / 2→50 nodes — the endpoint's whole success path was dead before |
| **4. `Base#delete`** | `_delete_ok` | 5 (4 T / 1 F) | **0** | contained entirely in `blocks_destroy` 3→6 / 7→23 / 4→9; `blocks.destroy.failure` reached |

Every family is non-zero on **both** sides, i.e. each mock produced a real
two-way node instead of pinning the app to one side. None of the four encloses
the `if` that produces its own PC. (`mine?`'s real body is
`self.id == target.user_id`, a compare that **cannot** record, because the rig's
`current_user` has a concrete id — so `1 == SymbolicInt` hits `Integer#==`
silently. The mock *adds* the branch the real body cannot express.)

Ablations for persist/exists/delete were queued but cancelled: ~21 concolic-slot
jobs were contending for 2 memory slots, and attribution is already unambiguous
from the disjoint PC families and entrypoint sets above.
`CAB_DISABLE_MOCKS=mine,persist,exists,delete,blocks,castable_int` is retained in
`targets.rb` so they stay reproducible.

Two further defects in the shared persistence mock: it hard-coded `true` with
**no `seed_for`** (the "permanently inert var" anti-pattern — DSE emitted the
flip, the mock ignored it), and its `!`-variant var names (`..._save!_ok`) are
**not legal Z3/Python identifiers**, so the engine logs `Failed to eval var decl`
and no seeder could ever have flipped them. Both fixed batch-locally.

## Two walls the fixes exposed — closed, not left open

- **`User#blocks` → real `Relation`.** With `share_with` alive, `contact.valid?`
  reaches `Contact#not_blocked_user` (`app/models/contact.rb:100`) →
  `user.blocks.where(...).exists?`, where `user` is `contact.user` — a symbolic
  User **without** the runner's singleton. The shared length-only `SymbolicList`
  gave `NoMethodError: where` in **113 of 400** smoke runs. Same override and
  reasoning as `photos/targets.rb` §3, and still cannot be shared (streams/posts
  need the list shape). Caveat: drops the association's
  `WHERE blocks.user_id = ?` scope.
- **`CastableSymbolicInt < SymbolicInt`.**
  `find_or_initialize_by(person_id: person.id)` builds a **real** Contact holding
  a `SymbolicInt`; `valid?` → `belongs_to.foreign_key_present?` →
  `ActiveModel::Type::Integer#cast_value` → `to_i` → `NotImplementedError`
  (44 of 227 runs). Fixed by giving the **value** the shape the app expects
  rather than mocking the consumer (`valid?` holds the app's own validation
  branches). `to_int` deliberately left raising — that is the implicit-coercion
  channel. Result: **0 `NotImplementedError` in the final 160 dumps.**

## One runner change

`run_dse.rb` no longer re-expands a path signature it has already seen (only the
inherited seed dict differs; the prefix replays identically and that path's flips
were queued the first time). Without it the deeper trees make the frontier grow
as O(branching^depth): the first smoke of `aspect_memberships_destroy` went from
"drains in 27 runs" to "400 runs, 8 paths, **not drained**". With it, all 13
worklists drain. `duplicate_path_runs` is now recorded in each
`exploration_summary.json` (264 of 315 on the largest entrypoint).

## Errors in the final 160 dumps — all real app outcomes

| error | n | where | classification |
|---|---|---|---|
| `NoMethodError … for false`/`for nil` | 20 | `aspects_controller.rb:93` | **Real.** `share_with` returns `false` (invalid contact) / `nil` (blocked); the controller has no guard → 500 in production too. BEFORE, the `nil` variant was mock-induced; it is now a faithful app state |
| `NoMethodError … for nil` | 5 | `aspects_controller.rb:33/60/76` | **Real** — no nil guard when the aspect lookup misses |
| `ActiveRecord::RecordNotFound` | 11 | finder mock, from 7 app call sites | **Real** — the 404 path; two caught by the controller's own `rescue_from` |
| `Diaspora::NotMine` | 2 | `aspect_memberships_controller.rb:19` | **Real, newly reachable** — the 403 branch mock 1 unlocked |
| `AssociationTypeMismatch` | 2 | `user/connecting.rb:21` | **Real, newly reachable** — a nil `@aspect` passed into `share_with`; production behaves identically |
| `NotImplementedError` | **0** | — | — |
| harness failures | **0** | — | — |

Errors rose 17/43 → 40/160 (40% → 25% of dumps). Deeper exploration simply
reaches more of the app's own error paths.

## Honest remaining limits

1. **Truthiness gap persists wherever the value is not mock-produced.** Still
   dead: `if current_user.auto_follow_back && …` (`aspects_controller.rb:33`) and
   `if receiving && user && …` (`contact.rb:100`) — boolean *columns* read
   without `!`/`==`. Columns spelled `col?` do record (that is why
   `chat_enabled` is a real node).
2. **Mocks still cannot return concrete `false`** (worked around with `nil`; the
   fix belongs in `call_interceptor.rb`).
3. **`SymbolicInt#to_int` still raises** by design; no implicit coercion was hit.
4. **No view rendering** — `community_spotlight` has no branch outside its view,
   so it stays vacuous and no mock can change that.
5. **One request shape per entrypoint** — contacts#index's `format.mobile`/`json`
   arms and the no-`person_id` arm of aspects#create are param-space, not
   path-condition, coverage.
6. **`User#blocks` renders unscoped SQL** here.

Also still open (pre-existing, worked around runner-locally): `CallInterceptor`
retains an unbounded `@all_calls` history across runs, and the engine still logs
`Failed to eval var decl 'len(X) = …'` for `SymbolicList` length vars.

## Files

`targets.rb` (new, 6 sections), `run_dse.rb` (+dup-path pruning), 13 ×
`<ep>/{dump_dseNNNN.json, exploration_summary.json, coverage_summary.json}`,
2 group roll-ups. Reproduce with
`EPS=… MAX_RUNS=4000 TIME_BUDGET=600 concolic-slot …/run_dse.rb`, then the
per-entrypoint coverage check. Before-state snapshot preserved at
`/home/dev/.claude/jobs/302ac302/tmp/cab_before_dumps/`.
