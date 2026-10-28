#!/bin/bash
# comments_index — CONFINEMENT OFF (2026-09-13).
#
# `docs/CONFINEMENT_PRECISION_20260913.md` §5.2/§6 measures confinement as
# FREE on this endpoint: COMPLETE=True; MISSING=0 with it off, on, and
# on-with-15-withdrawn. It buys 5 demand sets out of 85 in exchange for 46
# inferred licences the gate refuted 15 of, and 0 % of its pairs were probed
# beyond those 46. So the endpoint is re-closed with the STRICTLY WEAKER
# assumption set: no confinement at all.
#
# Two stages, both checkpointed, both detached in concolic-cov.slice, each
# gated on `free -g >= 4` AND `(live MemoryMax - slice MemoryCurrent) >= cap`.
#
#   STAGE 0  CONTROL, cap 4G. The SHIPPED knobs (confinement on, 15
#            withdrawn) re-run under TODAY's engine — which gained the C2/C3
#            flags at 21:26 — with both flags at their defaults. Its coverage
#            layer must equal the shipped one line for line. This is the
#            endpoint-scale proof that "flags off == today, byte for byte";
#            the 328 src/ unit tests are the cheap half of it.
#   STAGE 1  CONFINEMENT=0 coverage pass, cap 4G -> _cov_CONFOFF_20260913.json
#   STAGE 2  the engine section on stage 1's summary, cap 6G ->
#            coverage_summary.json  (the record)
#
# STAGE 2 is skipped unless STAGE 1 reproduces COMPLETE=True;MISSING=0 — if
# anything regresses this script STOPS rather than forcing the endpoint.
set +e
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/comments_index
S=/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/scratchpad
L=$B/_confoff_20260913.log
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
: > "$L"

gate() {   # $1 = cap in MB
  local cap=$1 i=0 fg cur mx head
  while :; do
    fg=$(free -g | awk '/^Mem/{print $7}')
    cur=$(systemctl --user show concolic-cov.slice -p MemoryCurrent --value 2>/dev/null)
    mx=$(systemctl --user show concolic-cov.slice -p MemoryMax --value 2>/dev/null)
    case "$cur" in ''|*[!0-9]*) cur=0;; esac
    case "$mx"  in ''|*[!0-9]*|infinity) mx=$((19*1073741824));; esac
    head=$(( (mx - cur) / 1048576 ))
    if [ "${fg:-0}" -ge 4 ] && [ "$head" -ge "$cap" ]; then
      say "LAUNCH: free=${fg}G cage_headroom=${head}MB (MemoryMax=$((mx/1048576))MB) cap=${cap}MB"
      return 0
    fi
    [ $((i % 10)) -eq 0 ] && say "WAIT: free=${fg}G (need >=4) headroom=${head}MB (need >=${cap}MB)"
    i=$((i+1)); sleep 30
  done
}

probe_rate() {   # the posts_show P26 gate must not be starved
  local n1 t1 n2 t2
  n1=$(grep -c "probe batch" /home/dev/project/reports/diaspora/results3/posts_show/_p26_gate_v2.log)
  t1=$(date +%s); sleep 120
  n2=$(grep -c "probe batch" /home/dev/project/reports/diaspora/results3/posts_show/_p26_gate_v2.log)
  t2=$(date +%s)
  say "P26 gate: $(( (n2-n1)*40 )) probes in $((t2-t1))s = $(awk "BEGIN{printf \"%.2f\", ($n2-$n1)*40/($t2-$t1)}") probes/s"
}

cp -p "$B/coverage_summary.json" "$B/_bak_coverage_summary_pre_confoff_20260913.json"
say "backed up the shipped summary"
say "shipped coverage layer: $(python3 -c "
import json;d=json.load(open('$B/coverage_summary.json'))
print(';'.join(f'{k}={d.get(k)}' for k in ('coverage_complete','tree_nodes','missing_branches','demand_sets','total_runs','corpus_dumps','total_path_conditions','truncated','solver_lost')))")"
probe_rate

# ─────────────────────────────────────────────────────────── STAGE 0 CONTROL
gate 4096
say "STAGE 0 CONTROL: shipped knobs under today's engine (flags default OFF)"
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax=4G -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_cov_CONTROL_20260913.time" \
  env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= CONCOLIC_SLOTS=1 \
      SKIP_COMPLETION=1 SUMMARY_OUT="$S/_ci_control.json" \
      COVERAGE_CHECKPOINT="$B/_cov_control_20260913.ckpt.jsonl" \
      python3 -u "$B/coverage_report.py" > "$B/_cov_CONTROL_20260913.log" 2>&1
