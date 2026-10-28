#!/usr/bin/env bash
# _run_drain_classic.sh — extended anon_mobile drain, CLASSIC regime
# (COMPOSE_CAP=0: multi-var composition disabled). MAX_RUNS=10000.
# Output redirected to /tmp/drain_classic.log. Hard timeout 1800s.
set -uo pipefail

cd /home/dev/project/reports/diaspora/results3/people_show
MAX_RUNS=10000 TIME_BUDGET=1500 COMPOSE_CAP=0 \
  timeout 1800 /home/dev/.claude/jobs/302ac302/tmp/concolic-slot \
  /home/dev/project/reports/diaspora/results3/people_show/run_dse.rb \
  > /tmp/drain_classic.log 2>&1
echo "EXIT=$?" >> /tmp/drain_classic.log