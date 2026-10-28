#!/bin/bash
# 2026-09-12 11:55: C12-2 (engine section) was OOM-killed at its 5G scope cap at 11:49
# (cage total was 7.1G). Cap raised to 9G in _c12_rerun_after_restart.sh. To keep the
# 19G cage safe with two drive campaigns running, start it only after posts_show's
# engine section service ends. Gate probes resume from ACHK_CHECKPOINT.
B=/home/dev/project/reports/diaspora/results3/notifications_index
while systemctl --user is-active posts-p14-s23-20260912.service >/dev/null 2>&1; do sleep 60; done
echo "[$(date -Is)] posts engine section ended; launching C12 from stage 2 (cap 9G)" >> "$B/_c12.log"
exec /bin/bash "$B/_c12_rerun_after_restart.sh" 2
