#!/bin/bash
# THE SHIPPED GATE, re-run on the 83 classes after the X10 fix landed in
# src/. The verdicts ON RECORD are this run's — the batch-local driver
# (_tier2_gate_local.py) is kept only as a cross-check.
set +e; unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/posts_show
LOG="$B/_tier2_gate3.log"
echo "=== tier2 gate (SHIPPED, post-X10-fix) start $(date -Is) ===" > "$LOG"
free -m | sed -n 2p >> "$LOG"
flock /tmp/concolic-heavy.lock python3 -u \
  /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
  "$B/assumption_manifest.json" --declared "$B/_tier2_declared.json" \
  --json-out "$B/_tier2_probe_results_shipped.json" >> "$LOG" 2>&1
rc=$?            # X10 fix 3: captured IMMEDIATELY, before any other command
echo "=== tier2 gate (SHIPPED) DONE rc=$rc $(date -Is) ===" >> "$LOG"
