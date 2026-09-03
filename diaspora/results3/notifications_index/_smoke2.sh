#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_smoke2.log"; echo "start $(date -Is)" > "$LOG"
flock /tmp/concolic-slot.lock env VARIANTS="html_typed" SEED_SUFFIXES='{"_profile_not_found":true}' \
  MAX_RUNS=60 TIME_BUDGET=240 LABEL_SUFFIX="_sm2" \
  /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
echo "DONE $(date -Is)" >> "$LOG"
