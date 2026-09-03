#!/bin/bash
set -u
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
until grep -q 'CHAIN2_DONE' "$B/_chain2.log" 2>/dev/null; do sleep 20; done
echo "--- hand round ---"
V=html_withcid SUF=_h1 MAXR=3000 "$B/_cycle5_hand.sh"
echo "--- coverage C ---"
"$B/_cycle5_cov.sh" > "$B/_cov5_c.log" 2>&1
grep -E 'COMPLETE=|loaded|EXIT=' "$B/_cov5_c.log"
echo CHAIN3_DONE
