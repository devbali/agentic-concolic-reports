#!/usr/bin/env bash
# Drive every entrypoint of the search_links_reports_profiles batch, ONE PER
# PROCESS. Process isolation matters here: links_resolve's not-found branch can
# abort the JVM (libcurl FFI SIGSEGV), and a shared process would take the rest
# of the batch down with it.
#
# Usage: ./drive_all.sh [entrypoint ...]
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SLOT=/home/dev/.claude/jobs/302ac302/tmp/concolic-slot
APP=/home/dev/project/ruby_examples/dse-apps/apps/diaspora
LOGS="$HERE/logs"
mkdir -p "$LOGS"

EPS=("$@")
if [ ${#EPS[@]} -eq 0 ]; then
  EPS=(search_search links_resolve report_index report_create report_update \
       report_destroy profiles_edit profiles_update profiles_show)
fi

for ep in "${EPS[@]}"; do
  echo "### $ep"
  ( cd "$APP" && ENTRYPOINTS="$ep" MAX_RUNS="${MAX_RUNS:-400}" \
      TIME_BUDGET="${TIME_BUDGET:-300}" \
      "$SLOT" "$HERE/run_dse.rb" ) >"$LOGS/$ep.log" 2>&1
  rc=$?
  echo "    exit=$rc  $(grep -c '^  \[dse' "$LOGS/$ep.log" 2>/dev/null) new paths"
  grep -E '^(  \[|\[stop\]|== )' "$LOGS/$ep.log" | tail -6
  # A JVM abort leaves an hs_err report in the app dir — move it next to the
  # entrypoint it belongs to instead of leaving it in the app tree.
  for f in "$APP"/hs_err_pid*.log; do
    [ -e "$f" ] || continue
    head -40 "$f" > "$HERE/$ep/jvm_crash_hs_err_head.txt"
    rm -f "$f"
  done
  rm -f "$APP"/core.* 2>/dev/null
done
