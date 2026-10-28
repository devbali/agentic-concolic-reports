#!/bin/bash
# §16 graph-guided seeding: one seed per REACHABLE remaining cube.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
TARGETS="$1"; LIST="$2"; TAG="${3:-E1}"; CAP="${4:-4G}"
cd "$B"
echo "[$(date -Is)] seed $TAG targets=$TARGETS list=$LIST cap=$CAP avail=$(free -m|awk '/^Mem/{print $7}')MB"
. /home/dev/project/reports/diaspora/results3/notifications_index/_wait_mem.sh
wait_mem 4096 "$(basename "$0")"
systemd-run --user --scope --slice=concolic-cov.slice -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c10_seed_${TAG}.time" \
  env TARGETS="$TARGETS" DUMP_LIST="$LIST" TAG="$TAG" \
  FORECL_IN="$B/_forecl.json" PYTHONPATH=/home/dev/project/src \
  python3 -u "$B/_enable_root.py" > "$B/_c10_seed_${TAG}.log" 2>&1
rc=$?
echo "[$(date -Is)] seed $TAG EXIT rc=$rc"
[ "$rc" != "0" ] && { echo "*** SEED $TAG FAILED rc=$rc ***"; tail -12 "$B/_c10_seed_${TAG}.log"; exit $rc; }
grep -E "TARGETS |foreclosure relation|solved |cubes with a FREED|enabling depth|indexed |enabling-rooted|witnesses emitted|base stats|enabling gates per cube|AGREEMENT|MEMBERS the chosen" "$B/_c10_seed_${TAG}.log"
grep -E 'Maximum resident|Elapsed' "$B/_c10_seed_${TAG}.time"
