#!/bin/bash
# PIPELINE 6 — the RIG-REPLAY confinement gate run. HELD twice over:
#   (a) until the ACTIVE probe lands (exhaustive-profile + constructed probes in
#       src/test_confinement_gate.py) — the owner judged the single-snapshot
#       composition probe not complete enough against the independence gate;
#   (b) until pipeline 5's confinement-aware pass has emitted the confined pairs
#       WITH their footprints (_cov_p5_conf.json) — a hand-built footprint would
#       be a different claim from the one the checker inferred.
# Budgeted as a BATCH on the slot tool (each JRuby ~1.2 GB), caged.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_pipeline6.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

say "waiting for (a) the ACTIVE confinement gate and (b) the confinement-aware pass"
w=0
while :; do
  active=0
  grep -qiE 'def test_[a-z0-9_]*(exhaustive|constructed|adversarial)' \
    /home/dev/project/src/test_confinement_gate.py 2>/dev/null && active=1
  [ "$active" = 1 ] && [ -s "$B/_cov_p5_conf.json" ] && break
  if [ $((w % 900)) -eq 0 ]; then
    say "  active_probe=$active  pass_summary=$([ -s "$B/_cov_p5_conf.json" ] && echo yes || echo no)"
  fi
  sleep 60; w=$((w+60))
  [ "$w" -ge 21600 ] && { say "held 6 h; NOT run — reporting instead of guessing"; exit 0; }
done
say "both preconditions met"
say "  gate baseline was:"; sed 's/^/    /' "$B/_active_gate_baseline.txt" >> "$L"
say "  gate now: $(md5sum /home/dev/project/src/test_confinement_gate.py)"

( cd /home/dev/project/src && timeout 1800 python3 -W ignore -u test_confinement_gate.py \
    > "$B/_test_confinement_gate.out" 2>&1 )
rc=$?
say "src/test_confinement_gate.py rc=$rc  $(tail -1 "$B/_test_confinement_gate.out")"
[ "$rc" -eq 0 ] || { say "active gate suite RED — rig run NOT started"; exit 0; }

python3 -u "$B/_mk_rig_declared.py" >> "$L" 2>&1 || { say "could not build the rig input"; exit 1; }

say "rig replays via tools/slot (CONCOLIC_SLOTS=2, ~1.2 GB each), caged 3G"
free -g | sed -n 2p >> "$L"
cage pxriggate.scope 3G \
  env CONCOLIC_SLOTS=2 PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  timeout 10800 python3 -u \
    /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
    "$B/assumption_manifest.json" --declared "$B/_rig_declared.json" \
    --json-out "$B/_rig_gate_results.json" \
  > "$B/_rig_gate.log" 2>&1
caged_verdict pxriggate.scope "$B/_rig_gate.log" 'RESULT:' >> "$L"
grep -E '^RESULT:' "$B/_rig_gate.log" >> "$L" 2>/dev/null
say "pipeline6 done"
