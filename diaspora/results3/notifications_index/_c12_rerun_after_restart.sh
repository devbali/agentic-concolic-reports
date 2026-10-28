#!/bin/bash
# =============================================================================
# C12 — THE NOTIFICATIONS_INDEX FINAL PASS, RERUN AFTER THE 2026-09-12 RESTART
#
# WHY THERE IS A C12. The C11 full pass (`_c11_pass_full.sh`, launched
# 2026-09-11 21:45, log `_c11_cov_full1.log`) COMPLETED its coverage phase —
# 114 610 runs, 8 962 s, peak RSS 4.75 GB, "[coverage] phase done" — and then
# DIED in the completion phase at 01:30:12 with
#
#     subprocess.TimeoutExpired: ... cardinality_consistency_audit.py ...
#     timed out after 1800 seconds
#         concolic_engine/completion.py:197  (run_audits, hard-coded timeout)
#
# `coverage_report.py` wrote `coverage_summary.json` only AFTER
# `attach_to_summary`, so NOTHING was written and 2 h 30 of coverage was lost.
# The audits scan the batch DIRECTORY (289 733 dumps), not the pass's
# DUMP_LIST (114 610 runs), which is why 1800 s was not enough.
#
# WHAT IS DIFFERENT HERE (all of it is why this must not happen again):
#   * the pass is SPLIT — coverage only (SKIP_COMPLETION=1 + SUMMARY_OUT), then
#     the gate as its own stage (`_engine_section.py`). A gate failure can no
#     longer take the coverage numbers with it;
#   * every stage is CHECKPOINTED (RUNBOOK §4): COVERAGE_CHECKPOINT,
#     ENGINE_CHECKPOINT (+ ACHK_CHECKPOINT / ACHK_RESULTS_JSONL inside it),
#     AUDITS_CHECKPOINT. A kill costs the unit in flight and nothing else, so
#     re-running THIS SCRIPT resumes instead of restarting;
#   * the audit timeout is configurable now and raised here
#     (COMPLETION_AUDIT_TIMEOUT), and a timeout is a RED audit, not a crash;
#   * `coverage_report.py` also catches a raising gate and still writes its
#     summary (backstop; the split is the real fix).
#
# NO EXTRACTION STAGE. Owner rule: policies are extracted at CLOSURE only.
#
# RUN IT AS:   bash _c12_rerun_after_restart.sh            # all three stages
#              bash _c12_rerun_after_restart.sh 2          # from stage 2 on
# Re-running after a kill is SAFE and is the intended recovery.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
FROM="${1:-1}"
STAMP=20260912
L="$B/_c12.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
# Rule 3 (RUNBOOK): a stage is judged by its OWN verdict line in its OWN log,
# never by an exit code or a marker written by the wrapper that can be killed.
verdict(){ # <label> <log> <regex>
  if grep -qE "$3" "$2" 2>/dev/null; then say "VERDICT $1: OK (line present)"; return 0
  else say "VERDICT $1: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
       tail -25 "$2" 2>/dev/null | sed 's/^/    /' | tee -a "$L"; return 1; fi
}

# ---------------------------------------------------------------- preflight --
say "C12 preflight"
# EXACT string compare per unit. `case "$act" in *active*)` — which is what
# this was until 2026-09-12 03:35 — ALSO MATCHES "inactive", so the check
# refused for ever and this script could never run at all (caught by
# dry-running posts_show/_p14_rerun_after_restart.sh, its port, against two
# non-existent units). `activating`/`reloading`/`deactivating` count as running.
_running=0
for u in notif-finish-20260911.service posts-finish-20260911.service; do
  st=$(systemctl --user is-active "$u" 2>/dev/null | head -1)
  say "  2026-09-11 chain $u: ${st:-unknown}   (must be inactive/failed)"
  case "$st" in active|activating|reloading|deactivating) _running=1;; esac
done
# STAGE1_ONLY=1 (2026-09-12 06:20, owner decided NOT to restart): run only the
# coverage layer now, beside posts_show's still-running chain. Stage 1 needs
# nothing from the staged apply list (live coverage.py already carries
# COVERAGE_CHECKPOINT), so both refusals below are downgraded to warnings and
# the script stops after stage 1. Stages 2-3 run later with the list applied.
if [ "${STAGE1_ONLY:-0}" = 1 ]; then
  say "  STAGE1_ONLY=1: preflight refusals downgraded to warnings; stopping after C12-1"
  [ "$_running" = 1 ] && say "  WARN: a 2026-09-11 chain is still running (posts_show) — allowed for stage 1"
