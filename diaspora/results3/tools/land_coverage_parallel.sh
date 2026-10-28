#!/bin/bash
# Land the step-6 parallelisation into src/concolic_engine/coverage.py.
#
# REFUSES to run while a coverage pass is live: the engine source hash is a
# coverage-checkpoint key, and a pass that reloaded mid-flight would be keyed
# on one engine and resumed under another. `assumption_checker.py` is NOT a
# blocker (it does not execute coverage.py's step 6) and is deliberately not
# matched here -- it is frozen at md5 5ae1b13c and this script never touches it.
set -euo pipefail
SRC=/home/dev/project/src/concolic_engine/coverage.py
NEW="$1"
BK=/home/dev/project/reports/diaspora/results3/_bak_c7par_20260914
STAMP=$(date +%Y%m%d_%H%M%S)

echo "== gate: any live coverage pass? =="
if pgrep -af "results3/.*coverage_report\.py" | grep -v shell-snapshots | grep -q .; then
  echo "REFUSING: a coverage pass is running:"
  pgrep -af "results3/.*coverage_report\.py" | grep -v shell-snapshots
  exit 3
fi
echo "  none running - gate open"

echo "== pre-flight =="
python3 -c "import ast,sys; ast.parse(open('$NEW').read()); print('  new file parses OK')"
grep -q "_par_enumerate" "$NEW" || { echo "REFUSING: $NEW is not the patched engine"; exit 4; }
CUR=$(md5sum "$SRC" | cut -d' ' -f1)
ORIG=$(md5sum "$BK/coverage.py.orig" | cut -d' ' -f1)
[ "$CUR" = "$ORIG" ] || { echo "REFUSING: src/ coverage.py ($CUR) is not the file that was backed up ($ORIG)"; exit 5; }
echo "  src/ coverage.py matches the dated backup: $CUR"

echo "== assumption_checker must be untouched =="
md5sum /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py

echo "== backup + install =="
cp -p "$SRC" "$BK/coverage.py.pre_par_$STAMP"
echo "  backup: $BK/coverage.py.pre_par_$STAMP"
cp "$NEW" "$SRC"
chmod 644 "$SRC"
echo "  installed: $(md5sum "$SRC" | cut -d' ' -f1)"

echo "== post-flight: import + serial default =="
python3 - <<'EOF'
import sys
sys.path.insert(0, "/home/dev/project/src")
from concolic_engine import coverage
print("  import OK;", coverage.__file__)
print("  _par_width(None, 100)   =", coverage._par_width(None, 100), "(must be 1: opt-in)")
print("  _par_width('1', 100)    =", coverage._par_width("1", 100), "(must be 1)")
print("  _par_width('4', 100)    =", coverage._par_width("4", 100))
print("  _par_width('auto', 100) =", coverage._par_width("auto", 100))
print("  _par_width('auto', 3)   =", coverage._par_width("auto", 3), "(capped by job count)")
EOF
echo "LANDED."
