#!/bin/bash
# =============================================================================
# C30 — MULTI-BASE ACTIVE FALSIFICATION (DISCIPLINE §17 / X12) of the §16e,
# §16f and §16g classes the C30 pass ACTUALLY APPLIED.
#
#   usage: SUMMARY=<cov summary.json> TAG=<tag> [FALS_K=8] bash _c30_fals.sh
#   verdict line: ^C30-FALS-DONE
#
# COPY of `_c29_fals.sh`. Differences:
#   * the class files are EXTRACTED FROM THE SUMMARY NAMED ON THE LAUNCH LINE,
#     never inherited from a previous round — §40.10's rule, made mechanical.
#   * §16e is probed too, not carried over. C29 carried ON's 89 §16e rows
#     because they were BYTE-IDENTICAL to the set §39.12 had probed; a
#     confinement-OFF pass is a different applied set and has not earned that
#     carry-over, so it is probed. The byte-identity check is still printed,
#     because if it DOES hold the carry-over is a legitimate second line of
#     evidence.
#   * CONCOLIC_SLOTS / CONCOLIC_PROBE_WORKERS = 14, not 1 (16-core box).
#   * FALS_K defaults to 8 and is REFUSED at 1 — `FALS_K=1` reproduces the
#     defective single-base test exactly (§17/X12), so it cannot be reached
#     by accident.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
SUMMARY="${SUMMARY:?usage: SUMMARY=<cov summary.json> TAG=<tag> bash _c30_fals.sh}"
TAG="${TAG:?usage: SUMMARY=<cov summary.json> TAG=<tag> bash _c30_fals.sh}"
K="${FALS_K:-8}"
L="$B/_c30_fals_${TAG}.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

if [ "$K" = 1 ]; then
  say "*** REFUSING FALS_K=1: it reproduces the single-base test X12 refuted "
  say "    (18 of 24 notifications §16g NOT-TESTABLEs were actually refutable). "
  say "    Use 8, or state an explicit reason and edit this guard."
  exit 2
fi
[ -s "$SUMMARY" ] || { say "*** SUMMARY=$SUMMARY missing/empty ***"; exit 2; }

if [ "$1" = "--verdict" ]; then
  if grep -qE '^C30-FALS-DONE' "$B/_c30_fals_${TAG}.out" 2>/dev/null; then
    say "VERDICT C30-FALS-$TAG: OK (line present)"
    grep -E '^===|RESULT|PASS|FAIL|NOT-TESTABLE|NOT-COMPARABLE|bases_' "$B/_c30_fals_${TAG}.out" | tail -40 | tee -a "$L"
    exit 0
  fi
  say "VERDICT C30-FALS-$TAG: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
  tail -25 "$B/_c30_fals_${TAG}.out" 2>/dev/null | sed 's/^/    /' | tee -a "$L"
  exit 10
fi

say "C30 FALS $TAG  summary=$(basename "$SUMMARY")  K=$K"
say "  summary md5 $(md5sum "$SUMMARY" | cut -d' ' -f1)"

# ---- extract the applied classes FROM THIS SUMMARY -------------------------
# THREE extractors, one per section, each reading its OWN summary list. They
# are NOT interchangeable and were nearly used as if they were:
#   _c30_gate_classes_16e.py  -> conjunction_foreclosure_list        (§16e)
#   _c29_gate_classes_16f.py  -> subconjunction_foreclosure_list     (§16f)
#   _c27_gate_classes.py      -> wellfounded_drop_list               (§16g)
# `_c27_gate_classes.py` is the §16g extractor despite its unqualified name.
python3 -u "$B/_c30_gate_classes_16e.py" "$SUMMARY" "$B/_c30_${TAG}_16e_classes.json" >>"$L" 2>&1
python3 -u "$B/_c29_gate_classes_16f.py" "$SUMMARY" "$B/_c30_${TAG}_16f_classes.json" >>"$L" 2>&1
python3 -u "$B/_c27_gate_classes.py"     "$SUMMARY" "$B/_c30_${TAG}_16g_classes.json" >>"$L" 2>&1
for f in 16e 16f 16g; do
  n=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$B/_c30_${TAG}_${f}_classes.json" 2>/dev/null)
  say "  §${f}: ${n:-?} distinct classes -> _c30_${TAG}_${f}_classes.json"
done

# ---- the byte-identity check on §16e, stated either way ---------------------
if [ -f "$B/_c27_16e_classes.json" ]; then
  if cmp -s "$B/_c30_${TAG}_16e_classes.json" "$B/_c27_16e_classes.json"; then
    say "  §16e class file is BYTE-IDENTICAL to the set C27 probed (§39.12) — the carry-over would be earned; probing anyway"
  else
    say "  §16e class file DIFFERS from the set C27 probed — carry-over NOT available, probing is required"
  fi
fi

. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "C30 FALS WAIT: free<4G"; sleep 30; done
wait_mem "${CAPMB:-16384}" "_c30/fals-$TAG" | tee -a "$L"

systemd-run --user --no-block --unit="notif-c30-fals-${TAG}" --slice=concolic-cov.slice \
  -p MemoryMax="${CAP:-16G}" -p MemorySwapMax=0 -p WorkingDirectory="$B" \
  -p StandardOutput="file:$B/_c30_fals_${TAG}.out" \
  -p StandardError="append:$B/_c30_fals_${TAG}.out" \
  --setenv=CONCOLIC_SLOTS=14 --setenv=CONCOLIC_PROBE_WORKERS=14 \
  --setenv=PYTHONPATH=/home/dev/project/src --setenv=JAVA_TOOL_OPTIONS= \
  --setenv=ACHK_CHECKPOINT="$B/_c30_achk_probes_${TAG}.jsonl" \
  --setenv=ACHK_INDEX_CHECKPOINT="$B/_achk_index.ckpt.jsonl" \
  --setenv=ACHK_HEARTBEAT_S=60 --setenv=FALS_K="$K" --setenv=ACHK_BASES="$K" \
  /usr/bin/bash -c "cd $B && \
     echo '=== 16g ===' && python3 -u $B/_c27_fals.py $B/_c30_${TAG}_16g_classes.json $B/_c30_fals_${TAG}_16g.json && \
     echo '=== 16f ===' && python3 -u $B/_c27_fals.py $B/_c30_${TAG}_16f_classes.json $B/_c30_fals_${TAG}_16f.json && \
     echo '=== 16e ===' && python3 -u $B/_c27_fals.py $B/_c30_${TAG}_16e_classes.json $B/_c30_fals_${TAG}_16e.json && \
     echo C30-FALS-DONE"
say "C30 FALS $TAG launched as notif-c30-fals-${TAG}; verdict ^C30-FALS-DONE in _c30_fals_${TAG}.out"
