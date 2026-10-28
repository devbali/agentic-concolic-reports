#!/bin/bash
# C13 — build the dump list for the next coverage pass: the C12 snapshot PLUS
# every dump produced since, i.e. this round's constructed runs. Written as an
# explicit FILE so the pass has a fixed, re-runnable corpus of record (and the
# checkpoint key is stable across a retry).
#   usage: bash _c13_snapshot.sh <stamp> [extra-glob ...]
set -e
B=/home/dev/project/reports/diaspora/results3/notifications_index
STAMP="${1:?usage: _c13_snapshot.sh <stamp> [glob ...]}"; shift
BASE="$B/_snapshot_pruned_20260911_143539.txt"
OUT="$B/_snapshot_c13_${STAMP}.txt"
{ cat "$BASE"
  for g in "$@"; do
    find "$B" -maxdepth 1 -name "$g" -printf '%p\n'
  done
} | sed 's#/\./#/#' | sort -u > "$OUT"
echo "$OUT  $(wc -l < "$OUT") runs  (base $(wc -l < "$BASE"), added $(( $(wc -l < "$OUT") - $(wc -l < "$BASE") )))"
