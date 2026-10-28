#!/bin/bash
# ============================================================================
# P35 — posts_show EXTRACTION + SUBSUMPTION, the SHIPPING run (2026-09-15).
#
# The owner's 2026-09-11 rule ("policies are extracted at CLOSURE only, and
# posts_show is NOT complete") is SUPERSEDED by the 2026-09-15 owner directive
# to ship posts_show INCOMPLETE: it is the last endpoint without a policy and a
# policy for all six gates a benchmark run. The header states plainly that the
# endpoint is not complete, which is what makes shipping it honest.
#
# Parallel scan validated serial-vs-parallel on a random 6 000-dump sample:
# SQL BYTE-IDENTICAL (128 statements), every summary field identical bar a
# SKIP-path note, 410s -> 111s (3.7x). 298 896 raw queries -> 124 distinct over
# 12 chunks, so the cross-worker dedup merge was exercised throughout.
#
# Subsumption: ONE JVM, threads via SUBSUME_SOLVER_THREADS (pairs are NOT
# sharded -- that premise was wrong, twice confirmed). null = TIMEOUT = KEPT.
# ============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
Q=/home/dev/project/reports/diaspora/results3/queries_from_runs
. "$B/_cage.sh"
cd /home/dev/project
export QFR_APP_CONFIG=/home/dev/project/reports/diaspora/queries_config/app.json
V=/home/dev/project/venvs/queries_from_runs/bin/python
L="$Q/_p35_extract_posts_show_SHIP2_20260915.log"
T0=$(date +%s)
cage p35ext2.scope 20G env QFR_APP_CONFIG="$QFR_APP_CONFIG" \
  EXTRACT_WORKERS="${EXTRACT_WORKERS:-6}" EXTRACT_CHUNK="${EXTRACT_CHUNK:-500}" \
  SUBSUME_SOLVER_THREADS="${SUBSUME_SOLVER_THREADS:-6}" \
  JAVA_TOOL_OPTIONS= PYTHONPATH=/home/dev/project/src \
  $V -u $Q/_p35_extract_posts_show_par.py > "$L" 2>&1
rc=$?
echo "[$(date -Is)] P35-EXTRACT-SHIP EXIT rc=$rc wall=$(( $(date +%s)-T0 ))s" | tee -a "$L"
grep -E '^posts_show: |RED|unparseable|subsumption|verdict tally' "$L" | tail -8
