#!/usr/bin/env bash
# Sequence: wait for cand1's drive -> its checks -> cand2's drive -> its checks.
# Slots are shared with the (untouchable) conversations_index gate, so these run
# one after another rather than in parallel.
B=/home/dev/project/reports/diaspora/results3/posts_show
until grep -q "run_dse.rb done" "$B/_p46_cand1/drive.log" 2>/dev/null; do sleep 15; done
echo "### CAND1 DRIVE DONE"
bash "$B/_p46_diff.sh" checks  "$B/_p46_cand1" > "$B/_p46_cand1/_checks.log" 2>&1
bash "$B/_p46_diff.sh" compare "$B/_p46_base" "$B/_p46_cand1" > "$B/_p46_cand1/_compare.log" 2>&1
echo "### CAND1 CHECKS+COMPARE DONE"
bash "$B/_p46_diff.sh" drive   "$B/_p46_cand2" 25 > "$B/_p46_cand2/_drive_wrap.log" 2>&1
echo "### CAND2 DRIVE DONE"
bash "$B/_p46_diff.sh" checks  "$B/_p46_cand2" > "$B/_p46_cand2/_checks.log" 2>&1
bash "$B/_p46_diff.sh" compare "$B/_p46_base" "$B/_p46_cand2" > "$B/_p46_cand2/_compare.log" 2>&1
echo "### ALL DONE"
