#!/bin/bash
# THE FULL ENGINE RUN (no SKIP_COMPLETION): coverage + completion (shim tests,
# note check, audits, assumption gate via _c11_gate_reuse.py).
# Cage lowered to 6G/high 5G on 2026-09-11, so the cap is 5G and nothing else
# of mine runs beside it (coordinator).
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
LIST="$1"; TAG="${2:-full1}"; CAP="${3:-5G}"
cd "$B"
echo "[$(date -Is)] FULL pass $TAG list=$LIST cap=$CAP avail=$(free -m|awk '/^Mem/{print $7}')MB"
. "$B/_wait_mem.sh"; wait_mem 5120 "_c11_pass_full.sh/$TAG"
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c11_pass_${TAG}.time" \
  env DUMP_LIST="$LIST" PYTHONPATH=/home/dev/project/src \
  MAX_MISSING_PER_CLIQUE=16 MISSING_CAP=40000 \
  python3 -u "$B/coverage_report.py" > "$B/_c11_cov_${TAG}.log" 2>&1
rc=$?
echo "[$(date -Is)] FULL pass $TAG EXIT rc=$rc"
if [ "$rc" != "0" ] && [ "$rc" != "1" ]; then
  echo "*** PASS $TAG FAILED rc=$rc (137 = cgroup SIGKILL at MemoryMax=$CAP) ***"
  tail -15 "$B/_c11_cov_${TAG}.log"; exit "$rc"
fi
grep -E '^OVERALL_COMPLETE=|^COMPLETE=|^GENUINE=|^dump_errors=|^\[assumptions\]|^\[confinement\]|^\[reuse\]|^RESULT:|^wrote |peak RSS' "$B/_c11_cov_${TAG}.log"
grep -E 'Maximum resident|Elapsed' "$B/_c11_pass_${TAG}.time"
