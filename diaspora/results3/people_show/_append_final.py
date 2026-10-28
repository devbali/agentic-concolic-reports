#!/usr/bin/env python3
"""Append the final status addendum (future-work #2: deeper anon_mobile drain)
to AGENT_RUN.md."""
ADDENDUM = """

---

## Addendum 2026-09-04 00:50 UTC — future-work #2 COMPLETE: deeper anon_mobile
## drain — frontier EXHAUSTED (2346 paths), NODES stays 45, MISSING stays 64

### What was done

Extended anon_mobile campaigns at MAX_RUNS=10000 (hard timeout 1800s each,
output redirected to /tmp/drain_*.log via wrapper scripts
`_run_drain_classic.sh` / `_run_drain_compose.sh`):

| regime        | MAX_RUNS | anon_mobile runs | mobile paths | drained | elapsed |
|---------------|----------|------------------|--------------|---------|---------|
| classic (CAP=0) | 10000  | 9950             | **2346**     | **YES** | 744.9s  |
| composition (CAP=6) | 10000 | 3961         | 1657         | **YES** | 306.6s  |

Both campaigns DRAINED (worklist exhausted). Two independent re-runs of the
classic campaign reproduced the drain deterministically (9950 runs / 2346
paths / 741.3s).

### The frontier WAS finite — the 6000-run ceiling was a cap, not a wall

The previous 6000-run campaign (06d1019-era, 1749 mobile paths) was
MAX_RUNS-CAPPED and never drained. At MAX_RUNS=10000 the classic regime
exhausted the worklist at 9950 runs with **2346 distinct mobile paths**
(+34% over 1749) — the last 4000+ runs added only ~600 new paths (2346 vs
~1749 at 6000), i.e. the frontier was asymptoting. Answer to the documented
item #2: a much larger MAX_RUNS WAS sufficient to drain the anon_mobile
frontier; no depth-first reordering was needed.

### Coverage on the drained corpus (2378 dumps, fully exhausted)

| metric | 06d1019 corpus (1781, capped) | a67ae0e composition (1682, drained) | NOW classic (2378, drained) |
|--------|-------------------------------|-------------------------------------|------------------------------|
| NODES  | 45                            | 45                                  | **45** (unchanged)           |
| MISSING| 64                            | 64                                  | **64** (unchanged)           |
| PCS    | 37136                         | 34955                               | **50314** (+35% vs baseline) |
| assumptions_used | 239                   | 239                                 | 239                           |

NODES did NOT grow beyond 45: the 2346 new paths are combinations of the
SAME 45 expr nodes — no new expr families appeared. MISSING stayed 64:
every one of the 64 is a structural gap (48 cross-format joins + 16
guard-foreclosed), now confirmed against a FULLY-EXHAUSTED frontier (the
strongest possible evidence — no seed combination remains unexplored).

### Final status (all future-work items disposition)

- #1 multi-var seed composition: DONE (a67ae0e) — drains faster, denser
  co-reach, but 64 persists (structural).
- #2 deeper anon_mobile drain: DONE (this addendum) — frontier exhausted
  at 2346 paths; NODES=45, MISSING=64 confirmed on the fully-drained
  corpus. The 64 is a lower bound with the strongest possible corpus
  evidence (drained, not capped).
- #3 decouple format from branch (harness change): NOT DONE — PERMISSION
  REQUIRED (source discipline). This is the ONLY remaining lever that
  could clear the 48 cross-format items (they need a single run rendering
  both html-presenter and mobile-stream).
- #4 multi-variable seed composition for the monsters: subsumed by #1/#2
  (composition + drain both done; conjunctions still structurally split).

### Committed artifact

Classic drained corpus state: 2378 dumps on disk (not committed — dumps
never committed), exploration_summary.json + coverage_summary.json
(MISSING=64, NODES=45, PCS=50314) committed. Frozen endpoints + shared
concolic_targets.rb untouched.
"""

path = "/home/dev/project/reports/diaspora/results3/people_show/AGENT_RUN.md"
with open(path, "a") as f:
    f.write(ADDENDUM)
print("appended", len(ADDENDUM), "chars")