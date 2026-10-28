#!/bin/bash
# PIPELINE 5 — the confinement line (coordinator 2026-09-11). Strictly ONE job
# at a time, every job through `cage`, this drive's share <= 3 G, `free -g` and
# the slice's MemoryCurrent checked before each launch.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_pipeline5.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
budget(){ say "  free -g: $(free -g | awk 'NR==2{print "avail="$7"G"}')  slice: $(systemctl --user show concolic-cov.slice -p MemoryCurrent --value | awk '{printf "%.1fG", $1/1073741824}')"; }
# Coordinator precondition for the 3.5 G census: launch ONLY when the OTHERS
# hold <= 5 G of the slice. This drive's own footprint is zero at that moment
# (strictly one job at a time), so the slice's MemoryCurrent IS the others'.
wait_for_room(){
  local capG="${1:-5}"
  while :; do
    local cur; cur=$(systemctl --user show concolic-cov.slice -p MemoryCurrent --value)
    if [ -n "$cur" ] && [ "$cur" -le $((capG*1073741824)) ]; then
      say "  room: slice MemoryCurrent=$(awk -v c=$cur 'BEGIN{printf "%.2fG", c/1073741824}') <= ${capG}G — launching"
      return 0
    fi
    say "  waiting for room: slice MemoryCurrent=$(awk -v c=$cur 'BEGIN{printf "%.2fG", c/1073741824}') > ${capG}G"
    sleep 60
  done
}

while systemctl --user is-active pxaudits3.scope >/dev/null 2>&1; do sleep 30; done
say "relaunch; audits stage already exited"
grep -n 'EXIT=' "$B/_c7_audits.log" 2>/dev/null | tail -12 >> "$L"

# ---- 1. X12 equivalence (OLD vs NEW, byte for byte) -----------------------
# Stage 1 (X12 equivalence) COMPLETED 2026-09-11 03:07 and is PROVEN:
# OLD == NEW == NEW(DUMP_LIST), md5 4de1fdce0492c05659ee74a466d38d84, 821 bytes,
# on 18 421 dumps / 1 104 139 clean notes (the first "DIFFER" was this
# harness comparing systemd-run's own banner line; stripped and re-diffed).
say "1: X12 equivalence — already PROVEN at 03:07, not re-run"


# ---- GATE: the STRICT confinement definition must have LANDED ------------
# The owner tightened CONFINEMENT to STRICT one-sidedness (a shape is in a
# decision's footprint only if, corpus-wide, it NEVER appears with that
# decision on its non-enabling side; any two-sided shape makes the decision
# not confined at all; the tripwire is a full counterexample search at load).
# A census run BEFORE that lands measures the WEAK definition and would
# overstate the collapse. Signal, per the coordinator: the counterexample-
# search tests in src/test_confinement.py.
wait_for_strict(){
  local waited=0
  while ! grep -qE '^def test_[a-z0-9_]*counterexample|counterexample search' \
        /home/dev/project/src/test_confinement.py 2>/dev/null; do
    if [ "$waited" -ge 14400 ]; then
      say "STRICT DID NOT LAND within 4 h -- stages 2-4 NOT RUN."
      say "  Running them now would produce WEAK-definition numbers and this"
      say "  drive would have to label them superseded. Reporting instead."
      return 1
    fi
    [ $((waited % 600)) -eq 0 ] && say "  waiting for STRICT confinement in src/ (coverage.py mtime $(stat -c %y /home/dev/project/src/concolic_engine/coverage.py 2>/dev/null | cut -d. -f1))"
    sleep 60; waited=$((waited+60))
  done
  say "STRICT confinement detected in src/test_confinement.py"
  say "  coverage.py      $(md5sum /home/dev/project/src/concolic_engine/coverage.py)"
  say "  test_confinement $(md5sum /home/dev/project/src/test_confinement.py)"
  say "  baseline was:"; sed 's/^/    /' "$B/_strict_baseline.txt" >> "$L"
  # and it must be GREEN before any number is taken from it
  ( cd /home/dev/project/src && timeout 1800 python3 -W ignore -u test_confinement.py \
      > "$B/_test_confinement.out" 2>&1 )
  local rc=$?
  say "  src/test_confinement.py rc=$rc  $(tail -1 "$B/_test_confinement.out")"
  [ "$rc" -eq 0 ] || { say "STRICT tests are RED -- stages 2-4 NOT RUN."; return 1; }
  return 0
}
if ! wait_for_strict; then
  say "pipeline5 stopped after stage 1 (X12) by the strict-confinement gate"
  exit 0
fi

# ---- 2. CONFINEMENT CENSUS on p5 (identical flags to _enum_p5_cost.log) ----
# NOTE: the tool's own docstring says a p5-sized census peaked at 3.3 GB, which
# is ABOVE this drive's 3 G share. Attempted at 3 G as the compliant run; if the
# cage kills it, that is REPORTED as a budget conflict, not retried larger
# without authorization.
# 3.5 G AUTHORIZED by the coordinator (2026-09-11) because the tool's own
# documented peak is 3.3 GB; every OTHER job in this pipeline stays at <= 3 G.
say "2: confinement census (p5) [cap 3500M, authorized; peak documented 3.3 GB]"; budget
wait_for_room 5
wait_no_pass | tee -a "$L"
cage pxconf.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 5400 \
  python3 -u /home/dev/project/reports/diaspora/tools/confinement_census.py "$B" \
      --json-out "$B/_confinement_census.json" \
  > "$B/_confinement_census.log" 2>&1
caged_verdict pxconf.scope "$B/_confinement_census.log" 'EXACT:|remaining' >> "$L"

# ---- 3. my canonicalised footprint re-run (the cross-check's 791) ---------
say "3: footprint re-run, canonicalised [cap 3G]"; budget
wait_no_pass | tee -a "$L"
cage pxfp2.scope 3G \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 3600 python3 -u "$B/_footprint_census.py" \
  > "$B/_footprint_census.log" 2>&1
caged_verdict pxfp2.scope "$B/_footprint_census.log" 'FOOTPRINT CENSUS' >> "$L"
python3 -u "$B/_sep_pairs.py" > "$B/_sep_pairs.log" 2>&1
tail -12 "$B/_sep_pairs.log" >> "$L"

# ---- 4. the real coverage pass, confinement-aware -------------------------
say "4: coverage_report.py MMC=16 on the pruned p5 list [cap 3G]"; budget
wait_no_pass | tee -a "$L"
cage pxcovC.scope 3G \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" SUMMARY_OUT="$B/_cov_p5_conf.json" \
      SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=16 PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= python3 -u "$B/coverage_report.py" \
  > "$B/_covC_p5_conf.log" 2>&1
caged_verdict pxcovC.scope "$B/_covC_p5_conf.log" '^COMPLETE=' >> "$L"
grep -E '^\[assumptions\]|^(COMPLETE|GENUINE|dumps_loaded|DEMAND_SETS|peak RSS|wrote)|confine' \
  "$B/_covC_p5_conf.log" >> "$L" 2>/dev/null
say "pipeline5 done"
