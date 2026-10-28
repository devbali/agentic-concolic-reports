#!/bin/bash
# §14 equivalence census: the SAME census as §12.8, but the profile key now
# comes from src/concolic_engine/coverage.py:profile_key (the 2026-09-10 memory
# fix), imported by _exact_enum.py instead of copied. Fourteen numbers must be
# byte-identical to _c9_census_c9pruned.log.
#
# Own slice (concolic-cov.slice), `python3 -u`, CHECKED exit code, PID printed,
# and /usr/bin/time -v for the peak RSS.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
LIST="$1"; TAG="${2:-c10}"; CAP="${3:-4600M}"
cd "$B"
echo "[$(date -Is)] census $TAG list=$LIST cap=$CAP avail=$(free -m|awk '/^Mem/{print $7}')MB"
. /home/dev/project/reports/diaspora/results3/notifications_index/_wait_mem.sh
wait_mem 4600 "$(basename "$0")"   # cage lowered to 6G/high 5G, 2026-09-11
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c10_census_${TAG}.time" \
  env DUMP_LIST="$LIST" PYTHONPATH=/home/dev/project/src \
  NO_GATE_WITHDRAW="${NO_GATE_WITHDRAW:-}" EMIT_REMAINING="${EMIT_REMAINING:-}" \
  python3 -u "$B/_exact_enum.py" --json-out "$B/_c10_census_${TAG}.json" \
  > "$B/_c10_census_${TAG}.log" 2>&1
rc=$?
echo "[$(date -Is)] census $TAG EXIT rc=$rc"
if [ "$rc" != "0" ]; then
  echo "*** CENSUS $TAG FAILED rc=$rc (137 = cgroup SIGKILL at MemoryMax=$CAP) ***"
  tail -8 "$B/_c10_census_${TAG}.log"; exit "$rc"
fi
grep -E 'evaluation sets|foreclosures inferred|tree_missing|nodes\(active\)|^EXACT:|^FORECLOSURE:|wide sets' "$B/_c10_census_${TAG}.log"
grep -E 'Maximum resident' "$B/_c10_census_${TAG}.time"
