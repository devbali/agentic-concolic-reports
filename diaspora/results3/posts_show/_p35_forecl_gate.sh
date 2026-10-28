#!/bin/bash
# ============================================================================
# P35 — THE FORECLOSURE GATE (§16f/§16g as a first-class tested assumption).
#
# Drives `src/end_to_end_completion_checker/assumption/foreclosure_gate.py`
# over the emitter's (C, d) export. Each class gets TWO constructed replays:
# a POSITIVE CONTROL (a member the corpus demonstrably evaluates under the
# same C) and the CLAIM. A control that does not come back green makes the
# class NOT-TESTABLE -- silence is never read as licence (X11/X12).
#
# `assumption_checker.py` is IMPORTED, NEVER EDITED: its md5 is the ProbeCache
# `engine` key over the whole file, so an edit would discard the 102 k-probe
# bank. Verified 5ae1b13c before and after.
#
# Judge by `RESULT:` in the log (or the process died).
# ============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd /home/dev/project || exit 2
CLASSES="${CLASSES:-$B/_p35_subconj_classes_W5_ctl.json}"
OUT="${OUT:-$B/_p35_forecl_gate_results.json}"
L="${LOG:-$B/_p35_forecl_gate.log}"
T0=$(date +%s)
{
echo "[$(date -Is)] === P35 FORECLOSURE GATE ==="
echo "  classes: $CLASSES ($(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$CLASSES" 2>/dev/null) classes)"
echo "  checker md5 (must be 5ae1b13c...): $(md5sum /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py | cut -d' ' -f1)"
echo "  probe batch ${ACHK_PROBE_BATCH:-500}  workers ${CONCOLIC_PROBE_WORKERS:-8}"
} > "$L"
env CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-8}" \
    CONCOLIC_PROBE_WORKERS="${CONCOLIC_PROBE_WORKERS:-8}" \
    ACHK_PROBE_BATCH="${ACHK_PROBE_BATCH:-500}" \
    ACHK_HEARTBEAT_S=60 \
    ACHK_INDEX_CHECKPOINT="$B/_p_achk_index.ckpt.jsonl" \
    ACHK_CHECKPOINT="$B/_p32_regate_probes.ckpt.jsonl" \
    PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
    python3 -u - "$B/assumption_manifest.json" "$CLASSES" "$OUT" >> "$L" 2>&1 <<'PY'
import json, sys
from end_to_end_completion_checker.assumption import assumption_checker as AC
from end_to_end_completion_checker.assumption import foreclosure_gate as FG

manifest, classes_path, out = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = json.load(open(manifest))

# INSTALL THE CANONICALIZE HOOK exactly as main() does, BEFORE any ProbeCache
# exists. assumption_checker guards this (:1194): without the hook the probe
# checkpoint key degrades to 'none' and a bank built under one canonicalization
# would be reused under another. We reuse the SAME bank as the confinement
# gates, so this must match theirs byte-for-byte.
if cfg.get("canonicalize"):
    import importlib
    mod_name, fn_name = cfg["canonicalize"].split(":")
    sys.path.insert(0, cfg["batch_dir"])
    _mod = importlib.import_module(mod_name)
    AC._CANON_FN = getattr(_mod, fn_name)
    AC._ALIASES = list(getattr(_mod, "ALIASES", []) or [])
    print(f"[canonicalize] {cfg['canonicalize']} with {len(AC._ALIASES)} alias(es)",
          flush=True)
    print(f"[canonicalize] key = {AC._canon_key()}", flush=True)

classes = FG.load_classes(classes_path)
print(f"loaded {len(classes)} foreclosure class(es)", flush=True)
have_ctl = sum(1 for c in classes if c.get("control_member"))
print(f"  with a positive control: {have_ctl}  without: {len(classes)-have_ctl}", flush=True)

cache = AC.ProbeCache(cfg, False)
cache.planning = True
FG.plan_and_test(cfg, classes, cache)
print("planning pass done; executing probes...", flush=True)
cache.execute()
cache.planning = False
res = FG.plan_and_test(cfg, classes, cache, out=out)
print(FG.summarise(res), flush=True)
w = FG.withdrawn(res)
print(f"classes a completion claim may NOT rely on: {len(w)} of {len(res)}", flush=True)
from collections import Counter
print("  by verdict:", dict(Counter(r['verdict'] for r in w)), flush=True)
for r in res:
    if r["verdict"] == "FAIL":
        print("  FAIL", r["member"][:70], "|", r["detail"][:110], flush=True)
cache.close()
PY
rc=$?
echo "[$(date -Is)] P35-FORECL-GATE EXIT rc=$rc wall=$(( $(date +%s)-T0 ))s" >> "$L"
