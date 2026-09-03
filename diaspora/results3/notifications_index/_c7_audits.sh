#!/bin/bash
# C7 closing checks — every judge, current tools, populations printed.
# Run AFTER the regenerated corpus exists. No outer flock anywhere: the only
# heavy phase (coverage) self-locks, and these are bounded scans.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
A=/home/dev/project/src/queries_from_runs/audits
T=/home/dev/project/reports/diaspora/tools
V=/home/dev/project/venvs/queries_from_runs/bin/python
LOG="$B/_c7_audits.log"; echo "=== c7 audits $(date -Is) ===" > "$LOG"
echo "corpus POPULATION: $(ls $B/dump_*.json 2>/dev/null | wc -l) dumps" >> "$LOG"
run() { echo "" >> "$LOG"; echo "##### $1 #####" >> "$LOG"; shift; "$@" >> "$LOG" 2>&1; echo "EXIT=$?" >> "$LOG"; }

run identity_symbolicity    env PYTHONPATH=/home/dev/project/src python3 $A/identity_symbolicity_audit.py "$B"
run statement_note_lint     env PYTHONPATH=/home/dev/project/src python3 $A/statement_note_lint.py "$B"
run bind_resolution         env PYTHONPATH=/home/dev/project/src $V $A/bind_resolution_audit.py "$B"
# MANDATORY BOTH WAYS before any extraction (RUNBOOK 2026-09-01): vanilla and
# patched. If they differ the extractor MUST install variant_d's assoc_fold.
run skipped_pcs_VANILLA     env PYTHONPATH=/home/dev/project/src $V $A/skipped_pcs_audit.py "$B"
run skipped_pcs_PATCHED     env PYTHONPATH=/home/dev/project/src $V $A/skipped_pcs_audit.py "$B" --patched /home/dev/project/reports/diaspora/results3/_experiment/variant_d
run pc_visibility           env PYTHONPATH=/home/dev/project/src python3 $A/pc_visibility_audit.py "$B" --gate type,unread,persisted,guid,first_name,last_name,person_id,diaspora_handle,rows,language
run empty_relation          env PYTHONPATH=/home/dev/project/src python3 $A/empty_relation_emission_audit.py "$B"
run noteless_call           env PYTHONPATH=/home/dev/project/src python3 $A/noteless_call_audit.py "$B"
run cardinality_consistency env PYTHONPATH=/home/dev/project/src python3 $A/cardinality_consistency_audit.py "$B"
run rig_crash_census        python3 $T/rig_crash_census.py "$B"
run boundary_declaration    env PYTHONPATH=/home/dev/project/src python3 $T/boundary_declaration_audit.py "$B" /home/dev/project/reports/diaspora/results3/comments_index /home/dev/project/reports/diaspora/results3/conversations_index
run format_coverage         python3 "$B/format_coverage_audit.py" "$B"
run note_fidelity           env PYTHONPATH=/home/dev/project/src $V $T/note_fidelity_audit.py "$B" "$B/concrete_run.json" --aliases "$B/concrete_aliases.json"
# H6 needs ONE --runs followed by EVERY run file, or it is skipped.
run hardening_lint          env PYTHONPATH=/home/dev/project/src python3 $T/hardening_lint.py "$B" --sample 400 \
      --runs "$B/concrete_run.json" $(ls "$B"/_c7_cr_*.json 2>/dev/null) $(ls "$B"/adversary/runs/A0*.json 2>/dev/null)
run count_matrix            python3 "$B/_c7_count_matrix.py" "$B" --runs "$B/concrete_run.json"
run variant_tuple_check     python3 "$B/_c7_variant_tuple_check.py"
echo "" >> "$LOG"; echo "=== c7 audits DONE $(date -Is) ===" >> "$LOG"
grep -n "EXIT=" "$LOG"
