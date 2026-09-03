#!/bin/bash
# cycle 6 coverage-ONLY pass (SKIP_COMPLETION). The flock is taken INSIDE the
# systemd unit that runs this script (RUNBOOK ops rule), exactly once.
set -u
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
echo "[heavy] waiting $(date +%H:%M:%S)"
flock /tmp/concolic-heavy.lock bash -c '
echo "[heavy] acquired $(date +%H:%M:%S)"; free -m | head -2
SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=${MMPC:-4} PYTHONPATH=/home/dev/project/src \
  python3 /home/dev/project/reports/diaspora/results3/conversations_index/coverage_report.py'
echo "EXIT=$?"
echo "[heavy] released $(date +%H:%M:%S)"
