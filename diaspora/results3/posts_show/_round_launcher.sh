#!/bin/bash
# Fresh launcher (the previous queue script was edited while bash was reading
# it, so it was stopped and replaced rather than trusted). Waits for the
# NO_PINS control's python to exit, then runs the phase-3 demand round.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
CTRL_PID="${1:-0}"
[ "$CTRL_PID" != "0" ] && while kill -0 "$CTRL_PID" 2>/dev/null; do sleep 15; done
echo "EXIT=(control python exited) $(date -Is)" >> "$B/_consistency_passA_nopins.log"
REACH_SPLIT=1 EMIT_MAX_PER_SET=2 CHUNK=250 DRIVE_PAR=2 ROOT_LIST="$B/_rootbase_p5.txt" \
  bash "$B/_p3_round.sh" DR3P0910 "$B/_snapshot_pruned_p5.txt" > "$B/_p3round_DR3P0910.out" 2>&1
echo "ROUND LAUNCHER DONE $(date -Is)" >> "$B/_p3round_DR3P0910.out"
