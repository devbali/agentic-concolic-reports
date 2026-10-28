#!/bin/bash
# C30 — dump list for the next coverage pass: the C27 corpus of record
# (_snapshot_c27_R8.txt, 136 028 runs) PLUS this round's constructed runs.
#   usage: bash _c29_snapshot.sh <stamp> [glob ...]
set -e
B=/home/dev/project/reports/diaspora/results3/notifications_index
STAMP="${1:?usage: _c29_snapshot.sh <stamp> [glob ...]}"; shift
BASE="${C30_BASE:-$B/_snapshot_c27_R8.txt}"
OUT="$B/_snapshot_c30_${STAMP}.txt"
{ cat "$BASE"
  for g in "$@"; do find "$B" -maxdepth 1 -name "$g" -printf '%p\n'; done
} | sed 's#/\./#/#' | sort -u > "$OUT"
echo "$OUT  $(wc -l < "$OUT") runs  (base $(basename "$BASE") $(wc -l < "$BASE"), added $(( $(wc -l < "$OUT") - $(wc -l < "$BASE") )))"
