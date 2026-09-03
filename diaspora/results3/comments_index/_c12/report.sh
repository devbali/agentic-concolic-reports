#!/bin/bash
set -u
P=/home/dev/project; B=$P/reports/diaspora/results3/comments_index
cd $P
unset JAVA_TOOL_OPTIONS
export CONCOLIC_SLOTS=2 CONCOLIC_PROBE_WORKERS=${WORKERS:-1} MAX_MISSING_PER_CLIQUE=64 PYTHONPATH=$P/src
echo "REPORT START $(date -Is)  SLOTS=$CONCOLIC_SLOTS WORKERS=$CONCOLIC_PROBE_WORKERS"
( while true; do
    a=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
    j=$(ps -eo rss,comm --no-headers | awk '$2=="java"{n++; s+=$1} END{printf "%d jvm %d MB", n, s/1024}')
    p=$(ps -eo rss,args --no-headers | awk '/coverage_report.py/ && !/awk/{printf "py %d MB", $1/1024; exit}')
    echo "  [tick $(date +%T)] MemAvailable=${a}MB  $j  $p"
    sleep 60
  done ) & TICK=$!
flock /tmp/concolic-heavy.lock /usr/bin/time -v python3 $B/coverage_report.py 2>&1 \
  | grep -vE "^Failed to eval" | tail -40
echo "REPORT ENDED $(date -Is)"
kill $TICK 2>/dev/null
