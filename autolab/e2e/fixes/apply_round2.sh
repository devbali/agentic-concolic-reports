#!/usr/bin/env bash
# apply_round2.sh — steps 1-6 of ROUND2_PLAN.md, in order, aborting on the
# first failure. Run ONLY when sweep1.out says "sweep finished": every file
# touched here is read at boot by every endpoint's own process.
set -euo pipefail
cd /home/dev/project/reports/autolab/e2e
PY=/home/dev/project/venvs/queries_from_runs/bin/python3
JR=/home/dev/tools/jruby-9.3.0.0/bin/jruby
export JAVA_HOME=/home/dev/tools/jdk-21.0.5
export PATH="$JAVA_HOME/bin:/home/dev/tools/jruby-9.3.0.0/bin:$PATH"
export GEM_HOME=/home/dev/.gem/jruby/2.6.0

grep -q "sweep finished" sweep1.out || { echo "REFUSING: sweep1 has not finished"; exit 1; }

echo "== 1. freeze the round-1 inventory =="
$PY tools/build_inventory.py . ./INVENTORY
mkdir -p _round1
cp -a manifest.jsonl runs logs results INVENTORY.json INVENTORY_RANKED.json INVENTORY.csv _round1/
echo "   archived to _round1/"

echo "== 2. baseline the target library BEFORE touching it =="
/home/dev/project/reports/autolab/test/run_tests.sh > fixes/tests_before.out 2>&1 || true
tail -3 fixes/tests_before.out
grep -q "ALL SUITES PASSED" fixes/tests_before.out || { echo "REFUSING: baseline suite not green"; exit 1; }

echo "== 3. apply the repairs =="
python3 fixes/apply_fixes_round1.py --apply
python3 fixes/apply_fix11_memo_run_scope.py --apply
python3 fixes/apply_fix12_asset_helpers.py --apply
python3 fixes/apply_fix8_scaffold_params.py --apply
python3 fixes/apply_fix10_config_limits.py --apply
python3 fixes/apply_pipeline_round2.py --apply

echo "== 4. syntax-check every Ruby file a sweep loads =="
for f in /home/dev/project/reports/autolab/entrypoints/lib/autolab_dse.rb \
         /home/dev/project/reports/autolab/targets/core.rb \
         /home/dev/project/reports/autolab/targets/endpoints/comments_index.rb \
         /home/dev/project/reports/autolab/entrypoints/tools/introspect_entrypoints.rb; do
  echo -n "   $(basename "$f"): "; "$JR" -c "$f"
done
$PY -c "import ast;[ast.parse(open(p).read()) for p in ['tools/pipeline.py','tools/sweep.py','/home/dev/project/reports/autolab/entrypoints/tools/build_manifest.py','/home/dev/project/reports/autolab/entrypoints/tools/scaffold.py']];print('   python: ok')"

echo "== 4b. regenerate the library's own inventory (my core.rb edits move line numbers) =="
# `inventory/citations.json` resolves each citation from a PATTERN to a LINE,
# and `inventory/manifest.json` records each declaration's line. None of the 14
# core.rb citation PATTERNS matches text these fixes change (checked: the
# patterns are for `dev_stub`-unrelated declarations), but three insertions at
# roughly lines 120, 1395 and 1998 shift every line after them, so the resolved
# numbers move. `test/test_inventory.py:261-264` regenerates each file and fails
# if regenerating CHANGED it — so without this the suite would fail once,
# rewrite the files as a side effect, and pass on a second run. Doing it here
# makes it explicit instead of a self-healing test.
cd /home/dev/project/reports/autolab
for t in build_inventory.py build_partition.py build_conflicts.py check_citations.py; do
  echo -n "   $t: "
  /home/dev/project/venvs/queries_from_runs/bin/python3 "tools/$t" > /dev/null 2>&1 \
    && echo ok || { echo "FAILED"; exit 1; }
done
cd /home/dev/project/reports/autolab/e2e
git -C /home/dev/project/reports 2>/dev/null diff --stat -- autolab/inventory 2>/dev/null || true

echo "== 5. re-run the target library's suite (core.rb and one endpoint layer changed) =="
/home/dev/project/reports/autolab/test/run_tests.sh > fixes/tests_after.out 2>&1 || true
tail -3 fixes/tests_after.out
grep -q "ALL SUITES PASSED" fixes/tests_after.out || { echo "STOP: the suite regressed — see fixes/tests_after.out"; exit 1; }

echo "== done: repairs applied, both suites green =="
echo "   next: regenerate the scaffolds (FIX-8), then the 6-endpoint verification trial"
