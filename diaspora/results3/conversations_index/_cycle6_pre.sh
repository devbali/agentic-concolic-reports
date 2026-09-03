#!/bin/bash
# cycle 6 pre-gate: shim extract+test, note check, note fidelity, extra audits.
set -u
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
echo "=== shim extract $(date +%H:%M:%S)"
ruby src/ruby_runtime/completion_checker/shim_extractor.rb "$B/targets.rb" "$B/concolic_targets.rb" > "$B/_shims6.json" 2>"$B/_shims6.err"
echo "extract EXIT=$? shims=$(python3 -c "import json;print(len(json.load(open('$B/_shims6.json'))))" 2>/dev/null)"
echo "=== shim tests $(date +%H:%M:%S)"
JRUBY_OPTS=--debug flock /tmp/concolic-slot.lock scripts/diaspora-concolic \
  src/ruby_runtime/completion_checker/shim_test_runner.rb "$B/_shims6.json" "$B/shim_tests.rb" "$B/_shim_results6.json" \
  > "$B/_shim6.log" 2>&1
echo "shimtest EXIT=$?"
python3 - <<'PY'
import json, collections
r=json.load(open("/home/dev/project/reports/diaspora/results3/conversations_index/_shim_results6.json"))
items=r if isinstance(r,list) else (r.get("results") or [])
c=collections.Counter(x.get("verdict") for x in items)
print("VERDICTS", dict(c))
for x in items:
    if x.get("verdict") not in ("PASS","PROTOCOL"):
        print("  RED", x.get("key"), x.get("verdict"), str(x.get("detail"))[:160])
PY
echo "=== note check $(date +%H:%M:%S)"
python3 src/end_to_end_completion_checker/mock/mock_note_check.py "$B/concrete_run.json" "$B" --aliases "$B/concrete_aliases.json" > "$B/_a6_note_check.out" 2>&1
echo "note_check EXIT=$?"; tail -12 "$B/_a6_note_check.out"
echo "=== note fidelity"
/home/dev/project/venvs/queries_from_runs/bin/python reports/diaspora/tools/note_fidelity_audit.py "$B" "$B/concrete_run.json" --aliases "$B/concrete_aliases.json" > "$B/_a6_note_fidelity.out" 2>&1
echo "note_fidelity EXIT=$?"; tail -8 "$B/_a6_note_fidelity.out"
echo "=== format coverage"
python3 "$B/format_coverage_audit.py" "$B" > "$B/_a6_format.out" 2>&1; echo "format EXIT=$?"; tail -5 "$B/_a6_format.out"
echo "=== pinned text query"
python3 "$B/pinned_text_query_audit.py" "$B" > "$B/_a6_pinned.out" 2>&1; echo "pinned EXIT=$?"; tail -5 "$B/_a6_pinned.out"
echo PRE6_DONE
