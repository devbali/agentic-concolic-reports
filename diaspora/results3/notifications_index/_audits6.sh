#!/bin/bash
# The coordinator's SEVEN checks, run by the batch as a pre-check.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
A=/home/dev/project/src/queries_from_runs/audits
LOG="$B/_audits6.log"; echo "=== audits6 $(date -Is) ===" > "$LOG"
run() { echo "" >> "$LOG"; echo "##### $1 #####" >> "$LOG"; shift; "$@" >> "$LOG" 2>&1; echo "EXIT=$?" >> "$LOG"; }
run identity_symbolicity   env PYTHONPATH=/home/dev/project/src python3 $A/identity_symbolicity_audit.py "$B"
run statement_note_lint    env PYTHONPATH=/home/dev/project/src python3 $A/statement_note_lint.py "$B"
run bind_resolution        env PYTHONPATH=/home/dev/project/src /home/dev/project/venvs/queries_from_runs/bin/python $A/bind_resolution_audit.py "$B"
run skipped_pcs            env PYTHONPATH=/home/dev/project/src /home/dev/project/venvs/queries_from_runs/bin/python $A/skipped_pcs_audit.py "$B" --patched /home/dev/project/reports/diaspora/results3/_experiment/variant_d
run pc_visibility          env PYTHONPATH=/home/dev/project/src python3 $A/pc_visibility_audit.py "$B" --gate type,unread,persisted,guid,first_name,last_name,person_id,diaspora_handle,rows,language
run empty_relation         env PYTHONPATH=/home/dev/project/src python3 $A/empty_relation_emission_audit.py "$B"
run noteless_call          env PYTHONPATH=/home/dev/project/src python3 $A/noteless_call_audit.py "$B"
run cardinality_consistency env PYTHONPATH=/home/dev/project/src python3 $A/cardinality_consistency_audit.py "$B"
run note_fidelity          env PYTHONPATH=/home/dev/project/src /home/dev/project/venvs/queries_from_runs/bin/python /home/dev/project/reports/diaspora/tools/note_fidelity_audit.py "$B" "$B/concrete_run.json" --aliases "$B/concrete_aliases.json"
run hardening_lint         env PYTHONPATH=/home/dev/project/src python3 /home/dev/project/reports/diaspora/tools/hardening_lint.py "$B" --sample 400
echo "" >> "$LOG"; echo "=== audits6 DONE $(date -Is) ===" >> "$LOG"
grep -n "EXIT=" "$LOG"
