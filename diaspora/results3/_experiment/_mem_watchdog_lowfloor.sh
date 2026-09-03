#!/bin/bash
# Overnight memory watchdog (2026-08-19): the box (7.8G, no swap) has been
# kernel-OOM-killed twice this week, taking the tmux session down. This
# guard guarantees the GLOBAL OOM killer never fires: when MemAvailable
# drops below the floor, kill the single largest-RSS EXPENDABLE process
# (jruby/java/z3/ruby, or python3 outside the session's own tooling) —
# never claude, tmux, sshd, node/VS Code, or openclaw. All legitimate heavy
# jobs tonight are re-runnable (DSE corpora are deterministic; checker and
# diff re-run from artifacts), so a kill costs a retry, not data.
FLOOR_KB=$((300 * 1024))
LOG=/home/dev/project/reports/diaspora/results3/_experiment/_mem_watchdog.log
echo "$(date -Is) watchdog up (floor 700MB)" >> "$LOG"
while true; do
  avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
  if [ "$avail" -lt "$FLOOR_KB" ]; then
    victim=$(ps -eo pid,rss,comm,args --sort=-rss | awk '
      NR>1 && ($3=="java" || $3=="jruby" || $3=="z3" || $3=="ruby" || $3=="python3") \
      && $4 !~ /claude|tmux|vscode|openclaw|sshd/ && $2 > 500000 {print $1; exit}')
    if [ -n "$victim" ]; then
      echo "$(date -Is) avail=${avail}KB < floor; killing $(ps -o pid,rss,args -p "$victim" | tail -1)" >> "$LOG"
      kill -9 "$victim" 2>/dev/null
      sleep 5
    else
      echo "$(date -Is) avail=${avail}KB < floor but no expendable victim found" >> "$LOG"
      sleep 10
    fi
  fi
  sleep 15
done
