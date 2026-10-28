#!/bin/bash
# PIPELINE 13a — the RESIDUAL CLASSIFICATION stages (§76.2). Every stage is
# caged, sequential, and prints its own verdict line. Nothing here is >2 G.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_p13a.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

wait_alone p13a | tee -a "$L"
say "13a-1: part report — decompose the OR-refined remaining by part [1G]"
cage p13part.scope 1G env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  TOPN=12 MEMBERS=6 python3 -u "$B/_part_report.py" > "$B/_part_report.log" 2>&1
caged_verdict p13part.scope "$B/_part_report.log" 'PART REPORT DONE' >> "$L"

say "13a-2: realisation table on the OD0911 construction round (§72.4) [2G]"
cage p13real.scope 2G env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  EMIT_IN="$B/_enum_emit_ORDEMAND.json" DRIVE_TAG=OD0911 \
  python3 -u "$B/_gc_realise.py" > "$B/_gc_realise_OD0911.log" 2>&1
caged_verdict p13real.scope "$B/_gc_realise_OD0911.log" 'wrote _gc_realise.json' >> "$L"
grep -E '^  (REALISED|UNEVALUATED|CONTRADICTED)|^gates realised' "$B/_gc_realise_OD0911.log" >> "$L"

say "13a-3: WHY unevaluated — §19's conjunction-foreclosure test [2G]"
cage p13unev.scope 2G env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  EMIT_IN="$B/_enum_emit_ORDEMAND.json" DRIVE_TAG=OD0911 MAXPAIRS=600 \
  DUMP_LIST="$B/_snapshot_pruned_OD0911.txt" \
  python3 -u "$B/_unev_why.py" > "$B/_unev_why.log" 2>&1
caged_verdict p13unev.scope "$B/_unev_why.log" 'UNEV WHY DONE' >> "$L"
grep -E 'CONJUNCTION-FORECLOSURE|REACHABLE |NO-MATCH ' "$B/_unev_why.log" >> "$L"
say "pipeline13a done"
