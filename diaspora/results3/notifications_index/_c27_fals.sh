#!/bin/bash
# C27 ACTIVE FALSIFICATION of the 24 §16g classes — the gate returned
# NOT-TESTABLE 24/24 and a NOT-TESTABLE is not a licence (§24.4), so this runs
# the same probe from MANY bases, in the §31.2/§31.3 style. Detached unit,
# checkpointed (same index + probe bank the C27 gate built), cap 8G.
#   verdict line: ^C27-FALS-DONE
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
TAG="${1:-F1}"; CAP="${CAP:-8G}"; CAPMB="${CAPMB:-8192}"
cd "$B" || exit 2
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c27_fals.log"; }
. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "C27 FALS WAIT: free<4G"; sleep 30; done
wait_mem "$CAPMB" "_c27/fals-$TAG" | tee -a "$B/_c27_fals.log"
systemd-run --user --no-block --unit="notif-c27-fals-$TAG" --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 -p WorkingDirectory="$B" \
  -p StandardOutput="file:$B/_c27_fals_${TAG}.out" \
  -p StandardError="append:$B/_c27_fals_${TAG}.out" \
  --setenv=CONCOLIC_SLOTS=1 --setenv=PYTHONPATH=/home/dev/project/src \
  --setenv=JAVA_TOOL_OPTIONS= \
  --setenv=ACHK_CHECKPOINT="$B/_c27_achk_probes.jsonl" \
  --setenv=ACHK_INDEX_CHECKPOINT="$B/_achk_index.ckpt.jsonl" \
  --setenv=ACHK_HEARTBEAT_S=60 \
  --setenv=FALS_K="${FALS_K:-8}" \
  /usr/bin/time -v -o "$B/_c27_fals_${TAG}.time" \
  python3 -u "$B/_c27_fals.py" "$B/_c27_gate_classes.json" "$B/_c27_fals_${TAG}.json"
say "C27 FALS $TAG launched as notif-c27-fals-$TAG (cap $CAP); verdict ^C27-FALS-DONE in _c27_fals_${TAG}.out"
