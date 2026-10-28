#!/bin/bash
# Round DR3P0910 — the phase-3 demand round, queued behind the measurement
# queue so only one >1 GB job of this drive's own ever runs.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
WAIT_PID="${1:-0}"
[ "$WAIT_PID" != "0" ] && while kill -0 "$WAIT_PID" 2>/dev/null; do sleep 20; done
EMIT_MAX_PER_SET=4 CHUNK=250 DRIVE_PAR=2 \
  bash "$B/_p3_round.sh" DR3P0910 "$B/_snapshot_pruned_p5.txt" > "$B/_p3round_DR3P0910.out" 2>&1
echo "QUEUE DONE $(date -Is)" >> "$B/_p3round_DR3P0910.out"
