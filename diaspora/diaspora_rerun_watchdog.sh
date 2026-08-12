#!/usr/bin/env bash
# diaspora_rerun_watchdog.sh — track progress of the find-mock re-run across batches.
# Exits 0 when every batch has a freshly-minted run_concolic.rb dump set (mtime today).
set -u
RESULTS="/home/dev/project/reports/diaspora/results"
BATCHES="comments contacts_aspects_blocks conversations likes notifications_tags oidc_federation_nodeinfo people photos posts search_links_reports_profiles services_admin streams users_sessions"
CHECK=240
today_marker(){ find "$RESULTS" -name 'dump_*.json' -newermt '2026-08-08 07:40' 2>/dev/null | wc -l; }
snapshot(){
  for b in $BATCHES; do
    # count freshly-updated dumps in this batch (mtime after fix went in)
    n=$(find "$RESULTS/$b" -name 'dump_*.json' -newermt '2026-08-08 07:40' 2>/dev/null | wc -l)
    echo "$b:$n"
  done
}
prev=$(snapshot); LOOP=0
while true; do
  sleep "$CHECK"; LOOP=$((LOOP+1)); cur=$(snapshot); STALL=""
  for b in $BATCHES; do
    c=$(echo "$cur" | grep -E "^$b:" | cut -d: -f2)
    p=$(echo "$prev" | grep -E "^$b:" | cut -d: -f2)
    [ "$c" = "$p" ] && STALL="$STALL $b"
  done
  echo "[watchdog $(date -u +%FT%TZ) loop $LOOP total_new_dumps=$(today_marker)] STALLED:$STALL"
  prev="$cur"
done
