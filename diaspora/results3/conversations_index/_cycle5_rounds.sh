#!/bin/bash
# cycle 5 — full from-scratch corpus regeneration (seed-consumption recording +
# empty-relation preload gating). One round per request variant.
set -u
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/conversations_index
MAXR=${MAXR:-12000}
for v in html_plain html_withcid json_plain json_withcid mobile_plain mobile_withcid; do
  echo "=== ROUND $v MAX_RUNS=$MAXR ==="
  MAX_RUNS=$MAXR TIME_BUDGET=5400 VARIANTS=$v \
    flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 \
    | grep -viE 'deprecat|fog\]|Ignoring activerecord|Top level ::'
  cp "$B/exploration_summary.json" "$B/_exploration_$v.json" 2>/dev/null
done
echo "dumps: $(ls $B/dump_*.json | wc -l)"
echo DONE
