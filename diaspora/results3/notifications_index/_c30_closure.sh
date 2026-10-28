#!/bin/bash
# =============================================================================
# C30 CLOSURE LAUNCHER — preflight, then detach the stage as a systemd UNIT
# (--no-block --unit=, StandardOutput=file:; a `>` redirection would bind to
# the CLIENT and lose the output — C24's defect).
#
#   usage: COV_OUT=<abs path to cov summary.json> bash _c30_closure.sh <2|3>
#
# COPY of `_c27_closure.sh`. Differences:
#   * COV_OUT is REQUIRED for stage 2 — no default. C27 defaulted it to the
#     WITHDRAWN `_cov_C26_C26R1.json` (§39.6).
#   * caps sized to the 16-core / 68 G box with a 56 G cage: stage 2 takes
#     24 G (was 9 G) because it now runs 14 JRuby probe workers, stage 3 3 G.
# =============================================================================
set +e
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
FROM="${1:?usage: COV_OUT=<...> _c30_closure.sh <2|3>}"
case "$FROM" in
  2) CAP="${CAP:-24G}"; CAPMB="${CAPMB:-24576}";;
  3) CAP="${CAP:-3G}";  CAPMB="${CAPMB:-3072}";;
  *) echo "stage must be 2 or 3"; exit 2;;
esac
L="$B/_c30_closure.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
if [ "$FROM" = 2 ]; then
  [ -n "$COV_OUT" ] || { say "*** COV_OUT is UNSET — refusing to guess a coverage summary ***"; exit 19; }
  [ -s "$COV_OUT" ] || { say "*** COV_OUT=$COV_OUT missing/empty ***"; exit 20; }
fi
. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "C30-$FROM WAIT: free<4G"; sleep 30; done
wait_mem "$CAPMB" "_c30/closure-$FROM" | tee -a "$L"
UNIT="notif-c30-closure-$FROM"
systemd-run --user --no-block --unit="$UNIT" --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 -p WorkingDirectory="$B" \
  -p StandardOutput="file:$B/_c30_closure_${FROM}.out" \
  -p StandardError="append:$B/_c30_closure_${FROM}.out" \
  --setenv=COV_OUT="$COV_OUT" \
  --setenv=CAP="$CAP" \
  --setenv=COMPLETION_AUDIT_TIMEOUT="${COMPLETION_AUDIT_TIMEOUT:-21600}" \
  /usr/bin/bash "$B/_c30_closure_inner.sh" "$FROM"
say "C30-$FROM launched as $UNIT (cap $CAP, COV_OUT=$(basename "${COV_OUT:-n/a}")); verdict in _c30_closure_${FROM}.out / _c30_closure.log"
