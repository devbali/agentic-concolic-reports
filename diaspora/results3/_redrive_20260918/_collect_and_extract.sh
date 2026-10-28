#!/usr/bin/env bash
# Post-drive: move the fresh people_stream dumps into their own corpus dir,
# restore the original exploration_summary.json, and re-extract the policy.
set -euo pipefail
RD=/home/dev/project/reports/diaspora/results3/_redrive_20260918
PS=/home/dev/project/reports/diaspora/results3/people_stream
QFR=/home/dev/project/reports/diaspora/results3/queries_from_runs
NEW=$RD/people_stream
PY=/home/dev/project/venvs/queries_from_runs/bin/python3

mkdir -p "$NEW"
# 1. keep the drive's own summary, then restore the pre-drive one in place
cp "$PS/exploration_summary.json" "$RD/_exploration_summary_people_stream_REDRIVE.json"
cp "$RD/_exploration_summary_people_stream_ORIG.json" "$PS/exploration_summary.json"

# 2. move fresh dumps out of the original corpus dir, stripping the _RD918 tag
n=0
for f in "$PS"/dump_*_RD918.json; do
  b=$(basename "$f"); mv "$f" "$NEW/${b%_RD918.json}.json"; n=$((n+1))
done
echo "moved $n dumps -> $NEW"
echo "original corpus left with: $(ls "$PS"/dump_*.json | wc -l) dumps"

# 3. param pool source for the new dir (params are fixed per endpoint and
#    unchanged by a note-refresh replay)
cp "$RD/_exploration_summary_people_stream_ORIG.json" "$NEW/exploration_summary.json"

# 4. preserve the pre-redrive policy, then re-extract over the fresh corpus
cp "$QFR/people_stream_pcfold3_base.sql" "$QFR/people_stream_pcfold3_base.sql.pre_redrive_20260918"
cp "$QFR/people_stream_pcfold3_fix.sql"  "$QFR/people_stream_pcfold3_fix.sql.pre_redrive_20260918"
cp "$QFR/_summary_people_stream_pcfold3.json" "$RD/_summary_people_stream_pcfold3_PRE_REDRIVE.json"

"$PY" "$QFR/_pcfold3_parallel.py" --endpoint people_stream \
    --dumpdir "$NEW" --out-dir "$QFR" --shards 8 --cap 2 --suffix _pcfold3 \
    > "$QFR/scratchpad_pcfold3_logs/people_stream_redrive.log" 2>&1
echo "VERDICT_REEXTRACT_PEOPLE_STREAM_DONE $(date -Is)"
