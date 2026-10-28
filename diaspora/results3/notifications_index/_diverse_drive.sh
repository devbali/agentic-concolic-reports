#!/bin/bash
# DIVERSE DRIVE (2026-09-09): bulk diverse seeds (v2, every length input
# assigned) across ALL SEVEN variants, SEEDS_ONLY, one JRuby per slot.
# usage: _diverse_drive.sh <seeds.json> <tag>     (tag must be unique per invocation)
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
SEEDS="$1"; TAG="$2"; LOG="$B/_diverse_drive_${TAG}.log"
export CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-3}"
say(){ echo "[$(date -Is)] $*" >> "$LOG"; }
say "=== DIVERSE DRIVE $TAG seeds=$SEEDS ($(python3 -c "import json;print(len(json.load(open('$SEEDS'))))") seeds) slots=$CONCOLIC_SLOTS ==="
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l); say "corpus before: $before dumps"
for V in html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain; do
  ( /home/dev/project/reports/diaspora/tools/slot env VARIANTS="$V" SEEDS_ONLY=1 \
      EXTRA_SEEDS_JSON="$SEEDS" LABEL_SUFFIX="_${TAG}${V:0:3}$( [ "${V##*_}" = typed ] && echo t || echo p)" \
      MAX_RUNS=100000 TIME_BUDGET=7200 \
      /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" > "$B/_diverse_${TAG}_${V}.log" 2>&1
    echo "[$(date -Is)] $V done rc=$? paths=$(grep -c 'new path' "$B/_diverse_${TAG}_${V}.log")" >> "$LOG" ) &
  sleep 2
done
wait
after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "corpus after: $after dumps (+$((after-before)))"
say "=== DIVERSE DRIVE $TAG END ==="
