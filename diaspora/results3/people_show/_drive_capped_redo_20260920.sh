#!/usr/bin/env bash
# people_show — targeted redrive of the TWO scenarios that hit FAST_BUDGET
# without draining in the r2 parallel drive (2026-09-20):
#   auth_self_html: runs=4842 paths=1835 drained=false capped_by=TIME_BUDGET
#   auth_other_html: runs=4921 paths=1594 drained=false capped_by=TIME_BUDGET
#
# Box freed up (comments_index gate finished, load ~50 -> ~6) so these two
# get a large budget to actually drain. Does NOT touch the other 7
# scenarios' dumps (KEEP_DUMPS=1, no wipe) and does NOT touch the still-
# running ps-drive-r2.service (anon_mobile_presenter / auth_mobile), which
# owns its own two JRuby PIDs under its own 8h SLOW_BUDGET.
#
# run_dse.rb's worklist is NOT persisted between invocations (stack starts
# fresh from root seeds each launch), so this is a from-scratch DSE replay
# for these two scenarios, not a resume. It is expected to be deterministic
# (fixed seeds, no randomness) and therefore to reproduce the same
# trajectory up to the previous cap and then continue past it, so
# overwriting dump_auth_self_html_*.json / dump_auth_other_html_*.json with
# the same index range is safe.
set -u
cd /home/dev/project/ruby_examples/dse-apps/apps/diaspora || exit 1
B=/home/dev/project/reports/diaspora/results3/people_show
L=$B/_drive_parallel_logs

export PATH="/home/dev/tools/jdk-21.0.5/bin:/home/dev/tools/jruby-9.3.0.0/bin:$PATH"
export JAVA_HOME="/home/dev/tools/jdk-21.0.5"
export GEM_HOME="/home/dev/.gem/jruby/2.6.0"
export RAILS_ENV="${RAILS_ENV:-concolic}"

pids=""
for s in auth_self_html auth_other_html; do
  SCENARIO_ONLY=$s SUMMARY_SUFFIX="_$s" KEEP_DUMPS=1 \
  MAX_RUNS=1000000 TIME_BUDGET="${CAPPED_BUDGET:-28800}" \
    bundle exec jruby -I/home/dev/project/ruby_examples/dse-apps/apps/diaspora \
      "$B/run_dse.rb" > "$L/${s}_redo20260920.log" 2>&1 &
  pids="$pids $!"
done

echo "launched pids:$pids"
rc=0
for p in $pids; do wait "$p" || rc=1; done
echo "CAPPED-REDO-DONE rc=$rc"
