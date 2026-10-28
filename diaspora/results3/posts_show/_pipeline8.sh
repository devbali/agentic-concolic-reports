#!/bin/bash
# PIPELINE 8 — the GATE-AWARE re-census, held until the extended keying lands.
# Signal (coordinator): gate fixtures in src/test_confinement.py — "two gates
# with disjoint downstreams". Same snapshot, identical flags, so the two
# `remaining` figures are directly comparable.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_pipeline8.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
md5sum /home/dev/project/src/concolic_engine/coverage.py /home/dev/project/src/test_confinement.py > "$B/_gateaware_baseline.txt"
say "baseline:"; sed 's/^/  /' "$B/_gateaware_baseline.txt" >> "$L"

w=0
while ! grep -qiE 'def test_[a-z0-9_]*gate[a-z0-9_]*(disjoint|downstream)|disjoint downstream|two gates with disjoint' \
      /home/dev/project/src/test_confinement.py 2>/dev/null; do
  [ $((w % 900)) -eq 0 ] && say "  waiting for the GATE-AWARE keying (coverage.py mtime $(stat -c %y /home/dev/project/src/concolic_engine/coverage.py | cut -d. -f1))"
  sleep 60; w=$((w+60))
  [ "$w" -ge 28800 ] && { say "held 8 h — NOT run; reporting instead"; exit 0; }
done
say "GATE-AWARE keying detected"; say "  now: $(md5sum /home/dev/project/src/concolic_engine/coverage.py)"
# The keying lands BEFORE it is green — the fable agent is still working. Keep
# WATCHING until the suite passes rather than giving up on the first red read
# (pipeline 8's first attempt exited at 05:38 on exactly that).
rc=1; t=0
while [ "$rc" -ne 0 ]; do
  ( cd /home/dev/project/src && timeout 1800 python3 -W ignore -u test_confinement.py \
      > "$B/_test_confinement_gateaware.out" 2>&1 )
  rc=$?
  if [ "$rc" -ne 0 ]; then
    [ $((t % 900)) -eq 0 ] && say "  gate-aware suite RED (rc=$rc) — waiting, NOT running the census: $(tail -1 "$B/_test_confinement_gateaware.out")"
    sleep 120; t=$((t+120))
    [ "$t" -ge 28800 ] && { say "gate-aware suite still RED after 8 h — NOT run; reporting"; exit 0; }
  fi
done
say "src/test_confinement.py rc=0  $(tail -1 "$B/_test_confinement_gateaware.out")"
say "  green at: $(md5sum /home/dev/project/src/concolic_engine/coverage.py)"

# SAME snapshot as _confinement_census.json, identical flags: the only variable
# is the keying.
say "gate-aware re-census on _snapshot_pruned_p5.txt [3500M]"
# This drive's own §16c pass must finish first, then notifications gets the
# exclusive slot for its certification pass — only then do we take it back.
# COMPANION (coordinator 2026-09-11): a census needs no exclusive slot —
# only the headroom rule. The slot gates below were removed for that reason.
wait_headroom 3 | tee -a "$L"
cage pxconfgate.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 7200 \
  python3 -u /home/dev/project/reports/diaspora/tools/confinement_census.py "$B" \
      --json-out "$B/_confinement_census_gateaware.json" \
  > "$B/_confinement_census_gateaware.log" 2>&1
caged_verdict pxconfgate.scope "$B/_confinement_census_gateaware.log" 'EXACT:|remaining' >> "$L"
python3 - <<'PY' >> "$L" 2>&1
import json
B="/home/dev/project/reports/diaspora/results3/posts_show/"
a=json.load(open(B+"_confinement_census.json"))
b=json.load(open(B+"_confinement_census_gateaware.json"))
print("\n=== §16c keying: OLD (other-decisions) -> NEW (gate-aware) ===")
for k in ("decided","undecidable","confined_decisions","disqualified_decisions"):
    print(f"  {k:24s} {a.get(k)} -> {b.get(k)}")
print(f"  pairs                    {a['pairs']} -> {b['pairs']}")
for k in ("cliques","satisfiable","covered","remaining","wide","wide_mass"):
    print(f"  census.16c.{k:14s} {a['census']['16c'][k]} -> {b['census']['16c'][k]}")
PY
say "pipeline8 done"
