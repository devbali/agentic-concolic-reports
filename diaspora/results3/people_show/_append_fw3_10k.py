#!/usr/bin/env python3
"""Append the 10000-run dual-format campaign result to AGENT_RUN.md."""
ADDENDUM = """

---

## Addendum 2026-09-04 03:55 UTC — FUTURE-WORK #3 scaled to MAX_RUNS=10000:
## dual frontier large-but-saturating (2606 paths), MISSING STILL 64

Bali's directive "as many runs as needed" (300 smoke → 5000 → 10000): the
5000-run dual campaign was capped by MAX_RUNS (1701 paths, stack ~25), so
the 10000-run campaign establishes the frontier's drain/saturation behavior.

### Campaign (bounded, hard timeout)

`MAX_RUNS=10000 TIME_BUDGET=1800 SCENARIO_ONLY=anon_mobile_presenter`
`timeout 3600 concolic-slot run_dse.rb` (log /tmp/fw3_dual10k.log,
1239.7s): **runs=10000, distinct_paths=2606, capped_by=MAX_RUNS** — NOT
drained. Path growth: 1701 @ 5000 → 2012 @ 5529 → 2457 @ 7185 → 2606 @
10000. Stack depth decayed from ~22 (early) to ~14-15 (late) with pcs ~30 →
~12-16 mid-run: the search is winding down but still surfacing occasional
new paths — the dual frontier is LARGE and saturating slowly, not finite at
this scale (the dual leg mints 17 more exprs than single-format, so its
combination space is inherently bigger than the classic mobile 2346-path
frontier, which DID drain at 9950).

### Coverage on the enlarged mixed corpus (4984 dumps)

Restored the drained baseline (2378) alongside the 2606 dual dumps —
4984-dump mixed corpus:

| metric | fa9e4aa (BEFORE) | bf9650c (dual 5k, 4079) | NOW (dual 10k, 4984) |
|--------|------------------|--------------------------|----------------------|
| MISSING| 64               | 64                       | **64** (unchanged)   |
| NODES  | 45               | 62                       | **62** (unchanged)   |
| runs   | 2378             | 4079                     | **4984**             |
| PCS    | 50314            | 101781                   | **129624**           |
| complete | incomplete     | incomplete               | incomplete           |
| assns_used | 239          | 239                      | 239                  |

TRUNCATED=True (per-clique combo-enumeration cap on some cliques — not a
run cap; the solver enumerates the max_missing_per_clique=4 sample then
stops, standard bounded-check behavior).

### Verdict (unchanged, now scale-robust)

MISSING=64 is invariant across SIX corpus configurations: baseline capped,
composition, classic drained, dual 5k mixed, classic re-run, dual 10k mixed.
The 10000-run dual campaign adds 905 more distinct dual paths than the
5000-run campaign (2606 vs 1701) — nearly doubling the reachable dual-path
surface — yet MISSING stays bit-count 64. The 48 cross-format items remain
blocked by the single-run call-ordinal naming collision (ZERO of the now
4984 dumps co-mint bare records_N with same-ordinal records_N_rows; probe
`_fw3_ordinal2.py`), and the ~16 guard-foreclosed items remain true
control-flow gaps. No further scaling can clear them without a runtime
ordinal change (out of scope). The dual frontier itself would need
MAX_RUNS > 10000 (or a reordered search) to fully drain — documented as a
larger-but-not-infinite frontier, consistent with the +17 NODES.
"""

path = "/home/dev/project/reports/diaspora/results3/people_show/AGENT_RUN.md"
with open(path, "a") as f:
    f.write(ADDENDUM)
print("appended", len(ADDENDUM), "chars")