#!/bin/bash
# 2026-09-13 05:30 (re-armed): keep the cage at 21G while the 26-42h confinement gate
# posts-p26-gate-20260913 runs beside campaign passes; revert to the owner's 19G budget
# when the gate service ends. Logged.
while systemctl --user is-active posts-p26-gate-20260913.service >/dev/null 2>&1; do sleep 120; done
systemctl --user set-property concolic-cov.slice MemoryMax=19G MemoryHigh=18G
echo "[$(date -Is)] cage reverted to 19G/18G (confinement gate ended)" >> /home/dev/project/reports/diaspora/results3/_RESTART_HANDOFF_20260911.md
