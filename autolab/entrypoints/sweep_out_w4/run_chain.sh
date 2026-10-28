#!/usr/bin/env bash
# The three-box chain for ONE endpoint, after the batch box has submitted.
#   stage 2  review (inline, seconds)  ->  CHECK worker on its own box
#   stage 3  policy build + render     (local; the IR has no box of its own)
#   stage 4  CONCRETE worker on its own box
# Each box driver tears down unconditionally and archives ctl/ before it.
set -uo pipefail
export PATH=/home/dev/tools/google-cloud-sdk/bin:$PATH
export PYTHONPATH=/home/dev/project:/home/dev/project/src_new
PY=/home/dev/project/venvs/sky/bin/python3
QPY=/home/dev/project/venvs/queries_from_runs/bin/python3
B=/home/dev/project/reports/autolab/entrypoints/sweep_out_w4
T=/home/dev/project/reports/autolab/tools
EP=posts_destroy
SPEC=/home/dev/project/reports/autolab/entrypoints/sweep_w4.json
CFG=/home/dev/project/reports/autolab/entrypoints/scaffold/$EP/config.json
PACKET=${1:?usage: run_chain.sh <packet-dir> [stage]}
ONLY=${2:-all}
mkdir -p $B/chain

step_review() {
  echo "### STAGE 2a — review (§5.2, inline)"
  python3 $T/make_review_doc.py --endpoint $EP --packet "$PACKET" --config "$CFG" \
      --out $B/chain/review_doc.json | tee $B/chain/review.out
  sha256sum $B/chain/review_doc.json | cut -d' ' -f1 > $B/chain/review.hash
  echo "review hash: $(cat $B/chain/review.hash)"
}
step_check() {
  echo "### STAGE 2b — CHECK worker, its own box"
  $PY $T/check_live_vm.py --spec "$SPEC" --endpoint $EP --packet "$PACKET" \
      --approved "$(cat $B/chain/review.hash)" --root $B/chain/check 2>&1 \
      | tee $B/chain/check.log
}
step_policy() {
  echo "### STAGE 3 — policy build + render"
  $QPY /home/dev/project/reports/autolab/e2e/tools/pipeline.py $EP "$PACKET/dumps" \
      $B/chain/policy.json 2>&1 | grep -v "Failed to eval var decl" | tail -5
  python3 -c "
import json;d=json.load(open('$B/chain/policy.json'))
print('stages :',json.dumps(d['stages']))
print('verdict:',d['verdict'])
print('policy :',json.dumps(d['policy']))
print('render :',json.dumps(d.get('render',{}))[:300])
print('blocking:',json.dumps(d['completion'].get('blocking')))"
  ls -la $B/chain/*.policy.txt $B/chain/*.sql 2>/dev/null
}
step_concrete() {
  echo "### STAGE 4 — CONCRETE worker, its own box (never run before)"
  $PY $T/concrete_live_vm.py --spec "$SPEC" --endpoint $EP --packet "$PACKET" \
      --batch-dir "$PACKET/dumps" --root $B/chain/concrete 2>&1 \
      | tee $B/chain/concrete.log
}
case "$ONLY" in
  review)   step_review ;;
  check)    step_check ;;
  policy)   step_policy ;;
  concrete) step_concrete ;;
  all)      step_review; step_check; step_policy; step_concrete ;;
esac
