#!/usr/bin/env bash
cd /home/dev/project/reports/diaspora/results3/conversations_index/adversary4
./run_scenario.sh Q04_reverify
./run_scenario.sh Q03_page_multiplicity
echo "CHAIN2-FINISHED $(date +%T)" >> runs/_progress.log
