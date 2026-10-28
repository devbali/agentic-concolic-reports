#!/bin/bash
# =============================================================================
# P15 COVERAGE PASS — the checkpointed stage-1 block of
# `_p14_rerun_after_restart.sh`, lifted verbatim in structure and made
# ARGUMENT-DRIVEN so each P15 round gets its own list, its own checkpoint and
# its own summary. P14 is NOT edited (owner rule: keep the pass of record
# intact; a rerun of P14 must still reproduce P14).
#
#   usage:  bash _p15_pass.sh <TAG> [DRIVETAG] [BASELIST]
#             TAG       round tag, e.g. P15A   (names every artefact)
#             DRIVETAG  dump-label tag of the drive just finished (default TAG);
#                       "-" skips the snapshot/prune step and reuses
#                       _snapshot_pruned_<TAG>.txt if it is already there
#             BASELIST  the previous round's PRUNED list
#                       (default _snapshot_pruned_OD0911.txt)
#
# WHAT IT DOES, in three stages, each judged by its OWN verdict line:
#   1. SNAPSHOT  = BASELIST + every dump this round's drive wrote.
#      Pruning `BASELIST + new` is EXACT for the §16b verdict and is not an
#      approximation of pruning the whole 189k-dump directory: `_prune_corpus.py`
#      keeps one dump per distinct OUTCOME PROFILE, BASELIST already holds one
#      per profile of the old corpus, and every old dump it dropped had a
#      profile that is still represented. Same profile set, ~38k dumps to read
#      instead of ~189k.
#   2. PRUNE     -> _snapshot_pruned_<TAG>.txt              (cap 3G)
#   3. THE PASS  -> _cov_FINAL_<TAG>_<STAMP>.json           (cap 7G)
#      SKIP_COMPLETION=1  (the gate is the coordinator's stage, never mixed in
#                          with the coverage layer — RUNBOOK §4, the rule that
#                          exists because notifications lost an 8 962 s phase)
#      COVERAGE_CHECKPOINT=_cov_<tag>.ckpt.jsonl  (a kill costs the demand set
#                          in flight and nothing else; the key is the corpus
#                          digest, so a NEW corpus starts fresh by itself and a
#                          rerun of THIS script resumes)
#      MAX_MISSING_PER_CLIQUE=1  — SET EXPLICITLY. The batch's own
#                          coverage_report.py line 203 defaults the env var to
#                          "4", which is what P14 actually ran at (§77.1: 6 150
#                          witnesses over 1 747 sets, 1 510 of them stopped AT
#                          the cap). The engine default has been 1 since
#                          DISCIPLINE §16d and one witness per set is all the
#                          constructor consumes — a second witness for the same
#                          set buys the demand round nothing and costs a full
#                          query on a larger formula.
#
# READ THE CHECKPOINT, NOT THE SUMMARY: the summary's `missing[]` is cut at
# MISSING_CAP=4000. `_p15_classify.py` reads `_cov_<tag>.ckpt.jsonl`.
#
# VERDICT. Last line is `P15-PASS-DONE <TAG>` or `P15-PASS-FAILED <stage>`.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"

TAG="${1:?usage: _p15_pass.sh <TAG> [DRIVETAG] [BASELIST]}"
DRIVETAG="${2:-$TAG}"
BASE="${3:-$B/_snapshot_pruned_OD0911.txt}"
[ -f "$BASE" ] || BASE="$B/$3"
STAMP="${STAMP:-20260912}"
low=$(echo "$TAG" | tr 'A-Z' 'a-z')

L="$B/_p15_pass_${TAG}.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
verdict(){ # <label> <unit> <log> <regex>
  if grep -qE "$4" "$3" 2>/dev/null; then say "VERDICT $1: OK (verdict line present)"; return 0
  else say "VERDICT $1: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
       caged_verdict "$2" "$3" "$4" | tee -a "$L"
       tail -25 "$3" 2>/dev/null | sed 's/^/    /' | tee -a "$L"; return 1; fi
}

SNAP="$B/_snapshot_p15_${TAG}.txt"
LIST="$B/_snapshot_pruned_${TAG}.txt"
COV_OUT="$B/_cov_FINAL_${TAG}_${STAMP}.json"
COV_CKPT="$B/_cov_${low}.ckpt.jsonl"

