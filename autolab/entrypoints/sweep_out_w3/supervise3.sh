#!/bin/bash
# Ramped supervisor. Never exits on an advance failure. Stops on its own
# SPEND ALLOWANCE -- a delta from the /credits baseline it reads at start.
export PATH=/home/dev/tools/google-cloud-sdk/bin:$PATH
export SWEEP_QUEUE_CONFIG=/home/dev/project/reports/autolab/entrypoints/queue_w3.json
export PYTHONPATH=/home/dev/project:/home/dev/project/src_new
BASE=/home/dev/project/reports/autolab/entrypoints/sweep_out_w3
Q=$BASE/queue
PY=/home/dev/project/venvs/sky/bin/python3
CTX=reports.autolab.tools.queue_context:make
RAMP=(10)
i=0
cd /home/dev/project

# ── THE SPEND CONTROL IS A DELTA, NEVER AN ABSOLUTE (fixed 2026-10-03) ──────
# This was `CEIL=130.96`: an absolute `total_usage`, compared straight against
# OpenRouter's ACCOUNT-CUMULATIVE figure. The key is SHARED and
# AUTO-TOPS-UP, so `total_usage` moves for reasons that have nothing to do
# with this sweep -- $52 was spent by something else over four days while
# both sweeps had zero boxes. An absolute ceiling is therefore meaningless
# the moment the account drifts, in BOTH directions:
#
#   * it stops being a brake -- a top-up raises the headroom silently;
#   * and it becomes a false trip -- with live usage ~133.40, this script's
#     old ceiling of 130.96 would have fired ON ITS FIRST POLL, before
#     launching anything.
#
# It also made the RECORD unreadable: anyone re-deriving the old threshold
# from today's `/credits` would conclude the pass overran, when what moved
# was the account, not the sweep.
#
# `ALLOWANCE` is what THIS RUN may spend. `USAGE_BASE` is re-read from
# /credits at this supervisor's OWN START, and the trip wire compares the
# DELTA. The old number was 130.96 against a hand-read baseline of
# 110.964684, i.e. this allowance; the budget is unchanged, only its
# expression is.
#
# NOTE `BASE` above is the OUTPUT DIRECTORY. The baseline is `USAGE_BASE`
# precisely so it cannot collide with it.
ALLOWANCE=${ALLOWANCE:-20.00}

read_usage() {
  curl -s -m 20 -H "Authorization: Bearer $(cat /home/dev/project/openrouter_api_key.txt)" \
        https://openrouter.ai/api/v1/credits | $PY -c 'import json,sys
try: print(json.load(sys.stdin)["data"]["total_usage"])
except Exception: print("")' 2>/dev/null
}

mkdir -p $BASE/qlogs

# A BASELINE THAT CANNOT BE READ IS A HARD FAILURE, not a warning. The delta
# is the only model-spend brake that exists (`docs/LAUNCH_SWEEP.md` §"THE
# BRAKE THAT DOES NOT EXIST"), and running without one is exactly how a
# shared, auto-topping-up key gets drained. Retry briefly, then refuse to
# launch anything.
USAGE_BASE=""
for attempt in 1 2 3 4 5; do
  USAGE_BASE=$(read_usage)
  [ -n "$USAGE_BASE" ] && break
  echo "[$(date -u +%H:%M:%S)] baseline /credits read failed (attempt $attempt/5)" | tee -a $BASE/qlogs/supervise.log
  sleep 10
done
if [ -z "$USAGE_BASE" ]; then
  echo "[$(date -u +%H:%M:%S)] ABORT: no /credits baseline; refusing to run with no spend brake" | tee -a $BASE/qlogs/supervise.log
  echo "NO_BASELINE" > $BASE/qlogs/STOPPED
  exit 2
fi
echo "[$(date -u +%H:%M:%S)] spend baseline total_usage=$USAGE_BASE allowance=$ALLOWANCE (stop when total_usage-baseline >= allowance)" | tee -a $BASE/qlogs/supervise.log
while :; do
  # spend check: delta from THIS run's own baseline, never an absolute
  U=$(read_usage)
  # A FAILED POLL IS REPORTED AS UNKNOWN, not as the previous poll's number:
  # `SPENT` is only computed when `$U` read, so without this it would carry
  # the last good value into the log line below and read as fresh.
  SPENT="?"
  if [ -n "$U" ]; then
    OVER=$($PY -c "print(1 if ($U - $USAGE_BASE) >= $ALLOWANCE else 0)" 2>/dev/null)
    SPENT=$($PY -c "print(round($U - $USAGE_BASE, 6))" 2>/dev/null)
    if [ "$OVER" = "1" ]; then
      echo "[$(date -u +%H:%M:%S)] ALLOWANCE REACHED spent=$SPENT >= $ALLOWANCE (total_usage=$U, baseline=$USAGE_BASE) -- stopping" | tee -a $BASE/qlogs/supervise.log
      $PY -m sweep.queue stop --out "$Q" --context "$CTX" --reason "spend allowance: $SPENT of $ALLOWANCE (total_usage $U, baseline $USAGE_BASE)" \
        >> $BASE/qlogs/stop.log 2>&1
      echo "ALLOWANCE_STOP spent=$SPENT allowance=$ALLOWANCE total_usage=$U baseline=$USAGE_BASE" > $BASE/qlogs/STOPPED
      break
    fi
  fi
  if [ -f $BASE/qlogs/HALT ]; then
    echo "[$(date -u +%H:%M:%S)] HALT file present -- exiting loop" | tee -a $BASE/qlogs/supervise.log
    break
  fi
  ML=${RAMP[$i]:-12}
  TS=$(date -u +%Y%m%dT%H%M%S)
  $PY -m sweep.queue advance --out "$Q" --context "$CTX" --max-launch "$ML" --max-concurrency 16 \
      > $BASE/qlogs/adv_$TS.json 2> $BASE/qlogs/adv_$TS.err
  SUM=$(tail -1 $BASE/qlogs/adv_$TS.err 2>/dev/null)
  STAT=$($PY -m sweep.queue status --out "$Q" 2>/dev/null | $PY -c '
import json,sys
d=json.load(sys.stdin); c=d["counts"]
o=d.get("orphans",{}); ol=o.get("orphans",[]) if isinstance(o,dict) else (o or [])
bill=sum(1 for e in d["entries"] if e.get("billing"))
print("q=%s prov=%s run=%s done=%s fail=%s billing=%s orph=%s" % (c["queued"],c["provisioned"],c["running"],c["done"],c["failed"],bill,len(ol)))
' 2>/dev/null)
  echo "[$(date -u +%H:%M:%S)] ml=$ML usage=$U spent=$SPENT/$ALLOWANCE | $SUM | $STAT" >> $BASE/qlogs/supervise.log
  i=$((i+1))
  sleep 25
done
echo "[$(date -u +%H:%M:%S)] supervisor loop exited" >> $BASE/qlogs/supervise.log
