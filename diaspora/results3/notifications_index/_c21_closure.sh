#!/bin/bash
# =============================================================================
# C21 CLOSURE RECORD — the RUNBOOK's closing stages, one detached checkpointed
# service per stage, each judged by its OWN verdict line.
#   usage: bash _c21_closure.sh <stage>       stage: 2 = engine section
#                                                    3 = c7 audits
# Ported from `_c12_rerun_after_restart.sh` stages 2 and 3 (which is where the
# env, the caps and the verdict greps come from); only the stamps changed.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
FROM="${1:?usage: _c21_closure.sh <2|3>}"
COV_OUT="${COV_OUT:-$B/_cov_C21_C21R1.json}"
AUDIT_TMO="${COMPLETION_AUDIT_TIMEOUT:-21600}"
L="$B/_c21_closure.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
verdict(){ if grep -qE "$3" "$2"; then say "VERDICT $1: OK (line present)"; return 0
           else say "VERDICT $1: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
                tail -25 "$2" | sed 's/^/    /' | tee -a "$L"; return 1; fi; }
. "$B/_wait_mem.sh"

if [ "$FROM" = 2 ]; then
  say "C21-2 ENGINE SECTION (audits + shims + note check + gate) -> coverage_summary.json"
  say "      SUMMARY_IN=$(basename "$COV_OUT")  audit timeout ${AUDIT_TMO}s each  cap 9G"
  [ -s "$COV_OUT" ] || { say "  *** $COV_OUT missing/empty ***"; exit 20; }
  while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "WAIT free<4G"; sleep 30; done
  # HARDENED HOLD (coordinator, 2026-09-13): match the script PATH, never a
  # bare job name, and drop every Claude Code wrapper shell (`shell-snapshots`
  # in argv) — a watcher polling for the job carries the job's name in its own
  # argv, so a bare-name hold is a LIVELOCK, not a wait. The hold NAMES the
  # blocker it is waiting on, so a livelock shows up in the log.
  _blockers(){ pgrep -a python3 2>/dev/null | grep -v shell-snapshots \
               | grep -E "posts_show/(coverage_report[.]py|_p31[_.a-z0-9]*[.]py)"; }
  while _blockers >/dev/null; do
    say "C21-2 HOLD: real posts_show blocker(s) -> $(_blockers | head -2 | cut -c1-140)"; sleep 60
  done
  while systemctl --user list-units --state=active --no-legend 'posts-p31-*' 2>/dev/null | grep -q .; do
    say "C21-2 HOLD: a posts-p31-* unit is active (P31 has priority)"; sleep 60
  done
  wait_mem 9216 "_c21/engine" | tee -a "$L"
  systemd-run --user --scope --slice=concolic-cov.slice \
    -p MemoryMax=9G -p MemorySwapMax=0 --quiet \
    choom -n 1000 -- /usr/bin/time -v -o "$B/_c21_eng.time" \
    env SUMMARY_IN="$COV_OUT" SUMMARY_OUT="$B/coverage_summary.json" \
        ENGINE_CHECKPOINT=1 COMPLETION_AUDIT_TIMEOUT="$AUDIT_TMO" \
        ACHK_CHECKPOINT="$B/_achk_probe_checkpoint.jsonl" \
        ACHK_RESULTS_JSONL="$B/_achk_rows.jsonl" \
        ACHK_INDEX_CHECKPOINT="$B/_c20_achk_index.jsonl" \
        ACHK_DERIVE_CHECKPOINT="$B/_c20_achk_derive.jsonl" \
        ACHK_HEARTBEAT_S=60 \
        CONCOLIC_SLOTS=1 CONCOLIC_PROBE_WORKERS=1 ACHK_PROBE_BATCH=20 \
        PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
        python3 -u "$B/_engine_section.py" > "$B/_c21_engine.log" 2>&1
  say "C21-2 exit=$?"
  verdict C21-2 "$B/_c21_engine.log" '^ENGINE SECTION DONE' || exit 21
  grep -E '^OVERALL_COMPLETE|^  (AUDIT|PASS|FAIL|PROTOCOL|NOTE-CHECK|ASSUMPTIONS|BLOCKING|CONFINEMENT|SHIM)' \
       "$B/_c21_engine.log" | tee -a "$L"
  grep -E 'Maximum resident|Elapsed' "$B/_c21_eng.time" | tee -a "$L"
  say "C21-CLOSURE-2-DONE"
fi

if [ "$FROM" = 3 ]; then
  say "C21-3 C7 AUDIT SUITE (AUDITS_CHECKPOINT=1, cap 3G)"
  while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "WAIT free<4G"; sleep 30; done
  wait_mem 3072 "_c21/audits" | tee -a "$L"
  systemd-run --user --scope --slice=concolic-cov.slice \
    -p MemoryMax=3G -p MemorySwapMax=0 --quiet \
    choom -n 1000 -- /usr/bin/time -v -o "$B/_c21_audits.time" \
    env AUDITS_CHECKPOINT=1 bash "$B/_c7_audits.sh" > "$B/_c21_audits.out" 2>&1
  say "C21-3 exit=$?"
  verdict C21-3 "$B/_c7_audits.log" '^=== c7 audits DONE' || exit 30
  grep -n 'EXIT=' "$B/_c7_audits.log" | tee -a "$L"
  say "  audits with a non-zero EXIT: $(grep -c 'EXIT=[^0]' "$B/_c7_audits.log")"
  grep -E 'Maximum resident' "$B/_c21_audits.time" | tee -a "$L"
  say "C21-CLOSURE-3-DONE"
fi
