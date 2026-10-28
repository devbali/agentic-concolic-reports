#!/bin/bash
# one advance pass, ramped. usage: adv.sh <max_launch> [max_concurrency]
export PATH=/home/dev/tools/google-cloud-sdk/bin:$PATH
export SWEEP_QUEUE_CONFIG=/home/dev/project/reports/autolab/entrypoints/queue_w2.json
export PYTHONPATH=/home/dev/project:/home/dev/project/src_new
Q=/home/dev/project/reports/autolab/entrypoints/sweep_out_w2/queue
PY=/home/dev/project/venvs/sky/bin/python3
CTX=reports.autolab.tools.queue_context:make
ML=${1:-0}; MC=${2:-12}
cd /home/dev/project
exec $PY -m sweep.queue advance --out "$Q" --context "$CTX" --max-launch "$ML" --max-concurrency "$MC"
