#!/usr/bin/env bash
cd /home/dev/project/reports/diaspora/results3/conversations_index/adversary6
for n in "$@"; do ./run_scenario.sh "$n"; done
echo "CHAIN DONE $(date +%T)" >> _progress.log
