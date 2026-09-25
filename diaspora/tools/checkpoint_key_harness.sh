#!/bin/bash
# Whole-stage checkpoint-key harness for reports/diaspora/results3/*/_engine_section.py.
# STUB engine only (see _stub_runner.py): nothing real is run, no audits, no JRuby.
set -u
S="$(cd "$(dirname "$0")" && pwd)"
B="${HARNESS_TMP:-${TMPDIR:-/tmp}}/ckpt_key_harness/batch"; rm -rf "$B"; mkdir -p "$B/auditdir"
SRC="${1:-/home/dev/project/reports/diaspora/results3/posts_show/_engine_section.py}"
cp "$SRC" "$B/_engine_section.py"

printf 'ORIGINAL SHIM TESTS\nSHIM_TESTS = {}\n'            > "$B/shim_tests.rb"
printf 'module ConcolicTargets; end\n'                     > "$B/concolic_targets.rb"
printf '# targets\n'                                       > "$B/targets.rb"
printf '{"calls": []}\n'                                   > "$B/concrete_run.json"
printf '{}\n'                                              > "$B/concrete_aliases.json"
printf '{"batch_dir": "%s"}\n' "$B"                        > "$B/assumption_manifest.json"
printf '[]\n'                                              > "$B/_shims_extracted.json"
printf '#!/usr/bin/env python3\nprint("audit v1")\n'       > "$B/auditdir/my_audit.py"
printf '{"coverage_complete": true, "missing_branches": 0, "assumptions": []}\n' > "$B/summary_in.json"
# NOTE: coverage_assumptions.py / _confinement_withdrawn.json / _prior_footprints.json
# are deliberately ABSENT at the start -- the key must digest them as absent, not error.
cat > "$B/completion_config.json" <<CFG
{
  "batch_dir": "$B",
  "workdir": "/home/dev/project",
  "extract_cmd": "ruby /home/dev/project/src/ruby_runtime/completion_checker/shim_extractor.rb $B/targets.rb $B/concolic_targets.rb",
  "test_cmd": "false {shims} {tests} {out}",
  "shim_tests": "$B/shim_tests.rb",
  "concrete_run": "$B/concrete_run.json",
  "note_check_cmd": "true {run} {batch} --aliases $B/concrete_aliases.json",
  "assumption_cfg": "$B/assumption_manifest.json",
  "assumption_cmd": "true {cfg} {declared} {out}",
  "extra_audit_cmds": [{"name": "my_audit", "cmd": "python3 $B/auditdir/my_audit.py {batch}"}],
  "audit_timeout": 21600
}
CFG

PASS=0; FAIL=0
step() {           # step <label> <expect RUN|SKIP>
  local label="$1" expect="$2"
  out=$(cd "$B" && env -i PATH=/usr/bin:/bin HOME=/tmp ENGINE_CHECKPOINT=1 \
        SUMMARY_IN="$B/summary_in.json" SUMMARY_OUT="$B/out.json" RUN_TAG="$label" \
        ${EXTRA_ENV:-} python3 "$S/_checkpoint_key_stub_runner.py" "$B/_engine_section.py" 2>&1)
  rc=$?
  if grep -q STUB-ATTACH-RAN <<<"$out"; then got=RUN; else got=SKIP; fi
  [ $rc -ne 0 ] && got="ERROR(rc=$rc)"
  k=$(head -1 "$B/out.json.checkpoint_key" 2>/dev/null)
  if [ "$got" = "$expect" ]; then PASS=$((PASS+1)); v="ok  "; else FAIL=$((FAIL+1)); v="FAIL"; fi
  printf '%s  %-46s expect %-4s got %-10s key %s\n' "$v" "$label" "$expect" "$got" "${k:0:12}"
  [ "$got" != "$expect" ] && { echo "----- output -----"; echo "$out"; echo "------------------"; }
  LAST_OUT="$out"
}

echo "=== whole-stage checkpoint key harness (stub engine) ==="
echo "section under test: $SRC"; echo
step "1 cold, no sidecar"                              RUN
step "2 unchanged inputs"                              SKIP
touch "$B/shim_tests.rb"
step "3 shim_tests.rb mtime-only touch"                SKIP     # content digest, not mtime
printf 'PORTED SHIM TEST\n' >> "$B/shim_tests.rb"
step "4 shim_tests.rb CONTENT changed (the §3 case)"   RUN
step "5 unchanged again"                               SKIP
printf 'ORIGINAL SHIM TESTS\nSHIM_TESTS = {}\n'        > "$B/shim_tests.rb"
step "6 shim_tests.rb RESTORED (a restore is a change)" RUN
step "7 unchanged after the restore"                   SKIP
printf '#!/usr/bin/env python3\nprint("audit v2")\n'   > "$B/auditdir/my_audit.py"
step "8 extra_audit_cmds SCRIPT SOURCE changed"        RUN
step "9 unchanged"                                     SKIP
printf '[{"key": "X"}]\n'                              > "$B/_shims_extracted.json"
step "10 _shims_extracted.json changed"                RUN
printf '# withdrawn\n[]\n'                             > "$B/_confinement_withdrawn.json"
step "11 optional file APPEARS (was ABSENT)"           RUN
rm -f "$B/_confinement_withdrawn.json"
step "12 optional file removed again"                  RUN
step "13 unchanged (optional file absent, no error)"   SKIP
printf 'module ConcolicTargets; X = 1; end\n'          > "$B/concolic_targets.rb"
step "14 concolic_targets.rb changed"                  RUN
step "15 unchanged"                                    SKIP
printf '{"coverage_complete": true, "missing_branches": 1, "assumptions": []}\n' > "$B/summary_in.json"
step "16 SUMMARY_IN changed (v1 caught this too)"      RUN
step "17 unchanged"                                    SKIP
EXTRA_ENV="COMPLETION_AUDIT_TIMEOUT=900"
step "18 COMPLETION_AUDIT_TIMEOUT set"                 RUN
step "19 same env knob, unchanged"                     SKIP
EXTRA_ENV="COMPLETION_AUDIT_TIMEOUT=900 ACHK_PROBE_BATCH=8"
step "20 ACHK_PROBE_BATCH added"                       RUN
EXTRA_ENV="COMPLETION_AUDIT_TIMEOUT=900 ACHK_PROBE_BATCH=8 CONCOLIC_PROBE_WORKERS=2"
step "21 CONCOLIC_PROBE_WORKERS added"                 RUN
EXTRA_ENV="COMPLETION_AUDIT_TIMEOUT=900 ACHK_PROBE_BATCH=8 CONCOLIC_PROBE_WORKERS=2 ACHK_HEARTBEAT_S=5"
step "22 ACHK_HEARTBEAT_S (denylisted: no re-run)"     SKIP
EXTRA_ENV=""
step "23 env knobs cleared again"                      RUN

echo
echo "--- the [checkpoint] key inputs line of the last run ---"
grep -o '\[checkpoint\] key inputs: .*' <<<"$LAST_OUT" | head -1 | cut -c1-1400
echo
echo "--- sidecar written (head) ---"
head -20 "$B/out.json.checkpoint_key"
echo "  ... $(grep -c '^#   ' "$B/out.json.checkpoint_key") input rows recorded"
echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
