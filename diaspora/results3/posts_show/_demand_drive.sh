#!/bin/bash
# DEMAND ROUND driver for posts_show. `_demand_root.py` writes one rooted-seed
# file per SCENARIO (`_demandR_<variant>.json`); this hands each to
# `_chunk_drive.sh` for that variant only, so a seed built from an auth_json
# base is replayed in auth_json and nowhere else. Chunked, so a native abort
# costs one chunk and names itself.
# usage: _demand_drive.sh <TAG> [CHUNK]
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
TAG="$1"; CHUNK="${2:-250}"
LOG="$B/_demand_drive_${TAG}.log"; : > "$LOG"
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
echo "[$(date -Is)] === DEMAND DRIVE $TAG  corpus before: $before ===" >> "$LOG"
for V in auth_html anon_html auth_json anon_json; do
  F="$B/_demandR_${V}.json"
  [ -f "$F" ] || { echo "[$(date -Is)] $V: no seed file — skipped (NOT silently: _demand_root.py wrote none)" >> "$LOG"; continue; }
  N=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$F")
  echo "[$(date -Is)] $V: $N seeds -> _chunk_drive.sh" >> "$LOG"
  DRIVE_PAR="${DRIVE_PAR:-2}" bash "$B/_chunk_drive.sh" "$F" "${TAG}${V:0:2}${V:5:2}" "$CHUNK" "$V" >> "$LOG" 2>&1
done
after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
echo "[$(date -Is)] corpus after: $after (+$((after-before)))" >> "$LOG"
echo "[$(date -Is)] === DEMAND DRIVE $TAG END ===" >> "$LOG"
tail -5 "$LOG"
