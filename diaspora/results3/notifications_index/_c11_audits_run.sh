#!/bin/bash
# Phase-3/C7 audits, caged (they are bounded scans; measured cap 2500M).
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
. "$B/_wait_mem.sh"; wait_mem 2500 "_c11_audits"
systemd-run --user --scope --slice=concolic-cov.slice -p MemoryMax=2500M -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c11_audits.time" "$B/_c7_audits.sh" > "$B/_c11_audits.out" 2>&1
rc=$?
[ "$rc" = "0" ] && touch "$B/_c11_audits.ok"
echo "[$(date -Is)] audits EXIT rc=$rc" | tee -a "$B/_c11_audits.out"
grep -E 'Maximum resident' "$B/_c11_audits.time"
