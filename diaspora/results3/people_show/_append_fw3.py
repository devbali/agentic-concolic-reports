#!/usr/bin/env python3
"""Append the FUTURE-WORK #3 result addendum to AGENT_RUN.md."""
ADDENDUM = """

---

## Addendum 2026-09-04 03:10 UTC — FUTURE-WORK #3 COMPLETE: dual-format
## scenario proves cross-format co-reachability, but MISSING stays 64
## (single-run ordinal-naming collision — not an app reachability gap)

### Option A implemented (PERMISSION GRANTED 2026-09-04 02:03)

`run_dse.rb` gains a fourth scenario `anon_mobile_presenter` (`dual: true`):
a single `$interceptor.run` block executes TWO real `PeopleController#show`
request cycles — the **format.all html presenter render** (mints the bare
`records_1/2` block/contact NullRelation checks) followed by the
**format.mobile stream render** (mints the `records_3/4/5_rows` posts-stream
family) — each with a fresh harness so the two request cycles stay isolated.
`SCENARIO_ONLY=<name>` env lets a campaign run one scenario in isolation.
Touches neither frozen endpoints nor shared concolic_targets.rb nor app
source (Option C stayed rejected).

### Campaign (bounded, hard timeout)

`MAX_RUNS=5000 TIME_BUDGET=1800 SCENARIO_ONLY=anon_mobile_presenter`
`timeout 3600 concolic-slot run_dse.rb` (log /tmp/fw3_dual.log, 645.5s):
**runs=5000, distinct_paths=1701, capped_by=MAX_RUNS** (frontier deeper than
5000; stack depth ~25, not drained). 14 of 5000 runs error with a Ruby
runtime `SymString#[]` boundary (`split result index 0 out of range` on an
empty seeded string, src/ruby_runtime/string.rb:265) — non-blocking, dumps
still recorded. The 1701 dual dumps were merged with the drained baseline
(2378) into a 4079-dump mixed corpus.

### Before/after (bounded checker, per-clique cap 4, hard timeouts)

| metric      | BEFORE (fa9e4aa)  | AFTER (mixed dual) |
|-------------|-------------------|--------------------|
| MISSING     | 64                | **64** (unchanged) |
| NODES       | 45                | **62** (+17 new)   |
| total_runs  | 2378              | 4079               |
| PCS         | 50314             | **101781** (+2.0x) |
| complete    | incomplete        | incomplete         |
| assns_used  | 239               | 239                |

### What the dual run ACHIEVED (real, valuable)

- **Semantic cross-format co-reachability PROVEN**: 1696 of 1701 dual dumps
  co-mint bare `records_1==0` (taken=False everywhere — Block.none is empty
  in anon) AND `records_3/4/5_rows>0` in ONE request. The app genuinely
  renders the html presenter AND the mobile stream in a single request.
- The 48 "cross-format missing" items were **never a real app reachability
  gap** — the 48 are an artifact of the CoverageChecker's per-run
  call-ordinal naming, NOT of the app.
- **NODES grew 45→62** and PCS doubled: the dual leg minted 17 genuinely new
  expr nodes (second finder `first_2`/`find_by_2`, `records_3/4/5_rows`,
  mobile-leg profile/NSFW/author_guid vars) — real new coverage surface.

### Why MISSING stays 64 (rigorous, ordinal-naming collision)

Census of all 4079 dumps: **ZERO dumps co-mint a bare `records_N` with the
same-ordinal `records_N_rows`** (probe `_fw3_ordinal2.py`). The checker's
missing items demand e.g. `Not(records_1 != 0) ∧ records_1_rows > 0` — a
single dump must mint bare `records_1` (html) AND `records_1_rows` (mobile)
under the SAME ordinal. The interceptor's per-run call-ordinal counter
(call_interceptor.rb:140, SYM_RESULT_<func>_<idx>) makes this impossible:
the html leg consumes `records_1`/`records_2`, so a co-run's mobile leg gets
`records_3/4/5_rows` by construction. A mobile-only run mints
`records_1_rows` but never bare `records_1`. Same-ordinal pairing is
**structurally unsatisfiable in any single run** — no seed set or format
mixing can break it. This is a **source-discipline finding**: clearing the
48 would require a runtime/engine change (per-render ordinal reset or
name-scoping), which is explicitly out of scope (SOURCE.md discipline).

### Final disposition of future-work items

- #1 multi-var composition: DONE (a67ae0e), 64 persists.
- #2 deeper mobile drain: DONE (69fe5bb), frontier exhausted, 64 persists.
- #3 decouple format from branch: **DONE (this addendum)** — dual-format
  scenario implemented and proven to co-mint both families semantically, but
  MISSING stays 64 due to the single-run ordinal-naming collision. The 48
  items are definitively NOT app reachability gaps; clearing them requires a
  runtime naming change (out of scope by discipline).

### Committed artifact

Mixed corpus 4079 dumps on disk (not committed — dumps never committed),
`coverage_summary.json` regenerated (MISSING=64, NODES=62, PCS=101781),
`exploration_summary.json` (dual campaign: 5000 runs/1701 paths/capped),
`run_dse.rb` (dual scenario + SCENARIO_ONLY). Frozen endpoints + shared
concolic_targets.rb untouched. Probe scripts `_fw3_*.py` (scratch, untracked).
"""

path = "/home/dev/project/reports/diaspora/results3/people_show/AGENT_RUN.md"
with open(path, "a") as f:
    f.write(ADDENDUM)
print("appended", len(ADDENDUM), "chars")