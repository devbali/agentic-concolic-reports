#!/usr/bin/env bash
# usage: run_scenario.sh <manifest basename without .rb>
set -u
ADV=/home/dev/project/reports/diaspora/results3/conversations_index/adversary
BATCH=/home/dev/project/reports/diaspora/results3/conversations_index
N=$1
unset JAVA_TOOL_OPTIONS
rm -f "$ADV/concrete_run.json"
systemd-run --user --pipe --wait -p MemoryMax=4000M -p MemorySwapMax=0 --working-directory=/home/dev/project \
  bash -c "unset JAVA_TOOL_OPTIONS; export CONCRETE_COVERAGE=${COV:-1} JRUBY_OPTS=${JOPTS:---debug}; flock /tmp/concolic-slot.lock scripts/diaspora-concolic /home/dev/project/src/ruby_runtime/completion_checker/concrete_run_probe.rb $ADV/$N.rb" \
  > "$ADV/runs/$N.log" 2>&1
echo "EXIT=$?" >> "$ADV/runs/$N.log"
if [ -f "$ADV/concrete_run.json" ]; then
  mv "$ADV/concrete_run.json" "$ADV/runs/$N.json"
  { echo "### mock_note_check"; python3 /home/dev/project/src/end_to_end_completion_checker/mock_note_check.py "$ADV/runs/$N.json" "$BATCH" --aliases "$BATCH/concrete_aliases.json"; echo "EXIT=$?";
    echo; echo "### concrete_checker"; python3 /home/dev/project/src/end_to_end_completion_checker/concrete_checker.py "$ADV/runs/$N.json" "$BATCH" --aliases "$BATCH/concrete_aliases.json"; echo "EXIT=$?"; } > "$ADV/runs/$N.judge.txt" 2>&1
fi
echo "DONE $N" >> "$ADV/runs/_progress.log"
