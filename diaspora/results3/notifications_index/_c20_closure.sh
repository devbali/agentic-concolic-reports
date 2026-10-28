#!/bin/bash
# =============================================================================
# C20 CLOSURE RECORD — the RUNBOOK's closing stages, one detached checkpointed
# service per stage, each judged by its OWN verdict line.
#   usage: bash _c20_closure.sh <stage>       stage: 2 = engine section
#                                                    3 = c7 audits
# Ported from `_c12_rerun_after_restart.sh` stages 2 and 3 (which is where the
# env, the caps and the verdict greps come from); only the stamps changed.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
FROM="${1:?usage: _c20_closure.sh <2|3>}"
COV_OUT="${COV_OUT:-$B/_cov_C20_C20R1.json}"
AUDIT_TMO="${COMPLETION_AUDIT_TIMEOUT:-21600}"
L="$B/_c20_closure.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
verdict(){ if grep -qE "$3" "$2"; then say "VERDICT $1: OK (line present)"; return 0
           else say "VERDICT $1: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
                tail -25 "$2" | sed 's/^/    /' | tee -a "$L"; return 1; fi; }
. "$B/_wait_mem.sh"

if [ "$FROM" = 2 ]; then
  say "C20-2 ENGINE SECTION (audits + shims + note check + gate) -> coverage_summary.json"
  say "      SUMMARY_IN=$(basename "$COV_OUT")  audit timeout ${AUDIT_TMO}s each  cap 9G"
  [ -s "$COV_OUT" ] || { say "  *** $COV_OUT missing/empty ***"; exit 20; }
  while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "WAIT free<4G"; sleep 30; done
  wait_mem 9216 "_c20/engine" | tee -a "$L"
  systemd-run --user --scope --slice=concolic-cov.slice \
    -p MemoryMax=9G -p MemorySwapMax=0 --quiet \
    choom -n 1000 -- /usr/bin/time -v -o "$B/_c20_eng.time" \
    env SUMMARY_IN="$COV_OUT" SUMMARY_OUT="$B/coverage_summary.json" \
        ENGINE_CHECKPOINT=1 COMPLETION_AUDIT_TIMEOUT="$AUDIT_TMO" \
        ACHK_CHECKPOINT="$B/_achk_probe_checkpoint.jsonl" \
        ACHK_RESULTS_JSONL="$B/_achk_rows.jsonl" \
        ACHK_INDEX_CHECKPOINT="$B/_c20_achk_index.jsonl" \
        ACHK_DERIVE_CHECKPOINT="$B/_c20_achk_derive.jsonl" \
        ACHK_HEARTBEAT_S=60 \
        CONCOLIC_SLOTS=1 CONCOLIC_PROBE_WORKERS=1 ACHK_PROBE_BATCH=20 \
        PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
        python3 -u "$B/_engine_section.py" > "$B/_c20_engine.log" 2>&1
  say "C20-2 exit=$?"
  verdict C20-2 "$B/_c20_engine.log" '^ENGINE SECTION DONE' || exit 21
  grep -E '^OVERALL_COMPLETE|^  (AUDIT|PASS|FAIL|PROTOCOL|NOTE-CHECK|ASSUMPTIONS|BLOCKING|CONFINEMENT|SHIM)' \
       "$B/_c20_engine.log" | tee -a "$L"
  grep -E 'Maximum resident|Elapsed' "$B/_c20_eng.time" | tee -a "$L"
  say "C20-CLOSURE-2-DONE"
fi

if [ "$FROM" = 3 ]; then
  say "C20-3 C7 AUDIT SUITE (AUDITS_CHECKPOINT=1, cap 6G after the 3G kill)"
  while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "WAIT free<4G"; sleep 30; done
  wait_mem 6144 "_c20/audits" | tee -a "$L"
  systemd-run --user --scope --slice=concolic-cov.slice \
    -p MemoryMax=6G -p MemorySwapMax=0 --quiet \
    choom -n 1000 -- /usr/bin/time -v -o "$B/_c20_audits.time" \
    env AUDITS_CHECKPOINT=1 bash "$B/_c7_audits.sh" > "$B/_c20_audits.out" 2>&1
  say "C20-3 exit=$?"
  verdict C20-3 "$B/_c7_audits.log" '^=== c7 audits DONE' || exit 30
  grep -n 'EXIT=' "$B/_c7_audits.log" | tee -a "$L"
  say "  audits with a non-zero EXIT: $(grep -c 'EXIT=[^0]' "$B/_c7_audits.log")"
  grep -E 'Maximum resident' "$B/_c20_audits.time" | tee -a "$L"
  say "C20-CLOSURE-3-DONE"
fi
