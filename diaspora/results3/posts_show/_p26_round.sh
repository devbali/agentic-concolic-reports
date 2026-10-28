#!/bin/bash
# =============================================================================
# P26 ROUND DRIVER (round 4 onward) — one command per ROUND instead of per
# stage. Runs §83.7's five-stage loop end to end, each stage caged, each
# stage judged BY ITS OWN VERDICT LINE (never by exit status alone), and
# stops on the brief's three stop conditions:
#
#   (a) OR-refined remaining == 0                     -> P26-ROUND-STOP-ZERO
#   (b) EMITTED CUBES == 0 while no_model > 0         -> P26-ROUND-STOP-NOMODEL
#       (the modelled residue is exhausted; every remaining region piece is one
#        the full conjunction has no Z3 model for — §83.1. This is the state the
#        brief says to STOP and REPORT, not to work around.)
#   (c) closed/run < 0.05 for two consecutive rounds  -> judged by the
#       coordinator off the census numbers this script prints; the script
#       prints the delta, it does not decide the campaign.
#
#   usage: bash _p26_round.sh <N> <X> <PREVLIST> <PREVIDX> [WAITLOG] [WAITPAT]
#     N        emit round number   -> tag P26R<N>
#     X        round letter        -> tag P26<X>, pass tag P26<X>2
#     PREVLIST previous pass's pruned snapshot (absolute or basename)
#     PREVIDX  previous round's _p23_index pickle (for the gaps bootstrap)
#     WAITLOG/WAITPAT  optional: block until WAITPAT appears in WAITLOG, so a
#                      round can be queued behind the previous round's pass
#                      without a second pass ever running beside it (the
#                      one-pass-per-endpoint rule, enforced here rather than
#                      remembered).
#
# NOTHING under src/, no targets.rb, no boundary, no declaration, no git.
# Every stage's own script is UNCHANGED; this only sequences them.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"

N="${1:?usage: _p26_round.sh <N> <X> <prevlist> <previdx> [waitlog] [waitpat]}"
X="${2:?round letter}"
PREV="${3:?prev pruned snapshot}"; [ -f "$PREV" ] || PREV="$B/$PREV"
PIDX="${4:?prev index pkl}";       [ -f "$PIDX" ] || PIDX="$B/$PIDX"
WAITLOG="${5:-}"; WAITPAT="${6:-}"
STAMP="${STAMP:-20260913}"
PASS_CAP="${PASS_CAP:-7G}"
EMIT_CAP_G="${EMIT_CAP_G:-6G}"

L="$B/_p26_round_P26${X}.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
T0=$(date +%s)

say "=== P26 ROUND P26${X} (emit tag P26R${N})  prev=$(basename "$PREV")  previdx=$(basename "$PIDX") ==="
say "  engine coverage.py md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"
say "  corpus $(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l) dumps"

# ---------------------------------------------------------------- stage 0 wait
if [ -n "$WAITLOG" ]; then
  w=0
  until grep -qE "$WAITPAT" "$WAITLOG" 2>/dev/null; do
    [ $((w % 600)) -eq 0 ] && say "  stage0: waiting for '$WAITPAT' in $(basename "$WAITLOG") (${w}s)"
    sleep 60; w=$((w+60))
  done
  say "stage0 OK — $(grep -E "$WAITPAT" "$WAITLOG" | tail -1)"
fi

# ---------------------------------------------------------------- stage 1 emit
EL="$B/_p26_enum_P26R${N}.log"
if [ "${SKIP_EMIT:-0}" = 1 ]; then
  # The emission for this round already exists and was VERIFIED intact
  # (line count == emit_stats.cubes, every line parses). Used when another
  # session ran step 1 of §83.7's loop concurrently — see §84's collision note.
  say "S1 EMIT SKIPPED (SKIP_EMIT=1) — reusing $(basename "$EL") / _p26_emit_P26R${N}.json.jsonl"
else
  say "S1 EMIT OR-refined remaining over $(basename "$PREV") ($(wc -l < "$PREV") profiles), cap ${EMIT_CAP_G}"
  cage "p26emit${N}.scope" "$EMIT_CAP_G" bash "$B/_p26_emit.sh" "P26R${N}" "$PREV"
  caged_verdict "p26emit${N}.scope" "$EL" '^P26-EMIT-OK|^P26-EMIT-DONE' | tee -a "$L"
fi
grep -qE '^P26-EMIT-DONE' "$EL" || { say "P26-ROUND-FAILED emit"; exit 3; }
grep -E '^  sets=|^EMIT: remaining cubes=|^  16b:|^universe built' "$EL" | tee -a "$L"

