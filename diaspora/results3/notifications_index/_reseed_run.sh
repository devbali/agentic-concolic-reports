#!/bin/bash
# RULE V rename: regenerate exactly the dumps whose notes carried the OLD
# parsed-guid names. No re-exploration — the seeds are the corpus's own, and
# no PC references those vars (SEEDS_ONLY writes one dump per root).
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_reseed_run.log"; echo "=== reseed start $(date -Is) ===" > "$LOG"
for V in html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain; do
  F="$B/_reseed_${V}.json"; [ -s "$F" ] || continue
  n=$(python3 -c "import json;print(len(json.load(open('$F'))))")
  echo "--- $V ($n roots) ---" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$F" SEEDS_ONLY=1 \
    LABEL_SUFFIX="_rv${V:0:3}" MAX_RUNS=4000 TIME_BUDGET=1200 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
echo "=== reseed DONE $(date -Is) ===" >> "$LOG"
