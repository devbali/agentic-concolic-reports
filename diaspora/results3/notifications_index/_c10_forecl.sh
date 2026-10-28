#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
LIST="$1"; CAP="${2:-5G}"
cd "$B"
echo "[$(date -Is)] forecl list=$LIST cap=$CAP avail=$(free -m|awk '/^Mem/{print $7}')MB"
. /home/dev/project/reports/diaspora/results3/notifications_index/_wait_mem.sh
wait_mem 5120 "$(basename "$0")"
systemd-run --user --scope --slice=concolic-cov.slice -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- env DUMP_LIST="$LIST" PYTHONPATH=/home/dev/project/src \
  python3 -u "$B/_forecl_dump.py" --out "$B/_forecl.json" > "$B/_c10_forecl.log" 2>&1
rc=$?
echo "[$(date -Is)] forecl EXIT rc=$rc"
[ "$rc" != "0" ] && { echo "*** FORECL FAILED rc=$rc ***"; tail -8 "$B/_c10_forecl.log"; exit $rc; }
grep -E "loaded |profiles=|^active=|foreclosures inferred|wrote " "$B/_c10_forecl.log"
