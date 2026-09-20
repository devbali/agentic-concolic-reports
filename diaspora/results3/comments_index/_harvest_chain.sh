#!/bin/bash
# Rule T2 from-scratch regeneration after boundary harvest B-1/B-2.
# E12 (2026-09-11): src/queries_from_runs is app-agnostic and REQUIRES an
# app config; bind_resolution_audit and identity_symbolicity_audit read the
# schema and the principal columns from it and go RED without one.
export QFR_APP_CONFIG="${QFR_APP_CONFIG:-/home/dev/project/reports/diaspora/queries_config/app.json}"
B=/home/dev/project/reports/diaspora/results3/comments_index
S=/tmp/claude-1000/-home-dev-project/e0395c49-56d0-42c0-af70-a3707c6552fa/scratchpad
RUN="flock /tmp/concolic-slot.lock systemd-run --user --pipe --wait -p MemoryMax=3000M -p MemorySwapMax=0 --working-directory=/home/dev/project"
RPT="systemd-run --user --pipe --wait -p MemoryMax=4500M -p MemorySwapMax=0 --working-directory=/home/dev/project"
find $B -maxdepth 1 -name 'dump_*.json' -delete
rm -f $B/concrete*.sqlite3 $B/_demand_*.json
for v in anon_json auth_json anon_mobile auth_mobile; do
  $RUN bash -c "unset JAVA_TOOL_OPTIONS; VARIANT=$v MAX_RUNS=6000 TIME_BUDGET=600 /home/dev/project/scripts/diaspora-concolic $B/run_dse.rb" > $S/h_$v.log 2>&1
  echo "== base $v: $(grep -E 'distinct paths|run errors' $S/h_$v.log | tr -s ' ' | tr '\n' ' ')"
done
# targeted roots for the four within-chain combinations (cycle-3 finding)
for v in anon_json auth_json; do
  [ -f $B/_targeted_$v.json ] || continue
  $RUN bash -c "unset JAVA_TOOL_OPTIONS; VARIANT=$v EXTRA_SEEDS_JSON=$B/_targeted_$v.json MAX_RUNS=900 TIME_BUDGET=240 LABEL_SUFFIX=_t1 /home/dev/project/scripts/diaspora-concolic $B/run_dse.rb" > $S/h_t1_$v.log 2>&1
  echo "== targeted $v: $(grep -E 'distinct paths|run errors' $S/h_t1_$v.log | tr -s ' ' | tr '\n' ' ')"
done
for it in 1 2 3; do
  $RPT bash -c 'unset JAVA_TOOL_OPTIONS; SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=64 PYTHONPATH=src python3 reports/diaspora/results3/comments_index/coverage_report.py' 2>&1 | grep -E "^COMPLETE=|RuntimeError"
  cd $B && python3 demand_round.py | tail -1
  ls $B/_demand_*.json >/dev/null 2>&1 || { echo "no demand seeds"; break; }
  for v in anon_json auth_json anon_mobile auth_mobile; do
    [ -f $B/_demand_$v.json ] || continue
    $RUN bash -c "unset JAVA_TOOL_OPTIONS; VARIANT=$v EXTRA_SEEDS_JSON=$B/_demand_$v.json MAX_RUNS=900 TIME_BUDGET=240 LABEL_SUFFIX=_h$it /home/dev/project/scripts/diaspora-concolic $B/run_dse.rb" > $S/h_d${it}_$v.log 2>&1
    echo "== demand$it $v: $(grep -E 'distinct paths|run errors' $S/h_d${it}_$v.log | tr -s ' ' | tr '\n' ' ')"
  done
  rm -f $B/_demand_*.json
done
$RPT bash -c 'unset JAVA_TOOL_OPTIONS; SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=64 PYTHONPATH=src python3 reports/diaspora/results3/comments_index/coverage_report.py' 2>&1 | grep -E "^COMPLETE=|RuntimeError"
for sc in anon auth mobile; do
  $RUN bash -c "unset JAVA_TOOL_OPTIONS; /home/dev/project/scripts/diaspora-concolic /home/dev/project/reports/diaspora/tools/concrete_checker/concrete_run_probe.rb $B/concrete_manifest_$sc.rb" > $S/h_concrete_$sc.log 2>&1
  grep -E "target_calls|ERROR" $S/h_concrete_$sc.log
  [ -f $B/concrete_run.json ] && mv $B/concrete_run.json $B/concrete_run_$sc.json
done
python3 $B/merge_concrete_runs.py
echo "=== BIND RESOLUTION (Rule V)"
PYTHONPATH=/home/dev/project/src /home/dev/project/venvs/queries_from_runs/bin/python /home/dev/project/src/queries_from_runs/audits/bind_resolution_audit.py $B 2>&1 | tail -4
echo "=== NOTE CHECK"
python3 /home/dev/project/src/end_to_end_completion_checker/mock/mock_note_check.py $B/concrete_run.json $B --aliases $B/concrete_aliases.json 2>&1 | tail -3
echo "=== FIDELITY"
PYTHONPATH=/home/dev/project/src /home/dev/project/venvs/queries_from_runs/bin/python /home/dev/project/reports/diaspora/tools/note_fidelity_audit.py $B $B/concrete_run_anon.json $B/concrete_run_auth.json $B/concrete_run_mobile.json $B/adversary/runs/C0*.json --aliases $B/concrete_aliases.json 2>&1 | grep -E "^-- (MISSING|STAR|AGG|PROJ|PRED|EXACT)|RESULT"
echo HARVESTDONE
