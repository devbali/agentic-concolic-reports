#!/bin/bash
set -u
P=/home/dev/project; B=$P/reports/diaspora/results3/comments_index
cd $P
unset JAVA_TOOL_OPTIONS
export CONCOLIC_SLOTS=2 CONCOLIC_PROBE_WORKERS=2 PYTHONPATH=$P/src
echo "START $(date -Is)  SLOTS=$CONCOLIC_SLOTS WORKERS=$CONCOLIC_PROBE_WORKERS"
( while true; do
    a=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
    j=$(ps -eo rss,comm --no-headers | awk '$2=="java"{n++; s+=$1} END{printf "%d jvm %d MB", n, s/1024}')
    echo "  [tick $(date +%T)] MemAvailable=${a}MB  $j"
    sleep 60
  done ) &
TICK=$!
/usr/bin/time -v python3 $P/src/end_to_end_completion_checker/assumption/assumption_checker.py \
  $B/assumption_manifest.json --declared $B/_assumptions_declared.json \
  --json-out $B/_c10/assumption_results_par.json 2>&1 | tail -60
echo "ENDED $(date -Is)"
kill $TICK 2>/dev/null
