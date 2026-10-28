#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c18.log"; }
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "C18 CENSUS WAIT free<4G"; sleep 30; done
say "C18 IDENTITY CENSUS start  list=_snapshot_c16_R2.txt"
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax=4G -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c18_census.time" \
  env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= WORKERS=4 \
      DUMP_LIST="$B/_snapshot_c16_R2.txt" \
      python3 -u "$B/_c18_identity_census.py" "$B/_c18_identity_census.json" \
      > "$B/_c18_census.log" 2>&1
say "C18 CENSUS exit=$?"
grep -qE '^C18-IDENTITY-CENSUS-DONE' "$B/_c18_census.log" \
  && say "VERDICT C18-CENSUS: OK" || say "VERDICT C18-CENSUS: *** NO VERDICT LINE ***"
grep -E 'Maximum resident|Elapsed' "$B/_c18_census.time" | tee -a "$B/_c18.log"
