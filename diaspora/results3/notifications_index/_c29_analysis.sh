#!/bin/bash
set -u
cd /home/dev/project/reports/diaspora/results3/notifications_index
echo "=== C29 DISPATCH ==="
python3 -u _c29_dispatch.py > _c29_dispatch.out 2>&1
echo "dispatch rc=$? $(tail -1 _c29_dispatch.out)"
echo "=== C29 MUS ==="
MUSW=${MUSW:-4} python3 -u _c29_mus.py > _c29_mus.out 2>&1
echo "mus rc=$? $(tail -1 _c29_mus.out)"
echo "C29-ANALYSIS-DONE"
