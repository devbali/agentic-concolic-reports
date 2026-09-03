#!/bin/bash
B=/home/dev/project/reports/diaspora/results3/comments_index
S=/tmp/claude-1000/-home-dev-project/e0395c49-56d0-42c0-af70-a3707c6552fa/scratchpad
RUN="flock /tmp/concolic-slot.lock systemd-run --user --pipe --wait -p MemoryMax=3000M -p MemorySwapMax=0 --working-directory=/home/dev/project"
RPT="systemd-run --user --pipe --wait -p MemoryMax=5500M -p MemorySwapMax=0 --working-directory=/home/dev/project"
for v in anon_json auth_json anon_mobile auth_mobile; do
  [ -f $B/_targeted_$v.json ] || continue
  $RUN bash -c "unset JAVA_TOOL_OPTIONS; VARIANT=$v EXTRA_SEEDS_JSON=$B/_targeted_$v.json MAX_RUNS=900 TIME_BUDGET=240 LABEL_SUFFIX=_t1 /home/dev/project/scripts/diaspora-concolic $B/run_dse.rb" > $S/t1_$v.log 2>&1
  echo "== t1 $v: $(grep -E 'distinct paths|run errors' $S/t1_$v.log | tr -s ' ' | tr '\n' ' ')"
done
$RPT bash -c 'unset JAVA_TOOL_OPTIONS; SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=64 PYTHONPATH=src python3 reports/diaspora/results3/comments_index/coverage_report.py' 2>&1 | grep -E "^COMPLETE=|RuntimeError"
echo TARGETEDDONE
