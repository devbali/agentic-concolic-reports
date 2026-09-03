#!/bin/bash
set -u
B=/home/dev/project/reports/diaspora/results3/conversations_index
until grep -q '^DONE' "$B/_regen5.log" 2>/dev/null; do sleep 20; done
echo "regen finished $(date +%H:%M)"
"$B/_cycle5_demand.sh"
