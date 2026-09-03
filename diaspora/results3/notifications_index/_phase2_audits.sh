#!/bin/bash
# Phase-2 SQL-consumer dump audits (parent-agent manual phase; not gating the
# engine's `complete`, but required by the three-phase closing process).
set +e
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_phase2_audits.log"
V=/home/dev/project/venvs/queries_from_runs/bin/python
FOLD=/home/dev/project/src/queries_from_runs
echo "== phase 2 audits $(date -Is) ==" > "$LOG"
run() { echo "--- $1 ---" >> "$LOG"; "$@" >> "$LOG" 2>&1; echo "exit=$? ($1)" >> "$LOG"; }
flock /tmp/concolic-heavy.lock env PYTHONPATH=src $V $FOLD/audits/identity_symbolicity_audit.py "$B" >> "$LOG" 2>&1; echo "exit=$? identity" >> "$LOG"
flock /tmp/concolic-heavy.lock env PYTHONPATH=src $V $FOLD/audits/statement_note_lint.py "$B" >> "$LOG" 2>&1; echo "exit=$? note_lint" >> "$LOG"
flock /tmp/concolic-heavy.lock env PYTHONPATH=src $V $FOLD/audits/bind_resolution_audit.py "$B" >> "$LOG" 2>&1; echo "exit=$? bind_resolution" >> "$LOG"
flock /tmp/concolic-heavy.lock env PYTHONPATH=src $V $FOLD/audits/skipped_pcs_audit.py "$B" --patched /home/dev/project/reports/diaspora/results3/_experiment/variant_d >> "$LOG" 2>&1; echo "exit=$? skipped_pcs" >> "$LOG"
flock /tmp/concolic-heavy.lock env PYTHONPATH=src $V $FOLD/audits/pc_visibility_audit.py "$B" --gate type,unread,persisted,guid >> "$LOG" 2>&1; echo "exit=$? pc_visibility" >> "$LOG"
echo "== phase 2 DONE $(date -Is) ==" >> "$LOG"
