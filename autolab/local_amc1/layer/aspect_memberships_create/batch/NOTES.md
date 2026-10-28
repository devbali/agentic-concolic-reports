# NOTES (aspect_memberships_create batch-1)
- config digest: 3c17dcb967e9806a2f14e2f21f1c83e9a76a05ab8994992571cbb85dd48e7ecf
- runner: /home/dev/project/reports/autolab/entrypoints/scaffold/aspect_memberships_create/run_dse.rb
- launcher: /home/dev/project/reports/autolab/entrypoints/scaffold/aspect_memberships_create/launch.sh
- targets registry: /home/dev/project/reports/autolab/targets/registry.json ; shims: targets/shared_shims.rb
- scenarios MAX_RUNS=1500 TIME_BUDGET=3000
- assumption_cmd: venv python3 src_new/concolic/gate/assumption_checker.py {cfg} --declared {declared} --json-out {out}
- completion.batch_dir (audits): /home/dev/project/reports/autolab/local_amc1/layer/aspect_memberships_create/batch
- inputs: aspect_id "5", person_id "7", principal 1
## progress (checkpoint)
- run1: 1500 runs / 403 dumps, run_errors {}, terminals InvalidLocale 112 / AssociationTypeMismatch 151, worklist not empty. Copied to batch/ top level.
- shim extractor: crashes under the default US-ASCII locale (invalid byte sequence in core.rb); with LANG=C.UTF-8 it gives 22 keys. shim_tests.rb carried from local_tags1 (sha 25015e76...), header only changed; run here: 10 PASS 12 PROTOCOL 0 FAIL.
- coverage baseline: tree_complete True, missing 88 truncated.
- non-principal language arms (find_by_1_user / find_by_1_person_owner / assoc_person_owner): 582 sibling pairs, 0 trace differences -> 6 UntrackedPathAssumption -> missing 14, not truncated.
- principal language en vs pl: 169/169 pairs DIFFER -> not declared.
- run2: 14 missing leaves seeded (SEEDS_ONLY, suffix _cov2)
