#!/bin/bash
set -e
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
LOG=/home/dev/project/reports/diaspora/results3/notifications_index/_gen_corpus.log
echo "=== corpus gen start $(date -Is) ===" > "$LOG"
flock /tmp/concolic-slot.lock env MAX_RUNS="${MAX_RUNS:-4500}" TIME_BUDGET="${TIME_BUDGET:-2400}" \
  /home/dev/project/scripts/diaspora-concolic \
  /home/dev/project/reports/diaspora/results3/notifications_index/run_dse.rb >> "$LOG" 2>&1
echo "=== corpus gen DONE $(date -Is) ===" >> "$LOG"
