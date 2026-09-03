#!/bin/bash
set -u
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
echo "[heavy] waiting $(date +%H:%M)"
flock /tmp/concolic-heavy.lock bash -c '
echo "[heavy] acquired $(date +%H:%M)"
SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=4 PYTHONPATH=/home/dev/project/src \
  python3 /home/dev/project/reports/diaspora/results3/conversations_index/_cycle4_corpus/coverage_report.py'
echo "EXIT=$?"
echo DONE
