#!/bin/bash
# =============================================================================
# P30 ASSUMPTION GATE, RE-RUN WITH --keep (the FALSIFIER FEEDBACK run).
# The first run refuted 5 of the 26 §16f classes; §16f says the refuting RUN
# removes the foreclosure on the next pass with nothing to retract by hand, so
# the probe dumps must ENTER the corpus. run_probe deletes them unless --keep,
# so the 19 probes are replayed once more with it. The corpus index checkpoint
# is REUSED (same declared file, same corpus), so this costs the probes only.
# P30 ASSUMPTION GATE — the DERIVED test for §16f SUB-CONJUNCTION FORECLOSURE
# on posts_show (`_test_subconjunction_foreclosure`). Modelled on
# notifications_index/_c19_gate.sh; one representative per (C, d) class,
# detached and CHECKPOINTED (RUNBOOK §4): ACHK_INDEX / ACHK_DERIVE / the probe
# log + ACHK_RESULTS_JSONL so a kill leaves every verdict row it produced, and
# a heartbeat so a slow phase can be told from a hung one.
#
# CONCOLIC_SLOTS=1 — posts_show's own confinement gate (posts-p26-gate-20260913,
# never stopped) already holds two JRuby slots on a 4-CPU box (§86.4).
# Its index checkpoint is NOT shared: this gate builds its own so the running
# gate's file is never contended.
#   usage: [CAP=8G] bash _p30_gate.sh [tag]
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
TAG="${1:-P30K}"; CAP="${CAP:-8G}"
cd "$B" || exit 2
. "$B/_cage.sh"
L="$B/_p30_gate_keep.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
[ -s "$B/_p30_gate_classes.json" ] || { say "P30 GATE: no classes file"; exit 2; }
say "P30 GATE $TAG: $(python3 -c "import json;print(len(json.load(open('$B/_p30_gate_classes.json'))))") class(es), cap=$CAP"
say "  checker md5 $(md5sum /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py | cut -d' ' -f1)"
# one coverage pass on the box at a time, and never beside notifications'
wait_no_pass | tee -a "$L"
gate_launch "$(_cap_gib "$CAP")" "p30gate$TAG" | tee -a "$L"
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet --unit="p30gate${TAG}.scope" \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_p30_gate_${TAG}.time" \
  env CONCOLIC_SLOTS=1 PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      ACHK_CHECKPOINT="$B/_p30k_achk_probes.jsonl" \
      ACHK_RESULTS_JSONL="$B/_p30k_achk_rows.jsonl" \
      ACHK_INDEX_CHECKPOINT="$B/_p30_achk_index.ckpt.jsonl" \
      ACHK_DERIVE_CHECKPOINT="$B/_p30k_achk_derive.ckpt.jsonl" \
      ACHK_HEARTBEAT_S=120 \
  python3 -u /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
      "$B/assumption_manifest.json" --declared "$B/_p30_gate_classes.json" \
      --json-out "$B/_p30_gate_${TAG}.json" --keep > "$B/_p30_gate_${TAG}.log" 2>&1
say "P30 GATE $TAG exit=$?"
if [ -s "$B/_p30_gate_${TAG}.json" ] || [ -s "$B/_p30k_achk_rows.jsonl" ]; then
  say "P30-GATE-DONE $TAG"
  python3 - "$B/_p30k_achk_rows.jsonl" <<'PY' | tee -a "$L"
import json,sys,collections
c=collections.Counter(); rows=[]
for l in open(sys.argv[1]):
    try:
        r=json.loads(l); c[r.get("verdict")]+=1; rows.append(r)
    except Exception: pass
print("P30 GATE VERDICTS: "+", ".join(f"{k}={v}" for k,v in sorted(c.items(), key=lambda x:str(x[0]))))
for r in rows:
    print(f"  {r.get('verdict'):>14}  {str(r.get('expr'))[:70]}  |  {str(r.get('prefix'))[:70]}")
PY
else
  say "P30-GATE-INCOMPLETE $TAG *** no rows — TREAT AS KILLED ***"
  tail -25 "$B/_p30_gate_${TAG}.log" | sed 's/^/    /' | tee -a "$L"
  exit 10
fi
