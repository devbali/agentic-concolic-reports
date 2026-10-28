#!/bin/bash
# =============================================================================
# P39 RE-PASS — the coverage verdict AFTER the round-11 drive finally ran.
#
# Corpus = P39R's profiles + the 3 000 P44S1 residue-drive runs. ONE input moved.
#          + the 124 admissible round-11 seeds + the 2 rescued selection misses
#            (labels *P39D3*), constructed in §104 and never driven until now
#          + the 50 witness dumps the P39 foreclosure gate kept (*achk8b776*).
# Flags are P37W's exactly (OR-refined, §16e+§16f ON, W=3, budget 20 000,
# MAX_MISSING_PER_CLIQUE=1), so MISSING/BLOCKING is a clean differential against
# 706/706 and the only input that moved is the corpus.
#
# Verdict: `P31-PASS-DONE P44R` plus the COMPLETE=/MISSING=/BLOCKING= line.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
L="$B/_p44_repass.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
SNAP="$B/_snapshot_p31_P44R.txt"
LIST="$B/_snapshot_pruned_P44R.txt"

nb=$(wc -l < "$B/_snapshot_pruned_P39R.txt")
find "$B" -maxdepth 1 -name 'dump_*P44S1*.json' > "$B/_new_p44_drive.txt"
: > "$B/_new_p44_gate.txt"   # P44: the CONTROL dumps (P44C1/P44C2) are NOT added.
# They realise cubes the corpus already contained, so they would move coverage
# for a reason that has nothing to do with the residue drive and would muddy the
# attribution. Base + the 3 000 P44S1 runs only -- one input moved.
nd=$(wc -l < "$B/_new_p44_drive.txt"); ng=$(wc -l < "$B/_new_p44_gate.txt")
cat "$B/_snapshot_pruned_P39R.txt" "$B/_new_p44_drive.txt" "$B/_new_p44_gate.txt" \
  | sed 's#^\./#'"$B"'/#' | sort -u > "$SNAP"
say "P44-SNAP base $nb + drive $nd + gate-witness $ng = $(wc -l < "$SNAP") unique"
if [ "$nd" = 0 ]; then say "P44-REPASS-FAILED: the drive wrote 0 dumps"; exit 3; fi

say "P44-PRUNE (cap 3G) -> $(basename "$LIST")"
cage "p44pruneP44R.scope" 3G \
  env DUMP_LIST="$SNAP" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_prune_corpus.py" --out "$LIST" > "$B/_p44_prune_P44R.log" 2>&1
grep -q 'distinct outcome profiles' "$B/_p44_prune_P44R.log" || {
  say "P44-REPASS-FAILED prune"; tail -20 "$B/_p44_prune_P44R.log" | tee -a "$L"; exit 4; }
grep 'distinct outcome profiles' "$B/_p44_prune_P44R.log" | tee -a "$L"

say "P44-PASS handing off to _p31_pass.sh P44R - (list already built)"
P31_SKIP_ONEPASS=1 STAMP=20260915 bash "$B/_p31_pass.sh" P44R - >> "$L" 2>&1
rc=$?
say "P44-REPASS EXIT rc=$rc"
grep -E '^COMPLETE=|^DEMAND_SETS=|^SUBCONJ|^CONJ_FOREC|P31-PASS-DONE|P31-PASS-FAILED' \
  "$B/_p31_pass_P44R.log" 2>/dev/null | tee -a "$L"
