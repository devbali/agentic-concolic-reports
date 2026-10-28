#!/bin/bash
# C16 — dump list for the next coverage pass: the C15 R2 base corpus
# (_snapshot_c14_R2.txt, 129 521 runs — the corpus the §16e verdict of
# 84 gap-sets was measured on) PLUS this round's constructed runs.
#   usage: bash _c16_snapshot.sh <stamp> [glob ...]
set -e
B=/home/dev/project/reports/diaspora/results3/notifications_index
STAMP="${1:?usage: _c16_snapshot.sh <stamp> [glob ...]}"; shift
BASE="${C16_BASE:-$B/_snapshot_c14_R2.txt}"
OUT="$B/_snapshot_c16_${STAMP}.txt"
{ cat "$BASE"
  for g in "$@"; do find "$B" -maxdepth 1 -name "$g" -printf '%p\n'; done
} | sed 's#/\./#/#' | sort -u > "$OUT"
echo "$OUT  $(wc -l < "$OUT") runs  (base $(basename "$BASE") $(wc -l < "$BASE"), added $(( $(wc -l < "$OUT") - $(wc -l < "$BASE") )))"
