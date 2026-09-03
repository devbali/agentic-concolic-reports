#!/bin/bash
# cycle 2 FINAL corpus (boundary harvest B-1/B-2 applied): base exploration,
# per-type roots, dimension roots, multi-row roots, and the suffix scenarios
# the checker demanded — all from checked-in seed files, no hand-tuned dumps.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_gen_c2b.log"; echo "=== c2b start $(date -Is) ===" > "$LOG"
ALL="html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain"
MAIN="html_typed mobile_typed json_typed html_plain"
# 1. base
for V in $ALL; do
  echo "--- base $V ---" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" MAX_RUNS=700 TIME_BUDGET=600 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
# 2. per-type roots
for k in 0 1 2 3 4 5 6 7; do
  for V in html_typed mobile_typed; do
    echo "--- type$k $V ---" >> "$LOG"
    flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$B/_seed_type$k.json" \
      LABEL_SUFFIX="_ty${k}${V:0:3}" MAX_RUNS=320 TIME_BUDGET=220 \
      /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
  done
done
# 3. dimension roots
for V in $ALL; do
  echo "--- dims $V ---" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$B/_seed_dims.json" \
    LABEL_SUFFIX="_dm${V:0:3}" MAX_RUNS=340 TIME_BUDGET=240 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
# 4. the suffix scenarios (dimension seeding), multi-row roots
i=0
for JS in '{"_disp_has_dlink":true}' '{"_text_has_dlink":true}' \
          '{"_rows)":0,"_text_nil":true}' '{"_rows)":0,"_guid":""}' \
          '{"_rows)":1,"_guid":"gg","_persisted":false}' '{"_persisted":false,"_guid":""}' \
          '{"_person_id":77,"_persisted":true}' '{"_person_id":77,"_persisted":false}' \
          '{"_target_is_photo":true,"_text_nil":true}' '{"_not_found":true}' \
          '{"_profile_not_found":true}' '{"_profile_not_found":true,"_text_nil":true}'; do
  for V in $MAIN; do
    echo "--- sfx$i $V $JS ---" >> "$LOG"
    flock /tmp/concolic-slot.lock env VARIANTS="$V" SEED_SUFFIXES="$JS" \
      EXTRA_SEEDS_JSON="$B/_seed_multirow.json" LABEL_SUFFIX="_s${i}${V:0:3}" \
      MAX_RUNS=280 TIME_BUDGET=200 \
      /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
  done
  i=$((i+1))
done
echo "=== c2b DONE $(date -Is) ===" >> "$LOG"
