#!/bin/bash
# FULL report: coverage + completion gate (shims, note check, assumptions, audits).
# heavy taken once, outermost; the gate's probes take the slot lock per launch.
set -u
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
echo "[heavy] waiting $(date +%H:%M)"
flock /tmp/concolic-heavy.lock bash -c '
echo "[heavy] acquired $(date +%H:%M)"; free -m | head -2
MAX_MISSING_PER_CLIQUE=4 PYTHONPATH=/home/dev/project/src \
  python3 /home/dev/project/reports/diaspora/results3/conversations_index/coverage_report.py'
echo "EXIT=$?"
echo DONE
