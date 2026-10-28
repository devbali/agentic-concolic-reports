#!/bin/bash
# §14 coverage pass — with the 2026-09-10 src memory fix (blake2b profile key).
# Own slice (concolic-cov.slice), MemoryMax=8G, `python3 -u`, exit code CHECKED,
# PID printed so a waiter polls THAT (never pgrep -f, which self-matches).
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
LIST="$1"; TAG="${2:-c10}"; CAP="${3:-5G}"
cd "$B"
AV=$(free -m|awk '/^Mem/{print $7}')
echo "[$(date -Is)] pass $TAG list=$LIST cap=$CAP avail=${AV}MB"
ps -eo rss,args --sort=-rss | head -4 | cut -c1-110
. /home/dev/project/reports/diaspora/results3/notifications_index/_wait_mem.sh
wait_mem 5120 "$(basename "$0")"   # cage lowered to 6G/high 5G, 2026-09-11
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c10_pass_${TAG}.time" \
  env DUMP_LIST="$LIST" PYTHONPATH=/home/dev/project/src \
  SKIP_COMPLETION="${SKIP_COMPLETION:-1}" \
  MAX_MISSING_PER_CLIQUE="${MAX_MISSING_PER_CLIQUE:-16}" \
  MISSING_CAP="${MISSING_CAP:-40000}" \
  SUMMARY_OUT="${SUMMARY_OUT:-}" \
  python3 -u "$B/coverage_report.py" > "$B/_c10_cov_${TAG}.log" 2>&1
rc=$?
echo "[$(date -Is)] pass $TAG EXIT rc=$rc"
if [ "$rc" != "0" ] && [ "$rc" != "1" ]; then
  echo "*** PASS $TAG FAILED rc=$rc (137 = cgroup SIGKILL at MemoryMax=$CAP) ***"
  tail -10 "$B/_c10_cov_${TAG}.log"; exit "$rc"
fi
# rc=1 is the DOCUMENTED "not complete" exit of coverage_report.py, not a failure.
grep -E '^OVERALL_COMPLETE=|^COMPLETE=|^GENUINE=|^dump_errors=|^wrote |peak RSS' "$B/_c10_cov_${TAG}.log"
grep -E 'Maximum resident|Elapsed' "$B/_c10_pass_${TAG}.time"
exit 0