else
[ "$_running" = 1 ] && { say "  *** a 2026-09-11 chain is STILL RUNNING — stop here ***"; exit 3; }
if ! grep -q '_audit_timeout' /home/dev/project/src/concolic_engine/completion.py; then
  say "  *** src/concolic_engine/completion.py has NOT been updated: the staged"
  say "      patch in results3/_CHECKPOINT_STAGED_20260912.md is not applied."
  say "      Apply the whole list (it also lands ENGINE/ACHK/AUDITS checkpoints),"
  say "      run 'cd src && python3 -m pytest -q --ignore=queries_from_runs' (237),"
  say "      then re-run this script. ***"; exit 4
fi
for f in _c7_audits.sh:AUDITS_CHECKPOINT; do
  p="${f%%:*}"; k="${f##*:}"
  grep -q "$k" "$B/$p" || { say "  *** $p lacks $k — apply list not applied ***"; exit 4; }
done
fi   # STAGE1_ONLY
say "  engine coverage.py   md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py   | cut -d' ' -f1)"
say "  engine completion.py md5 $(md5sum /home/dev/project/src/concolic_engine/completion.py | cut -d' ' -f1)"
LIST="$B/_snapshot_pruned_20260911_143539.txt"
say "  DUMP_LIST  $(wc -l < "$LIST") runs   (the C11 corpus, unchanged — same record)"
say "  batch dir  $(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l) dumps  (what the AUDITS scan)"
. "$B/_wait_mem.sh"

COV_OUT="$B/_cov_FINAL_C12_${STAMP}.json"
COV_CKPT="$B/_cov_c12.ckpt.jsonl"
# Per-audit wall clock for the gate's own audits. MEASURED 2026-09-12 on
# conversations_index (18 623 dumps / 2.53 GB) and scaled by BYTES to this
# directory (289 733 dumps / 39.19 GB):
#     empty_relation_emission   98 s ->  ~25 min
#     cardinality_consistency  228 s ->  ~59 min   <- the one that was killed
#     noteless_call             59 s ->  ~15 min
# which reproduces the C11 numbers (2 712 s for the four audits before the
# kill, then 1 800 s of a job that needed ~3 550 s). 6 h is a guard rail with
# room for a bigger corpus, not a schedule — and it is no longer fatal.
AUDIT_TMO="${COMPLETION_AUDIT_TIMEOUT:-21600}"

# ------------------------------------------------- stage 1: COVERAGE LAYER --
if [ "$FROM" -le 1 ]; then
  say "C12-1 COVERAGE LAYER (SKIP_COMPLETION=1, checkpointed) -> $COV_OUT"
  say "      expect ~2 h 30 fresh (C11: 8 962 s, peak RSS 4.75 GB); a resumed"
  say "      run skips every demand set already in $(basename "$COV_CKPT")"
  wait_mem 8192 "_c12/coverage" | tee -a "$L"
  systemd-run --user --scope --slice=concolic-cov.slice \
    -p MemoryMax=8G -p MemorySwapMax=0 --quiet \
    choom -n 1000 -- /usr/bin/time -v -o "$B/_c12_cov.time" \
    env DUMP_LIST="$LIST" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
        SKIP_COMPLETION=1 SUMMARY_OUT="$COV_OUT" \
        COVERAGE_CHECKPOINT="$COV_CKPT" \
        MISSING_CAP=40000 \
        python3 -u "$B/coverage_report.py" > "$B/_c12_cov.log" 2>&1
  say "C12-1 exit=$?"
  verdict C12-1 "$B/_c12_cov.log" '^COMPLETE=' || exit 10
  grep -E '^\[assumptions\]|^\[confinement\]|^\[checkpoint\]|^(COMPLETE|GENUINE|dump_errors|wrote)' \
       "$B/_c12_cov.log" | tee -a "$L"
  grep -E 'Maximum resident|Elapsed' "$B/_c12_cov.time" | tee -a "$L"
  [ "${STAGE1_ONLY:-0}" = 1 ] && { say "STAGE1_ONLY: C12-1 done; run 'bash $0 2' after the apply list lands"; exit 0; }
