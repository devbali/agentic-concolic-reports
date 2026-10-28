#!/bin/bash
# C27 CLOSURE (inner) — runs INSIDE the systemd unit so the whole stage,
# including its verdict tally, survives the launcher dying.
#   stage 2 = engine section      verdict ^ENGINE SECTION DONE
#   stage 3 = c7 audit suite      verdict ^=== c7 audits DONE
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
FROM="${1:?usage: _c27_closure_inner.sh <2|3>}"
COV_OUT="${COV_OUT:-$B/_cov_C26_C26R1.json}"
AUDIT_TMO="${COMPLETION_AUDIT_TIMEOUT:-21600}"
L="$B/_c27_closure.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
verdict(){ if grep -qE "$3" "$2"; then say "VERDICT $1: OK (line present)"; return 0
           else say "VERDICT $1: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
                tail -25 "$2" | sed 's/^/    /' | tee -a "$L"; return 1; fi; }

if [ "$FROM" = 2 ]; then
  say "C27-2 ENGINE SECTION (audits + shims + note check + gate) -> coverage_summary.json"
  say "      SUMMARY_IN=$(basename "$COV_OUT")  audit timeout ${AUDIT_TMO}s each  cap 9G"
  [ -s "$COV_OUT" ] || { say "  *** $COV_OUT missing/empty ***"; exit 20; }
  # The index checkpoint is the one the C27 §16g gate already paid for
  # (~2 h 20 over 310 k dumps after the 2026-09-14 assumption_checker re-merge).
  # `_canon_key` is identical for both runs (same 2 aliases, verified), so this
  # resumes INCREMENTALLY and only the dumps added since are re-indexed.
  /usr/bin/time -v -o "$B/_c27_eng.time" \
    env SUMMARY_IN="$COV_OUT" SUMMARY_OUT="$B/coverage_summary.json" \
        ENGINE_CHECKPOINT=1 COMPLETION_AUDIT_TIMEOUT="$AUDIT_TMO" \
        ACHK_CHECKPOINT="$B/_achk_probe_checkpoint.jsonl" \
        ACHK_RESULTS_JSONL="$B/_achk_rows.jsonl" \
        ACHK_INDEX_CHECKPOINT="$B/_achk_index.ckpt.jsonl" \
        ACHK_DERIVE_CHECKPOINT="$B/_c27_achk_derive_engine.ckpt.jsonl" \
        ACHK_HEARTBEAT_S=60 \
        CONCOLIC_SLOTS=1 CONCOLIC_PROBE_WORKERS=1 ACHK_PROBE_BATCH=20 \
        PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
        python3 -u "$B/_engine_section.py" > "$B/_c27_engine.log" 2>&1
  say "C27-2 exit=$?"
  verdict C27-2 "$B/_c27_engine.log" '^ENGINE SECTION DONE' || exit 21
  grep -E '^OVERALL_COMPLETE|^  (AUDIT|PASS|FAIL|PROTOCOL|NOTE-CHECK|ASSUMPTIONS|BLOCKING|CONFINEMENT|SHIM)' \
       "$B/_c27_engine.log" | tee -a "$L"
  grep -E 'Maximum resident|Elapsed' "$B/_c27_eng.time" | tee -a "$L"
  say "C27-CLOSURE-2-DONE"
fi

if [ "$FROM" = 3 ]; then
  say "C27-3 C7 AUDIT SUITE (AUDITS_CHECKPOINT=1, cap 3G)"
  /usr/bin/time -v -o "$B/_c27_audits.time" \
    env AUDITS_CHECKPOINT=1 bash "$B/_c7_audits.sh" > "$B/_c27_audits.out" 2>&1
  say "C27-3 exit=$?"
  verdict C27-3 "$B/_c7_audits.log" '^=== c7 audits DONE' || exit 30
  grep -n 'EXIT=' "$B/_c7_audits.log" | tee -a "$L"
  say "  audits with a non-zero EXIT: $(grep -c 'EXIT=[^0]' "$B/_c7_audits.log")"
  grep -E 'Maximum resident' "$B/_c27_audits.time" | tee -a "$L"
  say "C27-CLOSURE-3-DONE"
fi
