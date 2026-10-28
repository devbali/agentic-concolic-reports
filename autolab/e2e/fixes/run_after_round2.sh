#!/usr/bin/env bash
# run_after_round2.sh — steps 6, 7 and 8, each gated on the previous one.
# Stops (non-zero) rather than continuing on any failure, so a bad fix set
# cannot silently consume 2.5 hours of sweep.
set -uo pipefail
cd /home/dev/project/reports/autolab/e2e
PY=/home/dev/project/venvs/queries_from_runs/bin/python3

[ -f fixes/tests_after.out ] || { echo "REFUSING: round 2 not applied"; exit 1; }
grep -q "ALL SUITES PASSED" fixes/tests_after.out || { echo "REFUSING: suite not green"; exit 1; }

echo "############ STEP 6: regenerate the scaffolds ############"
if ! bash fixes/regen_scaffolds.sh > fixes/regen.out 2>&1; then
  echo "REGENERATION FAILED — scaffold tree left at scaffold.bak_e2e; see fixes/regen.out"
  tail -30 fixes/regen.out
  exit 1
fi
tail -25 fixes/regen.out
if grep -qE "^[0-9]+ endpoints changed inputs; [1-9]" fixes/regen.out; then
  echo "STOP: an endpoint LOST a symbolic input — that is a regression. Review fixes/regen.out."
  exit 1
fi

echo
echo "############ STEP 7: the 6-endpoint verification trial ############"
rm -rf runs logs results manifest.jsonl
mkdir -p runs logs results
$PY tools/sweep.py --par 3 --run-timeout 900 \
    --only sessions_new likes_index comments_index admin_pods_index \
           links_resolve contacts_index manifest_show home_show \
           diaspora_federation_receive_public > sweep_verify.out 2>&1
cat sweep_verify.out

echo
echo "############ judging the trial against the checklist ############"
if ! $PY fixes/check_verification.py; then
  echo "STOP: the verification trial did not meet the expectations written before it ran."
  exit 1
fi

echo
echo "############ STEP 8: the full re-sweep ############"
# no --max-runs/--time-budget: the limits come from each endpoint's config.json
nohup $PY tools/sweep.py --par 3 --run-timeout 900 > sweep2.out 2>&1 &
echo "sweep2 launched (pid $!) — watch sweep2.out"
