# streams batch — concolic re-run (prefix-directed DSE + batch-local targets)

Batch 13: `StreamsController`'s 8 stream entrypoints, driven through Rails' own
`ActionController::TestCase` rig against the real app. Regenerated 2026-08-15
with `run_dse.rb` + `targets.rb`.

- Runner: `run_dse.rb` (prefix-directed DSE; `MODE=explore` does one default run
  per entrypoint per format; `OVERLAY=0` = shared targets only, for baselines)
- Overlay: `targets.rb` (`StreamsTargets.install!`, loaded AFTER
  `ConcolicTargets.install!`)
- Launched via `/home/dev/.claude/jobs/302ac302/tmp/concolic-slot`
- `src/` untouched, shared `concolic_targets.rb` untouched, app source untouched
- 57 dumps / 95 executions / 4.8 s for the whole batch; every dump parses

## Results — BEFORE vs AFTER (2026-08-15 re-run with `targets.rb`)

Two honest baselines, both re-measured with the same checker
(`coverage_check.py`, a thin wrapper over `concolic_engine.CoverageChecker`):

| | dumps | PCs | nodes | missing | complete | genuine | **branch exprs with BOTH sides seen** | clean dumps |
|---|---|---|---|---|---|---|---|---|
| **A. shared targets only** (`OVERLAY=0`) | 15 | 14 | 11 | 0 | 8/8 | 8/8 | **1 / 9** | 11 / 15 |
| **B. previous round** (runner-local decls, 2026-08-14) | 25 | 36 | 19 | 0 | 8/8 | 8/8 | 9 / 9 | 9 / 25 |
| **C. THIS run** (overlay) | **57** | **108** | **23** | **0** | **8/8** | **8/8** | **11 / 11** | **49 / 57** |

Per entrypoint (C; B in parentheses where it differs):

| entrypoint | dumps | PCs | nodes | missing | complete | genuine / vacuous | runs | roots | drained | dump errors |
|---|---|---|---|---|---|---|---|---|---|---|
| `streams_aspects` | 12 (6) | 24 (12) | 5 | 0 | true | genuine | 22 | 4 | yes | 4 × `StatementInvalid` |
| `streams_multi` | 20 (6) | 48 (6) | 6 (2) | 0 | true | genuine | 36 | 8 | yes | 4 × `StatementInvalid` |
| `streams_public` | 5 (3) | 6 (3) | 2 | 0 | true | genuine | 7 | 3 | yes | — |
| `streams_activity` | 4 (2) | 6 (3) | 2 | 0 | true | genuine | 6 | 2 | yes | — |
| `streams_commented` | 4 (2) | 6 (3) | 2 | 0 | true | genuine | 6 | 2 | yes | — |
| `streams_liked` | 4 (2) | 6 (3) | 2 | 0 | true | genuine | 6 | 2 | yes | — |
| `streams_mentioned` | 4 (2) | 6 (3) | 2 | 0 | true | genuine | 6 | 2 | yes | — |
| `streams_followed_tags` | 4 (2) | 6 (3) | 2 | 0 | true | genuine | 6 | 2 | yes | — |
| **total** | **57** | **108** | **23** | **0** | 8/8 | **8 genuine, 0 vacuous** | 95 | 25 | 8/8 | 8 |

Every `exploration_summary.json` has `worklist_exhausted: true`,
`stopped_by: null` — a true fixpoint in every entrypoint, no cap hit
(`MAX_RUNS=900`, `TIME_BUDGET=420 s`; the batch takes 4.8 s).

What changed:

- **6 of 8 entrypoints are now completely error-free** (were: `SymbolicList#map`
  in every one). Clean dumps 9/25 → 49/57; 49 dumps reach `render`.
- **`streams_multi` tripled**: 6 → 20 dumps, 6 → 48 PCs, 2 → 6 nodes, and it
  acquired a **second** genuine branch (`Post.excluding_blocks` is reached twice:
  via `followed_tags_posts!` and via `ids! -> for_a_stream`), both sides covered.
  It went from **no clean run at all** to 16 clean runs.
- **One wall class left**: the SQLite `UNION ALL` failure (8 dumps, aspects +
  multi, real-query root only) — environment, not mocking.

### `complete=true` is the WEAKEST number in that table

The engine cannot parse `len(...)`; `check_satisfiability` returns UNSAT and
`coverage.py`'s `if not result.satisfiable: continue` **silently drops** the
missing branch, so a ONE-SIDED `len(...)` node still reports
`complete=true, missing=0`. Baseline A proves it: 7 of its 8 entrypoints have a
one-sided branch and all report complete. That is why every table here carries
**"branch exprs with both sides seen"**, computed from the dumps and independent
of the solver: baseline A scores 1/9, this run scores 11/11. `solver_lost: 0`
everywhere means "Z3 never weighed in", not "Z3 agreed".

