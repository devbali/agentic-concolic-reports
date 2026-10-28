#!/bin/bash
# The one thing left: subsumption on the shipped policy. Needs a REAL 6G window
# (free -g >= 7) and NO other endpoint's pass/census. Retries on its own; never
# overwrites the shipped file unless the run produces its verdict line.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/people_stream
Q=/home/dev/project/reports/diaspora/results3/queries_from_runs
cd /home/dev/project
say(){ echo "[$(date -Is)] $*" >> "$B/_x7_subsume.log"; }
: > "$B/_x7_subsume.log"
w=0
while :; do
  FG=$(free -g | awk '/^Mem/{print $7}')
  OTH=$(pgrep -af "coverage_report\.py|_exact_enum|confinement_census" | grep -v "bash -c" | grep -vc "people_stream")
  if [ "$FG" -ge 7 ] && [ "$OTH" -eq 0 ]; then break; fi
  [ $((w % 900)) -eq 0 ] && say "waiting for a 6G window: free=${FG}G other_passes=${OTH} (${w}s)"
  [ "$w" -ge 21600 ] && { say "no 6G window in 6h — giving up; the SKIP_SUBSUME edition stands (state None)"; exit 0; }
  sleep 60; w=$((w+60))
done
say "free window — extraction WITH subsumption at 6G"
"$B/_caged" 6G env OUT_SQL=$Q/people_stream.sql.subsume OUT_SUMMARY=$Q/_summary_people_stream.json.subsume \
  JAVA_TOOL_OPTIONS= PYTHONPATH=/home/dev/project/src \
  /home/dev/project/venvs/queries_from_runs/bin/python -u $Q/_extract_people_stream_streaming.py \
  > $Q/_extract_people_stream_SUBSUME_20260911.log 2>&1
rc=$?
V=$(grep -E '^people_stream: ' $Q/_extract_people_stream_SUBSUME_20260911.log)
say "rc=$rc :: ${V:-NO VERDICT LINE — killed, not done}"
if [ -n "$V" ] && grep -q "subsume_ran=True" $Q/_extract_people_stream_SUBSUME_20260911.log; then
  mv $Q/people_stream.sql.subsume $Q/people_stream.sql
  mv $Q/_summary_people_stream.json.subsume $Q/_summary_people_stream.json
  python3 - <<'PY'
hdr=open("/home/dev/project/reports/diaspora/results3/people_stream/POLICY_HEADER.txt").read()
p="/home/dev/project/reports/diaspora/results3/queries_from_runs/people_stream.sql"
s=open(p).read(); lines=s.split("\n"); i=0
while i < len(lines) and (lines[i].startswith("--") or not lines[i].strip()): i+=1
open(p,"w").write(hdr.rstrip("\n")+"\n\n"+"\n".join(lines[i:]))
PY
  say "INSTALLED with subsumption; views=$(grep -c '^SELECT' $Q/people_stream.sql)"
  say "$(grep -E 'verdict tally|total dropped|stage 1|stage 2' $Q/_extract_people_stream_SUBSUME_20260911.log | tr '\n' ' ')"
else
  rm -f $Q/people_stream.sql.subsume $Q/_summary_people_stream.json.subsume
  say "NOT installed — the SKIP_SUBSUME edition stands (state None, never True)"
fi