fi

# -------------------------------------------------- stage 2: ENGINE SECTION --
if [ "$FROM" -le 2 ]; then
  say "C12-2 ENGINE SECTION (audits + shims + note check + gate) -> coverage_summary.json"
  say "      audit timeout ${AUDIT_TMO}s each; ENGINE_CHECKPOINT=1 (whole-stage"
  say "      skip on matching inputs, per-probe resume inside the gate)"
  say "      expect ~1 h 45 of audits (25 + 59 + 15 min for the three big ones)"
  say "      + the gate's NEW declarations only"
  say "      (_c11_gate_reuse.py reuses the 2026-09-11 class-level rows)"
  [ -s "$COV_OUT" ] || { say "  *** $COV_OUT missing/empty — stage 1 did not deliver ***"; exit 20; }
  wait_mem 9216 "_c12/engine" | tee -a "$L"
  systemd-run --user --scope --slice=concolic-cov.slice \
    -p MemoryMax=9G -p MemorySwapMax=0 --quiet \
    choom -n 1000 -- /usr/bin/time -v -o "$B/_c12_eng.time" \
    env SUMMARY_IN="$COV_OUT" SUMMARY_OUT="$B/coverage_summary.json" \
        ENGINE_CHECKPOINT=1 COMPLETION_AUDIT_TIMEOUT="$AUDIT_TMO" \
        ACHK_CHECKPOINT="$B/_achk_probe_checkpoint.jsonl" \
        ACHK_RESULTS_JSONL="$B/_achk_rows.jsonl" \
        CONCOLIC_SLOTS=1 CONCOLIC_PROBE_WORKERS=1 ACHK_PROBE_BATCH=20 \
        PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
        python3 -u "$B/_engine_section.py" > "$B/_c12_engine.log" 2>&1
  say "C12-2 exit=$?"
  verdict C12-2 "$B/_c12_engine.log" '^ENGINE SECTION DONE' || exit 21
  grep -E '^OVERALL_COMPLETE|^  (AUDIT|PASS|FAIL|PROTOCOL|NOTE-CHECK|ASSUMPTIONS|BLOCKING|CONFINEMENT)' \
       "$B/_c12_engine.log" | tee -a "$L"
  grep -E 'Maximum resident|Elapsed' "$B/_c12_eng.time" | tee -a "$L"
fi

# ------------------------------------------------------- stage 3: C7 AUDITS --
if [ "$FROM" -le 3 ]; then
  say "C12-3 C7 AUDIT SUITE (AUDITS_CHECKPOINT=1)"
  say "      NOTE: five of these (format_coverage, note_fidelity, empty_relation,"
  say "      noteless_call, cardinality_consistency) are ALSO in the gate's"
  say "      extra_audit_cmds, so C12-2 has just paid for them once. The C7 run"
  say "      is the suite of record; its checkpoint dir makes a retry cheap."
  wait_mem 2500 "_c12/audits" | tee -a "$L"
  systemd-run --user --scope --slice=concolic-cov.slice \
    -p MemoryMax=2500M -p MemorySwapMax=0 --quiet \
    choom -n 1000 -- /usr/bin/time -v -o "$B/_c12_audits.time" \
    env AUDITS_CHECKPOINT=1 bash "$B/_c7_audits.sh" > "$B/_c12_audits.out" 2>&1
  # `bash <script>`, not the script directly: the apply list lands _c7_audits.sh
  # with `mv`, which keeps the staged file's 0644 and would make an exec fail.
  say "C12-3 exit=$?"
  verdict C12-3 "$B/_c7_audits.log" '^=== c7 audits DONE' || exit 30
  grep -n 'EXIT=' "$B/_c7_audits.log" | tee -a "$L"
  nz=$(grep -c 'EXIT=[^0]' "$B/_c7_audits.log"); say "  audits with a non-zero EXIT: $nz"
  grep -E 'Maximum resident' "$B/_c12_audits.time" | tee -a "$L"
fi

say "C12 done — read $B/_c12.log, then coverage_summary.json's completion section."
say "NO extraction ran (owner rule: policies are extracted at closure only)."