## `targets.rb` — what is in it and why

| # | target | shape | why legal | bought |
|---|---|---|---|---|
| 0a | `IterableSymbolicList < SymbolicList` | adds `#each`/`#map`, yields the representative once | same "one sampled row" semantics `#first`/`#last`/`#[0]` already implement | killed the ×9 `SymbolicList#map` wall |
| 0b | `QuotableSymbolicInt/String` | add `#value_for_database` | `Quoting#quote` consults it before the class-based `_quote` | symbolic binds quote as their concrete half |
| 0c | adapter `_quote`/`_type_cast` unwrap | prepended to the live connection class | pure SQL rendering, records nothing | route where `quote` gets the raw value |
| 0d | `QueryAttribute#value_for_database` unwrap | prepended | unwraps, then runs Rails' REAL type serialization | killed the multi `can't quote` / `to_i` wall |
| 1 | `Post.blocked_people` | length-**seedable** `IterableSymbolicList`, representative = quotable person_id | body is `user.blocks.map(&:person_id)` — SQL-free; the `where(... NOT IN (?))` stays in `excluding_blocks` | **the branch every entrypoint has** |
| 2 | `Stream::Aspect#aspect_ids` → `nil` | was `[1]` | pure transform; `nil` is the one value the interceptor passes through unchanged | killed 2 × `can't quote SymbolicList` |
| 3 | `User#has_hidden_shareables_of_type?` → concrete seeded bool | prepend, guarded by `concolic_attrs` | body is a pure Hash read; the `if` is at the CALL SITE | true side of `excluding_hidden_shareables` executes at last |
| 4 | `User#aspect_ids` / `#followed_tag_ids` → `[1]`, `#followed_tags` | prepend, guarded | `pluck` unsupported by design; enclosing SQL stays real | multi gets past its first line |

**Nothing here swallows the branch it guards**: for #1 the `if people.any?` is in
`Post.excluding_blocks`, for #3 the `if` is in `Post.excluding_hidden_shareables`
— call sites, not the mocked bodies.

**#1 was the missing-`seed_for` anti-pattern.** The shared §I mock
(`concolic_targets.rb:560`) returns a hard-coded `[]`, which
`call_interceptor.rb:181` (`to_symbolic`) re-wraps into a length-0 SymbolicList —
and that wrap never consults `seed_for`. DSE generated the flip, ran the child,
and the mock ignored it. Baseline A is what that costs: 1 of 9 branch
expressions two-sided.

**#3/#4 are prepends, not `declare_target`s, on purpose.** `to_symbolic` turns a
mock's `true`/`false` into a SymbolicBool (always truthy at a bare `if`, records
nothing) and an `Array` into a SymbolicList (unquotable by Arel — bug #2 again).
Consequence, stated plainly: these three do not appear as symbolic calls in the
dumps.

### A regression I caused and fixed (measured, not guessed)

The first `IterableSymbolicList` did `include Enumerable` (copied from
`photos/targets.rb` §6b). Enumerable sits ABOVE `SymbolicList` in the ancestor
chain, so `Enumerable#any?` shadowed the PC-recording `SymbolicList#any?`:
`people.any?` silently iterated and **all 8 entrypoints went from genuine to
VACUOUS — 72 PCs → 0 PCs — while `complete` stayed `true` for all 8.** Fixed by
defining only `#each`/`#map`. Any batch reusing that snippet on a list whose
`any?`/`count`/`first` carries the branch will hit this.

### Deliberately NOT in `targets.rb`

`User#visible_shareables` / `#visible_shareable_ids` — their bodies ARE the SQL.
The `SUBSTITUTE_USER_VISIBLE_QUERIES` knob replaces them, and precisely because
that replaces real app SQL it stays an **explicit non-default root knob** in
`run_dse.rb`. Both variants are explored as separate DSE roots and every dump
records which produced it (`seed_index.json`).

## Method

The interceptor names symbolic results with a per-run call ordinal
(`SYM_RESULT_<func>_<idx>`, `call_interceptor.rb:140`), so those names are not
stable across runs — flipping an early branch renumbers every later var. Feeding
`CoverageChecker.concrete_values` back wholesale as `seed_overrides` (what
`run_concolic_seeds.rb` in this directory did) is therefore unsound. Instead
each child run inherits its parent's seed dict (prefix replays identically → those
ordinals stay valid) and adds exactly one flip for one PC. Dedup on the path
signature plus the non-symbolic root knobs; expand until the worklist drains.

