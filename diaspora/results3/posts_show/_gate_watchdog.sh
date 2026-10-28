#!/bin/bash
# The gate was launched from a plain shell (mirroring notifications' _probe14.sh)
# and so is NOT under a MemoryMax cgroup. It indexes every dump_*.json in the
# batch — 129 606 of them — and pass B must not be endangered by that. Kill the
# gate, and only the gate, if its RSS crosses the cap or free memory collapses.
set +e
P="$1"; CAP_KB="${2:-3800000}"
while kill -0 "$P" 2>/dev/null; do
  rss=$(ps -o rss= -p "$P" 2>/dev/null | tr -d ' ')
  avail=$(free -m | awk 'NR==2{print $7}')
  if [ -n "$rss" ] && { [ "$rss" -gt "$CAP_KB" ] || [ "$avail" -lt 1200 ]; }; then
    echo "WATCHDOG: killing gate pid $P at RSS=${rss}kB avail=${avail}MB $(date -Is)" \
      >> /home/dev/project/reports/diaspora/results3/posts_show/_tier2_gate.log
    kill "$P" 2>/dev/null
    break
  fi
  sleep 20
done
