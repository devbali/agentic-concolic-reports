#!/bin/bash
# C14 — dump list for the next coverage pass: the C13 R2 snapshot (the corpus
# the M1 verdict was measured on) PLUS this round's constructed runs.
#   usage: bash _c14_snapshot.sh <stamp> [glob ...]
set -e
B=/home/dev/project/reports/diaspora/results3/notifications_index
STAMP="${1:?usage: _c14_snapshot.sh <stamp> [glob ...]}"; shift
BASE="${C14_BASE:-$B/_snapshot_c13_R2.txt}"
OUT="$B/_snapshot_c14_${STAMP}.txt"
{ cat "$BASE"
  for g in "$@"; do find "$B" -maxdepth 1 -name "$g" -printf '%p\n'; done
} | sed 's#/\./#/#' | sort -u > "$OUT"
echo "$OUT  $(wc -l < "$OUT") runs  (base $(basename "$BASE") $(wc -l < "$BASE"), added $(( $(wc -l < "$OUT") - $(wc -l < "$BASE") )))"
