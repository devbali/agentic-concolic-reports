#!/bin/bash
# cycle 6 — the six SQL-consumer audits + hardening lint, on the pruned corpus.
set -u
# E12 (2026-09-11): src/queries_from_runs is app-agnostic and REQUIRES an
# app config; bind_resolution_audit and identity_symbolicity_audit read the
# schema and the principal columns from it and go RED without one.
export QFR_APP_CONFIG="${QFR_APP_CONFIG:-/home/dev/project/reports/diaspora/queries_config/app.json}"
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
export PYTHONPATH=/home/dev/project/src
run() { n=$1; shift; echo "===== $n"; "$@" > "$B/_a6_$n.out" 2>&1; echo "$n EXIT=$?"; tail -6 "$B/_a6_$n.out"; echo; }
run identity_symbolicity python3 src/queries_from_runs/audits/identity_symbolicity_audit.py "$B"
run statement_note_lint python3 src/queries_from_runs/audits/statement_note_lint.py "$B"
run bind_resolution python3 src/queries_from_runs/audits/bind_resolution_audit.py "$B"
run pc_visibility python3 src/queries_from_runs/audits/pc_visibility_audit.py "$B" --gate persisted,unread,subject,author_id,person_id,conversation_id
run skipped_pcs /home/dev/project/venvs/queries_from_runs/bin/python src/queries_from_runs/audits/skipped_pcs_audit.py "$B" --patched /home/dev/project/reports/diaspora/results3/_experiment/variant_d
run empty_relation python3 src/queries_from_runs/audits/empty_relation_emission_audit.py "$B"
run hardening_lint python3 reports/diaspora/tools/hardening_lint.py "$B" --sample 400
echo AUDITS6_DONE
