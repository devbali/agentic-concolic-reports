#!/bin/bash
# posts_show base corpus generation (2026-09-09), on the RE-SYNCED boundary
# (Rule T: verbatim copy of reports/diaspora/concolic_targets.rb + a declaration
# filter for this batch's five documented descents; load-tested EXIT=0, no
# descended target fires). Uses tools/slot so it shares the machine politely
# with the notifications demand loop.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
# LABEL must be unique per INVOCATION, not per round: the round counter
# restarts at 1 every run, so "_b1" collided with the previous run's _b1
# dumps and OVERWROTE them (observed: +0 dumps in 10 minutes while the
# generator ran happily).
RUNID="$(date +%m%d%H%M)"
B=/home/dev/project/reports/diaspora/results3/posts_show
LOG="$B/_gen_base.log"; ST="$B/_gen_status"
say() { echo "[$(date -Is)] $*" >> "$LOG"; }
: > "$LOG"
say "=== posts_show base generation start (corpus $(find "$B" -maxdepth 1 -name "dump_*.json" | wc -l) dumps) ==="
for ROUND in 1 2 3 4; do
  before=$(find "$B" -maxdepth 1 -name "dump_*.json" | wc -l)
  echo "$(date -Is) | posts_show base round $ROUND (corpus $before)" > "$ST"
  say "round $ROUND start (corpus $before)"
  /home/dev/project/reports/diaspora/tools/slot env MAX_RUNS=4000 TIME_BUDGET=900 \
    LABEL_SUFFIX="_${RUNID}r${ROUND}" \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
  after=$(find "$B" -maxdepth 1 -name "dump_*.json" | wc -l)
  say "round $ROUND done rc=$? : $before -> $after (+$((after-before)))"
  if [ "$after" -le "$before" ]; then say "no new dumps in round $ROUND — stopping generation"; break; fi
done
say "=== base generation done: $(find "$B" -maxdepth 1 -name "dump_*.json" | wc -l) dumps ==="
echo "$(date -Is) | posts_show base generation DONE: $(find "$B" -maxdepth 1 -name "dump_*.json" | wc -l) dumps" > "$ST"
