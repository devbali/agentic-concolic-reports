#!/bin/bash
# §16g byte-identity harness: run the two CLOSED endpoints' coverage layer with
# the §16g flag ABSENT (their own defaults), once BEFORE the coverage.py edit
# and once AFTER, and diff both the stdout and the SUMMARY_OUT json.
#   usage: bash _byteid_chain.sh pre|post
set +e; unset JAVA_TOOL_OPTIONS
TAG="${1:?usage: _byteid_chain.sh pre|post}"
D=/home/dev/project/reports/diaspora/results3/_16g_byteid_20260914
R=/home/dev/project/reports/diaspora/results3
say(){ echo "[$(date -Is)] $*" >> "$D/_chain_$TAG.log"; }
: > "$D/_chain_$TAG.log"
say "engine coverage.py md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"
run_one(){
  local ep="$1" cap="$2" capmb="$3"
  while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "$ep WAIT free<4G"; sleep 30; done
  local max cur
  max=$(systemctl --user show concolic-cov.slice -p MemoryMax --value)
  cur=$(systemctl --user show concolic-cov.slice -p MemoryCurrent --value)
  while [ $(( (max - cur) / 1048576 )) -lt "$capmb" ]; do
    say "$ep WAIT slice headroom $(( (max-cur)/1048576 ))M < ${capmb}M"; sleep 60
    cur=$(systemctl --user show concolic-cov.slice -p MemoryCurrent --value)
  done
  say "$ep START cap=$cap headroom=$(( (max-cur)/1048576 ))M"
  systemd-run --user --pipe --wait --unit="byteid-${TAG}-${ep}" \
    --slice=concolic-cov.slice -p MemoryMax="$cap" -p MemorySwapMax=0 --quiet \
    -p WorkingDirectory=/home/dev/project \
    --setenv=PYTHONPATH=/home/dev/project/src --setenv=JAVA_TOOL_OPTIONS= \
    --setenv=SKIP_COMPLETION=1 --setenv=SUMMARY_OUT="$D/${ep}_${TAG}.json" \
    choom -n 1000 -- python3 -u "$R/${ep}/coverage_report.py" \
    > "$D/${ep}_${TAG}.log" 2>&1
  say "$ep rc=$? :: $(grep -E '^COMPLETE=' "$D/${ep}_${TAG}.log" | tr '\n' ' ')"
}
run_one people_stream 3G 3072
run_one comments_index 6G 6144
say "BYTEID-CHAIN-DONE $TAG"
