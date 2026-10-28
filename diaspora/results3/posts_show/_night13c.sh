#!/bin/bash
# NIGHT 13, FINAL FORM — the measurement stages are DONE (§76.1-§76.16); what
# is left is the record: the final pass, the engine section, the audits.
#
# THERE IS NO EXTRACTION STAGE AND THERE MUST NOT BE. Owner rule, 2026-09-11:
# policies are extracted at CLOSURE only, and posts_show is not complete.
# `_p13d.sh` is a refusal stub; its old body is at _p13d.sh.REMOVED_20260911.
#
# Each stage is caged and gated on `free -g >= 6` — the box reboots to 32 GB
# (see results3/_RESTART_HANDOFF_20260911.md §4); these fire by themselves when
# memory returns, and do not survive the reboot, which §4 covers.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_night13.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
say "=== NIGHT 13c: pass + engine + audits ONLY (extraction removed per the owner rule) ==="
bash "$B/_p13c.sh" >> "$L" 2>&1
say "=== NIGHT 13 DONE (no extraction stage) ==="
