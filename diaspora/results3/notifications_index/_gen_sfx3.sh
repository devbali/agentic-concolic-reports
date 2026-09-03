#!/bin/bash
# cycle 2 sweep #3: MULTI-ROW roots (list length 3, so the deep collection
# ordinals records_4 / records_6 exist at all) crossed with the dimensions the
# checker still demands — collection length, target-chain guid, persisted, and
# person-identity equality.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_gen_sfx3.log"; echo "=== sweep 3 start $(date -Is) ===" > "$LOG"
run() { local tag="$1"; local js="$2"; shift 2
  for V in "$@"; do
    echo "--- $tag $V ---" >> "$LOG"
    flock /tmp/concolic-slot.lock env VARIANTS="$V" SEED_SUFFIXES="$js" \
      EXTRA_SEEDS_JSON="$B/_seed_multirow.json" \
      LABEL_SUFFIX="_${tag}${V:0:3}" MAX_RUNS=300 TIME_BUDGET=220 \
      /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
  done
}
MAIN="html_typed mobile_typed json_typed html_plain"
run y0 '{"_rows)":0}'                                  $MAIN
run y1 '{"_rows)":0,"_guid":""}'                       $MAIN
run y2 '{"_rows)":1,"_guid":""}'                       $MAIN
run y3 '{"_rows)":1,"_guid":"gg","_persisted":false}'  $MAIN
run y4 '{"_person_id":77,"_persisted":true}'           $MAIN
run y5 '{"_person_id":77,"_persisted":false}'          $MAIN
run y6 '{"_persisted":false,"_guid":""}'               $MAIN
echo "=== sweep 3 DONE $(date -Is) ===" >> "$LOG"
