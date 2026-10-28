#!/usr/bin/env python3
"""Append the multi-var composition addendum to AGENT_RUN.md."""
ADDENDUM = """

---

## Addendum 2026-09-04 00:40 UTC — multi-variable seed composition
## (future-work #1): implemented, tested, bounded campaign — MISSING stays 64

### What was built

`dse_compose.rb` (pure-Ruby, MRI-unit-tested) + integration in `run_dse.rb`
`explore`: after the classic single-flip child pass, each observed run ALSO
spawns COMPOSED children that merge 2-way and 3-way flips on DISTINCT
symbolic vars into one seed set (`COMPOSE_CAP`, default 6 per way). This
jumps the co-flip depth by 2-3 per level, targeting the missing
dot × guid × stream × branch-B conjunctions directly (the single-flip chain
is depth-limited by PC ordering — flipping PC_k changes the path so the
sibling PC for the NEXT flip may vanish).

Unit tests (`_test_compose.rb`, 7 cases): distinct-var merge, same-var
skip, 3-way pairwise-distinct, parent-seed inheritance, dedup, cap bound,
min_k = max index + 1 — ALL PASS.

### Bounded campaign (MAX_RUNS=6000, TIME_BUDGET=900, COMPOSE_CAP=6,
### hard timeout 2900s — 305.5s actual)

| scenario    | runs   | distinct paths | composed children | drained |
|-------------|--------|----------------|-------------------|---------|
| anon_handle | 66     | 17             | 43                | YES     |
| anon_json   | 15     | 8              | 25                | YES     |
| anon_mobile | 3961   | 1657           | 1861              | YES     |

NOTE: ALL THREE SCENARIOS DRAINED (worklist exhausted) — the previous
6000-run campaign was MAX_RUNS-CAPPED and never drained. Composition's
LIFO order (composed children popped first) collapses the search onto
merged paths, so fewer distinct path signatures are written (1682 vs 1781
dumps) — but every seed-set in the merged space is covered.

### Result: MISSING = 64 — bit-identical to baseline (0 cleared, 0 new)

Checker on the composed corpus: MISSING=64, same 64 items (verified by
signature comparison `_cmp_compose.py`: 64 common, 0 cleared, 0 new),
NODES=45, PCS=34955, assumptions_used=239.

### Why composition cannot clear any of the 64 (confirmed by corpus search)

`_classify64.py` on the missing items:

- **48 cross-format**: `Not(records_1 != 0) ∧ Not(records_2 != 0)` (bare
  block/contact records — minted ONLY in html/json runs) conjoint with
  `records_1_rows > 0 ∧ to_a_1_rows != 0` (posts stream — minted ONLY in
  mobile runs). One format per request (controller: stream only in
  `format.mobile`; html/json render the presenter/block-checks only). NO
  seed composition can witness a conjunction of two format-separated var
  families — the honest floor from the earlier addendum, now demonstrated
  with the composition mechanism too.
- **16 guard-foreclosed** (12 guard_x_stream + 4 find_by variants):
  `first_1_not_found/closed_account == True` (or `find_by_1_not_found`)
  conjoint with stream attrs (`comments_count == 1`, `author_guid != ''`,
  via_user dot forms). When the finder fails/closed, the render path
  skips the stream — control-flow foreclosure, not seed-reachability.

Pair co-reach density DID improve (+50% on every 2-var pair, e.g.
`rows_gt0 × via_user_dot` 216→324, `via_user_dot × via_user_guid_empty`
144→216) and max conjunction depth is 6 in both corpora — but the 64
missing items need depth 8-10 AND cross-format/guard parts, which remain
structurally unreachable.

### Verdict

Multi-var composition is a genuine exploration improvement (drains the
worklist, denser co-reach, unit-tested) and is committed as future-work #1.
It does NOT reduce MISSING — the 64 are structural (48 format-exclusive +
16 guard-foreclosed), the ONLY remaining lever being the documented
future-work #3 (decouple format from branch in the harness — PERMISSION
REQUIRED, source discipline).
"""

path = "/home/dev/project/reports/diaspora/results3/people_show/AGENT_RUN.md"
with open(path, "a") as f:
    f.write(ADDENDUM)
print("appended", len(ADDENDUM), "chars")