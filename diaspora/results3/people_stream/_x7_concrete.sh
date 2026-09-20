#!/bin/bash
# Re-run the Phase 5 CONCRETE round on the X7 frame list (_concrete_targets.rb
# now traces CollectionAssociation#find_target, the frame the `photos` read goes
# through). One process per scenario — JVM crash isolation, so an abort names
# its own scenario — each caged at 2G with a high OOM score.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/people_stream
cd /home/dev/project
for sc in anon_all anon_json anon_handle auth_json; do
  cp -n "$B/concrete_run_$sc.json" "$B/concrete_run_$sc.json.pre_x7_20260911" 2>/dev/null
  echo "[$(date -Is)] concrete $sc"
  CONCOLIC_SLOTS=3 "$B/_caged" 1500M /home/dev/project/reports/diaspora/tools/slot \
    bash -c "unset JAVA_TOOL_OPTIONS; /home/dev/project/scripts/diaspora-concolic /home/dev/project/reports/diaspora/tools/concrete_checker/concrete_run_probe.rb $B/concrete_manifest_$sc.rb" \
    > "$B/_concrete_${sc}_x7.log" 2>&1
  rc=$?
  # concrete_run_probe.rb ALWAYS writes `concrete_run.json` next to the
  # manifest; the per-scenario name is made by RENAMING. Omitting this rename
  # (2026-09-11, first attempt) left merge_concrete_runs.py merging the OLD
  # per-scenario files, so a re-run on a new frame list silently produced the
  # previous run's frames — "a copied list goes stale silently", the same class
  # merge_concrete_runs.py's own header warns about.
  [ -f "$B/concrete_run.json" ] && mv "$B/concrete_run.json" "$B/concrete_run_$sc.json"
  echo "   rc=$rc $(tail -3 "$B/_concrete_${sc}_x7.log" | tr '\n' ' ' | cut -c1-160)"
done
cp -n "$B/concrete_run.json" "$B/concrete_run.json.pre_x7_20260911" 2>/dev/null
python3 "$B/merge_concrete_runs.py"
