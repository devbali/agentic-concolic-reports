#!/bin/bash
# C22 — re-run the engine's shim extractor + shim test runner for this batch.
# Ported from `_shim_run.sh`; only the scratch paths and the log stamp differ.
# Verdict line: `C22-SHIMRUN-DONE`.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project || exit 2
B=/home/dev/project/reports/diaspora/results3/notifications_index
S="${C22_SCRATCH:?set C22_SCRATCH}"
LOG="$B/_c22_shim_run.log"; echo "start $(date -Is)" > "$LOG"
ruby /home/dev/project/src/ruby_runtime/completion_checker/shim_extractor.rb \
     "$B/targets.rb" "$B/concolic_targets.rb" > "$S/shims.json" 2>>"$LOG"
echo "extracted $(python3 -c "import json;print(len(json.load(open('$S/shims.json'))))" 2>>"$LOG") shims" >> "$LOG"
flock /tmp/concolic-slot.lock env JRUBY_OPTS=--debug scripts/diaspora-concolic \
  /home/dev/project/src/ruby_runtime/completion_checker/shim_test_runner.rb \
  "$S/shims.json" "$B/shim_tests.rb" "$S/shim_results.json" >> "$LOG" 2>&1
echo "runner exit=$?" >> "$LOG"
python3 -c "
import json,collections
r=json.load(open('$S/shim_results.json'))
c=collections.Counter(x['verdict'] for x in r)
print('TALLY', dict(c))
for x in r:
    if x['verdict'] not in ('PASS','PROTOCOL'):
        print(' ', x['verdict'], x['key'], str(x.get('detail') or x.get('missed_lines') or x.get('targets_reached'))[:200])
" >> "$LOG" 2>&1
echo "C22-SHIMRUN-DONE $(date -Is)" >> "$LOG"
