#!/bin/bash
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_shimtest.log"
echo "=== shim test start $(date -Is) ===" > "$LOG"
JRUBY_OPTS=--debug flock /tmp/concolic-slot.lock /home/dev/project/scripts/diaspora-concolic \
  /home/dev/project/src/ruby_runtime/completion_checker/shim_test_runner.rb \
  "$B/_shims_extracted.json" "$B/shim_tests.rb" "$B/_shim_results.json" >> "$LOG" 2>&1
echo "=== shim test DONE $(date -Is) rc=$? ===" >> "$LOG"
