#!/bin/bash
# cycle 2: every concrete scenario, one manifest per JRuby process (crash
# isolation), then merge into concrete_run.json for the note check + fidelity.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_concrete_all.log"; echo "=== concrete all start $(date -Is) ===" > "$LOG"
for S in auth mobile links photo pages; do
  echo "--- $S ---" >> "$LOG"
  rm -f "$B/concrete_run.json"
  flock /tmp/concolic-slot.lock /home/dev/project/scripts/diaspora-concolic \
    /home/dev/project/src/ruby_runtime/completion_checker/concrete_run_probe.rb \
    "$B/concrete_manifest_${S}.rb" >> "$LOG" 2>&1
  rc=$?
  if [ -f "$B/concrete_run.json" ]; then
    mv "$B/concrete_run.json" "$B/concrete_run_${S}.json"
    echo "[$S] ok rc=$rc" >> "$LOG"
  else
    echo "[$S] NO concrete_run.json rc=$rc" >> "$LOG"
  fi
done
python3 "$B/merge_concrete_runs.py" >> "$LOG" 2>&1
echo "=== concrete all DONE $(date -Is) ===" >> "$LOG"
