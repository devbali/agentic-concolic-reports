#!/bin/bash
# THE ASSUMPTION GATE on the tier-2 proposal. Rule T3: these are proposals until
# this passes them. flock on the shared heavy lock so this never runs beside the
# notifications drive's JRuby work.
set +e; unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/posts_show
LOG="$B/_tier2_gate.log"
echo "=== tier2 gate start $(date -Is) ===" > "$LOG"
free -m | sed -n 2p >> "$LOG"
flock /tmp/concolic-heavy.lock python3 -u \
  /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
  "$B/assumption_manifest.json" --declared "$B/_tier2_declared.json" \
  --json-out "$B/_tier2_probe_results.json" >> "$LOG" 2>&1
rc=$?   # X10 fix 3: captured IMMEDIATELY
echo "=== tier2 gate DONE rc=$rc $(date -Is) ===" >> "$LOG"
