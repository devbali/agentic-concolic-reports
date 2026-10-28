#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
REM="$1"; LIST="$2"; TAG="${3:-CT}"; PER="${4:-4}"; CAP="${5:-3G}"
cd "$B"
echo "[$(date -Is)] construct $TAG rem=$REM per=$PER cap=$CAP avail=$(free -m|awk '/^Mem/{print $7}')MB"
. /home/dev/project/reports/diaspora/results3/notifications_index/_wait_mem.sh
wait_mem 3072 "$(basename "$0")"
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- \
  env DUMP_LIST="$LIST" PER_COMBO="$PER" OUT_ROOTS="$B/_construct_${TAG}_roots.json" \
  PYTHONPATH=/home/dev/project/src \
  python3 -u "$B/_construct_all.py" "$REM" > "$B/_c10_construct_${TAG}.log" 2>&1
rc=$?
echo "[$(date -Is)] construct $TAG EXIT rc=$rc"
[ "$rc" != "0" ] && { echo "*** CONSTRUCT FAILED rc=$rc ***"; tail -10 "$B/_c10_construct_${TAG}.log"; exit $rc; }
tail -12 "$B/_c10_construct_${TAG}.log"
