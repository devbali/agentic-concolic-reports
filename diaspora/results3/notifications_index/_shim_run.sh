#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
S=/tmp/claude-1000/-home-dev-project/e0395c49-56d0-42c0-af70-a3707c6552fa/scratchpad
LOG="$B/_shim_run.log"; echo "start $(date -Is)" > "$LOG"
ruby /home/dev/project/src/ruby_runtime/completion_checker/shim_extractor.rb "$B/targets.rb" "$B/concolic_targets.rb" > "$S/shims.json" 2>>"$LOG"
flock /tmp/concolic-slot.lock env JRUBY_OPTS=--debug scripts/diaspora-concolic \
  /home/dev/project/src/ruby_runtime/completion_checker/shim_test_runner.rb "$S/shims.json" "$B/shim_tests.rb" "$S/shim_results.json" >> "$LOG" 2>&1
echo "DONE $(date -Is)" >> "$LOG"
python3 -c "
import json,collections
r=json.load(open('$S/shim_results.json'))
c=collections.Counter(x['verdict'] for x in r)
print(dict(c))
for x in r:
    if x['verdict'] not in ('PASS','PROTOCOL'): print(' ', x['verdict'], x['key'], str(x.get('detail') or x.get('missed_lines') or x.get('targets_reached'))[:150])
" >> "$LOG" 2>&1