say "STAGE 0 exit=$?"
grep -E '^(COMPLETE=|DEMAND_SETS=|CONF )' "$B/_cov_CONTROL_20260913.log" | tee -a "$L"

# ────────────────────────────────────────────────────── STAGE 1 CONFINEMENT=0
gate 4096
say "STAGE 1: CONFINEMENT=0 coverage pass"
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax=4G -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_cov_CONFOFF_20260913.time" \
  env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= CONCOLIC_SLOTS=1 \
      CONFINEMENT=0 \
      SKIP_COMPLETION=1 SUMMARY_OUT="$B/_cov_CONFOFF_20260913.json" \
      COVERAGE_CHECKPOINT="$B/_cov_confoff_20260913.ckpt.jsonl" \
      python3 -u "$B/coverage_report.py" > "$B/_cov_CONFOFF_20260913.log" 2>&1
say "STAGE 1 exit=$?"
grep -E '^(COMPLETE=|DEMAND_SETS=|CONF )' "$B/_cov_CONFOFF_20260913.log" | tee -a "$L"

if ! grep -q '^COMPLETE=True;NODES=84;MISSING=0;BLOCKING=0;PCS=928746' "$B/_cov_CONFOFF_20260913.log"; then
  say "STOP: the CONFINEMENT=0 coverage layer did NOT reproduce the closed line. Nothing else runs."
  say "CI-CONFOFF-STOPPED"
  exit 1
fi
probe_rate

# ─────────────────────────────────────────────────────── STAGE 2 ENGINE SECTION
# The whole-stage sidecar digests SUMMARY_IN, so a new SUMMARY_IN re-runs the
# stage on its own; retire any stale one anyway so there is no way to replay.
[ -f "$B/coverage_summary.json.checkpoint_key" ] && \
  mv "$B/coverage_summary.json.checkpoint_key" \
     "$B/_bak_coverage_summary.checkpoint_key_pre_confoff_20260913" && \
  say "retired the whole-stage sidecar"
cp -p "$B/_shim_results.json" "$B/_bak_shim_results_pre_confoff_20260913.json" 2>/dev/null
cp -p "$B/_assumption_results.json" "$B/_bak_assumption_results_pre_confoff_20260913.json" 2>/dev/null
cp -p "$B/_assumptions_declared.json" "$B/_bak_assumptions_declared_pre_confoff_20260913.json" 2>/dev/null

gate 6144
say "STAGE 2: engine section on the CONFINEMENT=0 summary"
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax=6G -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_engine_CONFOFF_20260913.time" \
  env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= CONCOLIC_SLOTS=1 \
      SUMMARY_IN="$B/_cov_CONFOFF_20260913.json" \
      SUMMARY_OUT="$B/coverage_summary.json" \
      ENGINE_CHECKPOINT=1 \
      ACHK_CHECKPOINT="$B/_confoff_achk_probes.ckpt.jsonl" \
      ACHK_RESULTS_JSONL="$B/_confoff_achk_rows.jsonl" \
      ACHK_INDEX_CHECKPOINT="$B/_restore2_achk_index.ckpt.jsonl" \
      ACHK_DERIVE_CHECKPOINT="$B/_confoff_achk_derive.ckpt.jsonl" \
      ACHK_HEARTBEAT_S=60 \
      COMPLETION_AUDIT_TIMEOUT=21600 \
      python3 -u "$B/_engine_section.py" > "$B/_engine_CONFOFF_20260913.log" 2>&1
say "STAGE 2 exit=$?"
tail -70 "$B/_engine_CONFOFF_20260913.log" | tee -a "$L"
grep -E '^ENGINE SECTION DONE' "$B/_engine_CONFOFF_20260913.log" >/dev/null \
  && say "ENGINE-SECTION-VERDICT-OK" || say "ENGINE-SECTION-VERDICT-MISSING **FAIL**"
grep -E 'Maximum resident|Elapsed' "$B"/_cov_{CONTROL,CONFOFF}_20260913.time \
  "$B/_engine_CONFOFF_20260913.time" 2>/dev/null | tee -a "$L"
probe_rate
say "CI-CONFOFF-DONE"
