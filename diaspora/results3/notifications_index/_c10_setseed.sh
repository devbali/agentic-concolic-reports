#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
TARGETS="$1"; LIST="$2"; TAG="${3:-S1}"; CAP="${4:-4G}"
cd "$B"
echo "[$(date -Is)] setseed $TAG avail=$(free -m|awk '/^Mem/{print $7}')MB"
. /home/dev/project/reports/diaspora/results3/notifications_index/_wait_mem.sh
wait_mem 4096 "$(basename "$0")"
systemd-run --user --scope --slice=concolic-cov.slice -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c10_setseed_${TAG}.time" \
  env TARGETS="$TARGETS" DUMP_LIST="$LIST" TAG="$TAG" FORECL_IN="$B/_forecl.json" \
  PYTHONPATH=/home/dev/project/src \
  python3 -u "$B/_set_root.py" > "$B/_c10_setseed_${TAG}.log" 2>&1
rc=$?
echo "[$(date -Is)] setseed $TAG EXIT rc=$rc"
[ "$rc" != "0" ] && { echo "*** SETSEED FAILED rc=$rc ***"; tail -15 "$B/_c10_setseed_${TAG}.log"; exit $rc; }
grep -E "TARGETS |indexed |overlay seed dicts|emitted |leaf groups with|SOLVER|other:|FLIPPED" "$B/_c10_setseed_${TAG}.log"
grep -E 'Maximum resident|Elapsed' "$B/_c10_setseed_${TAG}.time"
