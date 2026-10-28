#!/usr/bin/env bash
# Run the three completion checks against a corpus directory, scoped.
#
#   usage: _p47_checks.sh <corpus-dir> [tag]
#
# The three are the ones that were RED on the shipped corpus, and they are the
# cheap way to tell whether the regenerated corpus actually fixed what phase
# (a) intended BEFORE paying for a full coverage+gate pass (~a day):
#
#   mock_note_check              every real statement has a matching corpus note
#   note_fidelity_audit          each note is faithful in projection/pred/LIMIT/ORDER
#   empty_relation_emission      no note reads a row of a list that is empty
#
# SCOPING. mock_note_check and empty_relation_emission honour `--dump-list` /
# `$DUMP_LIST`. note_fidelity_audit does NOT -- it globs `<batch>/dump_*.json`
# unconditionally (note_fidelity_audit.py:128) -- so it is handed the corpus
# directory itself, which is why a SYMLINK SAMPLE directory (_p47_sample.py) is
# the right thing to point this at while iterating.
#
# Run it on a sample to iterate; run it on the whole corpus for the verdict you
# intend to ship. A 20k stratified sample of the old corpus reproduced its
# full-corpus numbers exactly.
set -uo pipefail
D="${1:?usage: _p47_checks.sh <corpus-dir> [tag]}"
TAG="${2:-$(basename "$D")}"
B=/home/dev/project/reports/diaspora/results3/posts_show
PY=/home/dev/project/venvs/queries_from_runs/bin/python
cd /home/dev/project

L="$D/_dumps.txt"
[ -f "$L" ] || find "$D" -maxdepth 1 -name 'dump_*.json' > "$L"
N=$(wc -l < "$L")
RUN="$D/concrete_run.json"; [ -f "$RUN" ] || RUN="$B/concrete_run.json"
AL="$D/concrete_aliases.json"; [ -f "$AL" ] || AL="$B/concrete_aliases.json"
echo "== _p47_checks [$TAG]: $N dumps in $D =="

echo "--- mock_note_check ---"
PYTHONPATH=/home/dev/project/src DUMP_LIST="$L" "$PY" \
  /home/dev/project/src/end_to_end_completion_checker/mock/mock_note_check.py \
  "$RUN" "$D" --aliases "$AL" --dump-list "$L" > "$D/_chk_note_check.txt" 2>&1
echo "exit=$?"; grep -E "^RESULT|NOTE-MISMATCH|NOTE-MISSING|OUTSIDE any target" "$D/_chk_note_check.txt" | head -15

echo "--- note_fidelity ---"
PYTHONPATH=/home/dev/project/src "$PY" \
  /home/dev/project/reports/diaspora/tools/note_fidelity_audit.py \
  "$D" "$RUN" --aliases "$AL" > "$D/_chk_note_fidelity.txt" 2>&1
echo "exit=$?"; grep -E "^RESULT|^-- " "$D/_chk_note_fidelity.txt" | head -15

echo "--- empty_relation_emission ---"
PYTHONPATH=/home/dev/project/src python3 \
  /home/dev/project/src/queries_from_runs/audits/empty_relation_emission_audit.py \
  "$D" --dump-list "$L" > "$D/_chk_empty_rel.txt" 2>&1
echo "exit=$?"; grep -E "^RESULT|^-- " "$D/_chk_empty_rel.txt" | head -8

echo
echo "== summary [$TAG] =="
for f in _chk_note_check _chk_note_fidelity _chk_empty_rel; do
  printf "  %-22s %s\n" "${f#_chk_}" "$(grep -E '^RESULT' "$D/$f.txt" | head -1)"
done
