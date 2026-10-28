#!/bin/bash
set +e
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_probe14.log"
echo "=== probe14 start $(date -Is) ===" > "$LOG"
flock /tmp/concolic-heavy.lock python3 -u \
  /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
  "$B/assumption_manifest.json" --declared "$B/_probe14_declared.json" \
  --json-out "$B/_probe14_results.json" >> "$LOG" 2>&1
echo "=== probe14 DONE $(date -Is) rc=$? ===" >> "$LOG"