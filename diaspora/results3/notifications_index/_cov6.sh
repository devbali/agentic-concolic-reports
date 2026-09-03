#!/bin/bash
# coverage-only pass (no completion gate) for the demand loop.
# MMC = MAX_MISSING_PER_CLIQUE (how many missing combos per clique to enumerate)
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
MMC="${1:-300}"; TAG="${2:-cov}"
LOG="$B/_${TAG}.log"; echo "=== $TAG (MMC=$MMC) start $(date -Is) ===" > "$LOG"
env SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE="$MMC" PYTHONPATH=src python3 "$B/coverage_report.py" >> "$LOG" 2>&1
echo "=== $TAG DONE rc=$? $(date -Is) ===" >> "$LOG"
