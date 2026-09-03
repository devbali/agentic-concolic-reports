#!/usr/bin/env bash
# usage: run_scenario.sh <manifest basename>   (env: ADV5_REAL_LAYOUT=1 default, COV=1)
set -u
ADV=/home/dev/project/reports/diaspora/results3/conversations_index/adversary6
BATCH=/home/dev/project/reports/diaspora/results3/conversations_index
N=$1
unset JAVA_TOOL_OPTIONS
rm -f "$ADV/concrete_run.json"
systemd-run --user --pipe --wait -p MemoryMax=4000M -p MemorySwapMax=0 --working-directory=/home/dev/project \
  bash -c "unset JAVA_TOOL_OPTIONS; export CONCRETE_COVERAGE=${COV:-0} JRUBY_OPTS=${JOPTS:---debug} ADV5_REAL_LAYOUT=${ADV5_REAL_LAYOUT:-1}; flock /tmp/concolic-slot.lock scripts/diaspora-concolic /home/dev/project/src/ruby_runtime/completion_checker/concrete_run_probe.rb $ADV/$N.rb" \
  > "$ADV/_logs/$N.log" 2>&1
echo "EXIT=$?" >> "$ADV/_logs/$N.log"
if [ -f "$ADV/concrete_run.json" ]; then
  mv "$ADV/concrete_run.json" "$ADV/runs/$N.json"
  { echo "### mock_note_check"; python3 /home/dev/project/src/end_to_end_completion_checker/mock/mock_note_check.py "$ADV/runs/$N.json" "$BATCH" --aliases "$BATCH/concrete_aliases.json"; echo "EXIT=$?";
    echo; echo "### note_fidelity_audit"; PYTHONPATH=/home/dev/project/src /home/dev/project/venvs/queries_from_runs/bin/python /home/dev/project/reports/diaspora/tools/note_fidelity_audit.py "$BATCH" "$ADV/runs/$N.json" --aliases "$BATCH/concrete_aliases.json"; echo "EXIT=$?";
    echo; echo "### _multiset_counts (batch judge, write-aware)"; python3 "$BATCH/_multiset_counts.py" "$BATCH" --runs "$ADV/runs/$N.json"; echo "EXIT=$?"; } > "$ADV/$N.judge.txt" 2>&1
  [ -f "$ADV/_corpus_scan.json" ] && python3 "$ADV/_req_stats.py" "$ADV/_corpus_scan.json" "$ADV/runs/$N.json" > "$ADV/$N.stats.txt" 2>&1
fi
echo "DONE $N $(date +%T)" >> "$ADV/_progress.log"