**Format = JSON only.** In `MODE=explore` all eight actions were run in both
`:json` and `:html`. Every html run recorded **0 path conditions**: the html
branch of `stream_responder` calls `render 'streams/main_stream'`, the terminal
render marker (§Z), so `@stream.stream_posts` — the only branchable work — is
never evaluated. Html runs would only have added vacuous dumps.

**Root knobs** (recorded in each `seed_index.json`, kept in the dedup signature
so each variant keeps a dump):

| knob | entrypoints | why |
|---|---|---|
| `SIGNED_IN` | streams_public | `GET /public` is the one action with `except: :public`; anonymous and signed-in execute different code (`for_a_stream` skips `excluding_hidden_content` when user is nil) |
| `USER_GETTING_STARTED` | streams_multi | `if current_user.getting_started` is a truthiness-gap branch |
| `USER_HAS_HIDDEN_SHAREABLES` | all signed-in roots | NEW: drives overlay target #3; truthiness gap, so no PC can ever flip it |
| `SUBSTITUTE_USER_VISIBLE_QUERIES` | streams_aspects, streams_multi | with the real `User::Querying#visible_shareables*` the run hits the SQLite `UNION ALL` wall; the substituted variant reaches downstream real app code. An explicit variant, never the default |

## What the branch surface actually is

Only two app branches in the whole batch record path conditions:

1. **`Post.excluding_blocks`** — `if people.any?` (`app/models/post.rb:93`),
   reached by **all eight** entrypoints via
   `Post.for_a_stream → excluding_hidden_content`. Expr
   `(len(SYM_RESULT_Anonymous_blocked_people_N) != 0)`. In `streams_multi` it is
   reached TWICE per run (`followed_tags_posts!` and `ids! -> for_a_stream`), so
   that entrypoint has two independent instances, both two-sided.
2. **`Stream::Aspect#for_all_aspects?`** — `aspects.size == user.aspects.size`
   (`lib/stream/aspect.rb:80`), aspects only. Both operands are real intercepted
   `Relation#size` queries, so this node is fully seedable and both sides are
   covered.

A third PC per true-side run is the *same* expression re-recorded by ActiveRecord
itself (`Sanitization#quote_bound_value` calls `empty?` on the bind value before
mapping it); it collapses into a nested duplicate node, which is why `nodes` (23)
exceeds the number of distinct branch sites.

> **Reconciliation with `COMPLETENESS_AUDIT.md` (added 2026-08-15).** That audit
> keys branch expressions by source **site** `(expr, file, lineno)` and therefore
> scores this batch **10 / 19**, not the 11 / 11 above, which keys by
> **expression**. The difference is exactly the duplicate described in this
> paragraph: all 9 site-keyed one-sided entries are
> `active_record/sanitization.rb:205`, always `taken: true` only — verified
> site-by-site across all 8 entrypoints. It can only ever execute on the true
> side, because the `NOT IN (?)` clause is only built when `people.any?` was
> true, so it is **UNSAT by construction** and is the justified note the audit
> asks for. Neither number is wrong; the site-keyed one is stricter, and
> `reports/diaspora/batch_stats.py streams` reproduces it.
>
> The audit's first published explanation for these — the SQLite `UNION ALL`
> wall — was incorrect and has been corrected there: those 8 dumps crash before
> any branch and so record no PC at all, which cannot make an expression
> one-sided.

The surface is small because of the landed §I split: the JSON response goes
through the mocked `StreamsController#decorated_stream_posts`, which is exactly
where the stream relation would have been *materialized*. The relation is built
for real (`where`/`joins` chains) but mostly never executed, so SQL traceability
for this batch is thin — there is little query *result* to trace. Only three
query targets fire in clean runs: `Relation#size` ×2 in aspects (the
`for_all_aspects?` operands) and `SingularAssociation#find_target` ×2 per run in
multi (`person.owner` in `where_person_is_mentioned`) — the latter only became
reachable once the quoting walls were closed.

## Solver caveat on the list-length nodes

The engine cannot parse the `len(...)` PCs; for every entrypoint the checker
prints:

```
Failed to eval var decl 'len(SYM_RESULT_Anonymous_blocked_people_1) = Int('len(...)')':
    cannot assign to function call here
Failed to parse constraint '(len(SYM_RESULT_Anonymous_blocked_people_1) != 0)':
    name 'len' is not defined
```

