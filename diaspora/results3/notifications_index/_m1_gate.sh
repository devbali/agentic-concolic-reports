#!/bin/bash
# =============================================================================
# M-SNAP GATE (2026-09-12) — the assumption gate on the EIGHT new
# SymbolicConstraintAssumption declarations only (residue (a), campaign §26).
# One representative per class is the standing rule; here the class is
# (variable x hole) and there are only eight, so all eight are tested.
# Checkpointed (ACHK_CHECKPOINT): a kill resumes instead of restarting.
# Judged by its OWN verdict line `^RESULT:`; without it the run was KILLED.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
CAP="${CAP:-7G}"; CAPMB="${CAPMB:-7168}"
LOG="$B/_m1_gate.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_m1.log"; }
say "M-SNAP GATE: 8 declarations, cap=$CAP, batch dir $(ls -U "$B" | grep -c '^dump_.*json$') dumps"
say "  checker md5 $(md5sum /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py | cut -d' ' -f1)"
. "$B/_wait_mem.sh"
wait_mem "$CAPMB" "_m1/gate" | tee -a "$B/_m1.log"
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_m1_gate.time" \
  env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      CONCOLIC_SLOTS=2 CONCOLIC_PROBE_WORKERS=1 ACHK_PROBE_BATCH=8 \
      ACHK_LABEL_TOKEN=msnap \
      ACHK_CHECKPOINT="$B/_m1_probe_checkpoint.jsonl" \
      ACHK_RESULTS_JSONL="$B/_m1_rows.jsonl" \
      python3 -u /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
        "$B/assumption_manifest.json" --declared "$B/_msnap_declared.json" \
        --json-out "$B/_m1_gate_results.json" --keep > "$LOG" 2>&1
say "M-SNAP GATE exit=$?"
if grep -qE '^RESULT:' "$LOG"; then
  say "VERDICT M1-GATE: OK (line present)"
  grep -E '^RESULT:|^  (PASS|FAIL|ERROR|NOT-)' "$LOG" | tee -a "$B/_m1.log"
  grep -E 'Maximum resident|Elapsed' "$B/_m1_gate.time" | tee -a "$B/_m1.log"
  say "M1-GATE-DONE"
else
  say "VERDICT M1-GATE: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
  tail -25 "$LOG" | sed 's/^/    /' | tee -a "$B/_m1.log"
  exit 10
fi
