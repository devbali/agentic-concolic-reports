#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_gen_comp.log"; echo "start $(date -Is)" > "$LOG"
for V in html_typed mobile_typed json_typed html_plain mobile_plain; do
  echo "--- $V ---" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$B/_seed_comp.json" SEEDS_ONLY=1 \
    LABEL_SUFFIX="_cp${V:0:3}" MAX_RUNS=4000 TIME_BUDGET=350 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
echo "DONE $(date -Is)" >> "$LOG"
