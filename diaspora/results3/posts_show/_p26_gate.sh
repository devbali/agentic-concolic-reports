#!/bin/bash
# ============================================================================
# P26 job B — THE ACTIVE CONFINEMENT GATE (DISCIPLINE §16c check 2, (i)-(viii))
# over posts_show's 1 363 inferred-pair CLASSES, one representative per class.
#
# CHECKPOINTED everywhere the RUNBOOK §4 rule names one, because §82.5 projects
# 40-134 h at CONCOLIC_SLOTS=1 and a kill must cost the probe in flight only:
#   ACHK_INDEX_CHECKPOINT   the corpus index   (one row per dump, ~350 MB)
#   ACHK_DERIVE_CHECKPOINT  probe derivation   (one row per confined DECISION)
#   ACHK_CHECKPOINT         one row per JRuby probe replay
#   ACHK_RESULTS_JSONL      the verdict rows, streamed (--json-out alone writes
#                           an EMPTY file on a kill)
#   ACHK_HEARTBEAT_S=60     so a slow phase can be told from a hung one
# ACHK_CONF_PROFILES is NOT set: §16c says a budget that truncates (vi) makes
# the verdict NOT-TESTABLE, and a NOT-TESTABLE inferred pair is WITHDRAWN and
# blocks — a capped run withdraws exactly what it could not probe (§82.5).
#
# Judge by `RESULT:` in the log (or the process died).
# ============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd /home/dev/project || exit 2
L="$B/_p26_gate.log"
T0=$(date +%s)
{
echo "[$(date -Is)] === P26 CONFINEMENT GATE  1363 classes  slots=${CONCOLIC_SLOTS:-2} ==="
echo "  declared: $B/_p26_gate_classes.json ($(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$B/_p26_gate_classes.json") reps)"
echo "  corpus:   $(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l) dumps"
echo "  checker md5 $(md5sum /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py | cut -d' ' -f1)"
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
echo "[$(date -Is)] P26-GATE EXIT rc=$rc wall=$(( $(date +%s)-T0 ))s" >> "$L"
grep -E "^RESULT:" "$L" >> "$L"
