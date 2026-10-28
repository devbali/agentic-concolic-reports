#!/bin/bash
# =============================================================================
# P14 — THE POSTS_SHOW FINAL PASS, RERUN AFTER THE 2026-09-12 RESTART
#
# WHY THERE IS A P14. The 2026-09-11 final pass
# (`posts-finish-20260911.service` -> `_night13c.sh` -> `_p13c.sh` stage 13c-1,
# log `_covFINAL_OD0911.log`) was launched 21:45 on DUMP_LIST
# `_snapshot_pruned_OD0911.txt` (32 305 runs) with SKIP_COMPLETION=1 and
# MAX_MISSING_PER_CLIQUE=16. It finished loading at 21:55 and then ran
# **more than 5 h 45 m inside the checker WITHOUT WRITING A SINGLE BYTE**:
# `COVERAGE_CHECKPOINT` did not exist when it launched, so its whole result
# lived in RAM. It was also starved — box load 32 on 4 cores, ~0.6 core for the
# pass — and it was raised live from its scripted 3 G cap because it sat at
# exactly 3.0 G anon (RSS 3 152 792 kB at 03:30). It is expected to be KILLED
# by the restart, and everything it computed is lost. THIS script is the rerun,
# and it is checkpointed at every stage so that never happens again.
#
# WHAT IS DIFFERENT FROM `_p13c.sh` (each line is a defect it repairs):
#   * COVERAGE_CHECKPOINT on the coverage layer — a kill costs the demand set
#     in flight and nothing else; a rerun of THIS script resumes;
#   * ENGINE_CHECKPOINT (+ ACHK_CHECKPOINT / ACHK_RESULTS_JSONL inside it) on
#     the engine section, AUDITS_CHECKPOINT on the audit suite;
#   * COMPLETION_AUDIT_TIMEOUT=21600 — `completion.py` hard-coded 1800 s and a
#     TimeoutExpired escaped `attach_to_summary`; that is what destroyed
#     notifications_index's 8 962 s coverage phase on 2026-09-11. posts_show's
#     `empty_relation_emission` is ~23 min against a 36.07 GB / 183 351-dump
#     directory — under the old wall, but with only ~20 % of margin;
#   * REAL memory caps. 13c-1 was scripted at 3 G and needed more; 13c-2 was
#     scripted at 3 G while the handoff measured the engine section at ~7 G
#     (`_RESTART_HANDOFF_20260911.md` §2). Here: 7 G and 8 G.
#   * the split is kept (coverage layer, then the gate as its own stage), which
#     is the thing `_p13c.sh` already got right.
#
# NO EXTRACTION STAGE, AND THERE MUST NOT BE ONE. Owner rule: policies are
# extracted at CLOSURE only, and posts_show is NOT complete.
#
# RUN IT AS:   bash _p14_rerun_after_restart.sh          # all three stages
#              bash _p14_rerun_after_restart.sh 2        # from stage 2 on
# Re-running after a kill is SAFE and is the intended recovery.
#
# EXIT CODES: 2 batch dir missing · 3 a 2026-09-11 chain is still running ·
#             4 the staged apply list has not landed · 5 the cgroup cage was
#             not re-established after the reboot · 10/20/21/30 a stage that
#             did not produce its own verdict line.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"                 # cage / caged_verdict / wait_free6 / wait_alone
FROM="${1:-1}"
STAMP=20260912
L="$B/_p14.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
# Rule 3 (RUNBOOK §4): a stage is judged by its OWN verdict line in its OWN
# log, never by an exit code and never by a marker written by the wrapper —
# the wrapper is exactly the part that gets killed.
verdict(){ # <label> <unit> <log> <regex>
  if grep -qE "$4" "$3" 2>/dev/null; then say "VERDICT $1: OK (verdict line present)"; return 0
  else say "VERDICT $1: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
       caged_verdict "$2" "$3" "$4" | tee -a "$L"
       tail -25 "$3" 2>/dev/null | sed 's/^/    /' | tee -a "$L"; return 1; fi
}

# ---------------------------------------------------------------- preflight --
say "P14 preflight"
# EXACT string compare per unit, never `case $all in *active*)` — "inactive"
# CONTAINS "active", so the glob form refuses for ever and the script could
# never run at all. (notifications_index/_c12_rerun_after_restart.sh has that
# form; caught here 2026-09-12 by dry-running this preflight against two
# non-existent units.) `activating`/`reloading` count as running too.
_running=0
for u in posts-finish-20260911.service notif-finish-20260911.service; do
  st=$(systemctl --user is-active "$u" 2>/dev/null | head -1)
  say "  2026-09-11 chain $u: ${st:-unknown}"
  case "$st" in active|activating|reloading|deactivating) _running=1;; esac
