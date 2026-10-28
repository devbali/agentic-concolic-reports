#!/bin/bash
# C27 — the SAME multi-base active falsification, applied to the §16f and §16e
# layers, to measure how far the single-base gate probe's blindness extends.
#   verdict line: ^C27-FALS2-DONE
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c27_fals.log"; }
. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "C27 FALS2 WAIT: free<4G"; sleep 30; done
wait_mem 8192 "_c27/fals2" | tee -a "$B/_c27_fals.log"
systemd-run --user --no-block --unit="notif-c27-fals2" --slice=concolic-cov.slice \
  -p MemoryMax=8G -p MemorySwapMax=0 -p WorkingDirectory="$B" \
  -p StandardOutput="file:$B/_c27_fals2.out" -p StandardError="append:$B/_c27_fals2.out" \
  --setenv=CONCOLIC_SLOTS=1 --setenv=PYTHONPATH=/home/dev/project/src \
  --setenv=JAVA_TOOL_OPTIONS= \
  --setenv=ACHK_CHECKPOINT="$B/_c27_achk_probes.jsonl" \
  --setenv=ACHK_INDEX_CHECKPOINT="$B/_achk_index.ckpt.jsonl" \
  --setenv=ACHK_HEARTBEAT_S=60 --setenv=FALS_K="${FALS_K:-8}" \
  /usr/bin/bash -c "cd $B && echo '=== 16f ===' && python3 -u $B/_c27_fals.py $B/_c27_16f_classes.json $B/_c27_fals_16f.json && echo '=== 16e ===' && python3 -u $B/_c27_fals.py $B/_c27_16e_classes.json $B/_c27_fals_16e.json && echo C27-FALS2-DONE"
say "C27 FALS2 launched as notif-c27-fals2; verdict ^C27-FALS2-DONE in _c27_fals2.out"
