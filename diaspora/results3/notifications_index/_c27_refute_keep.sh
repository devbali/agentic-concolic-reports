#!/bin/bash
# C27 — materialise the refuting runs for the refuted §16g classes (keep=True),
# so the next coverage pass re-derives §16g with the falsifiers IN the corpus.
#   verdict line: ^C27-REFUTE-KEEP-DONE
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
TAG="${1:-K1}"; CAP="${CAP:-8G}"; CAPMB="${CAPMB:-8192}"
cd "$B" || exit 2
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c27_fals.log"; }
. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "C27 KEEP WAIT: free<4G"; sleep 30; done
wait_mem "$CAPMB" "_c27/keep-$TAG" | tee -a "$B/_c27_fals.log"
systemd-run --user --no-block --unit="notif-c27-keep-$TAG" --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 -p WorkingDirectory="$B" \
  -p StandardOutput="file:$B/_c27_keep_${TAG}.out" \
  -p StandardError="append:$B/_c27_keep_${TAG}.out" \
  --setenv=CONCOLIC_SLOTS=1 --setenv=PYTHONPATH=/home/dev/project/src \
  --setenv=JAVA_TOOL_OPTIONS= \
  --setenv=ACHK_LABEL_TOKEN="c27${TAG}" \
  --setenv=ACHK_INDEX_CHECKPOINT="$B/_achk_index.ckpt.jsonl" \
  --setenv=ACHK_HEARTBEAT_S=60 \
  /usr/bin/time -v -o "$B/_c27_keep_${TAG}.time" \
  python3 -u "$B/_c27_refute_keep.py" "$B/_c27_fals_F1.json" \
      "$B/_c27_refuting_dumps_${TAG}.txt" "$B/_c27_refuting_${TAG}.json"
say "C27 KEEP $TAG launched as notif-c27-keep-$TAG; verdict ^C27-REFUTE-KEEP-DONE in _c27_keep_${TAG}.out"
