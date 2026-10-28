#!/bin/bash
# P44 — the WIDTH SWEEP. Three disjoint slices of round T's seeds, one per
# total JRuby width, legs CONCURRENT in every arm. Each arm reports its own
# sustained rate and the box load it ran under, because this box is shared and
# a rate quoted without the load it was measured at is not a measurement.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
L="$B/_p44_width_sweep.log"; : > "$L"
for A in "W08 8" "W12 12" "W14 14"; do
  set -- $A; S="$1"; W="$2"
  echo "[$(date -Is)] ARM $S width=$W  load before: $(cut -d' ' -f1-3 /proc/loadavg)" >> "$L"
  t0=$(date +%s)
  bash "$B/_p44_drive_par.sh" "$S" "P44$S" 125 "$W"
  t1=$(date +%s)
  n=$(find "$B" -maxdepth 1 -name "dump_*P44$S*.json" | wc -l)
  echo "[$(date -Is)] ARM $S width=$W dumps=$n wall=$((t1-t0))s RATE=$(python3 -c "print(f'{$n/($t1-$t0):.2f}')") runs/s  load after: $(cut -d' ' -f1-3 /proc/loadavg)" >> "$L"
done
echo "P44-WIDTH-SWEEP-DONE" >> "$L"
