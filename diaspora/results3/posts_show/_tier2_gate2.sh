#!/bin/bash
# The tier2 gate, driven by the batch-local driver that corrects src/'s
# canonical-vs-runtime key mismatch (X10). flock so it never competes with the
# notifications drive for JRuby.
set +e; unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/posts_show
LOG="$B/_tier2_gate2.log"
echo "=== tier2 gate (local driver) start $(date -Is) ===" > "$LOG"
free -m | sed -n 2p >> "$LOG"
flock /tmp/concolic-heavy.lock python3 -u "$B/_tier2_gate_local.py" \
  "$B/assumption_manifest.json" "$B/_tier2_declared.json" \
  "$B/_tier2_probe_results.json" >> "$LOG" 2>&1
rc=$?   # X10 fix 3: captured IMMEDIATELY
echo "=== tier2 gate DONE rc=$rc $(date -Is) ===" >> "$LOG"
