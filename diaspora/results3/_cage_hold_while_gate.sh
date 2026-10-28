#!/bin/bash
# RETIRED 2026-09-13 21:40 — owner raised the budget to 32G flat; no hold/revert is needed.
# (was) 2026-09-13 18:20: hold the cage at 24G whenever a posts_show confinement-gate unit
# (posts-p26-gate*) is active — it (cap 12G, ~8-11G) overlaps notifications' engine section
# (cap 9G); revert to the owner's 19G budget whenever no gate unit is active. Logged on change.
H=/home/dev/project/reports/diaspora/results3/_RESTART_HANDOFF_20260911.md
state=""
while :; do
  if systemctl --user list-units --no-legend 'posts-p26-gate*' 2>/dev/null | grep -q ' active '; then want=24; else want=19; fi
  if [ "$want" != "$state" ]; then
    if [ "$want" = 24 ]; then systemctl --user set-property concolic-cov.slice MemoryMax=24G MemoryHigh=23G; else systemctl --user set-property concolic-cov.slice MemoryMax=19G MemoryHigh=18G; fi
    echo "[$(date -Is)] cage-hold: set ${want}G (gate unit active: $([ $want = 24 ] && echo yes || echo no))" >> "$H"; state=$want
  fi
  sleep 60
done
