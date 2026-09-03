#!/bin/bash
# C7 coverage-only pass (SKIP_COMPLETION): the clique-profile measurement the
# coordinator asked for BEFORE any big demand round.
#
# NO OUTER `flock` (fixed 2026-09-01 after a self-deadlock the coordinator
# killed at 1m47s): `coverage_report.py` ALREADY takes
# /tmp/concolic-heavy.lock itself (its _HEAVY_PATH / fcntl.flock LOCK_EX), and
# flock(2) is not reentrant across processes — a wrapper holding the same lock
# blocks its own child forever. Mutual exclusion is preserved because the
# report self-locks, and the "a launcher that dies takes its lock with it"
# property is BETTER this way: the lock lives in the process doing the work.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="${C7_COV_LOG:-$B/_c7_cov_only.log}"; echo "=== c7 coverage-only start $(date -Is) ===" > "$LOG"
echo "dumps: $(ls $B/dump_*.json 2>/dev/null | wc -l)" >> "$LOG"
echo "MemAvailable before: $(awk '/MemAvailable/{print $2/1024 " MB"}' /proc/meminfo)" >> "$LOG"
env SKIP_COMPLETION=1 MISSING_CAP=${MISSING_CAP:-12000} \
  MAX_MISSING_PER_CLIQUE=${MAX_MISSING_PER_CLIQUE:-60} \
  DUMP_SAMPLE=${DUMP_SAMPLE:-0} HEARTBEAT_SECS=${HEARTBEAT_SECS:-300} \
  PYTHONPATH=src python3 "$B/coverage_report.py" >> "$LOG" 2>&1
echo "=== c7 coverage-only DONE rc=$? $(date -Is) ===" >> "$LOG"
