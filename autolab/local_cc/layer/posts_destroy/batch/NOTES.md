# posts_destroy NOTES
- config digest: 048e7aa0fb59e91aef9d4aa912c7873b80f3cc088719a2d8e37ea7450060e982
- runner: /home/dev/project/reports/autolab/entrypoints/scaffold/posts_destroy/run_dse.rb
- targets registry: /home/dev/project/reports/autolab/targets/registry.json; shims: shared_shims.rb
- scenarios: MAX_RUNS 24 TIME_BUDGET 300 ; wall 5400s
- prev: 14 inherited dumps, 8 missing branches, tree_missing: first_3_not_found==True taken; devise_user person_id == post author_id taken
- run1 started ~22:55 MAX_RUNS=250 TIME_BUDGET=2400 LABEL_SUFFIX=r1 log batch/run1.log
- plain python3 lacks z3 here; use /home/dev/project/venvs/queries_from_runs/bin/python with PYTHONPATH=src_new for coverage
- shim_tests: subagent drafting in batch/shim_work/ (keys from extractor w/ LC_ALL=C.UTF-8; obj.* protocol keys auto PROTOCOL)
- assumptions.json plan: [] (driver does no pruning)
- manifest: batch_dir in/packet/dumps; runner /home/dev/project/scripts/diaspora-concolic <run_dse.rb>; workdir diaspora app
- 22:59 run1 done: 130 runs, 29 dumps, worklist empty true, 105s; measured missing_branches 0 tree_complete true tree_missing []
## attempt 2 (box batch-2, started 23:04)
- run2 launched MAX_RUNS=250 TIME_BUDGET=2400 DUMP_OUT=out/packet/dumps, log batch/run2.log (script batch/run2.sh)
- shim_tests delegated to sub-agent -> batch/shim_work/shim_tests.rb
- checker run_probe: runner split on spaces, cwd=workdir, env SEEDS_ONLY/EXTRA_SEEDS_JSON/LABEL_SUFFIX; dumps found in batch_dir, runner dirname, workdir
- 23:1x run2 done: 130 runs, 29 dumps, worklist empty true, 9.8s; coverage missing 0 tree_complete true tree_missing []
- manifest runner verified: SEEDS_ONLY replay of dse0029 seeds -> 1 dump, 1 run, 1.1s after boot
- packet built 34 files; writing marker
