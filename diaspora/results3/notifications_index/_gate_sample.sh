#!/bin/bash
set +e
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_gate_sample.log"
echo "=== gate sample start $(date -Is) ===" > "$LOG"
flock /tmp/concolic-heavy.lock env python3 -u \
  /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
  "$B/assumption_manifest.json" --declared "$B/_assum_sample.json" \
  --json-out "$B/_assum_sample_results.json" >> "$LOG" 2>&1
echo "=== gate sample DONE $(date -Is) rc=$? ===" >> "$LOG"
