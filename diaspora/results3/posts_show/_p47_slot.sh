#!/usr/bin/env bash
# P47-PRIVATE JRuby slot. Same mechanism as reports/diaspora/tools/slot, but a
# SEPARATE LOCK NAMESPACE (/tmp/p47-concolic-slot-N.lock).
#
# WHY THIS EXISTS — a real incident, 2026-09-25 04:20-04:39.
#
# `tools/slot` searches slots 1..N, where N is `$CONCOLIC_SLOTS`. It has no
# notion of reservation: N is a SEARCH RANGE, not an offset. The P47 drive set
# CONCOLIC_SLOTS=6 expecting to "land on 4-6" because the untouchable
# conversations_index gate (which runs with CONCOLIC_SLOTS=3) held 1-3. That
# assumption was wrong. At 04:20:24 the gate happened to have slot 1 free
# between probe batches, and a P47 leg took it -- and `tools/slot` holds the
# lock for the COMMAND'S WHOLE LIFE, so with TIME_BUDGET=36000 that leg would
# have held one third of the protected job's capacity for TEN HOURS.
#
# Measured symptom before the cause was found: the gate's probe checkpoint went
# quiet for 8 minutes. (Its CPU was still 72-80 %, which is why the checkpoint
# alone is a bad starvation test -- it writes once per 4-probe batch.)
#
# Two jobs sharing one lock namespace only works if they AGREE on the pool
# size. They did not: the gate thought the pool was 3, P47 thought it was 6.
# The fix is not a bigger number, it is a separate namespace -- then each job
# caps ITSELF and the box's total is the sum, which the launcher sizes.
#
# usage: _p47_slot.sh <command> [args...]      (workers from $P47_SLOTS, default 3)
set -u

N="${P47_SLOTS:-3}"
case "$N" in
  ''|*[!0-9]*) echo "_p47_slot: P47_SLOTS must be a positive integer, got '$N'" >&2; exit 2 ;;
esac
[ "$N" -ge 1 ] || { echo "_p47_slot: P47_SLOTS must be >= 1" >&2; exit 2; }
[ $# -ge 1 ] || { echo "_p47_slot: no command given" >&2; exit 2; }

while true; do
  for i in $(seq 1 "$N"); do
    exec 9>"/tmp/p47-concolic-slot-$i.lock" || continue
    if flock -n 9; then
      exec "$@"        # fd 9 stays open across exec: the lock is held for the
    fi                 # command's whole life and released when it exits
  done
  sleep 1
done
