#!/bin/bash
# comments_index — RERUN OF THE ENGINE SECTION after porting the two shim
# tests (W3-memo find_target, X6b-preloads) into shim_tests.rb, 2026-09-13.
# Coverage layer is UNCHANGED: SUMMARY_IN is the restored _cov_RESTORE_20260913.json.
# The ACHK checkpoints from the 02:00/04:00 gate are reused, so the 3 679
# assumption probes replay instead of re-running.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/comments_index
S=/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/scratchpad
L=$S/_engine_shims.log
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
: > "$L"
COV="$B/_cov_RESTORE_20260913.json"
CAP_MB=6144

# The whole-stage checkpoint key digests (SUMMARY_IN, completion_config) ONLY —
# NOT shim_tests.rb — so with the sidecar in place the stage would be SKIPPED
# and the stale section replayed. Retire it (kept, not deleted).
if [ -f "$B/coverage_summary.json.checkpoint_key" ]; then
  mv "$B/coverage_summary.json.checkpoint_key" \
     "$B/_bak_coverage_summary.checkpoint_key_pre_shimport_20260913"
  say "retired the whole-stage sidecar so the section actually re-runs"
fi
cp -p "$B/_shim_results.json"       "$B/_bak_shim_results_pre_shimport_20260913.json" 2>/dev/null
cp -p "$B/coverage_summary.json"    "$S/_comments_summary_pre_shimport_20260913.json" 2>/dev/null
say "probe ckpt $(wc -l < "$B/_restore2_achk_probes.ckpt.jsonl") rows, index ckpt $(wc -l < "$B/_restore2_achk_index.ckpt.jsonl") rows"

# LAUNCH GATE (owner rule): free -g available >= 4 AND (19G - slice MemoryCurrent) >= cap
i=0
while :; do
  fg=$(free -g | awk '/^Mem/{print $7}')
  cur=$(systemctl --user show concolic-cov.slice -p MemoryCurrent --value 2>/dev/null)
  case "$cur" in ''|*[!0-9]*) cur=0;; esac
  head=$(( (19*1073741824 - cur) / 1048576 ))
  if [ "${fg:-0}" -ge 4 ] && [ "$head" -ge "$CAP_MB" ]; then
    say "LAUNCH: free=${fg}G cage_headroom_to_19G=${head}MB cap=${CAP_MB}MB"; break
  fi
  [ $((i % 10)) -eq 0 ] && say "WAIT: free=${fg}G (need >=4) cage_headroom_to_19G=${head}MB (need >=${CAP_MB}MB)"
  i=$((i+1)); sleep 30
done

systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax=6G -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_engine_shimport_20260913.time" \
  env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      CONCOLIC_SLOTS=1 \
      SUMMARY_IN="$COV" SUMMARY_OUT="$B/coverage_summary.json" \
      ENGINE_CHECKPOINT=1 \
      ACHK_CHECKPOINT="$B/_restore2_achk_probes.ckpt.jsonl" \
      ACHK_RESULTS_JSONL="$B/_restore2_achk_rows.jsonl" \
      ACHK_INDEX_CHECKPOINT="$B/_restore2_achk_index.ckpt.jsonl" \
      ACHK_DERIVE_CHECKPOINT="$B/_restore2_achk_derive.ckpt.jsonl" \
      ACHK_HEARTBEAT_S=60 \
      COMPLETION_AUDIT_TIMEOUT=21600 \
      python3 -u "$B/_engine_section.py" > "$B/_engine_shimport_20260913.log" 2>&1
say "ENGINE SECTION exit=$?"
tail -60 "$B/_engine_shimport_20260913.log" | tee -a "$L"
grep -E '^ENGINE SECTION DONE' "$B/_engine_shimport_20260913.log" >/dev/null \
  && say "ENGINE-SECTION-VERDICT-OK" || say "ENGINE-SECTION-VERDICT-MISSING **FAIL**"
grep -E 'Maximum resident|Elapsed' "$B/_engine_shimport_20260913.time" 2>/dev/null | tee -a "$L"
say "CI-SHIMPORT-DONE"
