#!/usr/bin/env bash
# Relaunch of the two AUTHENTICATED legs, 2026-09-25 10:24, after the B-2
# reset fix (_p46_patch_b2reset.py).
#
# WHY ONLY THESE TWO. The fix makes `user.person` fire the real association
# reader in EVERY run instead of only the first of the process. It cannot touch
# the anonymous scenarios -- run_dse.rb hands them `user = nil`, and both before
# and after the fix anon dumps carry zero `people.owner_id` notes. So anon_html
# and anon_json keep running untouched and their 56 376 dumps are preserved;
# only the 37 157 pre-fix authenticated dumps were set aside (moved, not
# deleted, into v2/_pre_b2reset_auth_20260925/).
#
# PRIVATE SLOT NAMESPACE, never tools/slot -- see _p47_slot.sh for the incident.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/posts_show
RUNID="$(date +%m%d%H%M)"
for v in auth_html auth_json; do
  (
    P47_SLOTS=3 MAX_RUNS=200000 TIME_BUDGET=36000 \
      VARIANTS="$v" LABEL_SUFFIX="_v2${RUNID}${v}" \
      "$B/_p47_slot.sh" /home/dev/project/scripts/diaspora-concolic "$B/v2/run_dse.rb" \
      >> "$B/_p47_leg_${v}.log" 2>&1
    echo "[$(date -Is)] leg $v (post-b2reset) done rc=$? : $(grep -E 'drained=' "$B/_p47_leg_${v}.log" | tail -1)" >> "$B/_p47_gen_v2.log"
  ) &
done
wait
