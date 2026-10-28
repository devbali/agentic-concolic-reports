#!/bin/bash
# REMOVED 2026-09-11 21:1x — OWNER RULE: policies are extracted at CLOSURE
# only, and posts_show is NOT complete (§76). The coordinator killed the
# running instance of this script at 21:10; it must not be relaunched, and
# nothing may be written to queries_from_runs/posts_show.sql or to this
# batch's POLICY_HEADER.txt beyond the STANDING block already there.
# The previous body is kept verbatim at _install_policy_when_ready.sh.REMOVED_20260911.
echo "[$(date -Is)] _install_policy_when_ready.sh is REMOVED: extraction happens at CLOSURE only; posts_show is not complete." \
  | tee -a /home/dev/project/reports/diaspora/results3/posts_show/_p13d.log
exit 0
