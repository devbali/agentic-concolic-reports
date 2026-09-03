#!/bin/bash
set +e
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_gen_targ.log"
echo "=== targ gen start $(date -Is) ===" > "$LOG"
for V in html_typed mobile_typed html_plain; do
  echo "--- $V ---" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$B/_seed_targ.json" \
    LABEL_SUFFIX="_tg${V:0:3}" MAX_RUNS=400 TIME_BUDGET=220 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
echo "=== targ gen DONE $(date -Is) ===" >> "$LOG"
