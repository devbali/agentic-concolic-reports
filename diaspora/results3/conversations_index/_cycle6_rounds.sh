#!/bin/bash
# cycle 6 — full from-scratch corpus regeneration (T-f language decision +
# terminal, devise finder ORDER/LIMIT note, participants join operand order).
# slot lock taken once per launch, INSIDE the systemd unit that runs this.
set -u
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/conversations_index
MAXR=${MAXR:-12000}
for v in html_plain html_withcid json_plain json_withcid mobile_plain mobile_withcid; do
  echo "=== ROUND $v MAX_RUNS=$MAXR $(date +%H:%M:%S) ==="
  MAX_RUNS=$MAXR TIME_BUDGET=5400 VARIANTS=$v \
    flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 \
    | grep -viE 'deprecat|fog\]|Ignoring activerecord|Top level ::' | tail -12
  cp "$B/exploration_summary.json" "$B/_exploration_$v.json" 2>/dev/null
done
echo "dumps: $(find $B -maxdepth 1 -name 'dump_*.json' | wc -l)"
echo ROUNDS6_DONE
