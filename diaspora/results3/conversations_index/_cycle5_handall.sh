#!/bin/bash
# targeted-seed round over every variant that has a _hand_<v>.json
set -u
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/conversations_index
SUF=${SUF:-_h1}
MAXR=${MAXR:-4000}
for v in html_plain html_withcid json_plain json_withcid mobile_plain mobile_withcid; do
  [ -f "$B/_hand_$v.json" ] || continue
  echo "=== HAND $v (SUF=$SUF) ==="
  MAX_RUNS=$MAXR TIME_BUDGET=3600 VARIANTS=$v EXTRA_SEEDS_JSON="$B/_hand_$v.json" LABEL_SUFFIX="$SUF" \
    flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 \
    | grep -viE 'deprecat|fog\]|Ignoring activerecord|Top level ::' | tail -12
done
echo DONE
