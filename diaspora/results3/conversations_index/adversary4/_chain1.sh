#!/usr/bin/env bash
cd /home/dev/project/reports/diaspora/results3/conversations_index/adversary4
ADV4_DEVISE_WARDEN=1 ./run_scenario.sh Q01_devise_warden
ADV4_REAL_LAYOUT=1 ./run_scenario.sh Q02_real_layout
ADV4_REAL_LAYOUT=1 ./run_scenario.sh Q02b_real_layout_unread
echo "CHAIN1-FINISHED $(date +%T)" >> runs/_progress.log
