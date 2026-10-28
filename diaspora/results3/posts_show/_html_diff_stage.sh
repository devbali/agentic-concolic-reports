#!/bin/bash
# STAGE 4, queued behind _finish_sequence.sh (A -> B -> audits) so this drive
# never runs two >1 GB jobs of its own at once. Runs the html arm with §43's
# Person#name wrap in place and RECORDS whichever of the two outcomes happens:
# the arm completes, or it names the next failure point.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
R="$B/_COMPLETION_20260910.md"
WAIT_PID="${1:-0}"
[ "$WAIT_PID" != "0" ] && while kill -0 "$WAIT_PID" 2>/dev/null; do sleep 60; done
say(){ printf '%s\n' "$*" >> "$R"; }

cd /home/dev/project
SFX="_PNWRAP0910"
/home/dev/project/reports/diaspora/tools/slot env MAX_RUNS=3 TIME_BUDGET=600 \
  VARIANTS=auth_html LABEL_SUFFIX="$SFX" \
  /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" > "$B/_pnwrap.log" 2>&1
rc=$?
say ""
say "## §43. The Person#name wrap — the differential, run after the sequence"
say ""
say '```'
echo "runner exit=$rc" >> "$R"
python3 - "$B" "$SFX" >> "$R" <<'PY'
import json,glob,os,sys
B,SFX=sys.argv[1],sys.argv[2]
fs=sorted(glob.glob(os.path.join(B,"dump_auth_html*%s.json"%SFX)))
print("post-wrap html dumps: %d" % len(fs))
for f in fs:
    d=json.load(open(f)); e=d.get("error")
    npc=sum(1 for x in d["events"] if x.get("type")=="path_condition")
    print("  %-34s error=%-22s pcs=%d events=%d" % (
        os.path.basename(f), (e or {}).get("type","(none)"), npc, len(d["events"])))
    if e:
        print("    message: %s" % str(e.get("message"))[:150])
        for ln in str(e.get("traceback","")).split("\n")[:6]:
            print("      %s" % ln.strip())
print("")
print("PRE-WRAP baseline (dump_auth_html0001_CSSPOST0910.json, §14):")
p=os.path.join(B,"dump_auth_html0001_CSSPOST0910.json")
if os.path.exists(p):
    d=json.load(open(p)); e=d.get("error") or {}
    npc=sum(1 for x in d["events"] if x.get("type")=="path_condition")
    print("  error=%s pcs=%d events=%d" % (e.get("type"), npc, len(d["events"])))
    print("  message: %s" % str(e.get("message"))[:150])
PY
say '```'
say ""
say "Read this as §12/§14/§42 read: if the arm still terminates, the site above"
say "IS the next named failure point and the html view's reads remain absent"
say "from the policy (W1). If it completes, §12's cost is closed and the corpus"
say "must be regenerated before any policy claim uses it — the 99 448 existing"
say "dumps were all produced with the arm broken."
