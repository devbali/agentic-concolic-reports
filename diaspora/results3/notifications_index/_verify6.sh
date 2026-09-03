#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_verify6.log"; echo "=== verify6 start $(date -Is) ===" > "$LOG"
flock /tmp/concolic-slot.lock env VARIANTS="html_typed" MAX_RUNS=60 TIME_BUDGET=200 \
  EXTRA_SEEDS_JSON="$B/_verify6.json" SEED_SUFFIXES='{"_not_found":true}' \
  LABEL_SUFFIX="_vf6" /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
echo "=== verify6 rc=$? $(date -Is) ===" >> "$LOG"
