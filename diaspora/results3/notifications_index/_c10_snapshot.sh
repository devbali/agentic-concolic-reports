#!/bin/bash
# Snapshot the corpus and INCREMENTALLY prune it (§10.2/§12.7): writes
# _snapshot_<ts>.txt (population) and _snapshot_pruned_<ts>.txt (one dump per
# distinct outcome profile — the list every census and pass runs on).
# usage: _c10_snapshot.sh <old_pruned.txt> [shards]   -> prints the new pruned path
set -eu
B=/home/dev/project/reports/diaspora/results3/notifications_index
OLDP="$1"; NS="${2:-3}"
TS=$(date +%Y%m%d_%H%M%S)
cd "$B"
find "$B" -maxdepth 1 -name 'dump_*.json' > "_snapshot_${TS}.txt"
echo "[$(date -Is)] population: $(wc -l < "_snapshot_${TS}.txt") dumps"
./_prune_incremental.sh "$OLDP" "_snapshot_${TS}.txt" "_snapshot_pruned_${TS}.txt" "$NS"
echo "[$(date -Is)] pruned: $(wc -l < "_snapshot_pruned_${TS}.txt") profiles"
echo "PRUNED=_snapshot_pruned_${TS}.txt"
