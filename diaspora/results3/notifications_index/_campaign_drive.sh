#!/bin/bash
# CAMPAIGN DRIVE (2026-09-10) — continuous diverse-v2 driving until stopped.
#
# Loops: mint a FRESH batch of diverse-v2 seeds (new RNG each round, so each
# round explores different points of the {0,1,2,4}^22 length space), then run
# `_diverse_drive.sh` over all seven variants with a UNIQUE timestamped tag.
# Diverse seeds need no fresh targets, so the loop never waits on a pass.
#
# STOP: `touch _campaign_stop` — the loop finishes the round in flight and
# exits. Never hard-kill a runner mid-write.
#
# usage: _campaign_drive.sh [seeds-per-round] [slots]
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B"
N="${1:-6000}"; export CONCOLIC_SLOTS="${2:-3}"
LOG="$B/_campaign_drive.log"
say(){ echo "[$(date -Is)] $*" >> "$LOG"; }
say "=== CAMPAIGN DRIVE start: ${N} seeds/round, ${CONCOLIC_SLOTS} slots ==="
r=0
while [ ! -e "$B/_campaign_stop" ]; do
  r=$((r+1))
  TAG="DV$(date +%m%d%H%M%S)"          # unique per invocation; matches DV[0-9]+
  SEEDS="$B/_seeds_${TAG}.json"
  python3 "$B/_diverse_seeds2.py" "$N" "$SEEDS" --stride 120 >> "$LOG" 2>&1
  if [ ! -s "$SEEDS" ]; then say "round $r: seed mint FAILED, retrying in 60s"; sleep 60; continue; fi
  before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
  free=$(df --output=avail -BG /home | tail -1 | tr -dc '0-9')
  if [ "$free" -lt 15 ]; then say "round $r: DISK ${free}GB < 15GB — STOPPING"; break; fi
  say "round $r ($TAG): corpus $before, disk ${free}GB — driving"
  "$B/_diverse_drive.sh" "$SEEDS" "$TAG" >> "$LOG" 2>&1
  after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
  say "round $r ($TAG) done: corpus $after (+$((after-before)))"
  rm -f "$SEEDS"
done
say "=== CAMPAIGN DRIVE end after $r rounds ==="
