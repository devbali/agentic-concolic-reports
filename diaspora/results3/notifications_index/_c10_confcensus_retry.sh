#!/bin/bash
# Retry the final confinement census when the cage has real headroom.
# The 12:44 attempt died before "loaded" with the cage at 5.2 G of 8 and
# only 4.5 G free — a budget collision, not a defect (no verdict line = killed).
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B"
for i in $(seq 1 240); do
  CUR=$(systemctl --user show concolic-cov.slice -p MemoryCurrent --value)
  FG=$(free -m | awk '/^Mem/{print $7}')
  HEAD=$(( (8589934592 - CUR) / 1048576 ))
  if [ -z "$(./_box_clear.sh)" ] && [ "$HEAD" -ge 5200 ] && [ "$FG" -ge 7000 ]; then
    echo "[$(date -Is)] headroom ok: cage_head=${HEAD}MB free=${FG}MB — running"
    ./_c10_confcensus.sh
    exit 0
  fi
  sleep 60
done
echo "[$(date -Is)] never got headroom in 2 h — NOT run"
