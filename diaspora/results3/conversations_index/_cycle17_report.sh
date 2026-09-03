#!/bin/bash
# cycle 17 — REPORT-ONLY re-run on the cycle-16 corpus: c16's gate ran with the
# shim test file BEFORE `cp.loaded?` had a test (NO-TEST baked in). Corpus
# unchanged; manifests updated (single message read on the js 500; a non-admin
# mobile principal for the moderator-exists arm).
set -u
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
echo "=== concrete refresh (salt fix) $(date +%H:%M:%S) ==="
"$B/_cycle6_concrete.sh" > "$B/_concrete17.log" 2>&1; grep -E 'ERROR|merged' "$B/_concrete17.log" | tail -3
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
  2>&1 | tee "$B/_final19.log" | grep -E 'OVERALL_COMPLETE|^COMPLETE=|GENUINE='
echo "[heavy] released $(date +%H:%M:%S)"
python3 -c "
import json;d=json.load(open('$B/coverage_summary.json'));c=d['completion']
print('completion.complete =',c['complete']); print('blocking =',c['blocking'])
print('audits =',[(a['name'],a['green']) for a in c['audits']])
print('shims =',c['shim_verdict_counts']); print('assumps =',c['assumptions']['verdict_counts'],'failures',len(c['assumptions']['failures']))"
echo "=== eight audits $(date +%H:%M:%S) ==="
"$B/_cycle10_audits8.sh" > "$B/_audits17.log" 2>&1
grep -E 'EXIT=|RESULT' "$B/_audits17.log"
echo "=== lint WITH runs $(date +%H:%M:%S) ==="
PYTHONPATH=/home/dev/project/src python3 reports/diaspora/tools/hardening_lint.py "$B" --runs "$B"/concrete_run*.json --sample 0 > "$B/_a17_lint.out" 2>&1
echo "lint EXIT=$?"; sed -n '/-- H4/,$p' "$B/_a17_lint.out" | grep -vE '^\s*$'
echo "=== per-request MULTIPLICITY vs ground truth (counts, not sets) $(date +%H:%M:%S) ==="
python3 "$B/_multiset_counts.py" "$B" --runs "$B/concrete_run.json" > "$B/_a17_multiset.out" 2>&1; echo "multiset EXIT=$?"; tail -4 "$B/_a17_multiset.out"
echo CYCLE17_DONE
