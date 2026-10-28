#!/bin/bash
# One structural iteration: re-seed by OVERLAY from the current remaining set,
# drive it, re-enumerate. Caged; JRuby 1500M, python 2G, never concurrent.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/people_stream; cd /home/dev/project
TAG="$1"; PREV="$2"
find "$B" -maxdepth 1 -name 'dump_*.json' | sort > "$B/_snapshot_$TAG.txt"
rm -f "$B"/_setR_*.json
"$B/_caged" 2G env TAG="$TAG" SOLVE_EXCEPTIONS=1 BASES_PER_GROUP=5 \
  TARGETS="$B/_remaining_$PREV.jsonl" DUMP_LIST="$B/_snapshot_$TAG.txt" PYTHONPATH=/home/dev/project/src \
  /home/dev/project/venvs/queries_from_runs/bin/python -u "$B/_set_root.py" > "$B/_setr_$TAG.log" 2>&1
python3 -c "
import json,glob
roots=[]
for f in sorted(glob.glob('$B/_setR_*.json')):
    if f.endswith('_all.json'): continue
    roots.extend(json.load(open(f)))
json.dump(roots, open('$B/_setR_all.json','w')); print('seeds', len(roots))"
"$B/_x7_rooted_round.sh" "$B/_setR_all.json" "_$TAG" 4000 1800 > "$B/_round_$TAG.out" 2>&1
find "$B" -maxdepth 1 -name 'dump_*.json' | sort > "$B/_snapshot_$TAG.txt"
"$B/_caged" 2G env DUMP_LIST="$B/_snapshot_$TAG.txt" EMIT_REMAINING="$B/_remaining_$TAG.jsonl" PYTHONPATH=/home/dev/project/src \
  /home/dev/project/venvs/queries_from_runs/bin/python -u "$B/_exact_enum.py" --json-out "$B/_enum_$TAG.json" > "$B/_enum_$TAG.log" 2>&1
echo "[$TAG] corpus=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l) $(grep -E '^EXACT:' "$B/_enum_$TAG.log")"
