#!/usr/bin/env bash
# Seed-exact replay of ONE variant of ONE endpoint under RAILS_ENV=concolic_mod
# with the RC-1 prototype target layer.
#
#   _drive_variant.sh <endpoint> <variant> <runner_dir> <out_dir>
#
# Mirrors scripts/diaspora-concolic exactly except RAILS_ENV; the shared script
# is deliberately NOT edited (other agents are driving posts_show / people_show
# through it right now).
set -uo pipefail

EP="$1"; V="$2"; RUNNER_DIR="$3"; OUT="$4"

RD=/home/dev/project/reports/diaspora/results3/_redrive_20260919
APP=/home/dev/project/ruby_examples/dse-apps/apps/diaspora
LOG=$RD/_logs

mkdir -p "$OUT" "$LOG"
cd "$APP" || exit 1

export PATH="/home/dev/tools/jdk-21.0.5/bin:/home/dev/tools/jruby-9.3.0.0/bin:$PATH"
export JAVA_HOME="/home/dev/tools/jdk-21.0.5"
export GEM_HOME="/home/dev/.gem/jruby/2.6.0"
export RAILS_ENV=concolic_mod

SEEDS="$RD/_seeds/${EP}__${V}.json"
N=$(python3 -c "import json;print(len(json.load(open('$SEEDS'))))")
echo "=== $EP/$V : $N seeds : start $(date -Is) ==="

VARIANT="$V" VARIANTS="$V" \
EXTRA_SEEDS_JSON="$SEEDS" \
SEEDS_ONLY=1 \
LABEL_SUFFIX=_MOD919 \
MAX_RUNS=$((N + 10)) \
TIME_BUDGET=28800 \
DUMP_OUT="$OUT" \
  bundle exec jruby -I. "$RUNNER_DIR/run_dse.rb" \
  > "$LOG/${EP}_${V}.log" 2>&1
RC=$?

echo "=== $EP/$V : rc=$RC : end $(date -Is) : dumps_with_this_variant=$(ls "$OUT" | grep -c "^dump_${V}_") ==="
cp -p "$RUNNER_DIR/exploration_summary.json" \
      "$LOG/exploration_summary_${EP}_${V}_MOD919.json" 2>/dev/null
exit $RC
