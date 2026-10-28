#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
OLDP="$1"; CAP="${2:-2500M}"
cd "$B"
echo "[$(date -Is)] snapshot+prune old=$OLDP cap=$CAP avail=$(free -m|awk '/^Mem/{print $7}')MB"
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- ./_c10_snapshot.sh "$OLDP" 2 > "$B/_c10_snap.log" 2>&1
rc=$?
echo "[$(date -Is)] snapshot+prune EXIT rc=$rc"
[ "$rc" != "0" ] && { echo "*** SNAP FAILED rc=$rc ***"; tail -8 "$B/_c10_snap.log"; exit $rc; }
grep -E "population:|pruned:|PRUNED=" "$B/_c10_snap.log"
