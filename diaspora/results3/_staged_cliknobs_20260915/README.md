# Staged knob patches — 2026-09-15

Two files could not be edited safely while the notifications_index and
posts_show campaigns were running. The changes are staged here as unified
diffs against the exact revision I read; apply with
`patch -p0 < <file>` from `/home/dev/project` after checking the file has not
moved since.

## 1. `coverage.py.knobs.patch` → `src/concolic_engine/coverage.py`

**Not applied because** the posts_show agent is actively working this file
(standing instruction), and pid 170439 was running `coverage_report.py`
against it throughout.

**What it does.** Turns `max_missing_per_clique` and `max_cliques` from
hard-coded constructor defaults (1 and 1024) into declared knobs, so they
appear in a `--help` listing and follow the project precedence rule.

**Read this before applying.** The patch makes the constructor consult
`$MAX_CLIQUES` / `$MAX_MISSING_PER_CLIQUE`, which today are read *only* by the
batch drivers and passed in explicitly. Any process that merely has them
exported — every live campaign shell does — would then silently change the
caps of a `CoverageChecker` built without them. posts_show's own driver
exports `MAX_CLIQUES=16384` against a `src/` default of 1024: that is a 16x
change to a search budget arriving from a patch that looks like plumbing.
Either accept that (and say so in the batch notes), or apply only the
`KNOBS` declaration and leave the constructor reading its literals.

## 2. `_c30_extract_par.py.knobs.patch` → `reports/diaspora/results3/queries_from_runs/_c30_extract_par.py`

**Not applied because** the file was executing as pid 171042 (notifications_index
C30 extraction, 7 workers) — never edit a running script.

**What it does.** Adds `--num-workers` / `--chunk-size` alongside
`$EXTRACT_WORKERS` / `$EXTRACT_CHUNK`, which keep working unchanged. Apply
after that extraction finishes.

Both patches depend on `src/resource_knobs.py`, which is already in place.
