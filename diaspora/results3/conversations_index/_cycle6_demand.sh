#!/bin/bash
# one demand round per variant, from demand_round.py's _demand_<variant>.json
set -u
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/conversations_index
SUF=${SUF:-_d}
for v in html_plain html_withcid json_plain json_withcid mobile_plain mobile_withcid; do
  f="$B/_demand_$v.json"
  [ -f "$f" ] || continue
  echo "=== DEMAND $v ($SUF) $(date +%H:%M:%S) ==="
  MAX_RUNS=${MAXR:-7000} TIME_BUDGET=3600 VARIANTS=$v EXTRA_SEEDS_JSON="$f" LABEL_SUFFIX=$SUF \
    flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 \
    | grep -viE 'deprecat|fog\]|Ignoring activerecord|Top level ::' | tail -8
done
echo DEMAND_DONE
