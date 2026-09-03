#!/usr/bin/env bash
ADV=/home/dev/project/reports/diaspora/results3/comments_index/adversary6
for n in "$@"; do "$ADV/run6.sh" "$n"; done
echo "CHAIN-DONE $* $(date +%T)" >> "$ADV/runs/_done.log"
