#!/bin/bash
# X12 EQUIVALENCE PROOF, the way the digest fix proved its: OLD vs NEW on the
# SAME input, full output diffed BYTE FOR BYTE.
#
# Both arms run by GLOB over one symlink directory (no DUMP_LIST on either), so
# the only variable is the algorithm — the input path is identical. A third arm
# then runs NEW with DUMP_LIST over the real batch dir on the same file set, to
# show DUMP_LIST selects the same input and prints the same bytes.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
S=/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/scratchpad
A=/home/dev/project/src/queries_from_runs/audits/statement_note_lint.py
. "$B/_cage.sh"
L="$B/_x12_equiv.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

# hold until the detached audits stage exits
while systemctl --user is-active pxaudits3.scope >/dev/null 2>&1; do sleep 30; done
say "audits stage exited; free -g:"; free -g | sed -n 2p >> "$L"
say "slice MemoryCurrent: $(systemctl --user show concolic-cov.slice -p MemoryCurrent)"

D="$S/x12dir"; rm -rf "$D"; mkdir -p "$D"
awk 'NR%7==1' "$B/_snapshot_20260910_p5.txt" | head -20000 > "$S/x12_list.txt"
n=0; while read -r f; do ln -s "$f" "$D/$(basename "$f")" && n=$((n+1)); done < "$S/x12_list.txt"
say "symlinked $n dumps into $D"
( cd "$D" && ls dump_*.json > "$S/x12_names.txt" )

say "arm 1: OLD (retain-every-event), caged 3G"
cage pxlintold.scope 3G env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  timeout 3600 python3 "$S/lint_OLD.py" "$D" > "$B/_x12_old.out" 2>&1
say "arm 1 rc=$? ; peak: $(systemctl --user show pxlintold.scope -p MemoryPeak 2>/dev/null)"

say "arm 2: NEW (streamed), caged 3G"
cage pxlintnew.scope 3G env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  timeout 3600 python3 "$A" "$D" > "$B/_x12_new.out" 2>&1
say "arm 2 rc=$?"

say "arm 3: NEW with DUMP_LIST over the real batch dir, same file set"
cage pxlintdl.scope 3G env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  DUMP_LIST="$S/x12_names.txt" timeout 3600 python3 "$A" "$D" > "$B/_x12_dl.out" 2>&1
say "arm 3 rc=$?"

say "=== BYTE-FOR-BYTE DIFF ==="
if diff -q "$B/_x12_old.out" "$B/_x12_new.out" >/dev/null; then
  say "OLD vs NEW: IDENTICAL ($(wc -c < "$B/_x12_old.out") bytes, md5 $(md5sum < "$B/_x12_old.out" | cut -d' ' -f1))"
else
  say "OLD vs NEW: DIFFER -- the fix is NOT equivalence-preserving"
  diff -u "$B/_x12_old.out" "$B/_x12_new.out" | head -40 >> "$L"
fi
if diff -q "$B/_x12_new.out" "$B/_x12_dl.out" >/dev/null; then
  say "NEW-glob vs NEW-DUMP_LIST: IDENTICAL"
else
  say "NEW-glob vs NEW-DUMP_LIST: DIFFER"
  diff -u "$B/_x12_new.out" "$B/_x12_dl.out" | head -20 >> "$L"
fi
rm -rf "$D"
say "x12 equivalence done"
