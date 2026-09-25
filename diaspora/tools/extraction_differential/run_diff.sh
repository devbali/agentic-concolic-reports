#!/bin/bash
# E12 six-corpus differential: OLD src snapshot vs NEW config-driven src.
S=${DIFF_WORKDIR:?set DIFF_WORKDIR to a scratch dir holding old_src/ and arms/}
PY=/home/dev/project/venvs/queries_from_runs/bin/python3
R3=/home/dev/project/reports/diaspora/results3
SAMPLE=${SAMPLE:-3000}
SEED=20260911
mkdir -p $S/arms
cage () { systemd-run --user --slice=concolic-cov.slice --scope -q -p MemoryMax=1G choom -n 1000 -- "$@"; }
for c in comments_index conversations_index people_show notifications_index people_stream posts_show; do
  L=$S/arms/$c.list
  echo "=== $c OLD ==="
  cage env PYTHONPATH=$S/old_src:/home/dev/project/src $PY ${DIFF_TOOLS:-$(dirname "$0")}/diffarm.py $R3/$c $SAMPLE $SEED $S/arms/${c}_old $L
  echo "=== $c NEW ==="
  cage env PYTHONPATH=/home/dev/project/src $PY ${DIFF_TOOLS:-$(dirname "$0")}/diffarm.py $R3/$c $SAMPLE $SEED $S/arms/${c}_new $L
  python3 ${DIFF_TOOLS:-$(dirname "$0")}/compare.py $S/arms/${c}_old.json $S/arms/${c}_new.json | tee -a $S/arms/RESULTS.txt
done
echo "ALL DONE"
