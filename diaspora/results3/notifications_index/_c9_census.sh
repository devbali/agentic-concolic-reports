#!/bin/bash
# §12 phase-2 census: exact §16b demanded/covered/remaining on a fixed snapshot.
#
# TWO DEFECTS FIXED 2026-09-10 (coordinator, §12.7):
#  * `python3 -u`. Without it stdout is block-buffered, so when the process is
#    SIGKILLed the log's last line is whatever last filled a 4 KB buffer, not
#    where it died. The 17:25 kill looked like a silent stall for that reason.
#  * MemoryMax. The first attempt at 8G was killed (rc=137) in `build_universe`
#    on the 96 148-profile corpus. The cap is now a parameter and the exit code
#    is CHECKED and printed, so a cgroup kill can never read as "still running".
# The PID is printed so a waiter can poll THAT, never `pgrep -f _exact_enum.py`
# (which matches the waiter's own bash -c command line: self-match, four times
# this session).
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
LIST="$1"; TAG="${2:-c9}"; CAP="${3:-12G}"
cd "$B"
echo "[$(date -Is)] census $TAG list=$LIST cap=$CAP free=$(free -g|awk '/^Mem/{print $7}')GB"
systemd-run --user --scope -p MemoryMax="$CAP" --quiet \
  env DUMP_LIST="$LIST" PYTHONPATH=/home/dev/project/src \
  python3 -u "$B/_exact_enum.py" --json-out "$B/_c9_census_${TAG}.json" \
  > "$B/_c9_census_${TAG}.log" 2>&1
rc=$?
echo "[$(date -Is)] census $TAG EXIT rc=$rc"
if [ "$rc" != "0" ]; then
  echo "*** CENSUS $TAG FAILED rc=$rc (137 = cgroup SIGKILL at MemoryMax=$CAP) ***"
  tail -5 "$B/_c9_census_${TAG}.log"; exit "$rc"
fi
grep -E 'evaluation sets|foreclosures inferred|tree_missing|nodes\(active\)|^EXACT:|^FORECLOSURE:|wide sets' "$B/_c9_census_${TAG}.log"
