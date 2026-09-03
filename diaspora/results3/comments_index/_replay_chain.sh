#!/bin/bash
B=/home/dev/project/reports/diaspora/results3/comments_index
S=/tmp/claude-1000/-home-dev-project/e0395c49-56d0-42c0-af70-a3707c6552fa/scratchpad
RUN="flock /tmp/concolic-slot.lock systemd-run --user --pipe --wait -p MemoryMax=3000M -p MemorySwapMax=0 --working-directory=/home/dev/project"
find $B -maxdepth 1 -name 'dump_*.json' -delete   # ARG_MAX: rm -f dump_*.json silently fails at 20k+ files
rm -f $B/concrete*.sqlite3
for v in anon_json auth_json anon_mobile auth_mobile; do
  $RUN bash -c "unset JAVA_TOOL_OPTIONS; VARIANT=$v SEEDS_ONLY=1 EXTRA_SEEDS_JSON=$B/_replay_$v.json MAX_RUNS=40000 TIME_BUDGET=3000 /home/dev/project/scripts/diaspora-concolic $B/run_dse.rb" > $S/rp_$v.log 2>&1
  echo "== replay $v: $(grep -E 'distinct paths|run errors' $S/rp_$v.log | tr -s ' ' | tr '\n' ' ')"
done
echo "dumps: $(find $B -maxdepth 1 -name 'dump_*.json' | wc -l)"
for sc in anon auth mobile; do
  $RUN bash -c "unset JAVA_TOOL_OPTIONS; /home/dev/project/scripts/diaspora-concolic /home/dev/project/src/ruby_runtime/completion_checker/concrete_run_probe.rb $B/concrete_manifest_$sc.rb" > $S/rp_concrete_$sc.log 2>&1
  grep -E "target_calls|ERROR" $S/rp_concrete_$sc.log
  [ -f $B/concrete_run.json ] && mv $B/concrete_run.json $B/concrete_run_$sc.json
done
python3 $B/merge_concrete_runs.py
echo "=== BIND RESOLUTION"
PYTHONPATH=/home/dev/project/src /home/dev/project/venvs/queries_from_runs/bin/python /home/dev/project/src/queries_from_runs/audits/bind_resolution_audit.py $B 2>&1 | tail -6
echo "=== NOTE CHECK"
python3 /home/dev/project/src/end_to_end_completion_checker/mock/mock_note_check.py $B/concrete_run.json $B --aliases $B/concrete_aliases.json 2>&1 | tail -3
echo "=== FIDELITY"
PYTHONPATH=/home/dev/project/src /home/dev/project/venvs/queries_from_runs/bin/python /home/dev/project/reports/diaspora/tools/note_fidelity_audit.py $B $B/concrete_run_anon.json $B/concrete_run_auth.json $B/concrete_run_mobile.json $B/adversary/runs/C0*.json --aliases $B/concrete_aliases.json 2>&1 | grep -E "^-- (MISSING|STAR|AGG|PROJ|PRED|EXACT)|RESULT"
echo REPLAYDONE