done
# STAGE1_ONLY=1 (2026-09-12 08:00, owner did not restart; §16d engine landed):
# run ONLY the coverage layer now, on the new one-query-per-set engine, BESIDE
# the still-running 2026-09-11 pass (old engine in memory). Own output/ckpt
# files, so nothing races. Stage 1 needs nothing from the apply list.
if [ "${STAGE1_ONLY:-0}" = 1 ]; then
  say "  STAGE1_ONLY=1: preflight refusals downgraded to warnings; stopping after P14-1"
  [ "$_running" = 1 ] && say "  WARN: a 2026-09-11 chain is still running — allowed for stage 1"
elif [ "$_running" = 1 ]; then
  say "  *** a 2026-09-11 chain is STILL RUNNING — stop here. This script"
  say "      would put a second full pass on the box and would race the"
  say "      chain's own 13c-2/13c-3 for coverage_summary.json. ***"; exit 3
fi

# --- the staged apply list (results3/_CHECKPOINT_STAGED_20260912.md) ---------
# Every stage below sets a checkpoint variable that does NOTHING until these
# land. Refuse rather than run a five-figure-second job with its checkpoint
# silently inert.
if [ "${STAGE1_ONLY:-0}" = 1 ]; then :; elif ! grep -q '_audit_timeout' /home/dev/project/src/concolic_engine/completion.py; then
  say "  *** src/concolic_engine/completion.py has NOT been updated: the staged"
  say "      patch in results3/_CHECKPOINT_STAGED_20260912.md is not applied."
  say "      Apply the WHOLE list (it also lands ENGINE/ACHK/AUDITS checkpoints"
  say "      and posts_show/completion_config.json's audit_timeout), then run"
  say "      'cd /home/dev/project/src && python3 -m pytest -q --ignore=queries_from_runs'"
  say "      (237 expected), then re-run this script. ***"; exit 4
fi
for f in _engine_section.py:ENGINE_CHECKPOINT _c7_audits.sh:AUDITS_CHECKPOINT; do
  p="${f%%:*}"; k="${f##*:}"
  [ "${STAGE1_ONLY:-0}" = 1 ] && break
  grep -q "$k" "$B/$p" || { say "  *** $p lacks $k — the apply list is not applied ***"; exit 4; }
done
# NOT fatal: `audit_timeout` in completion_config.json is the standing default
# for a HAND invocation of the gate. P14-2 below passes
# COMPLETION_AUDIT_TIMEOUT explicitly, and the env var BEATS the config key
# (completion.py `_audit_timeout`: audit's own key > env > config > 1800), so a
# missing config key cannot make this script use 1800 s.
if grep -q 'audit_timeout' "$B/completion_config.json"; then
  say "  completion_config.json carries audit_timeout (standing default): ok"
else
  say "  WARN completion_config.json has no audit_timeout — it is staged as"
  say "       completion_config.json.checkpoint_next and is in the apply list."
  say "       NOT fatal here: P14-2 passes COMPLETION_AUDIT_TIMEOUT, which wins"
  say "       over the config key. Apply it so a HAND-run gate is safe too."
fi

# --- the cgroup cage does NOT survive a reboot (handoff §4) ------------------
mx=$(systemctl --user show concolic-cov.slice -p MemoryMax --value 2>/dev/null)
case "$mx" in ''|infinity|*[!0-9]*) mx=0;; esac
say "  concolic-cov.slice MemoryMax=$(awk -v m="$mx" 'BEGIN{printf "%.1fG", m/1073741824}')  MemoryCurrent=$(awk -v c="$(systemctl --user show concolic-cov.slice -p MemoryCurrent --value)" 'BEGIN{printf "%.1fG", c/1073741824}')"
if [ "$mx" -lt 9663676416 ]; then     # 9 GiB: stage 2 asks the cage for 8 G
  say "  *** the cage was not re-established after the reboot (need >= 9G so the"
  say "      8G engine stage can pass gate_launch). Run, per _RESTART_HANDOFF"
  say "      _20260911.md §4, sized to THIS box's RAM:"
  say "        systemctl --user set-property concolic-cov.slice MemoryMax=19G MemoryHigh=18G"
  say "      then re-run. (Without this, cage()'s gate_launch would poll for ever.) ***"
  exit 5
fi

say "  engine coverage.py   md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py   | cut -d' ' -f1)"
say "  engine completion.py md5 $(md5sum /home/dev/project/src/concolic_engine/completion.py | cut -d' ' -f1)"
say "  batch coverage_report.py md5 $(md5sum "$B/coverage_report.py" | cut -d' ' -f1)"
say "  batch _engine_section.py md5 $(md5sum "$B/_engine_section.py" | cut -d' ' -f1)"

