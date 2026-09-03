#!/bin/bash
cd /home/dev/project
LOG=/home/dev/project/reports/diaspora/results3/notifications_index/_cov_only.log
echo "=== coverage-only start $(date -Is) ===" > "$LOG"
env SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=4 PYTHONPATH=src python3 \
  /home/dev/project/reports/diaspora/results3/notifications_index/coverage_report.py >> "$LOG" 2>&1
echo "=== coverage-only DONE $(date -Is) rc=$? ===" >> "$LOG"
