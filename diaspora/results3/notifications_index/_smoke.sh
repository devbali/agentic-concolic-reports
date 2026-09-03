#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_smoke.log"; echo "start $(date -Is)" > "$LOG"
flock /tmp/concolic-slot.lock env CONCOLIC_DEBUG=1 VARIANTS="html_plain" MAX_RUNS=40 TIME_BUDGET=240 \
  LABEL_SUFFIX="_smk" /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
echo "DONE $(date -Is)" >> "$LOG"