# --- the 13c invariants: SAME corpus, same knobs, only the output is redated -
LIST="$B/_snapshot_pruned_OD0911.txt"          # IDENTICAL to 13c-1's DUMP_LIST
[ -s "$LIST" ] || { say "  *** DUMP_LIST $LIST missing/empty ***"; exit 4; }
NL=$(wc -l < "$LIST")
say "  DUMP_LIST  $LIST"
say "             $NL runs   (13c-1 ran on 32305 — a different number means a"
say "             DIFFERENT corpus and the checkpoint key will refuse to reuse"
say "             anything, which is correct, not a bug)"
say "  batch dir  $(wc -l < "$B/_all_dumps_OD0911.txt") dumps recorded 2026-09-11 21:45; live count $(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)"
say "             (the AUDITS scan the DIRECTORY, not the DUMP_LIST — that is"
say "              why the audit wall clock is sized off this number)"
say "  invariants vs _p13c.sh 13c-1: DUMP_LIST identical · SKIP_COMPLETION=1 ·"
say "             MAX_MISSING_PER_CLIQUE=16 · SUMMARY_OUT redated to this rerun"
say "             (_cov_FINAL_OD0911.json -> _cov_FINAL_P14_${STAMP}.json), so"
say "             the killed pass's name is never overwritten by a partial one"

COV_OUT="$B/_cov_FINAL_P14_${STAMP}.json"
COV_CKPT="$B/_cov_p14.ckpt.jsonl"
# Per-audit wall clock for the GATE's own audits (posts_show's
# extra_audit_cmds: note_fidelity, empty_relation_emission). MEASURED
# 2026-09-12 on conversations_index (18 623 dumps / 2.53 GB) and scaled by
# BYTES to this directory (183 351 dumps / 36.07 GB): empty_relation_emission
# 98 s -> ~23 min. 6 h is a guard rail with room for a bigger corpus, not a
# schedule — and since the staged completion.py a timeout is a RED audit row,
# not an exception that eats the stage.
AUDIT_TMO="${COMPLETION_AUDIT_TIMEOUT:-21600}"
say "  audit timeout ${AUDIT_TMO}s   coverage checkpoint $(basename "$COV_CKPT")"
say "  serialisation: wait_free6 + wait_alone before every stage (ALONE_OVERRIDE=${ALONE_OVERRIDE:-0})."
say "                 With ALONE_OVERRIDE unset this queues behind notifications'"
say "                 _c12 pass, which is the one-heavy-job rule; set it to 1"
say "                 only if the post-restart box is big enough for both."
[ -s "$COV_CKPT" ] && say "  RESUMING: $(wc -l < "$COV_CKPT") demand-set record(s) already in the checkpoint"

# ------------------------------------------------- stage 1: COVERAGE LAYER --
if [ "$FROM" -le 1 ]; then
  say "P14-1 COVERAGE LAYER (SKIP_COMPLETION=1, CHECKPOINTED) -> $COV_OUT"
  say "      cap 7G. The 2026-09-11 pass was scripted at 3G, sat at exactly"
  say "      3.0G anon and had to be raised LIVE; 7G is that number with room"
  say "      for the checker phase it never got to print."
  say "      EXPECT: 6-14 h fresh. Basis: the two comparable FULL passes on"
  say "      this endpoint were 13 293 s (3 h 42) and 14 284 s (3 h 58) at"
  say "      ~14.8k dumps / 543-553 declared assumptions; this one is 32 305"
  say "      dumps / 1 123 declared + 8 overnight pins (2.2x the corpus, 2.1x"
  say "      the assumptions, and the checker is superlinear in neither but"
  say "      cheap in neither either). The killed pass had already burned"
  say "      5 h 45 at ~0.6 core; on an uncontended core expect the low end."
  say "      A RESUMED run skips every demand set already recorded."
  wait_free6 p14pass | tee -a "$L"
  wait_alone p14pass | tee -a "$L"
  cage p14pass.scope 7G \
    /usr/bin/time -v -o "$B/_p14_cov.time" \
    env DUMP_LIST="$LIST" SUMMARY_OUT="$COV_OUT" \
        SKIP_COMPLETION=1 \
        COVERAGE_CHECKPOINT="$COV_CKPT" \
        PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
        python3 -u "$B/coverage_report.py" > "$B/_p14_cov.log" 2>&1
  say "P14-1 exit=$?"
  verdict P14-1 p14pass.scope "$B/_p14_cov.log" '^COMPLETE=' || exit 10
  grep -E '^\[assumptions\]|^\[checkpoint\]|^(COMPLETE|GENUINE|dumps_loaded|DEMAND_SETS|peak RSS|wrote|dump_errors)|confine|TREE-MISSING' \
       "$B/_p14_cov.log" | tee -a "$L"
  grep -E 'Maximum resident|Elapsed' "$B/_p14_cov.time" 2>/dev/null | tee -a "$L"
  [ "${STAGE1_ONLY:-0}" = 1 ] && { say "STAGE1_ONLY: P14-1 done; run 'bash $0 2' after the apply list lands"; exit 0; }
