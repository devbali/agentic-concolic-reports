#!/bin/bash
# Caged python launcher for ANALYSIS scripts (coordinator note 2026-09-11 19:0x:
# the memory invariant applies to analysis too, not only passes).
# usage: _c11_pyrun.sh <label> <cap_MB> <script.py> [args...]
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
LABEL="$1"; CAP="$2"; shift 2
# The invariant binds "before ANY launch >= 1 GB" (_wait_mem.sh). A SMALL
# analysis job (cap < 1024 MB, streaming - no dumps, no universe) is still
# CAGED and choom'"'"'d and still respects cage headroom, but does not hold for
# free>=4: that gate exists for multi-GB jobs.
. "$B/_wait_mem.sh"
if [ "$CAP" -ge 1024 ]; then
  wait_mem "$CAP" "$LABEL"
else
  while :; do
    cur=$(systemctl --user show concolic-cov.slice -p MemoryCurrent --value 2>/dev/null)
    head=$(( (4294967296 - ${cur:-0}) / 1048576 ))
    fg=$(free -g | awk '"'"'/^Mem/{print $7}'"'"')
    if [ "$head" -ge "$CAP" ]; then
      echo "[$(date -Is)] $LABEL LAUNCH(small): free=${fg}G cage_headroom=${head}MB cap=${CAP}MB"; break
    fi
    echo "[$(date -Is)] $LABEL WAIT(small): cage_headroom=${head}MB need ${CAP}MB"; sleep 30
  done
fi
T0=$(date +%s)
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=${CAP}M -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  python3 -u "$@" > "$B/_c11_${LABEL}.out" 2>&1
rc=$?
echo "[$(date -Is)] $LABEL EXIT rc=$rc wall=$(( $(date +%s)-T0 ))s" | tee -a "$B/_c11_${LABEL}.out"
