#!/bin/bash
# cycle 6 — FULL engine report: coverage + completion gate (shims, note check,
# assumptions, extra audits). heavy taken ONCE, outermost, INSIDE the systemd
# unit that runs this script; the gate's own probes take the slot lock per
# JRuby launch (assumption_manifest.json `runner`, completion_config `test_cmd`).
set -u
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
echo "[heavy] waiting $(date +%H:%M:%S)"
flock /tmp/concolic-heavy.lock bash -c '
echo "[heavy] acquired $(date +%H:%M:%S)"; free -m | head -2
MAX_MISSING_PER_CLIQUE=4 PYTHONPATH=/home/dev/project/src \
  python3 /home/dev/project/reports/diaspora/results3/conversations_index/coverage_report.py'
echo "EXIT=$?"
echo "[heavy] released $(date +%H:%M:%S)"
echo REPORT6_DONE
