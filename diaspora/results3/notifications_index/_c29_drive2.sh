#!/bin/bash
set +e
B=/home/dev/project/reports/diaspora/results3/notifications_index
export DRIVE_PAR=2 CONCOLIC_SLOTS=2 JRUBY_CAP=2G
echo "=== C29C (OFF cube, demand re-applied after fix_seeds, 44 seeds) ==="
SEEDSET=A C13_PREF_A=_c29off2_seeds_ C13_MANIFEST=_c29off2_drive_manifest.json \
  bash "$B/_c13_drive.sh" C29C 40
echo "C29-DRIVE2-DONE"
