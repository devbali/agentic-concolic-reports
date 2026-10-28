#!/bin/bash
# §12 phase-2 coverage pass. Own slice; pruned snapshot via DUMP_LIST; MMC=16.
# Same two fixes as _c9_census.sh: `python3 -u` and a CHECKED exit code, so a
# cgroup SIGKILL can never read as "still running" (§12.7).
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
LIST="$1"; TAG="${2:-c9}"; CAP="${3:-10G}"
cd "$B"
echo "[$(date -Is)] pass $TAG list=$LIST cap=$CAP free=$(free -g|awk '/^Mem/{print $7}')GB"
systemd-run --user --scope -p MemoryMax="$CAP" --quiet \
  env DUMP_LIST="$LIST" PYTHONPATH=/home/dev/project/src \
  SKIP_COMPLETION="${SKIP_COMPLETION:-1}" MAX_MISSING_PER_CLIQUE=16 MISSING_CAP=20000 \
  SUMMARY_OUT="${SUMMARY_OUT:-}" \
  python3 -u "$B/coverage_report.py" > "$B/_c9_cov_${TAG}.log" 2>&1
rc=$?
echo "[$(date -Is)] pass $TAG EXIT rc=$rc"
[ "$rc" != "0" ] && echo "*** PASS $TAG FAILED rc=$rc (137 = cgroup SIGKILL at MemoryMax=$CAP) ***"
tail -8 "$B/_c9_cov_${TAG}.log"
exit $rc
