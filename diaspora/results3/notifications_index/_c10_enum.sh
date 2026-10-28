#!/bin/bash
# §16 target enumeration: the EXACT remaining set, emitted with member
# assignments. Own slice, python3 -u, exit code checked, PID printed.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
LIST="$1"; TAG="${2:-e1}"; CAP="${3:-5G}"
cd "$B"
echo "[$(date -Is)] enum $TAG list=$LIST cap=$CAP avail=$(free -m|awk '/^Mem/{print $7}')MB"
. /home/dev/project/reports/diaspora/results3/notifications_index/_wait_mem.sh
wait_mem 5120 "$(basename "$0")"
systemd-run --user --scope --slice=concolic-cov.slice -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c10_enum_${TAG}.time" \
  env DUMP_LIST="$LIST" PYTHONPATH=/home/dev/project/src REACH_SPLIT=1 \
  EMIT_REMAINING="$B/_remaining_${TAG}.jsonl" \
  python3 -u "$B/_exact_enum.py" --json-out "$B/_c10_enum_${TAG}.json" \
  > "$B/_c10_enum_${TAG}.log" 2>&1
rc=$?
echo "[$(date -Is)] enum $TAG EXIT rc=$rc"
[ "$rc" != "0" ] && { echo "*** ENUM $TAG FAILED rc=$rc ***"; tail -8 "$B/_c10_enum_${TAG}.log"; exit $rc; }
grep -E 'evaluation sets|foreclosures inferred|tree_missing|nodes\(active\)|^EXACT:|^FORECLOSURE:|wide sets|EMIT_REMAINING|EMIT/COUNT|REACHABLE|MULTI-GATE' "$B/_c10_enum_${TAG}.log"
grep -E 'Maximum resident' "$B/_c10_enum_${TAG}.time"
