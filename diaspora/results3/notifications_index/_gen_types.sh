#!/bin/bash
set +e
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_gen_types.log"
echo "=== per-type gen start $(date -Is) ===" > "$LOG"
# Seed each STI type value and EXPLORE the rep decisions under it (flip
# expansion) across the render-heavy variants, so the type-gated within-rep
# cliques (contact profile, post STI, mention container) get observed.
for k in 0 1 2 3 4 5 6 7; do
  for V in html_typed mobile_typed; do
    echo "--- type$k $V ---" >> "$LOG"
    flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$B/_seed_type$k.json" \
      LABEL_SUFFIX="_ty${k}${V:0:3}" MAX_RUNS=420 TIME_BUDGET=260 \
      /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
  done
done
echo "=== per-type gen DONE $(date -Is) ===" >> "$LOG"
