#!/bin/bash
# Coverage-only pass in its OWN slice with a verified cap.
#   usage: _campaign_cov.sh <tag>   -> log _campaign_cov_<tag>.log, unit ndx-cov-<tag>, slice ndxcov.slice
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index; TAG="$1"; LOG="$B/_campaign_cov_${TAG}.log"
echo "[$(date -Is)] coverage pass start (unit ndx-cov-$TAG, slice ndxcov, MemoryMax=${MEMMAX:-10G}): corpus $(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l) dumps" > "$LOG"
systemd-run --user --unit="ndx-cov-${TAG}" --slice=ndxcov.slice --collect -p MemoryMax="${MEMMAX:-10G}" -p MemorySwapMax=0 \
  --working-directory=/home/dev/project \
  --setenv=SKIP_COMPLETION=1 --setenv=MAX_CLIQUES=16384 --setenv=MAX_MISSING_PER_CLIQUE="${MMC:-1}" \
  --setenv=MISSING_CAP=6000 --setenv=PYTHONPATH=src \
  /bin/bash -c "/usr/bin/time -v python3 $B/coverage_report.py >> '$LOG' 2>&1; echo \"[\$(date -Is)] coverage pass rc=\$?\" >> '$LOG'"
sleep 3; systemctl --user show "ndx-cov-${TAG}.service" -p MemoryMax -p Slice >> "$LOG"
