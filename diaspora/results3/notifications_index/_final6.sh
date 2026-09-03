#!/bin/bash
# FINAL engine report: coverage + completion (shims, note check, MANDATORY
# assumption gate, extra audits). coverage_report.py takes the HEAVY lock
# around the Z3 pass itself and releases it before the gate; the gate's probes
# take the SLOT lock per launch.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_final6.log"; echo "=== final6 start $(date -Is) ===" > "$LOG"
MAX_MISSING_PER_CLIQUE=4 PYTHONPATH=src python3 "$B/coverage_report.py" >> "$LOG" 2>&1
echo "=== final6 DONE rc=$? $(date -Is) ===" >> "$LOG"
