#!/bin/bash
# P25 — the PER-KEY residue of each §16c reading, from that pass's OWN
# checkpoint (never the summary: `missing[]` is cut at MISSING_CAP).
# `_p15_classify.py` runs main() at import, so it is RUN, never imported.
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
for T in P25OFF P25STRICT P25OR; do
  low=$(echo "$T" | tr 'A-Z' 'a-z')
  CK="$B/_cov_${low}.ckpt.jsonl"; COV="$B/_cov_FINAL_${T}_20260912.json"
  [ -s "$CK" ] || { echo "== $T: no checkpoint"; continue; }
  echo "===== $T ====="
  P15_CKPT="$CK" P15_COV="$COV" P15_GAPS="$B/_p25_gaps_${T}.json" \
    PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
    python3 -u "$B/_p15_classify.py" 2>&1 | tail -45
done
echo "P25-RESIDUE-DONE"
