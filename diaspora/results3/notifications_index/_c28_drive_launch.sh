#!/bin/bash
# C28 — launch one drive DETACHED as a --no-block --unit service, so neither a
# tool-call timeout nor a session cleanup can take it (RUNBOOK §4: a --scope
# client and a BLOCKING --unit client both die with the session that launched
# them; the chunk workers' own --scope clients then live inside THIS service).
# Verdict line: `C28-DRIVE-DONE <tag> +<n>` in $B/_c28_drive_<tag>.log.
#   usage: [DRIVE_PAR=n] [CHUNK=n] bash _c28_drive_launch.sh <TAG> [PREF]
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
TAG="${1:?usage: _c28_drive_launch.sh <TAG> [PREF]}"; PREF="${2:-_c28_r1_seeds_}"
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c28.log"; }
. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "DRIVE $TAG WAIT free<4G"; sleep 30; done
wait_mem "${CAPMB:-8192}" "_c28/drive-$TAG" | tee -a "$B/_c28.log"
say "C28 DRIVE $TAG pref=$PREF par=${DRIVE_PAR:-2} slots=${CONCOLIC_SLOTS:-2} chunk=${CHUNK:-100} cap=${CAP:-8G}"
systemd-run --user --no-block --unit="notif-c28-drive-$TAG" --slice=concolic-cov.slice \
  -p MemoryMax="${CAP:-8G}" -p MemorySwapMax=0 --quiet -p WorkingDirectory=/home/dev/project \
  -p StandardOutput="file:$B/_c28_drive_launch_${TAG}.out" \
  -p StandardError="append:$B/_c28_drive_launch_${TAG}.out" \
  --setenv=JAVA_TOOL_OPTIONS= --setenv=PYTHONPATH=/home/dev/project/src \
  --setenv=DRIVE_PAR="${DRIVE_PAR:-2}" --setenv=CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-2}" \
  --setenv=CHUNK="${CHUNK:-100}" --setenv=JRUBY_CAP="${JRUBY_CAP:-2G}" \
  /bin/bash "$B/_c28_drive.sh" "$TAG" "$PREF"
say "C28 DRIVE $TAG LAUNCHED unit=notif-c28-drive-$TAG log=$B/_c28_drive_${TAG}.log (verdict: C28-DRIVE-DONE $TAG +N)"
