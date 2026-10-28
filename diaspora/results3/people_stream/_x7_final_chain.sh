#!/bin/bash
# Final chain, queued behind any other FULL coverage pass (exclusive rule):
#   1  full engine on the closed corpus
#   2  re-extract + install (subsumption when free -g >= 7 and no pass, else SKIP)
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/people_stream
Q=/home/dev/project/reports/diaspora/results3/queries_from_runs
cd /home/dev/project
say(){ echo "[$(date -Is)] $*" >> "$B/_x7_final_chain.log"; }
: > "$B/_x7_final_chain.log"
# SLOT ORDER (coordinator, 2026-09-11):
#   posts_show's 16c pass -> notifications' final enumeration + certification
#   pass -> THIS chain -> posts_show's re-census.
# Two phases, ported from posts_show/_cage.sh::wait_for_notifications_cert, so
# this neither jumps the queue nor hangs forever if the pass came and went
# unseen: wait for notifications' coverage_report.py to be SEEN running and then
# to EXIT; if it is never seen within the grace, proceed AND SAY SO.
wait_for_notifications_cert() {
  local grace="${1:-7200}" seen=0 w=0 p
  while :; do
    p=$(ps -eo comm=,args= | awk '$1=="python3" && /notifications_index\/coverage_report\.py/' | head -1)
    if [ -n "$p" ]; then
      seen=1
      [ $((w % 600)) -eq 0 ] && say "slot priority: notifications certification pass is RUNNING - waiting (${w}s)"
    else
      if [ "$seen" = 1 ]; then
        say "slot priority: notifications certification pass EXITED after ${w}s - slot released"; return 0
      fi
      if [ "$w" -ge "$grace" ]; then
        say "slot priority: NO notifications pass seen in ${w}s (grace ${grace}s) - proceeding, and saying so"; return 0
      fi
      [ $((w % 600)) -eq 0 ] && say "slot priority: yielding to notifications (not started yet, ${w}s of ${grace}s grace)"
    fi
    sleep 60; w=$((w+60))
  done
}
while pgrep -f "results3/posts_show/coverage_report.py" >/dev/null; do sleep 60; done
say "posts_show pass exited"
wait_for_notifications_cert 7200
while pgrep -f "results3/(posts_show|notifications_index|comments_index|conversations_index|people_show)/coverage_report.py" >/dev/null; do sleep 60; done
say "pass slot free - full engine"
"$B/_caged" 3G env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  /home/dev/project/venvs/queries_from_runs/bin/python -u "$B/coverage_report.py" > "$B/_engine_20260911_final2.log" 2>&1
say "engine rc=$? :: $(grep -E '^OVERALL_COMPLETE|^COMPLETE=' "$B/_engine_20260911_final2.log" | tr '\n' ' ')"
FG=$(free -g | awk '/^Mem/{print $7}')
if [ "$FG" -ge 7 ] && ! pgrep -f "coverage_report.py" >/dev/null; then
  say "free=${FG}G and no pass — extraction WITH subsumption at 6G"
  "$B/_caged" 6G env OUT_SQL=$Q/people_stream.sql OUT_SUMMARY=$Q/_summary_people_stream.json \
    JAVA_TOOL_OPTIONS= PYTHONPATH=/home/dev/project/src \
    /home/dev/project/venvs/queries_from_runs/bin/python -u $Q/_extract_people_stream_streaming.py \
    > $Q/_extract_people_stream_X7_20260911.log 2>&1
else
  say "free=${FG}G — no 6G window; extraction with SKIP_SUBSUME=1 (state None, never True)"
  "$B/_caged" 2G env SKIP_SUBSUME=1 OUT_SQL=$Q/people_stream.sql OUT_SUMMARY=$Q/_summary_people_stream.json \
    JAVA_TOOL_OPTIONS= PYTHONPATH=/home/dev/project/src \
    /home/dev/project/venvs/queries_from_runs/bin/python -u $Q/_extract_people_stream_streaming.py \
    > $Q/_extract_people_stream_X7_20260911.log 2>&1
fi
say "extraction rc=$? :: $(grep -E '^people_stream: ' $Q/_extract_people_stream_X7_20260911.log)"
python3 - <<'PY'
hdr=open("/home/dev/project/reports/diaspora/results3/people_stream/POLICY_HEADER.txt").read()
p="/home/dev/project/reports/diaspora/results3/queries_from_runs/people_stream.sql"
s=open(p).read(); lines=s.split("\n"); i=0
while i < len(lines) and (lines[i].startswith("--") or not lines[i].strip()): i+=1
open(p,"w").write(hdr.rstrip("\n")+"\n\n"+"\n".join(lines[i:]))
PY
say "header re-applied; views=$(grep -c '^SELECT' $Q/people_stream.sql) todo=$(grep -c 'TODO(drive)' $Q/people_stream.sql)"
