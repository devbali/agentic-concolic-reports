#!/bin/bash
# Sustained probe rate from ROOT counts (never batch counts — a batch-counting
# sampler read 5x low once the batch size moved, §93.6/§92.6c). Sums the
# `N roots` field of each `[probe batch ...]` line, over a wall window.
# usage: _p32_ratesample.sh <log> <window_s>
L="$1"; W="${2:-300}"
roots() { grep -oE '\[probe batch [0-9]+: [0-9]+ roots' "$L" 2>/dev/null | awk '{s+=$4} END{print s+0}'; }
r0=$(roots); t0=$(date +%s)
sleep "$W"
r1=$(roots); t1=$(date +%s)
mem=$(systemctl --user show concolic-cov.slice -p MemoryCurrent --value)
peak=$(systemctl --user show "${UNIT:-x}" -p MemoryPeak --value 2>/dev/null)
printf 'SAMPLE window=%ss roots=%d rate=%.2f/s slice_mem=%.1fG unit_peak=%sG load=%s\n' \
  "$((t1-t0))" "$((r1-r0))" "$(echo "scale=4;($r1-$r0)/($t1-$t0)" | bc)" \
  "$(echo "scale=2;$mem/1073741824" | bc)" \
  "$(echo "scale=2;${peak:-0}/1073741824" | bc)" \
  "$(cut -d' ' -f1-3 /proc/loadavg)"
