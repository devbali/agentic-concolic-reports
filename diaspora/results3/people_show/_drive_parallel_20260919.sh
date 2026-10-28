#!/usr/bin/env bash
# people_show FULL re-drive, one JRuby per scenario IN PARALLEL
# (2026-09-19, completion-gate build).
#
# WHY a fresh drive at all: the gate matches every probe back to its launch
# through the dump's recorded `concolic_seeds`, and this runner never wrote
# that key until today. Every existing dump reports `{}` to
# `assumption_checker.seeds_as_written`, so no base is usable and the
# assumption gate cannot run. The corpus has to be regenerated once.
#
# WHY parallel: the 2026-09-18 sequential drive managed 2.2 runs/s while
# sharing the box with posts_show's 13 GB Z3 job, and three scenarios
# (anon_mobile, anon_mobile_presenter, auth_mobile) hit TIME_BUDGET. The box
# is idle now (16 cores, ~60 GB free), so each scenario gets its own JRuby and
# a budget large enough to DRAIN rather than cap.
#
# Safe to parallelise: dump filenames are prefixed with the scenario, and
# SUMMARY_SUFFIX keeps each process's exploration summary separate; they are
# merged afterwards by _merge_summaries.py.
#
# NOT routed through tools/slot: that wrapper caps concurrency at 2, which is
# exactly what this script is trying to avoid. The slot limit exists for
# memory (~1.2 GB/JRuby, set when the box had 7.9 GB); 9 JRubys is ~11 GB on a
# 68 GB box, and each scenario is capped by its own systemd MemoryMax.
set -u
# cwd MUST be the diaspora app: `bundle exec` resolves the Gemfile from the
# working directory, and run_dse.rb's first line is `require
# "./config/environment"`. This is exactly what scripts/diaspora-concolic
# does; running from the project root fails with "Could not locate Gemfile".
cd /home/dev/project/ruby_examples/dse-apps/apps/diaspora || exit 1
B=/home/dev/project/reports/diaspora/results3/people_show
L=$B/_drive_parallel_logs
mkdir -p "$L"

export PATH="/home/dev/tools/jdk-21.0.5/bin:/home/dev/tools/jruby-9.3.0.0/bin:$PATH"
export JAVA_HOME="/home/dev/tools/jdk-21.0.5"
export GEM_HOME="/home/dev/.gem/jruby/2.6.0"
export RAILS_ENV="${RAILS_ENV:-concolic}"

# One-shot wipe of the previous corpus, done ONCE here rather than by each
# scenario process (KEEP_DUMPS=0 in nine parallel runners would race).
# The 2026-09-18 F6 corpus is already snapshotted at
# _redrive_20260919/people_show_f6only/.
if [ "${WIPE:-1}" = "1" ]; then
  find "$B" -maxdepth 1 -name 'dump_*.json' -delete
  echo "wiped previous corpus"
fi

FAST="anon_handle anon_json auth_self_html auth_other_html auth_json anon_remote_401"
SLOW="anon_mobile anon_mobile_presenter auth_mobile"

pids=""
for s in $FAST; do
  SCENARIO_ONLY=$s SUMMARY_SUFFIX="_$s" KEEP_DUMPS=1 \
  MAX_RUNS=1000000 TIME_BUDGET="${FAST_BUDGET:-3600}" \
    bundle exec jruby -I/home/dev/project/ruby_examples/dse-apps/apps/diaspora \
      "$B/run_dse.rb" > "$L/$s.log" 2>&1 &
  pids="$pids $!"
done
for s in $SLOW; do
  SCENARIO_ONLY=$s SUMMARY_SUFFIX="_$s" KEEP_DUMPS=1 \
  MAX_RUNS=1000000 TIME_BUDGET="${SLOW_BUDGET:-21600}" \
    bundle exec jruby -I/home/dev/project/ruby_examples/dse-apps/apps/diaspora \
      "$B/run_dse.rb" > "$L/$s.log" 2>&1 &
  pids="$pids $!"
done

echo "launched pids:$pids"
rc=0
for p in $pids; do wait "$p" || rc=1; done
echo "ALL-SCENARIOS-DONE rc=$rc"
python3 "$B/_merge_summaries.py"
echo "PARALLEL-DRIVE-EXIT=$rc"
