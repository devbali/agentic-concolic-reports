#!/bin/bash
# cycle 2 SUFFIX sweep: set a whole DIMENSION (every variable with that name
# suffix, whatever call ordinal carries it) and let the DSE flip-expand from
# there. Exact-name demand seeds are frequently inert on deep decisions
# because the ordinal shifts; the dimension is what the scenario means.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_gen_sfx.log"; echo "=== suffix sweep start $(date -Is) ===" > "$LOG"
run() { # $1 tag, $2 json, $3.. variants
  local tag="$1"; local js="$2"; shift 2
  for V in "$@"; do
    echo "--- $tag $V ---" >> "$LOG"
    flock /tmp/concolic-slot.lock env VARIANTS="$V" SEED_SUFFIXES="$js" \
      LABEL_SUFFIX="_${tag}${V:0:3}" MAX_RUNS=260 TIME_BUDGET=200 \
      /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
  done
}
ALL="html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain"
run sd1 '{"_disp_has_dlink":true}'                                   $ALL
run sd2 '{"_text_has_dlink":true}'                                   $ALL
run sd3 '{"_text_has_dlink":true,"_disp_has_dlink":true,"_text_dlink_is_post":false,"_disp_dlink_is_post":false}' html_typed mobile_typed json_plain
run sp1 '{"_persisted":false}'                                       html_typed mobile_plain json_plain
run sp2 '{"_target_is_photo":true,"_text_nil":true}'                 html_typed mobile_typed json_typed
run sn1 '{"_not_found":true}'                                        html_typed mobile_plain
run st1 '{"_text_nil":true,"_disp_has_dlink":true}'                  html_typed mobile_typed
echo "=== suffix sweep DONE $(date -Is) ===" >> "$LOG"
