#!/bin/bash
# C28 DRIVE — one constructed batch, all seven request variants, through
# `_chunk_drive.sh` (chunked so a native JVM abort costs one chunk, not the
# batch).  usage: bash _c28_drive.sh <TAG> [PREF]
# Verdict line: `C28-DRIVE-DONE <tag> +<n>` (absence = killed, not done).
#
# DRIVE_PAR defaults to 2, NOT to CONCOLIC_SLOTS: the posts_show confinement
# gate `posts-p26-gate-v2-20260913` owns the box's other cores and is the long
# pole. It is never stopped and never waited on.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd /home/dev/project || exit 1
TAG="${1:?usage: _c28_drive.sh <TAG> [PREF]}"; PREF="${2:-_c28_r1_seeds_}"
export CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-2}"
export DRIVE_PAR="${DRIVE_PAR:-2}"
export JRUBY_CAP="${JRUBY_CAP:-2G}"
LOG="$B/_c28_drive_${TAG}.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$LOG"; }
. "$B/_wait_mem.sh"
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "=== C28 DRIVE $TAG pref=$PREF slots=$CONCOLIC_SLOTS par=$DRIVE_PAR corpus before: $before ==="
for V in html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain; do
  F="$B/${PREF}${V}.json"
  [ -f "$F" ] || { say "$V: no seed file"; continue; }
  N=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$F")
  [ "$N" = 0 ] && { say "$V: 0 seeds — nothing to drive (stated, not silent)"; continue; }
  while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "$V WAIT free<4G"; sleep 30; done
  say "$V: $N seeds -> _chunk_drive.sh"
  bash "$B/_chunk_drive.sh" "$F" "$TAG" "${CHUNK:-100}" "$V" >> "$LOG" 2>&1
  if grep -q "=== CHUNK DRIVE $TAG END ===" "$B/_chunk_drive_${TAG}.log"; then
    say "  leg $V: END line present"
  else
    say "  leg $V: *** NO END LINE — TREATED AS KILLED, NOT DONE ***"
  fi
done
after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "C28-DRIVE-DONE $TAG +$((after-before)) dumps (corpus $after)"
