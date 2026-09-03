#!/bin/bash
set -u
P=/home/dev/project; B=$P/reports/diaspora/results3/comments_index
cd $P; unset JAVA_TOOL_OPTIONS
MODE=$1              # plain | exec
SUF=""; EXPORTS=""
[ "$MODE" = exec ] && { SUF="_exec"; EXPORTS="CI_EXECUTOR=1"; }
echo "CONC $MODE START $(date -Is)"
for m in anon auth mobile r3 r4 r5 r6; do
  rm -f $B/concrete_run.json
  env $EXPORTS $P/reports/diaspora/tools/slot $P/scripts/diaspora-concolic \
      $P/src/ruby_runtime/completion_checker/concrete_run_probe.rb $B/concrete_manifest_$m.rb \
      > $B/_c12/conc_${MODE}_$m.log 2>&1
  rc=$?
  if [ -f $B/concrete_run.json ]; then mv $B/concrete_run.json $B/concrete_run_${m}${SUF}.json; fi
  echo "  [$MODE/$m] exit=$rc stmts=$(python3 -c "
import json,sys
try:
  d=json.load(open('$B/concrete_run_${m}${SUF}.json'))
  print(sum(len(sc.get('statements') or []) for sc in d), 'in', len(d),'scenarios')
except Exception as e: print('ERR',e)
")"
done
echo "CONC $MODE ENDED $(date -Is)"
