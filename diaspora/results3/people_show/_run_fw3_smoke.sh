#!/bin/bash
# FUTURE-WORK #3 Option A — smoke test: dual-format scenario only.
# SCENARIO_ONLY=anon_mobile_presenter, MAX_RUNS=300, hard timeout 480s.
set -u
export MAX_RUNS="${MAX_RUNS:-300}"
export TIME_BUDGET="${TIME_BUDGET:-300}"
export COMPOSE_CAP="${COMPOSE_CAP:-6}"
export SCENARIO_ONLY="anon_mobile_presenter"
LOG=/tmp/fw3_smoke.log
echo "== fw3 smoke $(date -u +%H:%M:%S) MAX_RUNS=$MAX_RUNS TIME_BUDGET=$TIME_BUDGET COMPOSE_CAP=$COMPOSE_CAP ==" | tee "$LOG"
timeout 480 /home/dev/.claude/jobs/302ac302/tmp/concolic-slot \
  /home/dev/project/reports/diaspora/results3/people_show/run_dse.rb >> "$LOG" 2>&1
echo "EXIT=$? at $(date -u +%H:%M:%S)" >> "$LOG"
tail -5 "$LOG"