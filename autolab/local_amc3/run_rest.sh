#!/usr/bin/env bash
# Drive 9: run pregate -> check -> policy -> realmode -> concrete in sequence,
# once --stage batch has exited. Each stage's own exit code is recorded; the
# chain stops only on codes that mean the stage could not run at all.
#   check:    0 = complete, 1 = not complete (BOTH are results -> continue)
#   concrete: 0 = domain passed, 1 = domain blocked (BOTH are results)
cd /home/dev/project/reports/autolab/local_amc3 || exit 9
unset JAVA_TOOL_OPTIONS
PY=/home/dev/project/venvs/queries_from_runs/bin/python3
run () {            # run <stage> <ok-codes...>
  local st=$1; shift
  echo "===== STAGE $st  $(date -u +%FT%TZ)"
  XDG_RUNTIME_DIR=/run/user/1000 systemd-run --user --scope -p MemoryMax=12G --quiet \
    "$PY" drive.py --stage "$st" --attempt 1 > "logs/$st-1.log" 2>&1
  local rc=$?
  echo "===== STAGE $st rc=$rc"
  tail -40 "logs/$st-1.log"
  for ok in "$@"; do [ "$rc" = "$ok" ] && return 0; done
  echo "===== CHAIN STOPPED: $st rc=$rc is not a result code"
  return 1
}
# Wait for the batch stage to have produced a packet record. Through the
# helper, not a hand-rolled loop: it takes a timeout (an unbounded wait makes
# this script unreachable) and it is the one place a wait is written here, so
# there is nowhere for a command-line pattern to creep back in. A sentinel
# file is the strongest form of wait there is -- nothing to match, so nothing
# to match wrongly.
PYTHONPATH=/home/dev/project/src_new "$PY" -m sweep.box.wait_for \
    --file state/packet.json --timeout 21600 --interval 20 || {
  echo "===== CHAIN STOPPED: no state/packet.json; the batch stage produced no packet"
  exit 1
}
echo "packet recorded: $(cat state/packet.json)"
run pregate  0 || exit 1
run check    0 1 || exit 1
run policy   0 || exit 1
run realmode 0 || exit 1
run concrete 0 1 || exit 1
echo "===== CHAIN COMPLETE $(date -u +%FT%TZ)"
