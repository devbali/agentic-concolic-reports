#!/usr/bin/env bash
# Drive people_stream (3 scenarios) and conversations_index (10 variants)
# seed-exactly under RAILS_ENV=concolic_mod, with a bounded JVM pool.
set -uo pipefail

RD=/home/dev/project/reports/diaspora/results3/_redrive_20260919
LOG=$RD/_logs
POOL=5

mkdir -p "$LOG"

pids=()
launch() {
  local ep=$1 v=$2 knob=$3
  while [ "$(jobs -rp | wc -l)" -ge "$POOL" ]; do sleep 5; done
  "$RD/_drive_rc1.sh" "$ep" "$v" "$knob" >> "$LOG/_orchestrate.out" 2>&1 &
}

echo "=== RC-1 drives start $(date -Is) ===" | tee -a "$LOG/_orchestrate.out"

for s in anon_all anon_json auth_json; do
  launch people_stream "$s" SCENARIO_ONLY
done
for v in html_withcid js_withcid mobile_plain mobile_withcid html_plain \
         js_plain json_withcid xml_withcid json_plain xml_plain; do
  launch conversations_index "$v" VARIANTS
done

wait
echo "=== RC-1 drives done $(date -Is) ===" | tee -a "$LOG/_orchestrate.out"
echo "people_stream fresh:      $(ls /home/dev/project/reports/diaspora/results3/people_stream | grep -c '_RC1MOD\.json$')" | tee -a "$LOG/_orchestrate.out"
echo "conversations_index fresh:$(ls /home/dev/project/reports/diaspora/results3/conversations_index | grep -c '_RC1MOD\.json$')" | tee -a "$LOG/_orchestrate.out"
echo "RC1_DRIVES_COMPLETE" | tee -a "$LOG/_orchestrate.out"
