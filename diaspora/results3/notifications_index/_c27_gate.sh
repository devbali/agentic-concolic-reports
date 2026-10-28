#!/bin/bash
# C27 §16g gate LAUNCHER. Preflight (RUNBOOK §4 / _wait_mem.sh), then detach the
# inner script as a systemd UNIT (--no-block --unit=, StandardOutput=file: — a
# `>` redirection binds to the client and loses the output).
#   usage: [CAP=8G CAPMB=8192] bash _c27_gate.sh [tag]
set +e
B=/home/dev/project/reports/diaspora/results3/notifications_index
TAG="${1:-C27G}"; CAP="${CAP:-8G}"; CAPMB="${CAPMB:-8192}"
cd "$B" || exit 2
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c27_gate.log"; }
[ -s "$B/_c27_gate_classes.json" ] || { say "C27 GATE: no classes file"; exit 2; }
. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "C27 GATE WAIT: free<4G"; sleep 30; done
wait_mem "$CAPMB" "_c27/gate-$TAG" | tee -a "$B/_c27_gate.log"
UNIT="notif-c27-gate-$TAG"
systemd-run --user --no-block --unit="$UNIT" --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 \
  -p StandardOutput="file:$B/_c27_gate_${TAG}.out" \
  -p StandardError="file:$B/_c27_gate_${TAG}.err" \
  -p WorkingDirectory="$B" \
  /usr/bin/bash "$B/_c27_gate_inner.sh" "$TAG"
say "C27 GATE $TAG launched as $UNIT (cap $CAP); verdict ^C27-GATE-DONE in _c27_gate_${TAG}.out"
