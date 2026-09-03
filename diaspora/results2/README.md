# results2 — reference-endpoint reruns with fully symbolic entrypoint arguments

## THE DISCIPLINE (read first)

Concolic execution has exactly **two tools** — (1) mocks, only at SQL-free
leaves whose bodies call no other target, with the real SQL rendered into
every query-standing mock's `note`; (2) assumptions, only with code-cited
arguments that the exempted combination can produce no target call or SQL
shape the covered ones don't. Full statement and the wall-closing procedure:
main `../README.md` §THE DISCIPLINE. Every mock and assumption in results2
is subject to audit against it (`MOCK_AUDIT.md` is the mock ledger;
violations — e.g. the historical render/`as_api_response` no-ops — are
findings to fix via `MOCK_FIDELITY_BRIEF.md`, never conveniences to keep).

Rerun of the six entrypoints that have reference per-endpoint policies
(`ruby_examples/dse-apps/policies/extracted/diaspora/per-endpoint/`), fixing
the harness gap found while diffing against them: **entrypoint arguments must
be symbolic** (see main `../README.md` §"Symbolic entrypoint variables"). The
original batches pinned request params (`params: { post_id: "5" }`) and often
`user.id = 1`, so user/param identity never reached the recorded SQL as
symbolic binds.

## Layout — one self-contained directory per entrypoint

```
results2/<entrypoint>/
├── concolic_targets.rb    ← PRIVATE COPY of ../concolic_targets.rb (edit freely here)
├── targets.rb             ← batch-local overlay, ported from the source batch
├── run_dse.rb             ← runner for THIS entrypoint only
├── dump_*.json            ← run dumps (in the entrypoint dir itself)
├── exploration_summary.json  ← MUST include the params map incl. symbolic names
├── coverage_summary.json
└── REPORT.md              ← honest per-entrypoint report
```

| entrypoint | port from |
|---|---|
| comments_index | `../results/comments/` |
| conversations_index | `../results/conversations/` |
| notifications_index | `../results/notifications_tags/` |
| people_show, people_stream | `../results/people/` |
| posts_show | `../results/posts/` |

## Symbolic-arguments requirements (the point of this rerun)

1. **Request params**: every param value becomes a symbolic var named
   `SYM_PARAM_<key>` (e.g. `SYM_PARAM_post_id`), seeded with the old concrete
   value — `symstr` for string params, `symint` for integer ones (top-level
   runtime methods; `symstr`/`symint`/`symbool` are NOT ConcolicTargets
   methods). Verify in the dumps that param-driven queries render
   `$$(SYM_PARAM_<key>)` binds via `sql_for`, not concrete literals.
2. **current_user**: remove any `define_singleton_method(:id) { 1 }` pin —
   `symbolic_instance` already provides a SymbolicInt id (`SYM_USER_<tag>_id`),
   and `sql_for` renders it as `$$(SYM_USER_<tag>_id)`.
3. **user.person / person.id**: try symbolic first. If it hits the known AR
   integer-cast wall (`SymbolicInt#to_i` when the id is written into a record
   as a foreign key), pin it back and DOCUMENT the wall in REPORT.md.
4. Other pinned identity attrs (`guid "abc123"`, `diaspora_handle`): attempt
   symbolic; keep the pin only where a wall forces it, and document.
5. **Association scoping**: where the old batch wired unscoped relations
   (`user.contacts → Contact.all`, `visibility.messages → Message.all`, …),
   prefer the scoped real relation so the recorded SQL keeps its
   `user_id`/`conversation_id` WHERE clause; if the real association cannot
   load on a symbolic instance, scope the mock relation manually
   (e.g. `Contact.where(user_id: user.id)`) so the symbolic user id lands in
   the SQL as a `$$()` bind. Document any place this is impossible.

Everything else follows the main README verbatim: framework-level targets,
wall-fixing discipline (smallest SQL-free leaf, never mock the query),
prefix-directed DSE (inherit parent seeds + flip exactly one branch — seeding
whole CoverageChecker suggestions is unsound, see the var-naming caveat),
per-entrypoint coverage with `coverage_summary.json`, loud/honest errors.

**Completion requirement:** every entrypoint directory MUST end with a
`coverage_summary.json` reporting `coverage_complete: true` (same shape as
`comments_index/coverage_summary.json`). Where strict per-node coverage
cannot be closed by exploration (unflippable branches, recurrences,
boundary-only outcomes), declare engine assumptions to make completeness
explicit rather than leaving it false — `UntrackedPathAssumption` /
`IndependenceAssumption` keyed by **expr** (not file:line; see main README
§"Declaring assumptions"). Every assumption used must be listed in the
summary's `assumptions` field and justified in REPORT.md — an assumption is
a documented claim, not a cover-up.

## Known fix to carry forward

The conversations_index rerun found the root cause of the long-standing
bind-rotation render bug: JRuby's `Object#instance_variables` does not
preserve assignment order for `Arel::Nodes::SelectStatement`, so
`collect_binds` in `concolic_targets.rb` emitted paginated queries
(`.paginate` → LIMIT/OFFSET) with WHERE binds swapped into the LIMIT/OFFSET
slots. Fix: explicit SQL-order traversal for `SelectStatement`/`SelectCore`
— see `results2/conversations_index/concolic_targets.rb` (`collect_binds`).
**Every new entrypoint dir should copy its `concolic_targets.rb` from that
fixed version** (or port the fix into its private copy) rather than from the
shared `../concolic_targets.rb`.

## Operational limits

- `JRUBY_OPTS=-J-Xmx1000m`; ONE JRuby process per agent at a time; launch via
  `/home/dev/project/scripts/diaspora-concolic <abs path to run_dse.rb>`.
- Other memory-heavy jobs may be running on the box — check `free -h` before
  starting; do not start a run with < 1.2Gi available.
- Kill only PIDs you started (runners all share names across batches).
- Trim the interceptor's `@all_calls` history between runs (unbounded-growth
  bug — see the source batches' runners for the workaround).

## Downstream

`src/queries_from_runs` already understands the new dumps: `$$(SYM_PARAM_*)`
binds are dropped from emitted queries (broadened over the param, matching the
reference format), `$$(SYM_USER_*_id)` renders as `_MY_UID`.
