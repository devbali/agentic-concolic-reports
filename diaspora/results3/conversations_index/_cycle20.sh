#!/bin/bash
# cycle 20 — REBUILD under the FINAL round-5 model (A5-7: prev_login_first + the derived IP equality; six trackable shapes). The corpus changed materially:
# C-5 (write follows dirty state), the layout pin's data access (NM-5) + the
# `sum` target, C-6 (conversation_id[] -> IN), C-7 (invalid page), C-8 (js +
# undeclared-format family). 10 variants now, not 6.
set -u
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
VARS="html_plain html_withcid json_plain json_withcid mobile_plain mobile_withcid js_plain js_withcid xml_plain xml_withcid"
echo "=== base exploration $(date +%H:%M:%S) ==="
for v in $VARS; do
  MAX_RUNS=4000 TIME_BUDGET=700 VARIANTS=$v \
    flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 \
    | grep -viE 'deprecat|fog\]|Ignoring activerecord|Top level ::' | tail -3
  echo "-- $v done $(date +%H:%M:%S)"
done
"$B/_cycle6_dedup.sh" 2>&1 | tail -1
M=99
for r in n1 n2 n3 n4 n5 n6 n7 n8; do
  echo "=== coverage $r $(date +%H:%M:%S) ==="
  MMPC=60 "$B/_cycle6_cov.sh" > "$B/_cov20_$r.log" 2>&1
  line=$(grep -E '^COMPLETE=' "$B/_cov20_$r.log" || true)
  if [ -z "$line" ]; then echo "NO VERDICT:"; tail -25 "$B/_cov20_$r.log"; echo CYCLE20_ABORTED; exit 1; fi
  echo "$line"; grep -E 'loaded' "$B/_cov20_$r.log"
  M=$(echo "$line" | sed -E 's/.*MISSING=([0-9]+).*/\1/'); echo "missing=$M"
  [ "$M" = "0" ] && { echo COVERAGE_COMPLETE; break; }
  python3 "$B/mk_hand_seeds2.py" 2>&1 | grep -E 'hand roots|no donor|skip'
  for v in $VARS; do
    [ -f "$B/_hand_$v.json" ] || continue
    # (i) REPLAY every hand root exactly once — SEEDS_ONLY bypasses the
    #     state/path dedup and does no flip expansion: 27 roots -> 27 runs,
    #     seconds, each landing its combination if its seeds are right
    #     (A3-13: 12 -> 18 of 32 assignments in ONE such replay).
    SEEDS_ONLY=1 VARIANTS=$v EXTRA_SEEDS_JSON="$B/_hand_$v.json" LABEL_SUFFIX="_${r}r20" \
      flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 | grep -E 'runs executed' | tr -s ' '
    # (ii) a SHORT expansion from the same roots for the neighbours
    MAX_RUNS=800 TIME_BUDGET=240 VARIANTS=$v EXTRA_SEEDS_JSON="$B/_hand_$v.json" LABEL_SUFFIX="_${r}x20" \
      flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 | grep -E 'distinct paths' | tr -s ' '
  done
  "$B/_cycle6_dedup.sh" 2>&1 | tail -1
done
[ "$M" = "0" ] || { echo "STOP: $M missing."; echo CYCLE20_ABORTED; exit 1; }
echo "=== concrete refresh (salt fix) $(date +%H:%M:%S) ==="
"$B/_cycle6_concrete.sh" > "$B/_concrete24.log" 2>&1; grep -E 'ERROR|merged' "$B/_concrete24.log" | tail -3
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
  2>&1 | tee "$B/_final22.log" | grep -E 'OVERALL_COMPLETE|^COMPLETE=|GENUINE='
echo "[heavy] released $(date +%H:%M:%S)"
python3 -c "
import json;d=json.load(open('$B/coverage_summary.json'));c=d['completion']
print('completion.complete =',c['complete']); print('blocking =',c['blocking'])
print('audits =',[(a['name'],a['green']) for a in c['audits']])
print('shims =',c['shim_verdict_counts']); print('assumps =',c['assumptions']['verdict_counts'],'failures',len(c['assumptions']['failures']))"
echo "=== eight audits $(date +%H:%M:%S) ==="
"$B/_cycle10_audits8.sh" > "$B/_audits20.log" 2>&1
grep -E 'EXIT=|RESULT' "$B/_audits20.log"
echo "=== lint WITH runs $(date +%H:%M:%S) ==="
PYTHONPATH=/home/dev/project/src python3 reports/diaspora/tools/hardening_lint.py "$B" --runs "$B"/concrete_run*.json --sample 0 > "$B/_a20_lint.out" 2>&1
echo "lint EXIT=$?"; sed -n '/-- H4/,$p' "$B/_a20_lint.out" | grep -vE '^\s*$'
echo "=== per-request MULTIPLICITY vs ground truth (counts, not sets) $(date +%H:%M:%S) ==="
python3 "$B/_multiset_counts.py" "$B" --runs "$B/concrete_run.json" > "$B/_a20_multiset.out" 2>&1; echo "multiset EXIT=$?"; tail -4 "$B/_a20_multiset.out"
echo CYCLE20_DONE
