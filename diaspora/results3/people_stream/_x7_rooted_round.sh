#!/bin/bash
# One ROOTED round: replay the seed roots in $1 and nothing else (SEEDS_ONLY,
# so a hit is attributable to a seed — see _COMPLETION_20260910.md §1).
#   usage: _x7_rooted_round.sh <roots.json> <label-suffix> [max_runs] [budget]
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/people_stream
ROOTS="$1"; SFX="$2"; MR="${3:-4000}"; TB="${4:-1800}"
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
echo "[$(date -Is)] rooted round $SFX: $(python3 -c "import json,sys;print(len(json.load(open('$ROOTS'))))") roots, corpus $before"
# caged: 2G per JRuby, OOMScoreAdjust=1000 (coordinator directive 2026-09-11)
CONCOLIC_SLOTS=3 "$B/_caged" 1500M /home/dev/project/reports/diaspora/tools/slot env MAX_RUNS="$MR" TIME_BUDGET="$TB" \
  LABEL_SUFFIX="$SFX" SEEDS_ONLY=1 EXTRA_SEEDS_JSON="$ROOTS" \
  /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" > "$B/_round${SFX}.log" 2>&1
rc=$?
after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
echo "[$(date -Is)] rooted round $SFX done rc=$rc : $before -> $after (+$((after-before)))"
tail -5 "$B/_round${SFX}.log"
