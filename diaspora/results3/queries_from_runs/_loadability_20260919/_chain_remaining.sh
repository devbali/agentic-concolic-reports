#!/bin/bash
# Fast-lane chain: run the remaining policy-loadability audits sequentially,
# one at a time, after the conversations_index audit finishes.
# Each runs in its OWN systemd scope with its own MemoryMax and unique unit.
set +e
Q=/home/dev/project/reports/diaspora/results3/queries_from_runs
OUT=$Q/_loadability_20260919
CFG=/home/dev/project/reports/diaspora/queries_config/app.json
PY=/home/dev/project/venvs/queries_from_runs/bin/python
AUD=/home/dev/project/src/queries_from_runs/audits/policy_loadability_audit.py
R3=/home/dev/project/reports/diaspora/results3

say(){ echo "[$(date -Is)] $*" >> "$OUT/_chain.log"; }
: > "$OUT/_chain.log"

# wait for the conversations audit to clear
while systemctl --user is-active --quiet loadaudit-conversations-20260919.scope; do sleep 20; done
say "conversations audit clear"

run_one() {
  local name="$1" batch="$2" sql="$3" unit="$4" cap="$5"
  say "START $name (batch=$batch)"
  systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax="$cap" --unit="$unit" \
    env QFR_APP_CONFIG="$CFG" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
    "$PY" -u "$AUD" "$batch" "$sql" --sample 2000 \
    > "$OUT/${name}_fix.log" 2>&1
  say "DONE  $name rc=$? :: $(grep -E 'written=|RESULT:' "$OUT/${name}_fix.log" | tr '\n' ' ')"
}

run_one comments_index      "$R3/comments_index"      "$Q/comments_index_pcfold3_fix.sql"      loadaudit-comments-20260919      8G
run_one notifications_index "$R3/notifications_index" "$Q/notifications_index_pcfold3_fix.sql" loadaudit-notifications-20260919 10G

say "CHAIN_DONE"
