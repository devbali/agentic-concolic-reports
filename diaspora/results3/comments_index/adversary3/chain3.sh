#!/usr/bin/env bash
ADV=/home/dev/project/reports/diaspora/results3/comments_index/adversary3
for n in "$@"; do "$ADV/run3.sh" "$n"; done
echo "CHAIN-DONE $* $(date +%T)" >> "$ADV/runs/_progress.log"
