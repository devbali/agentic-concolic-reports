#!/usr/bin/env bash
# Relaunch of the anon_html leg, 2026-09-25 04:40. The original leg was KILLED
# (pid 1912672) because tools/slot had handed it slot 1, which belongs to the
# untouchable conversations_index gate's pool -- see _p47_slot.sh. It had
# produced 0 dumps, so nothing is lost. This relaunch uses the PRIVATE slot
# namespace and therefore cannot contend with the gate.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/posts_show
P47_SLOTS=1 MAX_RUNS=200000 TIME_BUDGET=36000 \
  VARIANTS=anon_html LABEL_SUFFIX=_v209250420anon_html \
  "$B/_p47_slot.sh" /home/dev/project/scripts/diaspora-concolic "$B/v2/run_dse.rb" \
  >> "$B/_p47_leg_anon_html.log" 2>&1
echo "[$(date -Is)] anon_html relaunch done rc=$? : $(grep -E 'drained=' "$B/_p47_leg_anon_html.log" | tail -1)" >> "$B/_p47_gen_v2.log"
