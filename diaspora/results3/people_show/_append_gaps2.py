#!/usr/bin/env python3
"""Add a short final addendum to STRUCTURAL_GAPS.md anchoring the 64 count to
the fully-drained corpus (future-work #2, commit 69fe5bb)."""
ADDENDUM = """

---

## Addendum 2026-09-04 01:20 UTC — the 64 is now anchored to a DRAINED corpus

The "64 = genuine structural gaps" claim above was collected on the 1781-dump
CAPPED corpus. Future-work #2 (commit `69fe5bb`) re-ran the anon_mobile
exploration at MAX_RUNS=10000: the frontier **exhausted** at 9950 runs /
2346 mobile paths (+34% over the capped 1749), two deterministic re-runs, and
the bounded checker on the fully-drained 2378-dump corpus reported
**NODES=45 (unchanged), MISSING=64 (unchanged), PCS 37136→50314** — every
one of the 64 remains: 48 cross-format joins (format-exclusive per
controller/template; unwitnessable by any seed set) + 16 guard-foreclosed
(not_found/closed_account → stream never renders). This is the strongest
possible corpus evidence: no seed combination is left unexplored, yet the
same 64 stand.

Only future-work #3 (decouple format from branch in the harness) could clear
the 48 cross-format items — **PERMISSION REQUIRED** (source discipline:
harness change, ask first). Not done.
"""

path = "/home/dev/project/reports/diaspora/results3/people_show/STRUCTURAL_GAPS.md"
with open(path, "a") as f:
    f.write(ADDENDUM)
print("appended", len(ADDENDUM), "chars")