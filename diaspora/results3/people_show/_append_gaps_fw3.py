#!/usr/bin/env python3
"""Append the FUTURE-WORK #3 resolution to STRUCTURAL_GAPS.md — the 48
cross-format items are definitively a single-run ordinal-naming collision,
not an app reachability gap."""
ADDENDUM = """

---

## Addendum 2026-09-04 03:10 UTC — RESOLUTION: the 48 cross-format items are
## a call-ordinal NAMING collision, not an app reachability gap (FUTURE-WORK
## #3, dual-format scenario)

Earlier addenda classified the 64 into 48 "cross-format" + 16
"guard-foreclosed". FUTURE-WORK #3 (PERMISSION GRANTED, dual-format scenario
`anon_mobile_presenter` in run_dse.rb) directly tested the cross-format
claim. Result: **the app genuinely renders the html presenter AND the mobile
stream in one request** (1696/1701 dual dumps co-mint bare `records_1==0`
with `records_3/4/5_rows>0`), yet MISSING stays 64.

The resolution, proven by `_fw3_ordinal2.py` over all 4079 dumps:
**ZERO dumps co-mint a bare `records_N` with same-ordinal `records_N_rows`.**
The checker's 48 items demand `Not(records_1 != 0) ∧ records_1_rows > 0` in
one run — impossible because the interceptor's per-run call-ordinal counter
gives the html leg `records_1/2` and a co-run's mobile leg `records_3/4/5_rows`
by construction. A single format cannot mint both names either. So the 48 are
**unsatisfiable purely from the naming scheme** — they are not evidence of
any app-side unreachability. The app reaches both families; the checker
cannot pair them under one ordinal.

Downrevised honest reading of the 64:
- **~14 guard-foreclosed** (closed_account/not_found == True forecloses the
  stream render so `to_a_1_row_comments_count==1` cannot be witnessed) — true
  control-flow gaps, app-side real.
- **~50 ordinal-naming-unsat combinations** (bare `records_1/2 == 0` ∧ rows
  family ∧ profile/handle/guid conjuncts requiring same-ordinal bare+rows) —
  app-reachable but checker-structurally unpairable in one run; clearing
  them requires a runtime/engine call-ordinal change (SOURCE.md: OUT OF SCOPE).

The 64 therefore remains the honest bounded-count floor, and is now the
strongest possible claim: MISSING is unchanged at 64 across (a) deeper drain
(69fe5bb), (b) multi-var composition (a67ae0e), and (c) dual-format
co-rendering (this addendum) — three independent strategies, same 64.

Frozen endpoints + shared concolic_targets.rb untouched. `run_dse.rb` + docs
committed; probe scripts `_fw3_*.py` untracked scratch.
"""

path = "/home/dev/project/reports/diaspora/results3/people_show/STRUCTURAL_GAPS.md"
with open(path, "a") as f:
    f.write(ADDENDUM)
print("appended", len(ADDENDUM), "chars")