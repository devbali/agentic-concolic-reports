#!/bin/bash
# cycle 6 — TARGETED-SEED rounds (mk_hand_seeds.py): the coordinator's step-1
# recipe. demand_round.py replays only the clique's own variables and lets
# everything else fall back to the runner's DEFAULTS, so a combination whose
# ENABLING conditions are not themselves in the clique is replayed as the
# default path. mk_hand_seeds instead takes the corpus dump that already
# records every expr of the combination, takes THAT run's consumed seed dict,
# flips only the disagreeing conjuncts, and replays it as its own worklist ROOT.
set -u
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
until grep -q 'CHAIN6_DONE' "$B/_chain6.log" 2>/dev/null; do sleep 20; done
M=$(python3 -c "import json;print(json.load(open('$B/coverage_summary.json'))['missing_branches'])")
echo "chain6 finished $(date +%H:%M:%S); missing=$M"
for r in g1 g2 g3 g4; do
  [ "$M" = "0" ] && break
  echo "--- hand seeds ($r) $(date +%H:%M:%S) ---"
  python3 "$B/mk_hand_seeds.py" 2>&1 | tail -12
  echo "--- hand round $r ---"
  for v in html_plain html_withcid json_plain json_withcid mobile_plain mobile_withcid; do
    [ -f "$B/_hand_$v.json" ] || continue
    echo "=== HAND $v (_$r) $(date +%H:%M:%S) ==="
    MAX_RUNS=${MAXR:-6000} TIME_BUDGET=3600 VARIANTS=$v EXTRA_SEEDS_JSON="$B/_hand_$v.json" LABEL_SUFFIX="_$r" \
      flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 \
      | grep -viE 'deprecat|fog\]|Ignoring activerecord|Top level ::' | tail -6
  done
  "$B/_cycle6_dedup.sh" 2>&1 | tail -1
  echo "--- coverage after $r ---"
  "$B/_cycle6_cov.sh" > "$B/_cov7_$r.log" 2>&1
  grep -E 'COMPLETE=|loaded|EXIT=' "$B/_cov7_$r.log"
  M=$(python3 -c "import json;print(json.load(open('$B/coverage_summary.json'))['missing_branches'])")
  echo "missing=$M"
done
echo "FINAL_MISSING=$M"
echo HAND6_DONE
