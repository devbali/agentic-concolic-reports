#!/bin/bash
# C14 — full remaining-cube enumeration off the M-SNAP-declared universe.
set -u
cd "$(dirname "$0")"
source ./_wait_mem.sh
# coordinator rule for C14: free -g >= 4 (stricter than _wait_mem's >=2)
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do
  echo "[$(date -Is)] C14-ENUM WAIT: free<4G"; sleep 30
done
wait_mem 4096 c14enum
echo "[$(date -Is)] C14-ENUM START  DUMP_LIST=_snapshot_c13_R2.txt EMIT=$EMIT_REMAINING"
/usr/bin/time -v python3 -u _exact_enum.py --json-out ${C14_ENUM_JSON:-_c14_enum.json}
rc=$?
echo "[$(date -Is)] C14-ENUM-DONE rc=$rc"
