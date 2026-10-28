#!/bin/bash
# =============================================================================
# C19 ASSUMPTION GATE — the derived test for §16f SUB-CONJUNCTION FORECLOSURE.
# One representative per class (_c19_gate_classes.json), detached and
# CHECKPOINTED (RUNBOOK §4): ACHK_INDEX / ACHK_DERIVE / ACHK probe log +
# ACHK_RESULTS_JSONL so a kill leaves every verdict row it produced, plus a
# heartbeat so a slow phase can be told from a hung one. CONCOLIC_SLOTS=1:
# posts_show's gate holds the JRuby slot too.
#   usage: [CAP=8G CAPMB=8192] bash _c19_gate.sh [tag]
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
TAG="${1:-C19}"; CAP="${CAP:-8G}"; CAPMB="${CAPMB:-8192}"
cd "$B" || exit 2
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c19_gate.log"; }
[ -s "$B/_c19_gate_classes.json" ] || { say "C19 GATE: no classes file"; exit 2; }
say "C19 GATE $TAG: $(python3 -c "import json;print(len(json.load(open('$B/_c19_gate_classes.json'))))") class(es), cap=$CAP"
. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "C19 GATE WAIT: free<4G"; sleep 30; done
wait_mem "$CAPMB" "_c19/gate-$TAG" | tee -a "$B/_c19_gate.log"
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c19_gate_${TAG}.time" \
  env CONCOLIC_SLOTS=1 PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      ACHK_CHECKPOINT="$B/_c19_achk_probes.jsonl" \
      ACHK_RESULTS_JSONL="$B/_c19_achk_rows.jsonl" \
      ACHK_INDEX_CHECKPOINT="$B/_c19_achk_index.ckpt.jsonl" \
      ACHK_DERIVE_CHECKPOINT="$B/_c19_achk_derive.ckpt.jsonl" \
      ACHK_HEARTBEAT_S=120 \
  python3 -u /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
      "$B/assumption_manifest.json" --declared "$B/_c19_gate_classes.json" \
      --json-out "$B/_c19_gate_${TAG}.json" > "$B/_c19_gate_${TAG}.log" 2>&1
say "C19 GATE $TAG exit=$?"
if [ -s "$B/_c19_gate_${TAG}.json" ] || [ -s "$B/_c19_achk_rows.jsonl" ]; then
  say "C19-GATE-DONE $TAG"
  python3 - "$B/_c19_achk_rows.jsonl" <<'PY' | tee -a "$B/_c19_gate.log"
import json,sys,collections
c=collections.Counter()
for l in open(sys.argv[1]):
    try: c[json.loads(l)["verdict"]]+=1
    except Exception: pass
print("C19 GATE VERDICTS: "+", ".join(f"{k}={v}" for k,v in sorted(c.items())))
PY
else
  say "C19-GATE-INCOMPLETE $TAG *** no rows — TREAT AS KILLED ***"
  tail -25 "$B/_c19_gate_${TAG}.log" | sed 's/^/    /' | tee -a "$B/_c19_gate.log"
  exit 10
fi
