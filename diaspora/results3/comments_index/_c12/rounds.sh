#!/bin/bash
set -u
P=/home/dev/project; B=$P/reports/diaspora/results3/comments_index
cd $P; unset JAVA_TOOL_OPTIONS; export CONCOLIC_SLOTS=2
TAG=${TAG:-base}; MAXR=${MAXR:-11000}; TB=${TB:-1500}; SEEDSET=${SEEDSET:-}
run(){ v=$1; extra=""
  if [ -n "$SEEDSET" ]; then f=$B/_c12/_seed_${SEEDSET}_$v.json; [ -f "$f" ] || { echo "  [$TAG/$v] no seed"; return; }; extra="EXTRA_SEEDS_JSON=$f"; fi
  env DUMP_OUT=$B MAX_RUNS=$MAXR TIME_BUDGET=$TB VARIANT=$v $extra \
    $P/reports/diaspora/tools/slot $P/scripts/diaspora-concolic $B/run_dse.rb > $B/_c12/round_${TAG}_$v.log 2>&1
  echo "  [$TAG/$v] exit=$? $(grep -E 'runs executed|distinct paths|run errors' $B/_c12/round_${TAG}_$v.log | tr '\n' ' ')"
}
echo "ROUND $TAG START $(date -Is)"
run anon_json & run auth_json & wait
run anon_mobile & run auth_mobile & wait
echo "  dumps: $(find $B -maxdepth 1 -name 'dump_*.json' | wc -l)"
python3 $B/dedupe_dumps.py $B 2>&1 | tail -1
echo "  after dedupe: $(find $B -maxdepth 1 -name 'dump_*.json' | wc -l)"
echo "ROUND $TAG ENDED $(date -Is)"
