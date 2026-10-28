#!/bin/bash
# The SHIM LAYER on its own, so tonight's declarations get a verdict even
# though the full engine section cannot run under the 4 G cage. Same two
# commands `concolic_engine.completion` would run (extract_cmd, test_cmd from
# completion_config.json), same inputs, same output file.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
cd /home/dev/project
L="$B/_shim_run_20260911.log"; : > "$L"
echo "[$(date -Is)] extracting the shim list" >> "$L"
ruby /home/dev/project/src/ruby_runtime/completion_checker/shim_extractor.rb \
  "$B/targets.rb" "$B/concolic_targets.rb" > "$B/_shims_extracted.json" 2>>"$L"
echo "[$(date -Is)] shims extracted: $(python3 -c "import json;print(len(json.load(open('$B/_shims_extracted.json'))))")" >> "$L"
wait_alone shims >> "$L" 2>&1
cage pxshims.scope 2500M \
  env JRUBY_OPTS=--debug JAVA_TOOL_OPTIONS= \
  /home/dev/project/reports/diaspora/tools/slot scripts/diaspora-concolic \
  /home/dev/project/src/ruby_runtime/completion_checker/shim_test_runner.rb \
  "$B/_shims_extracted.json" "$B/shim_tests.rb" "$B/_shim_results_20260911.json" >> "$L" 2>&1
echo "[$(date -Is)] shim runner exit=$?" >> "$L"
python3 - <<'PY' >> "$L" 2>&1
import json, collections
p="/home/dev/project/reports/diaspora/results3/posts_show/_shim_results_20260911.json"
try:
    r=json.load(open(p))
except Exception as e:
    print("NO RESULTS:", e); raise SystemExit(1)
c=collections.Counter(v["verdict"] for v in r)
print("SHIM VERDICTS:", dict(c))
for v in r:
    if v["verdict"] not in ("PASS","PROTOCOL"):
        print("  BLOCKING", v["verdict"], v["key"], (v.get("detail") or "")[:120])
print("  W8 entry:", [v for v in r if v["key"].endswith("name_from_attrs")] or "ABSENT")
print("SHIMS DONE")
PY
