#!/bin/bash
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
LOG=/home/dev/project/reports/diaspora/results3/notifications_index/_concrete_mobile.log
echo "=== concrete mobile start $(date -Is) ===" > "$LOG"
flock /tmp/concolic-slot.lock /home/dev/project/scripts/diaspora-concolic \
  /home/dev/project/reports/diaspora/tools/concrete_checker/concrete_run_probe.rb \
  /home/dev/project/reports/diaspora/results3/notifications_index/concrete_manifest_mobile.rb >> "$LOG" 2>&1
mv /home/dev/project/reports/diaspora/results3/notifications_index/concrete_run.json \
   /home/dev/project/reports/diaspora/results3/notifications_index/concrete_run_mobile.json 2>/dev/null
echo "=== concrete mobile DONE $(date -Is) rc=$? ===" >> "$LOG"
