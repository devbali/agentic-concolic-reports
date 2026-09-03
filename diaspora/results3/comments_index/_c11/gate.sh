#!/bin/bash
set -u
P=/home/dev/project; B=$P/reports/diaspora/results3/comments_index
cd $P; unset JAVA_TOOL_OPTIONS
export CONCOLIC_SLOTS=2 CONCOLIC_PROBE_WORKERS=${WORKERS:-2} PYTHONPATH=$P/src
echo "GATE START $(date -Is) WORKERS=$CONCOLIC_PROBE_WORKERS"
( while true; do
    a=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
    j=$(ps -eo rss,comm --no-headers | awk '$2=="java"{n++; s+=$1} END{printf "%d jvm %d MB", n, s/1024}')
    d=$(ps -eo rss,args --no-headers | awk '/assumption_checker.py/ && !/awk/{printf "drv %d MB", $1/1024; exit}')
    echo "  [tick $(date +%T)] avail=${a}MB $j $d"; sleep 60
  done ) & TICK=$!
# capture the FULL stream (the engine keeps only a stdout tail, which is why
# the traceback was invisible) — coordinator directive, cycle 11.
/usr/bin/time -v python3 $P/src/end_to_end_completion_checker/assumption/assumption_checker.py \
  $B/assumption_manifest.json --declared $B/_assumptions_declared.json \
  --json-out $B/_assumption_results.json > $B/_c11/_gate_stderr.log 2>&1
echo "DRIVER EXIT=$?"
tail -40 $B/_c11/_gate_stderr.log
echo "GATE ENDED $(date -Is)"
kill $TICK 2>/dev/null
