#!/usr/bin/env bash
# smoke.sh — launch a sample of scaffolded endpoints and record how far each got.
#
# This is the tool that turns "scaffolded" into "verified to launch". It does
# NOT judge coverage or correctness; it answers one question per endpoint:
# does the generated runner boot, dispatch the action, and record path
# conditions?
#
#   tools/smoke.sh <endpoint-id> [<endpoint-id> ...]
#   tools/smoke.sh --all            # every scaffolded endpoint (slow: ~1 min each)
#
# Results land in entrypoints/smoke_results.json.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EP="$(dirname "$HERE")"
SCAFFOLD="$EP/scaffold"
LOGS="$EP/smoke_logs"
mkdir -p "$LOGS"

: "${MAX_RUNS:=2}"
: "${TIME_BUDGET:=120}"
export MAX_RUNS TIME_BUDGET

if [ "${1:-}" = "--all" ]; then
  mapfile -t IDS < <(cd "$SCAFFOLD" && ls -d */ | tr -d /)
else
  IDS=("$@")
fi
[ ${#IDS[@]} -eq 0 ] && { echo "usage: smoke.sh <id>... | --all"; exit 2; }

for id in "${IDS[@]}"; do
  d="$SCAFFOLD/$id"
  [ -f "$d/run_dse.rb" ] || { echo "no scaffold for $id" >&2; continue; }
  log="$LOGS/$id.log"
  start=$(date +%s)
  timeout 600 /home/dev/project/scripts/diaspora-concolic "$d/run_dse.rb" > "$log" 2>&1
  rc=$?
  end=$(date +%s)

  summary="$d/exploration_summary.json"
  if [ -f "$summary" ]; then
    printf '%-44s launched  (rc=%s, %ss)\n' "$id" "$rc" "$((end-start))"
  else
    printf '%-44s NO SUMMARY (rc=%s, %ss)\n' "$id" "$rc" "$((end-start))"
  fi
done
# The results file is built by smoke_report.py, which reads the summaries and
# logs rather than re-deriving them in shell arithmetic.
/home/dev/project/venvs/queries_from_runs/bin/python3 "$HERE/smoke_report.py"
