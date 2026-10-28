#!/bin/bash
# P44 DRIVE — one unit, all four variants, configurable width. Resumes on the
# per-chunk markers `_chunk_drive.sh` writes, so a kill costs at most a chunk.
#   usage: bash _p44_drive.sh <SEEDSET> <TAG> [CHUNK]
#   env:   DRIVE_PAR (workers) CONCOLIC_SLOTS (machine-wide JRuby locks)
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd /home/dev/project || exit 1
SET="${1:?seedset}"; TAG="${2:?tag}"; CHUNK="${3:-100}"
export DRIVE_PAR="${DRIVE_PAR:-8}" CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-8}"
L="$B/_p44_drive_${TAG}.log"
say(){ echo "[$(date -Is)] $*" >> "$L"; }
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "=== P44 DRIVE $TAG set=$SET chunk=$CHUNK par=$DRIVE_PAR slots=$CONCOLIC_SLOTS corpus=$before ==="
for V in auth_html anon_html auth_json anon_json; do
  F="$B/_p15_seeds${SET}_${V}.json"
  [ -f "$F" ] || { say "$V: NO SEED FILE $F"; continue; }
  N=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$F")
  [ "$N" = 0 ] && { say "$V: 0 seeds (stated, not silent)"; continue; }
  say "$V: $N seeds -> _chunk_drive.sh tag ${TAG}${V:0:2}${V:5:2}"
  bash "$B/_chunk_drive.sh" "$F" "${TAG}${V:0:2}${V:5:2}" "$CHUNK" "$V" >> "$L" 2>&1
  say "$V: leg end ($(grep -c "DONE consumed" "$B/_chunk_drive_${TAG}${V:0:2}${V:5:2}.log" 2>/dev/null) chunks done)"
done
after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "P44-DRIVE-DONE $TAG corpus $before -> $after (+$((after-before)))"
