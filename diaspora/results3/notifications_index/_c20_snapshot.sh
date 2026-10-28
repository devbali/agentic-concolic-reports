#!/bin/bash
# C20 — dump list for the next coverage pass: the C19R1 base corpus
# (_snapshot_c18_R2.txt, 131 186 runs — the corpus the §16f verdict of
# 11 gap-sets was measured on) PLUS this round's constructed runs.
#   usage: bash _c20_snapshot.sh <stamp> [glob ...]
set -e
B=/home/dev/project/reports/diaspora/results3/notifications_index
STAMP="${1:?usage: _c20_snapshot.sh <stamp> [glob ...]}"; shift
BASE="${C20_BASE:-$B/_snapshot_c18_R2.txt}"
OUT="$B/_snapshot_c20_${STAMP}.txt"
{ cat "$BASE"
  for g in "$@"; do find "$B" -maxdepth 1 -name "$g" -printf '%p\n'; done
} | sed 's#/\./#/#' | sort -u > "$OUT"
echo "$OUT  $(wc -l < "$OUT") runs  (base $(basename "$BASE") $(wc -l < "$BASE"), added $(( $(wc -l < "$OUT") - $(wc -l < "$BASE") )))"
