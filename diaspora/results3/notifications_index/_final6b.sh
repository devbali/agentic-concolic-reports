#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_final6.log"; echo "=== final6 start $(date -Is) ===" > "$LOG"
MAX_MISSING_PER_CLIQUE=4 PYTHONPATH=src python3 "$B/coverage_report.py" >> "$LOG" 2>&1
echo "=== final6 DONE rc=$? $(date -Is) ===" >> "$LOG"
