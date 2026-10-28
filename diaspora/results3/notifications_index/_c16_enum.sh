#!/bin/bash
# C16 — full remaining-cube enumeration UNDER §16e (DISCIPLINE §16e).
#   usage: [FORECLOSURE_CONJUNCTIONS=0|1] bash _c16_enum.sh
# Streamed (python3 -u), caged, judged by its own `^EXACT:` line.
set -u
cd "$(dirname "$0")"
source ./_wait_mem.sh
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do
  echo "[$(date -Is)] C16-ENUM WAIT: free<4G"; sleep 30
done
wait_mem "${CAPMB:-6144}" c16enum
echo "[$(date -Is)] C16-ENUM START DUMP_LIST=${DUMP_LIST} CONJ=${FORECLOSURE_CONJUNCTIONS:-1} EMIT=${EMIT_REMAINING:-}"
echo "[$(date -Is)] engine coverage.py md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"
/usr/bin/time -v python3 -u _c16_enum.py --json-out "${C16_ENUM_JSON:-_c16_enum.json}"
rc=$?
echo "[$(date -Is)] C16-ENUM-DONE rc=$rc"
