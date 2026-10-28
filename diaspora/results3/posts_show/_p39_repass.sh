#!/bin/bash
# =============================================================================
# P39 RE-PASS — the coverage verdict AFTER the round-11 drive finally ran.
#
# Corpus = P37W's 49 568 profiles
#          + the 124 admissible round-11 seeds + the 2 rescued selection misses
#            (labels *P39D3*), constructed in §104 and never driven until now
#          + the 50 witness dumps the P39 foreclosure gate kept (*achk8b776*).
# Flags are P37W's exactly (OR-refined, §16e+§16f ON, W=3, budget 20 000,
# MAX_MISSING_PER_CLIQUE=1), so MISSING/BLOCKING is a clean differential against
# 706/706 and the only input that moved is the corpus.
#
# Verdict: `P31-PASS-DONE P39R` plus the COMPLETE=/MISSING=/BLOCKING= line.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
L="$B/_p39_repass.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
SNAP="$B/_snapshot_p31_P39R.txt"
LIST="$B/_snapshot_pruned_P39R.txt"

nb=$(wc -l < "$B/_snapshot_pruned_P37W.txt")
find "$B" -maxdepth 1 -name 'dump_*P39D3*.json' > "$B/_new_p39_drive.txt"
find "$B" -maxdepth 1 -name 'dump_*achk8b776*.json' > "$B/_new_p39_gate.txt"
nd=$(wc -l < "$B/_new_p39_drive.txt"); ng=$(wc -l < "$B/_new_p39_gate.txt")
cat "$B/_snapshot_pruned_P37W.txt" "$B/_new_p39_drive.txt" "$B/_new_p39_gate.txt" \
  | sed 's#^\./#'"$B"'/#' | sort -u > "$SNAP"
say "P39-SNAP base $nb + drive $nd + gate-witness $ng = $(wc -l < "$SNAP") unique"
if [ "$nd" = 0 ]; then say "P39-REPASS-FAILED: the drive wrote 0 dumps"; exit 3; fi

say "P39-PRUNE (cap 3G) -> $(basename "$LIST")"
cage "p39pruneP39R.scope" 3G \
  env DUMP_LIST="$SNAP" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_prune_corpus.py" --out "$LIST" > "$B/_p39_prune_P39R.log" 2>&1
grep -q 'distinct outcome profiles' "$B/_p39_prune_P39R.log" || {
  say "P39-REPASS-FAILED prune"; tail -20 "$B/_p39_prune_P39R.log" | tee -a "$L"; exit 4; }
grep 'distinct outcome profiles' "$B/_p39_prune_P39R.log" | tee -a "$L"

say "P39-PASS handing off to _p31_pass.sh P39R - (list already built)"
P31_SKIP_ONEPASS=1 STAMP=20260915 bash "$B/_p31_pass.sh" P39R - >> "$L" 2>&1
rc=$?
say "P39-REPASS EXIT rc=$rc"
grep -E '^COMPLETE=|^DEMAND_SETS=|^SUBCONJ|^CONJ_FOREC|P31-PASS-DONE|P31-PASS-FAILED' \
  "$B/_p31_pass_P39R.log" 2>/dev/null | tee -a "$L"
