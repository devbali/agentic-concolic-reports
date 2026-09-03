#!/bin/bash
# CYCLE 6, phase 2: ONE launch per variant over the exact-name roots built from
# the corpus's own variable table (_mkroots.py). Replaces the 72 env-level
# SEED_SUFFIXES launches — a launch costs ~2.3 min (JRuby boot + app load) and
# the exploration itself ~10 s, so the plan was launch-bound, not compute-bound.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_gen_roots.log"; echo "=== roots start $(date -Is) ===" > "$LOG"
for V in html_typed mobile_typed json_typed html_plain json_plain mobile_plain xml_plain; do
  echo "--- roots $V ---" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$B/_roots6.json" \
    LABEL_SUFFIX="_rt${V:0:3}" MAX_RUNS=4000 TIME_BUDGET=900 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
echo "=== roots DONE $(date -Is) ===" >> "$LOG"
