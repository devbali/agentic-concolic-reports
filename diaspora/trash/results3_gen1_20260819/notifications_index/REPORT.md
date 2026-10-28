# results3/notifications_index — discipline-clean rebuild (2026-08-18)

(Agent-authored report, saved by coordinator. Full detail in the session
transcript; headline record here.)

## Verdict
`coverage_complete: false, truncated: true, missing: 8, solver_lost: 0,
unevaluable_exprs: [], total_runs: 440, PCs: 10,629, assumptions_used: 3` —
an honest capped state: 8 residual combos all trace to one
framework-internal `Person#guid !=` PC (via the app's real `to_param`
override feeding Journey route internals) whose taken=true side could not
be reproduced across 432 corpus runs + 2 targeted rounds + a fresh-JVM
attempt; left open rather than assumed away.

## What the discipline bought (vs results2)
- Render family + default_render REMOVED; the real
  index.html.haml → per-row partial pipeline executes (with runner plumbing
  for response/action_name/default_render that direct-action drives need).
- 14 distinct SQL shapes recorded (results2: 3): list × filters ×
  pagination, actors join, polymorphic target fetch, target-author fetch,
  profile fetch. Acceptance evidence includes
  `SELECT "posts".* FROM "posts" WHERE "posts"."id" = $$(..._row_target_id)`
  (polymorphic target), the actors INNER JOIN with a `$$()` bind, and the
  page-2 paginated list query with correct LIMIT/OFFSET slots.
- Per-type dispatch driven for 2 of 8 STI types (Liked, Reshared) via a
  seeded profile decision; started_sharing deliberately deferred (ActsAsApi
  descent), other five types not attempted this pass.
- New fixes: polymorphic `find_target` klass bug (reflection.klass raises
  on polymorphic; resolved via receiver.klass), ConcreteSymbolicString
  (bare String returns from mocks get re-wrapped by to_symbolic — only nil
  and SymbolicVar pass), to_param/id.to_s leaf shim, network-I/O wall on
  federation fetch, symbolic_user moved inside run body (the reset!
  registration trap again), type-selector early-break fix.

## Distance to reference's 71 (itemized)
1-per-relation representative sampling (shapes not row-multiplication);
2/8 types driven; Person#name's profile reads still mocked (audited
violation, out of this pass's scope); JSON-serializer path not driven
(html only). These are the four named residues.
