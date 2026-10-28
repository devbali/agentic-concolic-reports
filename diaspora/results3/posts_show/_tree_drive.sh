#!/bin/bash
# ROOTED TREE DRIVE for posts_show (2026-09-10 completion drive).
# One JRuby per (target, variant) seed file, so a native abort costs at most
# one file and NAMES itself instead of taking the whole round with it
# (notifications _chunk_drive.sh's lesson, at this round's much smaller scale:
# 45 seeds over 11 targets).
# Each invocation gets its own LABEL_SUFFIX (TAG + target + variant), as the
# standing "dump labels must be unique per INVOCATION" correction requires.
# usage: _tree_drive.sh <TAG> [t01 t02 ...]
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/posts_show
TAG="$1"; shift
# SEEDFILE PREFIX: `_treeR_` is the narrow round (`_tree_root.py`, 8 richest
# bases per target/variant); `_treeW_` is the WIDE round (`_tree_root_wide.py`,
# every DISTINCT base seed dict that reaches the site, up to --cap). The brief
# requires driving at a genuinely unreachable side TWICE before it may be
# declared, and these are the two rounds.
PFX="${PFX:-R}"
LOG="$B/_tree_drive_${TAG}.log"
export CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-3}"
say(){ echo "[$(date -Is)] $*" >> "$LOG"; }
: > "$LOG"
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "=== TREE DRIVE $TAG  corpus before: $before dumps  slots=$CONCOLIC_SLOTS ==="

FILES=""
if [ "$#" -gt 0 ]; then
  for t in "$@"; do FILES="$FILES $(find "$B" -maxdepth 1 -name "_tree${PFX}_${t}_*.json" | sort)"; done
else
  FILES="$(find "$B" -maxdepth 1 -name "_tree${PFX}_t*.json" | sort)"
fi

JOBS="$B/_treejobs_${TAG}.txt"; : > "$JOBS"
for f in $FILES; do
  base=$(basename "$f" .json)              # _tree<PFX>_tNN_<variant>
  tk=$(echo "$base" | cut -d_ -f3)
  v=$(echo "$base" | cut -d_ -f4-)
  echo "$f $tk $v $TAG" >> "$JOBS"
done
say "$(wc -l < "$JOBS") (target,variant) jobs queued"

cat > "$B/_treeworker_${TAG}.sh" <<'WS'
#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
F="$1"; TK="$2"; V="$3"; TAG="$4"
N=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$F")
SFX="_${TAG}${TK}$(echo "$V" | cut -c1-2)$(echo "$V" | cut -d_ -f2 | cut -c1-2)"
/home/dev/project/reports/diaspora/tools/slot env VARIANTS="$V" SEEDS_ONLY=1 \
  EXTRA_SEEDS_JSON="$F" LABEL_SUFFIX="$SFX" \
  MAX_RUNS=100000 TIME_BUDGET=1800 \
  /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" \
  > "$B/_treelog_${TAG}_${TK}_${V}.log" 2>&1
rc=$?
got=$(find "$B" -maxdepth 1 -name "dump_*${SFX}.json" | wc -l)
echo "[$(date -Is)] $TK $V seeds=$N rc=$rc dumps=$got suffix=$SFX" >> "$B/_tree_drive_${TAG}.log"
WS
chmod +x "$B/_treeworker_${TAG}.sh"
xargs -P "${DRIVE_PAR:-2}" -L1 "$B/_treeworker_${TAG}.sh" < "$JOBS"

after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "corpus after: $after dumps (+$((after-before)))"
say "=== TREE DRIVE $TAG END ==="
