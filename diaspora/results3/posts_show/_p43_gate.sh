#!/bin/bash
# =============================================================================
# P43 — the ADDITIVE flip-both independence gate over the 189 LEAK-refuted
# confinement pairs, re-put as declared IndependenceAssumptions.
#
# X11: this probe FAILs only on a NOVEL shape in flip-both; it is BLIND to
# dependence that REMOVES reads. A PASS here is WEAKER evidence than the
# corpus 2x2. It is run as corroboration, and because the previous agent's own
# falsifier was stated over it ("if flip-both FAILs a majority of the 189 the
# lever collapses").
#
# Shared bank (§103.2: one bank per ENDPOINT; `declared` is in no checkpoint
# key) + the canonical index. Verdict: `RESULT:` lines / P43-GATE EXIT.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd /home/dev/project || exit 2
L="$B/_p43_gate.log"; T0=$(date +%s)
{
echo "[$(date -Is)] === P43 INDEPENDENCE GATE — 189 LEAK pairs (X12 multi-base) ==="
echo "  declared: $B/_p43_leak_ind.json ($(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$B/_p43_leak_ind.json") pairs)"
echo "  corpus:   $(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l) dumps"
echo "  checker md5 $(md5sum /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py | cut -d' ' -f1)"
echo "  probe ckpt: $(( $(wc -l < "$B/_p32_regate_probes.ckpt.jsonl") - 1 )) records carried over"
} > "$L"
env CONCOLIC_SLOTS=2 CONCOLIC_PROBE_WORKERS=2 ACHK_PROBE_BATCH=800 \
    ACHK_HEARTBEAT_S=60 ACHK_BASES=8 \
    ACHK_INDEX_CHECKPOINT="$B/_p_achk_index.ckpt.jsonl" \
    ACHK_DERIVE_CHECKPOINT="$B/_p43_gate_derive.ckpt.jsonl" \
    ACHK_CHECKPOINT="$B/_p32_regate_probes.ckpt.jsonl" \
    ACHK_RESULTS_JSONL="$B/_p43_gate_rows.jsonl" \
    PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
    python3 -u /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
      "$B/assumption_manifest.json" --declared "$B/_p43_leak_ind.json" \
      --json-out "$B/_p43_gate_results.json" >> "$L" 2>&1
rc=$?
echo "[$(date -Is)] P43-GATE EXIT rc=$rc wall=$(( $(date +%s)-T0 ))s" >> "$L"
grep -E "^RESULT:" "$L" | tail -5 >> "$L"
