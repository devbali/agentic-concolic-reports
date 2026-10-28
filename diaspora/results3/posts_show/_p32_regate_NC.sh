#!/bin/bash
# ============================================================================
# P26 job B v3 — THE ACTIVE CONFINEMENT GATE, relaunched 2026-09-14 by the
# _p33_gate throughput round (§93, _p33_gate_throughput_20260914.md).
#
# ONE change from v2: ACHK_PROBE_BATCH 40 -> 200. Nothing else moves.
#   * measured: a probe LAUNCH is JVM+Rails boot (~53 s at the gate's own
#     concurrency) plus ~0.56 s per root; at batch 40 the boot is 1.32 s of
#     every 1.88 s probe. Batch 200 cuts the amortised boot to 0.26 s ->
#     ~0.83 s/probe, i.e. ~2.3x.
#   * CONCOLIC_SLOTS / CONCOLIC_PROBE_WORKERS stay at 2: the box is CPU
#     saturated (4 cores, load ~9.4 before this round), and a measured
#     concurrency sweep gave only +10% total probe throughput at concurrency
#     4 and +16% at 6 — nowhere near paying for its memory or for the
#     throughput it takes off the other rounds. See §93 for the table.
#   * ACHK_PROBE_BATCH is NOT part of any checkpoint key (the ProbeCache
#     header is keyed on engine/cfg/keep/phase), so the 2.8 GB probe
#     checkpoint carries over untouched — no header repointing needed.
#   * the INDEX checkpoint header WAS repointed by hand (§93): its `corpus`
#     digest covered 232 523 names because v2 indexed 104 stale
#     `dump_*_achkP30K_*` probe leftovers as corpus; those were deleted
#     afterwards, leaving the 232 419 real dumps. Index rows are keyed per
#     dump BASENAME and a dump is write-once, so every row stays valid and
#     the 104 rows for deleted files are simply never asked for.
#     697da27b253bff8d60cd0b81a4e358c4 -> 934bb9a9dbc9bd1402af50ca36b0be54.
#     The DERIVE checkpoint was NOT repointed: its records name
#     representatives, so it rotates and re-derives (~13 min) against the
#     clean corpus.
#
# Judge by `RESULT:` in the log (or the process died).
# ============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd /home/dev/project || exit 2
L="$B/_p32_regate_NC.log"
T0=$(date +%s)
{
echo "[$(date -Is)] === P26 CONFINEMENT RE-GATE (X12 multi-base) 61 NOT-COMPARABLE classes  slots=${CONCOLIC_SLOTS:-2} ==="
echo "  declared: $B/_p32_regate_NC.json ($(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$B/_p32_regate_NC.json") reps)"
echo "  corpus:   $(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l) dumps"
echo "  probe batch: ${ACHK_PROBE_BATCH:-200}  workers ${CONCOLIC_PROBE_WORKERS:-2}"
echo "  checker md5 $(md5sum /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py | cut -d' ' -f1)"
echo "  probe ckpt: $(( $(wc -l < "$B/_p32_regate_NC_probes.ckpt.jsonl") - 1 )) records carried over"
} > "$L"
env CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-2}" \
    CONCOLIC_PROBE_WORKERS="${CONCOLIC_PROBE_WORKERS:-2}" \
    ACHK_PROBE_BATCH="${ACHK_PROBE_BATCH:-200}" \
    ACHK_HEARTBEAT_S=60 ACHK_BASES="${ACHK_BASES:-8}" \
    ACHK_INDEX_CHECKPOINT="$B/_p_achk_index.ckpt.jsonl" \
    ACHK_DERIVE_CHECKPOINT="$B/_p32_regate_NC_derive.ckpt.jsonl" \
    ACHK_CHECKPOINT="$B/_p32_regate_NC_probes.ckpt.jsonl" \
    ACHK_RESULTS_JSONL="$B/_p32_regate_NC_rows.jsonl" \
    PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
    python3 -u /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
      "$B/assumption_manifest.json" --declared "$B/_p32_regate_NC.json" \
      --json-out "$B/_p32_regate_NC_results.json" >> "$L" 2>&1
rc=$?
echo "[$(date -Is)] P32-REGATE-NC EXIT rc=$rc wall=$(( $(date +%s)-T0 ))s" >> "$L"
grep -E "^RESULT:" "$L" >> "$L"
