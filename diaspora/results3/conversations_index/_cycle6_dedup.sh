#!/bin/bash
# Move EXACT-duplicate dumps (same variant + ordered (expr,taken) path + note
# multiset + consumed seeds + scenario + error) out of the corpus. Such a dump
# adds nothing to the coverage tree, to a note shape, to the assumption
# checker's corpus scan or to any audit's counts; it only costs memory.
set -u
B=/home/dev/project/reports/diaspora/results3/conversations_index
python3 /home/dev/project/reports/diaspora/results3/conversations_index/_dedup_scan.py "$B" "$B/_dup_list.txt"
mkdir -p "$B/_dup_dumps"
if [ -s "$B/_dup_list.txt" ]; then
  ( cd "$B" && tr '\n' '\0' < _dup_list.txt | xargs -0 -r -n 500 mv -t _dup_dumps/ )
fi
echo "corpus=$(find $B -maxdepth 1 -name 'dump_*.json'|wc -l) archived=$(find $B/_dup_dumps -name 'dump_*.json'|wc -l)"
echo DEDUP_DONE
