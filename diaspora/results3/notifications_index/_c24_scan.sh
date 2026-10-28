#!/bin/bash
# C24 — run a construction script caged and DETACHED (--no-block --unit), judged
# by its own verdict line `C24-SCAN-DONE <tag> exit=<rc>` in the tag log.
# Copy of _c22_scan.sh; the only changes are the stamps and the launch form
# (--no-block --unit instead of --scope: both --scope and a BLOCKING --unit
# client lost hour-long jobs to session cleanup on 2026-09-13).
# The constructor still reads C22_PREF / C22_MANIFEST (it is _c22_round1.py,
# unedited); only the VALUES are _c24_.
#   usage: [PLAN=1] [JOBS=n] [CAP=..] bash _c24_scan.sh <tag> <script> [args...]
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
TAG="${1:?tag}"; shift
CAP="${CAP:-2G}"; CAPMB="${CAPMB:-2048}"
L="$B/_c24_${TAG}.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c24.log"; }
. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "$TAG WAIT free<4G"; sleep 30; done
wait_mem "$CAPMB" "_c24/$TAG" | tee -a "$B/_c24.log"
say "$TAG START: $* (cap $CAP, JOBS=${JOBS:-3}, PLAN=${PLAN:-})"
: > "$L"
systemd-run --user --no-block --unit="notif-c24-$TAG" --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  -p WorkingDirectory="$B" \
  --setenv=PYTHONPATH=/home/dev/project/src --setenv=JAVA_TOOL_OPTIONS= \
  --setenv=JOBS="${JOBS:-3}" --setenv=PLAN="${PLAN:-}" \
  --setenv=INDEX_OUT="${INDEX_OUT:-}" --setenv=INDEX_IN="${INDEX_IN:-}" \
  --setenv=INDEX_MERGE="${INDEX_MERGE:-}" --setenv=TODO_CAP="${TODO_CAP:-40}" \
  --setenv=SETS_ONLY="${SETS_ONLY:-}" \
  --setenv=REQUIRE_ALL_MEMBERS="${REQUIRE_ALL_MEMBERS:-}" \
  --setenv=HARD_PER_ROW="${HARD_PER_ROW:-}" \
  --setenv=WRITE_DLINK="${WRITE_DLINK:-}" --setenv=GATE_SEEDS="${GATE_SEEDS:-}" \
  --setenv=WRITE_MEMBERS="${WRITE_MEMBERS:-}" \
  --setenv=C22_PREF="${C22_PREF:-_c24_r1_seeds_}" \
  --setenv=C22_MANIFEST="${C22_MANIFEST:-_c24_r1_manifest.json}" \
  choom -n 1000 -- /bin/bash -c \
    '/usr/bin/time -v -o "$0" python3 -u "$@" >> "'"$L"'" 2>&1; rc=$?; echo "C24-SCAN-DONE '"$TAG"' exit=$rc" >> "'"$L"'"' \
    "$B/_c24_${TAG}.time" "$@"
say "$TAG LAUNCHED unit=notif-c24-$TAG  log=$L  (verdict line: C24-SCAN-DONE $TAG exit=N)"
