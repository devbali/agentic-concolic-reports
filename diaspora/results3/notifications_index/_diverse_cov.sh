#!/bin/bash
# Coverage-only re-measure after a diverse drive (memory-capped unit).
#   usage: _diverse_cov.sh <tag>      -> log _diverse_cov_<tag>.log, systemd unit ndx-cov-<tag>
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index; TAG="$1"; LOG="$B/_diverse_cov_${TAG}.log"
echo "[$(date -Is)] coverage pass start: corpus $(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l) dumps" > "$LOG"
systemd-run --user --unit="ndx-cov-${TAG}" --collect -p MemoryMax="${MEMMAX:-9G}" -p MemorySwapMax=0 \
  --working-directory=/home/dev/project \
  --setenv=SKIP_COMPLETION=1 --setenv=MAX_CLIQUES=16384 --setenv=MAX_MISSING_PER_CLIQUE="${MMC:-1}" \
  --setenv=MISSING_CAP=6000 --setenv=PYTHONPATH=src \
  /bin/bash -c "python3 $B/coverage_report.py >> '$LOG' 2>&1; echo \"[\$(date -Is)] coverage pass rc=\$?\" >> '$LOG'"
