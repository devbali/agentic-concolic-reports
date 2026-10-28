#!/bin/bash
# ============================================================================
# P26 job B v2 — THE ACTIVE CONFINEMENT GATE, relaunched 2026-09-13 after the
# batch-probe matching fix (§90).
#
# v1 (00:08-18:07) degenerated to ONE JRuby launch PER PROBE: the batch's
# `canonicalize` hook (gate_canon.fix_len_names) renames a `len(X)` seed key
# to `SYM_LEN_X` at load, so `_run_chunk`'s `concolic_seeds == sd` missed
# every root that seeds a list length and replayed it singly. Fixed in
# src/.../assumption_checker.py (`seeds_as_written`, RAW_SEEDS_KEY).
#
# RESUME: $ACHK_CHECKPOINT keeps v1's 27,309 probe records — its header was
# repointed at the new engine hash by hand (the record FORMAT is unchanged;
# only how a dump is matched back to its root changed, so every recorded
# replay stays valid). The index/derive checkpoints rotate on their own: the
# engine hash changed AND the corpus grew 223,971 -> 232,523 dumps. ~30 min.
#
# Same caps as v1: CONCOLIC_SLOTS=2, CONCOLIC_PROBE_WORKERS=2, batch 40.
# Judge by `RESULT:` in the log (or the process died).
# ============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd /home/dev/project || exit 2
L="$B/_p26_gate_v2.log"
T0=$(date +%s)
{
echo "[$(date -Is)] === P26 CONFINEMENT GATE v2  1363 classes  slots=${CONCOLIC_SLOTS:-2} ==="
echo "  declared: $B/_p26_gate_classes.json ($(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$B/_p26_gate_classes.json") reps)"
echo "  corpus:   $(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l) dumps"
echo "  checker md5 $(md5sum /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py | cut -d' ' -f1)"
echo "  probe ckpt: $(( $(wc -l < "$B/_p26_achk_probes.ckpt.jsonl") - 1 )) records carried over from v1"
} > "$L"
env CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-2}" \
    CONCOLIC_PROBE_WORKERS="${CONCOLIC_PROBE_WORKERS:-2}" \
    ACHK_PROBE_BATCH=40 \
    ACHK_HEARTBEAT_S=60 \
    ACHK_INDEX_CHECKPOINT="$B/_p26_achk_index.ckpt.jsonl" \
    ACHK_DERIVE_CHECKPOINT="$B/_p26_achk_derive.ckpt.jsonl" \
    ACHK_CHECKPOINT="$B/_p26_achk_probes.ckpt.jsonl" \
    ACHK_RESULTS_JSONL="$B/_p26_achk_rows.jsonl" \
    PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
    python3 -u /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
      "$B/assumption_manifest.json" --declared "$B/_p26_gate_classes.json" \
      --json-out "$B/_p26_gate_results.json" >> "$L" 2>&1
rc=$?
echo "[$(date -Is)] P26-GATE-V2 EXIT rc=$rc wall=$(( $(date +%s)-T0 ))s" >> "$L"
grep -E "^RESULT:" "$L" >> "$L"
