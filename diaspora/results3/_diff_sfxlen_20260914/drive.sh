#!/bin/bash
# GROUND-TRUTH DIFFERENTIAL for the suffix-vs-length-var regression.
# Same fixture (notifications_index run_dse.rb + targets.rb, byte-identical in
# both arms), same seed (_seed_multirow.json, byte-identical), same scenario
# (_demand_suffixes.json[5] == {"_rows)":0}, the d5 scenario of _gen_dsfx.sh),
# same variant (html_typed), MAX_RUNS=1. ONLY concolic_targets.rb differs:
#   pre/  = as last night's name-boundary edit left it (skip present)
#   post/ = skip removed (pre-edit behaviour restored)
set +e
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
D=/home/dev/project/reports/diaspora/results3/_diff_sfxlen_20260914
SFX='{"_rows)":0}'
for v in pre post; do
  echo "=== ARM $v  $(date -Is) ==="
  env VARIANTS=html_typed SEED_SUFFIXES="$SFX" \
      EXTRA_SEEDS_JSON="$D/$v/_seed_multirow.json" \
      LABEL_SUFFIX="_sfxdiff" MAX_RUNS=1 TIME_BUDGET=600 \
      /home/dev/project/scripts/diaspora-concolic "$D/$v/run_dse.rb" 2>&1
  echo "=== ARM $v exit=$? $(date -Is) ==="
done
echo "=== DIFFERENTIAL VERDICT: both arms finished $(date -Is) ==="
