#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
TAG="${1:-S1}"; GLOB="${2:-dump_*S1*.json}"; CAP="${3:-2G}"
cd "$B"
echo "[$(date -Is)] audit $TAG cap=$CAP avail=$(free -m|awk '/^Mem/{print $7}')MB"
. /home/dev/project/reports/diaspora/results3/notifications_index/_wait_mem.sh
wait_mem 2048 "$(basename "$0")"
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- \
  env TAG="$TAG" CUBES="$B/_remaining_e1.jsonl" CUBE_SAMPLE="${CUBE_SAMPLE:-1500}" \
  SEED_AUDIT_SAMPLE="${SEED_AUDIT_SAMPLE:-2500}" PYTHONPATH=/home/dev/project/src \
  python3 -u "$B/_seed_audit.py" --glob "$GLOB" > "$B/_c10_audit_${TAG}.log" 2>&1
rc=$?
echo "[$(date -Is)] audit $TAG EXIT rc=$rc"
[ "$rc" != "0" ] && { echo "*** AUDIT FAILED rc=$rc ***"; systemctl --user status "run-*" 2>/dev/null|tail -3; tail -8 "$B/_c10_audit_${TAG}.log"; exit $rc; }
cat "$B/_c10_audit_${TAG}.log"
