#!/bin/bash
set -u
P=/home/dev/project; B=$P/reports/diaspora/results3/comments_index
cd $P; unset JAVA_TOOL_OPTIONS
export CONCOLIC_SLOTS=2
echo "ROUNDS START $(date -Is)"
run(){ v=$1; shift
  DUMP_OUT=$B MAX_RUNS=${MAXR:-11000} TIME_BUDGET=${TB:-1500} VARIANT=$v "$@" \
    $P/reports/diaspora/tools/slot $P/scripts/diaspora-concolic $B/run_dse.rb > $B/_c11/round_${TAG}_$v.log 2>&1
  echo "  [$TAG/$v] exit=$? $(grep -E 'runs executed|distinct paths|run errors' $B/_c11/round_${TAG}_$v.log | tr '\n' ' ')"
}
TAG=base
run anon_json  & run auth_json  & wait
run anon_mobile & run auth_mobile & wait
echo "  dumps after base: $(ls $B/dump_*.json | wc -l)"
python3 $B/dedupe_dumps.py $B 2>&1 | tail -2
echo "  dumps after dedupe: $(ls $B/dump_*.json | wc -l)"
echo "ROUNDS ENDED $(date -Is)"
