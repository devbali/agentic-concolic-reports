#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_concrete_photo2.log"; echo "=== photo re-run $(date -Is) ===" > "$LOG"
rm -f "$B/concrete_run.json"
flock /tmp/concolic-slot.lock /home/dev/project/scripts/diaspora-concolic \
  /home/dev/project/src/ruby_runtime/completion_checker/concrete_run_probe.rb \
  "$B/concrete_manifest_photo.rb" >> "$LOG" 2>&1
rc=$?
if [ -f "$B/concrete_run.json" ]; then mv "$B/concrete_run.json" "$B/concrete_run_photo.json"; echo "[photo] ok rc=$rc" >> "$LOG"; else echo "[photo] NO OUTPUT rc=$rc" >> "$LOG"; fi
python3 "$B/merge_concrete_runs.py" >> "$LOG" 2>&1
echo "=== photo re-run DONE $(date -Is) ===" >> "$LOG"
