#!/bin/bash
set -u; cd "$(dirname "$0")"
source ./_wait_mem.sh
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do echo "[$(date -Is)] C14-CONSTRUCT WAIT free<4G"; sleep 30; done
wait_mem 8192 c14construct
echo "[$(date -Is)] C14-CONSTRUCT START"
/usr/bin/time -v python3 -u _c14_construct.py
echo "[$(date -Is)] C14-CONSTRUCT-EXIT rc=$?"