So for those nodes `complete=true` means **both outcomes were observed** — the
strict per-node condition, which this run does satisfy for all 11 branch
expressions — but **no Z3 reasoning backs it**, and a one-sided node would be
reported the same way (see the BEFORE/AFTER section). `solver_lost: 0` everywhere.

## Every `error` in every dump

**49 of 57 dumps are clean and reach `render`** (was 9 of 25). All 8 remaining
errors are a single wall, and **none is a real app outcome** (no
`RecordNotFound` — none of these actions has a 404 path under the symbolic user):

| error | dumps | where | classification |
|---|---|---|---|
| `ActiveRecord::StatementInvalid` — SQLite `near "(": syntax error` | 8 (4 aspects, 4 multi) | `User::Querying#visible_shareable_sql` → `connection.select_values`, real-query root only | **ENVIRONMENT wall.** Diaspora emits `(SELECT …) UNION ALL (SELECT …) ORDER BY … LIMIT …`; SQLite rejects a parenthesised compound SELECT (the app targets MySQL/PostgreSQL). Fires **before** any branch → these 8 dumps have 0 PCs. Needs a MySQL/Postgres-backed `concolic` database: **infrastructure, not mocking**, and not fixable from `targets.rb` |

Walls present in the previous round and now **gone**:

| gone wall | count before | how |
|---|---|---|
| `NotImplementedError: SymbolicList#map` (`sanitization.rb:205 quote_bound_value` sanitising `where("posts.author_id NOT IN (?)", people)`) | 9 | overlay §0a. It fired *after* the PC, so the branch was already covered — but everything downstream of `excluding_blocks` on the true side was unreachable. Now `NOT IN (1)` renders and the request completes |
| `TypeError: can't quote SymbolicList` (Arel, real `visible_shareables`, aspects) | 2 | overlay #2 (`aspect_ids -> nil`) |
| `TypeError: can't quote SymbolicInt` (Arel `visit_Arel_Nodes_Or`, `EvilQuery::MultiStream`) | 2 | overlay §0c + §0d |

The multi wall took **two** fixes, and the intermediate state is worth recording:
with §0c alone the error merely MOVED, from `TypeError: can't quote …`
(`quoting.rb:179`) to `NotImplementedError: SymbolicInt#to_i` (`int.rb:30`) at the
same call site — because a **typed** bind attribute answers `value_for_database`
first (`Type::Integer#serialize -> Helpers::Numeric#cast -> cast_value ->
value.to_i`) and never reaches the adapter. §0d unwraps inside the bind attribute
and then lets Rails' real serialization run on the concrete value. That is
deliberately narrower than teaching symbolic ints `#to_i`: app code calling
`.to_i` still raises loudly instead of silently losing tracking.

`streams_multi` used to have **no clean run at all**; it now has 16 clean runs
out of 20 dumps, and its 4 SQLite dumps are the real-query root.

**Vacuous dumps: 5 of 57** — the 4 SQLite ones in multi plus
`streams_public/dump_dse0007` (the anonymous root: `Post.for_a_stream` skips
`excluding_hidden_content` when `user` is nil, so there is genuinely no branch).
**No entrypoint is vacuous.**

## Branches the runtime cannot record at all (truthiness gap, `src/TODO.txt`)

