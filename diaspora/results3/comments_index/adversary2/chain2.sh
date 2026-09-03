#!/usr/bin/env bash
ADV=/home/dev/project/reports/diaspora/results3/comments_index/adversary2
for n in "$@"; do "$ADV/run2.sh" "$n"; done
echo "CHAIN-DONE $* $(date +%T)" >> "$ADV/runs/_progress.log"
