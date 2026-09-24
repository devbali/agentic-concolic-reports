#!/bin/bash
# cycle 6 final audit sweep — the six SQL-consumer audits with the CYCLE-6 gate
# list, bind_resolution under the queries_from_runs venv (a plain python3 makes
# it degrade to NAME-LEVEL ONLY and false-RED every SYM_PARAM_* bind).
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
GATE=$(python3 -c "import json;print(','.join(json.load(open('$B/completion_config.json'))['pc_gate_columns']))")
echo "gate: $GATE"
run() { n=$1; shift; echo "===== $n"; "$@" > "$B/_a6f_$n.out" 2>&1; echo "$n EXIT=$?"; tail -8 "$B/_a6f_$n.out"; echo; }
run identity_symbolicity python3 src/queries_from_runs/audits/identity_symbolicity_audit.py "$B"
run statement_note_lint python3 src/queries_from_runs/audits/statement_note_lint.py "$B"
run bind_resolution $VP src/queries_from_runs/audits/bind_resolution_audit.py "$B"
run pc_visibility python3 src/queries_from_runs/audits/pc_visibility_audit.py "$B" --gate "$GATE"
run skipped_pcs $VP src/queries_from_runs/audits/skipped_pcs_audit.py "$B" --patched /home/dev/project/reports/diaspora/results3/_experiment/variant_d
run empty_relation python3 src/queries_from_runs/audits/empty_relation_emission_audit.py "$B"
run hardening_lint python3 reports/diaspora/tools/hardening_lint.py "$B" --sample 400
echo AUDITS6F_DONE
