#!/bin/bash
# C23 chain v2 (2026-09-14 06:20) — the remaining measurement passes, strictly
# in sequence, via _c23_pass2.sh (see its header for why the pgrep hold was
# dropped and why that is safe). OFF and C1X are already done.
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
say(){ echo "[$(date -Is)] CHAIN2 $*" | tee -a "$B/_c23.log"; }
while pgrep -a python3 2>/dev/null | grep -v shell-snapshots \
      | grep -q "notifications_index/_c23_coverage_report[.]py"; do
  say "WAIT: a _c23 pass is still running"; sleep 60
done
run(){ local tag="$1"; shift; say "START $tag ($*)"; env "$@" bash "$B/_c23_pass2.sh" "$tag"; say "END $tag rc=$?"; }
run C1     CONF_KEEP_NOTES=1
run ON     CONF_KEEP_NOTES=0
run C1C2   CONF_KEEP_NOTES=1 CONF_SPAN_UNION=1
run C1C2X  CONF_KEEP_NOTES=1 CONF_SPAN_UNION=1 CONF_KEYING=exact
say "CHAIN2 DONE"
