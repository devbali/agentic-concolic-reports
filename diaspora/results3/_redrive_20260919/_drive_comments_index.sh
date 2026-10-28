#!/usr/bin/env bash
# Seed-exact replay of comments_index under RAILS_ENV=concolic_mod, using the
# RC-1 prototype target layer (_proto/) that renders the model's REAL default
# projection instead of a hardcoded `"table".*`.
#
# Mirrors scripts/diaspora-concolic exactly except for RAILS_ENV; the shared
# script is deliberately NOT edited (posts_show / people_show are being driven
# through it by other agents right now).
#
# Fresh dumps go to DUMP_OUT — the original corpus in results3/comments_index/
# is never written to.
set -uo pipefail

RD=/home/dev/project/reports/diaspora/results3/_redrive_20260919
APP=/home/dev/project/ruby_examples/dse-apps/apps/diaspora
OUT=$RD/comments_index
LOG=$RD/_logs

mkdir -p "$OUT" "$LOG"
cd "$APP" || exit 1

export PATH="/home/dev/tools/jdk-21.0.5/bin:/home/dev/tools/jruby-9.3.0.0/bin:$PATH"
export JAVA_HOME="/home/dev/tools/jdk-21.0.5"
export GEM_HOME="/home/dev/.gem/jruby/2.6.0"
export RAILS_ENV=concolic_mod

for V in anon_json anon_mobile auth_json auth_mobile; do
  SEEDS="$RD/_seeds/comments_index__${V}.json"
  N=$(python3 -c "import json,sys;print(len(json.load(open('$SEEDS'))))")
  echo "=== $V : $N seeds : $(date -Is) ==="
  VARIANT="$V" \
  EXTRA_SEEDS_JSON="$SEEDS" \
  SEEDS_ONLY=1 \
  LABEL_SUFFIX=_MOD919 \
  MAX_RUNS=$((N + 10)) \
  TIME_BUDGET=14400 \
  DUMP_OUT="$OUT" \
    bundle exec jruby -I. "$RD/_proto/run_dse.rb" \
    > "$LOG/comments_index_${V}.log" 2>&1
  echo "  rc=$? dumps_now=$(ls "$OUT" | grep -c '^dump_') $(date -Is)"
  cp -p "$RD/_proto/exploration_summary.json" \
        "$LOG/exploration_summary_comments_index_${V}_MOD919.json" 2>/dev/null
done

echo "=== ALL DONE $(date -Is) total=$(ls "$OUT" | grep -c '^dump_') ==="
