#!/bin/bash
# PIPELINE 13c — THE FINAL PASS FOR THE RECORD, then the ENGINE SECTION, then
# the audits. Split in two (see _engine_section.py): a gate killed inside the
# pass would take every coverage number with it, because coverage_report.py
# prints nothing until the very end.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_p13c.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

say "engine coverage.py md5: $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"
say "engine completion.py md5: $(md5sum /home/dev/project/src/concolic_engine/completion.py | cut -d' ' -f1)"
say "snapshot: $(wc -l < "$B/_snapshot_pruned_OD0911.txt") profiles"
find "$B" -maxdepth 1 -name 'dump_*.json' > "$B/_all_dumps_OD0911.txt"
say "corpus: $(wc -l < "$B/_all_dumps_OD0911.txt") dumps"

say "13c-1: THE FINAL PASS, coverage layer [3G cap under the 4G cage, alone, behind the free-6 gate]"
wait_free6 finalpass | tee -a "$L"
wait_alone finalpass | tee -a "$L"
cage p13pass.scope 3G \
  env DUMP_LIST="$B/_snapshot_pruned_OD0911.txt" SUMMARY_OUT="$B/_cov_FINAL_OD0911.json" \
      SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=16 \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/coverage_report.py" > "$B/_covFINAL_OD0911.log" 2>&1
say "13c-1 exit=$?"
caged_verdict p13pass.scope "$B/_covFINAL_OD0911.log" '^COMPLETE=' >> "$L"
grep -E '^\[assumptions\]|^(COMPLETE|GENUINE|dumps_loaded|DEMAND_SETS|peak RSS|wrote|dump_errors)|confine|TREE-MISSING' \
  "$B/_covFINAL_OD0911.log" >> "$L" 2>/dev/null

say "13c-2: THE ENGINE SECTION (shims + notes + the gate on the confined pairs) [5G, alone]"
wait_free6 enginesection | tee -a "$L"
wait_alone enginesection | tee -a "$L"
cage p13eng.scope 3G \
  env SUMMARY_IN="$B/_cov_FINAL_OD0911.json" SUMMARY_OUT="$B/coverage_summary.json" \
      CONCOLIC_SLOTS=1 CONCOLIC_PROBE_WORKERS=1 ACHK_PROBE_BATCH=20 \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_engine_section.py" > "$B/_engine_section.log" 2>&1
say "13c-2 exit=$?"
caged_verdict p13eng.scope "$B/_engine_section.log" '^ENGINE SECTION DONE' >> "$L"
grep -E '^OVERALL_COMPLETE|^  (AUDIT|PASS|FAIL|PROTOCOL|NOTE-CHECK|ASSUMPTIONS|BLOCKING|CONFINEMENT)' \
  "$B/_engine_section.log" >> "$L" 2>/dev/null

say "13c-3: the audit suite [5G, alone] — streaming lint (X12 vehicle)"
wait_free6 audits | tee -a "$L"
wait_alone audits | tee -a "$L"
cage p13aud.scope 3G bash "$B/_c7_audits.sh" > "$B/_c7_audits.out" 2>&1
say "13c-3 exit=$?"
grep -n 'EXIT=' "$B/_c7_audits.log" >> "$L" 2>/dev/null
say "pipeline13c done"
