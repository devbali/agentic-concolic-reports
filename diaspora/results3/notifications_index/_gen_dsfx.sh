#!/bin/bash
# cycle 2: replay the checker's remaining BLOCKING combinations as SEED_SUFFIXES
# scenarios (see _demand_suffix.py for why the dimension, not the exact name).
# Multi-row roots so the deep collection ordinals exist.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_gen_dsfx.log"; echo "=== demand-suffix start $(date -Is) ===" > "$LOG"
n=$(python3 -c "import json;print(len(json.load(open('$B/_demand_suffixes.json'))))")
for i in $(seq 0 $((n-1))); do
  JS=$(python3 -c "import json;print(json.dumps(json.load(open('$B/_demand_suffixes.json'))[$i]))")
  for V in html_typed mobile_typed json_typed html_plain; do
    echo "--- d$i $V $JS ---" >> "$LOG"
    flock /tmp/concolic-slot.lock env VARIANTS="$V" SEED_SUFFIXES="$JS" \
      EXTRA_SEEDS_JSON="$B/_seed_multirow.json" \
      LABEL_SUFFIX="_d${i}${V:0:3}" MAX_RUNS=220 TIME_BUDGET=170 \
      /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
  done
done
echo "=== demand-suffix DONE $(date -Is) ===" >> "$LOG"
