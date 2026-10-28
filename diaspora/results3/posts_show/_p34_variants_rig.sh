#!/bin/bash
# VARIANTS differential rig — §94.5a. Private copy of the runner; HERE is this
# scratch dir, so NOT ONE DUMP LANDS IN posts_show/.  Does NOT use tools/slot.
set -u
S=/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/scratchpad/vrig
export PATH="/home/dev/tools/jdk-21.0.5/bin:/home/dev/tools/jruby-9.3.0.0/bin:$PATH"
cond="$1"; shift
suffix="_dif${cond}"
rm -f "$S"/dump_*"${suffix}".json
env SEEDS_ONLY=1 EXTRA_SEEDS_JSON="$S/roots200.json" LABEL_SUFFIX="$suffix" \
    JAVA_TOOL_OPTIONS= MAX_RUNS=100000 TIME_BUDGET=900 "$@" \
    /home/dev/project/scripts/diaspora-concolic "$S/run_dse.rb" \
    > "$S/cond_${cond}.log" 2>&1
echo "EXIT rc=$? cond=$cond dumps=$(ls "$S"/dump_*"${suffix}".json 2>/dev/null | wc -l)"
