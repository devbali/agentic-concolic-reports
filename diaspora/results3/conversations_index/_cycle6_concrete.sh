#!/bin/bash
# cycle 6 concrete refresh — real app, sqlite fixtures, no mocks. One process
# per manifest (JVM crash isolation). slot lock taken once per launch, INSIDE
# the systemd unit that runs this script.
set -u
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/conversations_index
P=/home/dev/project/src/ruby_runtime/completion_checker/concrete_run_probe.rb
for m in auth mobile; do
  echo "=== CONCRETE $m $(date +%H:%M:%S) ==="
  rm -f "$B/concrete_$m.sqlite3"
  flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$P" "$B/concrete_manifest_$m.rb" 2>&1 \
    | grep -viE 'deprecat|fog\]|Ignoring activerecord|Top level ::'
  mv -f "$B/concrete_run.json" "$B/concrete_run_$m.json"
done
python3 "$B/merge_concrete_runs.py"
echo CONCRETE6_DONE
