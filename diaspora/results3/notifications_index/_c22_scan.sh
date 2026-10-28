#!/bin/bash
# C22 — run a construction script caged, streamed, judged by its own verdict line.
#   usage: [PLAN=1] [JOBS=n] [CAP=..] bash _c22_scan.sh <tag> <script> [args...]
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
TAG="${1:?tag}"; shift
CAP="${CAP:-2G}"; CAPMB="${CAPMB:-2048}"
L="$B/_c22_${TAG}.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c22.log"; }
. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "$TAG WAIT free<4G"; sleep 30; done
wait_mem "$CAPMB" "_c22/$TAG" | tee -a "$B/_c22.log"
say "$TAG START: $* (cap $CAP, JOBS=${JOBS:-3}, PLAN=${PLAN:-})"
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c22_${TAG}.time" \
  env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= JOBS="${JOBS:-3}" \
      PLAN="${PLAN:-}" INDEX_OUT="${INDEX_OUT:-}" INDEX_IN="${INDEX_IN:-}" TODO_CAP="${TODO_CAP:-40}" INDEX_MERGE="${INDEX_MERGE:-}" SETS_ONLY="${SETS_ONLY:-}" REQUIRE_ALL_MEMBERS="${REQUIRE_ALL_MEMBERS:-}" HARD_PER_ROW="${HARD_PER_ROW:-}" K_BASES="${K_BASES:-}" C22_PREF="${C22_PREF:-_c22_r1_seeds_}" \
      C22_MANIFEST="${C22_MANIFEST:-_c22_r1_manifest.json}" \
      python3 -u "$@" > "$L" 2>&1
rc=$?
say "$TAG exit=$rc"
tail -30 "$L" | sed 's/^/    /' | tee -a "$B/_c22.log"
grep -E 'Maximum resident|Elapsed' "$B/_c22_${TAG}.time" | tee -a "$B/_c22.log"
say "C22-SCAN-DONE $TAG"
