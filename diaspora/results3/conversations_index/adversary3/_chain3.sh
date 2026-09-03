#!/usr/bin/env bash
cd /home/dev/project/reports/diaspora/results3/conversations_index/adversary3
until grep -q 'CHAIN2-FINISHED' runs/_progress.log; do sleep 20; done
./run_scenario.sh P12_unread_negative
echo "CHAIN3-FINISHED $(date +%T)" >> runs/_progress.log
