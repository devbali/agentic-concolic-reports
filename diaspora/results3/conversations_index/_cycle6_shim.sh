#!/bin/bash
set -u
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
echo "=== shim tests $(date +%H:%M:%S)"
JRUBY_OPTS=--debug flock /tmp/concolic-slot.lock scripts/diaspora-concolic \
  /home/dev/project/src/ruby_runtime/completion_checker/shim_test_runner.rb \
  "$B/_shims6.json" "$B/shim_tests.rb" "$B/_shim_results6.json" > "$B/_shim6.log" 2>&1
echo "shimtest EXIT=$?"
python3 - <<'PY'
import json, collections
r=json.load(open("/home/dev/project/reports/diaspora/results3/conversations_index/_shim_results6.json"))
items=r if isinstance(r,list) else (r.get("results") or [])
c=collections.Counter(x.get("verdict") for x in items)
print("VERDICTS", dict(c))
for x in items:
    if x.get("verdict") not in ("PASS","PROTOCOL"):
        print("  RED", x.get("key"), x.get("verdict"), str(x.get("detail"))[:200])
PY
echo SHIM6_DONE
