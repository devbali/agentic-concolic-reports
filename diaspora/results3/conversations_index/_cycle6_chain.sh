#!/bin/bash
# cycle 6 chain: (wait for rounds) -> dedup -> coverage -> [demand -> dedup ->
# coverage] x3, stopping at missing == 0. Every coverage pass takes heavy INSIDE
# this unit, exactly once; every JRuby launch takes slot, exactly once.
set -u
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
until grep -q 'ROUNDS6_DONE' "$B/_regen7.log" 2>/dev/null; do sleep 20; done
echo "rounds finished $(date +%H:%M:%S)"
"$B/_cycle6_dedup.sh" 2>&1 | tail -2
for r in f1 f2 f3 f4; do
  echo "--- coverage before $r $(date +%H:%M:%S) ---"
  "$B/_cycle6_cov.sh" > "$B/_cov7_$r.log" 2>&1
  grep -E 'COMPLETE=|loaded|EXIT=' "$B/_cov7_$r.log"
  M=$(python3 -c "import json;print(json.load(open('$B/coverage_summary.json'))['missing_branches'])")
  echo "missing=$M"
  [ "$M" = "0" ] && { echo COVERAGE_COMPLETE; break; }
  python3 "$B/demand_round.py" | tail -3
  SUF=_$r "$B/_cycle6_demand.sh" > "$B/_demand7_$r.log" 2>&1
  grep -E '^===|distinct paths|run errors' "$B/_demand7_$r.log" | tail -20
  "$B/_cycle6_dedup.sh" 2>&1 | tail -2
done
echo CHAIN6_DONE
