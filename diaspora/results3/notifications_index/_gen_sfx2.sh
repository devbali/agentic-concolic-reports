#!/bin/bash
# cycle 2 suffix sweep #2 — the pairs the checker still demands: a collection
# LENGTH (`len(..._rows)`) crossed with a target-chain GUID / PERSISTED. Both
# are set by DIMENSION (any call ordinal), which is the only way to reach the
# deep ordinals (records_4 / records_6 appear only in multi-row renders).
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_gen_sfx2.log"; echo "=== suffix sweep 2 start $(date -Is) ===" > "$LOG"
run() { local tag="$1"; local js="$2"; shift 2
  for V in "$@"; do
    echo "--- $tag $V ---" >> "$LOG"
    flock /tmp/concolic-slot.lock env VARIANTS="$V" SEED_SUFFIXES="$js" \
      LABEL_SUFFIX="_${tag}${V:0:3}" MAX_RUNS=300 TIME_BUDGET=220 \
      /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
  done
}
ALL="html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain"
MAIN="html_typed mobile_typed json_typed html_plain"
run x0 '{"_rows)":0,"_text_nil":true}'                         $ALL
run x1 '{"_rows)":0,"_guid":"","_text_nil":true}'              $MAIN
run x2 '{"_guid":"","_text_nil":true}'                         $MAIN
run x3 '{"_rows)":1,"_guid":"gg","_text_nil":true}'            $MAIN
run x4 '{"_rows)":0,"_persisted":false}'                       $MAIN
run x5 '{"_rows)":1,"_persisted":true,"_guid":""}'             $MAIN
echo "=== suffix sweep 2 DONE $(date -Is) ===" >> "$LOG"
