#!/usr/bin/env bash
# Targeted differential for the empty-list representative guard.
#
# The 60-run general differential cannot exercise this fix: its corpus never
# drives an as_api_response list to length 0 (empty_relation_emission scores
# "pass" on it either way). So replay THREE REAL SEED SETS taken from dumps of
# the shipped corpus that DO reproduce the escape (_p46_emptyseeds.json,
# extracted by matching `len(SYM_RESULT_ActsAsApi__Collection_as_api_response_N)
# == 0` against a note that still binds `<that list>_row...`), through the
# unpatched and patched trees, and compare.
set -uo pipefail
B=/home/dev/project/reports/diaspora/results3/posts_show
cd /home/dev/project
for v in emptyctl emptyfix; do
  d="$B/_p46_$v"
  rm -rf "$d"; mkdir -p "$d"
  if [ "$v" = emptyctl ]; then src="$B/_p46_base"; else src="$B/_p46_cand2"; fi
  cp "$src/run_dse.rb" "$src/targets.rb" "$src/concolic_targets.rb" "$d/"
  cp "$B/concrete_run.json" "$B/concrete_aliases.json" "$d/"
  CONCOLIC_SLOTS=5 MAX_RUNS=12 TIME_BUDGET=900 JAVA_TOOL_OPTIONS= \
    EXTRA_SEEDS_JSON="$B/_p46_emptyseeds.json" SEEDS_ONLY=1 VARIANTS=anon_json,auth_json \
    reports/diaspora/tools/slot scripts/diaspora-concolic "$d/run_dse.rb" \
    > "$d/drive.log" 2>&1
  echo "### $v drive done, dumps=$(find "$d" -maxdepth 1 -name 'dump_*.json' | wc -l)"
done
for v in emptyctl emptyfix; do
  d="$B/_p46_$v"
  find "$d" -maxdepth 1 -name 'dump_*.json' > "$d/_dumps.txt"
  PYTHONPATH=/home/dev/project/src python3 \
    /home/dev/project/src/queries_from_runs/audits/empty_relation_emission_audit.py \
    "$d" --dump-list "$d/_dumps.txt" > "$d/_chk_empty_rel.txt" 2>&1
  echo "### $v empty_relation_emission: $(grep -E '^RESULT' "$d/_chk_empty_rel.txt")"
done
echo "### EMPTYDIFF DONE"
