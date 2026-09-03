#!/bin/bash
# The EIGHT SQL-consumer audits + the hardening lint over the FULL corpus.
# None of these run Z3, so none takes the heavy lock.
set -u
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
export PYTHONPATH=/home/dev/project/src
VP=/home/dev/project/venvs/queries_from_runs/bin/python
GATE=$(python3 -c "import json;print(','.join(json.load(open('$B/completion_config.json'))['pc_gate_columns']))")
echo "gate: $GATE"
run() { n=$1; shift; "$@" > "$B/_a8_$n.out" 2>&1; e=$?; echo "$n EXIT=$e"; tail -3 "$B/_a8_$n.out"; echo; }
run identity_symbolicity  python3 src/queries_from_runs/audits/identity_symbolicity_audit.py "$B"
run statement_note_lint   python3 src/queries_from_runs/audits/statement_note_lint.py "$B"
run bind_resolution       $VP    src/queries_from_runs/audits/bind_resolution_audit.py "$B"
run pc_visibility         python3 src/queries_from_runs/audits/pc_visibility_audit.py "$B" --gate "$GATE"
run skipped_pcs           $VP    src/queries_from_runs/audits/skipped_pcs_audit.py "$B" --patched /home/dev/project/reports/diaspora/results3/_experiment/variant_d
run empty_relation        python3 src/queries_from_runs/audits/empty_relation_emission_audit.py "$B"
run noteless_call         python3 src/queries_from_runs/audits/noteless_call_audit.py "$B"
run cardinality           python3 src/queries_from_runs/audits/cardinality_consistency_audit.py "$B"
run hardening_lint_full   python3 reports/diaspora/tools/hardening_lint.py "$B" --sample 0
echo AUDITS8_DONE
