#!/bin/bash
# Proof (e): the declared set is not part of the index's identity, and the
# ALIAS declarations are. people_stream (13 677 dumps, idle, closed) is read
# ONLY; every checkpoint is written into the _idx_proof directory.
set -u
P=/home/dev/project/reports/diaspora/results3/_idx_proof_20260914
S=/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/scratchpad
B=/home/dev/project/reports/diaspora/results3/people_stream
CANON=gate_canon:canonicalize_for_gate
export ACHK_HEARTBEAT_S=0
cd $P
rm -f $P/psA.ckpt.jsonl $P/psA.ckpt.jsonl.stale $P/psB.ckpt.jsonl $P/psC.ckpt.jsonl

run () { echo "### $1"; python3 $S/idx_probe.py "${@:2}"; echo; }

echo "=== e1: from scratch under declared set A, no checkpoint"
run A_scratch_nockpt --declared $P/declared_A.json --canon $CANON $B - A_scratch_nockpt

echo "=== e2: build the checkpoint under A"
run A_build --declared $P/declared_A.json --canon $CANON $B $P/psA.ckpt.jsonl A_build

echo "=== e3: resume A's checkpoint under a MATERIALLY DIFFERENT declared set B"
run B_resume_A_ckpt --declared $P/declared_B.json --canon $CANON $B $P/psA.ckpt.jsonl B_resume_A_ckpt

echo "=== e4: from scratch under B (does the declared set change a ROW?)"
run B_scratch --declared $P/declared_B.json --canon $CANON $B $P/psB.ckpt.jsonl B_scratch

echo "=== e5: from scratch under C = A + one ALIAS declaration"
run C_scratch --declared $P/declared_C.json --canon $CANON $B $P/psC.ckpt.jsonl C_scratch

echo "=== e6: resume A's checkpoint under C (must REBUILD)"
run C_resume_A_ckpt --declared $P/declared_C.json --canon $CANON $B $P/psA.ckpt.jsonl C_resume_A_ckpt
echo DONE_DECLARED
