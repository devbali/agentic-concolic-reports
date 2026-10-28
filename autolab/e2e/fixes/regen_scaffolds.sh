#!/usr/bin/env bash
# regen_scaffolds.sh — step 6: re-run introspection -> manifest -> scaffold so
# FIX-8's widened param scan reaches the generated runners, then SHOW THE DIFF.
#
# The whole scaffold tree is backed up first and the diff is printed rather
# than assumed, because this rewrites all 161 run_dse.rb files and a bad
# regeneration would break every endpoint at once. Restore with:
#     rm -rf .../entrypoints/scaffold && mv .../entrypoints/scaffold.bak_e2e .../entrypoints/scaffold
set -euo pipefail
EP=/home/dev/project/reports/autolab/entrypoints
export JAVA_HOME=/home/dev/tools/jdk-21.0.5
export PATH="$JAVA_HOME/bin:/home/dev/tools/jruby-9.3.0.0/bin:$PATH"
export GEM_HOME=/home/dev/.gem/jruby/2.6.0
export RAILS_ENV=concolic_mod
PY=/home/dev/project/venvs/queries_from_runs/bin/python3

echo "== backing up the scaffold tree and the manifest =="
rm -rf "$EP/scaffold.bak_e2e" "$EP/manifest.json.bak_e2e"
cp -a "$EP/scaffold" "$EP/scaffold.bak_e2e"
cp -a "$EP/manifest.json" "$EP/manifest.json.bak_e2e"

echo "== 1/3 introspect (boots the app; ~3 min) =="
cd /home/dev/project/ruby_examples/dse-apps/apps/diaspora
# The JSON goes to a FILE named by ARGV[0], not to stdout -- an app
# initializer prints to stdout, so stdout is not usable (the script's own
# header, lines 10-16). Written to a temp file and moved only on success, so
# a failed run cannot leave a truncated raw_introspection.json behind.
bundle exec jruby -I. "$EP/tools/introspect_entrypoints.rb" \
    "$EP/raw_introspection.json.new" > /home/dev/project/reports/autolab/e2e/fixes/introspect.out 2>&1
test -s "$EP/raw_introspection.json.new"
mv "$EP/raw_introspection.json.new" "$EP/raw_introspection.json"

echo "== 2/3 build manifest =="
cd "$EP" && $PY tools/build_manifest.py

echo "== 3/3 scaffold =="
$PY tools/scaffold.py

echo "== re-apply the run limits (scaffold.py regenerates config.json) =="
python3 /home/dev/project/reports/autolab/e2e/fixes/apply_fix10_config_limits.py --apply

echo "== DIFF: which endpoints' symbolic inputs changed =="
$PY - <<'PYEOF'
import json, os
EP = "/home/dev/project/reports/autolab/entrypoints"
def inputs(root, eid):
    p = os.path.join(root, eid, "config.json")
    if not os.path.isfile(p):
        return None
    return sorted(i["name"] for i in (json.load(open(p)).get("inputs") or []))
old_root, new_root = EP + "/scaffold.bak_e2e", EP + "/scaffold"
ids = sorted(d for d in os.listdir(new_root) if os.path.isdir(os.path.join(new_root, d)))
moved = gone = 0
for eid in ids:
    a, b = inputs(old_root, eid), inputs(new_root, eid)
    if a == b:
        continue
    moved += 1
    added = [x for x in (b or []) if x not in (a or [])]
    removed = [x for x in (a or []) if x not in (b or [])]
    print(f"  {eid:44s} +{added} -{removed}")
    if removed:
        gone += 1
print(f"\n{moved} endpoints changed inputs; {gone} of them LOST an input "
      f"(a loss is a regression — investigate before sweeping)")
missing = [e for e in os.listdir(old_root)
           if os.path.isdir(os.path.join(old_root, e)) and e not in ids]
print(f"endpoints present before and absent now: {missing}")
PYEOF
