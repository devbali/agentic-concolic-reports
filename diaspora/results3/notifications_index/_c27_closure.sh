#!/bin/bash
# C27 CLOSURE LAUNCHER — preflight, then detach the stage as a systemd UNIT
# (--no-block --unit=, StandardOutput=file:; a `>` redirection would bind to
# the CLIENT and lose the output — C24's defect).
#   usage: [COV_OUT=<summary.json>] bash _c27_closure.sh <2|3>
set +e
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
FROM="${1:?usage: _c27_closure.sh <2|3>}"
case "$FROM" in 2) CAP=9G; CAPMB=9216;; 3) CAP=3G; CAPMB=3072;; *) echo "stage must be 2 or 3"; exit 2;; esac
L="$B/_c27_closure.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "C27-$FROM WAIT: free<4G"; sleep 30; done
wait_mem "$CAPMB" "_c27/closure-$FROM" | tee -a "$L"
UNIT="notif-c27-closure-$FROM"
systemd-run --user --no-block --unit="$UNIT" --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 -p WorkingDirectory="$B" \
  -p StandardOutput="file:$B/_c27_closure_${FROM}.out" \
  -p StandardError="append:$B/_c27_closure_${FROM}.out" \
  --setenv=COV_OUT="${COV_OUT:-$B/_cov_C26_C26R1.json}" \
  --setenv=COMPLETION_AUDIT_TIMEOUT="${COMPLETION_AUDIT_TIMEOUT:-21600}" \
  /usr/bin/bash "$B/_c27_closure_inner.sh" "$FROM"
say "C27-$FROM launched as $UNIT (cap $CAP); verdict in _c27_closure_${FROM}.out / _c27_closure.log"
