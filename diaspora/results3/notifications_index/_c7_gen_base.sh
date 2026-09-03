#!/bin/bash
# C7 base corpus, from scratch, on the un-pinned model (real layout + full
# before_action chain + real gon). One launch per variant; a JRuby launch costs
# ~2.5 min and the exploration seconds, so this is launch-bound.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_c7_gen_base.log"; echo "=== c7 gen base start $(date -Is) ===" > "$LOG"
ALL="html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain"
for V in $ALL; do
  echo "--- base $V $(date -Is) ---" >> "$LOG"
  /home/dev/project/reports/diaspora/tools/slot env VARIANTS="$V" MAX_RUNS=900 TIME_BUDGET=420 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
  echo "[base $V] dumps now: $(ls $B/dump_*.json 2>/dev/null | wc -l)" >> "$LOG"
done
echo "=== c7 gen base DONE $(date -Is) ===" >> "$LOG"
