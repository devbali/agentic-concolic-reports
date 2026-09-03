#!/bin/bash
# cycle 23 — ROUND-7 CLOSE after the multiset repairs (A7-4..A7-7) and the new
# js populated-inbox ground truth (A7-6). The CORPUS is unchanged (no model
# edit was needed: both OVERs were instrument-scope defects), so this is the
# closing set only: GATE dry run, full report (the completion gate re-reads the
# refreshed concrete_run.json), eight audits, lint with runs, crash census,
# boundary declaration, and the multiset matrix with runs passed EXPLICITLY.
set -u
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
echo "=== pre-flight: every distinct PC expr vs GATE_TABLE $(date +%H:%M:%S) ==="
cd "$B" && PYTHONPATH=/home/dev/project/src python3 - <<'PY'
import json,glob,re,importlib.util
spec=importlib.util.spec_from_file_location("ca","coverage_assumptions.py"); ca=importlib.util.module_from_spec(spec); spec.loader.exec_module(ca)
seen=set(); n=0
for f in glob.glob('dump_*.json'):
    try: d=json.load(open(f))
    except Exception: continue
    n+=1
    for e in d.get('events',()):
        if e.get('type')=='path_condition': seen.add(re.sub(r'\(len\(([A-Za-z0-9_]+)\)',r'(SYM_LEN_\1',e['expr']))
und=sorted(x for x in seen if ca._gate_info(x)[0]=="UNKNOWN")
print(f'dumps {n} distinct exprs {len(seen)} UNDOCUMENTED {len(und)}'); [print('  ',x) for x in und]
print('DRYRUN_CLEAN' if not und else 'DRYRUN_DIRTY')
PY
cd /home/dev/project
echo "=== FULL engine report $(date +%H:%M:%S) ==="
echo "[heavy] waiting $(date +%H:%M:%S)"
flock /tmp/concolic-heavy.lock bash -c '
echo "[heavy] acquired $(date +%H:%M:%S)"
MAX_MISSING_PER_CLIQUE=60 PYTHONPATH=/home/dev/project/src \
  python3 /home/dev/project/reports/diaspora/results3/conversations_index/coverage_report.py' \
  2>&1 | tee "$B/_final27b.log" | grep -E 'OVERALL_COMPLETE|^COMPLETE=|GENUINE='
echo "[heavy] released $(date +%H:%M:%S)"
python3 -c "
import json;d=json.load(open('$B/coverage_summary.json'));c=d['completion']
print('completion.complete =',c['complete']); print('blocking =',c['blocking'])
print('audits =',[(a['name'],a['green']) for a in c['audits']])
print('shims =',c['shim_verdict_counts']); print('assumps =',c['assumptions']['verdict_counts'],'failures',len(c['assumptions']['failures']))"
echo "=== eight audits $(date +%H:%M:%S) ==="
"$B/_cycle10_audits8.sh" > "$B/_audits23b.log" 2>&1
grep -E 'EXIT=|RESULT' "$B/_audits23b.log"
echo "=== lint WITH runs $(date +%H:%M:%S) ==="
PYTHONPATH=/home/dev/project/src python3 reports/diaspora/tools/hardening_lint.py "$B" --runs "$B"/concrete_run*.json --sample 0 > "$B/_a23b_lint.out" 2>&1
echo "lint EXIT=$?"; sed -n '/-- H4/,$p' "$B/_a23b_lint.out" | grep -vE '^\s*$'
echo "=== crash census $(date +%H:%M:%S) ==="
python3 reports/diaspora/tools/rig_crash_census.py "$B" > "$B/_rig_crash_census.out" 2>&1; echo "census EXIT=$?"; tail -3 "$B/_rig_crash_census.out"
echo "=== boundary declaration $(date +%H:%M:%S) ==="
python3 reports/diaspora/tools/boundary_declaration_audit.py "$B" > "$B/_boundary_decl.out" 2>&1; echo "boundary EXIT=$?"; tail -2 "$B/_boundary_decl.out"
echo "=== multiset matrix (runs passed EXPLICITLY) $(date +%H:%M:%S) ==="
for r in "$B/concrete_run.json" "$B/concrete_run_auth.json" "$B/concrete_run_mobile.json" \
         "$B/adversary7/runs/A1_reverify_interactions.json" "$B/adversary7/runs/A2_multiplicity_participants.json" \
         "$B/adversary7/runs/A3_absent_profile.json"; do
  echo "-- $(basename "$r")"
  python3 "$B/_multiset_counts.py" "$B" "$r" 2>&1 | grep -E "^  (OVER|UNDER)|RESULT|count-exact"
done
echo "-- ALL RUNS TOGETHER"
python3 "$B/_multiset_counts.py" "$B" "$B/concrete_run_auth.json" "$B/concrete_run_mobile.json" \
  "$B/adversary7/runs/A1_reverify_interactions.json" "$B/adversary7/runs/A2_multiplicity_participants.json" \
  "$B/adversary7/runs/A3_absent_profile.json" 2>&1 | grep -E "^  (OVER|UNDER)|RESULT|count-exact|layout classes"
echo CYCLE23B_DONE
