#!/usr/bin/env bash
# RC-1 seed-exact replay under RAILS_ENV=concolic_mod, for an endpoint whose
# runner writes dumps into its OWN directory (no DUMP_OUT support).
#
#   _drive_rc1.sh <endpoint> <variant> <scenario_env_name>
#
# <scenario_env_name> is VARIANTS (conversations_index) or SCENARIO_ONLY
# (people_stream) — the knob that restricts the run to a single scenario, so
# each seed is replayed only in the scenario it was originally explored in.
#
# Fresh dumps carry LABEL_SUFFIX=_RC1MOD and are moved out afterwards by the
# caller. scripts/diaspora-concolic is deliberately NOT used/edited.
set -uo pipefail

EP="$1"; V="$2"; SCEN_ENV="$3"

R3=/home/dev/project/reports/diaspora/results3
RD=$R3/_redrive_20260919
APP=/home/dev/project/ruby_examples/dse-apps/apps/diaspora
LOG=$RD/_logs

mkdir -p "$LOG"
cd "$APP" || exit 1

export PATH="/home/dev/tools/jdk-21.0.5/bin:/home/dev/tools/jruby-9.3.0.0/bin:$PATH"
export JAVA_HOME="/home/dev/tools/jdk-21.0.5"
export GEM_HOME="/home/dev/.gem/jruby/2.6.0"
export RAILS_ENV=concolic_mod

SEEDS="$RD/_seeds/${EP}__${V}.json"
N=$(python3 -c "import json;print(len(json.load(open('$SEEDS'))))")
echo "=== $EP/$V : $N seeds : start $(date -Is) ==="

env "$SCEN_ENV=$V" \
    EXTRA_SEEDS_JSON="$SEEDS" \
    SEEDS_ONLY=1 \
    LABEL_SUFFIX=_RC1MOD \
    MAX_RUNS=$((N + 10)) \
    TIME_BUDGET=28800 \
    KEEP_DUMPS=1 \
  bundle exec jruby -I. "$R3/$EP/run_dse.rb" \
  > "$LOG/${EP}_${V}_rc1.log" 2>&1
RC=$?

echo "=== $EP/$V : rc=$RC : end $(date -Is) : fresh=$(ls "$R3/$EP" | grep -c "_RC1MOD\.json$") ==="
exit $RC
