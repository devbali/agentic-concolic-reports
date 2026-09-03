# results2/notifications_index — rerun with symbolic entrypoint arguments

(Report authored by the batch agent; saved by the coordinating session.)

## Acceptance tests — PASSED (quoted from dumps)

- `dump_plain_dse0001.json`:
  `SELECT "notifications".* FROM "notifications" WHERE "notifications"."recipient_id" = $$(SYM_USER_NI_id)`
- Pagination (`dump_unread_only_dse0007.json`, page=2/per_page=5):
  `... WHERE "notifications"."recipient_id" = $$(SYM_USER_NI_id) AND "notifications"."unread" = true ORDER BY updated_at desc LIMIT 5 OFFSET 5`
  — binds in the right slots; the bind-rotation bug is absent (fixed
  `collect_binds` verified present in the private `concolic_targets.rb`).
- Rescoped unread relation: `... recipient_id = $$(SYM_USER_NI_id) AND unread = true`.

## What the old runner got wrong (root cause of the bad reference diff)

1. `symbolic_user` pinned `user.id = 1` and `person.id = 1` — recipient
   scoping could never record a symbolic bind.
2. `user.unread_notifications → Notification.all` — completely unscoped;
   every count/group_by query lost `recipient_id`.
3. All request params concrete, and driven through `tc.process(...)` which
   Rack-serializes params (would have defeated symbolic params anyway).

## This rerun

- `user.id` pin removed (flows symbolic); `person.id` unpinned too but
  genuinely unreached on index (no SYM_PERSON refs in any dump).
- `unread_notifications` rescoped: `Notification.where(recipient_id: user.id,
  unread: true)`.
- `params[:show]` symbolic (`SYM_PARAM_show`) — the entrypoint's only branch
  point, genuinely flippable.
- `params[:type]/[:page]/[:per_page]` kept concrete after LIVE wall probes
  (transcripts real, script at the batch scratch dir): `Hash#has_key?` →
  `SymbolicString#eql?` NotImplementedError; WillPaginate `Integer(value)` →
  `SymbolicInt#to_int`; `per_page.to_i` → `SymbolicInt#to_i`. Documented
  per spec item 4.
- Action invoked directly (`ctrl.send(:index)`) to avoid Rack param
  serialization — side effect: devise/locale before_actions never run, so no
  warden stub needed.

## Coverage

```json
{"endpoint": "notifications_index", "coverage_complete": true, "tree_nodes": 1,
 "missing_branches": 0, "total_runs": 6, "total_path_conditions": 6,
 "genuine": true, "vacuous": false, "dump_errors": {},
 "assumptions": [], "assumptions_used": 0}
```

6 dumps, all genuine; the single PC `(SYM_PARAM_show == StringVal('unread'))`
observed both ways; worklist drained in 0.3s at full caps. Zero errors.
The entrypoint truly has one branch: the shared render mock no-ops the
`_notification.haml` partial (whose `note.type == "Notifications::..."`
branch would otherwise be symbolic) — a framework-wide render wall, not
closable from a batch.

## Runner bug found & fixed while porting

The ported `flip_seed`/`parse_literal` didn't unwrap `StringVal('...')`
literals from `SymbolicString#==` PCs, so string PCs were silently
unflippable (first smoke test pinned all runs to the seed `show` value).
Fixed by porting the `StringVal(...)`/`IntVal(...)` unwrap from the
posts_show/comments_index runners; both `show` outcomes then explored.

---

## ADDENDUM (2026-08-18): completed under combination-coverage semantics

The "hollow complete" above is fixed. Authoritative state (fresh checker
run reproduces): `coverage_complete: true, truncated: false,
solver_lost: 0, unevaluable_exprs: [], missing: [], assumptions: []` —
complete on a REAL universe, zero assumptions.

Root cause of the hollowness: `CallInterceptor#run` calls
`SymbolicFunc.reset!` at start (call_interceptor.rb:261-262), erasing any
`symstr` registration made before `run` — the runner built SYM_PARAM_show
pre-run, so it never reached the dumps' symbolic_vars and its PC was
unevaluable. Fixed by moving the param construction inside the run body;
dumps regenerated (9 runs, 6 distinct paths, drained, 0 errors); all 6
dumps now declare SYM_PARAM_show and both outcomes of the single PC are
observed. The same defect was found and reported in comments_index (fixed
there by its own agent).
