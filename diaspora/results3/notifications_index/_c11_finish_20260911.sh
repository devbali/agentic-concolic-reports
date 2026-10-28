#!/bin/bash
# POST-REBOOT FINISH CHAIN (2026-09-11 21:30, 64 GB box, cage 24G): the full
# engine pass, then the audits. NO EXTRACTION (closure-only rule). Replaces
# _c11_queue.sh, whose free>=6 / empty-box gate was for the 16 GB box.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_c11_finish.log"
echo "[$(date -Is)] finish chain START free=$(free -g|awk '/^Mem/{print $7}')G cage=$(systemctl --user show concolic-cov.slice -p MemoryMax --value)" >> "$LOG"
"$B/_c11_pass_full.sh" "$B/_snapshot_pruned_20260911_143539.txt" full1 8G >> "$LOG" 2>&1
echo "[$(date -Is)] finish: pass stage returned $?" >> "$LOG"
"$B/_c11_audits_run.sh" >> "$LOG" 2>&1
echo "[$(date -Is)] finish: audits returned $?" >> "$LOG"
echo "[$(date -Is)] finish chain DONE (no extraction stage)" >> "$LOG"
