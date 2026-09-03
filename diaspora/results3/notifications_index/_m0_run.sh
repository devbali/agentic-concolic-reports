#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_m0_run.log"; echo "start $(date -Is)" > "$LOG"
for V in html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain; do
  F="$B/_seed_m0_${V}.json"; [ -s "$F" ] || continue
  flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$F" SEEDS_ONLY=1 \
    LABEL_SUFFIX="_m0${V:0:3}" MAX_RUNS=3000 TIME_BUDGET=300 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
echo "DONE $(date -Is)" >> "$LOG"
