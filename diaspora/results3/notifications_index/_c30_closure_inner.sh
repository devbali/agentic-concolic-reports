#!/bin/bash
# =============================================================================
# C30 CLOSURE (inner) — runs INSIDE the systemd unit so the whole stage,
# including its verdict tally, survives the launcher dying.
#
#   stage 2 = engine section      verdict ^ENGINE SECTION DONE
#   stage 3 = c7 audit suite      verdict ^=== c7 audits DONE
#
# COPY of `_c27_closure_inner.sh` (§29.9's rule: copy, never edit a script a
# previous round is judged by). Four differences, each stated:
#
#  1. COV_OUT is REQUIRED, not defaulted. C27 defaulted it to
#     `_cov_C26_C26R1.json` — a summary that has since been WITHDRAWN (§39.6).
#     A closure that silently reads a withdrawn summary is the worst failure
#     mode available here, so an unset COV_OUT is now a hard exit.
#
#  2. CONCOLIC_PROBE_WORKERS=14 (was 1) and ACHK_PROBE_BATCH=40 (was 20).
#     The "1 worker" setting was a consequence of a 4-core box with a 4-32 G
#     cage; the box is 16 cores / 68 G with a 56 G cage and sole tenancy.
#     14 = min(floor(cores-1.5), floor((cage-20G)/1.3G)).
#
#  3. ACHK_BASES=8 is set EXPLICITLY. It is already the checker's default
#     (`assumption_checker.py:1431`), but the multi-base gate (§17/X12) is the
#     thing this closure's evidence grade rests on, so it is written on the
#     launch line rather than inherited, and it appears in the log.
#
#  4. A FRESH derive checkpoint, `_c30_achk_derive_engine.ckpt.jsonl`.
#     `ACHK_DERIVE_CHECKPOINT` records PROFILE REPRESENTATIVES keyed by
#     `digest(canon(expr), footprint, enabling, ACHK_CONF_PROFILES)` —
#     the corpus is NOT in that key (`assumption_checker.py:1735-1740`).
#     Replaying a derive log built on a smaller corpus would therefore hand
#     the probe the OLD bases and silently exclude every dump added since,
#     which is exactly the evidence the multi-base grade is counting. The
#     INDEX checkpoint (`_achk_index.ckpt.jsonl`) is reused as C27 did —
#     that one is per-dump and genuinely incremental.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
FROM="${1:?usage: _c30_closure_inner.sh <2|3>}"
AUDIT_TMO="${COMPLETION_AUDIT_TIMEOUT:-21600}"
L="$B/_c30_closure.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
verdict(){ if grep -qE "$3" "$2"; then say "VERDICT $1: OK (line present)"; return 0
           else say "VERDICT $1: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
                tail -25 "$2" | sed 's/^/    /' | tee -a "$L"; return 1; fi; }

if [ "$FROM" = 2 ]; then
  [ -n "$COV_OUT" ] || { say "*** COV_OUT is UNSET — refusing to guess a coverage summary ***"; exit 19; }
  [ -s "$COV_OUT" ] || { say "  *** $COV_OUT missing/empty ***"; exit 20; }
  say "C30-2 ENGINE SECTION (audits + shims + note check + gate) -> coverage_summary.json"
  say "      SUMMARY_IN=$(basename "$COV_OUT")  audit timeout ${AUDIT_TMO}s each  cap ${CAP:-24G}"
  say "      ACHK_BASES=8  CONCOLIC_PROBE_WORKERS=14  ACHK_PROBE_BATCH=40  ACHK_HEARTBEAT_S=60"
  say "      derive ckpt: _c30_achk_derive_engine.ckpt.jsonl (FRESH — corpus is not in its key)"
  say "      index  ckpt: _achk_index.ckpt.jsonl (REUSED — per-dump, incremental)"
  say "      input summary md5 $(md5sum "$COV_OUT" | cut -d' ' -f1)"
  /usr/bin/time -v -o "$B/_c30_eng.time" \
    env SUMMARY_IN="$COV_OUT" SUMMARY_OUT="$B/coverage_summary.json" \
        ENGINE_CHECKPOINT=1 COMPLETION_AUDIT_TIMEOUT="$AUDIT_TMO" \
        ACHK_CHECKPOINT="$B/_achk_probe_checkpoint.jsonl" \
        ACHK_RESULTS_JSONL="$B/_achk_rows.jsonl" \
        ACHK_INDEX_CHECKPOINT="$B/_achk_index.ckpt.jsonl" \
        ACHK_DERIVE_CHECKPOINT="$B/_c30_achk_derive_engine.ckpt.jsonl" \
        ACHK_HEARTBEAT_S=60 \
        ACHK_BASES=8 \
        CONCOLIC_SLOTS=14 CONCOLIC_PROBE_WORKERS=14 ACHK_PROBE_BATCH=40 \
        PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
        python3 -u "$B/_engine_section.py" > "$B/_c30_engine.log" 2>&1
  say "C30-2 exit=$?"
  verdict C30-2 "$B/_c30_engine.log" '^ENGINE SECTION DONE' || exit 21
  grep -E '^OVERALL_COMPLETE|^  (AUDIT|PASS|FAIL|PROTOCOL|NOTE-CHECK|ASSUMPTIONS|BLOCKING|CONFINEMENT|SHIM)' \
       "$B/_c30_engine.log" | tee -a "$L"
  grep -E 'Maximum resident|Elapsed' "$B/_c30_eng.time" | tee -a "$L"
  say "C30-CLOSURE-2-DONE"
fi

if [ "$FROM" = 3 ]; then
  say "C30-3 C7 AUDIT SUITE (AUDITS_CHECKPOINT=1)"
  /usr/bin/time -v -o "$B/_c30_audits.time" \
    env AUDITS_CHECKPOINT=1 bash "$B/_c7_audits.sh" > "$B/_c30_audits.out" 2>&1
  say "C30-3 exit=$?"
  verdict C30-3 "$B/_c7_audits.log" '^=== c7 audits DONE' || exit 30
  grep -n 'EXIT=' "$B/_c7_audits.log" | tee -a "$L"
  say "  audits with a non-zero EXIT: $(grep -c 'EXIT=[^0]' "$B/_c7_audits.log")"
  grep -E 'Maximum resident' "$B/_c30_audits.time" | tee -a "$L"
  say "C30-CLOSURE-3-DONE"
fi
