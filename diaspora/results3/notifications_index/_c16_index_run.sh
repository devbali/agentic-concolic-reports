#!/bin/bash
# C16 — corpus index over the CURRENT base snapshot (_snapshot_c14_R2.txt,
# 129 521 runs = the corpus the C15 R2 §16e pass was measured on). Same
# `_c13_index.py`, same 440-expression universe file as C14.
set -u; cd "$(dirname "$0")"
source ./_wait_mem.sh
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do echo "[$(date -Is)] C16-INDEX WAIT free<4G"; sleep 30; done
wait_mem 3072 c16index
echo "[$(date -Is)] C16-INDEX START universe=_c14_universe_gaps.json list=${DUMP_LIST}"
/usr/bin/time -v python3 -u _c13_index.py
echo "[$(date -Is)] C16-INDEX-EXIT rc=$?"
