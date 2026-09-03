#!/bin/bash
set -u
P=/home/dev/project; B=$P/reports/diaspora/results3/comments_index
cd $P; unset JAVA_TOOL_OPTIONS; export CONCOLIC_SLOTS=2
TAG=$1; MAXR=${MAXR:-6000}; TB=${TB:-1200}
run(){ v=$1
  f=$B/_demand_$v.json
  [ -f "$f" ] || { echo "  [$TAG/$v] no demand file"; return; }
  DUMP_OUT=$B MAX_RUNS=$MAXR TIME_BUDGET=$TB VARIANT=$v EXTRA_SEEDS_JSON=$f \
    $P/reports/diaspora/tools/slot $P/scripts/diaspora-concolic $B/run_dse.rb > $B/_c11/round_${TAG}_$v.log 2>&1
  echo "  [$TAG/$v] exit=$? $(grep -E 'runs executed|distinct paths|run errors' $B/_c11/round_${TAG}_$v.log | tr '\n' ' ')"
}
echo "DEMAND $TAG START $(date -Is)"
run anon_json & run auth_json & wait
run anon_mobile & run auth_mobile & wait
echo "  dumps: $(find $B -maxdepth 1 -name 'dump_*.json' | wc -l)"
python3 $B/dedupe_dumps.py $B 2>&1 | tail -1
echo "  after dedupe: $(find $B -maxdepth 1 -name 'dump_*.json' | wc -l)"
echo "DEMAND $TAG ENDED $(date -Is)"
