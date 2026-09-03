#!/bin/bash
# cycle-10 standalone audit sweep
set -u
P=/home/dev/project
B=$P/reports/diaspora/results3/comments_index
O=$B/_c10
A=$P/src/queries_from_runs/audits
export PYTHONPATH=$P/src
unset JAVA_TOOL_OPTIONS
cd $P
run(){ n=$1; shift; echo "=== $n START $(date +%T)"; "$@" > $O/audit_$n.out 2>&1; echo "=== $n EXIT=$? $(date +%T)"; tail -4 $O/audit_$n.out; }
run identity_symbolicity   python3 $A/identity_symbolicity_audit.py $B
run statement_note_lint    python3 $A/statement_note_lint.py $B
run bind_resolution        python3 $A/bind_resolution_audit.py $B
run skipped_pcs            python3 $A/skipped_pcs_audit.py $B --patched $P/reports/diaspora/results3/_experiment/variant_d
run pc_visibility          python3 $A/pc_visibility_audit.py $B --gate public,diaspora_handle,author_id,person_id,language,type
run empty_relation_emission python3 $A/empty_relation_emission_audit.py $B
run noteless_call          python3 $A/noteless_call_audit.py $B
run cardinality_consistency python3 $A/cardinality_consistency_audit.py $B
echo "ALLDONE $(date +%T)"
