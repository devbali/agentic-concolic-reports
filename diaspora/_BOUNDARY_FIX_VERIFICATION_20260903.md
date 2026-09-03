# BOUNDARY FIX VERIFICATION — 2026-09-03 (after applying the 4 Rule T3 fixes)

Applied to: reports/diaspora/concolic_targets.rb (shared boundary), from
docs/_BOUNDARY_FIX_DRAFT_20260903.md, fixes 1-4 in draft order, exactly as
drafted. One dedicated git commit.

## Direct probe on the FIXED shared file (new, this session)

`_verify_boundary_fixes.rb` — boots diaspora env + runtime + the SHARED
concolic_targets.rb, drives each fixed mock through `interceptor.run`, asserts
the emitted note shapes and memo behaviour. Result: **14/14 checks PASS**.

| Check | Assertion | Result |
|---|---|---|
| Fix3 size | note starts `SELECT COUNT(*) FROM "users" ...` | PASS |
| Fix1 count | note starts `SELECT COUNT(*) FROM "users" ...` | PASS |
| Fix1 sum | note = `SELECT SUM("users"."id") FROM "users" ...` | PASS |
| Fix2 no crash | gon call through run() has no error field | PASS |
| Fix2 returns Gon module | g1 == ::Gon && g2 == ::Gon | PASS |
| Fix2 RequestStore[:gon] set | store[:gon] is a Gon::Request (real body ran) | PASS |
| Fix2 interceptor records | 2 symbolic_call events for 2 gon calls | PASS |
| Fix4 no crash | run error empty | PASS |
| Fix4 same instance | two reads of one association → first.equal?(second) | PASS |
| Fix4 klass | instance is the association's klass (Person) | PASS |
| Fix4 ONE event | two reads emit exactly 1 find_target symbolic_call | PASS |
| Fix4 second run no crash | run error empty | PASS |
| Fix4 fresh instance | second run's instance NOT equal to first run's | PASS |
| Fix4 fresh event | second run emits its own find_target event | PASS |

Evidence file: reports/diaspora/_verify_boundary_fixes.rb (kept in repo).
Run command (slot-serialized):
  tools/slot scripts/diaspora-concolic reports/diaspora/_verify_boundary_fixes.rb

## Closed-endpoint corpus censuses (run per draft VERIFICATION steps 1-3)

The closed endpoints (conversations_index, comments_index) run their OWN
private forks of concolic_targets.rb — the shared file is NOT loaded by their
dumps, so applying the fixes to the shared file cannot move their policy
views. Their prior censuses already established the reference shapes; the
probe above confirms the shared file now matches those shapes exactly.

- conversations_index: all 18 306 `sum` events carry `SELECT SUM(…)` shape
  (100% of sum events, 18 623 dumps); `size` 0-invoked. (Reference: batch-local
  override at notifications targets.rb 5b-iii(b) → same AGG-COLLAPSE shape the
  shared file now emits.)
- comments_index: 0 `sum`, 0 `size` events; 13 085 find_target events, 0
  repeated-note events (all first reads) — unaffected.
- conversations_index find_target: 73 997 find_target events across 6 000
  dumps, 1 364 repeated-note events in 1 358 dumps, ONE distinct shape
  (`SELECT "profiles".* ... WHERE "person_id" = @ LIMIT`) — multiplicity-only
  over-emission, exactly the population Fix 4 collapses. No view added/removed.

## notifications_index override removal — HELD

PAUSED_C7.md: notifications_index's coverage_summary.json is a coverage-only
pass (completion gate never ran; 7 681 combos missing). Its batch-local
overrides (calc :count/:sum, :size, find_target memo, gon shim) are therefore
KEPT — removing them would mask an incomplete corpus. Per task constraint:
"do NOT remove ... until its final report is written and its corpus is final"
— NOT final, so KEPT. The overrides are now redundant with the shared
boundary (they match it), but harmless; they will be removed in the final
closing pass once notifications_index completes.

## TARGET_FUNCTIONS.md

Updated: "REQUIRED BOUNDARY WORK — do ONCE..." section re-marked APPLIED with
verification summary; per-item text kept as before/after record.