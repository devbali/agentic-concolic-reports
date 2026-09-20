#!/usr/bin/env bash
# usage: run3.sh <manifest basename without .rb>   (one JRuby at a time, machine-wide lock)
set -u
ADV=/home/dev/project/reports/diaspora/results3/comments_index/adversary3
BATCH=/home/dev/project/reports/diaspora/results3/comments_index
N=$1
unset JAVA_TOOL_OPTIONS
rm -f "$ADV/concrete_run.json"
systemd-run --user --pipe --wait -p MemoryMax=4000M -p MemorySwapMax=0 --working-directory=/home/dev/project \
  bash -c "unset JAVA_TOOL_OPTIONS; export CONCRETE_COVERAGE=${COV:-0}; flock /tmp/concolic-slot.lock scripts/diaspora-concolic /home/dev/project/reports/diaspora/tools/concrete_checker/concrete_run_probe.rb $ADV/$N.rb" \
  > "$ADV/runs/$N.log" 2>&1
RC=$?
echo "EXIT=$RC" >> "$ADV/runs/$N.log"
if [ -f "$ADV/concrete_run.json" ]; then
  mv "$ADV/concrete_run.json" "$ADV/runs/$N.json"
  { echo "### mock_note_check"; python3 /home/dev/project/src/end_to_end_completion_checker/mock/mock_note_check.py "$ADV/runs/$N.json" "$BATCH" --aliases "$BATCH/concrete_aliases.json"; echo "EXIT=$?";
    echo; echo "### note_fidelity_audit"; PYTHONPATH=/home/dev/project/src /home/dev/project/venvs/queries_from_runs/bin/python /home/dev/project/reports/diaspora/tools/note_fidelity_audit.py "$BATCH" "$ADV/runs/$N.json" --aliases "$BATCH/concrete_aliases.json"; echo "EXIT=$?"; } > "$ADV/runs/$N.judge.txt" 2>&1
fi
echo "DONE $N rc=$RC json=$( [ -f "$ADV/runs/$N.json" ] && echo yes || echo no ) $(date +%T)" >> "$ADV/runs/_progress.log"
