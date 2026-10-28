#!/usr/bin/env bash
# Preserve the dual corpus, then run the mobile-only shape campaign.
# The checker needs BOTH shapes declared (rows_1/2 from anon_mobile,
# rows_3/4/5 from anon_mobile_presenter).
set -euo pipefail
cd /home/dev/project/reports/diaspora/results3/people_show

mkdir -p _corpus_dual
cp dump_*.json _corpus_dual/

SCENARIO_ONLY=anon_mobile MAX_RUNS=40000 TIME_BUDGET=2700 COMPOSE_CAP=8 \
  /home/dev/.claude/jobs/302ac302/tmp/concolic-slot \
  /home/dev/project/reports/diaspora/results3/people_show/run_dse.rb \
  > _mobile_campaign.log 2>&1
echo "MOBILE_EXIT=$?"

# merge: copy dual dumps back (mobile campaign wiped them)
cp _corpus_dual/dump_*.json .
echo "MERGED: $(ls dump_*.json | wc -l) dumps"