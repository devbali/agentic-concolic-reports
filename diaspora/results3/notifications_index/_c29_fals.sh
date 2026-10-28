#!/bin/bash
# C29 — multi-base active falsification (DISCIPLINE §17 / X12, ACHK_BASES/K = 8)
# of the §16g and §16f classes the C29ON1 pass APPLIED, on the C29 corpus.
#   verdict line: ^C29-FALS-DONE
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c29_fals.log"; }
. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "C29 FALS WAIT: free<4G"; sleep 30; done
wait_mem 8192 "_c29/fals" | tee -a "$B/_c29_fals.log"
systemd-run --user --no-block --unit="notif-c29-fals" --slice=concolic-cov.slice \
  -p MemoryMax=8G -p MemorySwapMax=0 -p WorkingDirectory="$B" \
  -p StandardOutput="file:$B/_c29_fals.out" -p StandardError="append:$B/_c29_fals.out" \
  --setenv=CONCOLIC_SLOTS=1 --setenv=PYTHONPATH=/home/dev/project/src \
  --setenv=JAVA_TOOL_OPTIONS= \
  --setenv=ACHK_CHECKPOINT="$B/_c29_achk_probes.jsonl" \
  --setenv=ACHK_INDEX_CHECKPOINT="$B/_achk_index.ckpt.jsonl" \
  --setenv=ACHK_HEARTBEAT_S=60 --setenv=FALS_K="${FALS_K:-8}" \
  /usr/bin/bash -c "cd $B && echo '=== 16g ===' && python3 -u $B/_c27_fals.py $B/_c29_16g_classes.json $B/_c29_fals_16g.json && echo '=== 16f ===' && python3 -u $B/_c27_fals.py $B/_c29_16f_classes.json $B/_c29_fals_16f.json && echo C29-FALS-DONE"
say "C29 FALS launched as notif-c29-fals; verdict ^C29-FALS-DONE in _c29_fals.out"
