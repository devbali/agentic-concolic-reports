#!/bin/bash
# The four fingerprint proofs for the incremental corpus index, on a
# hardlinked copy of comments_index (26 528 dumps).
set -u
P=/home/dev/project/reports/diaspora/results3/_idx_proof_20260914
S=/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/scratchpad
B=$P/base
CK=$P/base.ckpt.jsonl
export ACHK_HEARTBEAT_S=0
cd $P

run () { echo "### $1"; python3 $S/idx_probe.py "${@:2}"; echo; }

rm -f $CK $CK.stale

echo "=== phase 0: from scratch, no checkpoint at all"
run scratch_nockpt $B - scratch_nockpt

echo "=== phase 1: build the checkpoint (from scratch, writing rows)"
run build $B $CK build

echo "=== proof (a): re-run unchanged"
run resume_unchanged $B $CK resume_unchanged

echo "=== proof (b): +400 dumps"
i=0
for f in $(find $B -maxdepth 1 -name 'dump_*.json' | sort | head -400); do
  cp "$f" "$B/dump_synth$(printf '%05d' $i).json"; i=$((i+1))
done
find $B -maxdepth 1 -name 'dump_*.json' | wc -l
run grown_incremental $B $CK grown_incremental
run grown_scratch $B $P/grown_scratch.ckpt.jsonl grown_scratch

echo "=== proof (c): -300 dumps (150 synthetic, 150 real)"
find $B -maxdepth 1 -name 'dump_synth*.json' | sort | head -150 | xargs rm -f
find $B -maxdepth 1 -name 'dump_*.json' ! -name 'dump_synth*' | sort | head -150 | xargs rm -f
find $B -maxdepth 1 -name 'dump_*.json' | wc -l
run shrunk_incremental $B $CK shrunk_incremental
run shrunk_resume_after_compaction $B $CK shrunk_resume_after_compaction
run shrunk_scratch $B $P/shrunk_scratch.ckpt.jsonl shrunk_scratch

echo "=== proof (d): a changed ENGINE SOURCE"
rm -rf $P/src_variant
cp -a /home/dev/project/src $P/src_variant
echo "# proof (d): an engine source change" >> $P/src_variant/end_to_end_completion_checker/assumption/assumption_checker.py
sed "s#sys.path.insert(0, \"/home/dev/project/src\")#sys.path.insert(0, \"$P/src_variant\")#" \
    $S/idx_probe.py > $P/idx_probe_variant.py
echo "### engine_changed"
python3 $P/idx_probe_variant.py $B $CK engine_changed
echo
echo "### engine_changed_then_back (the ORIGINAL engine, after the variant rotated the log)"
python3 $S/idx_probe.py $B $CK engine_changed_then_back
echo DONE_PROOF
