#!/bin/bash
# NEGATIVE CONTROL for the tier2 gate, run with the SHIPPED checker.
# 83/83 PASS is exactly the shape of a gate that is not testing anything, so
# six pairs that the inherited adjudications say are DEPENDENT are submitted
# under the same harness. They are never declared anywhere.
set +e; unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/posts_show
LOG="$B/_tier2_negcontrol.log"
echo "=== negative control start $(date -Is) ===" > "$LOG"
flock /tmp/concolic-heavy.lock python3 -u \
  /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
  "$B/assumption_manifest.json" --declared "$B/_tier2_negcontrol.json" \
  --json-out "$B/_tier2_negcontrol_results.json" >> "$LOG" 2>&1
rc=$?
echo "=== negative control DONE rc=$rc $(date -Is) ===" >> "$LOG"
