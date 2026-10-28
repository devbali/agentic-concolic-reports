#!/usr/bin/env python3
"""Append the composition experiment results to STRUCTURAL_GAPS.md."""
ADDENDUM = """

---

## Addendum 2026-09-04 00:40 UTC — multi-variable seed composition tried

Future-work #1 (multi-variable seed composition) was implemented
(`dse_compose.rb` + `run_dse.rb` integration: per-run 2-way and 3-way
composed children on DISTINCT symbolic vars, `COMPOSE_CAP=6` per way,
MRI-unit-tested 7/7) and a bounded campaign run (MAX_RUNS=6000,
TIME_BUDGET=900 — 305.5s, all three scenarios DRAINED, 1682 dumps).

**Verdict: MISSING stays 64 — bit-identical to baseline (0 cleared, 0
new).** The classification of the 64 therefore stands, now with a second
independent mechanism:

- 48 cross-format (bare block/contact `records_1/2` × posts-stream rows):
  format-exclusive by controller/template (stream only in
  `format.mobile`), provably unwitnessable by ANY seed set — composition
  included.
- 16 guard-foreclosed (`first_1/find_by/via_user not_found/closed_account
  == True` × stream attrs): control-flow foreclosure, not seed-reachability.

Composition DID improve pair co-reach density ~50% (e.g. `rows_gt0 ×
via_user_dot` 216→324 of 1682 dumps; `via_user_dot × via_user_guid_empty`
144→216) and drained the exploration, but the residual gaps need depth 8-10
conjunctions with cross-format or guard-foreclosed parts — out of reach for
any seed-composition strategy. The remaining documented lever is future-work
#3 (harness decoupling of format from branch — PERMISSION REQUIRED).

Evidence probes (scratch, untracked): `_co_reach.py`, `_co_cmp.py`,
`_depth_cmp.py`, `_cmp_compose.py`, `_classify64.py`, `_missing_fams.py`,
`_peek_exprs.py`, `_test_compose.rb`, `_compose_campaign.log`.
"""

path = "/home/dev/project/reports/diaspora/results3/people_show/STRUCTURAL_GAPS.md"
with open(path, "a") as f:
    f.write(ADDENDUM)
print("appended", len(ADDENDUM), "chars")