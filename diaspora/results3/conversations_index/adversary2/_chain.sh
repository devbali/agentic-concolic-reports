#!/usr/bin/env bash
cd /home/dev/project/reports/diaspora/results3/conversations_index/adversary2
: > runs/_progress.log
for n in N01_diaspora_post_links R01_mobile_session N02_many_messages_unread N04_edge2_noprofile_principal N05_pagination_15_boundary N03_malformed_params R02_mobile_header R04_noprofile_participant R05_solo_conversation R06_pagination_16 R07_js_and_empty R08_edge_control R09_lang_pl R10_cid_variants; do
  ./run_scenario.sh $n
done
COV=0 ./run_scenario.sh R03_noprofile_last_author
echo "CHAIN-FINISHED $(date +%T)" >> runs/_progress.log
