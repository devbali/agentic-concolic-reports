#!/bin/bash
# cycle 2 dimension sweep: root the DSE inside every combination of the NEW
# decision dimensions (list length {0,1,3}, preloaded actors {0,1,4}, the
# diaspora-link family, the Photo target) and let it flip-expand from there.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_gen_dims.log"; echo "=== dims start $(date -Is) ===" > "$LOG"
for V in html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain; do
  echo "--- $V ---" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$B/_seed_dims.json" \
    LABEL_SUFFIX="_dm${V:0:3}" MAX_RUNS=400 TIME_BUDGET=300 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
echo "=== dims DONE $(date -Is) ===" >> "$LOG"
