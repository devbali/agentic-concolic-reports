#!/bin/bash
# C28 — dump list for the next coverage pass: the C27 corpus of record
# (_snapshot_c27_R3.txt, 135 208 runs — C26R1's 135 153 plus the 55 verified
# falsifier runs of §39.5/§39.9) PLUS this round's constructed runs.
#   usage: bash _c28_snapshot.sh <stamp> [glob ...]
set -e
B=/home/dev/project/reports/diaspora/results3/notifications_index
STAMP="${1:?usage: _c28_snapshot.sh <stamp> [glob ...]}"; shift
BASE="${C28_BASE:-$B/_snapshot_c27_R3.txt}"
OUT="$B/_snapshot_c28_${STAMP}.txt"
{ cat "$BASE"
  for g in "$@"; do find "$B" -maxdepth 1 -name "$g" -printf '%p\n'; done
} | sed 's#/\./#/#' | sort -u > "$OUT"
echo "$OUT  $(wc -l < "$OUT") runs  (base $(basename "$BASE") $(wc -l < "$BASE"), added $(( $(wc -l < "$OUT") - $(wc -l < "$BASE") )))"
