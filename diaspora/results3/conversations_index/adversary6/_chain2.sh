#!/usr/bin/env bash
cd /home/dev/project/reports/diaspora/results3/conversations_index/adversary6
while pgrep -f "run_scenario.sh R02_cid_overflow" >/dev/null; do sleep 5; done
for n in "$@"; do ./run_scenario.sh "$n"; done
echo "CHAIN DONE $(date +%T)" >> _progress.log
