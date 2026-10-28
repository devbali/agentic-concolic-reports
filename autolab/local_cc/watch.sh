#!/bin/bash
# Progress line every 60s for the live batch box: frames, tool calls, dumps, marker.
B=$(ls -dt /home/dev/project/reports/autolab/local_cc/boxes/*/ 2>/dev/null | head -1)
PY=/home/dev/project/venvs/queries_from_runs/bin/python3
JRUBY=/home/dev/tools/jruby-9.3.0.0/bin/jruby
while :; do
  [ -d "$B" ] || break
  F=$(wc -l < "$B/ctl/events.ndjson" 2>/dev/null || echo 0)
  T=$(grep -c '"kind": "tool_start"' "$B/ctl/events.ndjson" 2>/dev/null || echo 0)
  D=$(find "$B" -name 'dump_*.json' 2>/dev/null | wc -l)
  M=$([ -f "$B/out/packet.submitted" ] && echo YES || echo no)
  # Through the helper, never `pgrep -f`: a pattern matches the command line
  # of the shell running this loop as readily as the explorer's. `--list`
  # answers without waiting, which is what a progress line wants.
  J=$(PYTHONPATH=/home/dev/project/src_new "$PY" -m sweep.box.wait_for \
        --exe "$JRUBY" --contains run_dse.rb --list 2>/dev/null | wc -l)
  echo "[$(date -u +%H:%M:%S)] frames=$F tools=$T dumps=$D marker=$M jruby=$J"
  sleep 60
done
