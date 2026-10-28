#!/bin/bash
# =============================================================================
# M-SNAP GATE, RUN 2 (2026-09-12) — the REAL verdict.
#
# Run 1 (_m1_gate.sh, campaign §26.3) returned 8/8 PASS and every PASS was
# VACUOUS: the probe wrote its violating value at a CANONICAL-named DEAD KNOB
# the runtime never reads (X10 class). Both defects are now fixed in
# src/.../assumption_checker.py:
#   - pick_live_snapshot / _live_seed_key: seed the LIVE ordinal key, and
#     NOT-TESTABLE (never PASS) when no snapshot resolves one;
#   - _dump_dirs + "no dump" => ERROR (never "unrealizable").
#
# NO REUSE OF RUN 1's VERDICTS, two independent ways:
#   1. a FRESH checkpoint path (_m1_probe_checkpoint_v2.jsonl); run 1's file
#      is left untouched as evidence;
#   2. even at the old path the header key would not match — ProbeCache mixes
#      checkpoint.source_hash(assumption_checker) into it, and the edit moved
#      it from 9e19ecc8166b9beed199f45e91da27fd to 4b64bc69aab3f66748fc10e206a238d7.
# Results/rows go to _v2 files so run 1's are not appended to.
# ACHK_LABEL_TOKEN=msnap2 so a run-1 dump can never be globbed back in.
# Judged by its OWN verdict line `^RESULT:`; without it the run was KILLED.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
CAPMB="${CAPMB:-7168}"
LOG="$B/_m1_gate_v2.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_m1.log"; }
say "M-SNAP GATE v2: 8 declarations, cap=${CAPMB}MB, batch dir $(ls -U "$B" | grep -c '^dump_.*json$') dumps"
say "  checker md5 $(md5sum /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py | cut -d' ' -f1)"
. "$B/_wait_mem.sh"
wait_mem "$CAPMB" "_m1/gate_v2" | tee -a "$B/_m1.log"
/usr/bin/time -v -o "$B/_m1_gate_v2.time" \
  env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      CONCOLIC_SLOTS=2 CONCOLIC_PROBE_WORKERS=1 ACHK_PROBE_BATCH=8 \
      ACHK_LABEL_TOKEN=msnap2 \
      ACHK_CHECKPOINT="$B/_m1_probe_checkpoint_v2.jsonl" \
      ACHK_RESULTS_JSONL="$B/_m1_rows_v2.jsonl" \
      python3 -u /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
        "$B/assumption_manifest.json" --declared "$B/_msnap_declared.json" \
        --json-out "$B/_m1_gate_results_v2.json" --keep > "$LOG" 2>&1
say "M-SNAP GATE v2 exit=$?"
if grep -qE '^RESULT:' "$LOG"; then
  say "VERDICT M1-GATE-V2: OK (line present)"
  grep -E '^RESULT:|^  (PASS|FAIL|ERROR|NOT-)' "$LOG" | tee -a "$B/_m1.log"
  grep -E 'Maximum resident|Elapsed' "$B/_m1_gate_v2.time" | tee -a "$B/_m1.log"
  say "M1-GATE-V2-DONE"
else
  say "VERDICT M1-GATE-V2: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
  tail -25 "$LOG" | sed 's/^/    /' | tee -a "$B/_m1.log"
  exit 10
fi
