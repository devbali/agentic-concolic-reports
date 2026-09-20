#!/bin/bash
# C7 concrete ground truth: ONE REQUEST PER JRUBY PROCESS.
#
# Why: a second request in the same process under-reports its statements
# (measured; see the header of any concrete_manifest_*.rb). The old
# _concrete_all.sh ran one process per MANIFEST and looped 2-4 requests inside
# it, so every request after the first in each manifest was measuring an app
# whose Gon.preloads store already held the contact.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_c7_concrete_all.log"; echo "=== c7 concrete all start $(date -Is) ===" > "$LOG"
rm -f "$B"/_c7_cr_*.json
for S in auth mobile links photo pages; do
  M="$B/concrete_manifest_${S}.rb"
  N=$(grep -c '^  { ' <<<"$(sed -n '/^REQUESTS = \[/,/^\]/p' "$M")")
  echo "--- $S : $N request(s) ---" >> "$LOG"
  i=0
  while [ "$i" -lt "$N" ]; do
    rm -f "$B/concrete_run.json"
    CC_REQ=$i /home/dev/project/reports/diaspora/tools/slot \
      /home/dev/project/scripts/diaspora-concolic \
      /home/dev/project/reports/diaspora/tools/concrete_checker/concrete_run_probe.rb \
      "$M" >> "$LOG" 2>&1
    rc=$?
    if [ -f "$B/concrete_run.json" ]; then
      mv "$B/concrete_run.json" "$B/_c7_cr_${S}_${i}.json"
      echo "[$S req$i] ok rc=$rc" >> "$LOG"
    else
      echo "[$S req$i] NO concrete_run.json rc=$rc" >> "$LOG"
    fi
    i=$((i+1))
  done
done
python3 - >> "$LOG" 2>&1 <<'PY'
import glob, json, os
B="/home/dev/project/reports/diaspora/results3/notifications_index"
out=[]
for f in sorted(glob.glob(B+"/_c7_cr_*.json")):
    d=json.load(open(f))
    out.extend(d if isinstance(d,list) else [d])
json.dump(out, open(B+"/concrete_run.json","w"), indent=2)
print(f"merged {len(out)} scenario(s) from {len(glob.glob(B+'/_c7_cr_*.json'))} process(es) "
      f"-> concrete_run.json; statements total "
      f"{sum(len(e.get('statements') or []) for e in out)}")
PY
echo "=== c7 concrete all DONE $(date -Is) ===" >> "$LOG"
