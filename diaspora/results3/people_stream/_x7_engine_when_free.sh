#!/bin/bash
# Re-run the full engine at a cap that fits 13 677 dumps, and only when the box
# has NO other full pass / census running (coordinator's one-pass rule includes
# confinement_census) and enough headroom. The 3 G attempt at 11:29 was
# Result=oom-kill with no verdict line — killed, not done.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/people_stream
Q=/home/dev/project/reports/diaspora/results3/queries_from_runs
cd /home/dev/project
say(){ echo "[$(date -Is)] $*" >> "$B/_x7_engine_when_free.log"; }
: > "$B/_x7_engine_when_free.log"
w=0
while pgrep -f "coverage_report\.py|_exact_enum|confinement_census" | grep -qv "^$$\$"; do
  n=$(pgrep -af "coverage_report\.py|_exact_enum|confinement_census" | grep -v "bash -c" | grep -vc "people_stream/coverage_report")
  [ "$n" -eq 0 ] && break
  [ $((w % 600)) -eq 0 ] && say "waiting for the pass/census slot ($n running, ${w}s)"
  sleep 60; w=$((w+60))
done
say "slot free after ${w}s — full engine at 6G"
"$B/_caged" 6G env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  /home/dev/project/venvs/queries_from_runs/bin/python -u "$B/coverage_report.py" > "$B/_engine_20260911_final2.log" 2>&1
rc=$?
say "engine rc=$rc :: $(grep -E '^OVERALL_COMPLETE|^COMPLETE=' "$B/_engine_20260911_final2.log" | tr '\n' ' ')"
[ "$rc" -ne 0 ] && say "NOTE: rc!=0 — check for a verdict line before reading this as a run"
# subsumption only with a real window and no pass
FG=$(free -g | awk '/^Mem/{print $7}')
OTH=$(pgrep -af "coverage_report\.py|_exact_enum|confinement_census" | grep -v "bash -c" | grep -vc "people_stream" )
if [ "$FG" -ge 7 ] && [ "$OTH" -eq 0 ]; then
  say "free=${FG}G, no other pass — extraction WITH subsumption at 6G"
  "$B/_caged" 6G env OUT_SQL=$Q/people_stream.sql OUT_SUMMARY=$Q/_summary_people_stream.json \
    JAVA_TOOL_OPTIONS= PYTHONPATH=/home/dev/project/src \
    /home/dev/project/venvs/queries_from_runs/bin/python -u $Q/_extract_people_stream_streaming.py \
    > $Q/_extract_people_stream_SUBSUME_20260911.log 2>&1
  say "subsume extraction rc=$? :: $(grep -E '^people_stream: ' $Q/_extract_people_stream_SUBSUME_20260911.log)"
  python3 - <<'PY'
hdr=open("/home/dev/project/reports/diaspora/results3/people_stream/POLICY_HEADER.txt").read()
p="/home/dev/project/reports/diaspora/results3/queries_from_runs/people_stream.sql"
s=open(p).read(); lines=s.split("\n"); i=0
while i < len(lines) and (lines[i].startswith("--") or not lines[i].strip()): i+=1
open(p,"w").write(hdr.rstrip("\n")+"\n\n"+"\n".join(lines[i:]))
PY
  say "header re-applied; views=$(grep -c '^SELECT' $Q/people_stream.sql)"
else
  say "free=${FG}G other_passes=${OTH} — subsumption NOT attempted, the SKIP_SUBSUME edition stands (state None)"
fi
