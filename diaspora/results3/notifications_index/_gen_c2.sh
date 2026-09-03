#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_gen_c2.log"; echo "=== cycle2 base start $(date -Is) ===" > "$LOG"
for V in html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain; do
  echo "--- $V ---" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" MAX_RUNS=900 TIME_BUDGET=900 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
echo "=== cycle2 base DONE $(date -Is) ===" >> "$LOG"
