#!/usr/bin/env bash
cd /home/dev/project/reports/diaspora/results3/conversations_index/adversary3
for n in P01_page_domain P02_cid_shapes P03_formats P10_locale_leak P11_layout_gon_probe; do
  ./run_scenario.sh ${n}
done
echo "CHAIN2-FINISHED $(date +%T)" >> runs/_progress.log
