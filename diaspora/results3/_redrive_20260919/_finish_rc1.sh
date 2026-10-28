#!/usr/bin/env bash
# After the RC-1 drives: separate the fresh dumps out of the endpoint dirs,
# restore each endpoint's original exploration_summary.json, verify branching,
# extract, and grade. The ORIGINAL corpora are left intact.
set -uo pipefail

R3=/home/dev/project/reports/diaspora/results3
RD=$R3/_redrive_20260919
QFR=$R3/queries_from_runs
BENCH=/home/dev/project/policy-extraction-bench
PY=/home/dev/project/venvs/queries_from_runs/bin/python3
SP=/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/scratchpad/rc1_extract
STEP=$RD/_logs/_rc1_pipeline.log

say() { echo "[$(date -Is)] $*" | tee -a "$STEP"; }
mkdir -p "$SP"

say "STEP 1: wait for drives"
while systemctl --user is-active rc1-drives.scope >/dev/null 2>&1; do sleep 60; done
say "STEP 1 DONE"

for EP in people_stream conversations_index; do
  say "STEP 2 [$EP]: move fresh dumps out of the endpoint dir"
  mkdir -p "$RD/$EP"
  find "$R3/$EP" -maxdepth 1 -name 'dump_*_RC1MOD.json' -print0 \
    | xargs -0 -r -n 500 mv -t "$RD/$EP"
  say "  fresh=$(ls "$RD/$EP" | grep -c '^dump_')  leftover_in_orig=$(ls "$R3/$EP" | grep -c '_RC1MOD')"

  say "STEP 3 [$EP]: restore original exploration_summary.json (the drive overwrote it)"
  cp -p "$RD/_bak/exploration_summary_${EP}_PRE_MODFIX.json" "$R3/$EP/exploration_summary.json"
  cp -p "$RD/_bak/exploration_summary_${EP}_PRE_MODFIX.json" "$RD/$EP/exploration_summary.json"
  $PY -c "
import sys; sys.path.insert(0,'/home/dev/project/src')
from queries_from_runs.endpoint_params import params_from_summary
a=params_from_summary('$R3/$EP'); b=params_from_summary('$RD/$EP')
print('  param pool identical:', a==b, a)" | tee -a "$STEP"

  say "STEP 4 [$EP]: original corpus intact? $(ls "$R3/$EP" | grep -c '^dump_') dumps"

  say "STEP 5 [$EP]: BRANCHING VERIFICATION"
  python3 "$RD/_verify_corpus.py" "$R3/$EP" "$RD/$EP" \
    > "$RD/_logs/_verify_${EP}.txt" 2>&1
  tail -60 "$RD/_logs/_verify_${EP}.txt" | tee -a "$STEP"
  if ! grep -q "VERDICT: BRANCHING IDENTICAL" "$RD/_logs/_verify_${EP}.txt"; then
    say "!!! $EP BRANCHING DIFFERS — STOPPING, no extraction for this endpoint"
    continue
  fi

  say "STEP 6 [$EP]: extraction"
  $PY "$QFR/_pcfold3_parallel.py" --endpoint "$EP" \
      --dumpdir "$RD/$EP" --out-dir "$SP" --shards 8 --cap 2 --suffix _rc1mod \
      > "$RD/_logs/_extract_${EP}.log" 2>&1
  say "  rc=$?"
  grep -E "EXTRACTION DONE|arm=" "$RD/_logs/_extract_${EP}.log" | tail -3 | tee -a "$STEP"
  f="$SP/${EP}_rc1mod_fix.sql"
  [ -f "$f" ] && say "  star=$(grep -c 'profiles\`\.\*' "$f") lazycols=$(grep -Eo 'profiles\`\.\`(bio|gender|birthday|location)\`' "$f" | wc -l)"
  cp -p "$SP/${EP}_rc1mod_"*.sql "$RD/" 2>/dev/null
done

say "STEP 7: build jsonl + grade (comments_index keeps its already-fixed policy)"
ARGS=()
[ -f "$SP/conversations_index_rc1mod_fix.sql" ] && ARGS+=("diaspora/conversations-index=$SP/conversations_index_rc1mod_fix.sql")
[ -f "$SP/people_stream_rc1mod_fix.sql" ] && ARGS+=("diaspora/people-stream=$SP/people_stream_rc1mod_fix.sql")
python3 "$RD/_build_and_grade.py" "$RD/ours_modfix.jsonl" "$RD/ours_rc1_all.jsonl" "${ARGS[@]}" 2>&1 | tee -a "$STEP"

cd "$BENCH" || exit 1
$PY -m bench.grade "$RD/ours_rc1_all.jsonl" 2>&1 | tee -a "$STEP"
say "STEP 8: extra pairs after"
python3 "$RD/_extra_pairs.py" "$RD/ours_rc1_all.jsonl" 2>&1 | grep -v "^    - " | tee -a "$STEP"

say "RC1_PIPELINE_COMPLETE"
