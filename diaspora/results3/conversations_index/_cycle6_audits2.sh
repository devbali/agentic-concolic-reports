#!/bin/bash
set -u
# E12 (2026-09-11): src/queries_from_runs is app-agnostic and REQUIRES an
# app config; bind_resolution_audit and identity_symbolicity_audit read the
# schema and the principal columns from it and go RED without one.
export QFR_APP_CONFIG="${QFR_APP_CONFIG:-/home/dev/project/reports/diaspora/queries_config/app.json}"
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
export PYTHONPATH=/home/dev/project/src
VP=/home/dev/project/venvs/queries_from_runs/bin/python
echo "===== bind_resolution (venv python — schema import available)"
$VP src/queries_from_runs/audits/bind_resolution_audit.py "$B" > "$B/_a6_bind_resolution.out" 2>&1
echo "bind_resolution EXIT=$?"; tail -12 "$B/_a6_bind_resolution.out"
echo
echo "===== hardening_lint FULL CORPUS (no --sample; H4 polarity over every dump)"
python3 reports/diaspora/tools/hardening_lint.py "$B" > "$B/_a6_hardening_lint_full.out" 2>&1
echo "hardening_lint_full EXIT=$?"; cat "$B/_a6_hardening_lint_full.out"
echo AUDITS6B_DONE
