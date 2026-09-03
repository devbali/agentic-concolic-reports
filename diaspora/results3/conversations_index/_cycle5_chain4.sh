#!/bin/bash
# after the B-4/B-5 regeneration: coverage -> demand _e1 -> coverage -> demand _e2 -> coverage
set -u
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
until grep -q '^DONE' "$B/_regen6.log" 2>/dev/null; do sleep 20; done
echo "regen6 finished $(date +%H:%M); dumps=$(find $B -maxdepth 1 -name 'dump_*.json'|wc -l)"
for r in e1 e2 e3; do
  echo "--- coverage before $r ---"
  "$B/_cycle5_cov.sh" > "$B/_cov6_$r.log" 2>&1
  grep -E 'COMPLETE=|loaded|EXIT=' "$B/_cov6_$r.log"
  M=$(python3 -c "import json;print(json.load(open('$B/coverage_summary.json'))['missing_branches'])")
  echo "missing=$M"
  [ "$M" = "0" ] && { echo "COVERAGE_COMPLETE"; break; }
  python3 "$B/demand_round.py"
  SUF=_$r "$B/_cycle5_demand.sh" > "$B/_demand6_$r.log" 2>&1
  grep -E '^===|distinct paths|run errors' "$B/_demand6_$r.log" | tail -20
  echo "dumps=$(find $B -maxdepth 1 -name 'dump_*.json'|wc -l)"
done
echo CHAIN4_DONE
