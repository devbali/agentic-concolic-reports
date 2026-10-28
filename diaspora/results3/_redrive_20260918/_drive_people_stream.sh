#!/usr/bin/env bash
# people_stream note-refresh re-drive (2026-09-18).
# SEEDS_ONLY replay of the EXACT 13,677 concolic_seeds recorded in the existing
# proven-complete corpus, one pass per scenario, so the notes are re-recorded
# under the current runtime + the 2026-09-15 B-3 as_api_response fix.
# Explores nothing new: SEEDS_ONLY=1 replays roots and pushes no flip frontier.
set -uo pipefail
RD=/home/dev/project/reports/diaspora/results3/_redrive_20260918
PS=/home/dev/project/reports/diaspora/results3/people_stream
for scen in anon_all anon_json auth_json; do
  n=$(/home/dev/project/venvs/queries_from_runs/bin/python3 -c "import json;print(len(json.load(open('$RD/_seeds_$scen.json'))))")
  echo "=== DRIVE $scen seeds=$n $(date -Is) ==="
  EXTRA_SEEDS_JSON="$RD/_seeds_$scen.json" SEEDS_ONLY=1 SCENARIO_ONLY="$scen" \
    LABEL_SUFFIX=_RD918 MAX_RUNS=$((n + 10)) TIME_BUDGET=14400 \
    bash /home/dev/project/scripts/diaspora-concolic "$PS/run_dse.rb" \
    > "$RD/_drive_${scen}.log" 2>&1
  rc=$?
  produced=$(ls "$PS"/dump_${scen}*_RD918.json 2>/dev/null | wc -l)
  echo "=== DONE $scen exit=$rc produced=$produced expected=$n $(date -Is) ==="
done
echo "VERDICT_REDRIVE_PEOPLE_STREAM_DONE $(date -Is)"
