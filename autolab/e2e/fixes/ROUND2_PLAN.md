# Round 2 — the exact steps, in order, with the check that gates each one

Run these only once `sweep1.out` says `sweep finished`. Nothing here may run
while a sweep is reading the files it edits: `autolab_dse.rb` and
`targets/core.rb` are read at boot by EVERY endpoint's own process, so
editing them mid-sweep makes the corpus inhomogeneous. That mistake was made
twice in the fix trial and cost two restarts; the trial now lives on patched
COPIES for exactly this reason.

```bash
cd /home/dev/project/reports/autolab/e2e

# 1. freeze the inventory
/home/dev/project/venvs/queries_from_runs/bin/python3 tools/build_inventory.py . ./INVENTORY
mkdir -p _round1 && cp -a manifest.jsonl runs logs results INVENTORY*.json INVENTORY.csv _round1/

# 2. baseline the target library BEFORE touching it   (expect: ALL SUITES PASSED, 75/75)
/home/dev/project/reports/autolab/test/run_tests.sh 2>&1 | tail -5

# 3. apply the repairs
python3 fixes/apply_fixes_round1.py --apply        # FIX-1..FIX-7, FIX-9
python3 fixes/apply_fix11_memo_run_scope.py --apply # FIX-11 comments_index memo
python3 fixes/apply_fix12_asset_helpers.py --apply  # FIX-12 rig asset stubs
python3 fixes/apply_fix10_config_limits.py --apply  # FIX-10 config.json limits
python3 fixes/apply_pipeline_round2.py --apply      # P-1..P-4
python3 fixes/apply_fix8_scaffold_params.py --apply # FIX-8 scaffold param scan

# All 14 edits were dry-run together on scratch copies and every resulting
# Ruby file passed `jruby -c`; the anchors do not collide.

# 4. syntax-check both Ruby files the sweep will load
JAVA_HOME=/home/dev/tools/jdk-21.0.5 PATH=/home/dev/tools/jdk-21.0.5/bin:$PATH \
  /home/dev/tools/jruby-9.3.0.0/bin/jruby -c \
  /home/dev/project/reports/autolab/entrypoints/lib/autolab_dse.rb
JAVA_HOME=/home/dev/tools/jdk-21.0.5 PATH=/home/dev/tools/jdk-21.0.5/bin:$PATH \
  /home/dev/tools/jruby-9.3.0.0/bin/jruby -c \
  /home/dev/project/reports/autolab/targets/core.rb

# 5. re-run the target library's own suite   (must still be 75/75; core.rb changed)
/home/dev/project/reports/autolab/test/run_tests.sh 2>&1 | tail -5

# 6. regenerate the scaffolds so FIX-8's widened param scan reaches them,
#    then diff. ORDER MATTERS: `scaffold.py` used to hardcode MAX_RUNS=6 /
#    TIME_BUDGET=600, so regenerating AFTER FIX-10 would have put the stale
#    numbers straight back. FIX-10 now patches the generator as well, so the
#    order is safe either way — but run `apply_fix10_config_limits.py --apply`
#    again after any regeneration and confirm it reports 0 changed.
#    Verify: links_resolve gains :q; diaspora_federation_receive_public and
#    _private gain :xml (and :guid); no other endpoint's input set moves.

# 7. a 6-endpoint verification trial BEFORE committing 2.5 h to a full sweep.
#    It must cover the fixes no trial has yet exercised live:
#      sessions_new       FIX-2  (devise_mapping.to -> ::User)
#      likes_index        FIX-5  (handler RAISED vs no handler)
#      comments_index     FIX-5/6 + the gold path is unchanged
#      admin_pods_index   FIX-9  (SymbolicList#each wall)
#      links_resolve      FIX-8  (the :q param)
#      contacts_index     breadth
rm -rf runs logs results manifest.jsonl && mkdir -p runs logs results
/home/dev/project/venvs/queries_from_runs/bin/python3 tools/sweep.py --par 3 \
  --max-runs 24 --time-budget 300 --run-timeout 900 \
  --only sessions_new likes_index comments_index admin_pods_index links_resolve contacts_index

# 8. the full re-sweep, only if step 7 is clean.
#    NO --max-runs / --time-budget: sweep.py now takes them from each
#    endpoint's own config.json (FIX-10), which is the document the review
#    gates quote. Passing them would set `limits_overridden` on every row.
/home/dev/project/venvs/queries_from_runs/bin/python3 tools/sweep.py --par 3 \
  --run-timeout 900 > sweep2.out 2>&1 &

# 9. the dry run
cd /home/dev/project/src_new && /home/dev/project/venvs/queries_from_runs/bin/python3 \
  -m sweep.testbed --spec /home/dev/project/reports/autolab/e2e/dryrun/sweep_spec.json \
  --out /home/dev/project/reports/autolab/e2e/dryrun/out --allow-shared-machine \
  $(for e in admin_pods_index contacts_index notifications_index conversations_index photos_index streams_activity; do \
      echo --corpus $e=/home/dev/project/reports/autolab/e2e/runs/$e; done)
```

## Rollback

Every patch script copies the file it edits to `<file>.bak_e2e_round1` (or
`.bak_e2e_fix8` / `.bak_round1`) before writing. The pre-e2e driver is also at
`entrypoints/lib/autolab_dse.rb.bak_pre_e2e`.
