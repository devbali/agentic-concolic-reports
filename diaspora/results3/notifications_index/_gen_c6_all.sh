#!/bin/bash
# CYCLE 6 corpus, from scratch, in TWO phases: base exploration per variant,
# then ONE launch per variant over the exact-name roots built from the corpus's
# own variable table. A JRuby LAUNCH costs ~2.3 min and the exploration ~10 s,
# so the plan is launch-bound: 14 launches instead of 131.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_gen_all.log"; echo "=== gen_all start $(date -Is) ===" > "$LOG"
ALL="html_typed mobile_typed json_typed html_plain json_plain mobile_plain xml_plain"
for V in $ALL; do
  echo "--- base $V ---" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" MAX_RUNS=900 TIME_BUDGET=420 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
echo "--- building roots ---" >> "$LOG"
python3 "$B/_mkroots.py" >> "$LOG" 2>&1
for V in $ALL; do
  echo "--- roots $V ---" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$B/_roots6.json" \
    LABEL_SUFFIX="_rt${V:0:3}" MAX_RUNS=4500 TIME_BUDGET=900 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
echo "=== gen_all DONE $(date -Is) ===" >> "$LOG"