fi

# -------------------------------------------------- stage 2: ENGINE SECTION --
if [ "$FROM" -le 2 ]; then
  say "P14-2 ENGINE SECTION (audits + shims + note check + gate) -> coverage_summary.json"
  say "      cap 8G. _p13c.sh scripted 3G for this stage, which was WRONG: the"
  say "      restart handoff §2 measured it at ~7G ('report and stop' case)."
  say "      ENGINE_CHECKPOINT=1 = whole-stage skip on matching inputs +"
  say "      per-probe resume inside the gate; COMPLETION_AUDIT_TIMEOUT=${AUDIT_TMO}s."
  say "      EXPECT ~1 h - 1 h 30: ~23 min empty_relation_emission (measured,"
  say "      byte-scaled to 36.07 GB) + a few min note_fidelity + ~29 min for"
  say "      the gate's 184 probes + shim extract/test + the note check."
  [ -s "$COV_OUT" ] || { say "  *** $COV_OUT missing/empty — stage 1 did not deliver."
                         say "      Do NOT hand this stage the 2026-09-11 _cov_FINAL_OD0911.json:"
                         say "      that pass was killed and never wrote one. ***"; exit 20; }
  wait_free6 p14eng | tee -a "$L"
  wait_alone p14eng | tee -a "$L"
  cage p14eng.scope 8G \
    /usr/bin/time -v -o "$B/_p14_eng.time" \
    env SUMMARY_IN="$COV_OUT" SUMMARY_OUT="$B/coverage_summary.json" \
        ENGINE_CHECKPOINT=1 COMPLETION_AUDIT_TIMEOUT="$AUDIT_TMO" \
        ACHK_CHECKPOINT="$B/_achk_probe_checkpoint.jsonl" \
        ACHK_RESULTS_JSONL="$B/_achk_rows.jsonl" \
        CONCOLIC_SLOTS=1 CONCOLIC_PROBE_WORKERS=1 ACHK_PROBE_BATCH=20 \
        PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
        python3 -u "$B/_engine_section.py" > "$B/_p14_engine.log" 2>&1
  say "P14-2 exit=$?"
  verdict P14-2 p14eng.scope "$B/_p14_engine.log" '^ENGINE SECTION DONE' || exit 21
  grep -E '^OVERALL_COMPLETE|^\[checkpoint\]|^  (AUDIT|PASS|FAIL|PROTOCOL|NOTE-CHECK|ASSUMPTIONS|BLOCKING|CONFINEMENT)' \
       "$B/_p14_engine.log" | tee -a "$L"
  grep -E 'Maximum resident|Elapsed' "$B/_p14_eng.time" 2>/dev/null | tee -a "$L"
fi

# ------------------------------------------------------- stage 3: C7 AUDITS --
if [ "$FROM" -le 3 ]; then
  say "P14-3 C7 AUDIT SUITE (AUDITS_CHECKPOINT=1), cap 3G"
  say "      note_fidelity and empty_relation_emission are ALSO in the gate's"
  say "      extra_audit_cmds, so P14-2 has just paid for them once; the C7 run"
  say "      is the suite of record and its .done dir makes a retry cheap."
  say "      EXPECT ~1 h 35 - 2 h: the suite took 65 min on 2026-09-11"
  say "      (01:58:05 -> 03:03:51) over 129 606 dumps; the directory is now"
  say "      183 351 (x1.41) and the live script has gained the X12 streaming"
  say "      lint since that run. A resumed run replays every EXIT=0 audit."
  wait_free6 p14aud | tee -a "$L"
  wait_alone p14aud | tee -a "$L"
  cage p14aud.scope 3G \
    /usr/bin/time -v -o "$B/_p14_audits.time" \
    env AUDITS_CHECKPOINT=1 bash "$B/_c7_audits.sh" > "$B/_p14_audits.out" 2>&1
  # `bash <script>`, not the script directly: the apply list lands
  # _c7_audits.sh with `mv`, which keeps the staged file's 0644.
  say "P14-3 exit=$?"
  verdict P14-3 p14aud.scope "$B/_c7_audits.log" '^=== c7 audits DONE' || exit 30
  grep -n 'EXIT=' "$B/_c7_audits.log" | tee -a "$L"
  nz=$(grep -c 'EXIT=[^0]' "$B/_c7_audits.log"); say "  audits with a non-zero EXIT: $nz"
  grep -E 'Maximum resident' "$B/_p14_audits.time" 2>/dev/null | tee -a "$L"
fi

say "P14 done — read $B/_p14.log, then coverage_summary.json's completion section."
say "NO extraction ran (owner rule: policies are extracted at closure only, and"
say "posts_show is not complete)."
