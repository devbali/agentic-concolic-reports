#!/bin/bash
# CYCLE 6 corpus, from scratch (B-4 belongs_to not-found decisions, B-5 empty
# relation note residue, §7 one-fact-one-variable for finders, and the
# withdrawn assumption classes). Same shape as _gen_c2b.sh plus the suffix
# scenarios for the new decisions.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_gen_c6.log"; echo "=== c6 start $(date -Is) ===" > "$LOG"
ALL="html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain"
MAIN="html_typed mobile_typed json_typed html_plain"
for V in $ALL; do
  echo "--- base $V ---" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" MAX_RUNS=700 TIME_BUDGET=600 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
for k in 0 1 2 3 4 5 6 7; do
  for V in html_typed mobile_typed; do
    echo "--- type$k $V ---" >> "$LOG"
    flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$B/_seed_type$k.json" \
      LABEL_SUFFIX="_ty${k}${V:0:3}" MAX_RUNS=320 TIME_BUDGET=220 \
      /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
  done
done
for V in $ALL; do
  echo "--- dims $V ---" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$B/_seed_dims.json" \
    LABEL_SUFFIX="_dm${V:0:3}" MAX_RUNS=340 TIME_BUDGET=240 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
i=0
for JS in '{"_disp_has_dlink":true}' '{"_text_has_dlink":true}' \
          '{"_rows)":0,"_text_nil":true}' '{"_rows)":0,"_guid":""}' \
          '{"_rows)":1,"_guid":"gg","_persisted":false}' '{"_persisted":false,"_guid":""}' \
          '{"_person_id":77,"_persisted":true}' '{"_person_id":77,"_persisted":false}' \
          '{"_target_is_photo":true,"_text_nil":true}' '{"_not_found":true}' \
          '{"_profile_not_found":true}' '{"_profile_not_found":true,"_text_nil":true}' \
          '{"_row_person_not_found":true}' '{"_status_message_not_found":true,"_target_is_photo":true}' \
          '{"_recipient_not_found":true}' '{"_target_author_not_found":true,"_target_is_photo":true}' \
          '{"_profile_first_name":"","_profile_last_name":""}' \
          '{"_profile_first_name":"","_public_details":true}' \
          '{"_row_first_name":"","_row_last_name":"","_guid":""}' \
          '{"_text_has_mention":true,"_mention_inline_name":true}' \
          '{"_text_has_mention":true,"_mention_inline_name":false,"_persisted":true}' \
          '{"_birthday_year":900,"_public_details":true}' \
          '{"_disp_has_dlink":true,"_sharing":true}' \
          '{"_disp_has_dlink":true,"_sharing":false}' \
          '{"_language_available":false}' \
          '{"_target_not_found":true,"_text_has_mention":true}' ; do
  for V in $MAIN; do
    echo "--- sfx$i $V $JS ---" >> "$LOG"
    flock /tmp/concolic-slot.lock env VARIANTS="$V" SEED_SUFFIXES="$JS" \
      EXTRA_SEEDS_JSON="$B/_seed_multirow.json" LABEL_SUFFIX="_s${i}${V:0:3}" \
      MAX_RUNS=280 TIME_BUDGET=200 \
      /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
  done
  i=$((i+1))
done
echo "=== c6 DONE $(date -Is) ===" >> "$LOG"
