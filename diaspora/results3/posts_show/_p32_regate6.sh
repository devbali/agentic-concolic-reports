#!/bin/bash
# ============================================================================
# P32 RE-GATE 6 — resume of the 243 NOT-TESTABLE confinement classes.
# Written 2026-09-15 after regate5 died on run_probe's 900 s subprocess
# timeout (NOT a fault, NOT an OOM): 14 workers x B=800 under load ~38 with
# three other jobs pushed a single launch past 900 s.
#
# CHANGES FROM regate5 (settings only; src/ frozen at 5ae1b13c, manifest
# untouched so the 88 826-record bank resumes — cfg digest verified
# 92c6c0cdaa55d1a0927859fc0d89d537 == bank header):
#   ACHK_PROBE_BATCH  800 -> 500   launch wall = B x s/root/worker; B=500
#                                  keeps >=1.6x margin on 900 s even at the
#                                  1.125 s/root that regate5 measured under
#                                  3-job contention, and ~6x on an idle box.
#                                  Not 200: that spends half the wall on boot.
#   WORKERS           14 -> 8      16 cores, sole tenancy. 8 leaves 2 cores
#                                  per JRuby (the workload is ~1.0-1.1 cores
#                                  per process) so launches run at near
#                                  unloaded speed, and leaves headroom for
#                                  the notifications campaign.
#   MemoryMax         24G -> 36G   (cage set at launch, not here.) The 24 G
#                                  floor stands; 24 G cannot hold the
#                                  checker's ~19-20 GB of probe records at
#                                  102 k bank records PLUS 8 x ~1.3 GB of
#                                  workers. Box is 68 GB / 60 free, slice cap
#                                  is 62 GB, so 36 G is free headroom and
#                                  still leaves ~26 G for notifications.
#   ACHK_BASES        8            UNCHANGED. Never 1 — at 1 this reproduces
#                                  the single-base gate and the run is moot.
#
# env_by_scenario IS in the manifest and IS live (every regate5 batch read
# "scenario 'auth_html' ... 0 replayed singly, 800 matched"). Do not touch
# assumption_manifest.json — it is a cfg-digest input and the bank dies with it.
#
# The derive checkpoint WILL rotate (corpus moved 234 251 -> 236 372 because
# regate5's own replay dumps land in the batch dir, §100.5): budget ~15 min.
#
# Judge by `RESULT:` in the log (or the process died).
# ============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd /home/dev/project || exit 2
L="$B/_p32_regate6.log"
T0=$(date +%s)
{
echo "[$(date -Is)] === P32 CONFINEMENT RE-GATE 6 (X12 multi-base) 243 NOT-TESTABLE classes ==="
echo "  declared: $B/_p32_regate_NT.json ($(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$B/_p32_regate_NT.json") reps)"
echo "  corpus:   $(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l) dumps"
echo "  probe batch: ${ACHK_PROBE_BATCH:-500}  workers ${CONCOLIC_PROBE_WORKERS:-8}  slots ${CONCOLIC_SLOTS:-8}  bases ${ACHK_BASES:-8}"
echo "  checker md5 $(md5sum /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py | cut -d' ' -f1)"
echo "  probe ckpt: $(( $(wc -l < "$B/_p32_regate_probes.ckpt.jsonl") - 1 )) records carried over"
} > "$L"
env CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-8}" \
    CONCOLIC_PROBE_WORKERS="${CONCOLIC_PROBE_WORKERS:-8}" \
    ACHK_PROBE_BATCH="${ACHK_PROBE_BATCH:-500}" \
    ACHK_HEARTBEAT_S=60 ACHK_BASES="${ACHK_BASES:-8}" \
    ACHK_INDEX_CHECKPOINT="$B/_p_achk_index.ckpt.jsonl" \
    ACHK_DERIVE_CHECKPOINT="$B/_p32_regate_derive.ckpt.jsonl" \
    ACHK_CHECKPOINT="$B/_p32_regate_probes.ckpt.jsonl" \
    ACHK_RESULTS_JSONL="$B/_p32_regate_rows.jsonl" \
    PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
    python3 -u /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
      "$B/assumption_manifest.json" --declared "$B/_p32_regate_NT.json" \
      --json-out "$B/_p32_regate_results.json" >> "$L" 2>&1
rc=$?
echo "[$(date -Is)] P32-REGATE6 EXIT rc=$rc wall=$(( $(date +%s)-T0 ))s" >> "$L"
grep -E "^RESULT:" "$L" >> "$L"
