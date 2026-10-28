#!/bin/bash
# 2026-09-12 01:25: second arming (the first 2h window expired before the
# engine section started). Raise p13eng.scope to 8G when it appears; 6h window.
for i in $(seq 1 8640); do
  if systemctl --user is-active p13eng.scope >/dev/null 2>&1; then
    systemctl --user set-property p13eng.scope MemoryMax=8G && echo "[$(date -Is)] p13eng.scope raised to 8G" >> /home/dev/project/reports/diaspora/results3/posts_show/_p13c.log; exit 0
  fi
  sleep 10
done
echo "[$(date -Is)] _raise_eng_cap: p13eng.scope never appeared in 24h" >> /home/dev/project/reports/diaspora/results3/posts_show/_p13c.log
