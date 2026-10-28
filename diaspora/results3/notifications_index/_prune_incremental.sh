#!/bin/bash
# INCREMENTAL PRUNE (2026-09-10, §12.7).
#
# `_prune_corpus.py` keeps ONE dump per distinct outcome profile, and §10.2
# verified that the §16b verdict is a function of the profile SET alone. The
# previously pruned list is therefore already a complete cover of the OLD
# corpus's profiles, so
#     profiles(old_pruned  U  new dumps) == profiles(old corpus U new dumps)
# and pruning the union yields the same profile set as pruning the whole new
# corpus -- at the cost of loading |old_pruned| + |new| dumps instead of
# |whole corpus|. Nothing is deleted; this writes a snapshot LIST.
#
# usage: _prune_incremental.sh <old_pruned.txt> <new_full_snapshot.txt> <out.txt> [shards]
set -eu
B=/home/dev/project/reports/diaspora/results3/notifications_index
OLDP="$1"; NEWSNAP="$2"; OUT="$3"; NS="${4:-3}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
# the union: every dump of the old pruned cover, plus every dump the new
# snapshot has that the old pruned cover does not already carry.
sort -u "$OLDP" > "$W/oldp.txt"
sort -u "$NEWSNAP" > "$W/new.txt"
cat "$W/oldp.txt" "$W/new.txt" | sort -u > "$W/union.txt"
echo "old pruned $(wc -l < "$W/oldp.txt") + new snapshot $(wc -l < "$W/new.txt") -> union $(wc -l < "$W/union.txt") to profile"
for i in $(seq 0 $((NS-1))); do
  ( cd "$B" && DUMP_LIST="$W/union.txt" python3 _prune_corpus.py \
      --shards "$NS" --shard "$i" --part "$W/part_$i.json" ) &
done
wait
( cd "$B" && DUMP_LIST="$W/union.txt" python3 _prune_corpus.py --parts "$W/part_*.json" --out "$OUT" )
