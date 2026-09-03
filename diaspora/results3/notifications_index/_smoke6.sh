#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_smoke6.log"; echo "=== smoke6 start $(date -Is) ===" > "$LOG"
flock /tmp/concolic-slot.lock env VARIANTS="html_typed" MAX_RUNS=40 TIME_BUDGET=200 \
  LABEL_SUFFIX="_sm6" /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
echo "=== smoke6 rc=$? $(date -Is) ===" >> "$LOG"
