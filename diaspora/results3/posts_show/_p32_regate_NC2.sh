#!/bin/bash
# ============================================================================
# P32 RE-GATE NC2 — the 61 NOT-COMPARABLE confinement classes, 2026-09-15.
# Successor to _p32_regate_NC.sh (never run). THREE changes, all settings:
#   1. ACHK_CHECKPOINT now points at the SHARED bank
#      _p32_regate_probes.ckpt.jsonl instead of a private empty one.
#      SOUND, and it makes every overlapping probe free: the ProbeCache header
#      is keyed on engine/phase/cfg/canonicalize/keep ONLY (:1202-1208) and the
#      per-probe key is (scenario, seeds) (:1214) -- `declared` appears in
#      NEITHER. The NT gate's ~102 k records are therefore valid answers to any
#      NC probe that asks the same question, and the expensive probes
#      (_exhaustive_flip / _constructed_route, ~99 % of the total) are
#      functions of the DECISION and the CORPUS, not of the declared list, so
#      overlap is expected to be large. New NC probes append to the same file.
#      The DERIVE checkpoint stays private -- it IS keyed on `declared`.
#   2. batch 200 -> 500, workers 2 -> 8   (see _p32_regate6.sh for the sizing)
#   3. its own log, _p32_regate_NC2.log
# Judge by `RESULT:` in the log (or the process died).
# ============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd /home/dev/project || exit 2
L="$B/_p32_regate_NC2.log"
T0=$(date +%s)
{
echo "[$(date -Is)] === P26 CONFINEMENT RE-GATE (X12 multi-base) 61 NOT-COMPARABLE classes  slots=${CONCOLIC_SLOTS:-8} ==="
echo "  declared: $B/_p32_regate_NC.json ($(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$B/_p32_regate_NC.json") reps)"
echo "  corpus:   $(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l) dumps"
echo "  probe batch: ${ACHK_PROBE_BATCH:-500}  workers ${CONCOLIC_PROBE_WORKERS:-8}"
echo "  checker md5 $(md5sum /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py | cut -d' ' -f1)"
echo "  probe ckpt: $(( $(wc -l < "$B/_p32_regate_NC_probes.ckpt.jsonl") - 1 )) records carried over"
} > "$L"
env CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-8}" \
    CONCOLIC_PROBE_WORKERS="${CONCOLIC_PROBE_WORKERS:-8}" \
    ACHK_PROBE_BATCH="${ACHK_PROBE_BATCH:-500}" \
    ACHK_HEARTBEAT_S=60 ACHK_BASES="${ACHK_BASES:-8}" \
    ACHK_INDEX_CHECKPOINT="$B/_p_achk_index.ckpt.jsonl" \
    ACHK_DERIVE_CHECKPOINT="$B/_p32_regate_NC_derive.ckpt.jsonl" \
    ACHK_CHECKPOINT="$B/_p32_regate_probes.ckpt.jsonl" \
    ACHK_RESULTS_JSONL="$B/_p32_regate_NC_rows.jsonl" \
    PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
    python3 -u /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
      "$B/assumption_manifest.json" --declared "$B/_p32_regate_NC.json" \
      --json-out "$B/_p32_regate_NC_results.json" >> "$L" 2>&1
rc=$?
echo "[$(date -Is)] P32-REGATE-NC2 EXIT rc=$rc wall=$(( $(date +%s)-T0 ))s" >> "$L"
grep -E "^RESULT:" "$L" >> "$L"
