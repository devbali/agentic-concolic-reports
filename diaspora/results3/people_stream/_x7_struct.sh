#!/bin/bash
# STRUCTURAL closure of the remaining combinations (RUNBOOK Phase 2, coordinator
# directive 2026-09-11). Queued behind any other coverage/enumeration pass on the
# box — one at a time is the rule.
#   stage 1  _exact_enum.py  EMIT_REMAINING -> _remaining_X7.jsonl  (exact census)
#   stage 2  _set_root.py    OVERLAY seeds  -> _setR_<variant>.json (no per-cube Z3)
#   stage 3  one caged rooted round per variant, unique LABEL_SUFFIX
#   stage 4  re-enumerate and explain per key
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/people_stream
cd /home/dev/project
say(){ echo "[$(date -Is)] $*" >> "$B/_x7_struct.log"; }
: > "$B/_x7_struct.log"
while pgrep -f "posts_show/coverage_report.py|notifications_index/coverage_report.py|_exact_enum|confinement_census" | grep -qv "$$"; do sleep 60; done
say "box free — stage 1 enumeration"
find "$B" -maxdepth 1 -name 'dump_*.json' | sort > "$B/_snapshot_X7.txt"
say "DUMP_LIST snapshot: $(wc -l < "$B/_snapshot_X7.txt") dumps"
"$B/_caged" 2500M env DUMP_LIST="$B/_snapshot_X7.txt" EMIT_REMAINING="$B/_remaining_X7.jsonl" \
  PYTHONPATH=/home/dev/project/src \
  /home/dev/project/venvs/queries_from_runs/bin/python -u "$B/_exact_enum.py" \
  --json-out "$B/_enum_X7.json" >> "$B/_x7_struct.log" 2>&1
say "stage 1 rc=$? remaining=$(wc -l < "$B/_remaining_X7.jsonl" 2>/dev/null || echo NA)"
