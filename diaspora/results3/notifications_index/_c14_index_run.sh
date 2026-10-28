#!/bin/bash
set -u; cd "$(dirname "$0")"
source ./_wait_mem.sh
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do echo "[$(date -Is)] C14-INDEX WAIT free<4G"; sleep 30; done
wait_mem 4096 c14index
echo "[$(date -Is)] C14-INDEX START universe=_c14_universe_gaps.json list=_snapshot_c13_R2.txt"
/usr/bin/time -v python3 -u _c13_index.py
echo "[$(date -Is)] C14-INDEX-EXIT rc=$?"
