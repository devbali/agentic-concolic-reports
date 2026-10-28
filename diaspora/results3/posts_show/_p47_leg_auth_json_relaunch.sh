#!/usr/bin/env bash
# auth_json leg, relaunched 2026-09-25 10:33 with P47_SLOTS=3.
#
# The first relaunch used P47_SLOTS=2, but private slot 1 was already held by
# the anon_html leg (relaunched at 04:40 with P47_SLOTS=1) and slot 2 by
# auth_html -- so auth_json spun in _p47_slot.sh with nowhere to go and wrote 0
# dumps. P47_SLOTS is a SEARCH RANGE, exactly like tools/slot's: sizing it
# against "how many legs am I starting" is wrong, it has to account for every
# process already using the same private namespace.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/posts_show
P47_SLOTS=3 MAX_RUNS=200000 TIME_BUDGET=36000 \
  VARIANTS=auth_json LABEL_SUFFIX=_v21025auth_json \
  "$B/_p47_slot.sh" /home/dev/project/scripts/diaspora-concolic "$B/v2/run_dse.rb" \
  >> "$B/_p47_leg_auth_json.log" 2>&1
echo "[$(date -Is)] leg auth_json (post-b2reset, slots=3) done rc=$? : $(grep -E 'drained=' "$B/_p47_leg_auth_json.log" | tail -1)" >> "$B/_p47_gen_v2.log"
