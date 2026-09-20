#!/usr/bin/env bash
# people_show CONCRETE GROUND TRUTH (RUNBOOK Phase 5) — 2026-09-19.
#
# One invocation PER SCENARIO, deliberately: a scenario body can abort the JVM
# natively and a JVM abort takes the whole process with it, so per-scenario
# isolation is what makes a crasher name itself (concrete_run_probe.rb's own
# CRASH ISOLATION note; the same rule as the DSE runner's per-seed isolation).
# `mock_note_check` accepts a merged list, so the parts are concatenated at the
# end into the single concrete_run.json the completion config points at.
#
# MUST run AFTER the corpus is final: _concrete_targets.rb derives the target
# list from the corpus (`targets_from_corpus`), so a partial corpus yields a
# ground truth measured against the wrong target set.
set -u
B=/home/dev/project/reports/diaspora/results3/people_show
L=$B/_concrete_logs
mkdir -p "$L"
cd /home/dev/project/ruby_examples/dse-apps/apps/diaspora || exit 1
export PATH="/home/dev/tools/jdk-21.0.5/bin:/home/dev/tools/jruby-9.3.0.0/bin:$PATH"
export JAVA_HOME="/home/dev/tools/jdk-21.0.5"
export GEM_HOME="/home/dev/.gem/jruby/2.6.0"
export RAILS_ENV=concolic
export JAVA_TOOL_OPTIONS=""
# CI_EXECUTOR=1: the rig dispatches through ActionController::TestCase, which
# never runs ActionDispatch::Executor, so AR's query cache (an executor hook)
# is absent and every repeated identical statement is recorded twice. The real
# middleware stack DOES include the executor. Wrapping makes the ground truth
# match what a real request would record. (M-18, ported from people_stream.)
export CI_EXECUTOR="${CI_EXECUTOR:-1}"
export CONCRETE_COVERAGE="${CONCRETE_COVERAGE:-1}"

rc=0
for s in anon_handle anon_json auth_self_html auth_json; do
  echo "=== concrete: $s"
  JRUBY_OPTS="--debug -J-Xss16m" bundle exec jruby \
    -I/home/dev/project/ruby_examples/dse-apps/apps/diaspora \
    /home/dev/project/reports/diaspora/tools/concrete_checker/concrete_run_probe.rb \
    "$B/concrete_manifest_${s}.rb" > "$L/$s.log" 2>&1 || rc=1
  # the probe writes concrete_run.json NEXT TO THE MANIFEST; keep each part
  if [ -f "$B/concrete_run.json" ]; then
    mv "$B/concrete_run.json" "$B/concrete_run_${s}.json"
    echo "    -> concrete_run_${s}.json"
  else
    echo "    !! no output for $s (see $L/$s.log)"; rc=1
  fi
done

python3 "$B/_merge_concrete_runs.py"
echo "CONCRETE-EXIT=$rc"
exit $rc
