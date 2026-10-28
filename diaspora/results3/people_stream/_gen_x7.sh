#!/bin/bash
# people_stream corpus regeneration on the X7-repaired mock layer (2026-09-11).
# The pre-X7 corpus (1109 dumps) is KEPT under _corpus_pre_x7_20260910/ — §16b:
# removing runs can CREATE a foreclosure and RETRACT demand, so nothing is
# deleted, only moved out of the glob the checker reads.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
RUNID="$(date +%m%d%H%M)"
B=/home/dev/project/reports/diaspora/results3/people_stream
LOG="$B/_gen_x7.log"; ST="$B/_gen_x7_status"
say() { echo "[$(date -Is)] $*" >> "$LOG"; }
: > "$LOG"
say "=== X7 base generation start (corpus $(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l) dumps) ==="
for ROUND in 1; do
  before=$(find "$B" -maxdepth 1 -name "dump_*.json" | wc -l)
  echo "$(date -Is) | people_stream X7 base round $ROUND (corpus $before)" > "$ST"
  say "round $ROUND start (corpus $before)"
  # caged: 2G, oom_score_adj 1000 (coordinator directive 2026-09-11)
  CONCOLIC_SLOTS=3 "$B/_caged" 1500M /home/dev/project/reports/diaspora/tools/slot env MAX_RUNS=9000 TIME_BUDGET=2700 \
    LABEL_SUFFIX="_X7${RUNID}r${ROUND}" \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
  rc=$?
  after=$(find "$B" -maxdepth 1 -name "dump_*.json" | wc -l)
  say "round $ROUND done rc=$rc : $before -> $after (+$((after-before)))"
  if [ "$after" -le "$before" ]; then say "no new dumps in round $ROUND — stopping"; break; fi
done
say "=== X7 base generation done: $(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l) dumps ==="
echo "$(date -Is) | people_stream X7 base generation DONE: $(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l) dumps" > "$ST"
