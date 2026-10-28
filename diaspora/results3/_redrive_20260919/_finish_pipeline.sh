#!/usr/bin/env bash
# Wait for the comments_index drive, then verify -> extract -> grade, unattended.
set -uo pipefail

RD=/home/dev/project/reports/diaspora/results3/_redrive_20260919
R3=/home/dev/project/reports/diaspora/results3
QFR=$R3/queries_from_runs
BENCH=/home/dev/project/policy-extraction-bench
PY=/home/dev/project/venvs/queries_from_runs/bin/python3
OUTSQL=/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/scratchpad/extract_final
STEP=$RD/_logs/_pipeline.log

say() { echo "[$(date -Is)] $*" | tee -a "$STEP"; }

say "STEP 1: waiting for drive scopes to finish"
while [ "$(systemctl --user list-units --type=scope 2>/dev/null | grep -c 'rd919b-comments.*running')" != "0" ]; do
  sleep 60
done
N=$(ls "$RD/comments_index" | grep -c '^dump_')
say "STEP 1 DONE: drive finished, $N dumps"

say "STEP 2: harness failures across variant logs"
grep -h "HARNESS FAILURE" "$RD"/_logs/comments_index_*.log 2>/dev/null | sort | uniq -c | tee -a "$STEP"
say "STEP 2: per-variant summary lines"
grep -hA8 "exploration done" "$RD"/_logs/comments_index_*.log 2>/dev/null | tee -a "$STEP"

say "STEP 3: residual 'profiles.*' dumps (expect 0)"
find "$RD/comments_index" -name 'dump_*.json' -print0 \
  | xargs -0 -r grep -l 'profiles\\"\.\*' 2>/dev/null | wc -l | tee -a "$STEP"

say "STEP 4: branching-safety verification (orig vs fresh)"
python3 "$RD/_verify_corpus.py" "$R3/comments_index" "$RD/comments_index" \
  > "$RD/_logs/_verify_corpus_comments_index.txt" 2>&1
tail -40 "$RD/_logs/_verify_corpus_comments_index.txt" | tee -a "$STEP"

say "STEP 5: restore original exploration_summary.json as param-pool source"
cp -p "$R3/comments_index/exploration_summary.json" "$RD/comments_index/exploration_summary.json"
$PY -c "
import sys; sys.path.insert(0,'/home/dev/project/src')
from queries_from_runs.endpoint_params import params_from_summary
a=params_from_summary('$R3/comments_index'); b=params_from_summary('$RD/comments_index')
print('param pool identical:', a==b, a)" | tee -a "$STEP"

say "STEP 6: extraction (pcfold3, 8 shards, cap 2)"
mkdir -p "$OUTSQL"
$PY "$QFR/_pcfold3_parallel.py" --endpoint comments_index \
    --dumpdir "$RD/comments_index" --out-dir "$OUTSQL" \
    --shards 8 --cap 2 --suffix _modfix > "$RD/_logs/_extract_final.log" 2>&1
say "STEP 6 rc=$?"
tail -6 "$RD/_logs/_extract_final.log" | tee -a "$STEP"

say "STEP 7: residual profiles star / lazy cols in new policy"
for f in "$OUTSQL"/comments_index_modfix_base.sql "$OUTSQL"/comments_index_modfix_fix.sql; do
  [ -f "$f" ] || continue
  echo "  $(basename "$f"): star=$(grep -c 'profiles\`\.\*' "$f") lazycols=$(grep -Eo 'profiles\`\.\`(bio|gender|birthday|location)\`' "$f" | wc -l)" | tee -a "$STEP"
done

say "STEP 8: build results jsonl + grade"
python3 "$RD/_build_and_grade.py" \
  "$R3/_bench_20260919/ours_pcfold3_fix.jsonl" \
  "$RD/ours_modfix.jsonl" \
  "diaspora/comments-index=$OUTSQL/comments_index_modfix_fix.sql" 2>&1 | tee -a "$STEP"

cd "$BENCH" || exit 1
$PY -m bench.grade "$RD/ours_modfix.jsonl" 2>&1 | tee -a "$STEP"

say "STEP 9: extra-pair diff (after)"
python3 "$RD/_extra_pairs.py" "$RD/ours_modfix.jsonl" comments-index 2>&1 | tee -a "$STEP"

say "PIPELINE_COMPLETE"
