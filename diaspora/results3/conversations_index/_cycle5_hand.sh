#!/bin/bash
# targeted seed round for a specific missing combination
set -u
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/conversations_index
V=${V:-html_withcid}
SUF=${SUF:-_h1}
MAXR=${MAXR:-3000}
echo "=== HAND $V (SUF=$SUF) ==="
MAX_RUNS=$MAXR TIME_BUDGET=3600 VARIANTS=$V EXTRA_SEEDS_JSON="$B/_hand_$V.json" LABEL_SUFFIX="$SUF" \
  flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 \
  | grep -viE 'deprecat|fog\]|Ignoring activerecord|Top level ::' | tail -15
echo DONE
