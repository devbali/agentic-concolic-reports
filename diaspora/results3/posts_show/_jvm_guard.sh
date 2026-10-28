#!/bin/bash
# JVM ESCAPE GUARD (coordinator, 2026-09-11 20:4x). The blockaid harness runs
# `check_subsumed.sh` through subprocess.run — sequential, ONE JVM at a time,
# and a child inherits its parent's cgroup, so a JVM started under `cage` IS
# caged. This guard does not assume that: while stage 13d-2 runs it checks
# every `java` process on the box and, if one of MINE is outside
# concolic-cov.slice, it kills the stage rather than letting it run uncaged.
# Other agents' JVMs are reported, never killed.
set +e
B=/home/dev/project/reports/diaspora/results3/posts_show
L="$B/_jvm_guard.log"
TARGET_SCOPE="${1:-p13ext2.scope}"
while systemctl --user is-active "$TARGET_SCOPE" >/dev/null 2>&1; do
  for p in $(pgrep -x java 2>/dev/null); do
    cg=$(sed 's/.*://' "/proc/$p/cgroup" 2>/dev/null | head -1)
    anc=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    case "$cg" in
      */concolic-cov.slice/*) : ;;                       # caged: fine
      *) if ps -o args= -p "$anc" 2>/dev/null | grep -q "posts_show"; then
           echo "[$(date -Is)] UNCAGED JVM OF MINE pid=$p cg=$cg — stopping $TARGET_SCOPE" >> "$L"
           systemctl --user stop "$TARGET_SCOPE"
         else
           echo "[$(date -Is)] uncaged JVM pid=$p cg=$cg — NOT mine, reported only" >> "$L"
         fi ;;
    esac
  done
  sleep 15
done
echo "[$(date -Is)] guard exit: $TARGET_SCOPE inactive" >> "$L"
