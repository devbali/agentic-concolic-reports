#!/usr/bin/env bash
# people_show F6 re-drive (2026-09-18 reopen). Full DSE exploration with the
# SYMBOLIC principal (targets.rb#signed_in_user F6 repair).
#
# TIME_BUDGET is raised from the original campaign's 1200s to 3600s per
# scenario because the two mobile scenarios (anon_mobile_presenter,
# auth_mobile) were TIME_BUDGET-capped in the original run and the symbolic
# principal adds flippable vars, which can only grow the worklist.
set -u
cd /home/dev/project
export TIME_BUDGET="${TIME_BUDGET:-3600}"
export MAX_RUNS="${MAX_RUNS:-1000000}"
export COMPOSE_CAP="${COMPOSE_CAP:-6}"
exec reports/diaspora/tools/slot scripts/diaspora-concolic \
  /home/dev/project/reports/diaspora/results3/people_show/run_dse.rb
