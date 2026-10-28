#!/bin/bash
# C29 drive — the two enabling-gate-built rounds, ON cube then OFF cube.
set +e
B=/home/dev/project/reports/diaspora/results3/notifications_index
export DRIVE_PAR=2 CONCOLIC_SLOTS=2 JRUBY_CAP=2G
echo "=== C29A (ON cube, 68 seeds) ==="
SEEDSET=A C13_PREF_A=_c29on_seeds_ C13_MANIFEST=_c29on_drive_manifest.json \
  bash "$B/_c13_drive.sh" C29A 40
echo "=== C29B (OFF cube, 44 seeds) ==="
SEEDSET=A C13_PREF_A=_c29off_seeds_ C13_MANIFEST=_c29off_drive_manifest.json \
  bash "$B/_c13_drive.sh" C29B 40
echo "C29-DRIVE-ALL-DONE"
