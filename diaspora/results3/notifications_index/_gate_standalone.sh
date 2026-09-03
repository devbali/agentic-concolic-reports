#!/bin/bash
set +e
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_gate_standalone.log"
echo "=== gate standalone start $(date -Is) ===" > "$LOG"
# NOTE: NO outer slot flock — the assumption checker self-flocks the slot per
# replay (an outer slot lock deadlocks it, cycle 1). Heavy lock only.
flock /tmp/concolic-heavy.lock python3 -u \
  /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
  "$B/assumption_manifest.json" --declared "$B/_assumptions_declared.json" \
  --json-out "$B/_assumption_results.json" >> "$LOG" 2>&1
echo "=== gate standalone DONE $(date -Is) rc=$? ===" >> "$LOG"
