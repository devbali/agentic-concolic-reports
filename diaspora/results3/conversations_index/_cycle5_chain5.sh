#!/bin/bash
# after chain4: targeted-seed rounds until missing == 0
set -u
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
until grep -q 'CHAIN4_DONE' "$B/_chain4.log" 2>/dev/null; do sleep 20; done
M=$(python3 -c "import json;print(json.load(open('$B/coverage_summary.json'))['missing_branches'])")
echo "chain4 finished; missing=$M"
for r in h1 h2 h3; do
  [ "$M" = "0" ] && break
  echo "--- hand seeds ($r) ---"
  python3 "$B/mk_hand_seeds.py"
  echo "--- hand round $r ---"
  SUF=_$r MAXR=5000 "$B/_cycle5_handall.sh" > "$B/_hand6_$r.log" 2>&1
  grep -E '^===|distinct paths|run errors' "$B/_hand6_$r.log" | tail -20
  echo "dumps=$(find $B -maxdepth 1 -name 'dump_*.json'|wc -l)"
  echo "--- coverage after $r ---"
  "$B/_cycle5_cov.sh" > "$B/_cov6_after_$r.log" 2>&1
  grep -E 'COMPLETE=|loaded|EXIT=' "$B/_cov6_after_$r.log"
  M=$(python3 -c "import json;print(json.load(open('$B/coverage_summary.json'))['missing_branches'])")
  echo "missing=$M"
done
echo "FINAL_MISSING=$M"
echo CHAIN5_DONE
