#!/bin/bash
# =============================================================================
# C27 §16g ASSUMPTION GATE (inner) — runs INSIDE the systemd unit, so the whole
# job (probe run + verdict tally) survives the launcher dying.  One
# representative per (C, d) WELL-FOUNDED DROP class, checkpointed per RUNBOOK §4.
#   ACHK_INDEX_CHECKPOINT is the ENGINE SECTION's own default path on purpose:
#   assumption_checker.py was re-merged 2026-09-14 so every index is stale and
#   rebuilds ONCE (~2 h 20 over 310 k dumps); sharing the path means the engine
#   section resumes it incrementally instead of paying it again.
#   verdict line: ^C27-GATE-DONE
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
TAG="${1:-C27G}"
cd "$B" || exit 2
echo "[$(date -Is)] C27 GATE $TAG start: $(python3 -c "import json;print(len(json.load(open('$B/_c27_gate_classes.json'))))") §16g class(es)"
/usr/bin/time -v -o "$B/_c27_gate_${TAG}.time" \
  env CONCOLIC_SLOTS=1 PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      ACHK_CHECKPOINT="$B/_c27_achk_probes.jsonl" \
      ACHK_RESULTS_JSONL="$B/_c27_achk_rows.jsonl" \
      ACHK_INDEX_CHECKPOINT="$B/_achk_index.ckpt.jsonl" \
      ACHK_DERIVE_CHECKPOINT="$B/_c27_achk_derive.ckpt.jsonl" \
      ACHK_HEARTBEAT_S=60 \
  python3 -u /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
      "$B/assumption_manifest.json" --declared "$B/_c27_gate_classes.json" \
      --json-out "$B/_c27_gate_${TAG}.json" > "$B/_c27_gate_${TAG}.log" 2>&1
RC=$?
echo "[$(date -Is)] C27 GATE $TAG exit=$RC"
if [ -s "$B/_c27_gate_${TAG}.json" ] || [ -s "$B/_c27_achk_rows.jsonl" ]; then
  python3 - "$B/_c27_gate_${TAG}.json" "$B/_c27_achk_rows.jsonl" <<'PY'
import json, sys, collections, os
rows = []
if os.path.exists(sys.argv[1]) and os.path.getsize(sys.argv[1]):
    rows = json.load(open(sys.argv[1]))
if not rows:
    rows = [json.loads(l) for l in open(sys.argv[2]) if l.strip()]
c = collections.Counter(r.get("verdict") for r in rows)
print("C27 GATE VERDICTS: " + ", ".join(f"{k}={v}" for k, v in sorted(c.items())))
for i, r in enumerate(rows):
    print(f"  [{i:02d}] {r.get('verdict'):<14} {str(r.get('expr'))[:86]}")
    print(f"       {str(r.get('detail'))[:200]}")
PY
  echo "C27-GATE-DONE $TAG rc=$RC"
else
  echo "C27-GATE-INCOMPLETE $TAG *** no rows — TREAT AS KILLED ***"
  tail -30 "$B/_c27_gate_${TAG}.log" | sed 's/^/    /'
  exit 10
fi