say "=== P15 PASS $TAG   base=$(basename "$BASE")  drivetag=$DRIVETAG ==="
say "  engine coverage.py       md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"
say "  batch coverage_report.py md5 $(md5sum "$B/coverage_report.py" | cut -d' ' -f1)"
mx=$(systemctl --user show concolic-cov.slice -p MemoryMax --value); case "$mx" in ''|infinity|*[!0-9]*) mx=0;; esac
say "  cage MemoryMax=$(awk -v m=$mx 'BEGIN{printf "%.1fG", m/1073741824}') MemoryCurrent=$(awk -v c=$(systemctl --user show concolic-cov.slice -p MemoryCurrent --value) 'BEGIN{printf "%.1fG", c/1073741824}')"

# --------------------------------------------------- 1 + 2: snapshot & prune
if [ "$DRIVETAG" = "-" ]; then
  say "P15-PASS-1/2 SKIPPED (drivetag '-') — reusing $(basename "$LIST")"
  [ -s "$LIST" ] || { say "P15-PASS-FAILED snapshot: $LIST missing"; exit 3; }
else
  [ -s "$BASE" ] || { say "P15-PASS-FAILED snapshot: base list $BASE missing/empty"; exit 3; }
  nb=$(wc -l < "$BASE")
  find "$B" -maxdepth 1 -name "dump_*${DRIVETAG}*.json" > "$B/_new_${TAG}.txt"
  nn=$(wc -l < "$B/_new_${TAG}.txt")
  cat "$BASE" "$B/_new_${TAG}.txt" | sed 's#^\./#'"$B"'/#' | sort -u > "$SNAP"
  ns=$(wc -l < "$SNAP")
  say "P15-PASS-1 snapshot: base $nb + new $nn (label *${DRIVETAG}*) = $ns unique -> $(basename "$SNAP")"
  if [ "$nn" = 0 ]; then
    say "  *** the drive wrote 0 dumps with label *${DRIVETAG}* — a pass on an"
    say "      unchanged corpus reproduces the previous verdict and is a waste"
    say "      of 35 min. Stopping. ***"
    say "P15-PASS-FAILED snapshot"; exit 3
  fi
  say "P15-PASS-2 prune (cap 3G) -> $(basename "$LIST")"
  cage "p15prune${TAG}.scope" 3G \
    env DUMP_LIST="$SNAP" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
        python3 -u "$B/_prune_corpus.py" --out "$LIST" > "$B/_p15_prune_${TAG}.log" 2>&1
  say "P15-PASS-2 exit=$?"
  verdict P15-PASS-2 "p15prune${TAG}.scope" "$B/_p15_prune_${TAG}.log" 'distinct outcome profiles' || { say "P15-PASS-FAILED prune"; exit 4; }
  grep 'distinct outcome profiles' "$B/_p15_prune_${TAG}.log" | tee -a "$L"
fi
NL=$(wc -l < "$LIST")
say "  DUMP_LIST $(basename "$LIST")  $NL profiles"

# ------------------------------------------------------------- 3: the pass
[ -s "$COV_CKPT" ] && say "  RESUMING: $(wc -l < "$COV_CKPT") demand-set record(s) already in $(basename "$COV_CKPT")"
say "P15-PASS-3 COVERAGE LAYER (SKIP_COMPLETION=1, MAX_MISSING_PER_CLIQUE=1, CHECKPOINTED), cap 7G"
say "      -> $(basename "$COV_OUT")   ckpt $(basename "$COV_CKPT")"
say "      EXPECT ~35 min (P14 measured 35 min at cap 4 on 32 305 profiles);"
say "      cap 1 is CHEAPER per set, the corpus is larger — same order."
wait_free6 "p15pass${TAG}" | tee -a "$L"
wait_alone "p15pass${TAG}" | tee -a "$L"
cage "p15pass${TAG}.scope" "${PASS_CAP:-7G}" \
  /usr/bin/time -v -o "$B/_p15_cov_${TAG}.time" \
  env DUMP_LIST="$LIST" SUMMARY_OUT="$COV_OUT" \
      SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=1 \
      COVERAGE_CHECKPOINT="$COV_CKPT" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/coverage_report.py" > "$B/_p15_cov_${TAG}.log" 2>&1
say "P15-PASS-3 exit=$?"
verdict P15-PASS-3 "p15pass${TAG}.scope" "$B/_p15_cov_${TAG}.log" '^COMPLETE=' || { say "P15-PASS-FAILED pass"; exit 10; }
grep -E '^\[assumptions\]|^\[checkpoint\]|^(COMPLETE|GENUINE|dumps_loaded|DEMAND_SETS|peak RSS|wrote|dump_errors)|confine|TREE-MISSING' \
     "$B/_p15_cov_${TAG}.log" | tee -a "$L"
grep -E 'Maximum resident|Elapsed' "$B/_p15_cov_${TAG}.time" 2>/dev/null | tee -a "$L"
say "P15-PASS-DONE $TAG"
