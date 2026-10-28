#!/bin/bash
# CAGED PIPELINE (owner directive 2026-09-11). Every job runs via `cage`:
# concolic-cov.slice + per-job MemoryMax + choom -n 1000. Budget while the
# detached pass B (pxcovB2.scope, ~1.5 G) is alive: this drive's caps sum to
# <= 4 G. When pass B exits, stage 2 runs its two jobs CONCURRENTLY (5 G).
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"

# ---- stage 1 (now, alone: 3.5 G <= 4 G budget) -----------------------------
# §59's lever pricing on p5: what the demand universe becomes if the
# variable-disjoint pairs were independent. A HYPOTHETICAL; declares nothing.
cage pxwhatif.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 3600 python3 -u "$B/_whatif_indep.py" \
  > "$B/_whatif_indep.log" 2>&1
caged_verdict pxwhatif.scope "$B/_whatif_indep.log" '^EXACT:' >> "$B/_pipeline.log"

# ---- wait for pass B, then stage 2 runs its jobs TOGETHER ------------------
while systemctl --user is-active pxcovB2.scope >/dev/null 2>&1; do sleep 30; done
echo "[$(date -Is)] pass B ended; raising concurrency" >> "$B/_pipeline.log"

# 2a: what re-keying the find_by family by identity would do to `remaining`
cage pxwfmerge.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 3600 python3 -u "$B/_whatif_wf_merge.py" \
  > "$B/_whatif_wf_merge.log" 2>&1 &
P1=$!
# 2b: X11 diagnostic — keep the probe dumps for ONE same-rep control pair and
# show that flip-both's trace is a SUBSET of flip-A's, which is why `novel` is
# empty and the probe cannot fail it.
cage pxx11.scope 1500M \
  flock /tmp/concolic-heavy.lock python3 -u \
    /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
    "$B/assumption_manifest.json" --declared "$B/_x11_pair.json" \
    --json-out "$B/_x11_results.json" --keep \
  > "$B/_x11.log" 2>&1 &
P2=$!
wait $P1; caged_verdict pxwfmerge.scope "$B/_whatif_wf_merge.log" '^EXACT:' >> "$B/_pipeline.log"
wait $P2; caged_verdict pxx11.scope "$B/_x11.log" 'RESULT:' >> "$B/_pipeline.log"
echo "[$(date -Is)] pipeline done" >> "$B/_pipeline.log"
