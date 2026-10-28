#!/bin/bash
# REMOVED 2026-09-11 21:1x — OWNER RULE, relayed by the coordinator:
#
#     POLICIES ARE EXTRACTED AT CLOSURE ONLY.
#
# comments_index, conversations_index and people_stream were each extracted
# AFTER their pass printed `complete: true`. posts_show is NOT complete
# (§76: OR-confined remaining 2.02e7, 99.75 % of it in leaf groups no run has
# ever walked), so it gets NO policy file. The running SKIP_SUBSUME extraction
# and `_install_policy_when_ready.sh` were killed by the coordinator at 21:10;
# neither is to be relaunched, and nothing may be written to
# queries_from_runs/posts_show.sql.
#
# The previous body is kept verbatim at _p13d.sh.REMOVED_20260911 so the record
# shows what was removed rather than that something silently vanished. If this
# endpoint ever closes, that file is the starting point — it already carries
# the 3 G cap, the free-6 gate, `wait_alone`, and `_jvm_guard.sh`.
echo "[$(date -Is)] _p13d.sh is REMOVED: policies are extracted at CLOSURE only;" \
     "posts_show is not complete. Nothing extracted, nothing written." \
     | tee -a /home/dev/project/reports/diaspora/results3/posts_show/_p13d.log
exit 0
