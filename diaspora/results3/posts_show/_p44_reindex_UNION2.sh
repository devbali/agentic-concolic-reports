#!/bin/bash
# P44 -- rebuild the UNION index over the CURRENT corpus (post rounds 1-13+).
# Same recipe as the original P35C -> UNION fix: the frozen 52,444-profile
# index is now stale relative to ~230k more driven dumps, and the gate's
# control_support has collapsed to n=1 for 70-85% of testable classes as a
# result (measured on P44R8-R12, 2026-09-16). This produces UNION2 alongside
# UNION -- nothing is overwritten, callers opt in via P44_INDEX.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
L="$B/_p44_reindex_UNION2.log"
say(){ echo "[$(date -Is)] $*" >> "$L"; }
: > "$L"
find "$B" -maxdepth 1 -name 'dump_*.json' | sort -u > "$B/_snapshot_p44_UNION2.txt"
say "corpus $(wc -l < "$B/_snapshot_p44_UNION2.txt") dumps -> prune"
. "$B/_cage.sh"
cage "p44prunU2.scope" 6G \
  env DUMP_LIST="$B/_snapshot_p44_UNION2.txt" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_prune_corpus.py" --out "$B/_snapshot_pruned_UNION2.txt" >> "$L" 2>&1
grep -q . "$B/_snapshot_pruned_UNION2.txt" || { say "REINDEX-FAILED prune"; exit 4; }
say "pruned -> $(wc -l < "$B/_snapshot_pruned_UNION2.txt") profiles; indexing"
DUMP_LIST="$B/_snapshot_pruned_UNION2.txt" PARTS_IN="$B/_p44_parts_UNION.json" \
  P18_INDEX="$B/_p44_index_UNION2.pkl" PYTHONPATH=/home/dev/project/src \
  python3 -u "$B/_p23_index.py" >> "$L" 2>&1
grep -q 'P23-INDEX-DONE' "$L" && say "REINDEX-DONE UNION2" || say "REINDEX-FAILED index"
