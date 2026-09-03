#!/bin/bash
# after demand round _d1: coverage -> new demand seeds -> demand round _d2 -> coverage
set -u
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
until grep -q '^DONE' "$B/_demand5.log" 2>/dev/null; do sleep 20; done
echo "demand _d1 finished $(date +%H:%M); dumps=$(ls $B/dump_*.json|wc -l)"

echo "--- coverage A ---"
"$B/_cycle5_cov.sh" > "$B/_cov5_a.log" 2>&1
grep -E 'COMPLETE=|loaded|EXIT=' "$B/_cov5_a.log"

echo "--- demand seeds from A ---"
python3 "$B/demand_round.py"

echo "--- demand round _d2 ---"
SUF=_d2 "$B/_cycle5_demand.sh" > "$B/_demand5_d2.log" 2>&1
grep -E '^===|distinct paths|run errors|dumps:' "$B/_demand5_d2.log" | tail -30

echo "--- coverage B ---"
"$B/_cycle5_cov.sh" > "$B/_cov5_b.log" 2>&1
grep -E 'COMPLETE=|loaded|EXIT=' "$B/_cov5_b.log"
echo CHAIN2_DONE
