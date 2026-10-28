#!/bin/bash
# Stage 2 queue: the NO_PINS CONTROL for the consistency check, then the
# phase-3 demand round. Strictly sequential; waits by PID.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
WAIT_PID="${1:-0}"
[ "$WAIT_PID" != "0" ] && while kill -0 "$WAIT_PID" 2>/dev/null; do sleep 20; done

# ---- CONTROL: the SAME containment check with the pin tier REMOVED ---------
# Pass A ran at 18:14 with NO pins; the pin tier was installed later (§13,
# §47.3). Any witness the pinned check calls UNSAT is therefore explained by
# the pins unless it is ALSO unsat without them. `NO_PINS=1` is the tier's own
# documented off-switch, so this is a one-variable differential and not a
# rebuild of the check.
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=5G --unit=pxconsAnp.scope \
  env DUMP_LIST="$B/_snapshot_pruned_20260910.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= NO_PINS=1 SUMMARY="$B/_cov_pruned_baseline.json" \
      OUT="$B/_consistency_passA_nopins.json" \
  timeout 5400 python3 -u "$B/_consistency_check.py" > "$B/_consistency_passA_nopins.log" 2>&1
echo "EXIT=$? $(date -Is)" >> "$B/_consistency_passA_nopins.log"

# ---- the phase-3 demand round ---------------------------------------------
REACH_SPLIT=1 EMIT_MAX_PER_SET=2 CHUNK=250 DRIVE_PAR=2 \
  ROOT_LIST="$B/_rootbase_p5.txt" \
  bash "$B/_p3_round.sh" DR3P0910 "$B/_snapshot_pruned_p5.txt" > "$B/_p3round_DR3P0910.out" 2>&1
echo "QUEUE DONE $(date -Is)" >> "$B/_p3round_DR3P0910.out"
