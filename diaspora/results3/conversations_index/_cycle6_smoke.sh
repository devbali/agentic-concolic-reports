#!/bin/bash
set -u
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/conversations_index
MAX_RUNS=60 TIME_BUDGET=600 VARIANTS=html_withcid LABEL_SUFFIX=_smk6 \
  flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 \
  | grep -viE 'deprecat|fog|Ignoring activerecord'
echo "SMOKE_EXIT=$?"
echo SMOKE6_DONE
