#!/bin/bash
# UNIFIED MEMORY RULE (coordinator, 2026-09-11), replacing name-pattern gating:
# before ANY launch >= 1 GB, require BOTH
#     free -g available          >= 2
#     (4 GiB - slice MemoryCurrent) >= the cap  [cage lowered to 4G/high 3G, 2026-09-11 19:46]
# poll every 30 s until both hold, and LOG the two numbers at launch.
# usage: wait_mem <cap_in_MB> <label>
wait_mem() {
  local cap_mb="$1" label="$2" i=0 fg cur head
  while :; do
    fg=$(free -g | awk '/^Mem/{print $7}')
    cur=$(systemctl --user show concolic-cov.slice -p MemoryCurrent --value 2>/dev/null); case "$cur" in ''|*[!0-9]*) cur=0;; esac
    # 2026-09-11 21:30 (post-reboot, 64 GB box, slice MemoryMax=24G): read the LIVE cap
    mx=$(systemctl --user show concolic-cov.slice -p MemoryMax --value 2>/dev/null); case "$mx" in ''|infinity|*[!0-9]*) mx=4294967296;; esac
    head=$(( (mx - ${cur:-0}) / 1048576 ))
    if [ "${fg:-0}" -ge 2 ] && [ "$head" -ge "$cap_mb" ]; then
      echo "[$(date -Is)] $label LAUNCH: free=${fg}G cage_headroom=${head}MB cap=${cap_mb}MB"
      return 0
    fi
    if [ $((i % 10)) -eq 0 ]; then
      echo "[$(date -Is)] $label WAIT: free=${fg}G (need >=2) cage_headroom=${head}MB (need >=${cap_mb}MB)"
    fi
    i=$((i+1)); sleep 30
  done
}
