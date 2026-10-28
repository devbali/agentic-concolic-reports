# C7R1 — base rounds add ~nothing at this corpus size (measured 2026-09-07)

## What was run
`_c7_resume.sh` step 1: seven paged base rounds (MAX_RUNS=900, TIME_BUDGET=420),
4 956 -> 9 894 dumps in 8 minutes. The runner reported up to "new path #779"
per variant.

## What they actually added (sample: every 3rd dump, ~1 650 per half)

| corpus half | distinct exprs | distinct path signatures |
|---|---|---|
| pre-resume (4 956) | 150 | 1 639 |
| base-round `_C7R1b*` (4 938) | 148 | 1 641 |
| **union** | **150** | **1 647** |

**Zero** new decision variables; **~8** new path signatures out of 1 646.
The base rounds re-walked paths the corpus already had.

## Cause
`run_dse.rb:378` — `seen_paths = Set.new`, initialized empty per process and
never seeded from the dumps already on disk. Each fresh JRuby launch therefore
re-discovers existing paths and reports them as new. **The "new path #N"
counter is launch-local, not corpus-relative** — it is not evidence of corpus
growth, and must not be read as such.

## Consequence
The coverage pass now scans 9 894 runs instead of 4 956 for identical coverage
information. The same pass took ~3 000 s at 4 938 runs; at 9 894 it passed
50 000 s still running. Cost roughly doubles-or-worse per combination tested
while the missing space is unchanged.

## For the next round
- Base rounds are NOT the way to enlarge this corpus. The rooted demand round
  (`_demand_root.py`) is: it grafts the demanded assignment onto a real dump's
  base seeds, so it reaches combinations the default path never evaluates.
- If base rounds are ever wanted again, seed `seen_paths` from the existing
  dumps first, or they will burn launches regenerating the corpus.
- Decision 2026-09-07 (user): let the current pass finish rather than restart
  on the smaller corpus. The result is valid — the missing set is the same one
  the 4 956-dump corpus would yield; it just costs more wall-clock.
