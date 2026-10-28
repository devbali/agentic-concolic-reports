#!/bin/bash
# QUEUED HEAVY STAGES (coordinator 2026-09-11 19:46: the cage is 4G/high 3G and
# an editor language server outside it holds ~6 GB, so nothing over ~3 G can run).
# This waits for the box to come back — `free -g` >= 6 AND no other heavy job
# anywhere (_box_clear.sh empty: passes, enumerations, censuses, the gate, JRuby,
# blockaid) — and then runs, STRICTLY ONE AT A TIME:
#     1. the FULL engine pass (coverage + completion, cap 5G)
#     2. _c7_audits.sh
#     (the extraction stage was REMOVED — policies are extracted at closure only)
# Each stage is judged by its own printed verdict line; a stage that exits
# without one was killed, not done.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_c11_queue.log"
echo "[$(date -Is)] queue armed: waiting for free>=6G and an empty box" >> "$LOG"
i=0
while :; do
  fg=$(free -g | awk '/^Mem/{print $7}')
  busy=$("$B/_box_clear.sh" | wc -l)
  # The CAGE must also allow the job: with MemoryMax=4G on the slice a 5 G pass
  # is killed at 4 G whatever `free` says, so the gate is three-part.
  mx=$(systemctl --user show concolic-cov.slice -p MemoryMax --value)
  [ "$mx" = "infinity" ] && mx=99999999999
  if [ "${fg:-0}" -ge 6 ] && [ "$busy" -eq 0 ] && [ "${mx:-0}" -ge 5905580032 ]; then
    echo "[$(date -Is)] queue FIRING: free=${fg}G busy=$busy cage_max=$((mx/1073741824))G" >> "$LOG"; break
  fi
  [ $((i % 20)) -eq 0 ] && echo "[$(date -Is)] queue WAIT: free=${fg}G (need 6) busy=$busy cage_max=$((mx/1048576))MB (need >=5632MB)" >> "$LOG"
  i=$((i+1)); sleep 30
done
"$B/_c11_pass_full.sh" "$B/_snapshot_pruned_20260911_143539.txt" full1 5G >> "$LOG" 2>&1
echo "[$(date -Is)] queue: pass stage returned $?" >> "$LOG"
[ -f "$B/_c11_audits.ok" ] || "$B/_c7_audits.sh" >> "$LOG" 2>&1
echo "[$(date -Is)] queue: audits returned $?" >> "$LOG"
# EXTRACTION REMOVED 2026-09-11 21:16 (owner correction relayed by the
# coordinator): a policy is extracted at CLOSURE only, and notifications_index
# is not complete. Nothing in this chain writes queries_from_runs/*.sql or a
# POLICY_HEADER.
echo "[$(date -Is)] queue DONE" >> "$LOG"
