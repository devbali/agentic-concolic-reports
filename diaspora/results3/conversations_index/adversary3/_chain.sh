#!/usr/bin/env bash
cd /home/dev/project/reports/diaspora/results3/conversations_index/adversary3
: > runs/_progress.log
for n in P01_page_domain P02_cid_shapes P03_formats P04_setread_unchanged P06_cardinality P07_row_edges P08_language; do
  ./run_scenario.sh $n
done
ADV3_REAL_LAYOUT=1 ./run_scenario.sh P05_real_layout
./run_scenario.sh P09_noprofile_lastauthor
echo "CHAIN-FINISHED $(date +%T)" >> runs/_progress.log
