#!/bin/bash
# C30 DRIVE — the 96 seeds built by `_c30_construct.py` for the 8 remaining
# confinement-OFF blocking sets. Verdict line: `C13-DRIVE-DONE <tag> +<n>`.
#
# DRIVE_PAR is deliberately CONSERVATIVE and not the box's 14. The 16-core
# formula assumes sole tenancy; it is not sole tenancy right now (posts_show's
# assumption_checker is at ~15 GB and GROWING, plus another agent's coverage
# differential with two JRubies). §40.11a's finding is that the launch gate is
# a ONE-SHOT test that does not protect against a co-tenant that grows, so the
# worker count is sized to the headroom that actually exists, and
# `_chunk_drive.sh` re-gates on `wait_mem` before every JRuby.
set +e
B=/home/dev/project/reports/diaspora/results3/notifications_index
export DRIVE_PAR="${DRIVE_PAR:-4}" CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-4}" JRUBY_CAP="${JRUBY_CAP:-2G}"
echo "=== C30R1 (8 confinement-OFF blocking sets, 96 seeds, fix_seeds re-apply ON) ==="
SEEDSET=A C13_PREF_A=_c30_r1_seeds_ C13_MANIFEST=_c30_r1_drive_manifest.json \
  bash "$B/_c13_drive.sh" C30R1 50
echo "C30-DRIVE-DONE"