JS="$B/_p26_emit_P26R${N}.json"
read -r CUBES NOMODEL PIECES REMAIN <<<"$(python3 - "$JS" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); s=d["emit_stats"]
print(s["cubes"], s["no_model"], s["pieces"], d.get("remaining_total","?"))
PY
)"
say "S1 CENSUS: OR-refined REMAINING=$REMAIN  region_pieces=$PIECES  EMITTED(modelled)=$CUBES  MODEL-LESS=$NOMODEL"

if [ "$REMAIN" = "0" ]; then
  say "P26-ROUND-STOP-ZERO — OR-refined remaining is 0"; exit 0
fi
if [ "$CUBES" = "0" ]; then
  say "P26-ROUND-STOP-NOMODEL — modelled residue exhausted; $NOMODEL model-less region pieces remain of $PIECES"
  exit 0
fi

# ------------------------------------------------------------- stage 2 rebuild
say "S2 REBUILD (gaps-bootstrap -> fresh index -> gaps -> construct)"
OLD_INDEX="$PIDX" bash "$B/_p26_rebuild.sh" "P26${X}" \
  "$B/_p26_emit_P26R${N}.json.jsonl" "$PREV" >> "$L" 2>&1
grep -qE '^\[.*\] P26-REBUILD-DONE' "$B/_p26_rebuild_P26${X}.log" || {
  say "P26-ROUND-FAILED rebuild"; tail -20 "$B/_p26_rebuild_P26${X}.log" | tee -a "$L"; exit 4; }
say "S2 P26-REBUILD-DONE P26${X}"

# --------------------------------------------------------------- stage 3 drive
say "S3 DRIVE (DRIVE_PAR=2, CONCOLIC_SLOTS=4, chunk 200)"
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
SEEDSET="P26${X}" DRIVE_PAR=2 CONCOLIC_SLOTS=4 \
  P15_MANIFEST="$B/_p15_manifest_P26${X}.json" \
  bash "$B/_p15_drive.sh" "P26${X}" 200 >> "$L" 2>&1
DL="$B/_p15_drive_P26${X}.log"
grep -qE 'P15-DRIVE-DONE' "$DL" || { say "P26-ROUND-FAILED drive"; tail -20 "$DL" | tee -a "$L"; exit 5; }
after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "S3 $(grep -E 'P15-DRIVE-DONE' "$DL" | tail -1)   corpus ${before} -> ${after}"

# ------------------------------------------------------------- stage 4 explain
say "S4 EXPLAIN per key"
cage "p26exp${X}.scope" 4G \
  env P15_TAG="P26${X}" P15_SET="P26${X}" \
      P15_GAPS="$B/_p26_gaps_P26${X}.json" \
      P15_MANIFEST="$B/_p15_manifest_P26${X}.json" \
      P15_OUT="$B/_p26_explain_P26${X}.json" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p15_explain.py" > "$B/_p26_explain_P26${X}.log" 2>&1
caged_verdict "p26exp${X}.scope" "$B/_p26_explain_P26${X}.log" '^P15-EXPLAIN-DONE' | tee -a "$L"
grep -E 'WALKED|honoured|contradicted|never evaluated|cube literals|^  gaps' \
     "$B/_p26_explain_P26${X}.log" | head -20 | tee -a "$L"

# ---------------------------------------------------------------- stage 5 pass
say "S5 PASS P26${X}2 (OR-refined, checkpointed, cap ${PASS_CAP})"
STAMP="$STAMP" PASS_CAP="$PASS_CAP" ALONE_OVERRIDE=1 \
  bash "$B/_p26_pass.sh" "P26${X}2" "P26${X}" "$PREV" >> "$L" 2>&1
grep -qE 'P26-PASS-DONE' "$B/_p26_pass_P26${X}2.log" || {
  say "P26-ROUND-FAILED pass"; tail -20 "$B/_p26_pass_P26${X}2.log" | tee -a "$L"; exit 6; }
grep -E 'P26-PASS-1|distinct outcome|^(COMPLETE|GENUINE|NODES|MISSING|DEMAND_SETS)|Maximum resident|Elapsed' \
     "$B/_p26_pass_P26${X}2.log" | tee -a "$L"

say "P26-ROUND-DONE P26${X}  wall $(( $(date +%s)-T0 ))s"
say "  NEXT: bash _p26_round.sh $((N+1)) <next letter> _snapshot_pruned_P26${X}2.txt _p26_index_P26${X}.pkl"
