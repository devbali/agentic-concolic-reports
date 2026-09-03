#!/bin/bash
# gen3 saturation loop: {generate flip+pair seeds -> SEEDS_ONLY replay ->
# re-measure} until the uncovered-pair count stops improving. Pure corpus
# counting + targeted replays — no wide solver enumeration (standing rule).
set -uo pipefail
HERE=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$HERE"
LOG="$HERE/_saturate_loop.log"
: > "$LOG"
prev=999999
for round in 2 3 4 5 6 7 8; do
  python3 _gen_saturation_seeds.py _seed_sat$round.json >> "$LOG" 2>&1
  n=$(python3 -c "import json;print(len(json.load(open('_seed_sat$round.json'))))")
  echo "== round $round: $n seeds (prev uncovered $prev)" >> "$LOG"
  if [ "$n" = "0" ]; then echo "SATURATED" >> "$LOG"; break; fi
  if [ "$n" -ge "$((prev * 95 / 100))" ]; then echo "STALLED at $n" >> "$LOG"; break; fi
  prev=$n
  JRUBY_OPTS="-J-Xmx1500m" MAX_RUNS=$((n + 50)) TIME_BUDGET=1200 SEEDS_ONLY=1 \
    EXTRA_SEEDS_JSON="$HERE/_seed_sat$round.json" LABEL_SUFFIX="_sat$round" \
    /home/dev/project/scripts/diaspora-concolic "$HERE/run_dse.rb" >> "$LOG" 2>&1
done
echo "LOOP_EXIT" >> "$LOG"
