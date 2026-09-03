#!/bin/bash
# cycle 5 — checker-demanded exploration round.
set -u
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/conversations_index
MAXR=${MAXR:-12000}
SUF=${SUF:-_d1}
for v in html_plain html_withcid json_plain json_withcid mobile_plain mobile_withcid; do
  [ -f "$B/_demand_$v.json" ] || continue
  echo "=== DEMAND $v ==="
  MAX_RUNS=$MAXR TIME_BUDGET=5400 VARIANTS=$v EXTRA_SEEDS_JSON="$B/_demand_$v.json" LABEL_SUFFIX="$SUF" \
    flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 \
    | grep -viE 'deprecat|fog\]|Ignoring activerecord|Top level ::' | tail -12
  cp "$B/exploration_summary.json" "$B/_demand_res${SUF}_$v.json" 2>/dev/null
done
echo "dumps: $(ls $B/dump_*.json | wc -l)"
echo DONE
