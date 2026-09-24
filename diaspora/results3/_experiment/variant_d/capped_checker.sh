#!/bin/bash
# Per-query blast-radius wrapper (recipe P4). FIX 2026-08-20: systemd-run
# does NOT inherit the caller's env — SUBSUME_TIMEOUT_MS/THREADS silently
# never reached the JVM (it fell back to its 15000ms coverage default;
# found via a verdict reason quoting 15000 on a 300000 request). Pass them
# through explicitly.
exec systemd-run --user --pipe --quiet -p MemoryMax=3800M -p MemorySwapMax=0 \
  --setenv=SUBSUME_TIMEOUT_MS="${SUBSUME_TIMEOUT_MS:-15000}" \
  --setenv=SUBSUME_SOLVER_THREADS="${SUBSUME_SOLVER_THREADS:-1}" \
  --setenv=QFR_APP_CONFIG="${QFR_APP_CONFIG:-/home/dev/project/reports/diaspora/queries_config/app.json}" \
  /home/dev/project/src/queries_from_runs/subsume/check_subsumed.sh "$@"
