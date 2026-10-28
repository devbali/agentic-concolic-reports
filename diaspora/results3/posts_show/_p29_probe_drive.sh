#!/bin/bash
# P29 ACTIVE FALSIFICATION PROBE (§79) — drive the constructed render-split
# attempts. Same machinery as the P15 rounds (_chunk_drive.sh), caged, one
# JRuby at a time (CONCOLIC_SLOTS=1, DRIVE_PAR=1), resumable by chunk marker.
# Verdict line: P29-PROBE-DRIVE-DONE / -INCOMPLETE.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
LOG="$B/_p29_probe_drive.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$LOG"; }
TAG=P29P
export CONCOLIC_SLOTS=1 DRIVE_PAR=1
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "=== P29 probe drive start (corpus $before) ==="
for V in auth_html anon_html auth_json anon_json; do
  F="$B/_p29_seeds_${V}.json"
  N=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$F")
  [ "$N" = 0 ] && { say "$V: 0 seeds"; continue; }
  TAG2="${TAG}${V:0:2}${V:5:2}"
  say "$V: $N seeds -> chunk drive $TAG2"
  cage_drive "p29drv${V:0:2}${V:5:2}" 4G \
    bash "$B/_chunk_drive.sh" "$F" "$TAG2" 200 "$V" >> "$LOG" 2>&1
  caged_verdict "p29drv${V:0:2}${V:5:2}" "$B/_chunk_drive_${TAG2}.log" \
    "=== CHUNK DRIVE $TAG2 END ===" | tee -a "$LOG"
done
after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "corpus after: $after (+$((after-before)))"
n=$(find "$B" -maxdepth 1 -name "dump_*${TAG}*.json" | wc -l)
if [ "$n" -gt 0 ]; then say "P29-PROBE-DRIVE-DONE $n probe dumps (+$((after-before)))";
else say "P29-PROBE-DRIVE-INCOMPLETE 0 dumps"; fi
