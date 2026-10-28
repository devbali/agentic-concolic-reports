#!/bin/bash
# X12 — generic multi-base gate measurement. Judge by `^X12-DONE`.
set +e; unset JAVA_TOOL_OPTIONS
B="$1"; IN="$2"; OUT="$3"; L="$4"
cd /home/dev/project || exit 2
T0=$(date +%s)
{
echo "[$(date -Is)] === X12 multi-base  batch=$B in=$IN K=${X12_K:-8} ACTIVE=${X12_ACTIVE:-0} ==="
echo "  checker md5 $(md5sum /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py | cut -d' ' -f1)"
echo "  corpus $(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l) dumps"
} > "$L"
env CONCOLIC_SLOTS=1 CONCOLIC_PROBE_WORKERS=1 ACHK_PROBE_BATCH=200 ACHK_HEARTBEAT_S=60 \
    ACHK_INDEX_CHECKPOINT="$B/_x12_index.ckpt.jsonl" \
    ACHK_CHECKPOINT="$B/_x12_probes.ckpt.jsonl" \
    X12_K="${X12_K:-8}" X12_ACTIVE="${X12_ACTIVE:-0}" \
    PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
    python3 -u /home/dev/project/reports/diaspora/results3/tools/_x12_multibase.py "$B" "$IN" "$OUT" >> "$L" 2>&1
echo "[$(date -Is)] X12 EXIT rc=$? wall=$(( $(date +%s)-T0 ))s" >> "$L"
