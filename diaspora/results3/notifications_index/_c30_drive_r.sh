#!/bin/bash
# C30 DRIVE (parameterised) — drive one round's constructed seeds.
#   usage: TAG=C30R2 PREF=_c30_r2_seeds_ MAN=_c30_r2_drive_manifest.json \
#          [CHUNK=50] [DRIVE_PAR=6] bash _c30_drive_r.sh
# Verdict line: `C13-DRIVE-DONE <tag>` from _c13_drive.sh, then C30-DRIVE-DONE.
#
# DRIVE_PAR is sized to the headroom that ACTUALLY EXISTS, not to the box's 14
# (§40.11a: the launch gate is a ONE-SHOT test and does not protect against a
# co-tenant that grows). `_chunk_drive.sh` re-gates on `wait_mem` before every
# JRuby.
set +e
B=/home/dev/project/reports/diaspora/results3/notifications_index
TAG="${TAG:?TAG is required}"; PREF="${PREF:?PREF is required}"
MAN="${MAN:?MAN is required}"; CHUNK="${CHUNK:-50}"
export DRIVE_PAR="${DRIVE_PAR:-6}" CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-6}" JRUBY_CAP="${JRUBY_CAP:-2G}"
echo "=== $TAG (pref $PREF, chunk $CHUNK, par $DRIVE_PAR) ==="
SEEDSET=A C13_PREF_A="$PREF" C13_MANIFEST="$MAN" \
  bash "$B/_c13_drive.sh" "$TAG" "$CHUNK"
echo "C30-DRIVE-DONE"