1. `if current_user.getting_started` (`streams_controller.rb:33`) and
   `Stream::Multi#welcome?`/`#publisher_opts` — bare truthiness. A `SymbolicBool`
   there is always truthy and records nothing, so the runner returns a concrete
   bool from the `USER_GETTING_STARTED` knob. Both sides really were executed
   (4 of multi's 6 dumps) but neither is a recorded branch.
2. `if user.has_hidden_shareables_of_type?` (`post.rb:111`) — bare `if`. Before
   this round it could only ever be **false**, because `symbolic_instance` pins
   `User#hidden_shareables` to a plain `{}` (`concolic_targets.rb:277`), so the
   true side of `excluding_hidden_shareables` never executed. Overlay target #3
   makes it a seeded CONCRETE bool and the true side now executes — verified
   out-of-band: the guarded scope renders as
   `SELECT "posts".* FROM "posts" WHERE (posts.id NOT IN (NULL))`. Two honest
   caveats: (a) it is still not a recorded PC, and (b) the bind is NULL because
   `hidden_shareables` is a singleton method installed by `symbolic_instance`
   and cannot be overridden from a prepended module — the true side EXECUTES,
   its bind value is degenerate. The two knob variants therefore produce
   identical PC sequences and near-identical dumps: those extra dumps document
   executability, not new coverage (and are what doubles the dump count
   alongside multi's real growth).
3. `if user.present?` in `for_a_stream`, `if stream_klass.present?` in
   `stream_responder`, `if params[:a_ids].present?` in `save_selected_aspects` —
   decided on concrete values.
4. `AppConfig.settings.community_spotlight.enable? && user.show_community_spotlight_in_stream?`
   — the config operand is concrete-false, so the second operand (a
   boolean-column predicate reader, which *would* record) short-circuits.

## Runner-local (still in `run_dse.rb`, deliberately NOT in the overlay)

1. **`SUBSTITUTE_USER_VISIBLE_QUERIES` knob** (`visible_shareables → Post.all`,
   `visible_shareable_ids → [1]`). This *replaces app SQL*, which the wall-fixing
   discipline forbids for a mock, so it is **not the default** and was **not**
   promoted into `targets.rb`: both variants are explored as separate roots and
   every dump records which produced it. (The old `run_concolic.rb` here applied
   the `Post.all` substitution unconditionally and silently.)
2. **`@all_calls` trimmed per run** — `CallInterceptor` keeps an unbounded call
   history across runs (a `src/` concern).
3. Devise/auth plumbing: `StubWarden`, `current_user`/`user_signed_in?`
   singletons, concrete `user.id`/`person_id`/`person` (identity columns are fed
   into real WHERE clauses).

Everything else that used to live here — the seedable `Post.blocked_people`,
`user.aspect_ids`/`followed_tag_ids`, `followed_tags` — moved into `targets.rb`.

## `src/` gaps to raise to Bali (worked around batch-locally, NOT patched)

Each of these was closed for this batch by a subclass or a batch-local prepend in
`targets.rb`; they remain runtime gaps every other batch keeps re-paying.

1. **`to_symbolic` re-wraps a mock's `Array` return into a `SymbolicList`**
   (`call_interceptor.rb:165-181`) and Arel cannot quote one — so any mock whose
   value reaches a real WHERE must return `nil`. Bites shared §I rows 4-5.
2. **A `SymbolicList` from that wrap has a length no seed can change** (the wrap
   never consults `seed_for`) — it silently creates *uncoverable* branches. This
   is what left all 8 streams entrypoints half-covered.
3. **`SymbolicList#map`/`#each` raise even when a `representative:` is present**,
   although `#first`/`#last`/`#[0]` honour it. Inconsistent.
4. **Symbolic scalars are unquotable by ActiveRecord**: no `#value_for_database`
   and no `#to_i`, so any symbolic value reaching a bind kills the request in
   `Quoting#_quote` or `Type::Integer#cast_value`.
5. **`Calculations#pluck` unsupported** ⇒ every AR association ids_reader
   (`user.aspect_ids`, `user.followed_tag_ids`) is a wall.
6. **Engine: `len(X)` var decls fail to eval and `len(...)` constraints fail to
   parse**, so all list-length PCs are invisible to Z3 — and `coverage.py` treats
   "solver could not parse it" as "the missing side is unsatisfiable" and reports
   `complete=true`. A one-sided `len(...)` node is indistinguishable from a
   covered one in `coverage_summary.json`. The most misleading behaviour in the
   pipeline.
7. **Ruby truthiness gap** (`src/TODO.txt`) — see the section above.
8. `CallInterceptor` retains `@all_calls` for the whole process (unbounded growth).

## Files

```
results/streams/
├── targets.rb                  BATCH-LOCAL overlay (StreamsTargets.install!)
├── run_dse.rb                  runner (MODE=explore|dse, OVERLAY=0|1, RESULTS_DIR=)
├── coverage_check.py           per-entrypoint checker (wraps concolic_engine)
├── run_concolic.rb             previous-round runners, kept as inputs
├── run_concolic_seeds.rb         (the unsound seed-suggestion loop)
├── exploration_summary.json    batch-level roll-up of the 8 DSE runs
├── coverage_index.json         batch-level roll-up of the 8 coverage checks
├── coverage_index_baseline_no_overlay.json   baseline A (OVERLAY=0)
├── elapsed_seconds.txt
└── <entrypoint>/
    ├── dump_dseNNNN.json       one per DISTINCT path (+ per root-knob variant)
    ├── seed_index.json         label -> {seeds, pcs, error}
    ├── exploration_summary.json
    └── coverage_summary.json   this entrypoint's runs ONLY
```

Reproduce:

```
/home/dev/.claude/jobs/302ac302/tmp/concolic-slot \
    /home/dev/project/reports/diaspora/results/streams/run_dse.rb
cd /home/dev/project && PYTHONPATH=src python3 \
    reports/diaspora/results/streams/coverage_check.py \
    reports/diaspora/results/streams
```
