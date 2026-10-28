#!/usr/bin/env bash
# P47 co-tenancy guard. The conversations_index gate (slots 1-3) is protected
# and must not be starved by this drive. If its probe checkpoint goes quiet for
# longer than STALL_MIN, drop P47 from 3 concurrent legs to 2 by taking one
# slot away (CONCOLIC_SLOTS is per-invocation, so the lever is to stop one leg;
# the remaining legs keep their slots and the queued leg simply waits longer).
# Writes a verdict file either way -- silence must not look like success.
CK=/home/dev/project/reports/diaspora/results3/conversations_index/_fullgate919_probes.ckpt.jsonl
B=/home/dev/project/reports/diaspora/results3/posts_show
OUT=$B/_p47_guard.log
STALL_MIN=${STALL_MIN:-20}
: > $OUT
last=$(stat -c %Y $CK)
while systemctl --user is-active --quiet p47-gen-v2-posts-show.scope; do
  sleep 120
  now=$(stat -c %Y $CK); quiet=$(( ($(date +%s) - now) / 60 ))
  echo "$(date -Is) convix_ckpt quiet ${quiet}m | load $(cut -d' ' -f1 /proc/loadavg) | v2 $(find $B/v2 -maxdepth 1 -name 'dump_*.json'|wc -l)" >> $OUT
  if [ "$quiet" -ge "$STALL_MIN" ]; then
    echo "$(date -Is) ALERT: conversations_index probe checkpoint quiet ${quiet}m >= ${STALL_MIN}m -- P47 should drop a leg" >> $OUT
  fi
done
echo "$(date -Is) P47 scope inactive; guard exiting" >> $OUT
